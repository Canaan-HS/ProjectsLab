:: - Versions 1.0.9 -
:: - LastEditTime 2024/7/19 02:23 -

@echo off
chcp 65001 >nul 2>&1
color C
%1 %2
ver|find "5.">nul&&goto :Admin
mshta vbscript:createobject("shell.application").shellexecute("%~s0","goto :Admin","","runas",1)(window.close)&goto :eof
:Admin

cls
title 系統清理優化

@ ECHO.
@ ECHO.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ 系統緩存清理程序 ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
@ ECHO.
@ ECHO                                             - Versions 1.0.9 2023/06/01 -
@ ECHO.
@ ECHO                                        此程式只會清除(緩存/暫存)檔案不會影響系統                                 
@ ECHO.
@ ECHO                                      清理完畢後可選擇(重啟電腦/關機/直接離開程式等)
@ ECHO.
@ ECHO -----------------------------------------------------------------------------------------------------------------------
@ ECHO                                                按任意鍵開始清理系統
@ ECHO -----------------------------------------------------------------------------------------------------------------------
@ ECHO.

:: 等待任意鍵
pause

@echo 開始清理請稍.....
timeout /t 02 >nul

:: ========== 網路重置 ==========
:: 釋放IP位置
ipconfig /release 
:: 清空Dns緩存
ipconfig /flushdns
:: 重新請求IP位置
ipconfig /renew

:: ========== 網路優化 ==========

:: 刪除系統中的證書緩存
certutil -URLCache * delete
:: 刪除系統的 ARP 緩存
netsh int ip delete arpcache

:: ========== 清理優化 ==========
:: 刪除錯誤報告
DEL /F /S /Q "C:\WINDOWS\PCHealth\ERRORREP\QSIGNOFF\*.*"
DEL /F /S /Q "C:\WINDOWS\system32\LogFiles\HTTPERR\*.*"
:: 刪除操作緩存
DEL /F /S /Q "C:\WINDOWS\Microsoft.NET\Framework\v1.1.4322\Temporary ASP.NET Files\*.*"
DEL /F /S /Q "C:\WINDOWS\Microsoft.NET\Framework\v2.0.50727\Temporary ASP.NET Files\*.*"
DEL /F /S /Q "C:\WINDOWS\Microsoft.NET\Framework\v4.0.30319\Temporary ASP.NET Files\*.*"
DEL /F /S /Q "C:\WINDOWS\temp\*.*"
:: 刪除臨時文件
DEL /F /S /Q /A:S "C:\WINDOWS\IIS Temporary Compressed Files\*.*"
DEL %windir%\KB*.log /F /q
RD %windir%\$hf_mig$ /S /Q
:: 刪除舊版系統文件
RD /S /Q C:\Windows.old
:: 舊版刪除各瀏覽器緩存
DEL /f /s /q "%LocalAppData%\Microsoft\Windows\WebCache\*.*"
DEL /f /s /q "%LocalAppData%\Microsoft\Windows\INetCache\*.*"
DEL /f /s /q "%AppData%\Opera Software\Opera Stable\Cache\*.*"
DEL /f /s /q "%AppData%\Mozilla\Firefox\Profiles\*\cache2\*.*"
DEL /f /s /q "%AppData%\Google\Chrome\User Data\Default\Cache\*.*"
DEL /f /s /q "%LocalAppData%\Microsoft\Windows\Explorer\thumbcache*"

DEL /f /s /q "%windir%\*.bak"
DEL /f /s /q "%windir%\temp\*.*"
DEL /f /s /q "%systemdrive%\*.tmp"
DEL /f /s /q "%systemdrive%\*._mp"
DEL /f /s /q "%systemdrive%\*.log"
DEL /f /s /q "%systemdrive%\*.gid"
DEL /f /s /q "%systemdrive%\*.chk"
DEL /f /s /q "%systemdrive%\*.dlf"
DEL /f /s /q "C:\WINDOWS\HELP\*.*"
DEL /f /s /q "%systemroot%\Temp\*.*"
DEL /f /s /q "%windir%\prefetch\*.*"
DEL /f /s /q "%userprofile%\recent\*.*"
DEL /f /s /q "%userprofile%\cookies\*.*"
DEL /f /s /q "%systemdrive%\recycled\*.*"
DEL /f /s /q "%HomePath%\AppData\LocalLow\Temp\*.*"
DEL /f /s /q "%userprofile%\Local Settings\Temp\*.*"
DEL /f /s /q "%windir%\SoftwareDistribution\Download\*.*"
DEL /f /s /q "%LocalAppData%\Microsoft\Windows\Caches\*.*"
DEL /f /s /q "C:\ProgramData\Microsoft\Windows\WER\Temp\*.*"
DEL /f /s /q "%userprofile%\Local Settings\Temporary Internet Files\*.*"
DEL /f /s /q "%AllUsersProfile%\「開始」功能表\程式集\Windows Messenger.lnk"

