Import-Module ".\BackupCore.psm1"

$SavePath = "SavePath"
Main "$PSScriptRoot\$SavePath" (DefaultSavePath "$SavePath")