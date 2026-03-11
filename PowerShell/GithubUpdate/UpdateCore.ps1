param (
    [string]$owner = "",
    [string]$repo = "",
    [string]$asset_name = $null
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

if (-not $owner -or -not $repo) {
    Write-Host "參數 -owner 和 -repo 是必需的。" -ForegroundColor Red
    exit 1
}

$callPath = (Get-Location).Path
$versionRecordTemplate = "! Current Version - {0}"
$prefix = $versionRecordTemplate -replace '\{0\}', ''

function GetVersion {
    $file = Get-ChildItem -Path $callPath -File -Filter "$prefix*" | Select-Object -First 1
    if (-not $file) { return "" }
    return $file.Name.Substring($prefix.Length)
}

function SetVersion {
    param([string]$version)

    $newName = $versionRecordTemplate -f $version
    $existing = Get-ChildItem -Path $callPath -File -Filter "$prefix*" | Select-Object -First 1

    if ($existing) {
        Rename-Item -Path $existing.FullName -NewName $newName -Force
        Write-Host "版本紀錄修改: $version"
    }
    else {
        New-Item -ItemType File -Path (Join-Path $callPath $newName) | Out-Null
        Write-Host "創建版本紀錄: $version"
    }
}

function ParseVersion {
    param([string]$version)

    if ([string]::IsNullOrWhiteSpace($version)) { return $null }

    $parsed = $null
    if ([version]::TryParse($version, [ref]$parsed)) { return $parsed }

    return $null
}

function GetDownloadInfo {
    param($assets)

    if ($asset_name) {
        $matched = $assets | Where-Object { $_.name -eq $asset_name }
        if ($matched) { return $matched }
        Write-Host "未找到名為 '$asset_name' 的資產，使用自動檢測。" -ForegroundColor Yellow
    }

    $windowsCandidates = $assets | Where-Object {
        $name = $_.name.ToLowerInvariant()
        ($name -like "*windows*") -and
        ($name -notlike "*sha256*") -and
        ($name -notlike "*checksum*") -and
        ($name -notlike "*hash*")
    }

    $x64Patterns = @("x86_64", "x86-64", "x64", "amd64", "win64", "64bit", "64-bit", "x86-64")

    $x64Candidates = $windowsCandidates | Where-Object {
        $name = $_.name.ToLowerInvariant()
        $x64Patterns | Where-Object { $name -like "*$_*" } | Select-Object -First 1
    }

    return if ($x64Candidates -and $x64Candidates.Count -gt 0) { $x64Candidates } else { $windowsCandidates }
}

function DownloadAsset {
    param($asset)

    $url = $asset.browser_download_url
    $filePath = Join-Path $callPath $asset.name

    Write-Host "下載資產: $($asset.name)"
    Write-Host "目標位置: $filePath"
    Write-Host "下載網址: $url"

    Invoke-WebRequest -Uri $url -OutFile $filePath
    Write-Host "下載完成: $($asset.name)"
}

function SendRequest {
    $response = Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repo/releases/latest" -Headers @{
        "User-Agent" = "PowerShell"
    }

    if (-not $response -or -not ($response.name -and $response.assets)) {
        Write-Host "無法獲取最新版本資訊，請檢查倉庫名稱和網絡連接。" -ForegroundColor Red
        return
    }

    $oldVersion = ParseVersion (GetVersion)
    $newVersion = ParseVersion $response.name

    if (-not $oldVersion) {
        Write-Host "未找到之前的版本。"
        SetVersion $response.name
        return
    }

    if ($oldVersion -eq $newVersion) {
        Write-Host "已是最新版本。`n當前版本: $($response.name)"
    }
    elseif ($oldVersion -lt $newVersion) {
        Write-Host "有可用更新: $($response.name) (目前版本: $oldVersion)"
        $downloadInfo = GetDownloadInfo -assets $response.assets

        if ($downloadInfo) {
            Write-Host "版本更新為 $($response.name)"
            foreach ($asset in $downloadInfo) { DownloadAsset -asset $asset }
            SetVersion $response.name
        }
        else {
            Write-Host "未找到適合下載的資產。請檢查倉庫的發布頁面以確保有適合 Windows 的資產，或使用 -asset_name 參數指定資產名稱。" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "本機版本 ($oldVersion) 比最新發布版本 ($newVersion) 更新。 版本記錄已重置。" -ForegroundColor Yellow
        SetVersion $response.name
    }
}

SendRequest
Read-Host "`n按任意鍵退出"