$currentRoot = $PSScriptRoot

Invoke-ps2exe `
    -MTA `
    -supportOS `
    -Product "GithubUpdate" `
    -Version "1.0.0.0" `
    -Description "GithubUpdate" `
    -Copyright "Copyright (C) 2026 Canaan HS" `
    -InputFile "$currentRoot/UpdateCore.ps1" `
    -OutputFile "$currentRoot/gu.exe"