RD /s /q %LocalAppData%\Temp
RD /s /q "C:\Windows\SystemTemp"
RD /s /q %userprofile%\RecycleBin
RD /s /q "C:\ProgramData\Package Cache"
RD /s /q C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization

RD /s /q %userprofile%\Local
RD /s /q %userprofile%\Intel
RD /s /q %userprofile%\source
RD /s /q %systemdrive%\Program Files\Temp

DEL /f /s /q %windir%\logs\*.log
DEL /f /s /q %SYSTEMDRIVE%\AMD\*.*
DEL /f /s /q %windir%\Panther\*.log
DEL /f /s /q %SYSTEMDRIVE%\INTEL\*.*
DEL /f /s /q %SYSTEMDRIVE%\NVIDIA\*.*
DEL /f /s /q %SYSTEMDRIVE%\OneDriveTemp
DEL /f /s /q %windir%\Logs\MoSetup\*.log
DEL /f /s /q %windir%\Logs\CBS\CbsPersist*.log
DEL /f /s /q %LocalAppData%\Microsoft\Windows\WebCache\*.log

RD /s /q %LocalAppData%\pip\cache
RD /s /q C:\Users\%username%\.cache
RD /s /q C:\Users\%username%\.Origin
RD /s /q C:\Users\%username%\.QtWebEngineProcess
RD /s /q %LocalAppData%\Microsoft\Windows\INetCache\*.log

:: 額外軟體項目清除
RD /s /q "%LocalAppData%\Surfshark\Updates"
RD /s /q "%AppData%\Telegram Desktop\tdata\user_data"
RD /s /q "C:\ProgramData\IObit\Driver Booster\Download"
RD /s /q "%AppData%\Blitz\Cache"
RD /s /q "%AppData%\Blitz\Code Cache"
RD /s /q "%AppData%\Blitz\GPUCache"
RD /s /q "%AppData%\Blitz\DawnCache"
RD /s /q "%AppData%\nikke_launcher\tbs_cache"
RD /s /q "%AppData%\PikPak\Cache"
RD /s /q "%AppData%\PikPak\Code Cache"
RD /s /q "%AppData%\riot-client-ux\Cache"
RD /s /q "%AppData%\riot-client-ux\GPUCache"
RD /s /q "%AppData%\riot-client-ux\Code Cache"
DEL /f /q /s "%AppData%\IObit\IObit Uninstaller\UMlog\*.dbg"

:: Dx緩存清除
RD /s /q "%USERPROFILE%\AppData\Local\NVIDIA\DXCache"

color 3
cls
:: ========== 清除更新緩存 ==========
net stop bits
net stop wuauserv
net stop cryptSvc
net stop msiserver
ren "C:\Windows\System32\catroot2 catroot2.old"
ren "C:\Windows\SoftwareDistribution SoftwareDistribution.old"

DEL /f /s /q "C:\Windows\SoftwareDistribution\*.*"

net start bits
net start wuauserv
net start cryptSvc
net start msiserver

:: ========== 清除內建防火牆紀錄 ==========
DEL /f /s /q "%ProgramData%\Microsoft\Windows Defender\Support"
DEL /f /s /q "%ProgramData%\Microsoft\Windows Defender\Scans\MetaStore"
DEL /f /s /q "%ProgramData%\Microsoft\Windows Defender\Scans\History\CacheManager"
DEL /f /s /q "%ProgramData%\Microsoft\Windows Defender\Scans\History\Service\*.log"
DEL /f /s /q "%ProgramData%\Microsoft\Windows Defender\Scans\History\Results\Quick"
DEL /f /s /q "%ProgramData%\Microsoft\Windows Defender\Scans\History\Results\Resource"
DEL /f /s /q "%ProgramData%\Microsoft\Windows Defender\Scans\History\ReportLatency\Latency"
DEL /f /s /q "%ProgramData%\Microsoft\Windows Defender\Network Inspection System\Support\*.log"

