<#
  Deploy-Gamemode.ps1

  Puts gamemode.js into the built server and writes a server load order that
  actually lines up with the client's.

  The load order is the whole game here, so it is worth stating plainly.

  SkyMP turns a form id into a plugin plus a local id with plain arithmetic,
  fileIdx * 0x01000000 + shortFormId, where fileIdx is the position in
  server-settings.json. The client does NOT translate: remoteIdToLocalId passes
  anything below 0xff000000 straight to Game.getFormEx, and the client never
  calls Game.getFormFromFile, the one API that resolves by plugin name and
  handles light plugins. So the server's indices must equal the game's.

  Skyrim gives an ESL-flagged plugin no normal index at all, so listing one
  server-side shifts everything after it. Leaving them out is therefore exact,
  not a compromise, and it matches what the client already believes: its own
  loadOrderVerificationService enumerates with Game.getModCount, which skips
  light plugins by construction.

  A plugin that masters to a dropped one cannot load either, so those are pruned
  too, repeatedly until the list is closed. On this setup that costs exactly one
  plugin, MCMHelper.esp, which is menu glue the server has no use for.

  A plugin is light if its extension is .esl or its TES4 header carries flag
  0x200. The second case is the one that surprises people: TheNewGentleman.esp
  was a plain .esp carrying both the ESM and ESL flags.

  -FullLoadOrder disables all of this and lists everything. The server will
  start, and form ids will be wrong for every plugin after the first ESL. It is
  here for narrowing down a load failure, not for playing on.

#>
param(
    [string]$Gamemode,
    [string]$Dist     = 'C:\Thornswood-Dev\skymp\build\dist\server',
    [string]$Data     = 'C:\Thornswood\Game\Data',
    [string]$Plugins  = 'C:\Thornswood\Profile\Default\plugins.txt',
    [string]$ServerName = 'Thornswood',
    [int]   $Port     = 7777,
    [switch]$MinimalLoadOrder,   # masters plus Thornswood-Content.esp only
    [switch]$FullLoadOrder,      # list everything, indices be damned. for bisecting
    [switch]$Vortex,             # read the Steam game and the active Vortex profile
    [switch]$NewOrder,           # take the plugin list's order as it is, for a world being wiped
    <#
      The NPCs, and how many of them the server simulates.

      Patrick, 21 September, after playing it: "To many fucking NPCs spawning
      man all at once group together, on top of players, enimes hit way to hard
      and have to much health or dont die at all".

      npcEnabled true with an empty npcSettings means the server simulates
      EVERY npc in the world, interior and exterior, because both spawn flags
      default to true in ScampServer. That is one shared world, which is the
      thing SkyMP is for, and it is also every bandit and every chicken in
      Skyrim being kept alive by one process.

        -Npcs off        none at all. The cleanest way to test a trade.
        -Npcs interior   only inside, so towns are alive and the roads are not.
        -Npcs all        the default, everything.

      Off is not a downgrade to the Skyrim Together behaviour: that was
      everybody getting their own private copy. Off is nobody getting one.
    #>
    [ValidateSet('all', 'interior', 'off')][string]$Npcs = 'all',

    <#
      What a blow is worth, in each direction.

      Patrick, 21 September, after playing it: "enimes hit way to hard and have
      to much health or dont die at all". Both halves are one class in the
      engine, DamageMultFormula, which is always in the chain.

      -HitsOnPeople    an NPC hitting a person. The engine's own default is 2,
                       applied when this file says nothing, which is what it
                       has always said. Nobody chose that doubling. 1 is the
                       blow the weapon is actually worth.
      -HitsOnNpcs      a person hitting an NPC. This direction was never
                       multiplied at all, and the formula under it reads the
                       weapon's base damage, the target's armour and the power,
                       block and sneak flags, and NOTHING about the person
                       swinging: no skill, no perks, no attackDamageMult. So a
                       giant keeps its full vanilla health and takes the number
                       printed on the sword, over and over. 2 is a starting
                       point and it is one number to turn.

      Both are read separately by the fork, so setting one does not discard the
      other. They are in server-settings.json, so they reach the dev server
      through Publish-Server -Channel dev and the live one through
      Deploy-Server, and neither needs a rebuild once the fork is built.
    #>
    [double]$HitsOnPeople = 1.0,
    [double]$HitsOnNpcs   = 2.0
)

