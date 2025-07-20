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
    $errorOccurred = $false
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

        # 建立一個新的 Runspace
        $runspace = [powershell]::Create()
        $runspace.RunspacePool = $runspacePool

        $runspace.AddScript({
                param($inputFile, $outputFile, $isGif)

                $ErrorMessage = ""
                $ffmpegOutput = ""
                $ErrorOccurred = $false

                if ($isGif) {
                    $ffmpegOutput = ffmpeg -i "$inputFile" -loop 0 -c:v libwebp_anim -q:v 90 -compression_level 6 -preset drawing -threads 0 -vf "deband,nlmeans=s=1.0,unsharp=3:3:0.4:3:3:0" -pix_fmt yuva444p -an -map_metadata -1 "$outputFile" -y 2>&1
                }
                else {
                    $ffmpegOutput = ffmpeg -v error -i "$inputFile" -c:v libwebp -q:v 90 -compression_level 6 -preset drawing -threads 0 -vf "deband,unsharp=3:3:0.4:3:3:0" -pix_fmt yuva444p -an -map_metadata -1 "$outputFile" -y 2>&1
                }

                if ($LASTEXITCODE -ne 0) {
                    $ErrorOccurred = $true
                    $ErrorMessage = $ffmpegOutput
                }

                return [PSCustomObject]@{
                    Success     = -not $ErrorOccurred
                    InputFile   = $inputFile
                    OutputFile  = $outputFile
                    Error       = $ErrorMessage
                }
            }).AddArgument($inputFile).AddArgument($outputFile).AddArgument($isGif)

        try {
            $jobs += [PSCustomObject]@{
                Runspace    = $runspace
                AsyncResult = $runspace.BeginInvoke()
            }
        }
        catch {
            $runspace.Dispose()
        }
    }

    # 等待所有工作完成
    foreach ($job in $jobs) {
        $result = $job.Runspace.EndInvoke($job.AsyncResult)

        try {
            if ($result.Success) {
                try {
                    if (-not $result.InputFile.EndsWith('.webp', [System.StringComparison]::OrdinalIgnoreCase)) {
                        Remove-Item -LiteralPath $result.InputFile -Force -ErrorAction Stop
                    }
                }
                catch {
                    $errorOccurred = $true
                    Write-Warning "$($result.InputFile) Delete Failed: $_"
                }
            }else {
                $errorOccurred = $true
                Write-Error "Error File: $($result.InputFile)`nError Message: $($result.Error)"
            }
        }
        catch {
            $errorOccurred = $true
            Write-Error "Task Failed： $($result.InputFile)"
        } finally {
            $job.Runspace.Dispose()
        }
    }

    $runspacePool.Close()
    $runspacePool.Dispose()

    if (-not $errorOccurred) {
        Clear-Host
    }

    StartConvert
}

StartConvert