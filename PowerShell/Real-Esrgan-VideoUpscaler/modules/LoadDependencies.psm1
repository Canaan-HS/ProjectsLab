function FetchModel {
    param (
        [string]$modelFolder
    )

    if (-not(Test-Path $modelFolder)) {
        Write-Host "[模型文件夾不存在] $modelFolder"
        exit
    }

    $modelList = @{}

    # 檢查內部是否有文件夾
    $foldersToCheck = Get-ChildItem -Path $modelFolder -Recurse -Directory

    if ($foldersToCheck.Count -gt 0) {
        foreach ($folder in $foldersToCheck) {
            $filesInFolder = Get-ChildItem -Path $folder.FullName | 
                Where-Object { $_.Extension -in '.bin', '.param' } | # 篩選 .bin 和 .param
                Group-Object { $_.BaseName } | # 按檔案基礎名稱分組
                Where-Object { $_.Group.Count -eq 2 } # 只保留擁有兩個檔案的組

            if ($filesInFolder.Count -gt 0) {
                $path = $folder -split "\\"
                $modelList["$($path[-2])\$($path[-1])"] = $true
            }
        }
    } else {
        Get-ChildItem -Path $modelFolder | 
            Where-Object { $_.Extension -in '.bin', '.param' } | # 篩選 .bin 和 .param
            Group-Object { $_.BaseName } | # 按檔案基礎名稱分組
            Where-Object { $_.Group.Count -eq 2 } | # 只保留擁有兩個檔案的組
            Select-Object -ExpandProperty Group | # 展開檔案組
            ForEach-Object { $_.BaseName } | # 取得每個檔案的基礎名稱
            ForEach-Object { $modelList[$_] = $true }
    }

    if ($modelList.Count -eq 0) {
        Write-Host "[模型取得失敗] $modelFolder"
        exit
    }

    return $modelList
}

function FetchDependent {
    param (
        [string]$FetchPath, # 抓取依賴檔案路徑
        [boolean]$Init = $false # 初始化進程
    )

    $srmdFolder = "models-srmd"
    $rifeFolder = "rife-models"
    $realesrganFolder = "realesrgan-models"

    $ffmpegPath = "$FetchPath\tools\ffmpeg.exe"
    $ffprobePath = "$FetchPath\tools\ffprobe.exe"

    $srmdPath = "$FetchPath\srmd-ncnn-vulkan.exe"
    $rifePath = "$FetchPath\rife-ncnn-vulkan.exe"
    $realesrganPath = "$FetchPath\realesrgan-ncnn-vulkan.exe"

    # 關閉多餘的進程
    if ($Init) {
        Get-Process -Name "ffmpeg", "ffprobe", "rife-ncnn-vulkan", "realesrgan-ncnn-vulkan" -ErrorAction SilentlyContinue | Stop-Process -Force
        write-host "初始化進程完成"
    }

    # 判斷依賴檔案
    @(
        $ffmpegPath,
        $ffprobePath,
        $srmdPath,
        $rifePath,
        $realesrganPath
    ) | ForEach-Object {
        if (-not(Test-Path -LiteralPath $_)) {
            Write-Host "[依賴取得失敗] $_"
            exit
        }
    }

    FetchModel "$FetchPath\$srmdFolder" # 只用於驗證
    $rifeModelList = FetchModel "$FetchPath\$rifeFolder"
    $realesrganModelList = FetchModel "$FetchPath\$realesrganFolder"

    Write-Host "獲取依賴完成`n"
    return @{
        ffmpeg = $ffmpegPath
        ffprobe = $ffprobePath
        srmd = $srmdPath
        rife = $rifePath
        realesr = $realesrganPath
        rifeModelList = $rifeModelList
        realesrganModelList = $realesrganModelList
        realesrganModelFolder = $realesrganFolder
    }
}