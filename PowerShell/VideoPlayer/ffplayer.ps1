param (
    [string]$mediaPath
)

$argu = @(
    "-fs",
    "-infbuf",
    "-noborder",
    "-loop", "0",
    "-volume", "100",
    "`"$mediaPath`""
)

Start-Process ffplay -ArgumentList $argu -NoNewWindow