<#
  OwnPlugins.ps1

  Where a builder reads a plugin of the load order from (#2923).

  Thornswood's own plugins (Thornswood-Content.esp, Thornswood-Last.esp,
  Thornswood-WoodworkerTrail.esp, and any other file in game\content) are made
  and shipped from this repository's game\content. A game folder holds
  whichever release last reached it, so a table read from there describes a
  plugin nobody ships. Every plugin whose name is a file in game\content is
  read from there, and every other plugin from the game's Data folder. The same
  rule is OwnPlugins.js and own_plugins.py; tests\test-2923-own-plugins.js
  holds the three to it.

  Which plugins are in the load order is read here too (#2976). The game loads
  Skyrim's five masters, then every line of plugins.txt that starts with '*'.
  A line without one is a plugin Vortex or the launcher knows about and has
  switched off: the game does not load it, and its file may be gone. Eight
  builders parsed plugins.txt on their own and four of those took the
  switched off lines as loaded, so on 20 Oct Build-DoorTable.py stopped on
  ElysiumEstateSSE.esp, a switched off line whose file the launcher had
  removed on 1 Oct. Every builder takes its load order from Get-LoadOrder.

      . (Join-Path $PSScriptRoot 'OwnPlugins.ps1')
      $order = Get-LoadOrder $PluginsTxt
      $path = Get-PluginPath $Data 'Thornswood-Content.esp'
#>

$script:OwnPluginDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\game\content'))

function Test-OwnPlugin([string]$Name) {
    return [System.IO.File]::Exists((Join-Path $script:OwnPluginDir $Name))
}

function Get-PluginPath([string]$Data, [string]$Name) {
    if (Test-OwnPlugin $Name) { return (Join-Path $script:OwnPluginDir $Name) }
    return (Join-Path $Data $Name)
}

# The five masters load before the game reads plugins.txt, and are never
# written to it.
$script:LoadOrderMasters = @('Skyrim.esm', 'Update.esm', 'Dawnguard.esm', 'HearthFires.esm', 'Dragonborn.esm')

# plugins.txt as the game reads it: On is the load order (the masters, then
# each '*' line, once, names matched without case the way Windows matches
# files), Off is each line the game skips because it has no '*'.
function Read-PluginsTxt([string]$Path) {
    $on = New-Object 'System.Collections.Generic.List[string]'
    $off = New-Object 'System.Collections.Generic.List[string]'
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($m in $script:LoadOrderMasters) { $on.Add($m); [void]$seen.Add($m) }
    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($ln in [System.IO.File]::ReadAllLines($Path, (New-Object System.Text.UTF8Encoding($false)))) {
        $t = $ln.Trim()
        if (-not $t -or $t.StartsWith('#')) { continue }
        if (-not $t.StartsWith('*')) { $lines.Add($t); continue }
        $name = $t.Substring(1).Trim()
        if ($name -and $seen.Add($name)) { $on.Add($name) }
    }
    foreach ($name in $lines) { if ($seen.Add($name)) { $off.Add($name) } }
    return [pscustomobject]@{ On = $on.ToArray(); Off = $off.ToArray() }
}

function Get-LoadOrder([string]$Path) { return (Read-PluginsTxt $Path).On }
function Get-SwitchedOff([string]$Path) { return (Read-PluginsTxt $Path).Off }

# What a table says it was read from: how many plugins and the first twelve
# hex of the sha256 of their names in order, one per line. Never the plugin
# list's path, which names one machine (#3105).
function Get-LoadOrderName([string[]]$Order) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes(($Order -join "`n"))
    $hex = ([System.BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant().Substring(0, 12)
    return ('{0} plugins in load order (names sha256 {1})' -f $Order.Count, $hex)
}
