param (
    [Parameter(Position = 0)]
    [Alias("u")]
    [string]$url = "",

    [Alias("o")]
    [string]$owner = "",

    [Alias("r")]
    [string]$repo = "",

    [Alias("a")]
    [string]$asset_name = $null,

    [Alias("e")]
    [string]$exclude_patterns = $null,

    [Alias("ae")]
    [switch]$auto_extract = $null,

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

選項:
  -u, -url <url>                 GitHub 儲存庫網址
  -o, -owner <name>              GitHub 儲存庫擁有者
  -r, -repo <name>               GitHub 儲存庫名稱
  -a, -asset_name <name>         資產檔名關鍵字
  -e, -exclude_patterns <list>   排除關鍵字（逗號分隔）
  -ae, -auto_extract             下載後自動解壓縮
  -ni, -no_idm                   停用 IDM 偵測，強制使用內建下載器
  -h, -help                      顯示本說明

範例:
  gau https://github.com/owner/repo
  gau -o user -r app
  gau -o user -r app -a "software_x64_portable.exe"
  gau -o user -r app -e "debug,source"

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

if ($help -or $PSBoundParameters.Count -eq 0) { ShowHelp }

if ($url -match '(?i)^https://github\.com/([^/]+)/([^/]+)') {
    $owner = $matches[1]
    $repo = $matches[2]
}

if (-not $owner -or -not $repo) {
    Write-Host "參數 -owner 和 -repo 是必需的" -ForegroundColor Red
    ShowHelp
}

# ===== 核心程式 =====

$callPath = (Get-Location).Path

$versionRecordTemplate = "! Version - $repo - {0}"
$prefix = $versionRecordTemplate -replace '\{0\}', ''
$userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36"

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

# 取得版本文件
$versionFile = Get-ChildItem -Path $callPath -File -Filter "$prefix*" |
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
        Rename-Item -Path $versionFile.FullName -NewName $newName -Force
        Write-Host "版本紀錄修改: $version"
    }
    else {
        New-Item -ItemType File -Path (Join-Path $callPath $newName) | Out-Null
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

function GetDownloadInfo {
    param($assets)

    $notWindowsExecutable = "(?i)linux|ubuntu|dos|mac|ios|uos|macos|apple|android|ohos"
    $notExecutable = "(?i)sha256|checksum|checksums|hash|source|src|debug|symbols|pdb|test|tests|sh|json"
    $notX64Architecture = "(?i)win32|wow32|arm(?:64)?|aarch64|i[3-6]86|x86(?![-_]?64)|32[-_ ]?bit|mips(?:64)?|ppc(?:64)?|powerpc|sparc|riscv(?:64)?|s390x?"

    # 如果有指定排除檔案名特徵
    if ($exclude_patterns) {
        $excludeRegex = "(?i)" + (($exclude_patterns -split ',' | ForEach-Object {
                    [regex]::Escape($_.Trim())
                }) -join '|')
    }

    # 如果有指定下載特定檔案名稱，用包含匹配（忽略大小寫）
    if ($asset_name) {
        $matched = $assets | Where-Object {
            $_.name.Contains($asset_name) -and
            -not ($excludeRegex -and $_.name -match $excludeRegex) -and
            $_.name -notmatch $notExecutable -and
            $_.name -notmatch $notWindowsExecutable -and
            $_.name -notmatch $notX64Architecture
        }
        if ($matched -and $matched.name) { return $matched }
        Write-Host "未找到包含 '$asset_name' 的資產，使用自動檢測。" -ForegroundColor Yellow
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

    try {
        Remove-Item -Path $filePath -Force -ErrorAction Stop
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
    $downloadUrl   = $asset.browser_download_url
    $assetName     = $asset.name
    $githubSize    = if ($asset.size -gt 0) { [long]$asset.size } else { 0 }
    $idmWasRunning = [bool](Get-Process IDMan -ErrorAction SilentlyContinue)
    $idmRegistryPath = 'Software\DownloadManager'

    # --- 啟動前快照 ---
    # 只追蹤呼叫後新出現的數字 key，避免誤認舊下載。
    $initialKeyIds = [System.Collections.Generic.HashSet[string]]::new()
    $snapshotRoot = $null
    try {
        $snapshotRoot = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($idmRegistryPath)
        if ($snapshotRoot) {
            foreach ($name in $snapshotRoot.GetSubKeyNames()) {
                if ($name -match '^\d+$') { [void]$initialKeyIds.Add($name) }
            }
        }
    }
    catch {}
    finally { if ($snapshotRoot) { $snapshotRoot.Dispose() } }

    # --- 啟動 IDM ---
    # /n 靜默下載；/q 只在 IDM 原本未執行時使用（完成後會退出）。
    # 路徑結尾反斜線會吃掉結尾引號，先加倍。
    $quotedCallPath = $callPath -replace '(\\+)$', '$1$1'
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
    # 讀不到時退回 registry；完成／失敗仍以 registry 與檔案大小為準。
    $progressApiReady = $false
    try {
        if (-not ('GauIdmProgressWindow' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;

public class GauIdmProgress {
    public double Percent = -1;
    public long Downloaded;
    public long Speed;
}

public static class GauIdmProgressWindow {
    private delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc cb, IntPtr p);
    [DllImport("user32.dll")] private static extern bool EnumChildWindows(IntPtr hWnd, EnumProc cb, IntPtr p);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassName(IntPtr hWnd, StringBuilder sb, int max);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);

    private static readonly Regex DownloadedRegex = new Regex(@"([0-9][0-9.,]*)\s*MB\s*\(\s*([0-9][0-9.,]*)\s*%", RegexOptions.IgnoreCase | RegexOptions.Compiled);
    private static readonly Regex SpeedRegex = new Regex(@"([0-9][0-9.,]*)\s*(MB|KB)\s*/\s*(?:s|sec|秒)", RegexOptions.IgnoreCase | RegexOptions.Compiled);

    private static string ClassOf(IntPtr hWnd) { StringBuilder sb = new StringBuilder(128); GetClassName(hWnd, sb, sb.Capacity); return sb.ToString(); }
    private static string TextOf(IntPtr hWnd) { StringBuilder sb = new StringBuilder(512); GetWindowText(hWnd, sb, sb.Capacity); return sb.ToString(); }

    private static bool IsPopup(IntPtr hWnd) {
        bool found = false;
        EnumChildWindows(hWnd, delegate(IntPtr child, IntPtr p) {
            string cls = ClassOf(child);
            found = cls == "msctls_progress32" || cls == "IDM DownloadProgressComponent class";
            return !found;
        }, IntPtr.Zero);
        return found;
    }

    private static bool TitleMatches(string title, string assetName) {
        if (String.IsNullOrEmpty(title) || String.IsNullOrEmpty(assetName)) return false;
        title = title.Trim();
        if (title.Equals(assetName, StringComparison.OrdinalIgnoreCase)) return true;
        if (!title.EndsWith(assetName, StringComparison.OrdinalIgnoreCase)) return false;
        int index = title.Length - assetName.Length;
        return index <= 0 || " -(%".IndexOf(title[index - 1]) >= 0;
    }

    public static IntPtr Find(string assetName) {
        IntPtr found = IntPtr.Zero;
        EnumWindows(delegate(IntPtr hWnd, IntPtr p) {
            if (ClassOf(hWnd) != "#32770") return true;
            if (!TitleMatches(TextOf(hWnd), assetName)) return true;
            if (!IsPopup(hWnd)) return true;
            found = hWnd;
            return false;
        }, IntPtr.Zero);
        return found;
    }

    private static double Number(string text) {
        double value;
        if (Double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out value)) return value;
        if (Double.TryParse(text, NumberStyles.Float, CultureInfo.CurrentCulture, out value)) return value;
        if (text.IndexOf(',') >= 0) text = text.IndexOf('.') >= 0 ? text.Replace(",", "") : text.Replace(',', '.');
        return Double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out value) ? value : -1;
    }

    public static GauIdmProgress Read(IntPtr hWnd) {
        if (hWnd == IntPtr.Zero || !IsWindow(hWnd)) return null;

        GauIdmProgress data = new GauIdmProgress();
        string title = TextOf(hWnd);
        int percentIndex = title.IndexOf('%');
        if (percentIndex > 0) {
            double titlePercent = Number(title.Substring(0, percentIndex).Trim());
            if (titlePercent >= 0) data.Percent = titlePercent;
        }

        EnumChildWindows(hWnd, delegate(IntPtr child, IntPtr p) {
            if (ClassOf(child) != "Static") return true;

            string text = TextOf(child);
            if (String.IsNullOrEmpty(text)) return true;

            Match downloaded = DownloadedRegex.Match(text);
            if (downloaded.Success) {
                double mb = Number(downloaded.Groups[1].Value), pct = Number(downloaded.Groups[2].Value);
                if (mb >= 0) data.Downloaded = (long)Math.Round(mb * 1048576.0);
                if (pct >= 0) data.Percent = pct;
            }

            Match speed = SpeedRegex.Match(text);
            if (speed.Success) {
                double value = Number(speed.Groups[1].Value);
                double factor = speed.Groups[2].Value.Equals("KB", StringComparison.OrdinalIgnoreCase) ? 1024.0 : 1048576.0;
                if (value >= 0) data.Speed = (long)Math.Round(value * factor);
            }

            return true;
        }, IntPtr.Zero);

        return (data.Percent >= 0 || data.Downloaded > 0 || data.Speed > 0) ? data : null;
    }
}
'@
        }
        $progressApiReady = $true
    }
    catch {}

    # --- 監控參數 ---
    # registry 搜尋：前 2 秒 50ms、之後 200ms，最多 30 秒。
    # 找到後：有彈窗 250ms，否則 1 秒。
    $fastScanIntervalMs = 50; $fastScanDurationMs = 2000; $slowScanIntervalMs = 200
    $searchTimeoutMs = 30000; $progressIntervalMs = 1000
    $popupIntervalMs = 250; $popupSearchTimeoutMs = 15000

    # 完成與失敗判定。
    $fileStableLimitMs = 6000; $confirmMs = 1000
    $processCheckIntervalMs = 1000; $idmShutdownGraceMs = 10000
    $downloadTimeout = [TimeSpan]::FromMinutes(30)

    $timer               = [System.Diagnostics.Stopwatch]::StartNew()
    $downloadId          = $null
    $progressWindow      = [IntPtr]::Zero
    $lastFileSize        = -1
    $fileSizeChangedAtMs = 0
    $problemAtMs         = $null
    $lastProcessCheckMs  = $null
    $highestPercentShown = -1.0

    # --- 輸出 ---
    $consoleState = @{ LastLength = 0 }

    function Write-IdmText {
        param([string]$Text)
        $padding = $consoleState.LastLength - $Text.Length
        if ($padding -gt 0) { $Text += ' ' * $padding }
        [Console]::Write("`r$Text")
        $consoleState.LastLength = $Text.Length
    }

    function Write-IdmLine {
        param([long]$Downloaded, [long]$Total, [double]$Percent, [double]$SpeedMB)
        if ($Total -gt 0) {
            $line = "IDM 下載中: {0:N1} MB / {1:N1} MB ({2:N1}%) {3:N1} MB/s" -f `
                ($Downloaded / 1MB), ($Total / 1MB), $Percent, $SpeedMB
        }
        else {
            $line = "IDM 下載中: {0:N1} MB {1:N1} MB/s" -f ($Downloaded / 1MB), $SpeedMB
        }
        Write-IdmText $line
    }

    function Complete-IdmDownload {
        param([long]$Total)
        if ($Total -le 0) { $Total = 1 }
        Write-IdmLine -Downloaded $Total -Total $Total -Percent 100 -SpeedMB 0
        Write-Host "`nIDM 下載完成: $assetName"
    }

    function Write-IdmFailure {
        param([string]$Message)
        Write-Host "`n$Message" -ForegroundColor Red
    }

    function Get-TargetFileSize {
        try {
            $info = [System.IO.FileInfo]::new($filePath)
            if ($info.Exists) { return $info.Length }
        }
        catch {}
        return -1
    }

    # --- registry 存取 ---
    # Downloaded / FileSize 是 8-byte little-endian；Status / Speed 是 Int32。
    function Convert-IdmQword {
        param($Value)
        if ($Value -isnot [byte[]]) { return $null }
        if ($Value.Length -ge 8) { return [BitConverter]::ToInt64($Value, 0) }
        if ($Value.Length -eq 4) { return [BitConverter]::ToUInt32($Value, 0) }
        return $null
    }

    function Get-IdmEntryState {
        param([string]$KeyId)
        $state = [pscustomobject]@{ Found = $false; Status = $null; Downloaded = $null; FileSize = $null; Speed = $null }
        $root = $null; $key = $null
        try {
            $root = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($idmRegistryPath)
            if (-not $root) { return $state }
            $key = $root.OpenSubKey($KeyId)
            if (-not $key) { return $state }

            $state.Found = $true
            $state.Status = $key.GetValue('Status')
            $state.Speed = $key.GetValue('Speed')
            $state.Downloaded = Convert-IdmQword ($key.GetValue('Downloaded'))
            $state.FileSize = Convert-IdmQword ($key.GetValue('FileSize'))
        }
        catch {}
        finally { if ($key) { $key.Dispose() }; if ($root) { $root.Dispose() } }
        return $state
    }

    function Find-IdmEntryId {
        $root = $null; $bestId = $null
        try {
            $root = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($idmRegistryPath)
            if (-not $root) { return $null }

            foreach ($name in $root.GetSubKeyNames()) {
                $keyId = 0
                if (-not [int]::TryParse($name, [ref]$keyId)) { continue }
                if ($initialKeyIds.Contains($name)) { continue }
                if ($null -ne $bestId -and $keyId -ge $bestId) { continue }

                $key = $root.OpenSubKey($name)
                if (-not $key) { continue }
                try {
                    # Url0 是原始 URL；Referer 是 GitHub 頁面。FileName 是帶簽章 URL，不能比對。
                    $url0 = [string]$key.GetValue('Url0')
                    $referer = [string]$key.GetValue('Referer')
                    if ($url0.Trim() -eq $downloadUrl -or $referer.Trim() -eq $downloadUrl) { $bestId = $keyId }
                }
                finally { $key.Dispose() }
            }
        }
        catch {}
        finally { if ($root) { $root.Dispose() } }

        if ($null -ne $bestId) { return [string]$bestId }
        return $null
    }

    function Test-IdmFileComplete {
        param([long]$Size, [switch]$AllowUnknownSize)
        if ($Size -le 0) { return $false }
        if ($githubSize -gt 0) { return $Size -ge $githubSize }
        return [bool]$AllowUnknownSize
    }

    # --- 主迴圈 ---
    Write-IdmText "IDM 下載中 ..."
    $nextTickMs = $timer.ElapsedMilliseconds

    while ($true) {
        $nowMs = $timer.ElapsedMilliseconds
        $isSearching = (-not $downloadId -and $nowMs -le $searchTimeoutMs)

        # --- 讀取彈窗 ---
        $popupProgress = $null
        if ($progressApiReady) {
            if ($progressWindow -eq [IntPtr]::Zero -and $nowMs -le $popupSearchTimeoutMs) {
                $progressWindow = [GauIdmProgressWindow]::Find($assetName)
            }
            if ($progressWindow -ne [IntPtr]::Zero) {
                $popupProgress = [GauIdmProgressWindow]::Read($progressWindow)
                if ($null -eq $popupProgress -and -not [GauIdmProgressWindow]::IsWindow($progressWindow)) {
                    $progressWindow = [IntPtr]::Zero
                }
            }
        }

        # --- 尋找並讀取本次下載項目 ---
        if ($isSearching) { $downloadId = Find-IdmEntryId }

        $idmState = if ($downloadId) { Get-IdmEntryState -KeyId $downloadId } else { $null }
        $entryMissing = $null -ne $idmState -and (-not $idmState.Found -or $null -eq $idmState.Status)

        # --- 檔案大小 ---
        $fileSize = Get-TargetFileSize
        if ($fileSize -ne $lastFileSize) {
            $lastFileSize = $fileSize
            $fileSizeChangedAtMs = $nowMs
        }

        # --- 完成判定 ---
        # registry Status=3 優先；其次才是檔案大小。
        if ($null -ne $idmState -and $idmState.Status -eq 3 -and $fileSize -gt 0) {
            $finalTotal = [Math]::Max([long]$fileSize, [long]$githubSize)
            if ($idmState.FileSize -gt $finalTotal) { $finalTotal = [long]$idmState.FileSize }
            Complete-IdmDownload -Total $finalTotal
            return $true
        }

        if (Test-IdmFileComplete $fileSize) {
            Complete-IdmDownload -Total ([Math]::Max($githubSize, $fileSize))
            return $true
        }
        if ($githubSize -le 0 -and $fileSize -gt 0 -and
            ($nowMs - $fileSizeChangedAtMs) -ge $fileStableLimitMs) {
            Complete-IdmDownload -Total $fileSize
            return $true
        }

        # --- 失敗判定：暫停或項目移除 ---
        $problemKind = if ($null -ne $idmState -and $idmState.Status -eq 2) { 'paused' } elseif ($entryMissing) { 'missing' }

        if ($problemKind) {
            if ($null -eq $problemAtMs) {
                $problemAtMs = $nowMs
            }
            elseif (($nowMs - $problemAtMs) -ge $confirmMs) {
                $persists = $true
                if ($problemKind -eq 'paused') {
                    # 暫停後可能立刻續傳，再確認一次。
                    Start-Sleep -Milliseconds $progressIntervalMs
                    $persists = ((Get-IdmEntryState -KeyId $downloadId).Status -eq 2)
                }

                if ($persists) {
                    if (Test-IdmFileComplete $fileSize) {
                        Complete-IdmDownload -Total ([Math]::Max($githubSize, $fileSize))
                        return $true
                    }

                    $message = if ($problemKind -eq 'paused') { 'IDM 下載已暫停/停止，視為失敗。' }
                               else { 'IDM 下載項目已從清單移除（可能已取消），視為失敗。' }
                    Write-IdmFailure $message
                    return $false
                }

                $problemAtMs = $null
            }
        }
        else {
            $problemAtMs = $null
        }

        # --- 顯示進度 ---
        # 彈窗是即時值；registry 約 2–3 秒才更新，只當備援。
        $totalBytes = if ($null -ne $idmState -and [long]$idmState.FileSize -gt 0) {
            [long]$idmState.FileSize
        }
        elseif ($githubSize -gt 0) { [long]$githubSize }
        else { 0 }

        $downloaded = $null; $percent = 0.0; $speedMB = 0.0

        if ($null -ne $popupProgress -and $popupProgress.Percent -ge 0 -and
            ($popupProgress.Downloaded -gt 0 -or $totalBytes -gt 0)) {

            $percent = [Math]::Min(100.0, [Math]::Max(0.0, $popupProgress.Percent))
            $downloaded = [long]$popupProgress.Downloaded
            if ($downloaded -le 0 -and $totalBytes -gt 0) {
                $downloaded = [long]($totalBytes * $percent / 100.0)
            }
            $speedMB = $popupProgress.Speed / 1MB
        }
        elseif ($null -ne $idmState -and $null -ne $idmState.Downloaded) {
            $downloaded = [long]$idmState.Downloaded
            if ($totalBytes -gt 0) {
                $percent = [Math]::Min(100.0, $downloaded * 100.0 / $totalBytes)
            }
            if ($null -ne $idmState.Speed -and $idmState.Speed -gt 0) {
                $speedMB = $idmState.Speed / 1MB
            }
        }

        if ($null -ne $downloaded) {
            # IDM 重連時 Downloaded 可能回落，顯示值只前進不倒退。
            $highestPercentShown = [Math]::Max($highestPercentShown, $percent)
            Write-IdmLine -Downloaded $downloaded -Total $totalBytes `
                -Percent $highestPercentShown -SpeedMB $speedMB
        }
        else {
            Write-IdmText "IDM 下載中 ..."
        }

        # 重新取樣時間，避免輸出造成判定延遲。
        $nowMs = $timer.ElapsedMilliseconds

        # --- 失敗判定：IDM 程序消失 ---
        # idman.exe 只是啟動器；啟動後前 10 秒不判定。
        if (-not $idmWasRunning -and $nowMs -ge $idmShutdownGraceMs -and
            ($null -eq $lastProcessCheckMs -or ($nowMs - $lastProcessCheckMs) -ge $processCheckIntervalMs)) {
            $lastProcessCheckMs = $nowMs
            if (-not (Get-Process IDMan -ErrorAction SilentlyContinue)) {
                # 給最終檔案落地一點時間，再確認一次。
                Start-Sleep -Milliseconds 1000
                $finalSize = Get-TargetFileSize

                if (Test-IdmFileComplete $finalSize -AllowUnknownSize) {
                    Write-Host "`nIDM 下載完成: $assetName"
                    return $true
                }

                Write-IdmFailure 'IDM 已結束但檔案不完整（可能取消或失敗）。'
                return $false
            }
        }

        # --- 失敗判定：逾時 ---
        if ($timer.Elapsed -ge $downloadTimeout) {
            Write-IdmFailure '等待 IDM 下載逾時（30 分鐘），視為失敗。'
            return $false
        }

        # --- 排程（絕對時間格線，避免漂移）---
        $scheduleNowMs = $timer.ElapsedMilliseconds
        $intervalMs = if (-not $downloadId -and $scheduleNowMs -le $searchTimeoutMs) {
            if ($scheduleNowMs -lt $fastScanDurationMs) { $fastScanIntervalMs } else { $slowScanIntervalMs }
        }
        elseif ($progressApiReady -and
            ($progressWindow -ne [IntPtr]::Zero -or $scheduleNowMs -le $popupSearchTimeoutMs)) { $popupIntervalMs }
        else { $progressIntervalMs }

        $nextTickMs += $intervalMs
        if ($nextTickMs -lt $scheduleNowMs) { $nextTickMs = $scheduleNowMs }

        $sleepMs = $nextTickMs - $scheduleNowMs
        if ($sleepMs -gt 0) { Start-Sleep -Milliseconds $sleepMs }
    }
}

