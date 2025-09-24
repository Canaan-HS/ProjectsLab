param (
    [string]$videoPath
)

<#
    ? 個人用途
    目前電腦內 PotPlayer 使用 madVR 播放 4k 會掉 fps
#>

# 嘗試取得 PotPlayer 路徑
$potPlayerPath = (Get-StartApps | Where-Object { $_.AppID -like "*PotPlayerMini64.exe" }).AppID

# 取得解析度（需要 ffprobe）
if (Get-Command ffprobe -ErrorAction SilentlyContinue) {
    $resolution = & ffprobe -v quiet -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 $videoPath 2>$null
} else {
    $resolution = $null
}

if (-not $resolution) {
    if ($potPlayerPath) {
        Start-Process $potPlayerPath -ArgumentList "`"$videoPath`""
    }
    else {
        Start-Process "explorer.exe" -ArgumentList "`"$videoPath`""
    }
    exit
}

# 解析度解析
if ($resolution -match "^\d+x\d+$") {
    $parts = $resolution -split "x"
    $width = [int]$parts[0]
    $height = [int]$parts[1]
} else {
    $width = $height = 0
}

# 如果是 4K 以上 → 優先使用 ffplay
if ($width -ge 3840 -or $height -ge 2160) {
    if (Get-Command ffplay -ErrorAction SilentlyContinue) {
        Start-Process "ffplay" -ArgumentList "-loop", "0", "`"$videoPath`""
    }
    elseif ($potPlayerPath) {
        Start-Process $potPlayerPath -ArgumentList "`"$videoPath`""
    }
    elseif (Test-Path "$env:ProgramFiles\Windows Media Player\wmplayer.exe") {
        Start-Process "$env:ProgramFiles\Windows Media Player\wmplayer.exe" -ArgumentList "`"$videoPath`""
    }
    else {
        Start-Process "explorer.exe" -ArgumentList "`"$videoPath`""
    }
}
# PotPlayer
elseif ($potPlayerPath) {
    Start-Process $potPlayerPath -ArgumentList "`"$videoPath`""
}
else {
    Start-Process "explorer.exe" -ArgumentList "`"$videoPath`""
}