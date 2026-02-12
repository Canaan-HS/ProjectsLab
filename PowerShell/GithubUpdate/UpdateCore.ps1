param (
    [string]$owner = "",
    [string]$repo = "",
    [string]$asset_name = $null
)

if (-not $owner -or -not $repo) {
    Write-Error "Parameters 'owner' and 'repo' are required."
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
        Write-Host "Updated version record to $version"
    }
    else {
        New-Item -ItemType File -Path (Join-Path $callPath $newName) | Out-Null
        Write-Host "Created version record: $version"
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
        Write-Warning "Asset '$asset_name' not found. Using automatic detection."
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

    Write-Host "Downloading asset: $($asset.name)"
    Write-Host "Destination: $filePath"
    Write-Host "URL: $url"

    Invoke-WebRequest -Uri $url -OutFile $filePath
    Write-Host "Download complete: $($asset.name)"
}

function SendRequest {
    $response = Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repo/releases/latest" -Headers @{
        "User-Agent" = "PowerShell"
    }

    if (-not $response -or -not ($response.name -and $response.assets)) {
        Write-Error "Failed to fetch release info from GitHub."
        exit 1
    }

    $oldVersion = ParseVersion (GetVersion)
    $newVersion = ParseVersion $response.name

    if (-not $oldVersion) {
        SetVersion $response.name
        Write-Host "No previous version found. Recorded version: $($response.name)"
        exit 0
    }

    if ($oldVersion -eq $newVersion) {
        Write-Host "Up to date. Current version: $($response.name)"
    }
    elseif ($oldVersion -lt $newVersion) {
        Write-Host "Update available: $($response.name) (current: $oldVersion)"
        $downloadInfo = GetDownloadInfo -assets $response.assets

        if ($downloadInfo) {
            foreach ($asset in $downloadInfo) { DownloadAsset -asset $asset }
            SetVersion $response.name
            Write-Host "Version updated to $($response.name)"
        }
        else {
            Write-Warning "No suitable asset found for download."
        }
    }
    else {
        SetVersion $response.name
        Write-Warning "Local version ($oldVersion) is newer than latest release ($newVersion). Version record reset to $($response.name)"
    }
}

SendRequest