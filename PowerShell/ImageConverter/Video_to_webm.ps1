# ? 搭配本地 ffmpeg 使用

function StartConvert {
    $inputPath = $null

    while ($true) {
        $inputPath = Read-Host "[Video -> Webm] VideoPath"
        $inputPath = $inputPath.Trim('"')

        if (-not(Test-Path -LiteralPath $inputPath)) {
            Write-Host "`n[Error] Path does not exist`n" -ForegroundColor Red
        }
        else {
            break
        }
    }

    $jobs = @()
    $maxThreads = [Math]::Ceiling([Environment]::ProcessorCount / 3)

    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $maxThreads)
    $runspacePool.ThreadOptions = "ReuseThread"
    $runspacePool.Open()

    # 讀取影片檔案
    Get-ChildItem -LiteralPath $inputPath -Recurse |
    Where-Object { $_.Extension -in '.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv' } |
    ForEach-Object {

        $inputFile = $_.FullName
        $outputFile = "$($_.DirectoryName)\$($_.BaseName).webm"

        # 開啟新的 runspace
        $runspace = [powershell]::Create()
        $runspace.RunspacePool = $runspacePool

        $runspace.AddScript({
                param($inputFile, $outputFile)

                # 我的顯卡目前不支援 AV1 GPU 進行編碼, 暫時使用 CPU 進行編碼
                # -hwaccel cuda: 使用 NVIDIA GPU 硬體加速解碼, 大幅提升速度
                # -map 0:v -map 0:a?: 映射視訊軌道, 如果音訊軌道存在的話
                # -c:v libaom-av1: 使用 AV1 編碼器 (libaom)
                # -crf 22: 影片品質, 越低越好
                # -cpu-used 4: 編碼速度與品質的平衡點 (0-8, 越高越快)
                # -vf 降噪, 提升對比度與飽和度, 智慧銳化
                ffmpeg -hwaccel cuda -i "$inputFile" -map 0:v -map 0:a? -c:v libaom-av1 -crf 22 -cpu-used 4 -vf "hqdn3d=1.5:1.5:6:6,eq=contrast=1.1:saturation=1.15,smartblur=luma_radius=1.2:luma_strength=-0.7" -c:a libopus -b:a 320k "$outputFile" -y
            }).AddArgument($inputFile).AddArgument($outputFile)

        try {
            $jobs += [PSCustomObject]@{
                Runspace    = $runspace
                InputFile   = $inputFile
                AsyncResult = $runspace.BeginInvoke()
            }
        }
        catch {
            $runspace.Dispose()
        }
    }

    # 等待所有工作完成
    foreach ($job in $jobs) {
        $job.Runspace.EndInvoke($job.AsyncResult)
        $job.Runspace.Dispose()

        try {
            Remove-Item -LiteralPath $job.InputFile -Force
        }
        catch {
            Write-Warning "Remove Failed： $($job.InputFile)"
        }
    }

    $runspacePool.Close()
    $runspacePool.Dispose()

    Clear-Host
    StartConvert
}

StartConvert