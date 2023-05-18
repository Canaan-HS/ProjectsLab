<#
    我到底為什麼要用 PowerShell 這個垃圾東西來寫, 到底為什麼可以這麼搞心態, 當初選錯寫的語言了

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
    | \_| ''\---/'' | |
    \ .-\__ `-` ___/-. /
    ___`. .' /--.--\ `. . __
    ."" '< `.___\_<|>_/___.' >'"".
    | | : `- \`.;`\ _ /`;.`/ - ` : | |
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
$Gen = Generator $Dep.ffmpeg $Dep.ffprobe # 例項化引數生成器 (函式呼叫 -> & $Gen.func Par1 Par2)

# 獲取媒體資訊模塊
Import-Module "$currentRoot/modules/StreamsInfo.psm1"

function VideoUpscaler {
    param (
        [string]$InputMedia,  # 影片路徑
        [int]$TargetFPS = 24, # 目標 FPS (設置低於原始媒體, 並不會下降)
        [int]$UpscaleFactor = 2, # 放大倍率 (設置 1 ~ 4) [1 就什麼都不做]
        [string]$OutputFormat = "mp4", # 最終合併影片格式
        [string]$ProcessFormat = "png", # 處理的緩存圖片格式 (改成 webp 檔案會比較小 無損壓縮, 但會降低處理速度)
        [string]$CustomResolution = $null, # 自定輸出解析度 [用他來下降解析度, 不會壓縮檔案大小, 放大多少倍位元率就是多少]
        [boolean]$UpscaleCompression = $false, # 有損壓縮 AI 增強圖畫質 (啟用後降低處理速度, 並會修改輸出格式為 webp)
        [boolean]$FastOutput = $true # 以較快的速度合併輸出 (慢速模式: 以較高的畫質, 壓縮成較小的檔案 [不一並較小])
    )

    if (-not(Test-Path -LiteralPath $InputMedia)) {
        Write-Host "錯誤的媒體路徑: $InputMedia"
        exit
    }

    # 垃圾的 PowerSell 老是有路徑問題
    $InputMedia = Convert-Path -LiteralPath $InputMedia

    <# -------- 初始化運算配置 -------- #>

    # 低畫質的預處理 (降噪強度, 放大倍率)
    $srmdRules = @{
        144 = @(10, 4)
        240 = @(9, 3)
        360 = @(8, 2)
        480 = @(7, 2)
    }

    # 根據編號選擇模型 (目前不可選, 預設 2)
    $fpsModelRules = @{
        1 = @("rife-models\rife-v4.24_ensembleTrue")
        2 = @("rife-models\rife-v4.26-large_ensembleFalse")
    }

    # 根據增強倍率選擇模型
    $upscaleModelRules = @{
        1 = ""
        2 = @("realesr-animevideov3-x2")
        3 = @("realesr-animevideov3-x3")
        4 = @("realesr-animevideov3-x4")
    }

    # 開始位置
    $startIndex = 1
    # 輸出路徑模板
    $outputTemplate = "$(Split-Path $InputMedia)\$([System.IO.Path]::GetFileNameWithoutExtension($InputMedia))"

    <# -------- 獲取媒體資訊 -------- #>

    ($width, $height, $fps, $bitrate, $frames, $fillerFrame) = GetStreamsInfo $InputMedia $TargetFPS $UpscaleFactor

    # 嘗試解析自定義解析度 (縮小解析, 倍率乘數, 目標解析度)
    ($reduce, $factor, $Scale) = & $Gen.GetCustomScale $width $height $CustomResolution

    # 計算縮放後的大小
    $scaled = $Scale ? $Scale : (& $Gen.GetScaled $width $height $UpscaleFactor)

    # 如果有解析出自定義解析度, 且縮放倍率 不同 則優先使用自定縮放倍率
    if ($factor -and $UpscaleFactor -ne $factor) {
        $UpscaleFactor = $factor
        # 修改倍率後重新獲取影片資訊
        ($width, $height, $fps, $bitrate, $frames, $fillerFrame) = GetStreamsInfo $InputMedia $TargetFPS $UpscaleFactor
    }

    # 快取圖片填充量
    $imgFormat = ([string]$fillerFrame).Length

    <# -------- 解析配置 -------- #>

    # 限制倍率在 1 ~ 4
    $UpscaleFactor = [Math]::Max(1, [Math]::Min($UpscaleFactor, 4))

    # 取得快取目錄
    $cachePath = & $Gen.GetCachePath $outputTemplate $UpscaleFactor

    # 取得標準化解析度, 並獲取預處理配置
    $srmdProcess = $srmdRules[$(& $Gen.GetResolution $height)]

    # 取得可使用的模型
    $fpsModels = $fpsModelRules[2] | Where-Object { $Dep.rifeModelList[$_] }
    $upscaleModels = $upscaleModelRules[$UpscaleFactor] | Where-Object { $Dep.realesrganModelList[$_] }

    @{
        "Meta" = @{
            "媒體資訊" = @{
                "寬度" = $width
                "高度" = $height
                "FPS" = $fps
                "總幀數" = $frames
            }
            "輸出配置" = @{
                "媒體路徑" = $InputMedia
                "放大倍率" = $UpscaleFactor
                "輸出畫質" = $scaled
                "輸出比特" = "$($bitrate)M"
                "輸出總幀數" = $fillerFrame
                "輸出格式" = $OutputFormat
                "快速合併" = $FastOutput
                "快取目錄" = $cachePath
                "快取格式" = $ProcessFormat
                "圖片填充" = $imgFormat
            }
            "模型資訊" = @{
                "Fps" = $fpsModels
                "Upscale" = $upscaleModels
            }
        }
    } | ConvertTo-Json -Depth 3 | Write-Host

    <# -------- 增強處理工作 -------- #>

    # TODO - 避免處理錯誤, 需要加強檢查邏輯
    if (Test-Path $cachePath) {
        $Count = (Get-ChildItem -LiteralPath $cachePath -File).Count
        if ($Count -gt 0) {
            $startIndex = $Count + 1
        }
    } else {
        New-Item -ItemType Directory -Path $cachePath | Out-Null
    }

    # TODO - 預計後續修改為分段合併, 目前為一次合併, 非常耗空間
    $endIndex = $TargetFPS -gt $fps ? $fillerFrame : $frames
    if ($startIndex -lt $endIndex) {
        # 處理線程 (load/proc/save) [設置太高, 對於放大 4 倍, 容易記憶體不夠]
        $thread = "6:6:6"
        # 銳化參數
        $sharpness = "5:5:0.5:5:5:0.5"

        # 用於儲存所有的 Runspace 工作
        $jobs = @()
        # 最大允許同時執行的執行緒數
        $maxThreads = [Environment]::ProcessorCount - 1

        Write-Host "`n===== 幀數提取 =====>`n"
        if ($processFormat -eq "webp") {
            & $Dep.ffmpeg -v quiet -hwaccel cuda -i "$InputMedia" -an -vsync vfr -vf "fps=$fps,scale=iw:ih:flags=lanczos,unsharp=$sharpness" -c:v libwebp -lossless 1 -threads 0 -cpu-used 6 "$cachePath\%0$($imgFormat)d.$processFormat" -y
        } else {
            & $Dep.ffmpeg -v quiet -hwaccel cuda -i "$InputMedia" -an -vsync vfr -vf "fps=$fps,scale=iw:ih:flags=lanczos,unsharp=$sharpness" -q:v 1 -threads 0 -cpu-used 6 "$cachePath\%0$($imgFormat)d.$processFormat" -y
        }

        if ($srmdProcess) {
            Write-Host "`n===== 預處理 =====>`n"
            & $Dep.srmd -i "$cachePath" -o "$cachePath" -n "$($srmdProcess[0])" -s "$($srmdProcess[1])" -j "$thread"
        }

        # 目標 FPS > 原始 FPS, 先增加 FPS -> 在增強解析度, 反過來太吃 VRAM
        if ($TargetFPS -gt $fps) {
            Write-Host "`n===== 幀數提升 =====>`n"

            # 修改輸出的 $fps
            $fps = $TargetFPS
            $frames = $fillerFrame

            # 生成補幀用路徑
            $fpsPath ="$cachePath-$($TargetFPS)fps"
            New-Item -ItemType Directory -Path $fpsPath | Out-Null

            # 補幀數
            & $Dep.rife -i "$cachePath" -o "$fpsPath" -n "$fillerFrame" -m "$fpsModels" -j "$thread" -q 100 -f "%0$($imgFormat)d.$processFormat"

            # 完成後刪除原本緩存
            Remove-Item $cachePath -Recurse -Force
            # 修改名稱
            Rename-Item $fpsPath $cachePath
        }

        if ($upscaleModels) {
            Write-Host "`n===== 畫質提升 =====>`n"

            if (-not $UpscaleCompression) { # 不壓縮直接進行縮放
                & $Dep.realesr -i "$cachePath" -o "$cachePath" -s "$UpscaleFactor" -m "$($Dep.realesrganModelFolder)" -n "$upscaleModels" -t 0 -j "$thread"
            } else {
                $ProcessFormat = "webp"

                # 建立並開啟 Runspace Pool
                $runspacePool = [runspacefactory]::CreateRunspacePool(1, $maxThreads)
                $runspacePool.ThreadOptions = "ReuseThread"  # 避免不必要的執行緒建立
                $runspacePool.Open()

                (Get-ChildItem -LiteralPath $cachePath) | ForEach-Object {

                    # 建立新的 Powershell 物件並指定 runspace pool
                    $ps = [powershell]::Create()
                    $ps.RunspacePool = $runspacePool

                    $ps.AddScript({
                        param(
                            $Dep,
                            $scaled,
                            $thread,
                            $imgName,
                            $sharpness,
                            $UpscaleFactor,
                            $upscaleModels
                        )
    
                        $pngPath = $imgName
                        $webpPath = ($imgName -replace ".png", ".webp") # 壓縮輸出為 webp
                        & $Dep.realesr -i "$pngPath" -o "$webpPath" -s "$UpscaleFactor" -m "$($Dep.realesrganModelFolder)" -n "$upscaleModels" -t 512 -j "$thread"
                        Remove-Item $pngPath -Force # 刪除原始 png
    
                        $tempPath = ($webpPath -replace ".webp", "_temp.webp")
                        & $Dep.ffmpeg -hwaccel cuda -i "$webpPath" -an -vf "scale=$($scaled):force_original_aspect_ratio=decrease:flags=lanczos,pad=$($scaled):(ow-iw)/2:(oh-ih)/2:black,unsharp=$sharpness" -q:v 100 -threads 0 -cpu-used 6 "$tempPath" -y
                        Remove-Item $webpPath -Force # 刪除原始 webp, 替代為壓縮圖片
                        Rename-Item $tempPath $webpPath
                    })

                    # 傳入參數
                    $ps.AddArgument($Dep)
                    $ps.AddArgument($scaled)
                    $ps.AddArgument($thread)
                    $ps.AddArgument($_.FullName)
                    $ps.AddArgument($sharpness)
                    $ps.AddArgument($UpscaleFactor)
                    $ps.AddArgument($upscaleModels)

                    try {
                        # 儲存工作資訊，稍後等待所有工作完成
                        $jobs += [PSCustomObject]@{
                            PowerShell  = $ps
                            AsyncResult = $ps.BeginInvoke()
                        }
                    } catch {
                        $ps.Dispose()  # 釋放 PowerShell 物件，避免資源洩漏
                    }
                }

                # 等待所有 runspace 工作完成
                foreach ($job in $jobs) {
                    try {
                        if ($job.PowerShell -and $job.AsyncResult) { # 確保執行完成
                            $null = $job.PowerShell.EndInvoke($job.AsyncResult)
                        }
                    } catch {} finally {
                        if ($job.PowerShell) { # 確保 PowerShell 物件被正確釋放
                            $job.PowerShell.Dispose()
                        }
                    }
                }

                # 清理 runspace pool
                $runspacePool.Close()
                $runspacePool.Dispose()
            }
        }

    } elseif ($TargetFPS -gt $fps) { # 已經完成 在合併前最後的檢查
        $fps = $TargetFPS
        $frames = $fillerFrame
    }

    <# -------- 進行合併處理 -------- #>

    # 檢查是否已經完成
    if ((Get-ChildItem -Path $cachePath -File).Count -le ($frames + 1)) { # 這個 + 1 是誤差值, 待測試
        Write-Host "`n===== 媒體輸出 =====>`n"

        # 判斷合併模式
        $merge = $FastOutput ? "fast" : "slow"

        # 設定輸出路徑
        $upscaled_Path = "$outputTemplate-x$UpscaleFactor-$($fps)Fps-$merge.$OutputFormat"

        # 設定輸出濾鏡
        $vfConfig = "scale=$($scaled):force_original_aspect_ratio=decrease:flags=lanczos,pad=$($scaled):(ow-iw)/2:(oh-ih)/2:black,unsharp=5:5:0.5:5:5:0.5"

        # TODO - 預計添加完成後二次壓縮, 或是自適應比特率的選項, 目前是使用固定計算 $bitrate, 但對於自定 CustomResolution 某些情況下, 無法自行調整
        # 使用圖片合併成影片，音軌來自原始影片
        try {
            if ($merge -eq "slow") {
                & $Dep.ffmpeg -framerate $fps -i "$cachePath\%0$($imgFormat)d.$processFormat" -i "$InputMedia" -c:v libx265 -b:v "$($bitrate)M" -vf "$vfConfig" -preset slow -tune animation -threads 0 -cpu-used 6 -c:a copy -shortest "$upscaled_Path" -y
            } else {
                & $Dep.ffmpeg -hwaccel cuda -framerate $fps -i "$cachePath\%0$($imgFormat)d.$processFormat" -i "$InputMedia" -c:v hevc_nvenc -profile main10 -rc vbr -b:v "$($bitrate)M" -vf "$vfConfig" -preset p7 -rc-lookahead 32 -spatial-aq 1 -aq-strength 10 -temporal-aq 1 -threads 0 -cpu-used 6 -c:a copy -shortest "$upscaled_Path" -y
            }

            Remove-Item $cachePath -Recurse -Force
        } catch {
            Write-Host $_
        }
    }
}

# 使用 (目前不支援中途暫停, 停止後建議刪除文件重新執行)
VideoUpscaler `
    -InputMedia "R:\Test-1.mp4" `
    -TargetFPS 0 `
    -UpscaleFactor 2 `
    -ProcessFormat "png" `
    -OutputFormat "mp4" `
    -CustomResolution "" `
    -UpscaleCompression $false `
    -FastOutput $true