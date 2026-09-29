<#
  test-dev-version.ps1

  A dev build has to outrank what main has published, or nobody can take it.

  MEASURED 21 SEPTEMBER, in the run itself. 1.1.76 was rolled back, which put
  main on 1.1.77. The three fixes that came off it went onto a branch cut
  BEFORE that bump, so its Updater.cs still said 1.1.76. Shipping that branch
  to dev produced 1.1.76.1, and Ship said so in as many words:

      main is on 1.1.77, this one is on 1.1.76.1

  Updater.IsNewer compares part by part, so 1.1.76.1 is LOWER than 1.1.77.
  Every dev launcher that had taken the 1.1.77 reset was never offered the
  build. It was packed, uploaded, written into version.json and announced in
  Discord, and it could not be installed by anybody who was already on dev.

  The comment in Ship.ps1 already stated the rule this broke: "a promoted main
  release always wins". That holds while dev ships from main. It stops holding
  the moment dev ships from a branch behind main, which is exactly what a
  rollback forces.

  This lifts the version block out of the shipped Ship.ps1 and drives it
  against feeds on disk, and it carries the launcher's own IsNewer so the
  answer is the one a launcher would actually give.

  Read only apart from files under its own temp folder.
#>
[CmdletBinding()]
param([string]$ShipPath)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, the repository is one folder up.
$Here = Split-Path -Parent $Here
if (-not $ShipPath) { $ShipPath = Join-Path $Here 'scripts\release\Ship.ps1' }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

# ---- lift the dev version block out of the shipped script -------------------
$src = Get-Content -LiteralPath $ShipPath -Raw
$open = $src.IndexOf('elseif ($Dev) {')
Yes 'the dev version block is in Ship.ps1' ($open -ge 0)
if ($open -lt 0) { Write-Host ''; Write-Host "0 passed, 1 failed"; exit 1 }

# Brace match from the block's own opening brace.
$b = $src.IndexOf('{', $open)
$depth = 0; $end = -1
for ($i = $b; $i -lt $src.Length; $i++) {
    $c = $src[$i]
    if ($c -eq '{') { $depth++ }
    elseif ($c -eq '}') { $depth--; if ($depth -eq 0) { $end = $i; break } }
}
$body = $src.Substring($b + 1, $end - $b - 1)

<#
  The launcher's own comparison, ported from Updater.cs IsNewer. This is the
  thing that decides whether anybody ever sees the build, so the harness asks
  it rather than assuming that a bigger looking string wins.
#>
function Parts([string]$v) {
    $o = @()
    foreach ($p in (($v -replace '^[vV]', '') -split '\.')) {
        $k = 0
        if (-not [int]::TryParse($p, [ref]$k)) { return $null }
        $o += $k
    }
    return , $o
}
function IsNewer([string]$remote, [string]$local) {
    if (-not $remote) { return $false }
    if (-not $local) { return $true }
    if ($remote -eq $local) { return $false }
    $a = Parts $remote; $bb = Parts $local
    if ($null -eq $a -or $null -eq $bb) { return ($remote -ne $local) }
    for ($i = 0; $i -lt [Math]::Max($a.Count, $bb.Count); $i++) {
        $x = if ($i -lt $a.Count) { $a[$i] } else { 0 }
        $y = if ($i -lt $bb.Count) { $bb[$i] } else { 0 }
        if ($x -ne $y) { return ($x -gt $y) }
    }
    return $false
}

<#
  One run of the block, with two feeds on disk.

  $current is what the CHECKED OUT branch's Updater.cs says, which is the
  value Ship reads before this block. Everything else the block touches is a
  path to a version.json, so both are written fresh per case.
