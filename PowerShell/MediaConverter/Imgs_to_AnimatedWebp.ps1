# ? 搭配本地 ffmpeg, ffprobe 使用

function StartConvert {
    $inputDirectory = $null

    while ($true) {
        $inputDirectory = Read-Host "[Sequence -> Animated Webp] DirectoryPath"
        $inputDirectory = $inputDirectory.Trim('"')

        if (-not(Test-Path -LiteralPath $inputDirectory -PathType Container)) {
            Write-Host "`n[Error] Path does not exist`n" -ForegroundColor Red
        }
        else {
            break
        }
    }

    # 收集所有有效圖片，並過濾掉已存在的動畫
    $validExtensions = @('.png', '.jpg', '.jpeg', '.bmp', '.tiff', '.webp')
    $allImageFiles = Get-ChildItem -Path $inputDirectory -Recurse | Where-Object { $_.Extension -in $validExtensions } | ForEach-Object {
        if ($_.Extension -eq '.webp') {
            try {
                $streamCount = (ffprobe -v quiet -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 $_.FullName | Measure-Object).Count
                if ($streamCount -ge 1) {
                    return $null # 如果是動畫 WebP，則過濾掉
                }
            }
            catch {}
        } $_
    } | Where-Object { $_ -ne $null }

    # 使用正則表達式分組
    $groupedFiles = @{}
    $regex = "^(.*?_?)(\d+)$"
    foreach ($file in $allImageFiles) {
        if ($file.BaseName -match $regex) {
            $baseName = $matches[1]
            $numberStr = $matches[2]
            $number = [int]$numberStr
            $groupKey = Join-Path -Path $file.DirectoryName -ChildPath $baseName

            if (-not $groupedFiles.ContainsKey($groupKey)) {
                $groupedFiles[$groupKey] = [PSCustomObject]@{
                    Files     = [System.Collections.ArrayList]@()
                    Padding   = $numberStr.Length
                    Extension = $file.Extension
                }
            }

            $groupedFiles[$groupKey].Files.Add([PSCustomObject]@{ Path = $file.FullName; Number = $number }) | Out-Null
        }
    }

    $jobs = @()
    $maxThreads = [Environment]::ProcessorCount - 1

    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $maxThreads)
    $runspacePool.ThreadOptions = "ReuseThread"
    $runspacePool.Open()

    # 篩選出圖片數量大於1的群組進行處理
    $groupedFiles.GetEnumerator() | Where-Object { $_.Value.Files.Count -gt 1 } | ForEach-Object {

        $group = $_
        $outputFile = "$($group.Name.TrimEnd('_')).webp"
        $inputPattern = "$($group.Name)%0$($group.Value.Padding)d$($group.Value.Extension)"

        $runspace = [powershell]::Create()
        $runspace.RunspacePool = $runspacePool

        $runspace.AddScript({
                param($inputFils, $inputPattern, $outputFile)

                $ErrorMessage = ""
                $ffmpegOutput = ""
                $ErrorOccurred = $false

                $ffmpegOutput = ffmpeg -v error -framerate 10 -i "$inputPattern" -vf "format=yuva420p,deband,unsharp=3:3:0.4:3:3:0" -c:v libwebp_anim -q:v 90 -compression_level 6 -loop 0 -preset drawing -an -map_metadata -1 "$outputFile" -y 2>&1

                if ($LASTEXITCODE -ne 0) {
                    $ErrorOccurred = $true
                    $ErrorMessage = $ffmpegOutput
                }

                return [PSCustomObject]@{
                    Success      = -not $ErrorOccurred
                    InputFiles = $inputFils
                    OutputFile   = $outputFile
                    Error        = $ErrorMessage
                }
            }).AddArgument($group.Value.Files.Path).AddArgument($inputPattern).AddArgument($outputFile)
    
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
                foreach ($file in $result.InputFiles) {
                    try {
                        Remove-Item -LiteralPath $file -Force -ErrorAction Stop
                    }
                    catch {
                        $errorOccurred = $true
                        Write-Warning "$file Delete Failed: $_"
                    }
                }
            }
            else {
                $errorOccurred = $true
                Write-Error "Error File: $($result.OutputFile) | Error Message: $($result.Error)"
            }
        }
        catch {
            $errorOccurred = $true
            Write-Error "Task Failed: $($result.OutputFile)"
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

# 執行主函數
StartConvert