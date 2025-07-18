# ? 搭配本地 ffmpeg 使用

function StartConvert {
    $inputPath = $null

    while ($true) {
        $inputPath = Read-Host "ImgPath"
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
                    # -loop 0: 無限循環
                    # -c:v libwebp_anim: 使用 webp 動畫編碼
                    # -q:v 85: 圖片品質 (0-100), 越高越好
                    # -compression_level 6: 壓縮等級 (0-6), 越高壓縮率越高但越慢
                    # -threads 0: 自動分配核心
                    # -pix_fmt yuva420p: 像素格式, 支援透明度
                    ffmpeg -i "$inputFile" -loop 0 -c:v libwebp_anim -q:v 85 -compression_level 6 -threads 0 -pix_fmt yuva420p -map_metadata -1 "$outputFile" -y
                }
                else {
                    # -an: 去除音訊
                    # -c:v libwebp: 使用 webp 圖片編碼
                    # -q:v 85: 圖片品質
                    # -compression_level 6: 壓縮等級
                    # -preset drawing: 預設集, 適合細節豐富的圖片
                    # -vf "smartblur=luma_radius=1.0:luma_strength=-0.5": 進行更平滑的智慧銳化
                    # -threads 0: 自動分配核心
                    # -pix_fmt yuva420p: 像素格式, 支援透明度
                    ffmpeg -i "$inputFile" -an -c:v libwebp -q:v 85 -compression_level 6 -preset drawing -vf "smartblur=luma_radius=1.0:luma_strength=-0.5" -threads 0 -pix_fmt yuva420p -map_metadata -1 "$outputFile" -y
                }
            })

        # 傳入參數
        $runspace.AddArgument($inputFile)
        $runspace.AddArgument($outputFile)
        $runspace.AddArgument($isGif)

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

        try {
            # 如果有載入 webp 格式圖片, 那麼就不能刪除, 這會導致全部為空
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