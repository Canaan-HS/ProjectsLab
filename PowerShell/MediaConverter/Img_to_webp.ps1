# ? 搭配本地 ffmpeg 使用

function StartConvert {
    $inputPath = $null

    while ($true) {
        $inputPath = Read-Host "[Img -> Webp] ImgPath"
        $inputPath = $inputPath.Trim('"')

        if (-not(Test-Path -LiteralPath $inputPath)) {
            Write-Host "`n[Error] Path does not exist`n" -ForegroundColor Red
        }
        else {
            break
        }
    }

    $jobs = @()
    $maxThreads = [Environment]::ProcessorCount - 1

    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $maxThreads)
    $runspacePool.ThreadOptions = "ReuseThread"
    $runspacePool.Open()

    # 讀取圖片檔案
    Get-ChildItem -LiteralPath $inputPath -Recurse |
    Where-Object { $_.Extension -in '.jpg', '.png', '.gif', '.jpeg' } |
    ForEach-Object {

        $inputFile = $_.FullName
        $outputFile = "$($_.DirectoryName)\$($_.BaseName).webp"
        $isGif = $_.Extension -ieq ".gif"

        # 開啟新的 runspace
        $runspace = [powershell]::Create()
        $runspace.RunspacePool = $runspacePool

        $runspace.AddScript({
                param($inputFile, $outputFile, $isGif)

                if ($isGif) {
                    ffmpeg -i "$inputFile" -loop 0 -c:v libwebp_anim -q:v 90 -compression_level 6 -preset drawing -threads 0 -vf "deband,unsharp=3:3:0.4:3:3:0" -pix_fmt yuva444p -an -map_metadata -1 "$outputFile" -y
                }
                else {
                    ffmpeg -i "$inputFile" -c:v libwebp -q:v 90 -compression_level 6 -preset drawing -threads 0 -vf "deband,unsharp=3:3:0.4:3:3:0" -pix_fmt yuva444p -an -map_metadata -1 "$outputFile" -y
                }
            }).AddArgument($inputFile).AddArgument($outputFile).AddArgument($isGif)

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

        # 如果有載入 webp 格式圖片, 那麼就不能刪除, 這會導致全部為空
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