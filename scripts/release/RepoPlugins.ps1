<#
  RepoPlugins.ps1

  The plugins this repository builds and ships itself, in one list (#2486).
  Each is made under game\content (Add-ContentRecords.py and friends for
  Thornswood-Content.esp, Build-LastPlugin.py for Thornswood-Last.esp, #2468)
  and sent from there, never from a Vortex folder, so a rebuild reaches the
  servers and the packs with no collection revision.

  Every place that tells ours from the collection's reads this list:
    Ship-Rules.ps1           $ShipOursFiles, Ensure-ShipRequiredData
    Publish-Update.ps1 and Package-Thornswood.ps1   Test-FromCollection
    ServerContent.ps1        what the box holds, by size and sha256 (#2308)
    Deploy-Server.ps1 and Deploy-DevGamemode.ps1    sent from the repo, held by sha256
    CollectionPlugins.ps1    never held to records\collection-plugins.json (#2019)
  game\gamemode.js serves the same names (OURS, #1180), and
  tests\test-1180-own-plugins.js holds that list to $ShipOursFiles.

  Until #2486 each of those places named Thornswood-Content.esp alone, so
  Thornswood-Last.esp, built here too, fell through to "the collection's" in
  all of them and every rebuild needed a collection revision from Vortex.

  Defines a variable and functions and nothing else.
#>

$ThornswoodRepoPlugins = @('Thornswood-Content.esp', 'Thornswood-Last.esp')

# Whether a plugin name, or a Data\ path of one, is ours.
function Test-ThornswoodRepoPlugin([string]$Name) {
    if (-not $Name) { return $false }
    $n = $Name.Replace('/', '\')
    if ($n -match '^(?i)Data\\') { $n = $n.Substring(5) }
    if ($n.Contains('\')) { return $false }
    return [bool](@($ThornswoodRepoPlugins) -icontains $n)
}

# Where the repo keeps one of them.
function Get-ThornswoodRepoPluginPath([string]$RepoDir, [string]$Name) {
    return (Join-Path $RepoDir ('game\content\' + $Name))
}