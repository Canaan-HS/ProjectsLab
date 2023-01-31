# 取得完整影片資訊
# ffprobe -v quiet -print_format json -show_streams -show_format "影片路徑"

function Parse {
    param (
        [object]$param,
        [boolean]$toInt
    )

    return ($param -is [string]) ? ($toInt ? [int]$param : $param) : ($toInt ? [int]$param[0] : $param[0])
}

function GetStreamsInfo {
    param (
        [string]$Video, # 影片路徑
        [int]$targetFPS, # 目標的 FPS
        [int]$scaleFactor # 縮放乘數
    )

    try {
        # 取得媒體完整資訊
        $videoInfo = (& ffprobe -v quiet -print_format json -show_streams -show_format $Video | ConvertFrom-Json).streams

        # 處理回傳所需數據
        $width = Parse $videoInfo.width $true # 基本寬
        $height = Parse $videoInfo.height $true # 基本高

        $frame_rate = ((Parse $videoInfo.avg_frame_rate) -split "/")
        $fps = [int]([int]$frame_rate[0] / [int]$frame_rate[1]) # 每幀張數 Fps

        $fpsFactor = [Math]::Max($targetFPS / $fps, 1) # 根據目標 FPS, 計算出 FPS 乘數
        $bitrate = [int]((Parse $videoInfo.bit_rate $true) * ($scaleFactor * $scaleFactor) * [Math]::Max($fpsFactor * 0.8, 1) / 1MB) # 比特 位元 率 ($fpsFactor * 0.8 是壓縮用, 不一定會增加這麼多)

        $frames = Parse $videoInfo.nb_frames $true # 總共幀數 (擷圖的總數)
        $fillerFrame = [int]($frames * $fpsFactor) # 計算補偵後的框架數

        return @( # 不驗證參數有效性, 主函式會檢查
            $width, $height, $fps, $bitrate, $frames, $fillerFrame
        )
    } catch {
        write-host ($_.Exception.Message)
        exit
    }
}