# ? 搭配本地 ffmpeg, ffprobe, gifski 使用

Add-Type -AssemblyName System.Drawing

function Get-ImageDimensions {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        $image = [System.Drawing.Image]::FromFile($Path)
        try {
            return [PSCustomObject]@{
                Width  = $image.Width
                Height = $image.Height
            }
        }
        finally {
            $image.Dispose()
        }
    }
    catch {
        # 單引號不要拿掉，自動排版會在逗號後補空白，ffprobe 會把 height 當成輸入檔名
        $probe = ffprobe -v error -select_streams v:0 -show_entries 'stream=width,height' -of csv=p=0 "$Path" | Select-Object -First 1
        $parts = if ($probe) { $probe.ToString().Trim().Split(',') } else { @() }

        if ($parts.Count -ge 2 -and $parts[0] -match '^\d+$' -and $parts[1] -match '^\d+$') {
            return [PSCustomObject]@{
                Width  = [int]$parts[0]
                Height = [int]$parts[1]
            }
        }

        throw "Unable to read image dimensions: $Path"
    }
}

function New-HardLinkOrCopy {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    try {
        New-Item -ItemType HardLink -Path $Destination -Target $Source -ErrorAction Stop | Out-Null
    }
    catch {
        Copy-Item -LiteralPath $Source -Destination $Destination -ErrorAction Stop
    }

    return $Destination
}

