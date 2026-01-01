# 取得完整影片資訊
# ffprobe -v quiet -print_format json -show_streams -show_format "影片路徑"

function Parse {
    param ([object]$param, [boolean]$toInt)
    return ($param -is [string]) ? ($toInt ? [int]$param : $param) : ($toInt ? [int]$param[0] : $param[0])
}

# 解析幀率字串 (如 "24000/1001")
function ParseFrameRate([string]$fpsString) {
    if (-not $fpsString -or $fpsString -eq "0/0") { return 0 }
    $parts = $fpsString -split "/"
    $denom = if ([int]$parts[1] -eq 0) { 1 } else { [int]$parts[1] }
    return [Math]::Round([double]$parts[0] / $denom, 2)
}

function GetStreamsInfo {
    param ([string]$Video, [int]$targetFPS)

    $mediaInfo = & ffprobe -v quiet -print_format json -show_streams -show_format $Video | ConvertFrom-Json
    $stream = $mediaInfo.streams | Where-Object { $_.codec_type -eq 'video' } | Select-Object -First 1
    $format = $mediaInfo.format

    $width = [int]$stream.width
    $height = [int]$stream.height

    # 幀率 (優先 avg_frame_rate)
    $fps = ParseFrameRate $stream.avg_frame_rate
    if ($fps -eq 0) { $fps = ParseFrameRate $stream.r_frame_rate }

    # 時長 (優先 stream，備用 format，最後單獨查詢)
    $totalDuration = if ($stream.duration) { [double]$stream.duration } 
    elseif ($format.duration) { [double]$format.duration }
    else { [double](& ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $Video) }

    # 總幀數 (優先 stream，備用計算，最後實際計數)
    $totalFrames = if ($stream.nb_frames) { [int]$stream.nb_frames }
    elseif ($totalDuration -gt 0 -and $fps -gt 0) { [int][Math]::Ceiling($totalDuration * $fps) }
    else { [int](& ffprobe -v quiet -count_frames -select_streams v:0 -show_entries stream=nb_read_frames -of default=noprint_wrappers=1:nokey=1 $Video) }

    # 補幀後幀數
    $fpsFactor = [Math]::Max($targetFPS / $fps, 1)
    $finalFrames = [int]($totalFrames * $fpsFactor)

    # 檢測是否有音頻流
    $hasAudio = $null -ne ($mediaInfo.streams | Where-Object { $_.codec_type -eq 'audio' } | Select-Object -First 1)

    return @($width, $height, $fps, $totalDuration, $totalFrames, $finalFrames, $hasAudio)
}