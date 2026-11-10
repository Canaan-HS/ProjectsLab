param (
    [Parameter(Position = 0)]
    [Alias("u")]
    [string]$url = "",

    [Alias("o")]
    [string]$owner = "",

    [Alias("r")]
    [string]$repo = "",

    [Alias("i")]
    [string]$install = $null,

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

# 統一輸出格式，錯誤紅字、警告黃字
$Log = @{
    Info = { param([string]$msg) Write-Host $msg }
    Warn = { param([string]$msg) Write-Host $msg -ForegroundColor Yellow }
    Err  = { param([string]$msg) Write-Host $msg -ForegroundColor Red }
}

$Cli = @{
    Help      = {
        Write-Host @"

GitHub 資產更新工具

使用:
  gau.exe <GitHub 網址> [選項]
  gau.exe -o <owner> -r <repo> [選項]
  gau.exe -i <GitHub 網址 | owner/repo> [選項]
  gau.exe -i -o <owner> -r <repo> [選項]
  gau.exe -un <owner/repo>
  gau.exe -l | -c | -al

選項:
  -u, -url <url>                 GitHub 儲存庫網址
  -o, -owner <name>              GitHub 儲存庫擁有者
  -r, -repo <name>               GitHub 儲存庫名稱
  -a, -asset_name <name>         資產檔名關鍵字
  -e, -exclude_patterns <list>   排除關鍵字（逗號分隔）
  -ae, -auto_extract             下載後自動解壓縮
  -ae2, -auto_extract2           解壓後攤平單一頂層資料夾
  -ni, -no_idm                   停用 IDM 偵測，強制使用內建下載器
  -i, -install <owner/repo>      統一管理線：下載並納入紀錄
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
  gau -i user/app -ae2
  gau -i -o user -r app -a "x64" -ae
"@ -ForegroundColor Green
        exit 0
    }

    ParseRepo = {
        # 解析回傳 @(owner, repo) or 空陣列
        param([string]$text)

        if ($text -match '(?i)^https://github\.com/([^/]+)/([^/]+)') {
            return @($matches[1], $matches[2])
        }
        if ($text -match '^[^/\s]+/[^/\s]+$') {
            return $text -split '/'
        }
        return @()
    }
}

if ($MyInvocation.MyCommand.CommandType -ne "ExternalScript") {
    # ps2exe 宿主以萬用字元解析工作目錄，路徑含 [ ] 時誤判而退回 exe 自身資料夾；
    # 行程 CWD（Win32 層）不受影響，改以 -LiteralPath 導回
    $procCwd = [Environment]::CurrentDirectory
    if ($procCwd -and (Test-Path -LiteralPath $procCwd)) { Set-Location -LiteralPath $procCwd }

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

if ($help -or $PSBoundParameters.Count -eq 0) { & $Cli.Help }

# 模式判定（同時出現時取先者, 優先序: uninstall > install > list > check > all > 單發）
$mode = if ($uninstall) { 'uninstall' }
elseif ($install) { 'install' }
elseif ($list) { 'list' }
elseif ($check) { 'check' }
elseif ($all) { 'all' }
else { 'single' }

if ($url -match '(?i)^https://github\.com/([^/]+)/([^/]+)') {
    $owner = $matches[1]
    $repo = $matches[2]
}
elseif ($install) {
    # -i 的值（owner/repo 簡寫或 GitHub 網址）；編譯版「-i 後面沒有值」會傳入 'True'，
    # ParseRepo 解析不了 → 落到 -o/-r；腳本模式下 -i 後無值則直接由 PowerShell 擋下（提示給值）
    $parsed = & $Cli.ParseRepo $install

    if ($parsed) {
        $owner = $parsed[0]
        $repo = $parsed[1]
    }
}

# uninstall / list / check / all 不需要倉庫參數
if (-not $owner -or -not $repo) {

    if ($mode -eq 'install') {
        & $Log.Err "-i 需要 GitHub 網址、owner/repo 或 -o/-r 參數"
        & $Log.Info "範例: gau -i astral-sh/uv"
        exit 1
    }

    if ($mode -eq 'single') {
        & $Log.Err "需要 GitHub 網址或 -o/-r 參數"
        & $Cli.Help
    }
}

# ===== 核心程式 =====

$userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/155.0.0.0 Safari/537.36"

# 旗標：欄位名 → 簡寫（ctx 建立、紀錄存取、列表顯示共用；新增 -ae3 之類的旗標只需登記於此）
$Flags = [ordered]@{
    auto_extract  = 'ae'
    auto_extract2 = 'ae2'
    no_idm        = 'ni'
}

# ctx: 本次操作的共享狀態（臨時乾淨列表）
# 所有物件方法統一跟它拿參數、把結果寫回
# 單發線從參數建立 之後管理線會從紀錄逐筆重建
$ctx = @{
    owner                 = $owner
    repo                  = $repo
    dir                   = (Get-Location).Path
    asset_name            = $asset_name
    exclude_patterns      = $exclude_patterns
    currentVersion        = ""
    # 行為開關
    DownloadOnFirstRecord = $false   # -i 無紀錄時直接下載最新；單發線只記版本不下載
    CheckOnly             = $false
    # 結果欄位（Tool.Update 寫回）
    Status                = ""
    NewVersion            = ""
}
foreach ($flag in $Flags.Keys) { $ctx[$flag] = [bool](Get-Variable $flag -ValueOnly) }

$Github = @{
    Token      = $null

    # GitHub API token：環境變數優先，其次 gh CLI 登入憑證
    _FindToken = {
        if ($env:GITHUB_TOKEN) { return $env:GITHUB_TOKEN }

        $ghCmd = Get-Command gh -ErrorAction SilentlyContinue
        if (-not $ghCmd) { return $null }

        try { $token = "$(& $ghCmd.Source auth token 2>$null)".Trim() } catch { $token = $null }
        if ($token) { return $token }
        return $null
    }

    Latest     = {
        $headers = @{ "User-Agent" = $userAgent }
        if ($Github.Token) { $headers["Authorization"] = "Bearer $($Github.Token)" }

        Invoke-RestMethod -Uri "https://api.github.com/repos/$($ctx.owner)/$($ctx.repo)/releases/latest" -Headers $headers
    }
}
$Github.Token = & $Github._FindToken

# 版本：單發線用標記檔，比對用 Parse
$Ver = @{
    _Name = { param([string]$version) "! Version - $($ctx.repo) - $version" }

    # 取得版本文件（單發線：標記檔）
    _File = {
        $prefix = & $Ver._Name ''

        Get-ChildItem -LiteralPath $ctx.dir -File -Filter "$prefix*" |
        Sort-Object Name -Descending |
        Select-Object -First 1
    }

    Get   = {
        $file = & $Ver._File
        if (-not $file) { return "" }
        return $file.Name.Substring((& $Ver._Name '').Length)
    }

    Set   = {
        param([string]$version)

        $file = & $Ver._File
        $newName = & $Ver._Name $version

        if ($file) {
            Rename-Item -LiteralPath $file.FullName -NewName $newName -Force
        }
        else {
            # New-Item 沒有 -LiteralPath，改用 .NET 直接建空檔（路徑含 [ ] 也安全）
            [System.IO.File]::WriteAllText((Join-Path $ctx.dir $newName), "")
        }
        & $Log.Info "記錄版本: $version"
    }

    Parse = {
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
}

$Records = @{
    Path   = (Join-Path $env:USERPROFILE '.gau\records.json')
    Items  = $null

    # 讀入 Items
    Load   = {
        $Records.Items = [ordered]@{}
        if (-not (Test-Path -LiteralPath $Records.Path)) { return $true }

        try {
            $obj = Get-Content -LiteralPath $Records.Path -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        catch {
            & $Log.Err "紀錄檔解析失敗: $($_.Exception.Message)"
            return $false
        }

        if ($obj) {
            foreach ($p in $obj.PSObject.Properties) {
                $rec = [ordered]@{}
                foreach ($q in $p.Value.PSObject.Properties) { $rec[$q.Name] = $q.Value }
                $Records.Items[$p.Name] = $rec
            }
        }
        return $true
    }

    # 單一 JSON 字串值（含外層引號與跳脫）, 不用 ConvertTo-Json 是因為 5.1 對非 ASCII 與縮排的輸出與 7 不同
    _Str   = {
        param([string]$value)

        $escaped = $value.Replace('\', '\\').Replace('"', '\"')

        $sb = [System.Text.StringBuilder]::new('"')
        foreach ($ch in $escaped.ToCharArray()) {
            if ([int]$ch -lt 32) { $null = $sb.Append('\u{0:x4}' -f [int]$ch) }
            else { $null = $sb.Append($ch) }
        }
        $null = $sb.Append('"')
        return $sb.ToString()
    }

    Save   = {
        try {
            $parent = [System.IO.Path]::GetDirectoryName($Records.Path)
            if (-not (Test-Path -LiteralPath $parent)) {
                [System.IO.Directory]::CreateDirectory($parent) | Out-Null
            }

            # 手動序列化：統一為標準 2 空格縮排（5.1 的 ConvertTo-Json 是對齊式縮排且空物件跨行）
            $keys = @($Records.Items.Keys)
            if ($keys.Count -eq 0) {
                $json = "{}"
            }
            else {
                $entries = foreach ($key in $keys) {
                    $rec = $Records.Items[$key]

                    $fields = foreach ($name in @($rec.Keys)) {
                        $value = $rec[$name]
                        if ($null -eq $value) { continue }

                        if ($value -is [bool]) {
                            $jsonValue = if ($value) { 'true' } else { 'false' }
                        }
                        elseif ($value -is [int] -or $value -is [long] -or $value -is [double] -or $value -is [decimal]) {
                            $jsonValue = "$value"
                        }
                        else {
                            $jsonValue = & $Records._Str "$value"
                        }
                        '    {0}: {1}' -f (& $Records._Str $name), $jsonValue
                    }

                    "  {0}: {{`r`n{1}`r`n  }}" -f (& $Records._Str $key), ($fields -join ",`r`n")
                }
                $json = "{`r`n" + ($entries -join ",`r`n") + "`r`n}"
            }

            [System.IO.File]::WriteAllText($Records.Path, $json + "`r`n", [System.Text.UTF8Encoding]::new($false))
        }
        catch {
            & $Log.Err "紀錄檔寫入失敗: $($_.Exception.Message)"
        }
    }

    # 整筆重寫該 key 的紀錄（從 $ctx 序列化；不做逐欄合併，缺席欄位自然消失）
    Upsert = {
        $key = "$($ctx.owner)/$($ctx.repo)"

        # 以本次輸入的大小寫改寫 key（比對不分大小寫；大小寫相同時原位覆蓋，保持檔案順序穩定）
        $oldKey = @($Records.Items.Keys) | Where-Object { $_ -ieq $key } | Select-Object -First 1
        if ($oldKey -and $oldKey -cne $key) { $Records.Items.Remove($oldKey) }

        # [ordered] 保證欄位順序固定（雜湊表的列舉順序隨行程改變，會讓檔案位元組不穩定）
        $rec = [ordered]@{}
        $rec['dir'] = $ctx.dir
        $rec['version'] = $ctx.NewVersion
        if ($ctx.asset_name) { $rec['asset_name'] = $ctx.asset_name }
        if ($ctx.exclude_patterns) { $rec['exclude_patterns'] = $ctx.exclude_patterns }
        foreach ($flag in $Flags.Keys) { if ($ctx[$flag]) { $rec[$flag] = $true } }

        $Records.Items[$key] = $rec
        & $Records.Save
    }

    Delete = {
        param([string]$key)

        $oldKey = @($Records.Items.Keys) | Where-Object { $_ -ieq $key } | Select-Object -First 1
        if (-not $oldKey) { return $false }

        $Records.Items.Remove($oldKey)
        & $Records.Save
        return $true
    }

    # 紀錄 → ctx（批量線每筆重建；dir 與參數全部用紀錄裡的，缺席欄位讀出 $null = 沒給）
    ToCtx  = {
        param([string]$key, $rec)

        $parts = $key -split '/'

        $new = @{
            owner                 = $parts[0]
            repo                  = $parts[1]
            dir                   = "$($rec.dir)"
            asset_name            = $rec.asset_name
            exclude_patterns      = $rec.exclude_patterns
            currentVersion        = "$($rec.version)"
            DownloadOnFirstRecord = $true
            CheckOnly             = $false
            Status                = ""
            NewVersion            = ""
        }
        foreach ($flag in $Flags.Keys) { $new[$flag] = [bool]$rec[$flag] }
        return $new
    }

    # 顯示紀錄列表（-l）：每筆一行，路徑失效整行紅字
    Show   = {
        if ($Records.Items.Count -eq 0) {
            & $Log.Warn "尚無紀錄 (以 gau -i <owner/repo> 加入)"
            return
        }

        foreach ($key in @($Records.Items.Keys)) {
            $rec = $Records.Items[$key]

            $params = @()
            if ($rec.asset_name) { $params += "a=$($rec.asset_name)" }
            if ($rec.exclude_patterns) { $params += "e=$($rec.exclude_patterns)" }
            foreach ($flag in $Flags.Keys) { if ($rec[$flag]) { $params += $Flags[$flag] } }
            $paramText = if ($params.Count -gt 0) { " [$($params -join ' ')]" } else { "" }

            $verText = if ("$($rec.version)" -match '^v') { "$($rec.version)" } else { "v$($rec.version)" }
            $line = "{0}  {1}  {2}{3}" -f $key, $verText, $rec.dir, $paramText
            if (Test-Path -LiteralPath "$($rec.dir)") { & $Log.Info $line }
            else { & $Log.Err $line }
        }
    }
}

$Idm = @{
    Exe     = $null

    # IDM 偵測
    Locate  = {
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

    # 彈窗由既有的 IDMan 主進程建立（新的 IDMan.exe 只是啟動器），
    # 內含 msctls_progress32 與 Static 進度文字，約 200ms 更新一次。
    # 彈窗只用來顯示進度；使用者可能按「隱藏」或取消後重新下載，句柄會失效，需重新搜尋。
    # C# 只取文字，數值解析在 PowerShell 端（Add-Type 編譯時引用 Regex 會因組件轉送而失敗）
    _Source = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class GauIdmProgressWindow {
    private delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc cb, IntPtr p);
    [DllImport("user32.dll")] private static extern bool EnumChildWindows(IntPtr hWnd, EnumProc cb, IntPtr p);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassName(IntPtr hWnd, StringBuilder sb, int max);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);

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

    // 回傳 { 視窗標題, 各 Static 文字... }
    public static string[] Read(IntPtr hWnd) {
        List<string> texts = new List<string>();
        texts.Add(TextOf(hWnd));
        EnumChildWindows(hWnd, (child, p) => {
            if (ClassOf(child) == "Static") texts.Add(TextOf(child));
            return true;
        }, IntPtr.Zero);
        return texts.ToArray();
    }
}
'@

    _Load   = {
        if (-not ('GauIdmProgressWindow' -as [type])) {
            Add-Type -TypeDefinition $Idm._Source
        }
    }

    # 數字字串轉 double（含千分位或逗號小數點），失敗回傳 -1
    _Number = {
        param([string]$s)

        if ($s.IndexOf(',') -ge 0) {
            $s = if ($s.IndexOf('.') -ge 0) { $s.Replace(',', '') } else { $s.Replace(',', '.') }
        }

        $v = 0.0
        if ([double]::TryParse($s, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$v)) { return $v }
        return -1.0
    }

    # 解析彈窗文字，回傳 { 百分比(讀不到為 -1), 已下載 bytes, 速度 bytes/s }
    _Parse  = {
        param([string[]]$texts)

        $percent = -1.0
        $downloaded = 0.0
        $speed = 0.0

        $title = $texts[0]
        $idx = $title.IndexOf('%')
        if ($idx -gt 0) { $percent = & $Idm._Number ($title.Substring(0, $idx).Trim()) }

        foreach ($text in ($texts | Select-Object -Skip 1)) {
            if ($text -match '([0-9][0-9.,]*)\s*MB\s*\(\s*([0-9][0-9.,]*)\s*%') {
                $downloaded = (& $Idm._Number $matches[1]) * 1048576.0
                $percent = & $Idm._Number $matches[2]
            }
            if ($text -match '([0-9][0-9.,]*)\s*(MB|KB)\s*/\s*(?:s|sec|秒)') {
                $unit = if ($matches[2] -ieq 'KB') { 1024.0 } else { 1048576.0 }
                $speed = (& $Idm._Number $matches[1]) * $unit
            }
        }

        return @($percent, $downloaded, $speed)
    }

    # 成功回傳 $null，失敗回傳原因
    Run     = {
        param($asset, [string]$filePath)

        # --- IDM 進度彈窗 ---
        # 先載入再啟動 IDM，載入失敗時不會留下無人監控的下載
        try { & $Idm._Load }
        catch { return "無法載入 IDM 進度監控: $($_.Exception.Message)" }

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
            Start-Process -FilePath $Idm.Exe -ArgumentList $idmArgs -ErrorAction Stop | Out-Null
        }
        catch {
            return "無法啟動 IDM: $($_.Exception.Message)"
        }

        # --- 監控參數 ---
        $idmShutdownGraceMs = 10000   # idman.exe 只是啟動器；啟動後前 10 秒不判定進程消失
        $confirmMs = 3000    # 進程消失後，等待檔案落地的時間
        $downloadTimeout = [TimeSpan]::FromMinutes(30)

        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        $progressWindow = [IntPtr]::Zero
        $goneAtMs = $null
        $highestPercent = 0.0
        $failure = $null

        # --- 主迴圈 ---
        & $Download._Print 'IDM 下載中 ...'
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
            $popup = if ($progressWindow -ne [IntPtr]::Zero) { & $Idm._Parse ([GauIdmProgressWindow]::Read($progressWindow)) } else { @(-1, 0, 0) }

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
                & $Download._Progress 'IDM 下載中' ([Math]::Max($githubSize, $fileSize)) $githubSize 0 100
                break
            }

            # --- 失敗判定：進程消失（需持續 $confirmMs）、逾時 ---
            # 暫停／停止／取消都不算失敗（IDM 可續傳或重新加入），一律等到逾時。
            if (-not $processGone) { $goneAtMs = $null }
            elseif ($null -eq $goneAtMs) { $goneAtMs = $nowMs }
            elseif (($nowMs - $goneAtMs) -ge $confirmMs) { $failure = 'IDM 已結束但檔案不完整'; break }

            if ($timer.Elapsed -ge $downloadTimeout) { $failure = 'IDM 逾時 (30 分鐘)'; break }

            # --- 顯示進度 ---
            if ($popup[0] -ge 0) {
                # IDM 重連時數值可能回落，顯示值只前進不倒退。
                $highestPercent = [Math]::Max($highestPercent, [Math]::Min(100.0, $popup[0]))
                $downloaded = if ($popup[1] -gt 0) { [long]$popup[1] } else { [long]($githubSize * $highestPercent / 100.0) }
                & $Download._Progress 'IDM 下載中' $downloaded $githubSize ($popup[2] / 1MB) $highestPercent
            }

            # 有彈窗時 250ms；找不到時每秒才搜尋一次（EnumWindows 與 Get-Process 較吃資源）
            Start-Sleep -Milliseconds $(if ($progressWindow -ne [IntPtr]::Zero) { 250 } else { 1000 })
        }

        & $Download._EndLine
        return $failure
    }
}
$Idm.Exe = & $Idm.Locate

$Archive = @{
    # 解壓後規則：依旗標啟用、依序執行；Run 收到解壓目錄與目前新增的頂層項目
    # 新增規則（-ae3 ...）只需在此加一條並於 $Flags 登記旗標；任一規則啟用即視同 -ae
    Rules   = @(
        @{
            # -ae2 攤平層：解壓新增項「恰好一個資料夾」才攤平，其他情況等同 -ae
            # 將資料夾內容全部上移覆蓋到上層，最後刪除資料夾
            # 失敗時停止、保留資料夾與現狀，僅回報（不影響下載結果）
            Flag = 'auto_extract2'
            Run  = {
                param([string]$destination, $newItems)

                if (-not ($newItems.Count -eq 1 -and $newItems[0].PSIsContainer)) {
                    & $Log.Warn "跳過攤平: 解壓結果非單一頂層資料夾"
                    return
                }

                $shell = $newItems[0]

                try {
                    foreach ($item in @(Get-ChildItem -LiteralPath $shell.FullName -Force)) {
                        $target = Join-Path $destination $item.Name

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

                    Remove-Item -LiteralPath $shell.FullName -Force -ErrorAction Stop
                }
                catch {
                    & $Log.Err "攤平失敗: $($shell.Name) ($($_.Exception.Message))"
                }
            }
        }
    )

    Extract = {
        param([string]$filePath)

        $rules = @($Archive.Rules | Where-Object { $ctx[$_.Flag] })
        if (-not ($ctx.auto_extract -or $rules)) { return }

        # 可解壓的封存檔副檔名（忽略大小寫）
        $archiveExtensions = @(
            '.tar.gz', '.tar.xz', '.tar.bz2', '.tar.zst',
            '.tgz', '.txz', '.tbz2', '.tzst',
            '.zip', '.7z', '.rar', '.tar'
        )

        $name = [System.IO.Path]::GetFileName($filePath)
        $lowerName = $name.ToLowerInvariant()

        if (-not ($archiveExtensions | Where-Object { $lowerName.EndsWith($_) })) { return }

        & $Log.Info "解壓: $name"

        $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
        $destination = [System.IO.Path]::GetDirectoryName($filePath)

        # 解壓前快照頂層項目（此時壓縮檔已存在於清單中，diff 只取解壓新增項）
        if ($rules) {
            $before = @((Get-ChildItem -LiteralPath $destination -Force).Name)
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
            & $Log.Err "解壓失敗: $name"
            foreach ($line in $output) {
                $text = "$line".Trim()
                if ($text) { & $Log.Err "  $text" }
            }
            return
        }

        # 每條規則執行前重新取新增項，後面的規則看得到前面規則的結果
        foreach ($rule in $rules) {
            $newItems = @(Get-ChildItem -LiteralPath $destination -Force | Where-Object { $before -notcontains $_.Name })
            & $rule.Run $destination $newItems
        }

        try { Remove-Item -LiteralPath $filePath -Force -ErrorAction Stop }
        catch { & $Log.Warn "無法移除壓縮檔: $name" }
    }
}

$Download = @{
    _Last     = 0

    # 同一行覆寫輸出，以前一次長度補空白避免殘留
    _Print    = {
        param([string]$text)

        [Console]::Write("`r" + $text.PadRight($Download._Last))
        $Download._Last = $text.Length
    }

    # 結束進度列，避免後續訊息接在同一行
    _EndLine  = {
        Write-Host ""
        $Download._Last = 0
    }

    # 進度顯示：固定欄寬 + 0.1% 精度 + 即時速度
    # ps2exe 主控台模式不支援 Write-Progress
    # total 未知時只顯示已下載量；percent 省略時由 done/total 計算
    _Progress = {
        param([string]$label, [double]$done, [double]$total, [double]$speed, $percent = $null)

        if ($total -gt 0) {
            if ($null -eq $percent) { $percent = [Math]::Min(100.0, $done * 100.0 / $total) }
            $text = "{0}: {1:N1} MB / {2:N1} MB ({3:N1}%) {4:N1} MB/s" -f $label, ($done / 1MB), ($total / 1MB), $percent, $speed
        }
        else {
            $text = "{0}: {1:N1} MB {2:N1} MB/s" -f $label, ($done / 1MB), $speed
        }
        & $Download._Print $text
    }

    # 成功回傳 $null，失敗回傳原因
    _Builtin  = {
        param($asset, [string]$filePath)

        # 區域變數先歸零：避免下載途中失敗時，finally 以動態作用域讀到外層同名變數（如 Tool.Update 的 $response）
        $failure = $null
        $response = $null
        $stream = $null
        $fileStream = $null
        $progressShown = $false

        try {
            $request = [System.Net.WebRequest]::Create($asset.browser_download_url)
            $request.UserAgent = $userAgent
            $response = $request.GetResponse()
            $stream = $response.GetResponseStream()

            # 大小優先取 GitHub API 的 size，備援用 HTTP Content-Length
            $total = $asset.size
            if (-not $total -or $total -le 0) { $total = $response.ContentLength }

            $fileStream = [System.IO.File]::Create($filePath)
            $buffer = [byte[]]::new(1MB)
            $readTotal = 0

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $lastUpdateMs = 0
            $lastShownBytes = 0

            & $Download._Progress '下載中' 0 $total 0
            $progressShown = $true

            while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $fileStream.Write($buffer, 0, $read)
                $readTotal += $read

                # 每 100ms 更新一次，不受百分比粒度限制
                $nowMs = $stopwatch.ElapsedMilliseconds
                if (($nowMs - $lastUpdateMs) -ge 100) {
                    $elapsedSec = [Math]::Max(($nowMs - $lastUpdateMs) / 1000.0, 0.001)
                    & $Download._Progress '下載中' $readTotal $total (($readTotal - $lastShownBytes) / 1MB / $elapsedSec)
                    $lastUpdateMs = $nowMs
                    $lastShownBytes = $readTotal
                }
            }

            # 收尾確保最後一幀一定輸出（時間節流可能吞掉）
            if ($readTotal -gt $lastShownBytes) {
                $elapsedSec = [Math]::Max($stopwatch.ElapsedMilliseconds - $lastUpdateMs, 1) / 1000.0
                & $Download._Progress '下載中' $readTotal $total (($readTotal - $lastShownBytes) / 1MB / $elapsedSec)
            }
        }
        catch {
            $failure = $_.Exception.GetBaseException().Message
        }
        finally {
            if ($fileStream) { $fileStream.Dispose() }
            if ($stream) { $stream.Dispose() }
            if ($response) { $response.Dispose() }

            # 結束進度列，避免後續訊息接在同一行
            if ($progressShown) { & $Download._EndLine }

            if ($null -ne $failure -and (Test-Path -LiteralPath $filePath)) { Remove-Item -LiteralPath $filePath -Force }
        }

        return $failure
    }

    Fetch     = {
        param($asset)

        $filePath = Join-Path $ctx.dir $asset.name
        & $Log.Info "下載: $filePath"

        # 有 IDM 且未停用 → 交由 IDM 下載（不跑內部進度列）
        if ($Idm.Exe -and -not $ctx.no_idm) { $failure = & $Idm.Run $asset $filePath }
        else { $failure = & $Download._Builtin $asset $filePath }

        if ($null -ne $failure) {
            & $Log.Err "下載失敗: $($asset.name) ($failure)"
            return $false
        }

        & $Log.Info "下載完成: $($asset.name)"

        & $Archive.Extract $filePath | Out-Null

        return $true
    }

    Pick      = {
        param($assets)

        $notWindowsExecutable = "(?i)linux|ubuntu|dos|mac|ios|uos|macos|apple|android|ohos"
        $notExecutable = "(?i)sha256|checksum|checksums|hash|source|src|debug|symbols|pdb|test|tests|sh|json"
        $notX64Architecture = "(?i)win32|wow32|arm(?:64)?|aarch64|i[3-6]86|x86(?![-_]?64)|32[-_ ]?bit|mips(?:64)?|ppc(?:64)?|powerpc|sparc|riscv(?:64)?|s390x?"

        # 如果有指定排除檔案名特徵
        $excludeRegex = $null
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
            & $Log.Warn "未找到包含 '$($ctx.asset_name)' 的資產, 改用自動檢測"
        }

        # ! 塞選條件以我個人使用為主, 並非通用性
        # 自動查找常見 windows x64 資產（只取分數最高的一個）
        return $assets |
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
    }
}

