# ? 搭配本地 ffmpeg, ffprobe, gifski 使用 (PowerShell 7.4+)
# ! 主打高品質 GIF 轉換, 檔案大小會暴漲

function StartConvert {
    $inputPath = $null

    while ($true) {
        $inputPath = Read-Host "[Video -> GIF] VideoPath"
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
    $maxThreads = [Math]::Ceiling([Environment]::ProcessorCount / 4)

    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $maxThreads)
    $runspacePool.ThreadOptions = "ReuseThread"
    $runspacePool.Open()

    # 讀取影片檔案
    $videoFiles = @(Get-ChildItem -LiteralPath $inputPath -Recurse |
        Where-Object { $_.Extension -in '.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv' })

    Write-Host # 與一開始的輸入行空一行
    Write-Host "Found $($videoFiles.Count) video(s) to convert." -ForegroundColor Yellow

    $videoFiles | ForEach-Object {

        $inputFile = $_.FullName
        $outputFile = "$($_.DirectoryName)\$($_.BaseName).gif"

        # 建立一個新的 Runspace
        $runspace = [powershell]::Create()
        $runspace.RunspacePool = $runspacePool

        $runspace.AddScript({
                param($inputFile, $outputFile)

                $ErrorMessage = ""
                $gifskiOutput = ""
                $ErrorOccurred = $false
                $width = 0

                try {
                    # 取得影片原本的寬度，讓 gifski 不再額外縮圖
                    $widthRaw = ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$inputFile" | Select-Object -First 1
                    $widthRaw = if ($null -ne $widthRaw) { $widthRaw.ToString().Trim() } else { "" }

                    if ($widthRaw -notmatch '^\d+$' -or [int]$widthRaw -le 0) {
                        throw "Unable to read video width (ffprobe returned: '$widthRaw')"
                    }
                    $width = [int]$widthRaw

                    $gifskiOutput = ffmpeg -hide_banner -loglevel error -hwaccel cuda -i "$inputFile" -map 0:v:0 -an -pix_fmt yuv444p -f yuv4mpegpipe - |
                    gifski --fps 24 --quality 100 --lossy-quality 100 --width $width --extra -o "$outputFile" - 2>&1

                    # 管線的最後一個指令是 gifski, 所以 $LASTEXITCODE 是 gifski 的結果
                    if ($LASTEXITCODE -ne 0) {
                        $ErrorOccurred = $true
                        $ErrorMessage = $gifskiOutput
                    }
                    elseif (-not(Test-Path -LiteralPath $outputFile -PathType Leaf)) {
                        $ErrorOccurred = $true
                        $ErrorMessage = "Output file was not created: $outputFile"
                    }
                    elseif ((Get-Item -LiteralPath $outputFile).Length -le 0) {
                        $ErrorOccurred = $true
                        $ErrorMessage = "Output file is empty: $outputFile"
                    }
                }
                catch {
                    $ErrorOccurred = $true
                    $ErrorMessage = $_.Exception.Message
                    if ($gifskiOutput) {
                        $ErrorMessage = "$ErrorMessage`n$gifskiOutput"
                    }
                }

                return [PSCustomObject]@{
                    Success    = -not $ErrorOccurred
                    InputFile  = $inputFile
                    OutputFile = $outputFile
                    Error      = $ErrorMessage
                }
            }).AddArgument($inputFile).AddArgument($outputFile) | Out-Null

        Write-Host "[Convert] $inputFile -> $outputFile" -ForegroundColor Cyan

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
                Write-Host "[Done] $($result.OutputFile)" -ForegroundColor Green
            }
            else {
                $errorOccurred = $true
                Write-Error "Error File: $($result.InputFile) | Error Message: $($result.Error)"
            }
        }
        catch {
            $errorOccurred = $true
            Write-Error "Task Failed： $($result.InputFile)"
        }
        finally {
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