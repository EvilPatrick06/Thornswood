<#
  test-1715-light-recipes.ps1

      pwsh -NoProfile -File .\tests\test-1715-light-recipes.ps1

  #1715. 255 open-book rows of game\data\recipes.json need a light plugin:
  their recipe, their bench or their output is MoreCraftableEquipment.esp's
  or Gourmet.esp's, and the Bandage's bench is the loom keyword
  6ce000:Update.esm, a record MoreCraftableEquipment.esp adds under
  Update.esm's numbering. An engine that loads no light plugin has none of
  those records, so the server is never asked about those rows. Patrick,
  5 October: keep them, and the server learns light plugins.

  scripts\dev\Build-RecipeTable.ps1 therefore marks such a row "fires" only
  when the engine this release records loads light plugins ("lightPlugins":
  true in records\server-build.json, read by ServerOrder.ps1, the flag
  Deploy-Gamemode lists light plugins by). This lifts the rule out of the
  script by its syntax tree and runs it on records shaped like the measured
  ones, and holds the place in the script that applies it.

  -Repo points it at another checkout. Read only.
#>
[CmdletBinding()]
param([string]$Repo)
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $Repo) { $Repo = Split-Path -Parent $Here }

$script:pass = 0; $script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" -ForegroundColor Red }
}

$path = Join-Path $Repo 'scripts\dev\Build-RecipeTable.ps1'
$src = [IO.File]::ReadAllText($path)
$ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null)
$fn = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-RecipeLightPlugin' }, $true)
Yes 'Build-RecipeTable.ps1 has Get-RecipeLightPlugin' ($null -ne $fn)
if ($null -ne $fn) {
    Invoke-Expression $fn.Extent.Text
    $isLight = @{ 'Skyrim.esm' = $false; 'Update.esm' = $false; 'MoreCraftableEquipment.esp' = $true; 'Gourmet.esp' = $true; 'Thornswood-Content.esp' = $false }
    # The first plugin holding each record: the loom keyword is under
    # Update.esm's numbering, and MoreCraftableEquipment.esp adds it.
    $firstIn = @{ '6ce000:Update.esm' = 'MoreCraftableEquipment.esp'; '154c4:Thornswood-Content.esp' = 'Thornswood-Content.esp';
                  'e3c16:Skyrim.esm' = 'Skyrim.esm'; '1a:MoreCraftableEquipment.esp' = 'MoreCraftableEquipment.esp' }
    function Row([string]$desc, [string]$bench, [string]$out, [string[]]$inputs = @()) {
        return [pscustomobject]@{ Desc = $desc; BenchDesc = $bench; OutDesc = $out; InputList = @($inputs | ForEach-Object { [pscustomobject]@{ Desc = $_; Count = 1 } }) }
    }
    Yes 'a recipe in a light plugin needs it' ((Get-RecipeLightPlugin (Row '801:MoreCraftableEquipment.esp' 'e3c16:Skyrim.esm' '12eb7:Skyrim.esm') $firstIn $isLight) -eq 'MoreCraftableEquipment.esp')
    Yes 'the Bandage, a full plugin''s recipe at the loom keyword a light plugin adds to Update.esm, needs it' (
        (Get-RecipeLightPlugin (Row '154c4:Thornswood-Content.esp' '6ce000:Update.esm' 'd3d:Thornswood-Content.esp') $firstIn $isLight) -eq 'MoreCraftableEquipment.esp')
    Yes 'an output from a light plugin needs it' ((Get-RecipeLightPlugin (Row '100:Thornswood-Content.esp' 'e3c16:Skyrim.esm' '22:Gourmet.esp') $firstIn $isLight) -eq 'Gourmet.esp')
    Yes 'an input from a light plugin needs it' ((Get-RecipeLightPlugin (Row '100:Thornswood-Content.esp' 'e3c16:Skyrim.esm' '12eb7:Skyrim.esm' @('5:Gourmet.esp')) $firstIn $isLight) -eq 'Gourmet.esp')
    Yes 'a recipe all of full plugins needs none' ((Get-RecipeLightPlugin (Row '100:Thornswood-Content.esp' 'e3c16:Skyrim.esm' '12eb7:Skyrim.esm' @('5:Skyrim.esm')) $firstIn $isLight) -eq '')
}

# The place that applies it.
Yes 'the rule reads the engine from records\server-build.json through ServerOrder.ps1' (
    $src -match '\$ENGINE_LOADS_LIGHT = Test-ThornswoodEngineLoadsLight \(Join-Path \$PSScriptRoot ''\.\.\\\.\.\\records\\server-build\.json''\)' -and
    $src -match '\. \(Join-Path \$PSScriptRoot ''\.\.\\deploy\\ServerOrder\.ps1''\)')
Yes 'and a row that needs a light plugin fires only on an engine that loads them' (
    $src -match '\$lightNeeded = Get-RecipeLightPlugin \$r \$recordFirstIn \$pluginIsLight\s+if \(\$lightNeeded\) \{\s+\$script:lightRows\+\+\s+if \(-not \$ENGINE_LOADS_LIGHT\) \{ \$fires = \$false \}')
Yes 'each plugin''s lightness is its header''s: an .esl name or 0x200' ($src -match '\$pluginIsLight\[\$pl\] = \(\$pl -match ''\\\.esl\$''\) -or \(\(\[BitConverter\]::ToUInt32\(\$b, 8\) -band 0x200\) -ne 0\)')
Yes 'and each record''s plugin is the first that holds it' ($src -match 'if \(-not \$recordFirstIn\.ContainsKey\(\$desc\)\) \{ \$recordFirstIn\[\$desc\] = \$pl \}')

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
