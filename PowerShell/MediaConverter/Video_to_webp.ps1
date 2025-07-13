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
                ffmpeg -hwaccel cuda -i "$inputFile" -an -c:v libwebp_anim -loop 0 -q:v 95 -compression_level 6 -preset drawing -vf "deband,nlmeans=s=1.0,unsharp=3:3:0.4:3:3:0,fps=%TARGET_FPS%" -pix_fmt yuva444p -threads 0 -map_metadata -1 "$outputFile" -y
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