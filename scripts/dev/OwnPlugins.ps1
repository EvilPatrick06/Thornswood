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

      . (Join-Path $PSScriptRoot 'OwnPlugins.ps1')
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
