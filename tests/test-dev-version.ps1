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
# Scripts this runs whole go to a stand-in box, so the freshness guard lets them be (#2118).
$env:THORNSWOOD_HARNESS = '1'

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
$ast = [Management.Automation.Language.Parser]::ParseFile($ShipPath, [ref]$null, [ref]$null)
$guard = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Assert-DevVersionSelection' }, $true)
Invoke-Expression $guard.Extent.Text
function Die($text) { throw $text }

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
  One run of the block, against the feeds as the real Feed-Store.ps1 reads
  them. Since #907 (28 September) the block reads what is published through
  Read-SiteFeed and Get-FeedStoreLaunchers, not the version.json files in a
  releases clone, and Feed-Store.ps1 takes THORNSWOOD_TEST_SITE_DIR as the
  VPS's feed folders on disk, so this runs exactly what Ship runs:
    <site>\feed\version.json            what main has published
    <site>\feed-dev\version.json        what dev has out now
    <site>\feed-dev\launchers.txt       every dev number ever published
  and the copy last received on this machine, which Read-Published falls back
  to when the site has no answer, is LOCALAPPDATA\Thornswood\feed\<channel>,
  pointed here at a folder of the harness's own so the machine's copy is
  never read.

  $current is what the CHECKED OUT branch's Updater.cs says, which is the
  value Ship reads before this block. An empty feed argument leaves that file
  out.
#>
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('tsdevver-' + [Guid]::NewGuid().ToString('N'))
. (Join-Path (Split-Path -Parent $ShipPath) 'Feed-Store.ps1')
$oldSite = $env:THORNSWOOD_TEST_SITE_DIR
$oldLocal = $env:LOCALAPPDATA
$script:runN = 0
function Put-Feed([string]$dir, [string]$v) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Set-Content -LiteralPath (Join-Path $dir 'version.json') -Value (@{ launcherVersion = $v } | ConvertTo-Json)
}
function Run([string]$branchVersion, [string]$mainFeed, [string]$devFeed, [string[]]$devEver = @(), [string]$mainCopy = '', [bool]$aligned = $false, [string]$devCopy = '') {
    $script:runN++
    $site = Join-Path $tmp ('site' + $script:runN)
    $local = Join-Path $tmp ('local' + $script:runN)
    New-Item -ItemType Directory -Force -Path (Join-Path $site 'feed'), (Join-Path $site 'feed-dev'), $local | Out-Null
    if ($mainFeed) { Put-Feed (Join-Path $site 'feed') $mainFeed }
    if ($devFeed) { Put-Feed (Join-Path $site 'feed-dev') $devFeed }
    if ($devEver.Count) { Set-Content -LiteralPath (Join-Path $site 'feed-dev\launchers.txt') -Value $devEver -Encoding ASCII }
    if ($mainCopy) { Put-Feed (Join-Path $local 'Thornswood\feed\main') $mainCopy }
    if ($devCopy) { Put-Feed (Join-Path $local 'Thornswood\feed\dev') $devCopy }
    $env:THORNSWOOD_TEST_SITE_DIR = $site
    $env:LOCALAPPDATA = $local
    try {
        $sb = [scriptblock]::Create('$current = $args[0]; $MainSourceAligned = $args[1]; $MainEquivalent = $args[1]; function Say($t, $c) { }; function Die($t) { throw $t };' + $body + '; Assert-DevVersionSelection $target $current $MainSourceAligned (@($seen) + @($mainWas)); return $target')
        return & $sb $branchVersion $aligned
    }
    finally { $env:THORNSWOOD_TEST_SITE_DIR = $oldSite; $env:LOCALAPPDATA = $oldLocal }
}

