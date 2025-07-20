<#
    利用 Real-ESRGAN, RIFE, SRMD 等 AI 模型增強影片畫質、提升幀率。

    _ooOoo_
    o8888888o
    88" . "88
    (| -_- |)
     O\ = /O
    ___/`---'\____
    .   ' \\| |// `.
    / \\||| : |||// \
    / _||||| -:- |||||- \
    | | \\\ - /// | |
    | \_|" ''\---/'' | |
    \ .-\__ `-` ___/-. /
    ___`. .' /--.--\ `. . __
    ."" '< `.___\_<|>_/___.' >'"".
    | | : `- \`;`\ _ /`;.`/ - ` : | |
    \ \ `-. \_ __\ /__ _/ .-` / /
    ======`-.____`-.___\_____/___.-`____.-'======
    `=---='

    運行環境:
    PowerShell 7+
#>

# 取得指令碼位置
$currentRoot = $PSScriptRoot

# 載入依賴專案
Import-Module "$currentRoot/modules/LoadDependencies.psm1"
$Dep = FetchDependent $currentRoot # 初始化導入

# 載入引數生成器
Import-Module "$currentRoot/modules/ParameterGen.psm1"
$Gen = Generator $Dep.ffmpeg $Dep.ffprobe # 例項化數生成器

# 獲取媒體資訊模塊
Import-Module "$currentRoot/modules/StreamsInfo.psm1"

function VideoUpscaler {
    param (
        [string]$VideoPath, # 影片路徑
        [int]$TargetFPS = 24, # 目標 FPS (設置低於原始媒體, 並不會下降)
        [int]$UpscaleFactor = 2, # 放大倍率 (設置 1 ~ 4) [1 就什麼都不做]
        [string]$OutputFormat = "mp4", # 最終合併影片格式
        [string]$ProcessFormat = "png", # 處理的緩存圖片格式
        [string]$CustomResolution = $null, # 自定輸出解析度
        [boolean]$FastOutput = $true, # 快速輸出 [慢速壓縮率較高]
        [int]$ChunkDuration = 15 # 分段處理的時長（秒），0 為不分段
    )

    if (-not(Test-Path -LiteralPath $VideoPath)) {
        Write-Host "錯誤的媒體路徑: $VideoPath"
        exit
    }
    $VideoPath = Convert-Path -LiteralPath $VideoPath

    # -------- 初始化運算配置 --------
    $srmdRules = @{
        144 = @(10, 4)
        240 = @(9, 3)
        360 = @(8, 2)
        480 = @(7, 2)
    }
    $fpsModelRules = @{
        1 = "rife-models\rife-v4.24_ensembleTrue"
        2 = "rife-models\rife-v4.26-large_ensembleFalse"
    }
    $upscaleModelRules = @{
        1 = ""
        2 = "realesr-animevideov3-x2"
        3 = "realesr-animevideov3-x3"
        4 = "realesr-animevideov3-x4"
    }
    $outputTemplate = "$(Split-Path $VideoPath)\$([System.IO.Path]::GetFileNameWithoutExtension($VideoPath))"

    # -------- 獲取媒體資訊 --------
    ($width, $height, $fps, $totalDuration, $totalFrames, $fillerFrame) = GetStreamsInfo $VideoPath $TargetFPS $UpscaleFactor

    # ---- 解析解析度與放大倍率 ----
    $reduce = $null
    $scaled = & $Gen.GetScaled $width $height $UpscaleFactor

    # 如果有提供自訂解析度，則覆寫預設值
    if ($CustomResolution) {
        ($reduce, $UpscaleFactor, $scaled) = & $Gen.GetCustomScale $width $height $CustomResolution
    }

    # 4. 最終確認放大倍率在 1-4 之間
    $UpscaleFactor = [Math]::Max(1, [Math]::Min($UpscaleFactor, 4))

    # -------- 工作目錄、日誌與分段邏輯 --------
    $workDir = "$outputTemplate`_Upscaler"
    $chunksDir = Join-Path $workDir "chunks"
    $logFile = Join-Path $workDir "progress.log"

    # 讀取已完成的步驟
    $completedSteps = @{}
    if (Test-Path $logFile) {
        Get-Content $logFile | ForEach-Object { $completedSteps[$_] = $true }
    }
    
    # 輔助函式：記錄已完成的步驟到日誌
    function WriteProgressLog {
        param([string]$Step)
        Add-Content -Path $logFile -Value $Step
        $completedSteps[$Step] = $true
    }

    $chunks = @()
    if ($ChunkDuration -gt 0 -and $totalDuration -gt $ChunkDuration) {
        $numChunks = [Math]::Ceiling($totalDuration / $ChunkDuration)
        for ($i = 0; $i -lt $numChunks; $i++) {
            $startTimeSeconds = $i * $ChunkDuration
            $currentDuration = [Math]::Min($ChunkDuration, $totalDuration - $startTimeSeconds)
            if ($currentDuration -le 0) { break }

            $chunks += [PSCustomObject]@{
                Index      = $i
                StartTime  = [TimeSpan]::FromSeconds($startTimeSeconds).ToString("g")
                Duration   = $currentDuration
                OutputFile = Join-Path $chunksDir "chunk_$($i.ToString('000')).$OutputFormat"
            }
        }
    }
    else {
        $chunks += [PSCustomObject]@{
            Index      = 0
            StartTime  = "00:00:00"
            Duration   = $totalDuration
            OutputFile = Join-Path $chunksDir "chunk_000.$OutputFormat"
        }
    }

    # -------- 解析通用配置 --------
    $thread = "6:6:6"
    $chunksCount = $chunks.Count
    $TargetFPS = $TargetFPS -gt $fps ? $TargetFPS : $fps

    $srmdProcess = $srmdRules[$(& $Gen.GetResolution $height)]
    $fpsModels = $fpsModelRules[2] | Where-Object { $Dep.rifeModelList[$_] }
    $upscaleModels = $upscaleModelRules[$UpscaleFactor] | Where-Object { $Dep.realesrganModelList[$_] }

    $vfUnsharp = "deband,unsharp=3:3:0.4:3:3:0.0"

    $outputQuality = if ($FastOutput) {
        @("-c:v", "hevc_nvenc", "-profile:v", "main10", "-preset", "p7", "-rc", "vbr", "-cq", "22", "-qmin", "0", "-rc-lookahead", "32", "-spatial-aq", "1", "-pix_fmt", "p010le")
    }
    else {
        @("-c:v", "libx265", "-preset", "slow", "-crf", "20", "-tune", "animation", "-x265-params", "aq-mode=3:strong-intra-smoothing=0:rect=0:aq-strength=0.9", "-pix_fmt", "yuv420p10le")
    }

    # -------- 輸出除錯資訊 --------
    @{
        "Meta" = @{
            "媒體資訊" = @{
                "寬度"  = $width
                "高度"  = $height
                "FPS" = $fps
                "總時長" = $totalDuration
                "總幀數" = $totalFrames
            }
            "輸出配置" = @{
                "媒體路徑"  = $VideoPath
                "放大倍率"  = $UpscaleFactor
                "目標FPS" = $TargetFPS
                "輸出畫質"  = $scaled
                "輸出幀數"  = $fillerFrame
                "輸出格式"  = $OutputFormat
                "快速合併"  = $FastOutput
                "分段秒數"  = $ChunkDuration
                "分段數量"  = $chunksCount
                "工作目錄"  = $workDir
            }
            "模型資訊" = @{
                "補幀模型" = $fpsModels
                "增強模型" = $upscaleModels
            }
        }
    } | ConvertTo-Json -Depth 4 | Write-Host

    # -------- 主處理迴圈 --------
    New-Item -ItemType Directory -Path $chunksDir -Force | Out-Null


    foreach ($chunk in $chunks) {
        $chunkId = "CHUNK_$($chunk.Index)"
        if ($completedSteps.ContainsKey("$chunkId`_合併完成")) {
            continue
        }

        Write-Host "`n===== 段落 [$($chunk.Index + 1)/$($chunksCount)] 處理開始 (段落時間: $($chunk.StartTime)) =====>`n"
        $cachePath = Join-Path $workDir "cache_$($chunk.Index)"
        $currentCachePath = $cachePath # 該路徑在RIFE處理後會更新
        New-Item -ItemType Directory -Path $cachePath -Force | Out-Null

        $imgFormat = ([string][Math]::Ceiling($chunk.Duration * $TargetFPS)).Length

        # 1. 幀提取
        $step_extract = "$chunkId`_提取完成"
        if (-not $completedSteps.ContainsKey($step_extract)) {
            Write-Host "--> 步驟 1/5: 幀提取"
            $extractPath = Join-Path $cachePath "%0$($imgFormat)d.$processFormat"
            $vfConfigForExtract = "hwdownload,format=nv12,unsharp=3:3:0.2,fps=$fps"

            $ffmpegParams = @(
                '-v', 'error',
                '-hwaccel', 'cuda',
                '-hwaccel_output_format', 'cuda',
                '-ss', $chunk.StartTime,
                '-t', $chunk.Duration,
                '-i', $VideoPath,
                '-an',
                '-vf', $vfConfigForExtract,
                '-pix_fmt', 'rgb24',
                $extractPath,
                '-y'
            )

            if ($ProcessFormat -eq 'webp') {
                $ffmpegParams += @('-c:v', 'libwebp', '-lossless', 1)
            }
            else {
                $ffmpegParams += @('-q:v', 1)
            }

            & $Dep.ffmpeg $ffmpegParams
            WriteProgressLog $step_extract
        }
        else { Write-Host "--> 步驟 1/5: 幀提取 (完成跳過)" -ForegroundColor Gray }

        # 2. 預處理 (SRMD)
        $step_srmd = "$chunkId`_SRMD_預處理完成"
        if ($srmdProcess -and (-not $completedSteps.ContainsKey($step_srmd))) {
            if (Test-Path $cachePath -PathType Container) {
                Write-Host "--> 步驟 2/5: 預處理 (SRMD)"
                & $Dep.srmd -i "$cachePath" -o "$cachePath" -n "$($srmdProcess[0])" -s "$($srmdProcess[1])" -j "$thread" -f "$ProcessFormat"
                WriteProgressLog $step_srmd
            }
            else { Write-Host "SRMD 錯誤: 找不到快取目錄 $cachePath" -ForegroundColor Red; continue }
        }
        elseif ($srmdProcess) { Write-Host "--> 步驟 2/5: 預處理 (SRMD) (完成跳過)" -ForegroundColor Gray }

        # 3. 補幀 (RIFE)
        $step_rife = "$chunkId`_RIFE_補幀完成"
        if (($TargetFPS -gt $fps) -and (-not $completedSteps.ContainsKey($step_rife))) {
            if (Test-Path $cachePath -PathType Container) {
                Write-Host "--> 步驟 3/5: 幀數提升 (RIFE)"
                $fpsPath = "$cachePath-fps"
                New-Item -ItemType Directory -Path $fpsPath -Force | Out-Null

                $numFramesToGenerate = [Math]::Ceiling($chunk.Duration * $TargetFPS)
                $outputFileFormat = "%0$($imgFormat)d.$processFormat"

                & $Dep.rife -i "$cachePath" -o "$fpsPath" -n "$numFramesToGenerate" -m "$fpsModels" -j "$thread" -q 100 -f "$outputFileFormat"

                # 更新路徑給下一步使用
                $currentCachePath = $fpsPath
                WriteProgressLog $step_rife

                # 立即清理舊的快取以節省空間
                Write-Host "RIFE 處理完成，正在清理原始幀快取..." -ForegroundColor DarkGray
                Remove-Item $cachePath -Recurse -Force -ErrorAction SilentlyContinue
            }
            else { Write-Host "RIFE 錯誤: 找不到快取目錄 $cachePath" -ForegroundColor Red; continue }
        }
        elseif ($TargetFPS -gt $fps) {
            $currentCachePath = "$cachePath-fps" # 即使跳過，路徑也需要更新
            Write-Host "--> 步驟 3/5: 幀數提升 (RIFE) (完成跳過)" -ForegroundColor Gray
        }

        # 4. 畫質提升 (Real-ESRGAN)
        $step_realesr = "$chunkId`_RealESRGAN_提升完成"
        if ($upscaleModels -and (-not $completedSteps.ContainsKey($step_realesr))) {
            if (Test-Path $currentCachePath -PathType Container) {
                Write-Host "--> 步驟 4/5: 畫質提升 (Real-ESRGAN)"
                & $Dep.realesr -i "$currentCachePath" -o "$currentCachePath" -s "$UpscaleFactor" -m "$($Dep.realesrganModelFolder)" -n "$upscaleModels" -t 0 -j "$thread" -f "$ProcessFormat"
                WriteProgressLog $step_realesr
            }
            else { Write-Host "Real-ESRGAN 錯誤: 找不到快取目錄 $currentCachePath" -ForegroundColor Red; continue }
        }
        elseif ($upscaleModels) { Write-Host "--> 步驟 4/5: 畫質提升 (Real-ESRGAN) (完成跳過)" -ForegroundColor Gray }

        # 5. 合併分段影片 (無音訊)
        $step_merge_chunk = "$chunkId`_合併完成"
        if (-not $completedSteps.ContainsKey($step_merge_chunk)) {
            # 組合包含銳化等效果的濾鏡鏈
            $baseVf = if ($reduce) { "scale=$reduce,fps=$fps" } else { "scale=$scaled,fps=$fps" }
            $vfConfig = "$baseVf,$vfUnsharp"

            $imageInputPath = Join-Path $currentCachePath "%0$($imgFormat)d.$processFormat"
            if (Get-ChildItem -Path $currentCachePath -Filter "*.$processFormat" | Select-Object -First 1) {
                Write-Host "--> 步驟 5/5: 合併分段影片"

                if ($chunksCount -eq 1) {
                    # 只有一個分段，合併原始音訊
                    & $Dep.ffmpeg -v error -framerate $TargetFPS -start_number 0 -i "$imageInputPath" -i "$VideoPath" -vf $vfConfig @outputQualityk -map 0:v:0 -map 1:a:0 -c:a copy $($chunk.OutputFile) -y
                }
                else {
                    # 有多個分段，暫不合併音訊
                    & $Dep.ffmpeg -v error -framerate $TargetFPS -start_number 0 -i "$imageInputPath" -vf $vfConfig @outputQuality -an $($chunk.OutputFile) -y
                }

                WriteProgressLog $step_merge_chunk
            }
            else { Write-Host "合併錯誤: 在 $currentCachePath 中找不到圖片序列" -ForegroundColor Red; continue }
        }
        else { Write-Host "--> 5/5: 合併分段影片 (完成跳過)" -ForegroundColor Gray }

        # 即時清理
        if ($completedSteps.ContainsKey("$chunkId`_合併完成")) {
            Remove-Item $cachePath -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item "$cachePath-fps" -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "段落 [$($chunk.Index + 1)/$($chunksCount)] 完成清理。" -ForegroundColor Green
        }
    }

    # -------- 最終合併 --------
    $step_final_merge = "最終合併完成"
    if (-not $completedSteps.ContainsKey($step_final_merge)) {
        Write-Host "`n===== 所有段落處理完成，開始最終合併 =====>`n"

        # 定義最終輸出路徑
        $merge = $FastOutput ? "fast" : "slow"
        $upscaled_Path = "$outputTemplate-x$UpscaleFactor-$($TargetFPS)Fps-$merge.$OutputFormat"

        # 只有一個分段時，直接移動檔案
        if ($chunksCount -eq 1) {
            $sourceFile = $chunks[0].OutputFile
            if (Test-Path $sourceFile) {
                try {
                    Move-Item -Path $sourceFile -Destination $upscaled_Path -Force
                    Write-Host "影片移動成功: $upscaled_Path" -ForegroundColor Cyan
                    WriteProgressLog $step_final_merge
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
            $concatListFile = Join-Path $workDir "concat_list.txt"

            # 檢查所有預期的分段影片是否都存在
            $allChunksExist = $true
            foreach ($chunk in $chunks) {
                if (-not (Test-Path $chunk.OutputFile)) {
                    Write-Host "最終合併錯誤: 找不到分段影片 $($chunk.OutputFile)" -ForegroundColor Red
                    $allChunksExist = $false
                    break
                }
            }

            if ($allChunksExist) {
                $chunks | ForEach-Object { "file '$($_.OutputFile)'" } | Set-Content $concatListFile

                $vfConfig = "scale=$($scaled):force_original_aspect_ratio=decrease:flags=lanczos,pad=$($scaled):(ow-iw)/2:(oh-ih)/2:black,$vfUnsharp"

                $originalAudio = & $Dep.ffprobe -v error -i "$VideoPath" -select_streams a -show_streams -of json
                $hasOriginalAudio = -not [string]::IsNullOrEmpty($originalAudio)

                $inputFlags = if ($FastOutput) {
                    @("-v", "error", "-hwaccel", "cuda", "-c:v", "hevc_cuvid")
                }
                else {
                    @("-v", "error")
                }

                try {
                    if ($hasOriginalAudio) {
                        & $Dep.ffmpeg @inputFlags -f concat -safe 0 -i $concatListFile -i "$VideoPath" -vf "$vfConfig" @outputQuality -map 0:v:0 -map 1:a:0 -c:a copy "$upscaled_Path" -y
                    }
                    else {
                        & $Dep.ffmpeg @inputFlags -f concat -safe 0 -i $concatListFile -vf "$vfConfig" @outputQuality -an "$upscaled_Path" -y
                    }
                    Write-Host "影片合併成功: $upscaled_Path" -ForegroundColor Cyan
                    WriteProgressLog $step_final_merge
                }
                catch {
                    Write-Host "最終合併失敗: $_" -ForegroundColor Red
                    exit
                }
            }
        }
    }

    # -------- 清理工作目錄 --------
    if ($completedSteps.ContainsKey("最終合併完成")) {
        Write-Host "已清理所有工作檔案。"
        Remove-Item $workDir -Recurse -Force
        Read-Host "Enter 離開..."
    }
}

# --- 使用範例 ---
VideoUpscaler `
    -VideoPath "R:\Test-1.mp4" `
    -TargetFPS 0 `
    -UpscaleFactor 2 `
    -OutputFormat "mp4" `
    -ProcessFormat "png" `
    -CustomResolution "1920x1080" `
    -FastOutput $true `
    -ChunkDuration 15