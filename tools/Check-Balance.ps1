<#
  Check-Balance.ps1

  Reads the five generated tables and says whether the ladders line up.

  WHY

  Patrick, 21 September: "we also need to make sure the different tiers match
  across so like farmer matches with tiers of cook for their recipes, miner and
  smith, woodworker and miner and so on, so there isn't an imbalance".

  He is right and it is checkable rather than a matter of taste. Every class
  produces things at a rank and every profession consumes them at a rank, and
  the two ladders are built by different scripts using different rules against
  different records. Nothing has ever compared them. A novice Hearthcook whose
  first recipe needs a crop only an expert Farmer may grow is a dead end that
  neither table can see on its own, because each one is internally consistent.

  WHAT IT CAN SAY TODAY, AND WHAT IT CANNOT

  It compares the SHAPE of every ladder: how many things sit on each rung, and
  whether any rung is empty. An empty bottom rung is the failure that has now
  been shipped twice here, once in farming and once in gathering, and both times
  it meant a new character could do nothing at all and had no way to earn the
  rank that would have let them.

  It CANNOT yet follow a single recipe to the class that produces its inputs.
  tools\recipes.json records how MANY inputs a recipe has and not WHICH: the
  CNTO subrecords are read by the build script to count them and then dropped.
  Carrying the form ids through is a small change to a script that already has
  them in its hands, and until that is done this reports the shape rather than
  the chain. That limit is printed every run rather than left for somebody to
  discover.

  Read only. It opens five json files in this repository and writes nothing
  anywhere, and it does not touch the game folder or the VPS at all.

  Usage:
    .\tools\Check-Balance.ps1
    .\tools\Check-Balance.ps1 -Quiet     the verdict lines only

  Exit code 1 if any ladder has an empty rung below its top, because that is the
  one shape that is always wrong.
#>
[CmdletBinding()]
param(
    [string]$Repo = '',
    [switch]$Quiet,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $Repo) { $Repo = Split-Path -Parent $Here }

function Head($m) { if (-not $Quiet) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray } }
function Say($m, $c = 'Gray') { if (-not $Quiet) { Write-Host $m -ForegroundColor $c } }
function Ok($m)   { Write-Host ('  ok    ' + $m) -ForegroundColor Green }
function Bad($m)  { Write-Host ('  BAD   ' + $m) -ForegroundColor Red; $script:fail++ }
function Note($m) { Write-Host ('  note  ' + $m) -ForegroundColor Yellow }

$script:fail = 0
$RANKS = @('novice', 'advanced', 'expert', 'master')

function Load($name) {
    $p = Join-Path $Here $name
    if (-not (Test-Path -LiteralPath $p)) {
        Note "$name is not built yet, so the ladder it holds is not checked. Build it and run this again."
        return $null
    }
    try { return (Get-Content -LiteralPath $p -Raw | ConvertFrom-Json) }
    catch { Bad "$name does not parse: $($_.Exception.Message)"; return $null }
}

# Counts a map of rows by their rank field and reports the shape.
function Ladder($what, $map, $who) {
    if (-not $map) { return }
    $by = @{}
    foreach ($r in $RANKS) { $by[$r] = 0 }
    $n = 0
    foreach ($k in $map.PSObject.Properties.Name) {
        $row = $map.$k
        $rank = [string]$row.rank
        if (-not $rank) { continue }
        if ($by.ContainsKey($rank)) { $by[$rank]++ } else { $by[$rank] = 1 }
        $n++
    }
    if ($n -eq 0) { Note "$what has no rows with a rank on them"; return }

    $line = ($RANKS | ForEach-Object { '{0} {1}' -f $_, $by[$_] }) -join ', '
    Say ('  {0}  {1} rows: {2}' -f $what.PadRight(22), $n, $line)

    # The rule: a rung may be empty only if every rung above it is empty too.
    # An empty rung with something above it is a wall, and a wall at the bottom
    # is a character who can never start.
    $seenAbove = $false
    for ($i = $RANKS.Count - 1; $i -ge 0; $i--) {
        $r = $RANKS[$i]
        if ($by[$r] -gt 0) { $seenAbove = $true; continue }
        if ($seenAbove) {
            if ($i -eq 0) {
                Bad ("{0}: the NOVICE rung is empty and there are {1} rows above it, so a new {2} can do nothing at all and has no way to earn the rank that would let them" -f $what, $n, $who)
            } else {
                Bad ("{0}: the {1} rung is empty with rows above it, so that rank gives nothing and the next one is unreachable by doing the work" -f $what, $r)
            }
        }
    }
    return $by
}

Head 'What produces'

$ores     = Load 'ores.json'
$harvests = Load 'harvests.json'
$hunts    = Load 'hunts.json'

$shape = @{}
if ($ores)     { $shape['miner']    = Ladder 'Miner, ore veins'      $ores.ores      'miner' }
if ($harvests) { $shape['gatherer'] = Ladder 'Gatherer, plants'      $harvests.harvests 'gatherer' }
if ($harvests) { $shape['farmer']   = Ladder 'Farmer, crops'         $harvests.crops 'farmer' }
if ($harvests -and $harvests.PSObject.Properties.Name -contains 'fish') {
                 $shape['fisher']   = Ladder 'Fisher, water'         $harvests.fish  'fisher' }
