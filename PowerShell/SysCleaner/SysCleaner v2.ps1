[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Input {
    param (
        [string]$text,
        [string]$foregroundColor = 'default'
    )

    if ($foregroundColor -eq 'default') {
        return Read-Host "`n[37m[7m[1m$text[27m"
    } else {
        $Host.UI.RawUI.ForegroundColor = [ConsoleColor]::$foregroundColor
        $Host.UI.RawUI.BackgroundColor = [ConsoleColor]::'Black'
        return Read-Host "`n[1m$text"
    }
}

function Print {
    param (
        [string]$text,
        [string]$foreColor = 'White',
        [string]$backColor = 'Black'
    )
    Write-Host "[1m$text" -ForegroundColor $foreColor -BackgroundColor $backColor
}

function Delete {
    param (
        [Object]$RemoveObject
    )

    foreach ($path in @($RemoveObject)) {
        # 判斷是否為多層通配
        $isMultiWildcard = $path -match '\\[^\\]*\*[^\\]*\\'

        # 展開多層通配或直接處理
        $targets = $isMultiWildcard ? (Get-ChildItem -Path $path -Directory -ErrorAction SilentlyContinue) : ((Test-Path $path) ? @($path) : @())

        foreach ($item in $targets) {
            try {
                $targetPath = if ($item -is [System.IO.FileSystemInfo]) { $item.FullName } else { $item }
                Remove-Item -Path $targetPath -Recurse -Force -ErrorAction SilentlyContinue
                Print "清理成功: $targetPath" 'Green'
            } catch {
                Print "清理失敗: $_" 'Red'
            }
        }
    }
}

Print "========================================================================================================================" 'Red'
Print "                                                 系統清理程式 v2 (實驗版)" 'Magenta'
Print "========================================================================================================================" 'White'
Print ""
Print "                                              - Versions 1.0.0 2025/02/08 -" 'Green'
Print ""
Print "                                               清理時建議關閉所有應用程式" 'Yellow'
Print ""
Print "                                        此程式只會清除(緩存/暫存)檔案不會影響系統" 'Yellow'
Print ""
Print "-----------------------------------------------------------------------------------------------------------------------" 'White'
Print "                                                 按任意鍵開始清理系統"
Print "-----------------------------------------------------------------------------------------------------------------------" 'Red'
Input "輸入任意鍵..."

# 取得路徑
$C = $env:systemdrive
$Windows = $env:windir
$Roaming = $env:AppData
$User = $env:userprofile
$Local = $env:LocalAppData
$Program = $env:ProgramData
$LocalLow = "$(split-path $Roaming)\LocalLow"

# ===== 重置網路 =====
ipconfig /release # 釋放 IP
Clear-DnsClientCache # 清除 DNS 緩存
netsh int ip reset # 重置 IP 設定
netsh int tcp reset # 重置 TCP/IP 堆疊
netsh winsock reset # 重置 Winsock
certutil -URLCache * delete # 清除憑證 URL 緩存
netsh interface ip delete arpcache # 清除 ARP 緩存
nbtstat -R # 清除 NetBIOS 快取
ipconfig /renew # 更新 IP 配置

# ===== 重置更新緩存 =====
Stop-Service -Name bits, wuauserv, cryptSvc, msiserver -Force

Delete @(
    "$Windows\System32\catroot2"
    "$Windows\System32\catroot2.old"
    "$Windows\SoftwareDistribution"
    "$Windows\SoftwareDistribution.old"
)

Start-Service -Name bits, wuauserv, cryptSvc, msiserver

# ===== 清除系統基本緩存 =====
Delete @(
    # 舊的系統文件
    "$Windows.old"

    # 刪除錯誤報告 和 系統日誌
    "$Windows\System32\winevt\Logs\"
    "$Program\Microsoft\Windows\WER\"
    "$Windows\PCHealth\ERRORREP\QSIGNOFF\"
    "$Program\Microsoft\Diagnosis\ETLLogs\AutoLogger\"
    "$Windows\Sys*\config\systemprofile\AppData\Local\CrashDumps"

    # ASP.NET 應用程序的臨時編譯文件
    "$Windows\Microsoft.NET\Framework*\*\Temporary ASP.NET Files"

    # 舊版瀏覽器緩存
    "$Local\Microsoft\Windows\Explorer\thumbcache*"

    # 緩存數據
    "$C\*.tmp"
    "$C\*._mp"
    "$C\*.log"
    "$C\*.gid"
    "$C\*.chk"
    "$C\*.dlf"
    "$C\AMD\"
    "$C\INTEL\"
    "$C\NVIDIA\"
    "$C\recycled\"
    "$C\OneDriveTemp"
    "$C\Program Files\Temp"

    "$Windows\Temp\"
    "$Windows\*.bak"
    "$Windows\HELP\"
    "$Windows\KB*.log"
    "$Windows\prefetch\"
    "$Windows\SystemTemp"
    "$Windows\logs\*.log"
    "$Windows\Panther\*.log"
    "$Windows\Logs\MoSetup\*.log"
    "$Windows\Logs\CBS\CbsPersist*.log"
    "$Windows\SoftwareDistribution\Download\"
    "$Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization"

    # 刪除有風險
    "$Program\Package Cache\"

    "$User\Intel"
    "$User\.cache"
    "$User\.Origin"
    "$User\recent\"
    "$User\cookies\"
    "$User\RecycleBin\"
    "$User\.QtWebEngineProcess"
    "$User\Local Settings\Temp\"
    "$User\Local Settings\Temporary Internet Files\"
)

# ===== 清除防火牆紀錄 =====
Delete @(
    "$Program\Microsoft\Windows Defender\Support\"
    "$Program\Microsoft\Windows Defender\Scans\MetaStore\"
    "$Program\Microsoft\Windows Defender\Scans\History\CacheManager\"
    "$Program\Microsoft\Windows Defender\Scans\History\Service\*.log"
    "$Program\Microsoft\Windows Defender\Scans\History\Results\Quick\"
    "$Program\Microsoft\Windows Defender\Scans\History\Results\Resource\"
    "$Program\Microsoft\Windows Defender\Scans\History\ReportLatency\Latency\"
    "$Program\Microsoft\Windows Defender\Network Inspection System\Support\*.log"
)

# ===== 第三方軟體緩存 =====
Delete @(
    # Surfshark
    "$Local\Surfshark\Updates"
    # nikke
    "$Roaming\nikke_launcher\tbs_cache"
    # LINE
    "$Local\LINE\bin\old"
    # Telegram
    "$Roaming\Telegram Desktop\tdata\user_data"
    # NVIDIA
    "$LocalLow\NVIDIA\PerDriverVersion\DXCache"
    # IObit
    "$Program\IObit\Driver Booster\Download"
    "$Roaming\IObit\Software Updater\Log\*.dbg"
    "$Roaming\IObit\Software Updater\AutoLog\*.dbg"
    # VSCode
    "$Roaming\Code\logs"
    "$Roaming\Code\CachedData"
    "$Roaming\Code\User\History"
)

# ===== 掃描清理緩存類型文件 =====
$findFolders = @($Roaming, $Local, $LocalLow)
$cacheFolders = @(
    'Temp', 'Logs', 'Crashpad', 'History', 'INetHistory',  'CrashDumps',
    'Cache', 'Caches', 'lru-cache', 'librarycache', 'GPUCache', 'Code Cache', 'media_cache','MediaCache', 'DawnCache',
    'INetCache', 'ShaderCache', 'GrShaderCache', 'ScriptCache', 'CacheStorage', 'extensions_crx_cache', 'webcache', 'LocalCache'
)

foreach ($find in $findFolders) {
    $found = Get-ChildItem -Path $find -Recurse -Directory -ErrorAction SilentlyContinue |
        Where-Object {
            $cacheFolders.ToLower() -contains $_.Name.ToLower()
        }

    if ($found) { Delete $found }
}

# ===== 調用系統清理 並檢查錯誤 =====
Start-Process cleanmgr.exe -ArgumentList "/sagerun:99"

Clear-Host
Print "`n安全移除系統內隱藏檔案(這需要花一段時間)`n" 'Yellow'

# 清理不再需要的系統組件和臨時文件
& Dism.exe /online /Cleanup-Image /StartComponentCleanup

# 在組件清理的基礎上進行的擴展操作
& Dism.exe /online /Cleanup-Image /StartComponentCleanup /ResetBase

Print "`n檢查系統有無損壞(這需要花一段時間)`n" 'Green'
& Dism.exe /Online /Cleanup-Image /ScanHealth
& Dism.exe /Online /Cleanup-Image /CheckHealth
& Dism.exe /Online /Cleanup-image /RestoreHealth
& sfc /scannow

# ===== 結束選擇 =====
Print "  ✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬" 'Cyan'
Print ""
Print "           【 操作選擇 】"
Print ""
Print "    《1.電腦關機》   《2.電腦重啟》" 'Yellow'
Print ""
Print "    《3.清理還原》   《4.離開程式》" 'Yellow'
Print ""
Print "  ✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬" 'Cyan'
Print ""
$choice = Input "選擇功能 [代號]"

switch ($choice) {
    1 { Stop-Computer -Force }
    2 { Restart-Computer -Force }
    3 { control sysdm.cpl,0,4 }
    4 { exit }
}