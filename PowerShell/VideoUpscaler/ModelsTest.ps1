$currentRoot = $PSScriptRoot
$cachePath = "R:\UpscalerCache"
$testVideo = Join-Path $currentRoot "test/Test-2.mp4"

$ffmpge = Join-Path $currentRoot "tools/ffmpeg.exe"

if (-not(Test-Path $testVideo)) {
    Write-Error "未找到測試媒體"
    exit
}

Import-Module "$currentRoot/modules/StreamsInfo.psm1"


if (-not(Test-Path $cachePath)) {
    New-Item -ItemType Directory -Path $cachePath | Out-Null

    Write-Host "===== 幀提取 ====="
    $extractPath = Join-Path $cachePath "frame_%06d.png"
    $ffmpegParams = @(
        '-v', 'error',
        '-hwaccel', 'cuda',
        '-hwaccel_output_format', 'cuda',
        '-i', $testVideo,
        '-vf', 'hwdownload,format=nv12',
        '-an',
        $extractPath,
        '-y'
    )

    & $ffmpge $ffmpegParams
}

function TestSrmd {
    param (
        [string]$inputPath,
        [string]$outputPath,
        [int]$scale = 2
    )

    $srmd = Join-Path $currentRoot "srmd-ncnn-vulkan.exe"
    $srmdModels = Join-Path $currentRoot "models-srmd"

    if (-not(Test-Path $srmd) -or -not(Test-Path $srmdModels)) {
        Write-Error "Srmd 測試錯誤: 依賴缺失"
        return
    }

    if (-not(Test-Path $outputPath)) {
        New-Item -ItemType Directory -Path $outputPath | Out-Null
    }

    <#
     *   -h                   show this help
     *   -v                   verbose output
     *   -i input-path        input image path (jpg/png/webp) or directory
     *   -o output-path       output image path (jpg/png/webp) or directory
     *   -n noise-level       denoise level (-1/0/1/2/3/4/5/6/7/8/9/10, default=3)
     *   -s scale             upscale ratio (2/3/4, default=2)
     *   -t tile-size         tile size (>=32/0=auto, default=0) can be 0,0,0 for multi-gpu
     *   -m model-path        srmd model path (default=models-srmd)
     *   -g gpu-id            gpu device to use (default=auto) can be 0,1,2 for multi-gpu
     *   -j load:proc:save    thread count for load/proc/save (default=1:2:2) can be 1:2,2,2:2 for multi-gpu
     *   -x                   enable tta mode
     *   -f format            output image format (jpg/png/webp, default=ext/png)
    #>

    Write-Host "===== Srmd 預處理測試 ====="

    & $srmd -i $inputPath -o $outputPath -n 8 -s $scale -j "8:8:8"
}

function TestRife {
    param (
        [string]$inputPath,
        [string]$outputPath,
        [int]$modelIndex,
        [int]$targetFPS = 30
    )

    $rife = Join-Path $currentRoot "rife-ncnn-vulkan.exe"

    $rifeModels = @{
        1 = [PSCustomObject]@{
            "path" = Join-Path $currentRoot "rife-models/rife-anime"
            "useN" = $false
        }
        2 = [PSCustomObject]@{
            "path" = Join-Path $currentRoot "rife-models/rife-v4.26"
            "useN" = $true
        }
    }

    $selectModel = $rifeModels[$modelIndex]
    if (-not(Test-Path $rife) -or -not(Test-Path $selectModel.path)) {
        Write-Error "Rife 測試錯誤: 依賴缺失"
        return
    }

    if (-not(Test-Path $outputPath)) {
        New-Item -ItemType Directory -Path $outputPath | Out-Null
    }

    <#
     *   -h                   show this help
     *   -v                   verbose output
     *   -0 input0-path       input image0 path (jpg/png/webp)
     *   -1 input1-path       input image1 path (jpg/png/webp)
     *   -i input-path        input image directory (jpg/png/webp)
     *   -o output-path       output image path (jpg/png/webp) or directory
     *   -n num-frame         target frame count (default=N*2)
     *   -s time-step         time step (0~1, default=0.5)
     *   -m model-path        rife model path (default=rife-v2.3)
     *   -g gpu-id            gpu device to use (-1=cpu, default=auto) can be 0,1,2 for multi-gpu
     *   -j load:proc:save    thread count for load/proc/save (default=1:2:2) can be 1:2,2,2:2 for multi-gpu
     *   -x                   enable spatial tta mode
     *   -z                   enable temporal tta mode
     *   -u                   enable UHD mode
     *   -f pattern-format    output image filename pattern format (%08d.jpg/png/webp, default=ext/%08d.png)
     *   -q                   webp image quality (0-100)
     *   -l                   list out available gpu devices
    #>

    Write-Host "===== Rife 補幀測試 ====="

    $rifeParams = @(
        "-i", $inputPath,
        "-o", $outputPath,
        "-m", $selectModel.path,
        "-j", "8:8:8",
        "-q", 100,
        "-u"
    )

    if ($selectModel.useN) {
        ($width, $height, $fps, $totalDuration, $totalFrames, $finalFrames) = GetStreamsInfo $testVideo $targetFPS
        $rifeParams += @("-n", $finalFrames)
    }

    & $rife $rifeParams
}

