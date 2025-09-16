$Roaming = $env:AppData
$Local = $env:LocalAppData
$LocalLow = "$(split-path $Roaming)\LocalLow"

$findFolders = @($Roaming, $Local, $LocalLow)
$excludeFolders = @('Coodesker', 'globalStorage', 'TokenBroker')
$cacheFolders = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@(
        'Temp', 'Log', 'Logs', 'Crashpad', 'History', 'INetHistory', 'CrashDumps',
        'Cache', 'Cache2', '.cache', 'Caches', 'GLCache', 'DXCache', 'lru-cache',
        '.tiny_cache', 'librarycache', 'GPUCache', 'Code Cache', 'AppCache', 'AssetCache',
        'BrowserCache', 'ImageCache', 'CachedData', 'CachedExtensions', 'OfflineCache',
        'media_cache', 'MediaCache', 'DawnCache', 'INetCache', 'ShaderCache', 'GrShaderCache',
        'ScriptCache', 'CacheStorage', 'webcache', 'extensions_crx_cache', '__pycache__', 'Telemetry',
        'Temporary Internet Files'
    ),
    [System.StringComparer]::OrdinalIgnoreCase
)

foreach ($find in $findFolders) {
    $found = Get-ChildItem -Path $find -Recurse -Directory -ErrorAction SilentlyContinue |
    Where-Object {
        if (-not $cacheFolders.Contains($_.Name)) { return $false }
        foreach ($ex in $excludeFolders) {
            if ($_.FullName.IndexOf($ex, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                return $false
            }
        }
        return $true
    } | Select-Object -ExpandProperty FullName -Unique

    if ($found) {
        $found | ForEach-Object {
            write-host $_
        }
    }
}

write-host "掃描完成"