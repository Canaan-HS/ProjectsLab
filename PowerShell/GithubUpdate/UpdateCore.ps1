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

GitHub Asset Update Tool

使用:
  gau.exe <GitHub 網址> [選項]
  gau.exe -o <owner> -r <repo> [選項]

選項:
  -u, -url <url>                 https://github.com/owner/repo
  -o, -owner <name>              GitHub owner
  -r, -repo <name>               GitHub repository
  -a, -asset_name <name>         Asset name keyword
  -e, -exclude_patterns <list>   Exclude patterns (comma separated)
  -ae, -auto_extract             Auto extract downloaded archive
  -ni, -no_idm                   停用 IDM 偵測，強制使用內建下載器
  -h, -help                      Show this help

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

    $url = $asset.browser_download_url
    $assetName = $asset.name

    # 呼叫前 IDM 是否已在執行（決定能否用 /q 與進程監控）
    $idmWasRunning = [bool](Get-Process IDMan -ErrorAction SilentlyContinue)

    # 呼叫前快照 registry 最大下載 ID（用來識別新下載 失敗則退回純檔案輪詢）
    $idmRegBase = 'HKCU:\Software\DownloadManager'
    $maxIdBefore = 0
    try {
        $mv = Get-ItemProperty "$idmRegBase\maxID" -ErrorAction SilentlyContinue
        if ($mv -and $mv.maxID) { $maxIdBefore = [int]$mv.maxID }
    }
    catch { $maxIdBefore = 0 }

    # /n：靜默模式，不跳對話框直接開始下載
    # /q：只在我們自己啟動 IDM 時加（官方註明只在第一個 copy 有效），下載完成後 IDM 退出
    # 參數以單一字串傳入（自行加引號），確保 5.1/7.x 行為一致
    $idmArgs = "/n /d `"$url`" /p `"$callPath`" /f `"$($asset.name)`""
    if (-not $idmWasRunning) { $idmArgs += ' /q' }

    try {
        Start-Process -FilePath $idmExe -ArgumentList $idmArgs -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Host "呼叫 IDM 失敗: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }

    # 等待完成（1 秒輪詢）
    # 進度來源：IDM registry 的 Downloaded/FileSize/Speed（讀不到時顯示純文字）
    # 狀態原文：1=下載中、2=暫停/停止、3=完成（IDM 6.43 實測）
    $expectedSize = 0
    if ($asset.size -and $asset.size -gt 0) { $expectedSize = [long]$asset.size }

    $timeout = [TimeSpan]::FromMinutes(30)
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $lastSize = -1
    $stableCount = 0

    $regEntryId = $null      # 鎖定後 IDM registry 的 key
    $regSearchTimeout = 20   # 找不到對應 key 就放棄監看（退回純檔案輪詢）
    $stoppedCount = 0        # Status=2（暫停/停止）連續次數
    $goneCount = 0           # 對應 key 從 registry 消失的連續次數
    $progressShown = $false

    [Console]::Write("`rIDM 下載中 ...")
    $progressShown = $true

    while ($true) {
        Start-Sleep -Seconds 1

        # --- 檔案大小（成功判定的最終依據）---
        $size = -1
        if (Test-Path $filePath) {
            $item = Get-Item $filePath -ErrorAction SilentlyContinue
            if ($item) { $size = $item.Length }
        }

        if ($size -eq $lastSize) { $stableCount++ } else { $stableCount = 0; $lastSize = $size }

        # 完成判定
        if ($size -gt 0) {
            if ($expectedSize -gt 0) {
                if ($size -ge $expectedSize) {
                    if ($progressShown) { Write-Host "" }
                    Write-Host "IDM 下載完成: $assetName"
                    return $true
                }
            }
            elseif ($stableCount -ge 6) {
                if ($progressShown) { Write-Host "" }
                Write-Host "IDM 下載完成: $assetName"
                return $true
            }
        }

        # --- IDM registry 狀態監看 ---
        $regStatus = $null; $regDl = $null; $regFs = $null; $regSpeed = $null

        # 搜尋 ID 大於快照、且 Url0 或 Host+檔名 相符
        if (-not $regEntryId -and $maxIdBefore -gt 0 -and $stopwatch.Elapsed.TotalSeconds -le $regSearchTimeout) {
            try {
                $cands = @(Get-ChildItem $idmRegBase -ErrorAction SilentlyContinue |
                    Where-Object { $_.PSChildName -match '^\d+$' -and [int]$_.PSChildName -gt $maxIdBefore } |
                    Sort-Object { [int]$_.PSChildName })
                foreach ($cand in $cands) {
                    $cv = Get-ItemProperty $cand.PSPath -ErrorAction SilentlyContinue
                    if (-not $cv) { continue }
                    $isOurs = $false
                    if ($cv.Url0 -and $cv.Url0 -eq $url) { $isOurs = $true }
                    else {
                        try {
                            $u = [Uri]$url
                            $leaf = [System.IO.Path]::GetFileName($u.AbsolutePath)
                            if ($leaf -and $cv.Host -eq $u.Host -and $cv.FileName -eq $leaf) { $isOurs = $true }
                        }
                        catch {}
                    }
                    if ($isOurs) { $regEntryId = $cand.PSChildName; break }
                }
            }
            catch {}
        }

        if ($regEntryId) {
            $ev = Get-ItemProperty "$idmRegBase\$regEntryId" -ErrorAction SilentlyContinue
            if ($ev) {
                $goneCount = 0
                $regStatus = $ev.Status
                if ($null -ne $ev.Downloaded) { try { $regDl = [BitConverter]::ToInt64([byte[]]$ev.Downloaded, 0) } catch {} }
                if ($null -ne $ev.FileSize) { try { $regFs = [BitConverter]::ToInt64([byte[]]$ev.FileSize, 0) } catch {} }
                if ($null -ne $ev.Speed) { $regSpeed = $ev.Speed }

                # 快速失敗：使用者暫停/停止下載（Status=2）
                if ($regStatus -eq 2) { $stoppedCount++ } else { $stoppedCount = 0 }
                if ($stoppedCount -ge 2) {
                    # 再確認一次（防瞬態，例如暫停後立刻續傳）
                    Start-Sleep -Seconds 1
                    $ev2 = Get-ItemProperty "$idmRegBase\$regEntryId" -ErrorAction SilentlyContinue
                    if ($ev2 -and $ev2.Status -eq 2) {
                        if ($size -gt 0 -and $expectedSize -gt 0 -and $size -ge $expectedSize) {
                            if ($progressShown) { Write-Host "" }
                            Write-Host "IDM 下載完成: $assetName"
                            return $true
                        }
                        if ($progressShown) { Write-Host "" }
                        Write-Host "IDM 下載已暫停/停止，視為失敗。" -ForegroundColor Red
                        return $false
                    }
                    $stoppedCount = 0
                }
            }
            else {
                # 快速失敗：項目從清單被移除（取消/刪除）
                $goneCount++
                if ($goneCount -ge 2) {
                    if ($size -gt 0 -and $expectedSize -gt 0 -and $size -ge $expectedSize) {
                        if ($progressShown) { Write-Host "" }
                        Write-Host "IDM 下載完成: $assetName"
                        return $true
                    }
                    if ($progressShown) { Write-Host "" }
                    Write-Host "IDM 下載項目已從清單移除（可能已取消），視為失敗。" -ForegroundColor Red
                    return $false
                }
            }
        }

        # --- 進度列 ---
        if ($null -ne $regDl) {
            $speedMb = 0.0
            if ($null -ne $regSpeed -and $regSpeed -gt 0) { $speedMb = $regSpeed / 1MB }
            if ($null -ne $regFs -and $regFs -gt 0) {
                $pct = [Math]::Min(100.0, $regDl * 100.0 / $regFs)
                $line = "IDM 下載中: {0,7:N1} MB / {1,7:N1} MB ({2,5:N1}%) {3,6:N1} MB/s" -f ($regDl / 1MB), ($regFs / 1MB), $pct, $speedMb
            }
            else {
                $line = "IDM 下載中: {0,7:N1} MB {1,6:N1} MB/s" -f ($regDl / 1MB), $speedMb
            }
        }
        else {
            $line = "IDM 下載中 ..."
        }
        [Console]::Write("`r" + $line + "    ")

        # --- 案例 A： IDM 整個消失且檔案不完整 → 快速視為失敗 ---
        # （idman.exe 只是 launcher stub，真正主體是另一個進程，所以檢查整個 IDM）
        # 啟動後前 10 秒不判定，避免 stub/主體交接的空窗期
        if (-not $idmWasRunning -and $stopwatch.Elapsed.TotalSeconds -ge 10 -and
            -not (Get-Process IDMan -ErrorAction SilentlyContinue)) {

            # 給最終檔案落地一點時間，再確認一次
            Start-Sleep -Seconds 1
            $finalSize = -1
            if (Test-Path $filePath) {
                $finalItem = Get-Item $filePath -ErrorAction SilentlyContinue
                if ($finalItem) { $finalSize = $finalItem.Length }
            }

            if ($finalSize -gt 0 -and ($expectedSize -le 0 -or $finalSize -ge $expectedSize)) {
                if ($progressShown) { Write-Host "" }
                Write-Host "IDM 下載完成: $assetName"
                return $true
            }

            if ($progressShown) { Write-Host "" }
            Write-Host "IDM 已結束但檔案不完整（可能取消或失敗）。" -ForegroundColor Red
            return $false
        }

        if ($stopwatch.Elapsed -ge $timeout) {
            if ($progressShown) { Write-Host "" }
            Write-Host "等待 IDM 下載逾時（30 分鐘），視為失敗。" -ForegroundColor Red
            return $false
        }
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