if ($hunts)    { $shape['hunter']   = Ladder 'Hunter, animals'       $hunts.hunts    'hunter' }

Head 'What consumes'

$recipes = Load 'recipes.json'
if ($recipes) {
    $byHalf = @{}
    foreach ($k in $recipes.recipes.PSObject.Properties.Name) {
        $row = $recipes.recipes.$k
        # A recipe the server is never asked about cannot be gated, so it is not
        # part of any ladder and counting it would flatter every half that has
        # a lot of tempering in it. The Platewright is the one this matters to:
        # 2015 recipes and only 771 the server ever sees.
        if ($row.PSObject.Properties.Name -contains 'fires' -and -not $row.fires) { continue }
        $half = [string]$row.owner + '/' + [string]$row.half
        if (-not $byHalf.ContainsKey($half)) { $byHalf[$half] = @{} }
        $rank = [string]$row.rank
        if (-not $rank) { continue }
        if (-not $byHalf[$half].ContainsKey($rank)) { $byHalf[$half][$rank] = 0 }
        $byHalf[$half][$rank]++
    }

    $empties = @()
    foreach ($half in ($byHalf.Keys | Sort-Object)) {
        $by = $byHalf[$half]
        $tot = 0; foreach ($r in $RANKS) { if ($by.ContainsKey($r)) { $tot += $by[$r] } }
        $line = ($RANKS | ForEach-Object { '{0} {1}' -f $_, ($(if ($by.ContainsKey($_)) { $by[$_] } else { 0 })) }) -join ', '
        Say ('  {0}  {1} recipes the server is asked about: {2}' -f $half.PadRight(24), $tot, $line)
        # The SAME rung rule the producing ladders get, and the first run of this
        # script proved why it has to be here too: the Confectioner came out
        # 18 novice, 0 advanced, 10 expert, and the old check only looked at the
        # bottom rung so it said nothing. A hole in the middle is a rank that
        # gives you nothing new, which is the imbalance Patrick asked about,
        # just one rung further up than the one that has bitten us before.
        if ($tot -gt 0) {
            $seenAbove = $false
            for ($i = $RANKS.Count - 1; $i -ge 0; $i--) {
                $r = $RANKS[$i]
                $c = $(if ($by.ContainsKey($r)) { $by[$r] } else { 0 })
                if ($c -gt 0) { $seenAbove = $true; continue }
                if (-not $seenAbove) { continue }
                if ($i -eq 0) {
                    Bad ("{0}: no novice recipe, so somebody who picks that half can make nothing on their first day" -f $half)
                } else {
                    Bad ("{0}: nothing at {1} with {2} recipe(s) above it, so reaching that rank opens nothing" -f $half, $r, ($tot - $c))
                }
            }
        }
    }

    # The five that own nothing are a measured fact rather than a hole, and the
    # table says so itself. They are reported so nobody reads a zero as a bug,
    # and so that anybody building a panel knows not to promise them anything.
    if ($recipes.PSObject.Properties.Name -contains 'cannotCraftYet') {
        Head 'Halves that gate nothing, and why'
        foreach ($k in $recipes.cannotCraftYet.PSObject.Properties.Name) {
            Say ('  ' + $k)
            Say ('      ' + ([string]$recipes.cannotCraftYet.$k).Substring(0, [Math]::Min(150, ([string]$recipes.cannotCraftYet.$k).Length)))
        }
    }
}

Head 'Where the ladders disagree'

# The comparison that can be made without the inputs: the SHAPE. A class whose
# ladder is almost all one rung cannot feed a profession whose ladder is spread
# over four, because there is nothing at the ranks the profession is asking for.
if ($shape.Count) {
    $thin = @()
    foreach ($who in ($shape.Keys | Sort-Object)) {
        $by = $shape[$who]
        if (-not $by) { continue }
        $tot = 0; foreach ($r in $RANKS) { $tot += $by[$r] }
        if ($tot -eq 0) { continue }
        $top = 0; foreach ($r in $RANKS) { if ($by[$r] -gt $top) { $top = $by[$r] } }
        $share = [Math]::Round(100.0 * $top / $tot)
        if ($share -ge 60) { $thin += ('{0} ({1}% of it on one rung, {2} rows in all)' -f $who, $share, $tot) }
    }
    if ($thin.Count) {
        Note ('these ladders are lopsided, which is what an imbalance looks like before anybody plays it: ' + ($thin -join '; '))
    } else {
        Ok 'no producing ladder is piled onto a single rung'
    }
}

Head 'What this cannot answer yet'
Say '  Which class produces the inputs of any given recipe.'
Say '  tools\recipes.json records how many inputs a recipe has and not which, because'
Say '  the build script reads the CNTO subrecords to count them and then drops the ids.'
Say '  Carrying them through is a small change to a script that already holds them, and'
Say '  until then this reports the shape of each ladder rather than the chain between two.'

Write-Host ''
if ($script:fail -gt 0) {
    Write-Host ("{0} ladder problem(s). Every one of them is a rung somebody cannot climb." -f $script:fail) -ForegroundColor Red
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 1
}
Write-Host 'every ladder has a bottom rung and nothing above an empty one.' -ForegroundColor Green
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
