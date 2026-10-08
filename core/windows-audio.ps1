param([switch]$ListDevices, [string]$Device, [string]$File, [ValidateRange(0,100)][int]$Volume = 100)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
if (-not ('RobotSpeakAudio' -as [type])) {
    Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'windows-audio.cs')))
}
if ($ListDevices) {
    ConvertTo-Json -InputObject @([RobotSpeakAudio]::List()) -Compress
} else {
    if (-not $Device -or -not $File) { throw 'Use -ListDevices or -Device <endpoint ID> -File <WAV>.' }
    [RobotSpeakAudio]::Play($Device, $File, $Volume)
}