:: ========== Google清理 ==========
color A
cls
@echo Google Chrom 清理(將會被關閉)
timeout /t 02 >nul

:: 關閉
wmic process where name="chrome.exe" delete

set ChromeCache="%ChromeDataDir%\Cache"
set ChromeDataDir="C:\Users\%USERNAME%\Local Settings\Application Data\Google\Chrome\User Data\Default"

del /f /s /q "%LocalAppData%\Google\Chrome\User Data\Default\*tmp"
del /f /s /q "%LocalAppData%\Google\Chrome\User Data\Default\History*"

rd /s /q "%LocalAppData%\Google\Chrome\User Data\Default\Cache"
rd /s /q "%LocalAppData%\Google\Chrome\User Data\Default\IndexedDB"
rd /s /q "%LocalAppData%\Google\Chrome\User Data\extensions_crx_cache"
rd /s /q "%LocalAppData%\Google\Chrome\User Data\Default\Service Worker"

del /q /s /f "%ChromeCache%\*.*"
del /q /s /f "%ChromeDataDir%\*Cookies*.*"

:: ========== Edge清理 ==========
@echo Edge 清理(將會被關閉)
timeout /t 2 >nul

wmic process where name="msedge.exe" delete

for /d %%E in ("%LocalAppData%\Microsoft\Edge\User Data\Profile*") do (
    rd /s /q "%%E\Cache"
    rd /s /q "%%E\GPUCache"
    rd /s /q "%%E\IndexedDB"
    rd /s /q "%%E\Code Cache"
    rd /s /q "%%E\Service Worker"
)

:: ========== VScode清理 ==========
@echo VS Code 清理

rd /s /q "%AppData%\Code\logs"
rd /s /q "%AppData%\Code\Cache"
rd /s /q "%AppData%\Code\Crashpad"
rd /s /q "%AppData%\Code\Code Cache"
rd /s /q "%AppData%\Code\CachedData"
rd /s /q "%AppData%\Code\User\History"
rd /s /q "%AppData%\Code\CachedExtensions"
rd /s /q "%AppData%\Code\CachedExtensionVSIXs"
rd /s /q "%AppData%\Code\User\workspaceStorage"
rd /s /q "%LocalAppData%\Microsoft\vscode-cpptools"
rd /s /q "%AppData%\Code\Service Worker\ScriptCache"
rd /s /q "%AppData%\Code\Service Worker\CacheStorage"
rd /s /q "%AppData%\Code\User\globalStorage\redhat.java"

:: ========== discord清理 ==========
@echo DisCord 清理(DC將會被關)

timeout /t 02 >nul

:: 關閉
wmic process where name="Discord.exe" delete

del /f /s /q "%AppData%\Discord\Cache\*.*"
del /f /s /q "%AppData%\Discord\GPUCache\*.*"
del /f /s /q "%AppData%\Discord\Code Cache\*.*"
del /f /s /q "%AppData%\Discord\DawnCache\*.*"

:: ========== Line清理 ==========
@echo 清理Line緩存(Line將會被關閉)

timeout /t 02 >nul

:: 關閉
wmic process where name="Line.exe" delete

del /f /s /q "%LocalAppData%\LINE\Cache\*.*"
rd /s /q  "%LocalAppData%\LINE\bin\old"

:: ========== 優化操作 ==========
color B
cls
@echo 開始進行電腦優化

:: 終極效能 (不適用於所有人)
:: powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61
:: powercfg.exe /setactive e9a42b02-d5df-448d-aa00-03f14749eb61

:: 禁用休眠
powercfg.exe /hibernate off