function TestIfrnet {
    param (
        [string]$inputPath,
        [string]$outputPath,
        [int]$modelIndex,
        [int]$targetFPS = 30
    )

    $ifrnet = Join-Path $currentRoot "ifrnet-ncnn-vulkan.exe"

    $ifrnetModels = @{
        1 = [PSCustomObject]@{
            "path" = Join-Path $currentRoot "ifrnet-models/IFRNet_Vimeo90K"
            "useN" = $false
        }
        2 = [PSCustomObject]@{
            "path" = Join-Path $currentRoot "ifrnet-models/IFRNet_L_GoPro"
            "useN" = $true
        }
        3 = [PSCustomObject]@{
            "path" = Join-Path $currentRoot "ifrnet-models/IFRNet_L_Vimeo90K"
            "useN" = $false
        }
    }

    $selectModel = $ifrnetModels[$modelIndex]

    if (-not(Test-Path $ifrnet) -or -not(Test-Path $selectModel.path)) {
        Write-Error "Ifrnet 測試錯誤: 依賴缺失"
        return
    }

    if (-not(Test-Path $outputPath)) {
        New-Item -ItemType Directory -Path $outputPath | Out-Null
    }

    <#
     *  -h                   show this help
     *  -v                   verbose output
     *  -0 input0-path       input image0 path (jpg/png/webp)
     *  -1 input1-path       input image1 path (jpg/png/webp)
     *  -i input-path        input image directory (jpg/png/webp)
     *  -o output-path       output image path (jpg/png/webp) or directory
     *  -n num-frame         target frame count (default=N*2)
     *  -s time-step         time step (0~1, default=0.5)
     *  -m model-path        ifrnet model path (default=IFRNet_Vimeo90K)
     *  -g gpu-id            gpu device to use (-1=cpu, default=auto) can be 0,1,2 for multi-gpu
     *  -j load:proc:save    thread count for load/proc/save (default=1:2:2) can be 1:2,2,2:2 for multi-gpu
     *  -x                   enable tta mode
     *  -u                   enable UHD mode
     *  -f pattern-format    output image filename pattern format (%08d.jpg/png/webp, default=ext/%08d.png)
    #>

    Write-Host "===== Ifrnet 補幀測試 ====="

    $ifrnetParams = @(
        "-i", $inputPath,
        "-o", $outputPath,
        "-m", $selectModel.path,
        "-j", "8:8:8",
        "-u"
    )

    if ($selectModel.useN) {
        ($width, $height, $fps, $totalDuration, $totalFrames, $finalFrames) = GetStreamsInfo $testVideo $targetFPS
        $ifrnetParams += @("-n", $finalFrames)
    }

    & $ifrnet $ifrnetParams
}

