$currentRoot = $PSScriptRoot

Invoke-ps2exe `
    -MTA `
    -noConsole `
    -supportOS `
    -requireAdmin `
    -Product "VideoPlayer" `
    -Version "1.0.0.0" `
    -Description "VideoPlayer" `
    -Copyright "Copyright (C) 2025 Canaan HS" `
    -IconFile "$currentRoot/VideoPlayer.ico" `
    -InputFile "$currentRoot/VideoPlayer.ps1" `
    -OutputFile "$currentRoot/VideoPlayer.exe"