#>
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('tsdevver-' + [Guid]::NewGuid().ToString('N'))
function Run([string]$branchVersion, [string]$mainFeed, [string]$devFeed) {
    $mainDir = Join-Path $tmp 'main'
    $devDir = Join-Path $tmp 'dev'
    foreach ($d in @($mainDir, $devDir)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    Set-Content -LiteralPath (Join-Path $mainDir 'version.json') -Value (@{ launcherVersion = $mainFeed } | ConvertTo-Json)
    Set-Content -LiteralPath (Join-Path $devDir 'version.json') -Value (@{ launcherVersion = $devFeed } | ConvertTo-Json)

    $sb = [scriptblock]::Create(
        '$current = $args[0]; $MainReleaseDir = $args[1]; $ReleaseDir = $args[2];' +
        'function Say($t, $c) { };' + $body + '; return $target')
    return & $sb $branchVersion $mainDir $devDir
}

try {
    # S1: THE CASE THAT HAPPENED. Branch behind main after a rollback.
    $t = Run '1.1.76' '1.1.77' '1.1.77'
    Yes "S1 a branch on 1.1.76 shipped while main has published 1.1.77 gives $t" ($t -eq '1.1.77.1')
    Yes 'S1 and a launcher already on 1.1.77 is offered it' (IsNewer $t '1.1.77')
    Yes 'S1 and a launcher on the old 1.1.76 is offered it too' (IsNewer $t '1.1.76')

    # S2: the ordinary case, dev shipped from main, must not change.
    $t = Run '1.1.77' '1.1.77' '1.1.77'
    Yes "S2 dev off main gives $t" ($t -eq '1.1.77.1')
    Yes 'S2 and it outranks main' (IsNewer $t '1.1.77')

    # S3: the climb. A second and third dev build on the same base.
    $t = Run '1.1.77' '1.1.77' '1.1.77.1'
    Yes "S3 a second dev build climbs to $t" ($t -eq '1.1.77.2')
    $t = Run '1.1.77' '1.1.77' '1.1.77.2'
    Yes "S3 and a third to $t" ($t -eq '1.1.77.3')

    # S4: main moving on restarts the count, which is the old behaviour kept.
    $t = Run '1.1.78' '1.1.78' '1.1.77.3'
    Yes "S4 main moving to 1.1.78 restarts dev at $t" ($t -eq '1.1.78.1')
    Yes 'S4 and a promoted main release still beats every dev build before it' (IsNewer '1.1.79' '1.1.78.9')

    # S5: a branch AHEAD of the published main is left alone. Ordinary work on
    #     a branch after a main release is exactly this shape.
    $t = Run '1.1.80' '1.1.77' '1.1.77.1'
    Yes "S5 a branch ahead of main keeps its own number: $t" ($t -eq '1.1.80.1')

    # S6: an unreadable main feed does not stop a dev release. Dev is where
    #     things get tried, so it fails open on the branch's own number.
    $sb = [scriptblock]::Create(
        '$current = $args[0]; $MainReleaseDir = $args[1]; $ReleaseDir = $args[2];' +
        'function Say($t, $c) { };' + $body + '; return $target')
    $t = & $sb '1.1.76' (Join-Path $tmp 'nothing-here') (Join-Path $tmp 'dev')
    Yes "S6 an unreadable main feed still produces a version above what dev has out: $t" ($t -eq '1.1.77.2')

    # S7: 25 SEPTEMBER. Djinn's releases clone was days old and said 1.1.92,
    #     so his dev Ship went out as 1.1.92.3 while dev launchers were on
    #     1.1.94.3. Both feeds are read off the origin now, and the number
    #     climbs past everything the dev branch ever published.
    $origin = Join-Path $tmp 'rel.git'; $seed = Join-Path $tmp 'relseed'; $stale = Join-Path $tmp 'relstale'
    & git init -q --bare -b main $origin
    & git init -q -b main $seed
    & git -C $seed config user.email t@t; & git -C $seed config user.name t
    function Put($v) { Set-Content -LiteralPath (Join-Path $seed 'version.json') -Value ('{' + [char]10 + '  "launcherVersion": "' + $v + '"' + [char]10 + '}'); & git -C $seed add -A; & git -C $seed commit -q -m $v }
    Put '1.1.92'
    & git -C $seed remote add origin $origin; & git -C $seed push -q origin main 2>$null
    & git clone -q $origin $stale 2>$null
    & git -C $seed checkout -q -b dev
    foreach ($v in '1.1.94.1', '1.1.94.2', '1.1.94.3', '1.1.92.3') { Put $v }
    & git -C $seed push -q origin dev 2>$null
    & git -C $seed checkout -q main; Put '1.1.94'; & git -C $seed push -q origin main 2>$null
    & git -C $stale fetch -q origin dev 2>$null
    & git -C $stale worktree add -q (Join-Path $tmp 'relstale-dev') origin/dev 2>$null
    $sb = [scriptblock]::Create(
        '$current = $args[0]; $MainReleaseDir = $args[1]; $ReleaseDir = $args[2];' +
        'function Say($t, $c) { };' + $body + '; return $target')
    $t = & $sb '1.1.92' $stale (Join-Path $tmp 'relstale-dev')
    Yes "S7 a stale releases clone and a dev feed that went back to 1.1.92.3 give $t" ($t -eq '1.1.94.4')
    Yes 'S7 and a dev launcher on 1.1.94.3 is offered it' (IsNewer $t '1.1.94.3')
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "$script:pass passed, $script:fail failed"
exit $(if ($script:fail) { 1 } else { 0 })
