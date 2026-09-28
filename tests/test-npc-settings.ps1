<#
  test-npc-settings.ps1

  The NPCs come back: no "default" key inside npcSettings.

  WHAT WAS WRONG. Deploy-Gamemode.ps1 wrote the -Npcs choice as
  npcSettings = { "default": { spawnInInterior, spawnInExterior } }.
  ScampServer.cpp reads the flags from there and then ALSO keeps "default" in
  the per-plugin map, and WorldState::IsNpcAllowed refuses every NPC as soon
  as a key in that map is not a loaded plugin file. So every -Npcs setting
  that was not "off" spawned nobody. Patrick, 28 September: "NPCs are
  actually not working right now for some reason and they should be".
  Measured with the server binary over the Skyrim.esm and Update.esm form
  range: {} loads 6015 actors, a "default" key loads 0.

  WHAT THIS PROVES.
    1. Deploy-Gamemode.ps1's settings section, lifted by text and run against
       a scratch build for each -Npcs value, writes no "default" key.
    2. -Npcs all writes {}, -Npcs interior writes one entry per plugin in the
       load order, named exactly as the load order spells the file, inside
       only, and -Npcs off turns npcEnabled off.
    3. A "default" key a build already carries does not survive a deploy.
    4. When this machine has the server binary and the game's masters, the
       written npcSettings is handed to the engine itself: under all the
       Whiterun cow (outdoors) loads, under interior it does not and an
       indoor actor does. That part says SKIP where either is missing.

  Nothing here reaches the VPS. Read only apart from its own temp folder.
#>
[CmdletBinding()]
param([string]$ToolsDir)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, what they test is in tools\.
$Here = Join-Path (Split-Path -Parent $Here) 'tools'
if (-not $ToolsDir) { $ToolsDir = $Here }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-npcs-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$utf8 = New-Object Text.UTF8Encoding($false)

function Done {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail) { exit 1 }
    exit 0
}

$helper = Join-Path $ToolsDir '..\scripts\deploy\MaxOnline.ps1'
Yes 'MaxOnline.ps1 is there for the settings section' (Test-Path -LiteralPath $helper)
if (-not (Test-Path -LiteralPath $helper)) { Done }
. $helper

# ---- 1 to 3. Deploy-Gamemode.ps1's settings section --------------------------
$dg = Get-Content -LiteralPath (Join-Path $ToolsDir '..\scripts\deploy\Deploy-Gamemode.ps1') -Raw
$from = $dg.IndexOf('# ---- rewrite server-settings.json')
$to = -1
if ($from -ge 0) { $to = $dg.IndexOf('[IO.File]::WriteAllText($settingsPath', $from) }
if ($to -ge 0) { $to = $dg.IndexOf("`n", $to) }
Yes 'the settings section is in Deploy-Gamemode.ps1' ($from -ge 0 -and $to -gt $from)
if (-not ($from -ge 0 -and $to -gt $from)) { Done }
$section = $dg.Substring($from, $to - $from)

# The plugin names are the real kind: spaces, an apostrophe, an .esm and .esp.
$plugins = @('Skyrim.esm', 'Update.esm', 'Dawnguard.esm', 'HearthFires.esm', 'Dragonborn.esm',
             "JK's Whiterun's Outskirts.esp", 'Skyrim Unbound.esp')

function Invoke-Section([string]$dist, [string]$npcs) {
    $Dist = $dist
    $paths = @($plugins | ForEach-Object { 'C:/Data/' + $_ })
    $ServerName = 'Thornswood'; $Port = 7777; $VoicePort = 7778; $Npcs = $npcs
    $HitsOnPeople = 1.0; $HitsOnNpcs = 2.0; $Devs = @(); $Playtesters = @()
    $maxOnline = [pscustomobject]@{ Value = 0; From = 'x'; Why = 'none' }
    . ([scriptblock]::Create($section)) 6>$null
}
# The build folder as a deploy from before this fix left it, default key and all.
function Seed-Built([string]$dist) {
    New-Item -ItemType Directory -Force -Path $dist | Out-Null
    [IO.File]::WriteAllText((Join-Path $dist 'server-settings.json'),
        ('{"port":7777,"name":"Thornswood","maxPlayers":25,"keepMe":"yes","loadOrder":[],' +
         '"npcEnabled":true,"npcSettings":{"default":{"spawnInInterior":true,"spawnInExterior":true}}}'), $utf8)
}
function Read-Built([string]$dist) {
    Get-Content -LiteralPath (Join-Path $dist 'server-settings.json') -Raw | ConvertFrom-Json
}
function Keys($o) { if ($null -eq $o) { return @() } return @($o.PSObject.Properties | ForEach-Object { $_.Name }) }

$written = @{}
foreach ($npcs in 'all', 'interior', 'off') {
    $dist = Join-Path $tmp ('dist-' + $npcs)
    Seed-Built $dist
    $ok = $true
    try { Invoke-Section $dist $npcs } catch { $ok = $false; Write-Host ("      " + $_.Exception.Message) }
    Yes ("-Npcs {0}: the lifted section runs against a scratch build" -f $npcs) $ok
    $w = Read-Built $dist
    $written[$npcs] = $w
    $keys = Keys $w.npcSettings
    Yes ("-Npcs {0}: npcSettings is written" -f $npcs) ($null -ne $w.npcSettings)
    Yes ("-Npcs {0}: npcSettings has no default key, which refuses every NPC" -f $npcs) ($keys -notcontains 'default')
    Yes ("-Npcs {0}: every key names a plugin in the load order" -f $npcs) (@($keys | Where-Object { $plugins -notcontains $_ }).Count -eq 0)
    Yes ("-Npcs {0}: a key nobody sets there survives" -f $npcs) ($w.keepMe -eq 'yes')
}

