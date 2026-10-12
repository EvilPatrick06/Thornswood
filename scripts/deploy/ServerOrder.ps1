<#
  ServerOrder.ps1

  The server's load order once the engine loads light plugins (#1715), and
  the full index a form id is computed from. Dot-sourced by
  Deploy-Gamemode.ps1, Publish-Server.ps1 and Check-Chargen.ps1, and by
  tests\test-light-order.ps1, which holds it to the measured lists.

  WHY. A light plugin's forms have ids 0xFE000000 | (light index << 12) |
  local id, the light index being the plugin's place among the light plugins
  the game loads. Until the engine loaded them the server left every light
  plugin out and the light order was whatever each machine's Vortex and LOOT
  gave it. Measured on 5 Oct over the 133 session logs on the VPS since
  24 Sep: ten different light orders, KhisartinBeards.esp anywhere from light
  index 0x1E to 0x29, 0x29 in the main sessions of 5 Oct and 0x27 in the
  last dev one. The server stores what the client sends, so a beard stored
  on dev on 25 Sep under light index 0x20 (0xFE020827) names another plugin
  under the dev order of 5 Oct. docs\LIGHT-ORDER-DRIFT.md has the
  measurement, and scripts\oneoff\Move-LightFormIds.ps1 moves such ids once.

  THE RULE IS THE ONE THE FULL ORDER ALREADY HAS. The world keys stored forms
  on their index, so the order the server already runs is kept: its full
  plugins in their order and its light plugins in theirs, a plugin that is
  new on the end of its own kind, and one that is gone said out loud, because
  every plugin of its kind after it moves up one. The first time light
  plugins are listed there is no light order to keep, and it is taken from
  the plugin list the way the game takes it: Skyrim.ccc's entries that are in
  Data straight after the five masters (_ResourcePack.esl is light index 0),
  then the list with master flagged plugins first.

  THE SETTING. loadOrder lists every plugin the game loads, full and light,
  in the game's own order, so a light patch overrides the same records on
  the server as in the game. Lightness is not written down: the engine reads
  it from each plugin's header (0x200, or an .esl name), the same rule as
  Test-LoadOrderLight. A full plugin's index is its place among the full
  ones, so code that turns a plugin into a form id counts full plugins only
  (Get-ThornswoodFullIndex), never the position in the list.

  ONLY WITH AN ENGINE THAT LOADS THEM. An engine that does not gives every
  listed plugin a full index, and a light plugin in its list would move every
  full plugin after it. records\server-build.json says which engine a build
  is (lightPlugins, written by New-ServerBuildRecord.ps1 from the fork's
  source), and Deploy-Gamemode lists light plugins only when it says so.

  Keep it ASCII and Windows PowerShell 5.1.
#>

. (Join-Path $PSScriptRoot '..\release\Read-JsonFile.ps1')   # ConvertFrom-ThornswoodJson: a bad JSON file named

$script:ThornswoodBaseMasters = 'Skyrim.esm', 'Update.esm', 'Dawnguard.esm', 'HearthFires.esm', 'Dragonborn.esm'

# Whether the engine a server build record describes loads light plugins.
# False for a record that does not say, which is every record before #1715.
# A record that is there and does not read stops the caller: guessing either
# way would write a load order for an engine nobody knows.
function Test-ThornswoodEngineLoadsLight([string]$Record) {
    if (-not $Record) { throw 'no server build record was named, so it is not known whether the engine loads light plugins' }
    if (-not (Test-Path -LiteralPath $Record)) { throw "there is no server build record at $Record, so it is not known whether the engine loads light plugins" }
    try { $r = ConvertFrom-ThornswoodJson ([IO.File]::ReadAllText($Record)) $Record }
    catch { throw "the server build record at $Record does not read ($($_.Exception.Message)), so it is not known whether the engine loads light plugins" }
    return ($r.PSObject.Properties.Name -contains 'lightPlugins' -and $r.lightPlugins -eq $true)
}

# The game loads an .esl as a master whatever its header says, the same as an
# .esm. Read-PluginHeader in Deploy-Gamemode.ps1 reads the extension .esm and
# the 0x1 flag; this adds the .esl half for the light plugins.
function Test-ThornswoodLoadsAsMaster([string]$Name, $Header) {
    if ($Name -match '\.esl$') { return $true }
    return [bool]($null -ne $Header -and $Header.Master)
}