$Tool = @{
    # 查 API → 比版本 → 選資產 → 下載 → 解壓
    Update = {
        $response = & $Github.Latest

        # ? 測試用
        # & $Download.Pick $response.assets | ForEach-Object { write-host $_.name }
        # return

        if (-not $response -or -not ($response.tag_name -and $response.assets)) {
            & $Log.Err "無法取得版本資訊, 請檢查倉庫名稱與網路"
            $ctx.Status = 'ApiError'
            return
        }

        $tag = $response.tag_name
        $ctx.NewVersion = $tag

        $oldVersion = & $Ver.Parse $ctx.currentVersion
        $newVersion = & $Ver.Parse $tag

        if (-not $oldVersion) {
            if (-not $ctx.DownloadOnFirstRecord) {
                $ctx.Status = 'RecordOnly'
                return
            }
            if ($ctx.CheckOnly) {
                & $Log.Info "無法比對版本, 最新: $tag"
                $ctx.Status = 'HasUpdate'
                return
            }

            # -i 無紀錄或新路徑：視同首次下載，直接下載最新
            & $Log.Info "首次下載: $tag"
        }
        elseif ($oldVersion -eq $newVersion) {
            & $Log.Info "已是最新版本: $tag"
            $ctx.Status = 'UpToDate'
            return
        }
        elseif ($oldVersion -lt $newVersion) {
            & $Log.Info "有可用更新: $($ctx.currentVersion) -> $tag"

            if ($ctx.CheckOnly) {
                $ctx.Status = 'HasUpdate'
                return
            }
        }
        else {
            & $Log.Warn "本機版本較新: $oldVersion > $newVersion"
            $ctx.Status = 'Reset'
            return
        }

        $assets = & $Download.Pick $response.assets

        if (-not $assets) {
            & $Log.Warn "未找到適合的資產, 可用 -a 指定資產名稱"
            $ctx.Status = 'NoAsset'
            return
        }

        $failed = 0
        foreach ($asset in $assets) {
            if (-not (& $Download.Fetch $asset)) { $failed++ }
        }

        if ($failed -eq 0) {
            $ctx.Status = 'Updated'
        }
        else {
            $ctx.Status = 'Failed'
            & $Log.Err "版本紀錄未更新: $failed 個資產下載失敗"
        }
    }
}