function DownloadAsset {
    param($asset)

    $url = $asset.browser_download_url
    $filePath = Join-Path $callPath $asset.name

    Write-Host "下載資產: $($asset.name)"
    Write-Host "下載位置: $filePath"
    Write-Host "下載網址: $url"

    # 有 IDM 且未停用 → 交由 IDM 下載（不跑內部進度列）
    if ($idmExe -and -not $no_idm) {
        $ok = InvokeIdmDownload -asset $asset -filePath $filePath

        if ($ok -and $auto_extract) { AutoExtract -filePath $filePath | Out-Null }

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
                [Console]::Write(("`r下載中: {0,7:N1} MB / {1,7:N1} MB ({2,5:N1}%) {3,6:N1} MB/s" -f ($readTotal / 1MB), ($total / 1MB), $percent, $speed))
            }
            else {
                [Console]::Write(("`r下載中: {0,7:N1} MB {1,6:N1} MB/s" -f ($readTotal / 1MB), $speed))
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

        if (-not $ok -and (Test-Path $filePath)) { Remove-Item $filePath -Force }
    }

    if (-not $ok) {
        Write-Host "下載失敗: $errMsg" -ForegroundColor Red
        return $false
    }

    Write-Host "下載完成: $($asset.name)"

    if ($auto_extract) { AutoExtract -filePath $filePath | Out-Null }

    return $true
}

