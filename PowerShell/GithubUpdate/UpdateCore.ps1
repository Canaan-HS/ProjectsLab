param (
    [Parameter(Position = 0)]
    [Alias("u")]
    [string]$url = "",

    [Alias("o")]
    [string]$owner = "",

    [Alias("r")]
    [string]$repo = "",

    [Alias("i")]
    [switch]$install = $null,

    [Alias("un")]
    [string]$uninstall = $null,

    [Alias("l")]
    [switch]$list = $null,

    [Alias("c")]
    [switch]$check = $null,

    [Alias("al")]
    [switch]$all = $null,

    [Alias("a")]
    [string]$asset_name = $null,

    [Alias("e")]
    [string]$exclude_patterns = $null,

    [Alias("ae")]
    [switch]$auto_extract = $null,

    [Alias("ae2")]
    [switch]$auto_extract2 = $null,

    [Alias("ni")]
    [switch]$no_idm = $null,

    [Alias("h")]
    [switch]$help
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function ShowHelp {
    Write-Host @"

GitHub 資產更新工具

使用:
  gau.exe <GitHub 網址> [選項]
  gau.exe -o <owner> -r <repo> [選項]
  gau.exe -i <GitHub 網址 | owner/repo> [選項]
  gau.exe -i -o <owner> -r <repo> [選項]
  gau.exe -un <owner/repo>
  gau.exe -l | -check | -all

選項:
  -u, -url <url>                 GitHub 儲存庫網址
  -o, -owner <name>              GitHub 儲存庫擁有者
  -r, -repo <name>               GitHub 儲存庫名稱
  -a, -asset_name <name>         資產檔名關鍵字
  -e, -exclude_patterns <list>   排除關鍵字（逗號分隔）
  -ae, -auto_extract             下載後自動解壓縮
  -ae2, -auto_extract2           解壓後攤平單一頂層資料夾
  -ni, -no_idm                   停用 IDM 偵測，強制使用內建下載器
  -i, -install                   統一管理線：下載並納入紀錄（無紀錄時直接下載最新）
  -un, -uninstall <owner/repo>   解除紀錄綁定（不刪除已下載的檔案）
  -l, -list                      顯示紀錄列表（含路徑存活檢查）
  -c, -check                     批量檢查所有紀錄的更新（不下載、唯讀）
  -al, -all                      批量更新所有紀錄（檢查 + 下載）
  -h, -help                      顯示本說明

範例:
  gau https://github.com/owner/repo
  gau -o user -r app
  gau -o user -r app -a "software_x64_portable.exe"
  gau -o user -r app -e "debug,source"
  gau -i astral-sh/uv -ae2
  gau -i -o astral-sh -r uv -a "x64" -ae
  gau -un astral-sh/uv
  gau -l
  gau -check
  gau -all

備註:
  偵測到 gh CLI 登入或設定 GITHUB_TOKEN 環境變數時，API 自動帶授權（限額 60 → 5000/hr）

"@ -ForegroundColor Green
    exit 0
}

if ($MyInvocation.MyCommand.CommandType -ne "ExternalScript") {
    $exePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $sha256 = [System.Security.Cryptography.SHA256]::Create()

    try {
        $bytes = [System.IO.File]::ReadAllBytes($exePath)
        $hash = $sha256.ComputeHash($bytes)
        $hashString = [System.BitConverter]::ToString($hash).Replace('-', '')

        Write-Host "Hash: $($hashString.Substring(0, 32))`n" -ForegroundColor Cyan
    }
    finally {
        $sha256.Dispose()
    }
}

# 解析 -i / -un 的倉庫字串：完整 GitHub 網址或 owner/repo 簡寫
# 回傳 @(owner, repo)；無法解析回傳空陣列
function ParseRepoArg {
    param([string]$arg)

    if ($arg -match '(?i)^https://github\.com/([^/]+)/([^/]+)') {
        return @($matches[1], $matches[2])
    }
    if ($arg -match '^[^/\s]+/[^/\s]+$') {
        $parts = $arg -split '/'
        return @($parts[0], $parts[1])
    }
    return @()
}

if ($help -or $PSBoundParameters.Count -eq 0) { ShowHelp }

# 模式判定（同時出現時取先者；優先序: uninstall > install > list > check > all > 單發）
$mode = 'single'
if ($all) { $mode = 'all' }
if ($check) { $mode = 'check' }
if ($list) { $mode = 'list' }
if ($install) { $mode = 'install' }
if ($uninstall) { $mode = 'uninstall' }

if ($url -match '(?i)^https://github\.com/([^/]+)/([^/]+)') {
    $owner = $matches[1]
    $repo = $matches[2]
}
elseif ($install -and $url) {
    # -i 額外支援 owner/repo 簡寫（單發線維持原本只吃完整網址）
    $parsed = ParseRepoArg -arg $url
    if ($parsed) {
        $owner = $parsed[0]
        $repo = $parsed[1]
    }
}

if (-not $owner -or -not $repo) {
    if ($mode -eq 'install') {
        Write-Host "gau -i 需要 GitHub 網址、owner/repo 簡寫，或 -o/-r 參數。" -ForegroundColor Red
        Write-Host "範例: gau -i astral-sh/uv" -ForegroundColor Yellow
        Write-Host "      gau -i https://github.com/astral-sh/uv" -ForegroundColor Yellow
        Write-Host "      gau -i -o astral-sh -r uv" -ForegroundColor Yellow
        exit 1
    }
    if ($mode -eq 'single') {
        Write-Host "參數 -owner 和 -repo 是必需的" -ForegroundColor Red
        ShowHelp
    }
    # uninstall / list / check / all 不需要倉庫參數
}

# ===== 核心程式 =====

$versionRecordTemplate = "! Version - $repo - {0}"
$prefix = $versionRecordTemplate -replace '\{0\}', ''
$userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/155.0.0.0 Safari/537.36"

# 統一紀錄檔（管理線 -i 專用；單發線不碰）
$recordsPath = Join-Path $env:USERPROFILE '.gau\records.json'

# GitHub API token（提高限額 60 → 5000/hr）：環境變數優先，其次 gh CLI 登入憑證
$githubToken = $env:GITHUB_TOKEN
if (-not $githubToken) {
    $ghCmd = Get-Command gh -ErrorAction SilentlyContinue
    if ($ghCmd) {
        try { $githubToken = "$(& $ghCmd.Source auth token 2>$null)".Trim() } catch { $githubToken = $null }
        if (-not $githubToken) { $githubToken = $null }
    }
}

# IDM 偵測
function GetIdmPath {
    # 1) IDM 自己寫入的 registry
    $v = (Get-ItemProperty 'HKCU:\Software\DownloadManager' -ErrorAction SilentlyContinue).ExePath
    if ($v -and (Test-Path $v)) { return $v }

    # 2) 預設安裝路徑
    foreach ($p in @(
            "${env:ProgramFiles(x86)}\Internet Download Manager\IDMan.exe",
            "$env:ProgramFiles\Internet Download Manager\IDMan.exe"
        )) {
        if ($p -and (Test-Path $p)) { return $p }
    }

    return $null
}

$idmExe = GetIdmPath

# ctx: 本次操作的共享狀態（臨時乾淨列表）
# 所有函數統一跟它拿參數、把結果寫回，不做函數間參數傳遞；一律同步操作
# 單發線從參數建立；之後管理線會從紀錄逐筆重建
# 注意: 函數內只准 $ctx.x = ... 屬性賦值，禁止 $ctx = ... 整體重綁（動態作用域會造出區域變數）
$ctx = @{
    owner                 = $owner
    repo                  = $repo
    dir                   = (Get-Location).Path
    asset_name            = $asset_name
    exclude_patterns      = $exclude_patterns
    auto_extract          = [bool]$auto_extract
    auto_extract2         = [bool]$auto_extract2
    no_idm                = [bool]$no_idm
    currentVersion        = ""
    # 行為開關
    DownloadOnFirstRecord = $false   # -i 無紀錄時直接下載最新；單發線只記版本不下載
    # 結果欄位（ToolUpdate 寫回）
    Status                = ""
    NewVersion            = ""
    Failed                = @()
}

# 取得版本文件（單發線：標記檔）
$versionFile = Get-ChildItem -LiteralPath $ctx.dir -File -Filter "$prefix*" |
Sort-Object Name -Descending |
Select-Object -First 1

function GetVersion {
    if (-not $versionFile) { return "" }
    return $versionFile.Name.Substring($prefix.Length)
}

function SetVersion {
    param([string]$version)

    $newName = $versionRecordTemplate -f $version

    if ($versionFile) {
        Rename-Item -LiteralPath $versionFile.FullName -NewName $newName -Force
        Write-Host "版本紀錄修改: $version"
    }
    else {
        # New-Item 沒有 -LiteralPath，改用 .NET 直接建空檔（路徑含 [ ] 也安全）
        [System.IO.File]::WriteAllText((Join-Path $ctx.dir $newName), "")
        Write-Host "創建版本紀錄: $version"
    }
}

function ParseVersion {
    param([string]$version)

    if ([string]::IsNullOrWhiteSpace($version)) { return $null }

    # 抽取數字版本
    if ($version -match '\d+(\.\d+){1,3}') {
        $version = $matches[0]
    }

    $parsed = $null
    if ([version]::TryParse($version, [ref]$parsed)) {
        return $parsed
    }

    return $null
}

# ===== 統一紀錄（管理線）=====
# 檔案結構: { "owner/repo": { dir, version, ...參數 } }
# 欄位鏡像 CLI 參數名；沒給的參數不寫入（缺席 = 沒給），讀回時缺 key 為 $null（falsy）
# key 比對不分大小寫，以最新一次輸入的大小寫改寫

function RecordsLoad {
    if (-not (Test-Path -LiteralPath $recordsPath)) { return [ordered]@{} }

    try {
        $obj = Get-Content -LiteralPath $recordsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Write-Host "紀錄檔解析失敗: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }

    $loaded = [ordered]@{}
    if ($obj) {
        foreach ($p in $obj.PSObject.Properties) {
            $rec = [ordered]@{}
            foreach ($q in $p.Value.PSObject.Properties) { $rec[$q.Name] = $q.Value }
            $loaded[$p.Name] = $rec
        }
    }
    return $loaded
}

function RecordsSave {
    try {
        $parent = [System.IO.Path]::GetDirectoryName($recordsPath)
        if (-not (Test-Path -LiteralPath $parent)) {
            [System.IO.Directory]::CreateDirectory($parent) | Out-Null
        }

        $json = $records | ConvertTo-Json -Depth 5 | Out-String
        [System.IO.File]::WriteAllText($recordsPath, $json, [System.Text.UTF8Encoding]::new($false))
    }
    catch {
        Write-Host "紀錄檔寫入失敗: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# 整筆重寫該 key 的紀錄（從 $ctx 序列化；不做逐欄合併，缺席欄位自然消失）
function RecordUpsert {
    $key = "$($ctx.owner)/$($ctx.repo)"

    # 以本次輸入的大小寫改寫 key（比對不分大小寫；大小寫相同時原位覆蓋，保持檔案順序穩定）
    $oldKey = @($records.Keys) | Where-Object { $_ -ieq $key } | Select-Object -First 1
    if ($oldKey -and $oldKey -cne $key) { $records.Remove($oldKey) }

    # [ordered] 保證欄位順序固定（雜湊表的列舉順序隨行程改變，會讓檔案位元組不穩定）
    $rec = [ordered]@{}
    $rec['dir'] = $ctx.dir
    $rec['version'] = $ctx.NewVersion
    if ($ctx.asset_name) { $rec['asset_name'] = $ctx.asset_name }
    if ($ctx.exclude_patterns) { $rec['exclude_patterns'] = $ctx.exclude_patterns }
    if ($ctx.auto_extract) { $rec['auto_extract'] = $true }
    if ($ctx.auto_extract2) { $rec['auto_extract2'] = $true }
    if ($ctx.no_idm) { $rec['no_idm'] = $true }

    $records[$key] = $rec
    RecordsSave
}

function RecordRemove {
    param([string]$key)

    $oldKey = @($records.Keys) | Where-Object { $_ -ieq $key } | Select-Object -First 1
    if (-not $oldKey) { return $false }

    $records.Remove($oldKey)
    RecordsSave
    return $true
}

# 紀錄 → ctx（批量線每筆重建；dir 與參數全部用紀錄裡的，缺席欄位讀出 $null = 沒給）
function CtxFromRecord {
    param([string]$key, $rec)

    $parts = $key -split '/'

    return @{
        owner            = $parts[0]
        repo             = $parts[1]
        dir              = "$($rec.dir)"
        asset_name       = $rec.asset_name
        exclude_patterns = $rec.exclude_patterns
        auto_extract     = [bool]$rec.auto_extract
        auto_extract2    = [bool]$rec.auto_extract2
        no_idm           = [bool]$rec.no_idm
        currentVersion   = "$($rec.version)"
        DownloadOnFirstRecord = $true
        CheckOnly        = $false
        Status           = ""
        NewVersion       = ""
        Failed           = @()
    }
}

# 顯示紀錄列表（-l）：每筆一行，路徑失效整行紅字
function ShowRecords {
    param($records)

    if ($records.Count -eq 0) {
        Write-Host "目前沒有任何紀錄。以 gau -i <owner/repo> 安裝的工具會出現在這裡。" -ForegroundColor Yellow
        return
    }

    foreach ($key in @($records.Keys)) {
        $rec = $records[$key]

        $params = @()
        if ($rec.asset_name) { $params += "a=$($rec.asset_name)" }
        if ($rec.exclude_patterns) { $params += "e=$($rec.exclude_patterns)" }
        if ($rec.auto_extract) { $params += "ae" }
        if ($rec.auto_extract2) { $params += "ae2" }
        if ($rec.no_idm) { $params += "ni" }
        $paramText = if ($params.Count -gt 0) { " [$($params -join ' ')]" } else { "" }

        $line = "{0}  v{1}  {2}{3}" -f $key, $rec.version, $rec.dir, $paramText
        if (Test-Path -LiteralPath "$($rec.dir)") {
            Write-Host $line
        }
        else {
            Write-Host $line -ForegroundColor Red
        }
    }
}

function GetDownloadInfo {
    param($assets)

    $notWindowsExecutable = "(?i)linux|ubuntu|dos|mac|ios|uos|macos|apple|android|ohos"
    $notExecutable = "(?i)sha256|checksum|checksums|hash|source|src|debug|symbols|pdb|test|tests|sh|json"
    $notX64Architecture = "(?i)win32|wow32|arm(?:64)?|aarch64|i[3-6]86|x86(?![-_]?64)|32[-_ ]?bit|mips(?:64)?|ppc(?:64)?|powerpc|sparc|riscv(?:64)?|s390x?"

    # 如果有指定排除檔案名特徵
    if ($ctx.exclude_patterns) {
        $excludeRegex = "(?i)" + (($ctx.exclude_patterns -split ',' | ForEach-Object {
                    [regex]::Escape($_.Trim())
                }) -join '|')
    }

    # 如果有指定下載特定檔案名稱，用包含匹配（忽略大小寫）
    if ($ctx.asset_name) {
        $matched = $assets | Where-Object {
            $_.name.Contains($ctx.asset_name) -and
            -not ($excludeRegex -and $_.name -match $excludeRegex) -and
            $_.name -notmatch $notExecutable -and
            $_.name -notmatch $notWindowsExecutable -and
            $_.name -notmatch $notX64Architecture
        }
        if ($matched -and $matched.name) { return $matched }
        Write-Host "未找到包含 '$($ctx.asset_name)' 的資產，使用自動檢測。" -ForegroundColor Yellow
    }

    # ! 塞選條件以我個人使用為主, 並非通用性
    # 自動查找常見 windows x64 資產（只取分數最高的一個）
    $windowsAsset = $assets |
    ForEach-Object {
        $name = $_.name

        # 排除檔案名稱匹配
        if ($excludeRegex -and $name -match $excludeRegex) { return }
        # 排除非目標
        if ($name -match $notExecutable) { return }
        # 排除非 windows 資產
        if ($name -match $notWindowsExecutable) { return }
        # 排除非 x64 架構
        if ($name -match $notX64Architecture) { return }

        $score = 0

        # 平台
        if ($name -match '(?i)win|windows') { $score += 100 }
        # 架構
        if ($name -match '(?i)x86[-_]?64|x64|win[-_]?x?64|64[-_ ]?bit') { $score += 60 }
        # 安裝類型
        if ($name -match '(?i)portable|standalone|noinstall') { $score += 40 }
        # 格式
        if ($name -match '(?i)zip|7z|rar') { $score += 30 } elseif ($name -match '(?i)exe|msi' ) { $score += 20 }

        [PSCustomObject]@{
            Asset = $_
            Score = $score
        }
    } |
    Sort-Object Score -Descending |
    Select-Object -First 1 -ExpandProperty Asset

    return $windowsAsset
}

# 攤平（-ae2）：將殼資料夾內容全部上移覆蓋到上層，最後刪除殼資料夾
# 失敗時停止、保留殼資料夾與現狀，僅回報（不影響下載結果）
function FlattenFolder {
    param([string]$folderPath)

    $parent = [System.IO.Path]::GetDirectoryName($folderPath)
    $name = [System.IO.Path]::GetFileName($folderPath)

    Write-Host "攤平資料夾: $name"

    try {
        foreach ($item in @(Get-ChildItem -LiteralPath $folderPath -Force)) {
            $target = Join-Path $parent $item.Name

            if (-not $item.PSIsContainer) {
                # 檔案 → 直接覆蓋
                Move-Item -LiteralPath $item.FullName -Destination $target -Force -ErrorAction Stop
            }
            elseif (Test-Path -LiteralPath $target) {
                # 同名資料夾已存在 → 合併覆蓋後刪來源
                Get-ChildItem -LiteralPath $item.FullName -Force | Copy-Item -Destination $target -Recurse -Force -ErrorAction Stop
                Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
            }
            else {
                Move-Item -LiteralPath $item.FullName -Destination $target -ErrorAction Stop
            }
        }

        Remove-Item -LiteralPath $folderPath -Force -ErrorAction Stop
        Write-Host "攤平完成: $name"
        return $true
    }
    catch {
        Write-Host "攤平失敗: $name（$($_.Exception.Message)）" -ForegroundColor Red
        return $false
    }
}

function AutoExtract {
    param([string]$filePath)

    # 可解壓的封存檔副檔名（最長後綴優先、忽略大小寫）
    $archiveExtensions = @(
        '.tar.gz', '.tar.xz', '.tar.bz2', '.tar.zst',
        '.tgz', '.txz', '.tbz2', '.tzst',
        '.zip', '.7z', '.rar', '.tar'
    )

    $name = [System.IO.Path]::GetFileName($filePath)
    $lowerName = $name.ToLowerInvariant()

    $extension = $archiveExtensions | Where-Object { $lowerName.EndsWith($_) } | Select-Object -First 1
    if (-not $extension) { return $true }

    Write-Host "解壓中: $name"

    $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
    $destination = [System.IO.Path]::GetDirectoryName($filePath)

    # -ae2: 解壓前快照頂層項目（此時壓縮檔已存在於清單中，diff 只取解壓新增項）
    $snapshotBefore = @()
    if ($ctx.auto_extract2) {
        $snapshotBefore = @(Get-ChildItem -LiteralPath $destination -Force | ForEach-Object { $_.Name })
    }

    try {
        # bsdtar 解壓時直接覆蓋同名檔案；檔案被鎖定等錯誤以 exit code 回報
        $output = & $tar -xf $filePath -C $destination 2>&1
        $exitCode = $LASTEXITCODE
    }
    catch {
        $output = @($_.Exception.Message)
        $exitCode = -1
    }

    if ($exitCode -ne 0) {
        Write-Host "解壓失敗: $name（壓縮檔已保留）" -ForegroundColor Red
        foreach ($line in $output) {
            $text = "$line".Trim()
            if ($text) { Write-Host "  $text" -ForegroundColor Red }
        }
        return $false
    }

    Write-Host "解壓完成: $name"

    # -ae2 攤平層：解壓新增項「恰好一個資料夾」才攤平，其他情況等同 -ae
    if ($ctx.auto_extract2) {
        $before = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($n in $snapshotBefore) { $null = $before.Add($n) }

        $newItems = @(Get-ChildItem -LiteralPath $destination -Force | Where-Object { -not $before.Contains($_.Name) })

        if ($newItems.Count -eq 1 -and $newItems[0].PSIsContainer) {
            FlattenFolder -folderPath $newItems[0].FullName | Out-Null
        }
        else {
            Write-Host "解壓結果非單一頂層資料夾，跳過攤平。" -ForegroundColor Yellow
        }
    }

    try {
        Remove-Item -LiteralPath $filePath -Force -ErrorAction Stop
        Write-Host "已移除壓縮檔: $name"
    }
    catch {
        Write-Host "無法移除壓縮檔: $name" -ForegroundColor Yellow
    }

    return $true
}

function InvokeIdmDownload {
    param($asset, [string]$filePath)

    # --- 基本資訊 ---
    $downloadUrl = $asset.browser_download_url
    $assetName = $asset.name
    $githubSize = [long]$asset.size
    $idmWasRunning = [bool](Get-Process IDMan -ErrorAction SilentlyContinue)

    # --- 啟動 IDM ---
    # /n 靜默下載；/q 只在 IDM 原本未執行時使用（完成後會退出）。
    # 路徑結尾反斜線會吃掉結尾引號，先加倍。
    $quotedCallPath = $ctx.dir -replace '(\\+)$', '$1$1'
    $idmArgs = "/n /d `"$downloadUrl`" /p `"$quotedCallPath`" /f `"$assetName`""
    if (-not $idmWasRunning) { $idmArgs += ' /q' }

    try {
        Start-Process -FilePath $idmExe -ArgumentList $idmArgs -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Host "呼叫 IDM 失敗: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }

    # --- IDM 進度彈窗 ---
    # 彈窗由既有的 IDMan 主進程建立（新的 IDMan.exe 只是啟動器），
    # 內含 msctls_progress32 與 Static 進度文字，約 200ms 更新一次。
    # 彈窗只用來顯示進度；使用者可能按「隱藏」或取消後重新下載，句柄會失效，需重新搜尋。
    if (-not ('GauIdmProgressWindow' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;

public static class GauIdmProgressWindow {
    private delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc cb, IntPtr p);
    [DllImport("user32.dll")] private static extern bool EnumChildWindows(IntPtr hWnd, EnumProc cb, IntPtr p);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassName(IntPtr hWnd, StringBuilder sb, int max);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);

    private static readonly Regex DownloadedRegex = new Regex(@"([0-9][0-9.,]*)\s*MB\s*\(\s*([0-9][0-9.,]*)\s*%", RegexOptions.IgnoreCase);
    private static readonly Regex SpeedRegex = new Regex(@"([0-9][0-9.,]*)\s*(MB|KB)\s*/\s*(?:s|sec|秒)", RegexOptions.IgnoreCase);

    private static string ClassOf(IntPtr hWnd) { StringBuilder sb = new StringBuilder(128); GetClassName(hWnd, sb, sb.Capacity); return sb.ToString(); }
    private static string TextOf(IntPtr hWnd) { StringBuilder sb = new StringBuilder(512); GetWindowText(hWnd, sb, sb.Capacity); return sb.ToString(); }

    private static bool IsPopup(IntPtr hWnd) {
        bool found = false;
        EnumChildWindows(hWnd, (child, p) => {
            string cls = ClassOf(child);
            found = cls == "msctls_progress32" || cls == "IDM DownloadProgressComponent class";
            return !found;
        }, IntPtr.Zero);
        return found;
    }

    // 標題為「檔名」或「xx% 檔名」等，檔名前必須是分隔字元，避免誤認其他檔案。
    private static bool TitleMatches(string title, string name) {
        title = title.Trim();
        if (!title.EndsWith(name, StringComparison.OrdinalIgnoreCase)) return false;
        int i = title.Length - name.Length;
        return i == 0 || " -(%".IndexOf(title[i - 1]) >= 0;
    }

    public static IntPtr Find(string assetName) {
        IntPtr found = IntPtr.Zero;
        EnumWindows((hWnd, p) => {
            if (ClassOf(hWnd) != "#32770" || !TitleMatches(TextOf(hWnd), assetName) || !IsPopup(hWnd)) return true;
            found = hWnd;
            return false;
        }, IntPtr.Zero);
        return found;
    }

    private static double Number(string s) {
        if (s.IndexOf(',') >= 0) s = s.IndexOf('.') >= 0 ? s.Replace(",", "") : s.Replace(',', '.');
        double v;
        return Double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out v) ? v : -1;
    }

    // 回傳 { 百分比(讀不到為 -1), 已下載 bytes, 速度 bytes/s }
    public static double[] Read(IntPtr hWnd) {
        double percent = -1, downloaded = 0, speed = 0;
        string title = TextOf(hWnd);
        int idx = title.IndexOf('%');
        if (idx > 0) percent = Number(title.Substring(0, idx).Trim());

        EnumChildWindows(hWnd, (child, p) => {
            if (ClassOf(child) != "Static") return true;
            string text = TextOf(child);

            Match d = DownloadedRegex.Match(text);
            if (d.Success) { downloaded = Number(d.Groups[1].Value) * 1048576.0; percent = Number(d.Groups[2].Value); }

            Match s = SpeedRegex.Match(text);
            if (s.Success) speed = Number(s.Groups[1].Value) * (s.Groups[2].Value.Equals("KB", StringComparison.OrdinalIgnoreCase) ? 1024.0 : 1048576.0);
            return true;
        }, IntPtr.Zero);

        return new double[] { percent, downloaded, speed };
    }
}
'@
    }

    # --- 監控參數 ---
    $idmShutdownGraceMs = 10000   # idman.exe 只是啟動器；啟動後前 10 秒不判定進程消失
    $confirmMs = 3000    # 進程消失後，等待檔案落地的時間
    $downloadTimeout = [TimeSpan]::FromMinutes(30)

    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $progressWindow = [IntPtr]::Zero
    $goneAtMs = $null
    $highestPercent = 0.0

    # --- 輸出 ---
    $consoleState = @{ LastLength = 0 }

    # 不帶參數時只顯示「下載中」；有 $githubSize 時顯示總大小與百分比
    function Write-IdmLine {
        param($Downloaded = $null, [double]$Percent = 0, [double]$SpeedMB = 0)
        $text = if ($null -eq $Downloaded) { 'IDM 下載中 ...' }
        elseif ($githubSize -gt 0) { "IDM 下載中: {0:N1} MB / {1:N1} MB ({2:N1}%) {3:N1} MB/s" -f ($Downloaded / 1MB), ($githubSize / 1MB), $Percent, $SpeedMB }
        else { "IDM 下載中: {0:N1} MB {1:N1} MB/s" -f ($Downloaded / 1MB), $SpeedMB }
        [Console]::Write("`r" + $text.PadRight($consoleState.LastLength))
        $consoleState.LastLength = $text.Length
    }

    # --- 主迴圈 ---
    Write-IdmLine
    while ($true) {
        $nowMs = $timer.ElapsedMilliseconds

        # --- 讀取彈窗 ---
        # 句柄失效（隱藏、取消後重新下載）就清掉，並在同一輪重新搜尋。
        if ($progressWindow -ne [IntPtr]::Zero -and -not [GauIdmProgressWindow]::IsWindow($progressWindow)) {
            $progressWindow = [IntPtr]::Zero
        }
        if ($progressWindow -eq [IntPtr]::Zero) {
            $progressWindow = [GauIdmProgressWindow]::Find($assetName)
        }
        $popup = if ($progressWindow -ne [IntPtr]::Zero) { [GauIdmProgressWindow]::Read($progressWindow) } else { @(-1, 0, 0) }

        # IDM 進程已消失（IDM 原本就在執行時不看進程）
        # 彈窗還在代表 IDM 一定活著，省略 Get-Process 以降低 CPU 開銷。
        $processGone = -not $idmWasRunning -and $nowMs -ge $idmShutdownGraceMs -and
        $progressWindow -eq [IntPtr]::Zero -and
        -not (Get-Process IDMan -ErrorAction SilentlyContinue)

        # --- 完成判定 ---
        # 已知大小：檔案達到 GitHub 大小即完成；未知大小：進程結束後檔案存在即完成。
        $info = [System.IO.FileInfo]::new($filePath)
        $fileSize = if ($info.Exists) { $info.Length } else { -1 }
        $isComplete = if ($githubSize -gt 0) { $fileSize -ge $githubSize } else { $processGone -and $fileSize -gt 0 }

        if ($isComplete) {
            Write-IdmLine -Downloaded ([Math]::Max($githubSize, $fileSize)) -Percent 100
            Write-Host "`nIDM 下載完成: $assetName"
            return $true
        }

        # --- 失敗判定：進程消失（需持續 $confirmMs）、逾時 ---
        # 暫停／停止／取消都不算失敗（IDM 可續傳或重新加入），一律等到逾時。
        if (-not $processGone) { $goneAtMs = $null }
        elseif ($null -eq $goneAtMs) { $goneAtMs = $nowMs }
        elseif (($nowMs - $goneAtMs) -ge $confirmMs) {
            Write-Host "`nIDM 已結束但檔案不完整（可能取消或失敗）。" -ForegroundColor Red
            return $false
        }

        if ($timer.Elapsed -ge $downloadTimeout) {
            Write-Host "`n等待 IDM 下載逾時（30 分鐘），視為失敗。" -ForegroundColor Red
            return $false
        }

        # --- 顯示進度 ---
        if ($popup[0] -ge 0) {
            # IDM 重連時數值可能回落，顯示值只前進不倒退。
            $highestPercent = [Math]::Max($highestPercent, [Math]::Min(100.0, $popup[0]))
            $downloaded = if ($popup[1] -gt 0) { [long]$popup[1] } else { [long]($githubSize * $highestPercent / 100.0) }
            Write-IdmLine -Downloaded $downloaded -Percent $highestPercent -SpeedMB ($popup[2] / 1MB)
        }

        # 有彈窗時 250ms；找不到時每秒才搜尋一次（EnumWindows 與 Get-Process 較吃資源）
        Start-Sleep -Milliseconds $(if ($progressWindow -ne [IntPtr]::Zero) { 250 } else { 1000 })
    }
}

function DownloadAsset {
    param($asset)

    # 區域變數先歸零：避免下載途中失敗時，finally 以動態作用域讀到外層同名變數（如 ToolUpdate 的 $response）
    $ok = $false
    $errMsg = ''
    $response = $null
    $stream = $null
    $fileStream = $null
    $progressShown = $false

    $url = $asset.browser_download_url
    $filePath = Join-Path $ctx.dir $asset.name

    Write-Host "下載資產: $($asset.name)"
    Write-Host "下載位置: $filePath"
    Write-Host "下載網址: $url"

    # 有 IDM 且未停用 → 交由 IDM 下載（不跑內部進度列）
    if ($idmExe -and -not $ctx.no_idm) {
        $ok = InvokeIdmDownload -asset $asset -filePath $filePath

        if ($ok -and ($ctx.auto_extract -or $ctx.auto_extract2)) { AutoExtract -filePath $filePath | Out-Null }

        return $ok
    }

    try {
        $request = [System.Net.WebRequest]::Create($url)
        $request.UserAgent = $userAgent
        $response = $request.GetResponse()
        $stream = $response.GetResponseStream()

        # 大小優先取 GitHub API 的 size，備援用 HTTP Content-Length
        $total = $asset.size
        if (-not $total -or $total -le 0) { $total = $response.ContentLength }

        $fileStream = [System.IO.File]::Create($filePath)
        $buffer = [byte[]]::new(1MB)
        $readTotal = 0

        # 進度顯示：固定欄寬 + 0.1% 精度 + 即時速度
        # ps2exe 主控台模式不支援 Write-Progress
        function ShowProgress {
            param([double]$speed)

            if ($total -gt 0) {
                $percent = [Math]::Min(100.0, $readTotal * 100.0 / $total)
                [Console]::Write(("`r下載中: {0:N1} MB / {1:N1} MB ({2:N1}%) {3:N1} MB/s" -f ($readTotal / 1MB), ($total / 1MB), $percent, $speed))
            }
            else {
                [Console]::Write(("`r下載中: {0:N1} MB {1:N1} MB/s" -f ($readTotal / 1MB), $speed))
            }
        }

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $lastUpdateMs = 0
        $lastShownBytes = 0

        ShowProgress 0.0
        $progressShown = $true

        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $fileStream.Write($buffer, 0, $read)
            $readTotal += $read

            # 每 100ms 更新一次，不受百分比粒度限制
            $nowMs = $stopwatch.ElapsedMilliseconds
            if (($nowMs - $lastUpdateMs) -ge 100) {
                $elapsedSec = [Math]::Max(($nowMs - $lastUpdateMs) / 1000.0, 0.001)
                ShowProgress (($readTotal - $lastShownBytes) / 1MB / $elapsedSec)
                $lastUpdateMs = $nowMs
                $lastShownBytes = $readTotal
            }
        }

        # 收尾確保最後一幀一定輸出（時間節流可能吞掉）
        if ($readTotal -gt $lastShownBytes) {
            $elapsedSec = [Math]::Max($stopwatch.ElapsedMilliseconds - $lastUpdateMs, 1) / 1000.0
            ShowProgress (($readTotal - $lastShownBytes) / 1MB / $elapsedSec)
        }

        $ok = $true
    }
    catch {
        $errMsg = $_.Exception.GetBaseException().Message
    }
    finally {
        if ($fileStream) { $fileStream.Dispose() }
        if ($stream) { $stream.Dispose() }
        if ($response) { $response.Dispose() }

        # 結束進度列，避免後續訊息接在同一行
        if ($progressShown) { Write-Host "" }

        if (-not $ok -and (Test-Path -LiteralPath $filePath)) { Remove-Item -LiteralPath $filePath -Force }
    }

    if (-not $ok) {
        Write-Host "下載失敗: $errMsg" -ForegroundColor Red
        return $false
    }

    Write-Host "下載完成: $($asset.name)"

    if ($ctx.auto_extract -or $ctx.auto_extract2) { AutoExtract -filePath $filePath | Out-Null }

    return $true
}

# 核心管線：查 API → 比版本 → 選資產 → 下載 → 解壓
# 狀態全部從 $ctx 讀取，結果寫回 $ctx；版本寫回一律由呼叫端（模式層）接手
function ToolUpdate {
    $headers = @{ "User-Agent" = $userAgent }
    if ($githubToken) { $headers["Authorization"] = "Bearer $githubToken" }

    $response = Invoke-RestMethod -Uri "https://api.github.com/repos/$($ctx.owner)/$($ctx.repo)/releases/latest" -Headers $headers

    # ? 測試用
    # GetDownloadInfo -assets $response.assets | ForEach-Object { write-host $_.name }
    # return

    if (-not $response -or -not ($response.tag_name -and $response.assets)) {
        Write-Host "無法獲取最新版本資訊，請檢查倉庫名稱和網絡連接。" -ForegroundColor Red
        $ctx.Status = 'ApiError'
        return
    }

    $ctx.NewVersion = $response.tag_name

    $oldVersion = ParseVersion $ctx.currentVersion
    $newVersion = ParseVersion $response.tag_name

    if (-not $oldVersion) {
        if (-not $ctx.DownloadOnFirstRecord) {
            Write-Host "未找到之前的版本。"
            $ctx.Status = 'RecordOnly'
            return
        }
        if ($ctx.CheckOnly) {
            Write-Host "紀錄版本無法比對，遠端最新: $($response.tag_name)"
            $ctx.Status = 'HasUpdate'
            return
        }
        # -i 無紀錄或新路徑：視同首次下載，直接下載最新
        Write-Host "視為首次下載，直接下載最新版本: $($response.tag_name)"
    }
    elseif ($oldVersion -eq $newVersion) {
        Write-Host "已是最新版本。`n當前版本: $($response.tag_name)"
        $ctx.Status = 'UpToDate'
        return
    }
    elseif ($oldVersion -lt $newVersion) {
        Write-Host "有可用更新: $($response.tag_name) (目前版本: $oldVersion)"
        if ($ctx.CheckOnly) {
            $ctx.Status = 'HasUpdate'
            return
        }
    }
    else {
        Write-Host "本機版本 ($oldVersion) 比最新發布版本 ($newVersion) 更新。 版本記錄已重置。" -ForegroundColor Yellow
        $ctx.Status = 'Reset'
        return
    }

    $downloadInfo = GetDownloadInfo -assets $response.assets

    if ($downloadInfo) {
        Write-Host "下載版本: $($response.tag_name)"

        $failed = @()
        foreach ($asset in $downloadInfo) {
            if (-not (DownloadAsset -asset $asset)) { $failed += $asset.name }
        }

        if ($failed.Count -eq 0) {
            $ctx.Status = 'Updated'
        }
        else {
            $ctx.Status = 'Failed'
            $ctx.Failed = $failed
            Write-Host "有 $($failed.Count) 個資產下載失敗，版本記錄未更新，下次執行會重新嘗試：" -ForegroundColor Red
            foreach ($name in $failed) { Write-Host "  - $name" -ForegroundColor Red }
        }
    }
    else {
        $ctx.Status = 'NoAsset'
        Write-Host "未找到適合下載的資產。請檢查倉庫的發布頁面以確保有適合 Windows 的資產，或使用 -asset_name 參數指定資產名稱。" -ForegroundColor Yellow
    }
}

# ===== 執行 =====

switch ($mode) {
    'uninstall' {
        # 解除紀錄綁定（不刪除任何已下載的檔案；不做路徑檢查）
        $records = RecordsLoad
        if ($null -eq $records) { break }

        # -un 吃 key 或完整網址（解析統一走 ParseRepoArg）
        $parsed = ParseRepoArg -arg $uninstall
        $key = if ($parsed) { "$($parsed[0])/$($parsed[1])" } else { $uninstall }

        if (RecordRemove -key $key) {
            Write-Host "已解除紀錄綁定: $key（已下載的檔案未更動）"
        }
        else {
            Write-Host "查無紀錄: $key" -ForegroundColor Red
        }
    }

    'install' {
        # 管理線：版本讀自統一紀錄；操作成功 → 整筆覆蓋寫回（不做逐欄合併）
        $records = RecordsLoad
        if ($null -eq $records) { break }

        $key = "$($ctx.owner)/$($ctx.repo)"
        $ctx.DownloadOnFirstRecord = $true

        if ($records.Contains($key)) {
            $rec = $records[$key]

            if ("$($rec.dir)" -eq $ctx.dir) {
                $ctx.currentVersion = "$($rec.version)"
            }
            else {
                Write-Host "調用路徑與紀錄不同（紀錄: $($rec.dir)），視為全新下載。" -ForegroundColor Yellow
            }
        }

        ToolUpdate

        switch ($ctx.Status) {
            'Updated' { RecordUpsert }
            'UpToDate' { RecordUpsert }
            'Reset' { RecordUpsert }
        }
    }

    'list' {
        $records = RecordsLoad
        if ($null -eq $records) { break }

        ShowRecords -records $records
    }

    { $_ -in @('check', 'all') } {
        # 批量線：-check 只檢查不下載（完全唯讀）；-all 用紀錄參數在紀錄的 dir 重放
        $records = RecordsLoad
        if ($null -eq $records) { break }

        $stats = @{ Updated = 0; UpToDate = 0; Failed = 0; Dead = 0 }
        $failedList = @()

        foreach ($key in @($records.Keys)) {
            $rec = $records[$key]
            if (-not (Test-Path -LiteralPath "$($rec.dir)")) {
                Write-Host "[$key] 路徑失效: $($rec.dir)" -ForegroundColor Red
                $stats.Dead++
                continue
            }

            Write-Host "`n[$key]"
            try {
                $ctx = CtxFromRecord -key $key -rec $rec
                $ctx.CheckOnly = ($mode -eq 'check')
                ToolUpdate

                switch ($ctx.Status) {
                    'Updated'   { $stats.Updated++; if ($mode -eq 'all') { RecordUpsert } }
                    'HasUpdate' { $stats.Updated++ }
                    'UpToDate'  { $stats.UpToDate++ }
                    'Reset'     { $stats.UpToDate++; if ($mode -eq 'all') { RecordUpsert } }
                    default     { $stats.Failed++; $failedList += "$key ($($ctx.Status))" }
                }
            }
            catch {
                Write-Host "[$key] 執行失敗: $($_.Exception.Message)" -ForegroundColor Red
                $stats.Failed++
                $failedList += "$key (例外: $($_.Exception.Message))"
            }
        }

        Write-Host ""
        Write-Host ("彙總: 更新 {0} | 已最新 {1} | 失敗 {2} | 路徑失效 {3}" -f $stats.Updated, $stats.UpToDate, $stats.Failed, $stats.Dead) -ForegroundColor Cyan
        if ($failedList.Count -gt 0) {
            foreach ($f in $failedList) { Write-Host "  失敗: $f" -ForegroundColor Red }
        }
    }

    'single' {
        # 單發線：版本讀自標記檔
        $ctx.currentVersion = GetVersion

        ToolUpdate

        # 收尾：依狀態寫回標記檔
        switch ($ctx.Status) {
            'RecordOnly' { SetVersion $ctx.NewVersion }
            'Updated' { SetVersion $ctx.NewVersion }
            'Reset' { SetVersion $ctx.NewVersion }
        }
    }
}

Read-Host "`n按任意鍵退出"