# ===== 執行 =====

switch ($mode) {
    'uninstall' {
        # 解除紀錄綁定（不刪除任何已下載的檔案；不做路徑檢查）
        if (-not (& $Records.Load)) { break }

        # -un 吃 key 或完整網址（解析統一走 ParseRepo）
        $parsed = & $Cli.ParseRepo $uninstall
        $key = if ($parsed) { "$($parsed[0])/$($parsed[1])" } else { $uninstall }

        if (& $Records.Delete $key) { & $Log.Info "已移除紀錄: $key" }
        else { & $Log.Err "查無紀錄: $key" }
    }

    'install' {
        # 管理線：版本讀自統一紀錄；操作成功 → 整筆覆蓋寫回（不做逐欄合併）
        if (-not (& $Records.Load)) { break }

        $key = "$($ctx.owner)/$($ctx.repo)"
        $ctx.DownloadOnFirstRecord = $true

        if ($Records.Items.Contains($key)) {
            $rec = $Records.Items[$key]

            if ("$($rec.dir)" -eq $ctx.dir) {
                $ctx.currentVersion = "$($rec.version)"
            }
            else {
                & $Log.Warn "路徑與紀錄不同 ($($rec.dir)), 視為全新下載"
            }
        }

        & $Tool.Update

        if ($ctx.Status -in 'Updated', 'UpToDate', 'Reset') { & $Records.Upsert }
    }

    'list' {
        if (-not (& $Records.Load)) { break }

        & $Records.Show
    }

    { $_ -in @('check', 'all') } {
        # 批量線：-check 只檢查不下載（完全唯讀）；-all 用紀錄參數在紀錄的 dir 重放
        if (-not (& $Records.Load)) { break }

        $stats = @{ Updated = 0; UpToDate = 0; Failed = 0; Dead = 0 }
        $failedList = @()

        foreach ($key in @($Records.Items.Keys)) {
            $rec = $Records.Items[$key]

            & $Log.Info "`n[$key]"
            if (-not (Test-Path -LiteralPath "$($rec.dir)")) {
                & $Log.Err "路徑失效: $($rec.dir)"
                $stats.Dead++
                continue
            }

            try {
                $ctx = & $Records.ToCtx $key $rec
                $ctx.CheckOnly = ($mode -eq 'check')
                & $Tool.Update

                switch ($ctx.Status) {
                    'Updated' { $stats.Updated++; if ($mode -eq 'all') { & $Records.Upsert } }
                    'HasUpdate' { $stats.Updated++ }
                    'UpToDate' { $stats.UpToDate++ }
                    'Reset' { $stats.UpToDate++; if ($mode -eq 'all') { & $Records.Upsert } }
                    default { $stats.Failed++; $failedList += "$key ($($ctx.Status))" }
                }
            }
            catch {
                & $Log.Err "執行失敗: $($_.Exception.Message)"
                $stats.Failed++
                $failedList += "$key (例外: $($_.Exception.Message))"
            }
        }

        $updatedLabel = if ($mode -eq 'check') { '可更新' } else { '已更新' }
        Write-Host ""
        Write-Host ("彙總: {0} {1} | 已最新 {2} | 失敗 {3} | 路徑失效 {4}" -f $updatedLabel, $stats.Updated, $stats.UpToDate, $stats.Failed, $stats.Dead) -ForegroundColor Cyan
        foreach ($f in $failedList) { & $Log.Err "  失敗: $f" }
    }

    'single' {
        # 單發線：版本讀自標記檔
        $ctx.currentVersion = & $Ver.Get

        & $Tool.Update

        # 收尾：依狀態寫回標記檔
        if ($ctx.Status -in 'RecordOnly', 'Updated', 'Reset') { & $Ver.Set $ctx.NewVersion }
    }
}

Read-Host "`n按 Enter 退出"