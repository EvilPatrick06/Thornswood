<#
  test-package-release-dir.ps1

  The installer has to find the live feed on whichever machine builds it,
  and has to stop rather than guess when the feed is not there.

  Entry 175 on the list. Package-Thornswood.ps1 read version.json from a path
  written into one home folder, and when that was missing it fell back to this
  repo's own version.json. MEASURED 24 SEPTEMBER: the feed beside the repo
  lists 227 packs and the repo's copy lists 164, 63 short. That version.json is
  what applied.txt is written from, and applied.txt is what tells a fresh
  install which packs it already has, so the fallback quietly shipped an
  installer that fetched 63 packs again on first launch.

  This never runs the packager. It takes twenty minutes and closes the game.
  It reads the script, checks the parameter and every path in it, and lifts
  the block between the release feed markers, which is only the lookup and the
  stop, and drives it against folders under its own temp folder. If the
  markers move, this stops rather than quietly testing nothing.
#>
[CmdletBinding()]
param([string]$PackagePath)
# Scripts this runs whole go to a stand-in box, so the freshness guard lets them be (#2118).
$env:THORNSWOOD_HARNESS = '1'

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here0 = $PSScriptRoot
if (-not $Here0) { $Here0 = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, the repository is one folder up.
$Here0 = Split-Path -Parent $Here0
if (-not $PackagePath) { $PackagePath = Join-Path $Here0 'scripts\release\Package-Thornswood.ps1' }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Done {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail) { exit 1 }
    exit 0
}

# ---- the script parses, the same gate the build check uses -----------------
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($PackagePath, [ref]$tokens, [ref]$errors)
Yes 'Package-Thornswood.ps1 parses' (@($errors).Count -eq 0)
$src = Get-Content -LiteralPath $PackagePath -Raw

# ---- the parameter ---------------------------------------------------------
$params = @()
if ($ast.ParamBlock) { $params = @($ast.ParamBlock.Parameters) }
$rel = @($params | Where-Object { $_.Name.VariablePath.UserPath -eq 'ReleaseDir' })
Yes 'there is a -ReleaseDir parameter' ($rel.Count -eq 1)
if ($rel.Count -eq 1) {
    Yes 'it takes a string' ($rel[0].StaticType -eq [string])
    # Nothing in this param block says Position, so PowerShell numbers the
    # non-switch ones in the order they are written. -ReleaseDir went in after
    # the four that were there, so none of theirs moved. A later one goes after
    # it (-Stub did, #1192): what matters is that the positions already handed
    # out stay where they are, not that -ReleaseDir is last for ever.
    $positional = @($params | Where-Object { $_.StaticType -ne [switch] } | ForEach-Object { $_.Name.VariablePath.UserPath })
    $before = @('Root', 'OutDir', 'Level', 'VortexManifest', 'ReleaseDir')
    $kept = ($positional.Count -ge $before.Count) -and
            (@(0..($before.Count - 1) | Where-Object { $positional[$_] -ne $before[$_] }).Count -eq 0)
    Yes ('it comes after the four that were there and nothing went in ahead of it, so no positional argument moves (' + ($positional -join ', ') + ')') $kept
}

# ---- no path into anybody's home folder ------------------------------------
$homePaths = @($ast.FindAll({
    param($n)
    ($n -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
     $n -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) -and
    ($n.Value -match '(?i)^[a-z]:\\Users\\')
}, $true))
Yes 'no string in the script is a path under C:\Users' ($homePaths.Count -eq 0)
foreach ($h in $homePaths) { Write-Host ("      line {0}: {1}" -f $h.Extent.StartLineNumber, $h.Extent.Text) }

# ---- version.json only ever comes from the feed ----------------------------
# The fallback was Join-Path (Split-Path -Parent $here) 'version.json', which is
# the repo's own copy. Any Join-Path onto version.json that does not start from
# $ReleaseDir is that fallback or one like it.
$joins = @($ast.FindAll({
    param($n)
    ($n -is [System.Management.Automation.Language.CommandAst]) -and
    ($n.GetCommandName() -eq 'Join-Path') -and
    (@($n.CommandElements | Where-Object {
        $_ -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $_.Value -eq 'version.json'
    }).Count -gt 0)
}, $true))
Yes 'the script reads version.json somewhere' ($joins.Count -ge 1)
$stray = @($joins | Where-Object {
    $first = $_.CommandElements[1]
    -not ($first -is [System.Management.Automation.Language.VariableExpressionAst] -and
          $first.VariablePath.UserPath -eq 'ReleaseDir')
})
Yes 'and only ever out of $ReleaseDir' ($stray.Count -eq 0)
foreach ($s in $stray) { Write-Host ("      line {0}: {1}" -f $s.Extent.StartLineNumber, $s.Extent.Text) }

