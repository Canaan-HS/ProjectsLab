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
        $mediaInfo = & ffprobe -v quiet -print_format json -show_streams -show_format $Video | ConvertFrom-Json
        $videoStream = $mediaInfo.streams | Where-Object { $_.codec_type -eq 'video' } | Select-Object -First 1
        $formatInfo = $mediaInfo.format

        # 處理回傳所需數據
        $width = [int]$videoStream.width # 基本寬
        $height = [int]$videoStream.height # 基本高

        $frame_rate = ($videoStream.avg_frame_rate -split "/")
        $fps = [int]([int]$frame_rate[0] / [int]$frame_rate[1]) # 每幀張數 Fps

        $fpsFactor = [Math]::Max($targetFPS / $fps, 1) # 根據目標 FPS, 計算出 FPS 乘數
        
        # 如果 formatInfo.bit_rate 存在且有效，則使用它，否則回退到 videoStream.bit_rate
        $baseBitrate = if ($formatInfo.bit_rate) { [int]$formatInfo.bit_rate } else { [int]$videoStream.bit_rate }
        $bitrate = [int]($baseBitrate * ($scaleFactor * $scaleFactor) * [Math]::Max($fpsFactor * 0.8, 1) / 1MB) # 比特 位元 率

        $totalFrames = [int]$videoStream.nb_frames # 總共幀數 (擷圖的總數)
        $totalDuration = [double]$formatInfo.duration # 總時長（秒）
        $fillerFrame = [int]($totalFrames * $fpsFactor) # 計算補幀後的框架數

        return @(
            $width, $height, $fps, $bitrate, $totalDuration, $totalFrames, $fillerFrame
        )
    } catch {
        write-host ("獲取媒體資訊時發生錯誤: " + $_.Exception.Message)
        exit
    }
}