<#
  test-installer-behind-gate.ps1

  A main release refuses to go out while the public installer is behind, and a
  dev release still only warns.

  WHY THIS EXISTS. The second half of issue #422. The first half baked the
  releases feed path into Package-Thornswood so a rebuilt installer is seeded
  from the right feed (PR #228). This half is the gate: Thornswood-Setup.zip
  falls one release further behind on every main Ship, because Ship does not
  rebuild the installer with the release, and the only sign was a yellow line
  on the closing screen nobody rereads. So an installer drifted release after
  release until a new person sat through the whole pile on first launch.

  Now a main Ship works out how far behind the zip is BEFORE it publishes, and
  refuses if it is behind and nothing here was going to rebuild it. -Package is
  the way through, because it rebuilds the installer after the release, so the
  two go out together. A dev release never refuses: it does not touch the
  installer. Nor does a hotfix: it is the live build plus one urgent fix, and
  holding it for a twenty-minute rebuild is the opposite of what a hotfix is
  for.

  It lifts Measure-Installer and the gate out of the shipped Ship.ps1 by the
  parser, the way test-ship-gate.ps1 lifts the Git gate, and drives them
  against a throwaway installer zip and releases feed, so nothing here touches
  this repository, the network or any launcher. Read only apart from files
  under its own temp folder.
#>
[CmdletBinding()]
param([string]$ShipPath)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $ShipPath) { $ShipPath = Join-Path (Split-Path -Parent $Here) 'scripts\release\Ship.ps1' }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Done {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    exit $(if ($script:fail) { 1 } else { 0 })
}

$src = [IO.File]::ReadAllText($ShipPath)
$tokens = $null; $errs = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($src, [ref]$tokens, [ref]$errs)
Yes 'Ship.ps1 parses' (@($errs).Count -eq 0)

# ---- lift the function and the gate out of the shipped script ------------------
$FnAst = [System.Management.Automation.Language.FunctionDefinitionAst]
$IfAst = [System.Management.Automation.Language.IfStatementAst]

$measure = ''
foreach ($fn in $ast.FindAll({ param($n) $n -is $FnAst }, $true)) {
    if ($fn.Name -eq 'Measure-Installer') { $measure = $fn.Extent.Text; break }
}
Yes 'Ship.ps1 has Measure-Installer' ($measure -ne '')

# The gate is the if that carries the whole rule: it reads Measure-Installer,
# and its refusal names the zip. Found by both so another if never stands in.
$gate = ''
foreach ($n in $ast.FindAll({ param($x) $x -is $IfAst }, $true)) {
    $text = $n.Extent.Text
    if ($text.Contains('Measure-Installer') -and $text.Contains('Thornswood-Setup.zip') -and $text.Contains('Die')) {
        $gate = $text; break
    }
}
Yes 'Ship.ps1 has the installer gate' ($gate -ne '')

# The gate refuses on the main channel and lets a dev release, a hotfix, a dry
# run and a -Package release through, read off the condition itself so a change
# to it is caught here rather than shipped.
Yes 'the gate is off for a dev release'   ($gate -match '-not \$Dev\b')
Yes 'the gate is off for a hotfix'        ($gate -match '-not \$hotfix\b')
Yes 'the gate is off for a dry run'       ($gate -match '-not \$DryRun\b')
Yes 'the gate is off when -Package is set' ($gate -match '-not \$Package\b')

# The gate must sit before the publish, or a refusal leaves a release half out.
$gateAt = $src.IndexOf($gate)
$publishAt = $src.IndexOf("Head 'Publishing'")
Yes 'the gate runs before the publish' ($gateAt -ge 0 -and $publishAt -gt $gateAt)

if (-not ($measure -and $gate)) { Done }

# ---- drive them against a throwaway installer and feed -------------------------
# Die is Ship's own exit; here it throws, so a refusal comes back as its words.
# Unbump records that it was asked, so the gate putting the version back before
# it stops is checked the way the real gate calls it.
# The sections lifted below call ConvertFrom-ThornswoodJson, which their script dot-sources.
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\release\Read-JsonFile.ps1')
$stubs = @'
function Say($m, $c) { }
function Head($m) { }
function Die($m) { throw ('STOP. ' + $m) }
function Unbump($why) { $global:tsUnbumped += @($why) }
'@
$gateSb = [scriptblock]::Create(
    '$DistRoot = $args[0]; $Root = $args[1]; $ReleaseDir = $args[2];' +
    '$Dev = $args[3]; $hotfix = $args[4]; $DryRun = $args[5]; $Package = $args[6];' +
    $stubs + "`n" + $measure + "`n" + $gate)
