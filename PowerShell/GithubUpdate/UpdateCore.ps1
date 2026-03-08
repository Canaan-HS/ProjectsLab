param (
    [Alias("o")]
    [string]$owner = "",

    [Alias("r")]
    [string]$repo = "",

    [Alias("a")]
    [string]$asset_name = $null,

    [Alias("e")]
    [string]$exclude_patterns = $null,

    [Alias("h")]
    [switch]$help
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function ShowHelp {
    Write-Host @"

GitHub 發佈快速更新

使用:
  gau.exe [選項]

選項:
  -o, -owner <name>              GitHub owner
  -r, -repo <name>               GitHub repository
  -a, -asset_name <name>         Asset name keyword
  -e, -exclude_patterns <list>   Exclude patterns (comma separated)
  -h, -help                      Show this help

範例:
  gau -o user -r app
  gau -o user -r app -a "software_x64_portable.exe"
  gau -o user -r app -e "debug,source"

"@ -ForegroundColor Green
    exit 0
}

if ($help) { ShowHelp }
elseif (-not $owner -or -not $repo) {
    Write-Host "參數 -owner 和 -repo 是必需的。" -ForegroundColor Red
    ShowHelp
}

# ===== 核心程式 =====

$callPath = (Get-Location).Path

$versionRecordTemplate = "! Version - $repo - {0}"
$prefix = $versionRecordTemplate -replace '\{0\}', ''

# 取得版本文件
$versionFile = Get-ChildItem -Path $callPath -File -Filter "$prefix*" |
Sort-Object Name -Descending |
Select-Object -First 1

function GetVersion {
    if (-not $versionFile) { return "" }
    return $versionFile.Name.Substring($prefix.Length)
}

function SetVersion {
    param([string]$version)

    $newName = $versionRecordTemplate -f $version

    if ($versionFile) {
        Rename-Item -Path $versionFile.FullName -NewName $newName -Force
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

    # 抽取數字版本
    if ($version -match '\d+(\.\d+){1,3}') {
        $version = $matches[0]
    }

    $parsed = $null
    if ([version]::TryParse($version, [ref]$parsed)) {
        return $parsed
    }

    return $null
}

function GetDownloadInfo {
    param($assets)

    $notExecutable = "(?i)sha256|checksum|checksums|hash|source|src|debug|symbols|pdb|test|tests"
    $notX64Architecture = "(?i)arm|arm64|aarch64|x86|32[-_ ]?bit"

    # 如果有指定排除檔案名特徵
    if ($exclude_patterns) {
        $excludeRegex = "(?i)" + (($exclude_patterns -split ',' | ForEach-Object {
                    [regex]::Escape($_.Trim())
                }) -join '|')
    }

    # 如果有指定下載特定檔案名稱，用包含匹配（忽略大小寫）
    if ($asset_name) {
        $matched = $assets | Where-Object {
            $_.name.Contains($asset_name) -and
            -not ($excludeRegex -and $_.name -match $excludeRegex) -and
            $_.name -notmatch $notExecutable -and
            $_.name -notmatch $notX64Architecture
        }
        if ($matched -and $matched.name) { return $matched }
        Write-Host "未找到包含 '$asset_name' 的資產，使用自動檢測。" -ForegroundColor Yellow
    }

    # ! 塞選條件以我個人使用為主, 並非通用性
    # 自動查找常見 windows x64 資產
    $windowsAsset = $assets |
    ForEach-Object {
        $name = $_.name

        # 排除檔案名稱匹配
        if ($excludeRegex -and $name -match $excludeRegex) { return }
        # 排除非目標
        if ($name -match $notExecutable) { return }
        # 排除非 x64 架構
        if ($name -match $notX64Architecture) { return }

        $score = 0

        # 平台
        if ($name -match '(?i)win|windows') { $score += 100 }
        # 架構
        if ($name -match '(?i)x64|x86_64|x86-64|win64|win-x64|64[-_ ]?bit') { $score += 60 }
        # 安裝類型
        if ($name -match '(?i)portable|standalone|noinstall') { $score += 40 }
        # 格式
        if ($name -match '(?i)zip|7z|rar') { $score += 30 } elseif ($name -match '(?i)exe|msi' ) { $score += 20 }

        [PSCustomObject]@{
            Asset = $_
            Score = $score
        }
    } |
    Sort-Object Score -Descending |
    Select-Object -ExpandProperty Asset

    return $windowsAsset
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
        "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36"
    }

    if (-not $response -or -not ($response.tag_name -and $response.assets)) {
        Write-Host "無法獲取最新版本資訊，請檢查倉庫名稱和網絡連接。" -ForegroundColor Red
        return
    }

    $oldVersion = ParseVersion (GetVersion)
    $newVersion = ParseVersion $response.tag_name

    if (-not $oldVersion) {
        Write-Host "未找到之前的版本。"
        SetVersion $response.tag_name
        return
    }

    if ($oldVersion -eq $newVersion) {
        Write-Host "已是最新版本。`n當前版本: $($response.tag_name)"
    }
    elseif ($oldVersion -lt $newVersion) {
        Write-Host "有可用更新: $($response.tag_name) (目前版本: $oldVersion)"
        $downloadInfo = GetDownloadInfo -assets $response.assets

        if ($downloadInfo) {
            Write-Host "版本更新為 $($response.tag_name)"
            foreach ($asset in $downloadInfo) { DownloadAsset -asset $asset }
            SetVersion $response.tag_name
        }
        else {
            Write-Host "未找到適合下載的資產。請檢查倉庫的發布頁面以確保有適合 Windows 的資產，或使用 -asset_name 參數指定資產名稱。" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "本機版本 ($oldVersion) 比最新發布版本 ($newVersion) 更新。 版本記錄已重置。" -ForegroundColor Yellow
        SetVersion $response.tag_name
    }
}

SendRequest
Read-Host "`n按任意鍵退出"