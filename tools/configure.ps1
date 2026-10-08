param([switch]$ListDevices, [switch]$ChooseDevice, [string]$Device, [string[]]$Events, [string]$Volume, [switch]$On, [switch]$Off, [string]$Test)
$ErrorActionPreference = 'Stop'
if ($On -and $Off) { throw 'Choose -On or -Off.' }
$repoDir = Split-Path $PSScriptRoot -Parent
$audio = Join-Path $repoDir 'core/windows-audio.ps1'
if ($ChooseDevice) {
    $choices = @((& $audio -ListDevices | ConvertFrom-Json) | ForEach-Object { $_ })
    Write-Host '0) System default'
    for ($i=0; $i -lt $choices.Count; $i++) { Write-Host "$($i+1)) $($choices[$i].name)" }
    $choice = Read-Host 'Output number'
    if ($choice -notmatch '^\d+$' -or [int]$choice -gt $choices.Count) { throw 'Invalid output number.' }
    $Device = if ([int]$choice -eq 0) { 'default' } else { 'windows:' + $choices[[int]$choice-1].id }
}
$changeDevice = $ChooseDevice -or $PSBoundParameters.ContainsKey('Device')
if ($ListDevices) {
    $outputs = @((& $audio -ListDevices | ConvertFrom-Json) | ForEach-Object {
        [pscustomobject]@{ id = ('windows:' + $_.id); name = $_.name }
    })
    ConvertTo-Json -InputObject $outputs -Depth 4
    return
}
$configPath = $env:ROBOTSPEAK_CONFIG
if (-not $configPath) {
    $base = $env:XDG_CONFIG_HOME
    if (-not $base) { $base = $env:APPDATA }
    $configPath = Join-Path $base 'robotspeak-agents/config.json'
}
$known = @('received','done','review','question','approval','failed','blocked','turn')
$config = [pscustomobject]@{ events = $known; device = 'default'; volume = 50; enabled = $true }
if (Test-Path -LiteralPath $configPath) {
    $loaded = [IO.File]::ReadAllText($configPath) | ConvertFrom-Json
    if ($loaded -isnot [pscustomobject]) { throw 'Invalid RobotSpeak configuration.' }
    if ($loaded.PSObject.Properties['events']) { $config.events = $loaded.events }
    if ($loaded.PSObject.Properties['device']) { $config.device = $loaded.device }
    if ($loaded.PSObject.Properties['volume']) { $config.volume = $loaded.volume }
    if ($loaded.PSObject.Properties['enabled']) { $config.enabled = $loaded.enabled }
}
if ($PSBoundParameters.ContainsKey('Volume')) { $config.volume = $Volume }
if ($On) { $config.enabled = $true }
if ($Off) { $config.enabled = $false }
if ($PSBoundParameters.ContainsKey('Events')) {
    if ($Events.Count -eq 1 -and $Events[0] -eq 'all') { $config.events = $known }
    elseif ($Events.Count -eq 1 -and $Events[0] -eq 'none') { $config.events = @() }
    else { $config.events = @($Events | ForEach-Object { $_.ToLowerInvariant() }) }
}
if ($changeDevice) {
    if ($Device -ne 'default') {
        if (-not $Device.StartsWith('windows:')) { throw 'PowerShell uses a windows:<endpoint ID> device.' }
        $id = $Device.Substring(8)
        $available = @((& $audio -ListDevices | ConvertFrom-Json) | ForEach-Object { $_ })
        if (-not ($available | Where-Object { $_.id -eq $id })) { throw 'Selected Windows device is unavailable.' }
    }
    $config.device = $Device
}
if ($config.events -isnot [array]) { throw 'events must be an array.' }
foreach ($state in $config.events) { if ($known -cnotcontains $state) { throw "Unknown RobotSpeak state: $state" } }
if ($config.device -isnot [string] -or $config.device -notmatch '^(default|windows:.+)$' -or $config.device -match '[\x00-\x1f]') { throw 'Invalid Windows output device.' }
if ([string]$config.volume -notmatch '^\d{1,3}$' -or [int]$config.volume -gt 100) { throw 'Volume must be an integer from 0 to 100.' }
$config.volume = [int]$config.volume
if ($config.enabled -isnot [bool]) { throw 'enabled must be a boolean.' }
$save = $PSBoundParameters.ContainsKey('Events') -or $changeDevice -or $PSBoundParameters.ContainsKey('Volume') -or $On -or $Off
if ($save) {
    $folder = Split-Path $configPath -Parent
    [IO.Directory]::CreateDirectory($folder) | Out-Null
    $temporary = Join-Path $folder ('.config-' + [guid]::NewGuid().ToString() + '.json')
    try {
        [IO.File]::WriteAllText($temporary, ($config | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
        if (-not ('RobotSpeakConfigFile' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class RobotSpeakConfigFile {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool MoveFileExW(string source, string target, uint flags);
    public static void Replace(string source, string target) {
        if (!MoveFileExW(source,target,1)) throw new Win32Exception(Marshal.GetLastWin32Error());
    }
}
'@
        }
        # Rename with replacement works on Windows disks and WSL's UNC provider.
        [RobotSpeakConfigFile]::Replace($temporary, $configPath)
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
    Write-Output "Saved: $configPath"
}
if ($Test) {
    $phrases = @{ received=@('RCV','Neutral'); done=@('OK','Satisfied'); review=@('OK','Doubtful'); question=@('K','Curious'); approval=@('K','Concerned'); failed=@('ERR','Apologetic'); blocked=@('ERR','Concerned'); turn=@('K','Neutral') }
    if (-not $phrases.ContainsKey($Test)) { throw 'Unknown RobotSpeak state.' }
    $deviceForTest = $config.device
    if ($env:ROBOTSPEAK_DEVICE) { $deviceForTest = $env:ROBOTSPEAK_DEVICE }
    $volumeForTest = $config.volume
    if (Test-Path Env:ROBOTSPEAK_VOLUME) {
        if ($env:ROBOTSPEAK_VOLUME -notmatch '^\d{1,3}$' -or [int]$env:ROBOTSPEAK_VOLUME -gt 100) { throw 'Volume must be an integer from 0 to 100.' }
        $volumeForTest = [int]$env:ROBOTSPEAK_VOLUME
    }
    if ($volumeForTest -eq 0) { return }
    $callsign = '2'
    if ($env:ROBOTSPEAK_CALLSIGN) { $callsign = $env:ROBOTSPEAK_CALLSIGN }
    $voice = Join-Path $repoDir 'vendor/robotspeak/robot-voice.ps1'
    $phrase = $phrases[$Test]
    if ($deviceForTest -eq 'default' -and $volumeForTest -eq 100) { & $voice -Word $phrase[0] -Mood $phrase[1] -Callsign $callsign -PauseMs 0 }
    else {
        if ($deviceForTest -ne 'default' -and -not $deviceForTest.StartsWith('windows:')) { throw 'Test needs a Windows output device.' }
        $endpoint = if ($deviceForTest -eq 'default') { 'default' } else { $deviceForTest.Substring(8) }
        $wav = [IO.Path]::GetTempFileName()
        try {
            & $voice -Word $phrase[0] -Mood $phrase[1] -Callsign $callsign -OutFile $wav
            & $audio -Device $endpoint -File $wav -Volume $volumeForTest
        } finally { [IO.File]::Delete($wav) }
    }
} elseif (-not $save) {
    $config | ConvertTo-Json -Depth 4
}
