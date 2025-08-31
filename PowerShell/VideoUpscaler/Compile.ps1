$currentRoot = $PSScriptRoot

Invoke-ps2exe `
    -MTA `
    -supportOS `
    -requireAdmin `
    -Product "VideoUpscaler" `
    -Version "1.0.0.0" `
    -Description "VideoUpscaler" `
    -Copyright "Copyright (C) 2025 Canaan HS" `
    -InputFile "$currentRoot/vu.ps1" `
    -OutputFile "$currentRoot/vu.exe"