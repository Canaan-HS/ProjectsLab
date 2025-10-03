param (
    [string]$mediaPath
)

$argu = @(
    "-fs",
    "-infbuf",
    "-noborder",
    "-volume", "100",
    "`"$mediaPath`""
)

Start-Process ffplay -ArgumentList $argu -NoNewWindow