# Whether the plugin file at $Path is light, by the rule the engine and the
# game use: an .esl name, or 0x200 in the TES4 record's flags. A file that is
# not there, or not a plugin, cannot be told and stops the caller.
function Test-ThornswoodPluginLight([string]$Path) {
    if ($Path -match '\.esl$') { return $true }
    if (-not (Test-Path -LiteralPath $Path)) { throw "$Path is not on this machine, so whether it is a light plugin cannot be read" }
    $fs = [IO.File]::OpenRead($Path)
    try {
        $b = New-Object byte[] 12
        $n = $fs.Read($b, 0, 12)
    } finally { $fs.Close() }
    if ($n -lt 12 -or [Text.Encoding]::ASCII.GetString($b, 0, 4) -ne 'TES4') { throw "$Path is not a plugin (no TES4 header), so whether it is light cannot be read" }
    return (([BitConverter]::ToUInt32($b, 8) -band 0x200) -ne 0)
}

# The full index of each plugin in a server-settings.json loadOrder, by the
# engine the record names: with one that loads light plugins they take no
# full index, read from each file's header; otherwise every entry has one.
# Returns a script block for Get-ThornswoodFullIndex, or $null.
function Get-ThornswoodLightTest([string[]]$Paths, [string]$Record) {
    if (-not (Test-ThornswoodEngineLoadsLight $Record)) { return $null }
    $light = @{}
    foreach ($p in @($Paths)) {
        $f = ([string]$p).Replace('/', '\')
        $light[[IO.Path]::GetFileName($f)] = Test-ThornswoodPluginLight $f
    }
    return { param($n) [bool]$light[$n] }.GetNewClosure()
}

# A plugin's index among the full plugins of a load order, the index the
# engine puts in a full form id's top byte, or -1 when it is not there or is
# light. $IsLight takes a name.
function Get-ThornswoodFullIndex([string[]]$Order, [scriptblock]$IsLight, [string]$Name) {
    $n = 0
    foreach ($raw in @($Order)) {
        $leaf = @("$raw".Trim() -split '[\\/]')[-1]
        $light = ($null -ne $IsLight) -and (& $IsLight $leaf)
        if ([string]::Equals($leaf, $Name, [StringComparison]::OrdinalIgnoreCase)) {
            if ($light) { return -1 }
            return $n
        }
        if (-not $light) { $n++ }
    }
    return -1
}

# The game's own order for a plugin list: the five masters, the Skyrim.ccc
# entries that are present, then the list's entries with the ones the game
# loads as masters first (Test-ThornswoodLoadsAsMaster), each kept in the
# order it has. $Info maps a present plugin to its header (Light, Master); a
# name with no entry is not in Data and is left out.
function Get-ThornswoodGameSequence([string[]]$Wanted, [string[]]$Ccc, [hashtable]$Info) {
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $out = New-Object Collections.Generic.List[string]
    foreach ($m in $script:ThornswoodBaseMasters) {
        $hit = @($Wanted | Where-Object { [string]::Equals("$_", $m, [StringComparison]::OrdinalIgnoreCase) })
        if ($Info.ContainsKey($m) -or $hit.Count) { [void]$out.Add($m); [void]$seen.Add($m) }
    }
    foreach ($c in @($Ccc)) {
        $n = "$c".Trim()
        if ($n.Length -eq 0 -or $seen.Contains($n) -or -not $Info.ContainsKey($n)) { continue }
        [void]$out.Add($n); [void]$seen.Add($n)
    }
    $first = New-Object Collections.Generic.List[string]
    $rest = New-Object Collections.Generic.List[string]
    foreach ($w in @($Wanted)) {
        $n = "$w".Trim()
        if ($n.Length -eq 0 -or $seen.Contains($n) -or -not $Info.ContainsKey($n)) { continue }
        [void]$seen.Add($n)
        if (Test-ThornswoodLoadsAsMaster $n $Info[$n]) { [void]$first.Add($n) } else { [void]$rest.Add($n) }
    }
    foreach ($n in $first) { [void]$out.Add($n) }
    foreach ($n in $rest) { [void]$out.Add($n) }
    return ,[string[]]$out.ToArray()
}

<#
  The server's load order with light plugins in it.

    $Wanted   the plugin list's enabled names, the five masters in front
    $Ccc      Skyrim.ccc's names
    $Info     name to header (Light, Master) for each plugin that is in Data
    $Prior    the names the server's own list has now, empty for a new order

  Returns Order (every plugin, full and light, in the game's order), and for
  saying what happened: Full and Light (each kind in its index order),
  AddedFull, AddedLight, Removed (the server had them, the list does not),
  NewFullMasters (new master flagged full plugins, which the game hoists to
  the front, so they cannot go on the end of an order a world is keyed to),
  LightOutOfPlace (light plugins that the game would load before a light
  plugin the kept order puts in front of them, so their light index would
  not be the server's), and LightKept (false when there was no light order
  to keep and this one was taken from the list).
#>
function Get-ThornswoodServerOrder([string[]]$Wanted, [string[]]$Ccc, [hashtable]$Info, [string[]]$Prior) {
    $game = Get-ThornswoodGameSequence $Wanted $Ccc $Info
    $isLight = @{}
    foreach ($n in $game) { $isLight[$n.ToLowerInvariant()] = [bool]$Info[$n].Light }
    $gameFull = @($game | Where-Object { -not $isLight[$_.ToLowerInvariant()] })
    $gameLight = @($game | Where-Object { $isLight[$_.ToLowerInvariant()] })
    $cccSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($c in @($Ccc)) { $t = "$c".Trim(); if ($t.Length) { [void]$cccSet.Add($t) } }

    $byLower = @{}
    foreach ($n in $game) { $byLower[$n.ToLowerInvariant()] = $n }
    $priorFull = New-Object Collections.Generic.List[string]
    $priorLight = New-Object Collections.Generic.List[string]
    $removed = New-Object Collections.Generic.List[string]
    $placed = @{}
    foreach ($raw in @($Prior)) {
        $p = @("$raw".Trim() -split '[\\/]')[-1]
        if ($p.Length -eq 0) { continue }
        $k = $p.ToLowerInvariant()
        if ($placed.ContainsKey($k)) { continue }
        $placed[$k] = $true
        if (-not $byLower.ContainsKey($k)) { [void]$removed.Add($p); continue }
        if ($isLight[$k]) { [void]$priorLight.Add($byLower[$k]) } else { [void]$priorFull.Add($byLower[$k]) }
    }

    $full = New-Object Collections.Generic.List[string]
    $addedFull = New-Object Collections.Generic.List[string]
    if ($priorFull.Count) {
        foreach ($n in $priorFull) { [void]$full.Add($n) }
        foreach ($n in $gameFull) { if (-not $placed.ContainsKey($n.ToLowerInvariant())) { [void]$full.Add($n); [void]$addedFull.Add($n) } }
    } else {
        foreach ($n in $gameFull) { [void]$full.Add($n) }
    }
    $newFullMasters = @($addedFull | Where-Object { Test-ThornswoodLoadsAsMaster $_ $Info[$_] })
    if (-not $priorFull.Count) { $newFullMasters = @() }

    $light = New-Object Collections.Generic.List[string]
    $addedLight = New-Object Collections.Generic.List[string]
    $kept = $priorLight.Count -gt 0
    if ($kept) {
        foreach ($n in $priorLight) { [void]$light.Add($n) }
        foreach ($n in $gameLight) { if (-not $placed.ContainsKey($n.ToLowerInvariant())) { [void]$light.Add($n); [void]$addedLight.Add($n) } }
    } else {
        foreach ($n in $gameLight) { [void]$light.Add($n) }
    }

    # The game's own rule over the kept light order: the Skyrim.ccc ones
    # first, then the ones it loads as masters (an .esl always), then the
    # rest. A light plugin that comes after one of a later group would be
    # given an earlier light index by the game than by the server: a new
    # one of those cannot go on the end of a light order a world is keyed to,
    # the same as a new full master.
    $outOfPlace = New-Object Collections.Generic.List[string]
    $rank = 0
    foreach ($n in $light) {
        $r = if ($cccSet.Contains($n)) { 0 } elseif (Test-ThornswoodLoadsAsMaster $n $Info[$n]) { 1 } else { 2 }
        if ($r -lt $rank) { [void]$outOfPlace.Add($n) } else { $rank = $r }
    }

    # Into the game's order: each place the list gives a full plugin is
    # filled from the full order, each place it gives a light plugin from the
    # light order. So light and full plugins sit among each other where the
    # game puts them, and each kind is in the order its indices come from.
    $order = New-Object Collections.Generic.List[string]
    $fi = 0; $li = 0
    foreach ($n in $game) {
        if ($isLight[$n.ToLowerInvariant()]) { [void]$order.Add($light[$li]); $li++ }
        else { [void]$order.Add($full[$fi]); $fi++ }
    }

    return [pscustomobject]@{
        Order = [string[]]$order.ToArray()
        Full = [string[]]$full.ToArray()
        Light = [string[]]$light.ToArray()
        AddedFull = [string[]]$addedFull.ToArray()
        AddedLight = [string[]]$addedLight.ToArray()
        Removed = [string[]]$removed.ToArray()
        NewFullMasters = [string[]]$newFullMasters
        LightOutOfPlace = [string[]]$outOfPlace.ToArray()
        LightKept = $kept
    }
}