:: 禁用硬碟節能
for /f "tokens=*" %%i in ('reg query "HKLM\SYSTEM\CurrentControlSet\Enum" /s /f "StorPort"^| findstr "StorPort"') do reg add "%%i" /v "EnableIdlePowerManagement" /t REG_DWORD /d "0" /f >nul 2>&1
    for %%i in (EnableHIPM EnableDIPM EnableHDDParking) do for /f %%a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Services" /s /f "%%i" ^| findstr "HKEY"') do reg add "%%a" /v "%%i" /t REG_DWORD /d "0" /f >nul 2>&1
    for /f %%i in ('call "resources\smartctl.exe" --scan') do (
        call "resources\smartctl.exe" -s apm,off %%i
        call "resources\smartctl.exe" -s aam,off %%i
    ) >nul 2>&1
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Storage" /v "StorageD3InModernStandby" /t REG_DWORD /d "0" /f >nul 2>&1
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device" /v "IdlePowerMode" /t REG_DWORD /d "0" /f >nul 2>&1

POWERSHELL "$devices = Get-WmiObject Win32_PnPEntity; $powerMgmt = Get-WmiObject MSPower_DeviceEnable -Namespace root\wmi; foreach ($p in $powerMgmt){$IN = $p.InstanceName.ToUpper(); foreach ($h in $devices){$PNPDI = $h.PNPDeviceID; if ($IN -like \"*$PNPDI*\"){$p.enable = $False; $p.psbase.put()}}}"

:: 碎片整理工具
%windir%\system32\defrag.exe %systemdrive% -b

:: 停止搜尋服務
net stop "Windows Search
:: 搜尋服務禁止啟用
sc config "Windows Search" start=disabled
:: 停止網路共享服務
net stop "WMPNetworkSvc"
:: 網路共享服務禁止啟用
sc config "WMPNetworkSvc" start=disabled

:: 清理虛擬內存後 , 再次創建設置
wmic pagefileset delete
wmic pagefileset create name="C:\pagefile.sys"
wmic pagefileset where name="C:\\pagefile.sys" set InitialSize=4096,MaximumSize=12288

:: 關閉桌面管理器動畫
reg add "HKEY_CURRENT_USER\Software\Policies\Microsoft\Windows\DWM" /v "DisallowAnimations" /t REG_dword /d 1 /f
:: Windows Explorer 動畫關閉
reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v "TurnOffSPIAnimations" /t REG_dword /d 1 /f
:: 視窗最大最小化動畫關閉
reg add "HKEY_CURRENT_USER\Control Panel\Desktop\WindowMetrics" /v "MinAnimate" /t REG_SZ /d 0 /f
:: 關閉自動更新
reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Update" /v "UpdateMode" /t REG_DWORD /d 0 /f
:: 啟用分離桌面
reg add "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" /v "DesktopProcess" /t REG_DWORD /d 1 /f

:: 重啟防火牆
netsh advfirewall set allprofiles state on
netsh advfirewall firewall set rule all new enable=yes

:: 內建清理
cleanmgr /sagerun:99

color D
cls
@echo 接下來需要安全移除系統內隱藏檔案 所以需要一段掃描時間
timeout /t 02 >nul

:: 清理不再需要的系統組件和臨時文件
Dism.exe /online /Cleanup-Image /StartComponentCleanup
:: 在組件清理的基礎上進行的擴展操作
Dism.exe /online /Cleanup-Image /StartComponentCleanup /ResetBase

@echo 檢查系統修復檔有無損(這需要花一段時間確保系統無損壞)
Dism /Online /Cleanup-Image /ScanHealth
Dism /Online /Cleanup-Image /CheckHealth
DISM /Online /Cleanup-image /RestoreHealth

:: 刪除創建的多於文件
rd /s /q C:\Program
rd /s /q Settings
rd /s /q Files

cls
@echo 檢查系統有無損壞
sfc /scannow

:: 最後詢問是否重啟
:ExitMenu
color C
CLS
MODE con: COLS=40 LINES=15
ECHO.
ECHO    ✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬
ECHO.
ECHO             【 操作選擇 】
ECHO.
ECHO      《1.電腦關機》   《2.電腦重啟》
ECHO.
ECHO      《3.清理還原》   《4.離開程式》
ECHO.            
ECHO    ✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬✬
ECHO.

Choice /C 1234 /N /M "選擇 (數字) :"

if %errorlevel% == 1 (
    shutdown /s /t 0
    exit
) else if %errorlevel% == 2 (
    shutdown /r /t 0
    exit
) else if %errorlevel% == 3 (
    control sysdm.cpl,,4
    goto ExitMenu
) else if %errorlevel% == 4 (
    exit
)