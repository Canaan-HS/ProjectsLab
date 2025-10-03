param (
    [string]$mediaPath
)

$argu = @(
    "-fs",
    "-stats",
    "-infbuf",
    "-noborder",
    "`"$mediaPath`""
)

Start-Process ffplay -ArgumentList $argu -NoNewWindow