try {
    # S1: THE CASE THAT HAPPENED. Branch behind main after a rollback.
    $t = Run '1.1.76' '1.1.77' '1.1.77'
    Yes "S1 a branch on 1.1.76 shipped while main has published 1.1.77 gives $t" ($t -eq '1.1.77.1')
    Yes 'S1 and a launcher already on 1.1.77 is offered it' (IsNewer $t '1.1.77')
    Yes 'S1 and a launcher on the old 1.1.76 is offered it too' (IsNewer $t '1.1.76')

    # S2: main's own launcher keeps the same version in both feeds. The flag
    #     here stands for Get-DevLauncherLine's answer; which clean checkouts
    #     of origin/main get it is tests	est-2347-dev-launcher-version.ps1.
    $t = Run '1.1.105' '1.1.105' '1.1.104.1' @('1.1.104.1') '' $true
    Yes "S2 clean Main source aligns Dev on $t" ($t -eq '1.1.105')
    Yes 'S2 an older Dev launcher is offered the aligned version' (IsNewer $t '1.1.104.1')
    $t = Run '1.1.105' '1.1.105' '1.1.105' @('1.1.105') '' $true
    Yes 'S2 another pack from identical Main source retains 1.1.105' ($t -eq '1.1.105')
    $refused = $false
    try { $null = Run '1.1.104' '1.1.104' '1.1.104.1' @('1.1.104.1') '' $true } catch { $refused = $true }
    Yes 'S2 alignment refuses a downgrade and requires a higher Main version' $refused
    $refused = $false
    try { Assert-DevVersionSelection '1.1.104' '1.1.104' $true @('1.1.104.1') } catch { $refused = $true }
    Yes 'S2 an explicit version cannot bypass the published Dev floor' $refused
    $refused = $false
    try { Assert-DevVersionSelection '1.1.105.1' '1.1.105' $true @('1.1.104.1') } catch { $refused = $true }
    Yes 'S2 an explicit suffix cannot split a Main-equivalent release' $refused
    $refused = $false
    try { $null = Run '1.1.105' '' '' @() '1.1.106' $true } catch { $refused = $true }
    Yes 'S2 cached higher Main evidence still prevents downgrade when the site is unreadable' $refused
    $refused = $false
    try { $null = Run '1.1.105' '' '' @() '' $true '1.1.106.1' } catch { $refused = $true }
    Yes 'S2 cached higher Dev evidence still prevents downgrade when the site is unreadable' $refused
    # A genuinely separate Dev branch still uses the fourth number.
    $t = Run '1.1.77' '1.1.77' '1.1.77'
    Yes "S2 separate Dev work gives $t" ($t -eq '1.1.77.1')
    Yes 'S2 separate Dev work outranks its Main base' (IsNewer $t '1.1.77')

    # S3: the climb. A second and third dev build on the same base.
    $t = Run '1.1.77' '1.1.77' '1.1.77.1' @('1.1.77.1')
    Yes "S3 a second dev build climbs to $t" ($t -eq '1.1.77.2')
    $t = Run '1.1.77' '1.1.77' '1.1.77.2' @('1.1.77.1', '1.1.77.2')
    Yes "S3 and a third to $t" ($t -eq '1.1.77.3')

    # S4: main moving on restarts the count, which is the old behaviour kept.
    $t = Run '1.1.78' '1.1.78' '1.1.77.3' @('1.1.77.1', '1.1.77.2', '1.1.77.3')
    Yes "S4 main moving to 1.1.78 restarts dev at $t" ($t -eq '1.1.78.1')
    Yes 'S4 and a promoted main release still beats every dev build before it' (IsNewer '1.1.79' '1.1.78.9')

    # S5: a branch AHEAD of the published main is left alone. Ordinary work on
    #     a branch after a main release is exactly this shape.
    $t = Run '1.1.80' '1.1.77' '1.1.77.1' @('1.1.77.1')
    Yes "S5 a branch ahead of main keeps its own number: $t" ($t -eq '1.1.80.1')

    # S6: a main feed that cannot be read stops a dev release before anything
    #     is built (Patrick, 19 Oct, #2711 decision 1 B). It used to fail open
    #     on the branch's own number, which could land below main's.
    $refused = $false
    try { $null = Run '1.1.76' '' '1.1.77.1' @('1.1.77.1') } catch { $refused = $true }
    Yes 'S6 a main feed that cannot be read stops the dev Ship' $refused
    # S6b (#2711): the copy received here is there and does not read, and the
    # site has no answer. It stops, as S6, and says why (this was a try with
    # an empty catch, then a yellow line that went on).
    $site = Join-Path $tmp 'site-s6b'; $local = Join-Path $tmp 'local-s6b'
    New-Item -ItemType Directory -Force -Path (Join-Path $site 'feed'), (Join-Path $site 'feed-dev'), (Join-Path $local 'Thornswood\feed\main') | Out-Null
    Put-Feed (Join-Path $site 'feed-dev') '1.1.77.1'
    Set-Content -LiteralPath (Join-Path $site 'feed-dev\launchers.txt') -Value @('1.1.77.1') -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $local 'Thornswood\feed\main\version.json') -Value '{ "launcherVersion": '
    $env:THORNSWOOD_TEST_SITE_DIR = $site; $env:LOCALAPPDATA = $local
    $script:s6said = @()
    $s6stop = ''
    try {
        $sb = [scriptblock]::Create('$current = $args[0]; $MainSourceAligned = $false; $MainEquivalent = $false; function Say($t, $c) { $script:s6said += $t }; function Die($t) { throw $t };' + $body + '; return $target')
        $null = & $sb '1.1.76'
    } catch { $s6stop = $_.Exception.Message } finally { $env:THORNSWOOD_TEST_SITE_DIR = $oldSite; $env:LOCALAPPDATA = $oldLocal }
    Yes 'S6b a main copy here that does not read stops the dev Ship' ([bool]$s6stop)
    Yes '  and says it could not read what main has published, and that nothing was built' ($s6stop -match '(?s)Could not read what main has published \(.+\), so the dev number could land below main''s\. Nothing was built\.')

    # S7: 25 SEPTEMBER. Djinn's releases clone was days old and said 1.1.92,
    #     so his dev Ship went out as 1.1.92.3 while dev launchers were on
    #     1.1.94.3. Main's number is the site's feed now, and the dev number
    #     climbs past every one the dev store has ever published, even with
    #     the dev feed itself gone back to 1.1.92.3 and this machine's last
    #     copy of main still saying 1.1.92.
    $t = Run '1.1.92' '1.1.94' '1.1.92.3' @('1.1.94.1', '1.1.94.2', '1.1.94.3', '1.1.92.3') '1.1.92'
    Yes "S7 a stale copy here and a dev feed that went back to 1.1.92.3 give $t" ($t -eq '1.1.94.4')
    Yes 'S7 and a dev launcher on 1.1.94.3 is offered it' (IsNewer $t '1.1.94.3')

    # S8: the site has no main feed to give, so the copy last received here is
    #     used, and it still lifts a branch that is behind.
    $t = Run '1.1.76' '' '1.1.77' @() '1.1.77'
    Yes "S8 with no main feed on the site, the copy here (1.1.77) is the base: $t" ($t -eq '1.1.77.1')
}
finally {
    $env:THORNSWOOD_TEST_SITE_DIR = $oldSite
    $env:LOCALAPPDATA = $oldLocal
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# ---- #2035: Updater.cs is written back with no byte order mark ------------
# Ship writes Updater.cs for the bump, Unbump and the dev put-back. With
# Set-Content -Encoding UTF8 that added a mark in Windows PowerShell 5.1 and
# none in PowerShell 7, so a 5.1 Ship left the file changed in git by three
# bytes. CI runs PowerShell 7, where Set-Content would pass a byte check, so
# the script's own text is checked as well as the write.
Yes 'Ship.ps1 never writes Updater.cs with Set-Content (#2035)' (-not ($src -match 'Set-Content\s+\$updaterCs'))
$wm = [regex]::Match($src, '(?s)function Write-UpdaterCs\(\[string\]\$text\) \{.*?\r?\n\}')
Yes 'Ship.ps1 has one writer for Updater.cs, Write-UpdaterCs' $wm.Success
Yes 'and the bump, Unbump and the dev put-back all go through it' (([regex]::Matches($src, 'Write-UpdaterCs \$(src|back)')).Count -eq 3)
if ($wm.Success) {
    $bomTmp = Join-Path ([IO.Path]::GetTempPath()) ('tw-2035-' + [Guid]::NewGuid().ToString('N') + '.cs')
    try {
        $updaterCs = $bomTmp
        . ([ScriptBlock]::Create($wm.Value))
        $text = "using System;`r`n    public const string Version = `"1.2.0.1`";`r`n"
        Write-UpdaterCs $text
        $bytes = [IO.File]::ReadAllBytes($bomTmp)
        Yes 'the file it writes starts with no byte order mark' (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF))
        Yes 'and holds exactly the text given, with no newline added' ([Text.Encoding]::UTF8.GetString($bytes) -ceq $text)
    }
    finally { Remove-Item -LiteralPath $bomTmp -Force -ErrorAction SilentlyContinue }
}

Write-Host ''
Write-Host "$script:pass passed, $script:fail failed"
exit $(if ($script:fail) { 1 } else { 0 })