Yes '-Npcs all: npcEnabled is on' ($written['all'].npcEnabled -eq $true)
Yes '-Npcs all: npcSettings is {}, every NPC everywhere' ((Keys $written['all'].npcSettings).Count -eq 0)

$in = $written['interior']
$inKeys = Keys $in.npcSettings
Yes '-Npcs interior: npcEnabled is on' ($in.npcEnabled -eq $true)
Yes ('-Npcs interior: one entry per plugin, {0} of them' -f $plugins.Count) ($inKeys.Count -eq $plugins.Count)
Yes '-Npcs interior: the names are spelt as the load order spells them' (
    @($plugins | Where-Object { $inKeys -cnotcontains $_ }).Count -eq 0)
$flags = @($inKeys | ForEach-Object { $in.npcSettings.$_ })
Yes '-Npcs interior: every entry is inside only' (
    @($flags | Where-Object { $_.spawnInInterior -ne $true -or $_.spawnInExterior -ne $false }).Count -eq 0)

Yes '-Npcs off: npcEnabled is off' ($written['off'].npcEnabled -eq $false)

# ---- 4. the engine itself, where this machine has it --------------------------
$serverDist = $env:THORNSWOOD_SERVER_DIST
if (-not $serverDist) {
    try { $serverDist = [string](& (Join-Path $ToolsDir '..\scripts\release\Where.ps1') ServerDist 6>$null) } catch { $serverDist = '' }
}
$gameData = $env:THORNSWOOD_GAME_DATA
if (-not $gameData) { $gameData = 'C:\Thornswood\Game\Data' }
$native = if ($serverDist) { Join-Path $serverDist 'scam_native.node' } else { '' }
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not ($native -and (Test-Path -LiteralPath $native) -and (Test-Path -LiteralPath (Join-Path $gameData 'Skyrim.esm')) -and $node)) {
    Write-Host 'SKIP  the engine check: needs scam_native.node (THORNSWOOD_SERVER_DIST), Skyrim.esm (THORNSWOOD_GAME_DATA) and node'
    Done
}

# 0x10ebaf is the Whiterun cow the engine's own NpcExists test uses (outdoors,
# no crime faction, not essential). 0xea7 is an indoor actor in Skyrim.esm.
$probe = @'
const addon = require(process.argv[2]);
const s = JSON.parse(require('fs').readFileSync(process.argv[3], 'utf8'));
const srv = new addon.ScampServer(JSON.stringify(s));
const out = {};
for (const [k, id] of [['cow', 0x10ebaf], ['indoors', 0xea7]]) {
  try { srv.get(id, 'pos'); out[k] = true; } catch (e) { out[k] = false; }
}
console.log('PROBE ' + JSON.stringify(out));
process.exit(0);
'@
$probeFile = Join-Path $tmp 'probe.js'
[IO.File]::WriteAllText($probeFile, $probe, $utf8)
$masters = @('Skyrim.esm', 'Update.esm', 'Dawnguard.esm', 'HearthFires.esm', 'Dragonborn.esm')

function Invoke-Engine($npcSettings, [bool]$enabled, [switch]$AsGiven) {
    # The written npcSettings with the entries for the two plugins not loaded
    # here taken out, because the engine needs every key to be a plugin it
    # actually loaded. Any other key goes over as written, so a default key
    # reaches the engine. -AsGiven hands it over untouched.
    $ns = [ordered]@{}
    foreach ($k in (Keys $npcSettings)) {
        if ($AsGiven -or $masters -contains $k -or $plugins -notcontains $k) { $ns[$k] = $npcSettings.$k }
    }
    $s = [ordered]@{
        port = 7991; maxPlayers = 2; offlineMode = $true; name = 'npc-settings-test'
        dataDir = $gameData; loadOrder = @($masters | ForEach-Object { Join-Path $gameData $_ })
        npcEnabled = $enabled; npcAllowEssential = $false; npcAllowCrimeFaction = $false
        npcSettings = [pscustomobject]$ns; logLevel = 'error'
    }
    $f = Join-Path $tmp ('engine-' + [Guid]::NewGuid().ToString('N').Substring(0, 8) + '.json')
    [IO.File]::WriteAllText($f, ([pscustomobject]$s | ConvertTo-Json -Depth 10), $utf8)
    $ErrorActionPreference = 'Continue'
    $line = @(& $node.Source $probeFile $native $f 2>&1 | ForEach-Object { [string]$_ } | Where-Object { $_.StartsWith('PROBE ') })
    if (-not $line.Count) { return $null }
    return ($line[-1].Substring(6) | ConvertFrom-Json)
}

$r = Invoke-Engine $written['all'].npcSettings $true
Yes 'engine, -Npcs all: the Whiterun cow is in the world' ($null -ne $r -and $r.cow -eq $true)
Yes 'engine, -Npcs all: so is the indoor actor' ($null -ne $r -and $r.indoors -eq $true)
$r = Invoke-Engine $written['interior'].npcSettings $true
Yes 'engine, -Npcs interior: the cow outdoors is not' ($null -ne $r -and $r.cow -eq $false)
Yes 'engine, -Npcs interior: the indoor actor is' ($null -ne $r -and $r.indoors -eq $true)
# The shape this replaces, to show the engine still refuses it: that is why
# the key must never be written.
$r = Invoke-Engine ([pscustomobject]@{ default = [pscustomobject]@{ spawnInInterior = $true; spawnInExterior = $true } }) $true -AsGiven
Yes 'engine: a default key still refuses the cow, the reason it is never written' ($null -ne $r -and $r.cow -eq $false)

Done
