# ? 搭配本地 ffmpeg 使用
$inputPath = $null

while ($true) {
    $inputPath = Read-Host "ImgPath"
    $inputPath = $inputPath.Trim('"')

    if (-not(Test-Path -LiteralPath $inputPath)) {
        Write-Host "`n[Error] Path does not exist`n" -ForegroundColor Red
    } else {
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
                ffmpeg -i "$inputFile" -loop 0 -c:v libwebp_anim -q:v 85 -compression_level 6 -threads 0 "$outputFile" -y
            } else {
                ffmpeg -i "$inputFile" -an -c:v libwebp -q:v 85 -compression_level 6 -preset drawing -threads 0 "$outputFile" -y
            }
        })

        # 傳入參數
        $runspace.AddArgument($inputFile)
        $runspace.AddArgument($outputFile)
        $runspace.AddArgument($isGif)

        try {
            $jobs += [PSCustomObject]@{
                Runspace = $runspace
                InputFile = $inputFile
                AsyncResult = $runspace.BeginInvoke()
            }
        } catch {
            $runspace.Dispose()
        }
    }

# 等待所有工作完成
foreach ($job in $jobs) {
    $job.Runspace.EndInvoke($job.AsyncResult)
    $job.Runspace.Dispose()

    try { # 如果有載入 webp 格式圖片, 那麼就不能刪除, 這會導致全部為空
        Remove-Item -LiteralPath $job.InputFile -Force
    } catch {
        Write-Warning "Remove Failed： $($job.InputFile)"
    }
}

$runspacePool.Close()
$runspacePool.Dispose()