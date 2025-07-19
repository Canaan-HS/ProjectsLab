# ? 搭配本地 ffmpeg, ffprobe 使用
# ? 有一個 $framerate 函數會動態計算 framerate(Fps), 但這個函數的計算可能會大幅度影響轉換速度, 如果不需要可以直接給他一個預設值

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
    $allImageFiles = Get-ChildItem -LiteralPath $inputDirectory -Recurse | Where-Object { $_.Extension -in $validExtensions } | ForEach-Object {
        if ($_.Extension -eq '.webp') {
            try {
                $streamCount = (ffprobe -v quiet -select_streams v:0 -show_entries frame=media_type -of csv=p=0 $_.FullName | Measure-Object).Count
                if ($streamCount -gt 1) {
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
                    Files       = [System.Collections.ArrayList]@()
                    Padding     = $numberStr.Length
                    Extension   = $file.Extension
                    StartNumber = $number
                }
            }
            else {
                if ($number -lt $groupedFiles[$groupKey].StartNumber) {
                    $groupedFiles[$groupKey].StartNumber = $number
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
        $uid = [guid]::NewGuid().ToString("N")
        $inputFils = $group.Value.Files.Path | Sort-Object Number

        $dir = Split-Path $group.Name
        # $baseName = Split-Path $group.Name -Leaf
        $padding = $group.Value.Padding
        $suffix = $group.Value.Extension

        $startNumber = $group.Value.StartNumber
        $outputFile = "$($group.Name.TrimEnd('_')).webp"
        $inputPattern = "$($dir)\$($uid)_%0$($padding)d$($suffix)"

        # 重新命名檔案, 處理可能斷掉的連號
        $newFils = @()
        $index = $startNumber
        foreach ($file in $inputFils) {
            $fileName = "{0}_{1}{2}" -f $uid, $index.ToString("D$padding"), $suffix
            $newName = Join-Path $dir $fileName

            if ($file -ne $newName) {
                try {
                    Rename-Item -LiteralPath $file $newName
                }
                catch {
                    Rename-Item $file $newName
                }
            }

            $index++
            $newFils += $newName
        }

        $runspace = [powershell]::Create()
        $runspace.RunspacePool = $runspacePool

        $runspace.AddScript({
                param($inputFils, $newFils, $startNumber, $inputPattern, $outputFile)

                function GetDynamicFramerate {
                    param(
                        [string[]]$ImagePaths,
                        [int]$MinFramerate = 7,
                        [int]$MaxFramerate = 14
                    )

                    $imageCount = $ImagePaths.Count
                    if ($imageCount -le 1) { return $MinFramerate }

                    $totalSsim = 0.0
                    $comparisonCount = 0

                    for ($i = 0; $i -lt ($imageCount - 1); $i++) {
                        $image1 = $ImagePaths[$i]
                        $image2 = $ImagePaths[$i + 1]
                        try {
                            $ssimOutput = ffmpeg -v warning -i "$image2" -i "$image1" -lavfi ssim -f null - 2>&1
                            $ssimMatch = $ssimOutput | Select-String -Pattern 'All:([\d.]+)'
                            if ($ssimMatch) {
                                $ssimValue = [double]$ssimMatch.Matches[0].Groups[1].Value
                                $totalSsim += $ssimValue
                                $comparisonCount++
                            }
                        }
                        catch {}
                    }

                    if ($comparisonCount -eq 0) {
                        return [int](($MinFramerate + $MaxFramerate) / 2)
                    }

                    $avgSsim = $totalSsim / $comparisonCount
                    $calculatedFramerate = $MinFramerate + (($MaxFramerate - $MinFramerate) * (1.0 - $avgSsim))

                    return [int][math]::Round($calculatedFramerate)
                }

                $ErrorMessage = ""
                $ffmpegOutput = ""
                $ErrorOccurred = $false
                $framerate = GetDynamicFramerate $newFils # 動態計算 framerate (會大幅度影響轉換速度) [可改成直接給預設值]

                $ffmpegOutput = ffmpeg -v error -framerate $framerate -start_number $startNumber -i "$inputPattern" -vf "format=yuva420p,deband,unsharp=3:3:0.4:3:3:0" -c:v libwebp_anim -q:v 90 -compression_level 6 -loop 0 -preset drawing -an -map_metadata -1 "$outputFile" -y 2>&1

                if ($LASTEXITCODE -ne 0) {
                    $ErrorOccurred = $true
                    $ErrorMessage = $ffmpegOutput
                }

                return [PSCustomObject]@{
                    Success    = -not $ErrorOccurred
                    InputFiles = $inputFils
                    NewFiles   = $newFils
                    OutputFile = $outputFile
                    Error      = $ErrorMessage
                }
            }).AddArgument($inputFils).AddArgument($newFils).AddArgument($startNumber).AddArgument($inputPattern).AddArgument($outputFile)
    
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
                for ($i = 0; $i -lt $result.NewFiles.Count; $i++) {
                    $newFile = $result.NewFiles[$i]
                    $oldFile = $result.InputFiles[$i]

                    try {
                        Remove-Item -LiteralPath $newFile -Force -ErrorAction Stop
                    }
                    catch {
                        $errorOccurred = $true
                        Write-Warning "$newFile Delete Failed: $_"

                        # 嘗試把新檔案改回舊檔名
                        if (Test-Path $newFile) {
                            try {
                                Rename-Item -LiteralPath $newFile -NewName (Split-Path $oldFile -Leaf) -ErrorAction Stop
                            }
                            catch {
                                Write-Warning "Restore Failed: $newFile -> $oldFile : $_"
                            }
                        }
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