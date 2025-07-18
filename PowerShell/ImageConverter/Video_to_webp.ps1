# ? 搭配本地 ffmpeg 使用

function StartConvert {
    $inputPath = $null

    while ($true) {
        $inputPath = Read-Host "[Video -> Webp&gif] VideoPath"
        $inputPath = $inputPath.Trim('"')

        if (-not(Test-Path -LiteralPath $inputPath)) {
            Write-Host "`n[Error] Path does not exist`n" -ForegroundColor Red
        }
        else {
            break
        }
    }

    $jobs = @()
    $maxThreads = [Math]::Ceiling([Environment]::ProcessorCount / 2)

    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $maxThreads)
    $runspacePool.ThreadOptions = "ReuseThread"
    $runspacePool.Open()

    # 讀取影片檔案
    Get-ChildItem -LiteralPath $inputPath -Recurse |
    Where-Object { $_.Extension -in '.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv' } |
    ForEach-Object {

        $inputFile = $_.FullName
        $outputFile = "$($_.DirectoryName)\$($_.BaseName).webp"

        # 開啟新的 runspace
        $runspace = [powershell]::Create()
        $runspace.RunspacePool = $runspacePool

        $runspace.AddScript({
                param($inputFile, $outputFile)

                # -hwaccel cuda: 使用 NVIDIA GPU 硬體加速解碼, 大幅提升速度
                # -an: 完全去除音訊
                # -c:v libwebp_anim: 使用 webp 動畫編碼
                # -loop 0: 無限循環
                # -q:v 95: 圖片品質 (0-100), 越高越好
                # -compression_level 6: 壓縮等級 (0-6), 越高壓縮率越高但越慢
                # -pix_fmt yuva420p: 像素格式, 支援透明度
                # -vf 降噪, 智慧銳化
                # -threads 0: 自動分配核心
                # -map_metadata -1: 移除所有中繼資料
                ffmpeg -hwaccel cuda -i "$inputFile" -an -c:v libwebp_anim -loop 0 -q:v 95 -compression_level 6 -pix_fmt yuva420p -vf "hqdn3d=1.5:1.5:6:6,smartblur=luma_radius=1.0:luma_strength=-0.5" -threads 0 -map_metadata -1 "$outputFile" -y
            }).AddArgument($inputFile).AddArgument($outputFile)

        try {
            [void]($jobs += [PSCustomObject]@{
                    Runspace    = $runspace
                    InputFile   = $inputFile
                    AsyncResult = $runspace.BeginInvoke()
                })
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