function SendRequest {
    $response = Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repo/releases/latest" -Headers @{ "User-Agent" = $userAgent }

    # ? 測試用
    # GetDownloadInfo -assets $response.assets | ForEach-Object { write-host $_.name }
    # return

    if (-not $response -or -not ($response.tag_name -and $response.assets)) {
        Write-Host "無法獲取最新版本資訊，請檢查倉庫名稱和網絡連接。" -ForegroundColor Red
        return
    }

    $oldVersion = ParseVersion (GetVersion)
    $newVersion = ParseVersion $response.tag_name

    if (-not $oldVersion) {
        Write-Host "未找到之前的版本。"
        SetVersion $response.tag_name
        return
    }

    if ($oldVersion -eq $newVersion) {
        Write-Host "已是最新版本。`n當前版本: $($response.tag_name)"
    }
    elseif ($oldVersion -lt $newVersion) {
        Write-Host "有可用更新: $($response.tag_name) (目前版本: $oldVersion)"
        $downloadInfo = GetDownloadInfo -assets $response.assets

        if ($downloadInfo) {
            Write-Host "下載版本: $($response.tag_name)"

            $failed = @()
            foreach ($asset in $downloadInfo) {
                if (-not (DownloadAsset -asset $asset)) { $failed += $asset.name }
            }

            if ($failed.Count -eq 0) {
                SetVersion $response.tag_name
            }
            else {
                Write-Host "有 $($failed.Count) 個資產下載失敗，版本記錄未更新，下次執行會重新嘗試：" -ForegroundColor Red
                foreach ($name in $failed) { Write-Host "  - $name" -ForegroundColor Red }
            }
        }
        else {
            Write-Host "未找到適合下載的資產。請檢查倉庫的發布頁面以確保有適合 Windows 的資產，或使用 -asset_name 參數指定資產名稱。" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "本機版本 ($oldVersion) 比最新發布版本 ($newVersion) 更新。 版本記錄已重置。" -ForegroundColor Yellow
        SetVersion $response.tag_name
    }
}

SendRequest
Read-Host "`n按任意鍵退出"