function TestRealcugan {
    param (
        [string]$inputPath,
        [string]$outputPath,
        [int]$scale = 2
    )

    $realcugan = Join-Path $currentRoot "realcugan-ncnn-vulkan.exe"
    $realcuganModels = Join-Path $currentRoot "realcugan-models-pro"

    if (-not(Test-Path $realcugan) -or -not(Test-Path $realcuganModels)) {
        Write-Error "Realcugan 測試錯誤: 依賴缺失"
        return
    }

    if (-not(Test-Path $outputPath)) {
        New-Item -ItemType Directory -Path $outputPath | Out-Null
    }

    <#
     *   -h                   show this help
     *   -v                   verbose output
     *   -i input-path        input image path (jpg/png/webp) or directory
     *   -o output-path       output image path (jpg/png/webp) or directory
     *   -n noise-level       denoise level (-1/0/1/2/3, default=-1)
     *   -s scale             upscale ratio (1/2/3/4, default=2)
     *   -t tile-size         tile size (>=32/0=auto, default=0) can be 0,0,0 for multi-gpu
     *   -c syncgap-mode      sync gap mode (0/1/2/3, default=3)
     *   -m model-path        realcugan model path (default=models-se)
     *   -g gpu-id            gpu device to use (-1=cpu, default=auto) can be 0,1,2 for multi-gpu
     *   -j load:proc:save    thread count for load/proc/save (default=1:2:2) can be 1:2,2,2:2 for multi-gpu
     *   -x                   enable tta mode
     *   -f format            output image format (jpg/png/webp, default=ext/png)
    #>

    Write-Host "===== Realcugan 超分測試 ====="

    & $realcugan -i $inputPath -o $outputPath -n 2 -s $scale -m $realcuganModels -j "8:8:8"
}

function TestRealesrgan {
    param (
        [string]$inputPath,
        [string]$outputPath,
        [int]$modelIndex = 1,
        [int]$scale = 2
    )

    $realesrgan = Join-Path $currentRoot "realesrgan-ncnn-vulkan.exe"
    $realesrganModels = Join-Path $currentRoot "realesrgan-models"

    $modelName = @{
        1 = "realesr-animevideov3-x2"
        2 = "realesr-animevideov3-x3"
        3 = "realesr-animevideov3-x4"
    }
    if (-not(Test-Path $realesrgan) -or -not(Test-Path $realesrganModels)) {
        Write-Error "Realesrgan 測試錯誤: 依賴缺失"
        return
    }

    if (-not(Test-Path $outputPath)) {
        New-Item -ItemType Directory -Path $outputPath | Out-Null
    }

    <#
     *   -h                   show this help
     *   -i input-path        input image path (jpg/png/webp) or directory
     *   -o output-path       output image path (jpg/png/webp) or directory
     *   -s scale             upscale ratio (can be 2, 3, 4. default=4)
     *   -t tile-size         tile size (>=32/0=auto, default=0) can be 0,0,0 for multi-gpu
     *   -m model-path        folder path to the pre-trained models. default=models
     *   -n model-name        model name (default=realesr-animevideov3, can be realesr-animevideov3 | realesrgan-x4plus | realesrgan-x4plus-anime | realesrnet-x4plus)
     *   -g gpu-id            gpu device to use (default=auto) can be 0,1,2 for multi-gpu
     *   -j load:proc:save    thread count for load/proc/save (default=1:2:2) can be 1:2,2,2:2 for multi-gpu
     *   -x                   enable tta mode
     *   -f format            output image format (jpg/png/webp, default=ext/png)
     *   -v                   verbose output
    #>

    Write-Host "===== Realesrgan 超分測試 ====="

    & $realesrgan -i $inputPath -o $outputPath -s $scale -m $realesrganModels -n $modelName[$modelIndex] -j "6:6:6"
}

# ===== 流程測試 =====
# TestSrmd $cachePath "R:\TestSrmd"
# TestRife $cachePath "R:\TestRife" 1
# TestIfrnet $cachePath "R:\TestIfrnet" 1
# TestRealcugan $cachePath "R:\TestRealcugan"
# TestRealesrgan $cachePath "R:\TestRealesrgan"