# ---- lift the lookup -------------------------------------------------------
$open = '# ==== thornswood release feed ===='
$shut = '# ==== end thornswood release feed ===='
$a = $src.IndexOf($open)
$b = $src.IndexOf($shut)
Yes 'the release feed block markers are in Package-Thornswood.ps1' ($a -ge 0 -and $b -gt $a)
if ($a -lt 0 -or $b -le $a) { Done }
$block = $src.Substring($a, $b - $a)

# It has to run before the packager does anything that costs time or touches
# the game: before it closes the game and before anything is staged.
foreach ($mark in "Head 'Packaging'", 'Stop-Game', 'Copy-Item') {
    $at = $src.IndexOf($mark)
    Yes ("the lookup comes before the first " + $mark) ($at -lt 0 -or $a -lt $at)
}
# And the applied.txt section uses what the lookup found rather than looking
# again. Every assignment to $vLive is inside the block.
$assigns = @($ast.FindAll({
    param($n)
    ($n -is [System.Management.Automation.Language.AssignmentStatementAst]) -and
    ($n.Left -is [System.Management.Automation.Language.VariableExpressionAst]) -and
    ($n.Left.VariablePath.UserPath -eq 'vLive')
}, $true))
Yes '$vLive is set' ($assigns.Count -ge 1)
Yes 'and only inside the lookup' (@($assigns | Where-Object { $_.Extent.StartOffset -lt $a -or $_.Extent.StartOffset -gt $b }).Count -eq 0)

# Runs the lifted block the way the packager does: $ReleaseDir is whatever was
# passed, and LOCALAPPDATA is where this machine's working copy of the live
# feed is (Feed-Store.ps1, #907). Die is the packager's stop, so here it throws
# and the message comes back.
function Run-Lookup([string]$appData, [string]$passed) {
    $ReleaseDir = $passed
    $vLive = ''
    function Die($m) { throw ('DIE: ' + $m) }
    $died = ''
    $oldApp = $env:LOCALAPPDATA
    $env:LOCALAPPDATA = $appData
    try { . ([scriptblock]::Create($block)) }
    catch { $died = [string]$_.Exception.Message }
    finally { $env:LOCALAPPDATA = $oldApp }
    return [pscustomobject]@{ ReleaseDir = $ReleaseDir; vLive = $vLive; Died = $died }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-releasedir-' + [Guid]::NewGuid().ToString('N'))
try {
    # One machine: the working copy of the live feed under LOCALAPPDATA, and a
    # repo carrying its own stale version.json, the way it does today.
    $app   = Join-Path $work 'appdata'
    $feed  = Join-Path $app 'Thornswood\feed\main'
    $repo  = Join-Path $work 'Thornswood-Repo'
    New-Item -ItemType Directory -Path $feed, $repo -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $repo 'version.json') -Value '{"packs":[{"id":"stale"}]}' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $feed 'version.json') -Value '{"packs":[{"id":"live"}]}' -Encoding UTF8

    # ---- nothing passed: this machine's working copy of the live feed
    $r = Run-Lookup $app ''
    Yes 'nothing passed finds the live feed this machine last received' ($r.ReleaseDir -eq $feed)
    Yes 'and reads its version.json' ($r.vLive -eq (Join-Path $feed 'version.json'))
    Yes 'and does not stop' ($r.Died -eq '')
    Yes 'it is not a clone of Thornswood-Releases beside the repo' ($r.ReleaseDir -notlike '*Thornswood-Releases*')

    # ---- passed explicitly
    $elsewhere = Join-Path $work 'elsewhere'
    New-Item -ItemType Directory -Path $elsewhere -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $elsewhere 'version.json') -Value '{"packs":[]}' -Encoding UTF8
    $r = Run-Lookup $app $elsewhere
    Yes '-ReleaseDir is used as given' ($r.vLive -eq (Join-Path $elsewhere 'version.json'))
    Yes 'and does not stop' ($r.Died -eq '')

    # ---- the feed is missing: stop, and never the repo's own copy
    Remove-Item -LiteralPath (Join-Path $feed 'version.json') -Force
    $r = Run-Lookup $app ''
    Yes 'no feed received on this machine stops the packager' ($r.Died -like 'DIE: *')
    Yes 'and says where it looked' ($r.Died.Contains($feed))
    Yes 'and says how to put it right' ($r.Died.Contains('-ReleaseDir') -and $r.Died.Contains('thornswood.net/feed/version.json'))
    Yes 'the repo''s own version.json is never taken instead' ($r.vLive -ne (Join-Path $repo 'version.json'))

    # ---- an explicit folder with no feed in it stops too, rather than going
    # back to the default and packaging against something nobody asked for
    Set-Content -LiteralPath (Join-Path $feed 'version.json') -Value '{"packs":[]}' -Encoding UTF8
    $empty = Join-Path $work 'empty'
    New-Item -ItemType Directory -Path $empty -Force | Out-Null
    $r = Run-Lookup $app $empty
    Yes 'a -ReleaseDir with no version.json stops' ($r.Died -like 'DIE: *')
    Yes 'and names that folder' ($r.Died.Contains($empty))
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Done