function Get-UniformPngSequence {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Frames,

        [Parameter(Mandatory = $true)]
        [string]$Directory,

        [Parameter(Mandatory = $true)]
        [string]$Uid,

        [int]$Padding = 4
    )

    $orderedSource = @($Frames | Sort-Object Number)
    $ordered = @(
        for ($i = 0; $i -lt $orderedSource.Count; $i++) {
            [PSCustomObject]@{
                Index     = $i + 1
                Path      = $orderedSource[$i].Path
                Number    = $orderedSource[$i].Number
                Extension = $orderedSource[$i].Extension
            }
        }
    )

    $count = $ordered.Count
    if ($count -lt 2) {
        throw 'A group must contain at least 2 frames'
    }

    # 1. 取群組最大寬高
    $maxW = 0
    $maxH = 0
    foreach ($frame in $ordered) {
        $dim = Get-ImageDimensions -Path $frame.Path
        if ($dim.Width -gt $maxW) { $maxW = $dim.Width }
        if ($dim.Height -gt $maxH) { $maxH = $dim.Height }
    }
    if ($maxW -le 0 -or $maxH -le 0) {
        throw 'Invalid image dimensions in group'
    }

    # 2. 建立連續序號的暫存 PNG (PNG 原檔直接 hardlink，不重新壓縮)
    $tempFiles = [System.Collections.Generic.List[string]]::new()
    $pattern = Join-Path -Path $Directory -ChildPath ("{0}_%0{1}d.png" -f $Uid, $Padding)
    $indexPaths = @{}

    foreach ($frame in $ordered) {
        if ($frame.Extension -ieq '.png') {
            $target = Join-Path -Path $Directory -ChildPath ("{0}_{1}.png" -f $Uid, $frame.Index.ToString("D$Padding"))
            New-HardLinkOrCopy -Source $frame.Path -Destination $target | Out-Null
            $tempFiles.Add($target)
            $indexPaths[$frame.Index] = $target
        }
    }

    # 3. 非 PNG 依副檔名分批，每個副檔名只跑一次 ffmpeg
    $nonPng = @($ordered | Where-Object { $_.Extension -ine '.png' })
    if ($nonPng.Count -gt 0) {
        $batchNo = 0
        foreach ($batch in ($nonPng | Group-Object Extension)) {
            $batchNo++
            $ext = $batch.Name
            $batchFrames = @($batch.Group | Sort-Object Number)
            $batchCount = $batchFrames.Count
            $batchUid = "{0}_src{1}" -f $Uid, $batchNo
            $batchPattern = Join-Path -Path $Directory -ChildPath ("{0}_%0{1}d{2}" -f $batchUid, $Padding, $ext)
            $batchOutPattern = Join-Path -Path $Directory -ChildPath ("{0}_%0{1}d.png" -f $batchUid, $Padding)

            $batchLinks = @()
            for ($k = 1; $k -le $batchCount; $k++) {
                $link = Join-Path -Path $Directory -ChildPath ("{0}_{1}{2}" -f $batchUid, $k.ToString("D$Padding"), $ext)
                New-HardLinkOrCopy -Source $batchFrames[$k - 1].Path -Destination $link | Out-Null
                $batchLinks += $link
            }

            try {
                $convertOutput = ffmpeg -hide_banner -loglevel error -start_number 1 -i "$batchPattern" `
                    -c:v png -pix_fmt rgba -compression_level 100 -start_number 1 "$batchOutPattern" -y 2>&1

                if ($LASTEXITCODE -ne 0) {
                    throw "ffmpeg PNG batch conversion failed ($ext): $convertOutput"
                }

                for ($k = 1; $k -le $batchCount; $k++) {
                    $frame = $batchFrames[$k - 1]
                    $converted = Join-Path -Path $Directory -ChildPath ("{0}_{1}.png" -f $batchUid, $k.ToString("D$Padding"))
                    $target = Join-Path -Path $Directory -ChildPath ("{0}_{1}.png" -f $Uid, $frame.Index.ToString("D$Padding"))
                    New-HardLinkOrCopy -Source $converted -Destination $target | Out-Null
                    $tempFiles.Add($target)
                    $indexPaths[$frame.Index] = $target
                }
            }
            finally {
                foreach ($link in $batchLinks) {
                    Remove-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
                }
                for ($k = 1; $k -le $batchCount; $k++) {
                    $converted = Join-Path -Path $Directory -ChildPath ("{0}_{1}.png" -f $batchUid, $k.ToString("D$Padding"))
                    Remove-Item -LiteralPath $converted -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    # 4. 尺寸正規化：全部 PNG 且尺寸一致時直接跳過
    $needNormalize = $false
    foreach ($frame in $ordered) {
        if ($frame.Extension -ine '.png') {
            $needNormalize = $true
            break
        }
        $dim = Get-ImageDimensions -Path $frame.Path
        if ($dim.Width -ne $maxW -or $dim.Height -ne $maxH) {
            $needNormalize = $true
            break
        }
    }

    $finalPaths = @()
    if ($needNormalize) {
        $normUid = "{0}_norm" -f $Uid
        $normPattern = Join-Path -Path $Directory -ChildPath ("{0}_%0{1}d.png" -f $normUid, $Padding)
        $scaleFilter = "scale=$($maxW):$($maxH):force_original_aspect_ratio=decrease:flags=lanczos,pad=$($maxW):$($maxH):(ow-iw)/2:(oh-ih)/2"

        $normalizeOutput = ffmpeg -hide_banner -loglevel error -start_number 1 -i "$pattern" `
            -vf $scaleFilter -c:v png -pix_fmt rgba -compression_level 100 -start_number 1 "$normPattern" -y 2>&1

        if ($LASTEXITCODE -ne 0) {
            throw "ffmpeg normalize failed: $normalizeOutput"
        }

        for ($i = 1; $i -le $count; $i++) {
            $path = Join-Path -Path $Directory -ChildPath ("{0}_{1}.png" -f $normUid, $i.ToString("D$Padding"))
            $finalPaths += $path
            $tempFiles.Add($path)
        }
    }
    else {
        for ($i = 1; $i -le $count; $i++) {
            $finalPaths += $indexPaths[$i]
        }
    }

    return [PSCustomObject]@{
        Paths     = [string[]]$finalPaths
        Width     = $maxW
        Height    = $maxH
        TempFiles = [string[]]$tempFiles.ToArray()
    }
}

function Start-Convert {
    $inputDirectory = $null

    while ($true) {
        $inputDirectory = Read-Host "[Sequence -> GIF] DirectoryPath"
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
                $streamCount = (ffprobe -v quiet -select_streams v:0 -show_entries frame=media_type -of csv=p=0 "$($_.FullName)" | Measure-Object).Count
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
                    Prefix      = $baseName
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
    $errorOccurred = $false
    $maxThreads = [Math]::Max(1, [Math]::Ceiling([Environment]::ProcessorCount / 4))

    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $maxThreads)
    $runspacePool.ThreadOptions = "ReuseThread"
    $runspacePool.Open()

    # 篩選出圖片數量大於1的群組進行處理
    $groups = @($groupedFiles.GetEnumerator() | Where-Object { $_.Value.Files.Count -gt 1 })

    Write-Host # 與一開始的輸入行空一行
    if ($groups.Count -eq 0) {
        Write-Host "No image sequences found." -ForegroundColor Yellow
    }
    else {
        Write-Host "Found $($groups.Count) group(s) to convert." -ForegroundColor Yellow
    }

    $groups | ForEach-Object {

        $group = $_
        $uid = [guid]::NewGuid().ToString("N")
        $dir = Split-Path -Path $group.Value.Files[0].Path -Parent
        $padding = [Math]::Max(4, $group.Value.Padding)

        # 檔名有前綴時沿用舊版命名 (frame_00001.png -> frame.gif)
        $baseName = $group.Value.Prefix.TrimEnd('_')

        # 純數字檔名沒有前綴，改用「資料夾名 + 編號範圍」避免產生 空名稱.gif
        if ([string]::IsNullOrWhiteSpace($baseName)) {
            $folderName = Split-Path -Path $dir -Leaf
            $minNumber = ($group.Value.Files | Measure-Object -Property Number -Minimum).Minimum
            $maxNumber = ($group.Value.Files | Measure-Object -Property Number -Maximum).Maximum
            $baseName = "{0}_{1}-{2}" -f $folderName,
            ([int]$minNumber).ToString("D$padding"),
            ([int]$maxNumber).ToString("D$padding")
        }

        $outputFile = Join-Path -Path $dir -ChildPath "$baseName.gif"

        $frames = @($group.Value.Files | ForEach-Object {
                [PSCustomObject]@{
                    Path      = $_.Path
                    Number    = $_.Number
                    Extension = [System.IO.Path]::GetExtension($_.Path)
                }
            })
        $inputFils = @($frames | Sort-Object Number | ForEach-Object { $_.Path })

        Write-Host "[Prepare] $($frames.Count) frames -> $outputFile" -ForegroundColor DarkCyan

        try {
            # 抽象化：取得統一尺寸、統一格式的 PNG 序列
            $sequence = Get-UniformPngSequence -Frames $frames -Directory $dir -Uid $uid -Padding $padding
        }
        catch {
            $errorOccurred = $true
            Write-Error "Prepare Failed: $outputFile | $_"
            Get-ChildItem -LiteralPath $dir -Filter "$uid*" -File | Remove-Item -Force -ErrorAction SilentlyContinue
            return
        }

        Write-Host "[Convert] $outputFile (width $($sequence.Width))" -ForegroundColor Cyan

        # 建立一個新的 Runspace
        $runspace = [powershell]::Create()
        $runspace.RunspacePool = $runspacePool

        $runspace.AddScript({
                param($pngPaths, $width, $outputFile, $inputFils, $tempFiles)

                $ErrorMessage = ""
                $gifskiOutput = ""
                $ErrorOccurred = $false

                try {
                    $gifskiOutput = gifski --fps 22 --quality 100 --lossy-quality 100 --width $width --extra `
                        -o "$outputFile" @pngPaths 2>&1

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
                    InputFiles = $inputFils
                    TempFiles  = $tempFiles
                    OutputFile = $outputFile
                    Error      = $ErrorMessage
                }
            }).AddArgument($sequence.Paths).AddArgument($sequence.Width).AddArgument($outputFile).AddArgument($inputFils).AddArgument($sequence.TempFiles) | Out-Null

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
            foreach ($tempFile in @($result.TempFiles)) {
                Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
            }

            if ($result.Success) {
                foreach ($oldFile in @($result.InputFiles)) {
                    try {
                        Remove-Item -LiteralPath $oldFile -Force -ErrorAction Stop
                    }
                    catch {
                        $errorOccurred = $true
                        Write-Warning "$oldFile Delete Failed: $_"
                    }
                }

                Write-Host "[Done] $($result.OutputFile)" -ForegroundColor Green
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

    Start-Convert
}

# 執行主函數
Start-Convert