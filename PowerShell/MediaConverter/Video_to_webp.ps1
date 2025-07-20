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
    $errorOccurred = $false
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

        # 建立一個新的 Runspace
        $runspace = [powershell]::Create()
        $runspace.RunspacePool = $runspacePool

        $runspace.AddScript({
                param($inputFile, $outputFile)

                $ErrorMessage = ""
                $ffmpegOutput = ""
                $ErrorOccurred = $false

                $ffmpegOutput = ffmpeg -hwaccel cuda -i "$inputFile" -an -c:v libwebp_anim -loop 0 -q:v 95 -compression_level 6 -preset drawing -vf "deband,nlmeans=s=1.0,unsharp=3:3:0.4:3:3:0" -pix_fmt yuva444p -threads 0 -map_metadata -1 "$outputFile" -y 2>&1

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
                    Remove-Item -LiteralPath $result.InputFile -Force -ErrorAction Stop
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