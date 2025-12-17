<#
    運行環境:
    PowerShell 7+

    重要說明:
    檔案路徑最好都是英文，不要有奇怪的符號或文字，否則可能會出現問題。 [PowerShell 麻煩的地方]
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
    # ======== 通用 VRAM 參數計算 (8GB VRAM 標準) ========
    _GetVRAMParams         = {
        <#
            .SYNOPSIS
            根據當前處理階段的解析度，動態計算 tile 和 thread 參數
            
            .PARAMETER inputWidth
            當前階段的輸入寬度
            
            .PARAMETER inputHeight
            當前階段的輸入高度
            
            .PARAMETER outputScale
            此階段的放大倍率（預設為 1，表示不放大）
            
            .PARAMETER toolName
            工具名稱，用於微調參數 (srmd | rife | ifrnet | realcugan | realesrgan)
            
            .OUTPUTS
            PSCustomObject 包含 Thread, Tile, MegaPixels, OutputRes
            
            .NOTES
            8GB VRAM 安全參數對照表 (基於輸出解析度)：
            ┌─────────────────┬─────────┬──────────┬────────────────────┐
            │ 輸出解析度(MP)  │ tile    │ thread   │ 約等於             │
            ├─────────────────┼─────────┼──────────┼────────────────────┤
            │ < 1 MP          │ 0(全圖) │ 8:8:8    │ ≤ 720p             │
            │ 1 - 2 MP        │ 0(全圖) │ 6:6:6    │ 720p - 1080p       │
            │ 2 - 4 MP        │ 400     │ 5:5:5    │ 1080p - 1440p      │
            │ 4 - 9 MP        │ 300     │ 4:4:4    │ 1440p - 4K         │
            │ 9 - 16 MP       │ 200     │ 3:3:3    │ 4K - 5K            │
            │ 16 - 35 MP      │ 150     │ 2:2:2    │ 5K - 8K            │
            │ > 35 MP         │ 100     │ 1:1:1    │ > 8K               │
            └─────────────────┴─────────┴──────────┴────────────────────┘
        #>
        param(
            [int]$inputWidth,
            [int]$inputHeight,
            [int]$outputScale = 1,
            [string]$toolName = ""
        )
        
        # 計算輸出像素量 (MegaPixels)
        $outputWidth = $inputWidth * $outputScale
        $outputHeight = $inputHeight * $outputScale
        $megaPixels = ($outputWidth * $outputHeight) / 1000000
        
        # 根據輸出像素量選擇基準參數
        ($thread, $tile) = switch ($true) {
            ($megaPixels -lt 1)  { @("8:8:8", 0);   break }  # ≤720p: 全圖處理
            ($megaPixels -lt 2)  { @("6:6:6", 0);   break }  # ~1080p: 全圖處理
            ($megaPixels -lt 4)  { @("5:5:5", 400); break }  # ~1440p
            ($megaPixels -lt 9)  { @("4:4:4", 300); break }  # ~4K
            ($megaPixels -lt 16) { @("3:3:3", 200); break }  # ~5K
            ($megaPixels -lt 35) { @("2:2:2", 150); break }  # ~8K
            default              { @("1:1:1", 100) }         # >8K
        }
        
        # 根據工具特性微調參數
        switch ($toolName.ToLower()) {
            "realcugan" {
                # RealCUGAN 模型較輕量，可使用更大 tile 提升速度
                if ($tile -gt 0) { 
                    $tile = [int][Math]::Min($tile * 1.5, 600) 
                }
            }
            "srmd" {
                # SRMD 較重，tile 需要更保守一些
                if ($tile -gt 0) { 
                    $tile = [int]($tile * 0.75) 
                }
            }
            "realesrgan" {
                # Realesrgan 中等負載，維持基準值
            }
            { $_ -in @("rife", "ifrnet") } {
                # 補幀工具不使用 tile，僅調整 thread
                $tile = $null
            }
        }
        
        return [PSCustomObject]@{
            Thread     = $thread
            Tile       = $tile
            MegaPixels = [Math]::Round($megaPixels, 2)
            OutputRes  = "${outputWidth}x${outputHeight}"
        }
    }
    # ======== 幀提取 (string) ========
    _ExtractFrames         = {
        param (
            [PSCustomObject]$chunk # 處理分段
        )
        $extractPath = Join-Path $UV.cachePath "%0$($UV.imgFill)d.$($UV.frameCacheFormat)"
        $vfConfigForExtract = "hwdownload,format=nv12,fps=$($UV.fps)"

        $ffmpegParams = @(
            '-v', 'error',
            '-hwaccel', 'cuda',
            '-hwaccel_output_format', 'cuda',
            '-ss', $chunk.StartTime,
            '-t', $chunk.Duration,
            '-i', $UV.videoPath,
            '-an',
            '-vf', $vfConfigForExtract,
            '-pix_fmt', 'rgb24',
            $extractPath,
            '-y'
        )

        if ($UV.frameCacheFormat -eq 'webp') {
            $ffmpegParams += @('-c:v', 'libwebp', '-lossless', 1)
        }
        else {
            $ffmpegParams += @('-q:v', 1)
        }

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
        # 根據目標解析度取用對應的參數
        $UV.nvencParams = $UV.nvencRules[[math]::Max((& $PARAMETER.GetResolution ($UV.scaled -split ":")[1]), 720)]

        $UV.vfUnsharp = "unsharp=2:2:0.08:2:2:0.0,deband=0.04:0.04:0.04:0.04:16:1"

        $isModernFormat = $UV.outputFormat -match '^(mp4|mkv|mov)$'
        $pixFmt = if ($isModernFormat) { "p010le" } else { "yuv420p" }

        $audioParams = if ($UV.ext -eq $UV.outputFormat) { 
            @("-c:a", "copy") 
        }
        else { 
            @("-c:a", "aac", "-b:a", "192k") 
        }

        $outputQuality = if ($UV.fastEncode) {
            @("-c:v", "hevc_nvenc", "-profile:v", "main10", "-preset", "p7", "-rc", "vbr_hq", "-qmin", "0", "-rc-lookahead", "32", "-spatial-aq", "1", "-aq-strength", "4", "-pix_fmt", $pixFmt) + $UV.nvencParams
        }
        else {
            @("-c:v", "libx265", "-preset", "slow", "-crf", "20", "-tune", "animation", "-x265-params", "aq-mode=3:strong-intra-smoothing=0:rect=0:aq-strength=0.9", "-pix_fmt", "yuv420p10le")
        }

        $losslessQuality = if ($UV.fastEncode) {
            @("-c:v", "hevc_nvenc", "-profile:v", "main10", "-preset", "p7", "-rc", "constqp", "-qp", "0", "-pix_fmt", $pixFmt)
        }
        else {
            @("-c:v", "libx265", "-preset", "ultrafast", "-crf", "0", "-pix_fmt", "yuv420p10le")
        }

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

            $UV.imgFill = ([string][Math]::Ceiling($chunk.Duration * $UV.targetFPS)).Length

            # ---- 追蹤當前解析度 (會隨著處理流程變化) ----
            $currentWidth = $UV.width
            $currentHeight = $UV.height

            # 1. 幀提取
            $step_extract = "$chunkId`_提取完成"
            if (-not $UV.completed.ContainsKey($step_extract)) {
                Write-Host "--> 幀提取 (解析度: ${currentWidth}x${currentHeight})"
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

                    Write-Host "--> 預處理 [SRMD] (輸入: ${currentWidth}x${currentHeight}, 輸出: $($preParams.OutputRes), 約$($preParams.MegaPixels)MP)"
                    Write-Host "    參數: Thread=$($preParams.Thread), Tile=$($preParams.Tile)"

                    & $UV._PreProcess $preParams.Thread $preParams.Tile
                    & $UV.writeLog -step $step_preProcess

                    # 更新當前解析度
                    $currentWidth = $currentWidth * $preScale
                    $currentHeight = $currentHeight * $preScale
                }
                else { Write-Host "預處理錯誤: 找不到快取目錄 $($UV.cachePath)" -ForegroundColor Red; continue }
            }
            elseif ($UV.preProcess) { 
                # 即使跳過，也要更新解析度
                $preScale = $UV.preProcess[1]
                $currentWidth = $currentWidth * $preScale
                $currentHeight = $currentHeight * $preScale
                Write-Host "--> 預處理 (完成跳過, 當前解析度: ${currentWidth}x${currentHeight})" -ForegroundColor Gray 
            }

            # 3. 補幀
            $step_interpolator = "$chunkId`_補幀完成"
            $fps_cachePath = "$($UV.cachePath)-fps"
            if (($UV.targetFPS -gt $UV.fps) -and (-not $UV.completed.ContainsKey($step_interpolator))) {
                if (Test-Path -LiteralPath $UV.cachePath -PathType Container) {
                    # 計算補幀階段的 VRAM 參數 (補幀不改變解析度，scale = 1)
                    $interpParams = & $UV._GetVRAMParams $currentWidth $currentHeight 1 $UV.interpolatorName

                    Write-Host "--> 補幀 [$($UV.interpolatorName)] (解析度: ${currentWidth}x${currentHeight}, 約$($interpParams.MegaPixels)MP)"
                    Write-Host "    參數: Thread=$($interpParams.Thread)"

                    New-Item -ItemType Directory -Path $fps_cachePath -Force | Out-Null

                    # 更新路徑給下一步使用
                    $currentCachePath = $fps_cachePath

                    & $UV._Interpolator $fps_cachePath $interpParams.Thread
                    & $UV.writeLog -step $step_interpolator

                    # 立即清理舊的快取以節省空間
                    Remove-Item -LiteralPath $UV.cachePath -Recurse -Force -ErrorAction SilentlyContinue
                }
                else { Write-Host "補幀錯誤: 找不到快取目錄 $($UV.cachePath)" -ForegroundColor Red; continue }
            }
            elseif ($UV.targetFPS -gt $UV.fps) {
                $currentCachePath = $fps_cachePath # 即使跳過，路徑也需要更新
                Write-Host "--> 補幀 (完成跳過)" -ForegroundColor Gray
            }

            # 4. 畫質提升
            $step_realesr = "$chunkId`_提升完成"
            if ($UV.upscalerModels -and (-not $UV.completed.ContainsKey($step_realesr))) {
                if (Test-Path -LiteralPath $currentCachePath -PathType Container) {
                    # 計算超分階段的 VRAM 參數
                    $upscaleParams = & $UV._GetVRAMParams $currentWidth $currentHeight $UV.scaleFactor $UV.upscalerName
                    
                    Write-Host "--> 畫質提升 [$($UV.upscalerName)] (輸入: ${currentWidth}x${currentHeight}, 輸出: $($upscaleParams.OutputRes), 約$($upscaleParams.MegaPixels)MP)"
                    Write-Host "    參數: Thread=$($upscaleParams.Thread), Tile=$($upscaleParams.Tile)"

                    # 獲取資料夾內符合格式的圖片總數
                    $totalImages = (Get-ChildItem -LiteralPath $currentCachePath -Filter "*.$($UV.frameCacheFormat)" -File).Count
                    if ($totalImages -eq 0) {
                        Write-Host "畫質提升警告: 在 $currentCachePath 中找不到可處理的圖片，跳過此步驟。" -ForegroundColor Yellow
                        & $UV.writeLog -step $step_realesr
                        continue
                    }

                    & $UV._Upscaler $currentCachePath $upscaleParams.Thread $upscaleParams.Tile
                    
                    if ($LASTEXITCODE -eq 0) {
                        & $UV.writeLog -step $step_realesr
                        
                        # 更新當前解析度
                        $currentWidth = $currentWidth * $UV.scaleFactor
                        $currentHeight = $currentHeight * $UV.scaleFactor
                    }
                    else {
                        Write-Host "畫質提升處理失敗，退出碼: $LASTEXITCODE" -ForegroundColor Red
                    }
                }
                else { Write-Host "畫質提升錯誤: 找不到快取目錄 $currentCachePath" -ForegroundColor Red; continue }
            }
            elseif ($UV.upscalerModels) { 
                # 即使跳過，也要更新解析度
                $currentWidth = $currentWidth * $UV.scaleFactor
                $currentHeight = $currentHeight * $UV.scaleFactor
                Write-Host "--> 畫質提升 (完成跳過, 當前解析度: ${currentWidth}x${currentHeight})" -ForegroundColor Gray 
            }

            # 5. 合併分段影片 (無音訊)
            $step_merge_chunk = "$chunkId`_合併完成"
            if (-not $UV.completed.ContainsKey($step_merge_chunk)) {

                # 設置縮放參數
                $baseVf = if ($UV.reduce) {
                    "fps=$($UV.targetFPS),scale=$($UV.reduce):flags=lanczos:force_original_aspect_ratio=decrease"
                }
                else {
                    "fps=$($UV.targetFPS),scale=$($UV.scaled):flags=lanczos"
                }

                $imageInputPath = Join-Path $currentCachePath "%0$($UV.imgFill)d.$($UV.frameCacheFormat)"
                if (Get-ChildItem -LiteralPath $currentCachePath -Filter "*.$($UV.frameCacheFormat)" | Select-Object -First 1) {
                    Write-Host "--> 合併分段影片 (最終解析度: ${currentWidth}x${currentHeight})"
 
                    $ffmpegParams = @(
                        '-v', 'error',
                        '-framerate', $UV.targetFPS,
                        '-start_number', 0,
                        '-i', $imageInputPath
                    )

                    if ($UV.chunksCount -eq 1) {
                        $ffmpegParams += @('-i', $UV.videoPath)
                        $ffmpegParams += @('-vf', "$baseVf,$($UV.vfUnsharp)")
                        $ffmpegParams += $outputQuality
                        $ffmpegParams += @('-map', '0:v:0', '-map', '1:a:0')
                        $ffmpegParams += $audioParams
                        $ffmpegParams += @($chunk.OutputFile, '-y')
                    }
                    else {
                        # 有多個分段，暫不合併音訊 (分段時無損壓縮)
                        $ffmpegParams += @('-vf', $baseVf)
                        $ffmpegParams += $losslessQuality
                        $ffmpegParams += @('-an', $chunk.OutputFile, '-y')
                    }

                    $message = & $DEPEND.ffmpeg $ffmpegParams 2>&1
                    & $UV.writeLog -message $message -step $step_merge_chunk
                }
                else { Write-Host "合併錯誤: 在 $currentCachePath 中找不到圖片序列" -ForegroundColor Red; continue }
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
            $upscaled_Path = "$($UV.outputTemplate)-x$($UV.scaleFactor)-$($UV.targetFPS)fps-$merge.$($UV.outputFormat)"

            # 只有一個分段時，直接移動檔案
            if ($UV.chunksCount -eq 1) {
                $sourceFile = $UV.chunks[0].OutputFile
                if (Test-Path -LiteralPath $sourceFile) {
                    try {
                        Move-Item -LiteralPath $sourceFile -Destination $upscaled_Path -Force
                        Write-Host "影片移動成功: $upscaled_Path" -ForegroundColor Cyan
                        & $UV.writeLog -step $step_final_merge
                    }
                    catch {
                        Write-Host "影片移動失敗: $_" -ForegroundColor Red
                        exit
                    }
                }
                else {
                    Write-Host "段落合併錯誤: 找不到來源檔案 $sourceFile" -ForegroundColor Red
                }
            }
            else {
                $concatListFile = Join-Path $UV.workDir "concat_list.txt"

                # 檢查所有預期的分段影片是否都存在
                $allChunksExist = $true
                foreach ($chunk in $UV.chunks) {
                    if (-not (Test-Path -LiteralPath $chunk.OutputFile)) {
                        Write-Host "最終合併錯誤: 找不到分段影片 $($chunk.OutputFile)" -ForegroundColor Red
                        $allChunksExist = $false
                        break
                    }
                }

                if ($allChunksExist) {
                    $UV.chunks | ForEach-Object { "file '$($_.OutputFile)'" } | Set-Content -LiteralPath $concatListFile

                    $originalAudio = & $DEPEND.ffprobe -v error -i "$($UV.videoPath)" -select_streams a -show_streams -of json
                    $hasOriginalAudio = -not [string]::IsNullOrEmpty($originalAudio)

                    $ffmpegParams = @("-v", "error")

                    if ($UV.fastEncode) {
                        $ffmpegParams += @("-hwaccel", "cuda")
                    }

                    try {
                        $message = ""
                        $ffmpegParams += @("-f", "concat", "-safe", "0")

                        if ($hasOriginalAudio) {
                            $ffmpegParams += @(
                                '-i', $concatListFile,
                                '-i', "$($UV.videoPath)"
                            )
                            $ffmpegParams += $outputQuality
                            $ffmpegParams += @(
                                '-map', '0:v:0',
                                '-map', '1:a:0'
                            )
                            $ffmpegParams += $audioParams
                            $ffmpegParams += @("$upscaled_Path", '-y')

                            $message = & $DEPEND.ffmpeg @ffmpegParams 2>&1
                        }
                        else {
                            $ffmpegParams += @('-i', $concatListFile)
                            $ffmpegParams += $outputQuality
                            $ffmpegParams += @('-an', "$upscaled_Path", '-y')
                            
                            $message = & $DEPEND.ffmpeg @ffmpegParams 2>&1
                        }

                        & $UV.writeLog -message $message -step $step_final_merge -print $false
                        if ($LASTEXITCODE -ne 0) { throw $message }

                        Write-Host "影片合併成功: $upscaled_Path" -ForegroundColor Cyan
                    }
                    catch {
                        Write-Host "最終合併失敗: $_" -ForegroundColor Red
                        exit
                    }
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

        # 預設位元率較高 (因為可能有 3D 動畫之類的)
        $UV.nvencRules = @{
            720  = @("-b:v", "7000k", "-maxrate", "10000k", "-cq", "22")
            1080 = @("-b:v", "12000k", "-maxrate", "15000k", "-cq", "21")
            1440 = @("-b:v", "24000k", "-maxrate", "40000k", "-cq", "20") 
            2160 = @("-b:v", "40000k", "-maxrate", "60000k", "-cq", "19") 
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
            $UV.finalFrames
        ) = GetStreamsInfo $UV.videoPath $UV.targetFPS

        # 如果有提供自訂解析度且大於原始 FPS，則覆寫預設值
        $UV.targetFPS = $UV.targetFPS -gt $UV.fps ? $UV.targetFPS : $UV.fps

        # 不可自訂 FPS (預設直接 2 倍)
        if (-not ($UV.interpolationModel.customFrame)) {
            $UV.targetFPS = $UV.fps * 2
            $UV.finalFrames = $UV.totalFrames * 2
        }

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
        $UV.upscalerModelName = $UV.upscalerName -eq "Realesrgan" ? $UV.realesrganModelName[$UV.scaleFactor] : $null

        # -------- 初始化工作目錄 與 日誌 --------
        $UV.workDir = "$(& $PARAMETER.GetCachePath $UV.outputPath $UV.fileName $UV.scaleFactor $UV.targetFPS)"
        $UV.cacheDir = (Test-Path -LiteralPath $UV.cacheDirectory) ? $UV.cacheDirectory : $UV.workDir # 如果有指定緩存目錄則使用
        $UV.chunksDir = Join-Path $UV.workDir "chunks"
        $UV.logFile = Join-Path $UV.workDir "progress.log"

        # 處理日誌 ($UV.chunks, $UV.completed, $UV.writeLog)
        & $UV._LogProcess
        # 取得分段數
        $UV.chunksCount = $UV.chunks.Count

        # -------- 預計算各階段解析度變化 (用於除錯資訊) --------
        $preScale = if ($UV.preProcessRules[(& $PARAMETER.GetResolution $UV.height)]) { 
            $UV.preProcessRules[(& $PARAMETER.GetResolution $UV.height)][1] 
        } else { 1 }
        
        $stageInfo = @{
            "階段1_原始"     = "$($UV.width)x$($UV.height)"
            "階段2_預處理後" = "$($UV.width * $preScale)x$($UV.height * $preScale)"
            "階段3_補幀後"   = "$($UV.width * $preScale)x$($UV.height * $preScale) (解析度不變)"
            "階段4_超分後"   = "$($UV.width * $preScale * $UV.scaleFactor)x$($UV.height * $preScale * $UV.scaleFactor)"
        }

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
                "解析度變化" = $stageInfo
                "模型資訊" = @{
                    "預處理程式" = $UV.preProcessCall
                    "預處理模型" = $UV.preProcessModels
                    "補幀程式"  = $UV.interpolatorCall
                    "補幀模型"  = $UV.interpolationModel.path
                    "超分程式"  = $UV.upscalerCall
                    "超分模型路徑"  = $UV.upscalerModels
                    "超分模型名稱" = $UV.upscalerModelName
                }
            }
        } | ConvertTo-Json -Depth 4 | Write-Host

        & $UV._Core
    }
    # ======== 調用參數 ========
    videoPath              = ""          # 輸入影片路徑
    upscaler               = "realcugan"  # 超分算法 (realcugan [動漫適用] | realesrgan [通用] (使用的模型速度較快) )
    interpolator           = "rife"   # 補幀算法 (rife [品質佳速度快] | ifrnet [品質高速度慢])
    <#
        ? 補幀算法模型
        ! 使用不可自訂的模型會自訂將原始 FPS * 2
        * ifrnet: 1=IFRNet_L_GoPro | 2=IFRNet_Vimeo90K | 3=IFRNet_L_Vimeo90K (只有 GoPro 可自訂 FPS)
        * rife: 1=rife-v4.26 | 2=rife-anime (只有 rife-v4.26 可自訂 FPS)
    #>
    interpolatorModelIndex = 1
    targetFPS              = 24  # 目標 FPS（低於來源不會降）
    scaleFactor            = 2  # 放大倍率（1~4，1 表示不放大）
    outputFormat           = "mp4"  # 最終輸出影片格式
    frameCacheFormat       = "png"  # 中間幀緩存格式
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
$UV.chunkDurationSec = 30

# 執行
& $UV.Start