param (
    [string]$mediaPath
)

Start-Process ffplay -ArgumentList "-fs", "-loop", "0", "-infbuf", "`"$mediaPath`"" -NoNewWindow
exit