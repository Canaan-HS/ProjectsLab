$currentRoot = $PSScriptRoot

Invoke-ps2exe `
    -MTA `
    -supportOS `
    -Product "GAU" `
    -Version "1.0.0.0" `
    -Description "GAU" `
    -Copyright "Copyright (C) 2026 Canaan HS" `
    -InputFile "$currentRoot/Core.ps1" `
    -OutputFile "$currentRoot/gau.exe"