$measureSb = [scriptblock]::Create(
    '$DistRoot = $args[0]; $Root = $args[1]; $ReleaseDir = $args[2];' + $measure + "`nreturn (Measure-Installer)")

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('tsinst-' + [Guid]::NewGuid().ToString('N'))
$DistRoot = Join-Path $tmp 'dist'
$Root = Join-Path $tmp 'Play'
$ReleaseDir = Join-Path $tmp 'Thornswood-Releases'
$distDir = Join-Path (Join-Path $DistRoot 'Play') '_dist'
$zip = Join-Path $distDir 'Thornswood-Setup.zip'
$feed = Join-Path $ReleaseDir 'version.json'

# The zip was built at a fixed moment; the packs are stamped around it, so how
# many are newer is the count the gate turns on.
$built = [datetime]'2026-06-01 12:00:00'
function Set-Zip { New-Item -ItemType Directory -Force -Path $distDir | Out-Null; [IO.File]::WriteAllText($zip, 'a setup zip'); (Get-Item -LiteralPath $zip).LastWriteTime = $built }
function Drop-Zip { if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force } }
function Set-Packs([string[]]$ids) {
    $packs = ($ids | ForEach-Object { '{"id":"' + $_ + '"}' }) -join ','
    [IO.File]::WriteAllText($feed, '{"launcherVersion":"1.1.94","packs":[' + $packs + ']}')
}

# Not called Measure: that is an alias for Measure-Object and would win.
function Ask-Installer { return (& $measureSb $DistRoot $Root $ReleaseDir) }
# '' when the gate lets the release through, the STOP line when it does not.
function Gate([bool]$dev, [bool]$hotfix, [bool]$dry, [bool]$pkg) {
    $global:tsUnbumped = @()
    try { & $gateSb $DistRoot $Root $ReleaseDir $dev $hotfix $dry $pkg | Out-Null; return '' }
    catch { return [string]$_.Exception.Message }
}

try {
    New-Item -ItemType Directory -Force -Path $ReleaseDir | Out-Null

    # ---- Measure-Installer counts the releases the zip is behind -------------------
    Set-Zip
    # Two releases newer than the zip, one older; the split parts of a release
    # (-1 -2 -3) are one release.
    Set-Packs @('20260101-0900', '20260701-1000', '20260801-1100-1', '20260801-1100-2')
    $m = Ask-Installer
    Yes 'M1 the zip is found' ($m.HaveZip)
    Yes "M1 two releases are newer than it, the split one counted once: $($m.Behind)" ($m.Behind -eq 2)
    Yes 'M1 it reports when the zip was built' ($m.ZipTime -eq $built)

    Set-Packs @('20260101-0900', '20260201-0800')
    $m = Ask-Installer
    Yes "M2 a zip newer than every release is not behind: $($m.Behind)" ($m.HaveZip -and $m.Behind -eq 0)

    Drop-Zip
    $m = Ask-Installer
    Yes 'M3 no zip on disk is reported as none, nothing behind' (-not $m.HaveZip -and $m.Behind -eq 0)

    # ---- the gate: a main release refuses while the installer is behind ------------
    Set-Zip
    Set-Packs @('20260701-1000', '20260801-1100')   # two behind

    $r = Gate $false $false $false $false
    Yes "GATE main and behind stops the release: '$r'" ($r -like 'STOP.*')
    Yes 'GATE it says how far behind and when the zip was built' ($r -match '\b2 releases behind' -and $r -match 'Jun')
    Yes 'GATE it offers -Package and Package-Thornswood.ps1' ($r -match '-Package' -and $r -match 'Package-Thornswood\.ps1')
    Yes 'GATE it puts the version back before it stops' (@($global:tsUnbumped).Count -ge 1)

    $r = Gate $false $false $false $true
    Yes "GATE main with -Package is not refused, the rebuild is coming: '$r'" ($r -eq '')

    $r = Gate $true $false $false $false
    Yes "GATE a dev release is never refused for behind: '$r'" ($r -eq '')

    $r = Gate $false $true $false $false
    Yes "GATE a hotfix is never refused for behind: '$r'" ($r -eq '')

    $r = Gate $false $false $true $false
    Yes "GATE a dry run is not refused: '$r'" ($r -eq '')

    # ---- the gate lets a current installer, or none at all, through ----------------
    Set-Packs @('20260101-0900', '20260201-0800')   # zip newer than all
    $r = Gate $false $false $false $false
    Yes "GATE main with a current installer goes through: '$r'" ($r -eq '')

    Drop-Zip
    Set-Packs @('20260701-1000', '20260801-1100')
    $r = Gate $false $false $false $false
    Yes "GATE main with no installer yet is not refused for behind: '$r'" ($r -eq '')
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Done