# ---------------------------------------------------------------- -Vortex ---
#
# Where the build actually is.
#
# Two answers, and the wrong one is silent: it produces a load order that
# looks fine and does not match what anybody is running. The old build under
# C:\Thornswood\Game is still on this machine and still readable, so a default
# that points at it keeps working long after it stopped being the truth.
#
# -Vortex reads the live one instead: Skyrim where Steam put it, with the mods
# Vortex has deployed into it, and the plugin list of whichever Vortex profile
# is active. That is what is loaded when the game starts, so it is what the
# server should be built from.
function Get-SkyrimPath {
    $roots = @()
    foreach ($k in 'HKCU:\Software\Valve\Steam','HKCU:\Software\Wow6432Node\Valve\Steam') {
        try { $p = (Get-ItemProperty -Path $k -Name SteamPath -EA Stop).SteamPath } catch { continue }
        if ($p) { $roots += ($p -replace '/','\') }
    }
    try { $p = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Wow6432Node\Valve\Steam' -Name InstallPath -EA Stop).InstallPath } catch { $p = $null }
    if ($p) { $roots += $p }

    # Games are not always in Steam's own folder. Every extra library is listed
    # in this file, one "path" line each, with the separator escaped.
    foreach ($r in @($roots)) {
        $vdf = Join-Path $r 'config\libraryfolders.vdf'
        if (-not (Test-Path -LiteralPath $vdf)) { continue }
        foreach ($line in (Get-Content -LiteralPath $vdf)) {
            $m = [regex]::Match($line, '^\s*"path"\s+"(.+)"\s*$')
            if ($m.Success) { $roots += ($m.Groups[1].Value -replace '\\\\','\') }
        }
    }

    foreach ($r in ($roots | Select-Object -Unique)) {
        $g = Join-Path $r 'steamapps\common\Skyrim Special Edition'
        if (Test-Path -LiteralPath (Join-Path $g 'SkyrimSE.exe')) { return $g }
    }
    return ''
}

if ($Vortex) {
    $sk = Get-SkyrimPath
    if (-not $sk) { throw "Could not find Skyrim Special Edition through Steam, so -Vortex has nothing to read." }
    $Data    = Join-Path $sk 'Data'
    $Plugins = Join-Path $env:LOCALAPPDATA 'Skyrim Special Edition\Plugins.txt'
    if (-not (Test-Path -LiteralPath $Plugins)) { throw "No plugin list at $Plugins. Start Vortex, activate the Thornswood profile and deploy, then run this again." }
    Write-Host "  -Vortex" -ForegroundColor Cyan
    Write-Host "    data     $Data" -ForegroundColor DarkGray
    Write-Host "    plugins  $Plugins" -ForegroundColor DarkGray
}


# Resolved from where this script is rather than from a fixed path under
# Downloads. The repo folder gets renamed and moved, and a default that names it
# turns every one of these into a broken command the first time it does.
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $Gamemode) { $Gamemode = Join-Path $Here 'gamemode.js' }

if (-not (Test-Path -LiteralPath $Gamemode)) { throw "not found: $Gamemode" }
if (-not (Test-Path -LiteralPath $Dist))     { throw "server dist not found: $Dist" }

Copy-Item -LiteralPath $Gamemode -Destination (Join-Path $Dist 'gamemode.js') -Force
$kb = [math]::Round((Get-Item (Join-Path $Dist 'gamemode.js')).Length / 1KB)
Write-Host "gamemode.js -> $Dist  ($kb KB)" -ForegroundColor Cyan

function Read-PluginHeader([string]$path) {
    $fs = [IO.File]::OpenRead($path)
    $len = [Math]::Min(16384, $fs.Length)
    $b = New-Object byte[] $len
    [void]$fs.Read($b, 0, $len)
    $fs.Close()

    $light = ($path -match '\.esl$')
    if ($len -ge 12 -and [Text.Encoding]::ASCII.GetString($b,0,4) -eq 'TES4') {
        if (([BitConverter]::ToUInt32($b,8) -band 0x200) -ne 0) { $light = $true }
    }

    $masters = @()
    for ($i = 0; $i -lt $b.Length - 6; $i++) {
        if ($b[$i] -eq 0x4D -and $b[$i+1] -eq 0x41 -and $b[$i+2] -eq 0x53 -and $b[$i+3] -eq 0x54) {
            $sz = [BitConverter]::ToUInt16($b, $i+4)
            if ($sz -gt 0 -and $sz -lt 260 -and ($i+6+$sz) -le $b.Length) {
                $str = [Text.Encoding]::GetEncoding(1252).GetString($b, $i+6, $sz).TrimEnd([char]0)
                if ($str -match '\.es[pml]$') { $masters += $str }
            }
        }
    }
    [pscustomobject]@{ Light = $light; Masters = ($masters | Select-Object -Unique) }
}

# ---- build the load order --------------------------------------------------
$wanted = if ($MinimalLoadOrder) {
    'Skyrim.esm','Update.esm','Dawnguard.esm','HearthFires.esm','Dragonborn.esm','Thornswood-Content.esp'
} else {
    if (-not (Test-Path -LiteralPath $Plugins)) { throw "not found: $Plugins" }
    $fromFile = Get-Content -LiteralPath $Plugins |
                Where-Object { $_ -match '^\*' } |
                ForEach-Object { $_.TrimStart('*').Trim() }
    # plugins.txt omits the always-on masters; the server needs them spelled out
    $implicit = 'Skyrim.esm','Update.esm','Dawnguard.esm','HearthFires.esm','Dragonborn.esm'
    @($implicit | Where-Object { $fromFile -notcontains $_ }) + $fromFile
}

$info = @{}; $missing = @()
foreach ($p in $wanted) {
    $full = Join-Path $Data $p
    if (Test-Path -LiteralPath $full) { $info[$p] = Read-PluginHeader $full } else { $missing += $p }
}

$drop = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$pruned = @{}
if (-not $FullLoadOrder) {
    foreach ($p in $wanted) { if ($info[$p] -and $info[$p].Light) { [void]$drop.Add($p) } }
    $lightCount = $drop.Count
    do {
        $again = $false
        foreach ($p in $wanted) {
            if (-not $info[$p] -or $drop.Contains($p)) { continue }
            foreach ($m in $info[$p].Masters) {
                if ($drop.Contains($m)) { [void]$drop.Add($p); $pruned[$p] = $m; $again = $true; break }
            }
        }
    } while ($again)
} else { $lightCount = 0 }

$keep  = @($wanted | Where-Object { $info[$_] -and -not $drop.Contains($_) })

# ---- the order the server already runs stays ------------------------------
#
# The world database keys every changed form on fileIdx * 0x01000000 plus the
# local id, and fileIdx is the position in this list. Move a plugin and every
# saved chest, door and body from every plugin after it points at the wrong
# record. So the order is not this machine's plugin list's to decide once a
# world exists: the list the server already has is kept as it is, a plugin
# that is new goes on the end, and a plugin that is gone is said out loud,
# because everything after it moves up one and that is the one move nothing
# here can undo. The client follows: the launcher's LoadOrder.cs puts every
# machine's list into the server's order, and Publish-Update.ps1 ships the
# reference list that way. Until 20 September this took the order from the
# plugin list every time, and LOOT re-sorting that list at 13:05 would have
# re-keyed the whole world on the next deploy.
#
# -NewOrder takes the list's order as it is. That is for a world that is
# being wiped, and for nothing else.
$priorPath = Join-Path $Dist 'server-settings.json'
$prior = @()
if (-not $NewOrder -and -not $FullLoadOrder -and -not $MinimalLoadOrder -and (Test-Path -LiteralPath $priorPath)) {
    try {
        $prior = @((Get-Content -LiteralPath $priorPath -Raw | ConvertFrom-Json).loadOrder |
                   ForEach-Object { [IO.Path]::GetFileName(([string]$_).Replace('/', '\')) } |
                   Where-Object { $_ })
    } catch { $prior = @() }
}
if ($prior.Count) {
    $keepBy = @{}
    foreach ($k in $keep) { $keepBy[$k.ToLowerInvariant()] = $k }
    $ordered = @(); $placed = @{}
    foreach ($p in $prior) {
        $lk = $p.ToLowerInvariant()
        if ($keepBy.ContainsKey($lk) -and -not $placed.ContainsKey($lk)) { $ordered += $keepBy[$lk]; $placed[$lk] = $true }
    }
    $added   = @($keep  | Where-Object { -not $placed.ContainsKey($_.ToLowerInvariant()) })
    $removed = @($prior | Where-Object { -not $keepBy.ContainsKey($_.ToLowerInvariant()) })
    $keep = @($ordered + $added)
    Write-Host ("  order kept from the server's own list: {0} in place, {1} new on the end, {2} gone" -f $ordered.Count, $added.Count, $removed.Count) -ForegroundColor Cyan
    foreach ($a in $added)   { Write-Host "    + $a" -ForegroundColor Green }
    foreach ($r in $removed) { Write-Host "    - $r   every plugin after it moves up one; the world's saved forms from those plugins are re-keyed" -ForegroundColor Yellow }
} elseif ($NewOrder) {
    Write-Host "  -NewOrder: the plugin list's order is taken as it is" -ForegroundColor Yellow
}

$paths = @($keep | ForEach-Object { (Join-Path $Data $_) -replace '\\', '/' })

# ---- rewrite server-settings.json -----------------------------------------
$settingsPath = Join-Path $Dist 'server-settings.json'
$s = if (Test-Path -LiteralPath $settingsPath) {
        Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
     } else { [pscustomobject]@{} }

$s | Add-Member -NotePropertyName loadOrder   -NotePropertyValue $paths      -Force
$s | Add-Member -NotePropertyName name        -NotePropertyValue $ServerName -Force
$s | Add-Member -NotePropertyName port        -NotePropertyValue $Port       -Force
$s | Add-Member -NotePropertyName offlineMode -NotePropertyValue $true       -Force
$s | Add-Member -NotePropertyName dataDir     -NotePropertyValue 'data'      -Force
# Server-simulated NPCs. Off is SkyMP's default and it is the Skyrim Together
# behaviour we are leaving behind: everyone gets their own private copy of every
# bandit. On means one shared world. npcSettings stays empty, which is "no
# per-NPC overrides", not "no NPCs".
$s | Add-Member -NotePropertyName npcEnabled  -NotePropertyValue ($Npcs -ne 'off') -Force

# WHAT YOU ARE WEARING STAYS ON. Measured 20 September, after Patrick rejoined
# an existing character and arrived with nothing on.
#
# The server refuses an equipment update outright in two places, and on a
# modded load order both of them fire constantly:
#
#   equipmentSlotCheckEnabled   the gear strip. ActionListener::OnUpdateEquipment
#                               ORs together the biped slot flags of everything
#                               worn and refuses the whole update the moment two
#                               items share one bit, then sends an UnequipItem
#                               for every item involved. Vanilla Skyrim already
#                               uses slots 44 to 47, and every cloak, scarf and
#                               backpack mod reaches for the same handful of
#                               free-looking ones. It is an anti-cheat against
#                               wearing five chest pieces and it costs far more
#                               than it earns here.
#   equipmentSpellCheckEnabled  a spell the server did not itself grant is
#                               refused and a RemoveSpell is sent back. Every
#                               spell learned from a tome in the world is one
#                               the server never saw, so it comes straight back
#                               off the hand.
#
# Both were made switchable in our own fork of the engine and both still default
# to true in WorldState.h:277-278, because the engine change was made and the
# last step, writing the setting, never was. So the switches have been there and
# have never once been thrown. This throws them.
#
# What is worn is saved by the engine, not by the gamemode: MpChangeForm carries
# an equipment field and MpChangeForms.cpp writes it to the world save. So
# equipment already persists across a session, on the one condition that the
# update was accepted in the first place. These two lines are that condition.
# The gamemode cannot do this job instead: EquipmentBinding has a Get and no
# Set, so the server can read what somebody is wearing and cannot write it.
<#
  NOTHING IN THE WORLD COMES BACK, EXCEPT THE THINGS THAT GROW.

  Patrick, 21 September: "even the stuff in the containers that start in them
  should be once only and same wih on the ground so it doesnt respawn and isnt
  infinites (Except for the thigs that hang like the meats, garlic, elves ears,
  etc.)".

  The gamemode already refuses to hand over a weapon, a piece of armour, a tool
  or a coin that the world placed, and empties a container of those once. What it
  cannot do from inside is stop the ENGINE putting everything back an hour later.
  MpObjectReference::GetRelootTime returns an hour for CONT, an hour for anything
  espm::utils::IsItem calls an item, and an hour for FLOR and TREE. So a chest
  emptied of its bread refills with bread at teatime, for ever, and that is an
  infinite supply of everything the gamemode does NOT take out.

  RequestReloot returns early when the base type is in forbiddenReloot, so this
  is the switch and there is no other.

  WHICH TYPES, AND THE MEASUREMENT THAT MADE THE EXCEPTION SAFE. Every
  harvestable this server knows about was looked up by record type on
  21 September, all 146 of them across the four tables in tools\harvests.json:

      the hanging game     7 bases, every one FLOR
      plants and harvests  109 bases, 69 FLOR and 40 TREE
      crops                15 bases, 11 TREE and 4 FLOR
      fish                 15 bases, every one FLOR

  Not one of them is anything else. So FLOR and TREE are exactly the things
  Patrick wants to keep coming back, and everything he wants to stop is a
  different type. The exception is not a list of forms anybody has to maintain:
  it is the two types left out of the line below.

  The item types are the ones IsItem covers, which is what the engine itself
  reloots on an hour, written out here rather than inferred so that a reader can
  see what is in the list without reading espm.
#>
$s | Add-Member -NotePropertyName forbiddenReloot -NotePropertyValue @(
    'CONT',
    'WEAP', 'ARMO', 'AMMO', 'MISC', 'ALCH', 'INGR', 'BOOK', 'SLGM', 'SCRL',
    'LIGH', 'KEYM', 'NOTE'
) -Force
$s | Add-Member -NotePropertyName equipmentSlotCheckEnabled  -NotePropertyValue $false -Force
$s | Add-Member -NotePropertyName equipmentSpellCheckEnabled -NotePropertyValue $false -Force
# The third one, and the one the live log actually shows firing. Measured on
# 20 September: 24 refusals over two days, every one of them the same item,
# 0x13790 IronWarAxe, on every character seconds after spawning. Skyrim
# Unbound hands out starting gear inside the client's own game and the server
# never sees it happen, so the first equipment update a new character sends
# names an item the server has no record of. Upstream throws the WHOLE update
# away for that, so the equipment record stays empty all session, and on the
# next spawn the client empties the pack and refills it from that empty record.
# Off, the unknown item is dropped and the rest of the update is kept.
$s | Add-Member -NotePropertyName equipmentInventoryCheckEnabled -NotePropertyValue $false -Force
<#
  npcSettings.default is where the two spawn flags actually live.

  ScampServer reads them from INSIDE npcSettings (it used to read them from the
  root, which is a Thornswood fix already in the fork). An empty object leaves
  both true, which is every NPC everywhere.
#>
$npcDefault = [pscustomobject]@{
    spawnInInterior = ($Npcs -ne 'off')
    spawnInExterior = ($Npcs -eq 'all')
}
$s | Add-Member -NotePropertyName npcSettings -NotePropertyValue ([pscustomobject]@{
    default = $npcDefault
}) -Force
Write-Host "  NPCs: $Npcs (interior $($npcDefault.spawnInInterior), exterior $($npcDefault.spawnInExterior))" -ForegroundColor DarkGray

<#
  What a blow is worth. See -HitsOnPeople and -HitsOnNpcs above.

  This key was absent from every settings file this repo has ever written, so
  the server logged "Unable to get multiplier from config" at startup and
  doubled every blow landed on a person, and nobody knew. Writing it is the
  whole of the fix for the first half of Patrick's sentence; the second half
  needs the fork built, because playerMultiplier is ours.
#>
$s | Add-Member -NotePropertyName damageMultFormulaSettings -NotePropertyValue ([pscustomobject]@{
    multiplier       = $HitsOnPeople
    playerMultiplier = $HitsOnNpcs
}) -Force
Write-Host ("  damage: an NPC hitting a person x{0}, a person hitting an NPC x{1}" -f $HitsOnPeople, $HitsOnNpcs) -ForegroundColor DarkGray
# Where a brand new character first appears, which is also where the gamemode
# runs character creation. Skyrim Unbound's own creation room is the right
# answer on this setup: a new game already puts everybody there, so the client
# and the server agree from the first frame instead of arguing about it. The
# Whiterun gate this used to point at was the published SkyMP spawn, and it is
# still the fallback, but it is outdoors and half a world away from where the
# client actually starts.
#
# The form id is computed rather than written down. SkyMP resolves
# fileIdx * 0x01000000 + shortFormId and fileIdx is this array's own index, so a
# literal would rot the moment the load order moved.
$hallPlugin = 'Skyrim Unbound.esp'
$hallLocal  = 0x19BAD4                      # SkyrimUnboundRoom01
$hallIdx = -1
for ($i = 0; $i -lt $paths.Count; $i++) {
    if ([IO.Path]::GetFileName($paths[$i]) -ieq $hallPlugin) { $hallIdx = $i; break }
}
if ($hallIdx -ge 0) {
    $hallId = ($hallIdx * 0x01000000) + $hallLocal
    $start = [pscustomobject]@{
        pos = @(3755.7, -495.7, -207.7); worldOrCell = ('0x{0:X8}' -f $hallId); angleZ = 180
    }
    $startNote = "the Unbound creation room, $hallPlugin at index $hallIdx, form 0x{0:X8}" -f $hallId
} else {
    $start = [pscustomobject]@{
        pos = @(22659, -8697, -3594); worldOrCell = '0x1a26f'; angleZ = 268
    }
    $startNote = "Whiterun's main gate; $hallPlugin is not in the load order"
}
$s | Add-Member -NotePropertyName startPoints -NotePropertyValue @($start) -Force

# Set-Content -Encoding UTF8 writes a byte order mark under Windows PowerShell
# 5.1 and does not under PowerShell 7, so the same line produces a different
# file depending on which one happens to run it. A BOM is not JSON: node stops
# on the first character with "Unexpected token", the server never starts, and
# nothing about the message points at the file that was written three steps
# earlier. WriteAllText with an explicit encoding is the same in both.
[IO.File]::WriteAllText($settingsPath, ($s | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false)))

Write-Host ("server-settings.json  {0} plugins, name '{1}', port {2}, NPCs server-side" -f $paths.Count, $ServerName, $Port) -ForegroundColor Cyan
Write-Host '  the gear strip and the spell strip are both off, so what you wear and what you have learned stay on' -ForegroundColor DarkGray
Write-Host ("  new characters start at {0}" -f $startNote) -ForegroundColor DarkGray

if ($FullLoadOrder) {
    Write-Host '  -FullLoadOrder: indices will NOT match the game. Diagnostic use only.' -ForegroundColor Yellow
} elseif ($lightCount) {
    Write-Host ("  {0} light plugin(s) left out so the indices match the game exactly" -f $lightCount) -ForegroundColor DarkGray
    foreach ($k in ($pruned.Keys | Sort-Object)) {
        Write-Host ("      also {0}, which masters to {1}" -f $k, $pruned[$k]) -ForegroundColor DarkGray
    }
}
$tw = ($Data -replace '\\','/') + '/Thornswood-Content.esp'
$i = [Array]::IndexOf($paths, $tw)
if ($i -lt 0) {
    Write-Host '  WARNING: Thornswood-Content.esp is not in the load order. The stations will not resolve.' -ForegroundColor Red
} else {
    Write-Host ("  Thornswood-Content.esp at index {0} (0x{1:X2})" -f $i, $i) -ForegroundColor DarkGray
}

Write-Host ''
