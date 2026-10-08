param([Parameter(Mandatory=$true)][string]$WorkDir)
$ErrorActionPreference = 'Stop'
$repoDir = Split-Path $PSScriptRoot -Parent
$configure = Join-Path $repoDir 'tools/configure.ps1'
$originalConfig = $env:ROBOTSPEAK_CONFIG
try {
    $env:ROBOTSPEAK_CONFIG = Join-Path $WorkDir 'windows-config.json'
    $devices = @((& $configure -ListDevices | ConvertFrom-Json) | ForEach-Object { $_ })
    foreach ($item in $devices) { if (-not $item.id.StartsWith('windows:') -or -not $item.name) { throw 'Invalid device list.' } }
    $initial = & $configure | ConvertFrom-Json
    # Old files gain the new defaults; this test may reuse its temporary file.
    if (-not $initial.PSObject.Properties['volume'] -or $initial.PSObject.Properties['enabled'].Value -isnot [bool]) { throw 'Missing new defaults.' }
    & $configure -Volume 50 -On | Out-Null
    & $configure -Events @('review','question') | Out-Null
    $saved = [IO.File]::ReadAllText($env:ROBOTSPEAK_CONFIG) | ConvertFrom-Json
    if (($saved.events -join ',') -ne 'review,question') { throw 'Events not persisted.' }
    if ($saved.volume -ne 50 -or -not $saved.enabled) { throw 'Volume or enabled state not persisted.' }
    if ($devices.Count -gt 0) {
        & $configure -Device $devices[0].id | Out-Null
        $saved = [IO.File]::ReadAllText($env:ROBOTSPEAK_CONFIG) | ConvertFrom-Json
        if ($saved.device -ne $devices[0].id) { throw 'Endpoint ID not persisted.' }
    }
    $before = [IO.File]::ReadAllText($env:ROBOTSPEAK_CONFIG)
    $rejected = $false
    try { & $configure -Events @('done','invalid') | Out-Null } catch { $rejected = $true }
    if (-not $rejected -or [IO.File]::ReadAllText($env:ROBOTSPEAK_CONFIG) -ne $before) { throw 'Invalid events modified preferences.' }
    $rejected = $false
    try { & $configure -Device 'windows:missing' | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'Unknown endpoint accepted.' }
    foreach ($bad in @('-1','101','1.5','junk','')) {
        $rejected = $false
        try { & $configure -Volume $bad | Out-Null } catch { $rejected = $true }
        if (-not $rejected -or [IO.File]::ReadAllText($env:ROBOTSPEAK_CONFIG) -ne $before) { throw 'Invalid volume modified preferences.' }
    }
    & $configure -Off | Out-Null
    $saved = [IO.File]::ReadAllText($env:ROBOTSPEAK_CONFIG) | ConvertFrom-Json
    if ($saved.enabled -ne $false -or $saved.volume -ne 50 -or ($saved.events -join ',') -ne 'review,question') { throw 'Off did not preserve preferences.' }
    & $configure -On | Out-Null
    if ([IO.File]::ReadAllText($env:ROBOTSPEAK_CONFIG) -ne $before) { throw 'On did not restore saved preferences.' }
    if ($saved.parts -ne 'callsign+word+mood') { throw 'Missing default parts.' }
    & $configure -Parts MSG,MOOD | Out-Null
    $saved = [IO.File]::ReadAllText($env:ROBOTSPEAK_CONFIG) | ConvertFrom-Json
    if ($saved.parts -ne 'word+mood') { throw 'Parts not normalized.' }
    & $configure -Parts 'Mood+ID' | Out-Null
    $saved = [IO.File]::ReadAllText($env:ROBOTSPEAK_CONFIG) | ConvertFrom-Json
    if ($saved.parts -ne 'callsign+mood') { throw 'Parts order not canonical.' }
    $before = [IO.File]::ReadAllText($env:ROBOTSPEAK_CONFIG)
    foreach ($bad in @('', 'voice', 'word+', 'word mood')) {
        $rejected = $false
        try { & $configure -Parts $bad | Out-Null } catch { $rejected = $true }
        if (-not $rejected -or [IO.File]::ReadAllText($env:ROBOTSPEAK_CONFIG) -ne $before) { throw "Invalid parts accepted: '$bad'" }
    }
    & $configure -Parts all | Out-Null
    & $configure -Events none | Out-Null
    $saved = [IO.File]::ReadAllText($env:ROBOTSPEAK_CONFIG) | ConvertFrom-Json
    if ($saved.events.Count -ne 0) { throw 'Cannot silence all events.' }
    # -Say honors the switch and the audible states; muted here, so it only reports.
    $env:ROBOTSPEAK_DEBUG = '1'; $env:ROBOTSPEAK_MUTE = '1'
    try {
        if (& $configure -Say done) { throw 'Silenced state announced.' }
        & $configure -Events all | Out-Null
        if ((& $configure -Say done) -ne 'done OK Satisfied 2') { throw 'Audible state not announced.' }
        $env:ROBOTSPEAK_CALLSIGN = '1'
        if ((& $configure -Say question) -ne 'question K Curious 1') { throw 'Callsign not honored.' }
        & $configure -Off | Out-Null
        if (& $configure -Say done) { throw 'Off did not silence -Say.' }
        if ((& $configure -Test done) -ne 'done OK Satisfied 1') { throw '-Test must play while off.' }
        & $configure -On | Out-Null
        $rejected = $false
        try { & $configure -Say bogus | Out-Null } catch { $rejected = $true }
        if (-not $rejected) { throw 'Unknown state accepted.' }
    } finally { Remove-Item Env:ROBOTSPEAK_DEBUG, Env:ROBOTSPEAK_MUTE, Env:ROBOTSPEAK_CALLSIGN -ErrorAction SilentlyContinue }
    $headerType = [RobotSpeakAudio].GetNestedType('Header', [Reflection.BindingFlags]::NonPublic)
    $formatType = [RobotSpeakAudio].GetNestedType('Format', [Reflection.BindingFlags]::NonPublic)
    $expectedHeader = if ([IntPtr]::Size -eq 8) { 48 } else { 32 }
    if ([Runtime.InteropServices.Marshal]::SizeOf([Activator]::CreateInstance($headerType)) -ne $expectedHeader -or [Runtime.InteropServices.Marshal]::SizeOf([Activator]::CreateInstance($formatType)) -ne 18) { throw 'Invalid WinMM ABI layout.' }
    # The PowerShell path attenuates exactly the same canonical samples as Perl.
    $stream = [IO.MemoryStream]::new()
    $writer = [IO.BinaryWriter]::new($stream)
    $writer.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $writer.Write([uint32]52)
    $writer.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt ')); $writer.Write([uint32]16)
    $writer.Write([uint16]1); $writer.Write([uint16]1); $writer.Write([uint32]22050); $writer.Write([uint32]44100)
    $writer.Write([uint16]2); $writer.Write([uint16]16); $writer.Write([Text.Encoding]::ASCII.GetBytes('data')); $writer.Write([uint32]16)
    foreach ($sample in @(-32768,-32767,-3,-1,0,1,3,32767)) { $writer.Write([int16]$sample) }
    $writer.Flush(); $source = $stream.ToArray(); $writer.Dispose(); $stream.Dispose()
    $scaled = [RobotSpeakAudio]::ScalePcm([byte[]]$source.Clone(), 50)
    $values = for ($i=44; $i -lt $scaled.Length; $i+=2) { [BitConverter]::ToInt16($scaled,$i) }
    if (($values -join ',') -ne '-16384,-16383,-1,0,0,0,1,16383') { throw 'Incorrect 50 percent PCM.' }
    if ([Convert]::ToBase64String([RobotSpeakAudio]::ScalePcm([byte[]]$source.Clone(),100)) -ne [Convert]::ToBase64String($source)) { throw '100 percent changes audio.' }
    $silent = [RobotSpeakAudio]::ScalePcm([byte[]]$source.Clone(),0)
    for ($i=44; $i -lt $silent.Length; $i++) { if ($silent[$i] -ne 0) { throw 'Zero percent is not silent.' } }
    Write-Output 'Windows device enumeration and preferences: all checks passed (no sound)'
} finally { $env:ROBOTSPEAK_CONFIG = $originalConfig }
