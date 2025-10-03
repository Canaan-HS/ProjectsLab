param (
    [string]$videoPath
)

<#
    ? 個人用途
    目前電腦內 PotPlayer 使用 madVR 播放 4k 會掉 fps
#>

# 嘗試從環境變數取得 PotPlayer 路徑
$potPlayerPath = $env:PotPlayerPath
# 嘗試取得 Windows Media Player 路徑
$mediaPlayerPath = "$env:ProgramFiles\Windows Media Player\wmplayer.exe"

if (-not $potPlayerPath -or -not (Test-Path $potPlayerPath)) {
    # 環境變數不存在或路徑失效，使用 Get-StartApps 查找
    $potPlayerPath = (Get-StartApps | Where-Object { $_.AppID -like "*PotPlayerMini64.exe" }).AppID

    # 找到更新使用者環境變數
    if ($potPlayerPath) {
        [Environment]::SetEnvironmentVariable("PotPlayerPath", $potPlayerPath, "User")
    }
}

# 取得解析度（需要 ffprobe）
if (Get-Command ffprobe -ErrorAction SilentlyContinue) {
    $arguments = @(
        '-v', 'error',
        '-select_streams', 'v:0',
        '-show_entries', 'stream=width,height:format=duration',
        '-read_intervals', '%+#0',
        '-of', 'csv=p=0',
        $videoPath
    )

    $info = & ffprobe @arguments 2>$null
}

function reTry {
    param (
        [boolean]$skipPotPlayer = $false,
        [boolean]$skipWindowsMediaPlayer = $false
    )

    # PotPlayer
    if ($potPlayerPath -and -not $skipPotPlayer) {
        try {
            Start-Process $potPlayerPath -ArgumentList "`"$videoPath`""
        }
        catch {
            reTry -skipPotPlayer $true
            return
        }
    }
    # Windows Media Player
    elseif ((Test-Path $mediaPlayerPath) -and -not $skipWindowsMediaPlayer) {
        try {
            Start-Process $mediaPlayerPath -ArgumentList "`"$videoPath`""
        } 
        catch {
            reTry -skipWindowsMediaPlayer $true
            return
        }
    }
    # default
    else {
        Start-Process "explorer.exe" -ArgumentList "`"$videoPath`""
    }

    exit
}

if (-not $info) { reTry }

$infoLength = $info.Length
if ($infoLength -eq 3) {
    $width = [int]$info[0]
    $height = [int]$info[1]
    $duration = [math]::Ceiling([double]$info[2])
}
elseif ($infoLength -eq 2) {
    $dims = $info[0] -split ','
    $width = [int]$dims[0]
    $height = [int]$dims[1]
    $duration = [math]::Ceiling([double]$info[1])
} else {
    reTry
}

# 判斷解析度 >= 4K 或長度 <= 20 秒
if (($width -ge 3840 -or $height -ge 2160) -or ($duration -le 20)) {
    # ffplay
    if (Get-Command ffplay -ErrorAction SilentlyContinue) {
        Start-Process ffplay -ArgumentList "-fs", "-loop", "0", "-infbuf", "-seek_interval", "3", "`"$videoPath`"" -NoNewWindow
        exit
    }
}

reTry