<#
  LastPluginRecipe.ps1

  What this checkout's recipe for Thornswood-Last.esp says of the plugin it
  makes (#2791): the size and sha256 game\data\last-plugin.json names, and
  the plugin's file header, which the recipe writes out. No repository holds
  the plugin (LastPluginOnBox.ps1 says why and how the box makes it), so a
  deploy or a release that has to know which plugin it is, or whether it is
  light and which masters it names, reads it here.

  Defines a variable and functions and nothing else, and loads only
  ..\release\Read-JsonFile.ps1. tests\test-2791-last-on-box.ps1 holds it.
#>

. (Join-Path $PSScriptRoot '..\release\Read-JsonFile.ps1')

$ThornswoodLastPlugin = 'Thornswood-Last.esp'

# The plugin the commit's recipe makes, as game\data\last-plugin.json names it:
# Bytes and Sha (lowercase), or $null when the checkout has no manifest.
function Get-ThornswoodLastPluginWant([string]$RepoDir) {
    $p = Join-Path $RepoDir 'game\data\last-plugin.json'
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    $m = ConvertFrom-ThornswoodJson ([IO.File]::ReadAllText($p)) $p
    if (-not $m.plugin -or -not [string]$m.plugin.sha256) { throw "$p names no plugin, so nothing says which Thornswood-Last.esp its recipe makes." }
    return [pscustomobject]@{ Bytes = [int64]$m.plugin.size; Sha = ([string]$m.plugin.sha256).ToLowerInvariant() }
}

# The plugin's file header, its TES4 record with its flags and masters, as
# the recipe holds it: Thornswood writes that record itself, so the recipe's
# first step writes it out (scripts\mods\last_recipe.py, LIT), with the
# first group headers after it, which are left off here.
# For a reader of the header where no plugin is (Deploy-Gamemode.ps1 asks
# whether it is light and which masters it names). $null when the checkout
# has no recipe; a throw when the recipe does not start that way.
function Get-ThornswoodLastRecipeHead([string]$RepoDir) {
    $p = Join-Path $RepoDir 'game\data\last-plugin.recipe'
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    $b = [IO.File]::ReadAllBytes($p)
    $varint = {
        $n = [int64]0; $shift = 0
        while ($true) {
            if ($script:lastAt -ge $b.Length) { throw "$p ends in the middle of a number." }
            $x = $b[$script:lastAt]; $script:lastAt++
            $n = $n -bor ([int64]($x -band 0x7F) -shl $shift)
            if (-not ($x -band 0x80)) { return $n }
            $shift += 7
        }
    }
    if ($b.Length -lt 41 -or [Text.Encoding]::ASCII.GetString($b, 0, 5) -ne ("TSLR" + [char]1)) { throw "$p is not a version 1 recipe for $ThornswoodLastPlugin." }
    $script:lastAt = 41
    $count = & $varint
    for ($i = 0; $i -lt $count; $i++) {
        $script:lastAt++
        $nameLength = [int](& $varint)
        $script:lastAt += $nameLength
        [void](& $varint)
        $script:lastAt += 32
    }
    if ($script:lastAt -ge $b.Length -or $b[$script:lastAt] -ne 0) { throw "$p does not start its steps with the plugin's own header." }
    $script:lastAt++
    $n = [int](& $varint)
    if ($script:lastAt + $n -gt $b.Length -or $n -lt 24 -or [Text.Encoding]::ASCII.GetString($b, $script:lastAt, 4) -ne 'TES4') { throw "$p does not start its steps with the plugin's own header." }
    $record = 24 + [int64][BitConverter]::ToUInt32($b, $script:lastAt + 4)
    if ($record -gt $n) { throw "$p does not write the plugin's whole header in its first step." }
    $head = New-Object byte[] $record
    [Array]::Copy($b, $script:lastAt, $head, 0, $record)
    return ,$head
}
