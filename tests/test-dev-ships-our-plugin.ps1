# test-dev-ships-our-plugin.ps1
#
# A dev release carries our own plugin; a main release leaves it to the Nexus
# collection; every other file the collection provides stays out of both.
#
# Patrick, 24 September: "we can put a temp patch for the plugins until we put
# them on nexus", "yeah they shoul be entrily isolated for testing", "thats the
# point of a dev build". See $DevShipsOurs in scripts/release/Publish-Update.ps1.
#
# This lifts the real $DevShipsOurs line and the real Test-FromCollection out
# of Publish-Update.ps1 with the PowerShell parser and runs them, rather than
# matching text. Read only.
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, the repository is one folder up.
$here = Split-Path -Parent $here
$src = Join-Path $here 'scripts\release\Publish-Update.ps1'

$pass = 0; $fail = 0
function yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host ('PASS  ' + $what) }
    else { $script:fail++; Write-Host ('FAIL  ' + $what) }
}

$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$tokens, [ref]$errors)
yes 'Publish-Update.ps1 parses' ($errors.Count -eq 0)

$fn = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Test-FromCollection' }, $true) | Select-Object -First 1
$list = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$DevShipsOurs' }, $true) | Select-Object -First 1
yes 'Test-FromCollection is in the script' ($null -ne $fn)
yes 'and so is the list of our files a dev release carries' ($null -ne $list)

if ($fn -and $list) {
    # One scope per case, so $Dev and $vortexFiles are exactly what the script
    # would hold at that point.
    function Ask([bool]$dev, [string]$rel) {
        $block = [scriptblock]::Create(
            '$Dev = $args[0]; ' +
            '$vortexFiles = New-Object ''System.Collections.Generic.HashSet[string]'' ([StringComparer]::OrdinalIgnoreCase); ' +
            '[void]$vortexFiles.Add(''Data\Thornswood-Content.esp''); ' +
            '[void]$vortexFiles.Add(''Data\Skyrim.esm''); ' +
            '[void]$vortexFiles.Add(''Data\SunHelmSurvival.esp''); ' +
            $list.Extent.Text + '; ' + $fn.Extent.Text + '; ' +
            'Test-FromCollection $args[1]')
        return [bool](& $block $dev $rel)
    }

    yes 'on the dev channel our plugin is not treated as the collection''s, so it ships' (-not (Ask $true 'Data\Thornswood-Content.esp'))
    yes 'and the match ignores case, the way the record does' (-not (Ask $true 'data\thornswood-content.esp'))
    yes 'on the main channel it is still the collection''s, so it does not ship' (Ask $false 'Data\Thornswood-Content.esp')
    yes 'a master the collection provides stays out of a dev release' (Ask $true 'Data\Skyrim.esm')
    yes 'and so does a mod the collection provides' (Ask $true 'Data\SunHelmSurvival.esp')
    yes 'and a file the collection does not provide is still ours on both channels' ((-not (Ask $true 'Data\Platform\Plugins\thornswood-front.js')) -and (-not (Ask $false 'Data\Platform\Plugins\thornswood-front.js')))
    yes 'the list names exactly one file today, our plugin' ($list.Extent.Text -match "@\('Data\\Thornswood-Content\.esp'\)")
}

$code = Get-Content -LiteralPath $src -Raw
yes 'the launcher side it relies on is still there: Updater unshares before it extracts' ((Get-Content -LiteralPath (Join-Path $here 'launcher\app\Updater.cs') -Raw) -match 'OwnGame\.Unshare\(full\);\s*\r?\n\s*e\.ExtractToFile\(full, true\);')

Write-Host ''
Write-Host ('{0} passed, {1} failed' -f $pass, $fail)
if ($fail) { exit 1 }
exit 0
