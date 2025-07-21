# ? 搭配本地 ffmpeg full 版本使用

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
    $errorOccurred = $false
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

        # 建立一個新的 Runspace
        $runspace = [powershell]::Create()
        $runspace.RunspacePool = $runspacePool

        $runspace.AddScript({
                param($inputFile, $outputFile)

                $ErrorMessage = ""
                $ffmpegOutput = ""
                $ErrorOccurred = $false

                $ffmpegOutput = ffmpeg -hwaccel cuda -i "$inputFile" -map 0:v -map 0:a? -c:v libsvtav1 -crf 23 -preset 7 -svtav1-params "tune=0" -vf "deband,unsharp=5:5:0.7:5:5:0,eq=contrast=1.05:saturation=1.1" -c:a libopus -b:a 320k "$outputFile" -y 2>&1

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
            }).AddArgument($inputFile).AddArgument($outputFile)

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
                    if (-not $result.InputFile.EndsWith('.webm', [System.StringComparison]::OrdinalIgnoreCase)) {
                        Remove-Item -LiteralPath $result.InputFile -Force -ErrorAction Stop
                    }
                }
                catch {
                    $errorOccurred = $true
                    Write-Warning "$($result.InputFile) Delete Failed: $_"
                }
            }else {
                $errorOccurred = $true
                Write-Error "Error File: $($result.InputFile) | Error Message: $($result.Error)"
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