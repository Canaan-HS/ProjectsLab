$currentRoot = $PSScriptRoot

Invoke-ps2exe `
    -MTA `
    -noConsole `
    -supportOS `
    -Product "ffplayer" `
    -Version "1.0.0.0" `
    -Description "ffplayer" `
    -Copyright "Copyright (C) 2025 Canaan HS" `
    -IconFile "$currentRoot/ffplayer.ico" `
    -InputFile "$currentRoot/ffplayer.ps1" `
    -OutputFile "$currentRoot/ffplayer.exe"