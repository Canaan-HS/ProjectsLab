<#
    運行環境:
    PowerShell 7+

    重要說明:
    1. 檔案路徑最好都是英文，不要有奇怪的符號或文字，否則可能會出現問題。 [PowerShell 麻煩的地方]
    2. 目前除了 mp4 以外，其他格式還需測試
#>

# 取得指令碼位置
$CURRENT_ROOT = $PSScriptRoot

# 載入依賴專案
Import-Module "$CURRENT_ROOT\modules\LoadDependencies.psm1"
$DEPEND = FetchDependent $CURRENT_ROOT

# 載入參數生成器
Import-Module "$CURRENT_ROOT\modules\ParameterGen.psm1"
$PARAMETER = Generator $DEPEND.ffmpeg $DEPEND.ffprobe

# 獲取媒體資訊模塊
Import-Module "$CURRENT_ROOT\modules\StreamsInfo.psm1"

$UV = @{
    # ======== 檢查依賴項 (bool) ========
    _CheckDependent        = {
        param (
            [array]$dependencies # 依賴項清單
        )
        $allExist = $true
        foreach ($dependency in $dependencies) {
            if (-not (Test-Path -LiteralPath $dependency)) {
                Write-Error "缺少依賴項: $dependency"
                $allExist = $false
            }
        }
        return $allExist
    }
    # ======== 檢查影片是否有 Alpha 通道 (bool) ========
    _CheckAlphaChannel     = {
        param (
            [string]$videoPath
        )
        $ffprobeOutput = & $DEPEND.ffprobe -v error -select_streams v:0 -show_entries stream=pix_fmt -of json "$videoPath" 2>&1
        $pixelFormat = ($ffprobeOutput | ConvertFrom-Json).streams[0].pix_fmt
        return $pixelFormat -match '(rgba|bgra|yuva444p|yuva422p|yuva420p)'
    }
    # ======== 日誌處理 (void) ========
    _LogProcess            = {
        # 讀取已完成的步驟
        $UV.completed = @{}
        if (Test-Path -LiteralPath $UV.logFile) {
            Get-Content -LiteralPath $UV.logFile | ForEach-Object { $UV.completed[$_] = $true }
        }

        # 記錄已完成的步驟到日誌
        $UV.writeLog = {
            param([string]$message, [string]$step, [bool]$print = $true)

            if ($LASTEXITCODE -ne 0) {
                if ($print) { Write-Error $message }
                return
            }

            Add-Content -LiteralPath $UV.logFile -Value $step
            $UV.completed[$step] = $true
        }

        $UV.chunks = @()
        if ($UV.chunkDurationSec -gt 0 -and $UV.totalDuration -gt $UV.chunkDurationSec) {
            $numChunks = [Math]::Ceiling($UV.totalDuration / $UV.chunkDurationSec)
            for ($i = 0; $i -lt $numChunks; $i++) {
                $startTimeSeconds = $i * $UV.chunkDurationSec
                $currentDuration = [Math]::Min($UV.chunkDurationSec, $UV.totalDuration - $startTimeSeconds)
                if ($currentDuration -le 0) { break }

                $UV.chunks += [PSCustomObject]@{
                    Index      = $i
                    StartTime  = [TimeSpan]::FromSeconds($startTimeSeconds).ToString("g")
                    Duration   = $currentDuration
                    OutputFile = Join-Path $UV.chunksDir "chunk_$($i.ToString('000')).$($UV.outputFormat)"
                }
            }
        }
        else {
            $UV.chunks += [PSCustomObject]@{
                Index      = 0
                StartTime  = "00:00:00"
                Duration   = $UV.totalDuration
                OutputFile = Join-Path $UV.chunksDir "chunk_000.$($UV.outputFormat)"
            }
        }
    }
    # ======== 通用 VRAM 參數計算 (7GB VRAM 標準 - 穩定優先) ========
    # ! 實驗性測試
    _GetVRAMParams         = {
        param(
            [int]$inputWidth,
            [int]$inputHeight,
            [int]$outputScale = 1,
            [string]$toolName = ""
        )

        $outputWidth = $inputWidth * $outputScale
        $outputHeight = $inputHeight * $outputScale
        $megaPixels = ($outputWidth * $outputHeight) / 1000000

        # 工具配置: [ThreadMult, ThreadOffset, MaxThread, TileMult, NoTile, TileOffset]
        # srmd/realesrgan/realcugan: tile 大可以提升效果，優先 tile 大
        # rife/ifrnet: 不使用 tile，只需要線程
        $toolConfig = @{
            srmd       = @(1.0, 0, 8, 1.0, $false, 0)
            realcugan  = @(1.2, 0, 10, 1.0, $false, 0)
            realesrgan = @(1.2, 0, 10, 1.0, $false, 0)
            rife       = @(1.0, 0, 8, 0, $true, 0)
            ifrnet     = @(1.0, 0, 8, 0, $true, 0)
        }

        # 基準參數: [MaxMP, Thread, Tile] (7GB VRAM 保守設定)
        $baseParams = @(
            @(1, 8, 0),   # < 1 MP (≤720p)
            @(2, 6, 512), # 1-2 MP (720p-1080p)
            @(4, 5, 256), # 2-4 MP (1080p-1440p)
            @(9, 4, 128), # 4-9 MP (1440p-4K)
            @(16, 3, 64), # 9-16 MP (4K-5K)
            @(35, 2, 32), # 16-35 MP (5K-8K)
            @([int]::MaxValue, 1, 0) # > 35 MP (>8K)
        )

        $base = $baseParams | Where-Object { $megaPixels -lt $_[0] } | Select-Object -First 1
        $baseThread = $base[1]
        $baseTile = $base[2]

        $config = $toolConfig[$toolName.ToLower()]
        if ($config) {
            # 計算線程數：保守計算，不拉極限，向下取整確保整數
            $thread = [Math]::Floor([Math]::Min($baseThread * $config[0] + $config[1], $config[2]))

            # 計算塊大小：優先效果，保持較大的 tile
            $tile = if ($config[4]) {
                $null
            }
            else {
                [int]($baseTile * $config[3] + $config[5])
            }
        }
        else {
            $thread = $baseThread
            $tile = $baseTile
        }

        return [PSCustomObject]@{
            Thread     = "$($thread):$($thread):$($thread)"
            Tile       = $tile
            MegaPixels = [Math]::Round($megaPixels, 2)
            OutputRes  = "${outputWidth}x${outputHeight}"
        }
    }
    # ======== FFmpeg 參數配置 (hashtable) ========
    # ! 實驗性測試
    _GetFFmpegParams       = {
        param(
            [ValidateSet("extract", "lossless", "output")]
            [string]$mode = "output"
        )

        $isModernFormat = $UV.outputFormat -match '^(mp4|mkv|mov|m4v)$'
        $isWebM = $UV.outputFormat -eq 'webm'

        # 如果是現代格式且無 Alpha，使用 10bit，否則標準 yuv420p
        $pixFmt = if ($isModernFormat) { "p010le" } else { "yuv420p" }

        # 如果有 Alpha 通道，強制不能使用 NVENC (因為硬體不支援 Alpha)
        # 並且如果輸出是 MP4，建議切換到 WebM 或 MOV，因為 MP4 對 Alpha 支援極差
        # 這裡為了相容性，若有 Alpha 則強制切換邏輯為 CPU 編碼
        if ($UV.hasAlpha) {
            $UV.fastEncode = $false # 強制關閉 GPU 編碼
        }

        # 統一位元率配置
        $bitrateTable = @{
            nvenc = @{
                720  = @("-b:v", "20000k", "-maxrate", "30000k", "-bufsize", "40000k")
                1080 = @("-b:v", "40000k", "-maxrate", "60000k", "-bufsize", "80000k")
                1440 = @("-b:v", "70000k", "-maxrate", "100000k", "-bufsize", "140000k")
                2160 = @("-b:v", "120000k", "-maxrate", "180000k", "-bufsize", "240000k")
            }
            vp9   = @{
                720  = @("-b:v", "18000k", "-minrate", "12000k", "-maxrate", "25000k")
                1080 = @("-b:v", "35000k", "-minrate", "25000k", "-maxrate", "50000k")
                1440 = @("-b:v", "65000k", "-minrate", "45000k", "-maxrate", "90000k")
                2160 = @("-b:v", "110000k", "-minrate", "75000k", "-maxrate", "150000k")
            }
            x265  = @{ 720 = 10; 1080 = 9; 1440 = 8; 2160 = 7 }
        }

        $getResKey = {
            $h = [int](($UV.scaled -split ":")[1])
            @(2160, 1440, 1080, 720) | Where-Object { $h -ge $_ } | Select-Object -First 1
        }

        switch ($mode) {
            "extract" {
                # 幀提取配置
                $hwaccelParams = if (-not $UV.hasAlpha -and $UV.ext -match '^(mp4|mkv|mov|m4v|webm)$') {
                    @('-hwaccel', 'cuda', '-hwaccel_output_format', 'cuda')
                }
                else { @() }

                # 有 Alpha 時使用 bgra，否則 rgb24
                $alphaPixelFormat = if ($UV.hasAlpha) { 'bgra' } else { 'rgb24' }

                $vfConfig = if ($hwaccelParams.Count -gt 0) {
                    "hwdownload,format=nv12,format=$alphaPixelFormat,fps=$($UV.fps)"
                }
                else {
                    "format=$alphaPixelFormat,fps=$($UV.fps)"
                }

                # 提取格式參數
                $codecParams = switch ($UV.frameCacheFormat) {
                    'webp' { @('-c:v', 'libwebp', '-lossless', '1', '-compression_level', '0', '-quality', '100', '-preset', 'picture') }
                    'png' { @('-c:v', 'png', '-pred', 'mixed', '-compression_level', '1') }
                    default { @('-q:v', '1') }
                }

                return @{
                    HwAccel     = $hwaccelParams
                    VideoFilter = $vfConfig
                    Codec       = $codecParams
                    PixelFormat = $alphaPixelFormat
                }
            }
            "lossless" {
                # 中間無損合併
                # 如果有 Alpha，使用 yuva444p10le 以保證最高精度
                $losslessPixFmt = if ($UV.hasAlpha) { 'yuva444p10le' } else { 'yuv420p10le' }

                $videoParams = if ($isWebM -or $UV.hasAlpha) {
                    # WebM 或 有 Alpha 時，強制使用 VP9 無損 (NVENC 不支援 Alpha)
                    $webmPixFmt = if ($UV.hasAlpha) { "yuva420p" } else { "yuv420p" }
                    @(
                        "-c:v", "libvpx-vp9", "-lossless", "1",
                        "-speed", "4", "-tile-columns", "4", "-frame-parallel", "1",
                        "-threads", "8", "-pix_fmt", $webmPixFmt
                    )
                }
                elseif ($UV.fastEncode) {
                    @(
                        "-c:v", "hevc_nvenc", "-profile:v", "main10",
                        "-preset", "p7", "-rc", "constqp", "-qp", "0",
                        "-tier", "high", "-pix_fmt", $losslessPixFmt
                    )
                }
                else {
                    @(
                        "-c:v", "libx265", "-preset", "ultrafast", "-crf", "0",
                        "-x265-params", "lossless=1", "-pix_fmt", $losslessPixFmt
                    )
                }

                return @{
                    VideoCodec = $videoParams
                    Container  = if ($isWebM -or $UV.hasAlpha) { @("-f", "webm") } else { @() }
                }
            }
            "output" {
                $resKey = & $getResKey
                # 最終輸出像素格式
                $outputPixFmt = if ($UV.hasAlpha) { 'yuva420p' } else { $pixFmt }

                $audioParams = if ($UV.ext -eq $UV.outputFormat) { @("-c:a", "copy") }
                else { @("-c:a", "aac", "-b:a", "256k") }

                # 如果有 Alpha，強制走 WebM/VP9 路徑 (相容性最好) 或 MOV/ProRes，這裡選用 VP9
                $useVP9 = $isWebM -or $UV.hasAlpha

                $videoParams = if ($useVP9) {
                    $bitrate = $bitrateTable.vp9[$resKey]
                    if ($UV.fastEncode) {
                        # VP9 Realtime (CPU 較快)
                        @(
                            "-c:v", "libvpx-vp9", "-b:v", "0", "-crf", "15",
                            "-deadline", "realtime", "-cpu-used", "4",
                            "-tile-columns", "4", "-frame-parallel", "1", "-threads", "8",
                            "-pix_fmt", $outputPixFmt
                        )
                    }
                    else {
                        # VP9 Quality
                        @(
                            "-c:v", "libvpx-vp9", "-b:v", "0", "-crf", "10",
                            "-deadline", "good", "-cpu-used", "1",
                            "-tile-columns", "4", "-row-mt", "1", "-threads", "8",
                            "-pix_fmt", $outputPixFmt
                        )
                    }
                }
                elseif ($UV.fastEncode) {
                    # NVENC (無 Alpha)
                    $bitrate = $bitrateTable.nvenc[$resKey]
                    @(
                        "-c:v", "hevc_nvenc", "-profile:v", "main10",
                        "-preset", "p7", "-tune", "hq",
                        "-rc", "vbr", "-cq", "10",
                        "-rc-lookahead", "32", "-spatial-aq", "1", "-temporal-aq", "1",
                        "-aq-strength", "8", "-b_ref_mode", "middle", "-tier", "high",
                        "-pix_fmt", $outputPixFmt
                    ) + $bitrate
                }
                else {
                    # x265 (CPU)
                    $crf = $bitrateTable.x265[$resKey]
                    @(
                        "-c:v", "libx265", "-preset", "slow", "-crf", $crf,
                        "-tune", "animation",
                        "-x265-params", "aq-mode=3:bframes=8:ref=6",
                        "-pix_fmt", $outputPixFmt
                    )
                }

                return @{
                    VideoCodec  = $videoParams
                    AudioCodec  = $audioParams
                    Container   = if ($isWebM) { @("-f", "webm") } else { @() }
                    IsWebM      = $isWebM
                    PixelFormat = $outputPixFmt
                }
            }
        }
    }
    # ======== 幀提取 (string) ========
    _ExtractFrames         = {
        param (
            [PSCustomObject]$chunk # 處理分段
        )
        $extractPath = Join-Path $UV.cachePath "%0$($UV.imgFill)d.$($UV.frameCacheFormat)"
    
        # 獲取提取配置
        $extractConfig = & $UV._GetFFmpegParams "extract"

        $ffmpegParams = @('-v', 'error') + $extractConfig.HwAccel + @(
            '-ss', $chunk.StartTime,
            '-t', $chunk.Duration,
            '-i', $UV.videoPath,
            '-an',
            '-vf', $extractConfig.VideoFilter,
            '-pix_fmt', $extractConfig.PixelFormat
        ) + $extractConfig.Codec + @($extractPath, '-y')

        $message = & $DEPEND.ffmpeg $ffmpegParams 2>&1
        return $message
    }
    # ======== 預處理 (void) ========
    _PreProcess            = {
        param(
            [string]$thread,
            [int]$tile
        )

        $params = @(
            '-i', $UV.cachePath,
            '-o', $UV.cachePath,
            '-n', $UV.preProcess[0],
            '-s', $UV.preProcess[1],
            '-j', $thread,
            '-t', $tile,
            '-f', $UV.frameCacheFormat
        )
        
        & $UV.preProcessCall $params
    }
    # ======== 補幀 (void) ========
    _Interpolator          = {
        param (
            [string]$fpsPath, # 補幀後的輸出路徑
            [string]$thread   # 動態線程參數
        )

        $interpolatorParams = @(
            '-i', $UV.cachePath,
            '-o', $fpsPath,
            '-m', $UV.interpolationModel.path,
            '-j', $thread,
            '-f', "%0$($UV.imgFill)d.$($UV.frameCacheFormat)",
            '-u'
        )

        # 可以自訂幀數
        if ($UV.interpolationModel.customFrame) {
            $interpolatorParams += @('-n', $UV.finalFrames)
        }

        # webp 品質
        if ($UV.interpolatorName -eq 'RIFE') {
            $interpolatorParams += @('-q', 100)
        }

        & $UV.interpolatorCall $interpolatorParams
    }
    # ======== 畫質提升 (void) ========
    _Upscaler              = {
        param(
            [string]$inputPath,
            [string]$thread,
            [int]$tile
        )

        $argsList = @(
            "-i", $inputPath,
            "-o", $inputPath,
            "-s", $UV.scaleFactor,
            "-j", $thread,
            "-t", $tile,
            "-f", $UV.frameCacheFormat,
            "-m", $UV.upscalerModels
        )

        # Realesrgan 額外需要指定模型名稱
        if ($UV.upscalerModelName) {
            $argsList += @("-n", $UV.upscalerModelName)
        }

        & $UV.upscalerCall $argsList
    }
    # ======== 核心處理函數 (void) ========
    _Core                  = {
        # 根據當前畫質判斷是否需要預處理
        $UV.preProcess = $UV.preProcessRules[(& $PARAMETER.GetResolution $UV.height)]

        $UV.vfUnsharp = "unsharp=3:3:0.03:3:3:0.0,deband=0.01:0.01:0.01:0.01:6:1"

        # 獲取編碼參數配置
        $outputEncodeConfig = & $UV._GetFFmpegParams "output"
        $losslessEncodeConfig = & $UV._GetFFmpegParams "lossless"

        # -------- 主處理迴圈 --------
        $ProgressPreference = "SilentlyContinue" # 隱藏進度條
        New-Item -ItemType Directory -Path $UV.chunksDir -Force | Out-Null # 創建分段目錄

        foreach ($chunk in $UV.chunks) {
            $chunkIndex = $chunk.Index + 1
            $chunkId = "CHUNK_$($chunkIndex)"

            if ($UV.completed.ContainsKey("$chunkId`_合併完成")) { continue }

            Write-Host "`n===== 段落 [$chunkIndex/$($UV.chunksCount)] 處理開始 (段落時間: $($chunk.StartTime)) =====>`n"

            $UV.cachePath = Join-Path $UV.cacheDir "cache-$chunkIndex"
            $currentCachePath = $UV.cachePath
            New-Item -ItemType Directory -Path $UV.cachePath -Force | Out-Null

            # ---- 追蹤當前解析度 (會隨著處理流程變化) ----
            $currentWidth = $UV.width
            $currentHeight = $UV.height

            # 1. 幀提取
            $step_extract = "$chunkId`_提取完成"
            if (-not $UV.completed.ContainsKey($step_extract)) {
                Write-Host "--> 幀提取 (Input=${currentWidth}x${currentHeight})"
                $message = & $UV._ExtractFrames $chunk
                & $UV.writeLog -message $message -step $step_extract
            }
            else { Write-Host "--> 幀提取 (完成跳過)" -ForegroundColor Gray }

            # 2. 預處理 (存在 $UV.preProcess 時代表需要預處理)
            $step_preProcess = "$chunkId`_預處理完成"
            if ($UV.preProcess -and (-not $UV.completed.ContainsKey($step_preProcess))) {
                if (Test-Path -LiteralPath $UV.cachePath -PathType Container) {
                    $preScale = $UV.preProcess[1]
                    $preParams = & $UV._GetVRAMParams $currentWidth $currentHeight $preScale "srmd"

                    Write-Host "--> 預處理 [SRMD] (Input=${currentWidth}x${currentHeight})"
                    Write-Host "Output=$($preParams.OutputRes), Thread=$($preParams.Thread), Tile=$($preParams.Tile), MegaPixels=$($preParams.MegaPixels)"

                    & $UV._PreProcess $preParams.Thread $preParams.Tile
                    & $UV.writeLog -step $step_preProcess

                    # 更新當前解析度
                    $currentWidth = $currentWidth * $preScale
                    $currentHeight = $currentHeight * $preScale
                }
                else { Write-Host "預處理錯誤: 找不到快取目錄" -ForegroundColor Red; continue }
            }
            elseif ($UV.preProcess) {
                # 即使跳過，也要更新解析度
                $preScale = $UV.preProcess[1]
                $currentWidth = $currentWidth * $preScale
                $currentHeight = $currentHeight * $preScale
                Write-Host "--> 預處理 (完成跳過, Output=${currentWidth}x${currentHeight})" -ForegroundColor Gray 
            }

            # 3. 補幀
            $step_interpolator = "$chunkId`_補幀完成"
            $fps_cachePath = "$($UV.cachePath)-fps"
            if (($UV.targetFPS -gt $UV.fps) -and (-not $UV.completed.ContainsKey($step_interpolator))) {
                if (Test-Path -LiteralPath $UV.cachePath -PathType Container) {
                    $interpParams = & $UV._GetVRAMParams $currentWidth $currentHeight 1 $UV.interpolatorName

                    Write-Host "--> 補幀 [$($UV.interpolatorName)] (Input=${currentWidth}x${currentHeight})"
                    Write-Host "Output=$($interpParams.OutputRes), Thread=$($interpParams.Thread), MegaPixels=$($interpParams.MegaPixels)"

                    New-Item -ItemType Directory -Path $fps_cachePath -Force | Out-Null

                    # 更新路徑給下一步使用
                    $currentCachePath = $fps_cachePath

                    & $UV._Interpolator $fps_cachePath $interpParams.Thread
                    & $UV.writeLog -step $step_interpolator

                    # 立即清理舊的快取以節省空間
                    Remove-Item -LiteralPath $UV.cachePath -Recurse -Force -ErrorAction SilentlyContinue
                }
                else { Write-Host "補幀錯誤, 找不到快取目錄: $($UV.cachePath)" -ForegroundColor Red; continue }
            }
            elseif ($UV.targetFPS -gt $UV.fps) {
                # 即使跳過，也要更新路徑
                $currentCachePath = $fps_cachePath
                Write-Host "--> 補幀 (完成跳過)" -ForegroundColor Gray
            }

            # 4. 畫質提升
            $step_realesr = "$chunkId`_提升完成"
            if ($UV.upscalerModels -and (-not $UV.completed.ContainsKey($step_realesr))) {
                if (Test-Path -LiteralPath $currentCachePath -PathType Container) {
                    $upscaleParams = & $UV._GetVRAMParams $currentWidth $currentHeight $UV.scaleFactor $UV.upscalerName

                    Write-Host "--> 畫質提升 [$($UV.upscalerName)] (Input=${currentWidth}x${currentHeight})"
                    Write-Host "Output=$($upscaleParams.OutputRes), Thread=$($upscaleParams.Thread), Tile=$($upscaleParams.Tile), MegaPixels=$($upscaleParams.MegaPixels)"

                    # 獲取資料夾內符合格式的圖片總數
                    if ((Get-ChildItem -LiteralPath $currentCachePath -Filter "*.$($UV.frameCacheFormat)" -File).Count -eq 0) {
                        Write-Host "畫質提升警告: 在 $currentCachePath 中找不到可處理的圖片，跳過此步驟。" -ForegroundColor Yellow
                        & $UV.writeLog -step $step_realesr
                        continue
                    }

                    & $UV._Upscaler $currentCachePath $upscaleParams.Thread $upscaleParams.Tile
            
                    if ($LASTEXITCODE -eq 0) {
                        & $UV.writeLog -step $step_realesr
                        $currentWidth = $currentWidth * $UV.scaleFactor
                        $currentHeight = $currentHeight * $UV.scaleFactor
                    }
                    else { Write-Host "畫質提升處理失敗，退出碼: $LASTEXITCODE" -ForegroundColor Red }
                }
                else { Write-Host "畫質提升錯誤: 找不到快取目錄" -ForegroundColor Red; continue }
            }
            elseif ($UV.upscalerModels) { 
                # 即使跳過，也要更新解析度
                $currentWidth = $currentWidth * $UV.scaleFactor
                $currentHeight = $currentHeight * $UV.scaleFactor
                Write-Host "--> 畫質提升 (完成跳過, Output=${currentWidth}x${currentHeight})" -ForegroundColor Gray 
            }

            # 5. 合併分段影片 (修正重點: 強制輸入與輸出的幀率一致)
            $step_merge_chunk = "$chunkId`_合併完成"
            if (-not $UV.completed.ContainsKey($step_merge_chunk)) {
                $imageInputPath = Join-Path $currentCachePath "%0$($UV.imgFill)d.$($UV.frameCacheFormat)"

                if (Get-ChildItem -LiteralPath $currentCachePath -Filter "*.$($UV.frameCacheFormat)" | Select-Object -First 1) {
                    Write-Host "--> 合併分段影片"

                    # 設定 FPS
                    $vfFilters = @("fps=$($UV.targetFPS)")

                    # 只有在指定自訂解析度時才縮放，否則保持 AI 輸出原尺寸 (避免縮小變形)
                    if ($UV.outputResolution) {
                        $scaleParam = if ($UV.reduce) { $UV.reduce } else { $UV.scaled }
                        $vfFilters += "scale=$($scaleParam):flags=lanczos:force_original_aspect_ratio=decrease"
                        $vfFilters += "pad=ceil(iw/2)*2:ceil(ih/2)*2" # 確保偶數像素
                    }

                    # 加入銳化
                    if ($UV.chunksCount -eq 1) { $vfFilters += $UV.vfUnsharp }

                    $finalVf = $vfFilters -join ","
                    $ffmpegParams = @(
                        '-v', 'error',
                        '-framerate', $UV.targetFPS,
                        '-start_number', 0,
                        '-i', $imageInputPath
                    )

                    if ($UV.chunksCount -eq 1) {
                        # 單一分段：直接輸出最終品質
                        $ffmpegParams += @('-i', $UV.videoPath)
                        $ffmpegParams += @('-vf', $finalVf)
                        $ffmpegParams += @('-map', '0:v:0', '-map', '1:a:0?')
                        $ffmpegParams += @('-r', $UV.targetFPS)
                        $ffmpegParams += $outputEncodeConfig.VideoCodec
                        $ffmpegParams += $outputEncodeConfig.AudioCodec
                        $ffmpegParams += $outputEncodeConfig.Container
                    }
                    else {
                        # 多分段：中間檔無損編碼
                        $ffmpegParams += @('-vf', $finalVf)
                        $ffmpegParams += @('-r', $UV.targetFPS)
                        $ffmpegParams += $losslessEncodeConfig.VideoCodec
                        $ffmpegParams += @('-an')
                        $ffmpegParams += $losslessEncodeConfig.Container
                    }

                    $ffmpegParams += @($chunk.OutputFile, '-y')

                    $message = & $DEPEND.ffmpeg $ffmpegParams 2>&1
                    & $UV.writeLog -message $message -step $step_merge_chunk
                }
                else { Write-Host "合併錯誤: 無圖片" -ForegroundColor Red; continue }
            }
            else { Write-Host "--> 合併分段影片 (完成跳過)" -ForegroundColor Gray }

            # 6. 即時清理
            if ($UV.completed.ContainsKey("$chunkId`_合併完成")) {
                Remove-Item -LiteralPath $UV.cachePath -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $fps_cachePath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "段落 [$chunkIndex/$($UV.chunksCount)] 完成清理。" -ForegroundColor Green
            }
        }

        # -------- 最終合併 --------
        $step_final_merge = "最終合併完成"
        if (-not $UV.completed.ContainsKey($step_final_merge)) {
            Write-Host "`n===== 所有段落處理完成，開始最終合併 =====>`n"

            # 定義最終輸出路徑
            $merge = $UV.fastEncode ? "fast" : "slow"
            $alphaTag = if ($UV.hasAlpha) { "-alpha" } else { "" }
            $upscaled_Path = "$($UV.outputTemplate)-x$($UV.scaleFactor)-$($UV.targetFPS)fps$alphaTag-$merge.$($UV.outputFormat)"

            # 只有一個分段時，直接移動檔案
            if ($UV.chunksCount -eq 1) {
                $sourceFile = $UV.chunks[0].OutputFile
                if (Test-Path -LiteralPath $sourceFile) {
                    try {
                        Move-Item -LiteralPath $sourceFile -Destination $upscaled_Path -Force
                        Write-Host "影片移動成功: $upscaled_Path" -ForegroundColor Cyan
                        & $UV.writeLog -step $step_final_merge
                    }
                    catch { Write-Host "影片移動失敗: $_" -ForegroundColor Red; exit }
                }
                else { Write-Host "段落合併錯誤: 找不到來源檔案" -ForegroundColor Red }
            }
            else {
                $concatListFile = Join-Path $UV.workDir "concat_list.txt"

                # 檢查所有預期的分段影片是否都存在
                $allChunksExist = $true
                foreach ($chunk in $UV.chunks) {
                    if (-not (Test-Path -LiteralPath $chunk.OutputFile)) {
                        Write-Host "最終合併錯誤: 找不到分段影片 $($chunk.OutputFile)" -ForegroundColor Red
                        $allChunksExist = $false; break
                    }
                }

                if ($allChunksExist) {
                    $UV.chunks | ForEach-Object { "file '$($_.OutputFile)'" } | Set-Content -LiteralPath $concatListFile

                    try {
                        $message = ""
                        $ffmpegParams = @("-v", "error")

                        # WebM 不使用 CUDA 加速合併
                        if ($UV.fastEncode -and -not $outputEncodeConfig.IsWebM) {
                            $ffmpegParams += @("-hwaccel", "cuda")
                        }

                        $ffmpegParams += @("-f", "concat", "-safe", "0", "-i", $concatListFile)

                        if ($UV.hasAudio) {
                            $ffmpegParams += @("-i", "$($UV.videoPath)")
                            $ffmpegParams += @("-map", "0:v:0", "-map", "1:a:0")
                            $ffmpegParams += $outputEncodeConfig.VideoCodec
                            $ffmpegParams += $outputEncodeConfig.AudioCodec
                        }
                        else {
                            $ffmpegParams += @("-map", "0:v:0")
                            $ffmpegParams += $outputEncodeConfig.VideoCodec
                            $ffmpegParams += @("-an")
                        }

                        # 最終合併時也加上 -r 以策安全，避免繼承到音軌的原始時間基準
                        $ffmpegParams += @("-r", $UV.targetFPS)
                        
                        $ffmpegParams += $outputEncodeConfig.Container
                        $ffmpegParams += @("$upscaled_Path", "-y")

                        $message = & $DEPEND.ffmpeg @ffmpegParams 2>&1

                        & $UV.writeLog -message $message -step $step_final_merge -print $false
                        if ($LASTEXITCODE -ne 0) { throw $message }

                        Write-Host "影片合併成功: $upscaled_Path" -ForegroundColor Cyan
                    }
                    catch { Write-Host "最終合併失敗: $_" -ForegroundColor Red; exit }
                }
            }
        }

        # -------- 清理工作目錄 --------
        if ($UV.completed.ContainsKey("最終合併完成")) {
            Write-Host "已清理所有工作檔案。"
            Remove-Item -LiteralPath $UV.workDir -Recurse -Force
            Read-Host "Enter 離開..."
        }
    }
    # ======== 運行調用 (void) ========
    Start                  = {
        if (-not(Test-Path -LiteralPath $UV.videoPath -PathType Leaf)) {
            Write-Host "錯誤的媒體: $($UV.videoPath)"
            return
        }

        # 獲取媒體副檔名
        $UV.ext = [System.IO.Path]::GetExtension($UV.videoPath).TrimStart('.')

        # -------- 初始化執行配置 --------

        $UV.outputPath = Split-Path -LiteralPath $UV.videoPath
        $UV.fileName = [System.IO.Path]::GetFileNameWithoutExtension($UV.videoPath)
        $UV.outputTemplate = Join-Path $UV.outputPath $UV.fileName # 組成輸出路徑的字串模板

        # 宣告預處理應用參數
        $UV.preProcessCall = Join-Path $CURRENT_ROOT "srmd-ncnn-vulkan.exe"
        $UV.preProcessModels = Join-Path $CURRENT_ROOT "models-srmd"

        # 宣告補幀應用參數
        switch ($UV.interpolator) {
            "ifrnet" {
                $UV.interpolatorName = "IFRNet"
                $UV.interpolatorCall = Join-Path $CURRENT_ROOT "ifrnet-ncnn-vulkan.exe"
                $UV.interpolatorModels = @{
                    1 = [PSCustomObject]@{
                        path        = Join-Path $CURRENT_ROOT "ifrnet-models/IFRNet_L_GoPro"
                        customFrame = $true
                    }
                    2 = [PSCustomObject]@{
                        path        = Join-Path $CURRENT_ROOT "ifrnet-models/IFRNet_Vimeo90K"
                        customFrame = $false
                    }
                    3 = [PSCustomObject]@{
                        path        = Join-Path $CURRENT_ROOT "ifrnet-models/IFRNet_L_Vimeo90K"
                        customFrame = $false
                    }
                }
                break
            }
            default {
                $UV.interpolatorName = "RIFE"
                $UV.interpolatorCall = Join-Path $CURRENT_ROOT "rife-ncnn-vulkan.exe"
                $UV.interpolatorModels = @{
                    1 = [PSCustomObject]@{
                        path        = Join-Path $CURRENT_ROOT "rife-models/rife-v4.26"
                        customFrame = $true
                    }
                    2 = [PSCustomObject]@{
                        path        = Join-Path $CURRENT_ROOT "rife-models/rife-anime"
                        customFrame = $false
                    }
                }
            }
        }

        # 獲取補幀模型
        $UV.interpolationModel = $UV.interpolatorModels[$UV.interpolatorModelIndex]

        # 宣告超分應用參數
        switch ($UV.upscaler) {
            "realcugan" {
                $UV.upscalerName = "RealCUGAN"
                $UV.upscalerCall = Join-Path $CURRENT_ROOT "realcugan-ncnn-vulkan.exe"
                $UV.upscalerModels = Join-Path $CURRENT_ROOT "realcugan-models-pro"
                break
            }
            default {
                $UV.upscalerName = "Realesrgan"
                $UV.upscalerCall = Join-Path $CURRENT_ROOT "realesrgan-ncnn-vulkan.exe"
                $UV.upscalerModels = Join-Path $CURRENT_ROOT "realesrgan-models"
            }
        }

        # -------- 初始化運算配置 --------

        # 根據解析度選擇 (降噪強度, 放大倍率)
        $UV.preProcessRules = @{
            144 = @(7, 2)
            240 = @(6, 2)
            360 = @(5, 2)
            480 = @(4, 2)
        }

        # realesrgan 限定, 自動模型選擇
        $UV.realesrganModelName = @{
            1 = ""
            2 = "realesr-animevideov3-x2"
            3 = "realesr-animevideov3-x3"
            4 = "realesr-animevideov3-x4"
        }

        # -------- 檢查依賴完整性 --------

        $result = & $UV._CheckDependent @(
            $UV.preProcessCall,
            $UV.preProcessModels,
            $UV.interpolatorCall,
            $UV.interpolationModel.path,
            $UV.upscalerCall,
            $UV.upscalerModels
        )

        if (-not $result) { return }

        # -------- 處理 媒體資訊 --------

        # 獲取影片資訊
        (
            $UV.width,
            $UV.height,
            $UV.fps,
            $UV.totalDuration,
            $UV.totalFrames,
            $UV.finalFrames,
            $UV.hasAudio
        ) = GetStreamsInfo $UV.videoPath $UV.targetFPS

        $UV.hasAlpha = & $UV._CheckAlphaChannel $UV.videoPath

        # 如果有提供自訂解析度且大於原始 FPS，則覆寫預設值
        $UV.targetFPS = $UV.targetFPS -gt $UV.fps ? $UV.targetFPS : $UV.fps

        # 不可自訂 FPS (預設直接 2 倍)
        if (-not ($UV.interpolationModel.customFrame)) {
            $UV.targetFPS = $UV.fps * 2
            $UV.finalFrames = $UV.totalFrames * 2
        }

        # 根據補幀後總幀數計算填充位數（至少 2 位）
        $UV.imgFill = [Math]::Max(([string]$UV.finalFrames).Length, 2)

        # ---- 處理 解析度 與 放大倍率 ----
        $UV.reduce = $null # 縮小後解析度
        $UV.scaled = & $PARAMETER.GetScaled `
            $UV.width `
            $UV.height `
            $UV.scaleFactor

        # 如果有提供自訂解析度，則覆寫預設值
        if ($UV.outputResolution) {
            ($UV.reduce, $UV.scaleFactor, $UV.scaled) = & $PARAMETER.GetCustomScale `
                $UV.width `
                $UV.height `
                $UV.outputResolution
        }

        # 確認放大倍率在 1-4 之間
        $UV.scaleFactor = [Math]::Max(1, [Math]::Min($UV.scaleFactor, 4))

        # 根據放大倍率獲取模型名稱
        $UV.upscalerModelName = $UV.upscalerName -eq "Realesrgan" ? $UV.realesrganModelName[$UV.scaleFactor] : ""

        # 如果放大倍率為 1 則不需要模型
        if ($UV.scaleFactor -eq 1) {
            $UV.upscalerModels = ""
        }

        # -------- 初始化工作目錄 與 日誌 --------
        $UV.workDir = "$(& $PARAMETER.GetCachePath $UV.outputPath $UV.fileName $UV.scaleFactor $UV.targetFPS)"
        $UV.cacheDir = (Test-Path -LiteralPath $UV.cacheDirectory) ? $UV.cacheDirectory : $UV.workDir # 如果有指定緩存目錄則使用
        $UV.chunksDir = Join-Path $UV.workDir "chunks"
        $UV.logFile = Join-Path $UV.workDir "progress.log"

        # 處理日誌 ($UV.chunks, $UV.completed, $UV.writeLog)
        & $UV._LogProcess
        # 取得分段數
        $UV.chunksCount = $UV.chunks.Count

        # -------- 輸出除錯資訊 --------
        @{
            "Meta" = @{
                "媒體資訊" = @{
                    "寬度"  = $UV.width
                    "高度"  = $UV.height
                    "FPS" = $UV.fps
                    "總時長" = $UV.totalDuration
                    "總幀數" = $UV.totalFrames
                }
                "輸出配置" = @{
                    "媒體路徑"  = $UV.videoPath
                    "放大倍率"  = $UV.scaleFactor
                    "目標FPS" = $UV.targetFPS
                    "輸出畫質"  = $UV.scaled
                    "輸出幀數"  = $UV.finalFrames
                    "輸出格式"  = $UV.outputFormat
                    "快速編碼"  = $UV.fastEncode
                    "分段秒數"  = $UV.chunkDurationSec
                    "分段數量"  = $UV.chunksCount
                    "合併目錄"  = $UV.workDir
                    "緩存目錄"  = $UV.cacheDir
                }
                "模型資訊" = @{
                    "預處理程式"  = $UV.preProcessCall
                    "預處理模型"  = $UV.preProcessModels
                    "補幀程式"   = $UV.interpolatorCall
                    "補幀模型"   = $UV.interpolationModel.path
                    "超分程式"   = $UV.upscalerCall
                    "超分模型路徑" = $UV.upscalerModels
                    "超分模型名稱" = $UV.upscalerModelName
                }
            }
        } | ConvertTo-Json -Depth 4 | Write-Host

        & $UV._Core
    }
    # ======== 初始參數 ========
    videoPath              = ""          # 輸入影片路徑
    upscaler               = "realcugan"  # 超分算法 (realcugan [老動漫適用] | realesrgan [通用] (模型速度較快, 更加激進修復) )
    interpolator           = "rife"   # 補幀算法 (rife [品質佳速度快] | ifrnet [品質高速度慢])
    <#
        ? 補幀算法模型
        ! 使用不可自訂的模型會自動將原始 FPS * 2
        * ifrnet: 1=IFRNet_L_GoPro | 2=IFRNet_Vimeo90K | 3=IFRNet_L_Vimeo90K (只有 GoPro 可自訂 FPS)
        * rife: 1=rife-v4.26 | 2=rife-anime (只有 rife-v4.26 可自訂 FPS)
    #>
    interpolatorModelIndex = 1
    targetFPS              = 24  # 目標 FPS（低於來源不會降）
    scaleFactor            = 2  # 放大倍率（1~4，1 表示不放大）
    outputFormat           = "mp4"  # 最終輸出影片格式 (支援: mp4, mkv, mov, webm, avi, m4v)
    frameCacheFormat       = "png"  # 中間幀緩存格式 (png [品質最佳] | webp [體積較小] | jpg [最快])
    cacheDirectory         = $null  # 自訂緩存目錄
    outputResolution       = $null  # 自訂輸出解析度
    fastEncode             = $true  # 快速編碼（否則高壓縮）
    chunkDurationSec       = 20  # 分段處理秒數，0 = 不分段
}

# --- 使用範例 ---
$UV.videoPath = "R:\Test-2.mp4"
$UV.upscaler = "realcugan"
$UV.interpolator = "rife"
$UV.interpolatorModelIndex = 1
$UV.targetFPS = 0
$UV.scaleFactor = 2
$UV.outputFormat = "mp4"
$UV.frameCacheFormat = "png"
$UV.cacheDirectory = ""
$UV.outputResolution = "1920x1080"
$UV.fastEncode = $true
$UV.chunkDurationSec = 15

# 執行
& $UV.Start