<#
.SYNOPSIS
Video Upscaler (VU) command-line launcher.
Provides a user-friendly interface for the main Upscaler.ps1 script.
#>
[CmdletBinding(SupportsShouldProcess=$true, HelpUri='https://github.com/your-repo-link-here')]
param(
    [Parameter(Mandatory=$false, Position=0)]
    [Alias('i')]
    [string]$VideoPath,

    [Parameter(Mandatory=$false)]
    [Alias('t', 'fps')]
    [int]$TargetFPS = 0,

    [Parameter(Mandatory=$false)]
    [Alias('u', 'scale')]
    [int]$UpscaleFactor = 2,

    [Parameter(Mandatory=$false)]
    [Alias('o', 'format')]
    [string]$OutputFormat = "mp4",

    [Parameter(Mandatory=$false)]
    [ValidateSet("png", "webp")]
    [Alias('p', 'pformat')]
    [string]$ProcessFormat = "png",

    [Parameter(Mandatory=$false)]
    [Alias('c', 'res')]
    [string]$CustomResolution = $null,

    [Parameter(Mandatory=$false)]
    [Alias('f')]
    [boolean]$FastOutput = $true,

    [Parameter(Mandatory=$false)]
    [Alias('cd', 'duration')]
    [int]$ChunkDuration = 30,

    [Parameter(Mandatory=$false)]
    [Alias('h', '?')]
    [switch]$Help,

    [Parameter(Mandatory=$false)]
    [Alias('v')]
    [switch]$Version
)

# --- Metadata ---
$scriptVersion = "1.0.0" # Maintained version, fixed critical bug

# --- Functions ---
function Show-Help {
    Write-Host @"

影片增強工具 (VU) - v$scriptVersion
一個使用 AI 模型提升影片畫質、幀率與解析度的命令列工具。

用法:
  vu <影片路徑> [選項]
  vu -i <影片路徑> [選項]

必要參數:
  -i, -VideoPath <路徑>      要處理的影片檔案路徑。

選項:
  -t, -TargetFPS <整數>      輸出影片的目標 FPS。(預設: 0, 與來源相同)
  -u, -UpscaleFactor <整數>   放大倍率 (1-4)。(預設: 2)
  -o, -OutputFormat <字串>    輸出影片的容器格式。(預設: mp4)
  -p, -ProcessFormat <字串>   處理過程中暫存圖片的格式 (png/webp)。(預設: png)
  -c, -CustomResolution <字串> 自訂輸出解析度，例如 "1920x1080"。(預設: null)
  -f, -FastOutput             最終合併時使用較快的硬體編碼器。(預設: true)
  -cd, -ChunkDuration <整數>  分段處理的時長(秒)，設為 0 則不分段。(預設: 30)
  -h, -Help                   顯示此幫助訊息。
  -v, -Version                顯示版本資訊。
"@
}

# --- Main Logic ---
if ($Version) {
    Write-Host "Video Upscaler (VU) version $scriptVersion"
    exit
}

if ($PSBoundParameters.Count -eq 0 -or $Help -or ([string]::IsNullOrEmpty($VideoPath) -and !$Version)) {
    Show-Help
    exit
}

try {
    $scriptPath = Join-Path $PSScriptRoot "Upscaler.ps1"
    if (-not (Test-Path $scriptPath)) {
        throw "找不到主腳本: $scriptPath"
    }

    $command = "& `"$scriptPath`""
    foreach ($key in $PSBoundParameters.Keys) {
        if ($key -notin @('Help', 'Version')) {
            $value = $PSBoundParameters[$key]
            if ($value -is [bool]) {
                if ($value) { $command += " -$key" }
            } elseif ($value -ne $null) {
                $command += " -$key `"$value`""
            }
        }
    }

    Write-Host "正在執行: powershell.exe -NoProfile -ExecutionPolicy Bypass -Command `"$command`"" -ForegroundColor DarkGray
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$command"
}
catch {
    Write-Host "[Error] 執行失敗:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}