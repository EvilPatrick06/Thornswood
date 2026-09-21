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

  COUNTING ROWS ON A RUNG IS NOT ENOUGH, WHICH WAS FOUND ON 21 SEPTEMBER. This
  script read the counts, found four rungs of the Enchanter/Bladebinder with 41,
  56, 40 and 24 recipes on them, and said every ladder was sound and exited 0.
  All 41 rows on that novice rung want a Heart Stone, and ores.json ranks all
  four Heart Stone deposits master, so a novice Bladebinder opens 41 recipes and
  can gather the makings for none of them. That is the same dead end as an empty
  rung wearing a label, and the label came from the second rule in
  Build-RecipeTable.ps1, which re-ranks a half by how long its shopping lists
  are when neither price nor input cost can tell its rows apart. So every rung
  is now checked for whether anybody standing on it could gather for even one
  row of it, and a half where that fails and is not written down in the table
  with a measured reason fails this script.

  It also follows a recipe to the class that produces its inputs, which it
  could not do until 21 September. tools\recipes.json records WHICH items each
  recipe wants now and not just how many: Build-RecipeTable.ps1 read the CNTO
  subrecords to count them and dropped the form ids, and it keeps them. Every
  owned row carries inputItems, each with the class that produces that item and
  the rank it is produced at, and inputRank, the dearest of them. So the chain
  report below is a number rather than a shape: how far each half's recipes sit
  from what their inputs cost, and every case more than one rung out.

  What is still out of reach is one more hop. Leather Strips, Steel Ingot and
  Leather are the three commonest inputs in the whole table and none of them
  comes out of the ground: each is made at a smelter or a tanning rack, which
  is itself a recipe, one of the 1679 nobody owns. Those rows are ranked by
  what they sell for and say so, and the limit is printed every run rather than
  left for somebody to discover.

  Read only. It opens five json files in this repository and writes nothing
  anywhere, and it does not touch the game folder or the VPS at all.

  Usage:
    .\tools\Check-Balance.ps1
    .\tools\Check-Balance.ps1 -Quiet     the verdict lines only

  Exit code 1 if any ladder has an empty rung below its top, or a rung nobody
  standing on it could gather for that the table has not already written down
  with a reason. Those are the two shapes that are always wrong.
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
    # The same rows again, kept rather than counted, because the standability
    # check below has to look at what each one asks for and a count cannot.
    $rowsOf = @{}
    foreach ($k in $recipes.recipes.PSObject.Properties.Name) {
        $row = $recipes.recipes.$k
        # A recipe the server is never asked about cannot be gated, so it is not
        # part of any ladder and counting it would flatter every half that has
        # a lot of tempering in it. The Platewright is the one this matters to:
        # 2015 recipes and only 771 the server ever sees.
        if ($row.PSObject.Properties.Name -contains 'fires' -and -not $row.fires) { continue }
        $half = [string]$row.owner + '/' + [string]$row.half
        if (-not $byHalf.ContainsKey($half)) { $byHalf[$half] = @{} }
        if (-not $rowsOf.ContainsKey($half)) { $rowsOf[$half] = New-Object 'System.Collections.Generic.List[object]' }
        $rank = [string]$row.rank
        if (-not $rank) { continue }
        if (-not $byHalf[$half].ContainsKey($rank)) { $byHalf[$half][$rank] = 0 }
        $byHalf[$half][$rank]++
        $rowsOf[$half].Add($row)
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

        # AND WHETHER ANYBODY CAN STAND ON THE RUNGS THAT DO HAVE ROWS ON THEM.
        # A row is standable at its rung when inputRank is null, meaning no
        # class rank stands between somebody and the makings, or when inputRank
        # is at or below that rung. A rung whose every row fails that is the
        # Bladebinder case in the header: a rank you reach, a list of recipes it
        # opens, and not one of them you can gather for.
        #
        # The table itself names the halves somebody has decided to live with,
        # in rungsNobodyCanGatherFor with the reason beside it, and
        # Build-RecipeTable.ps1 refuses to write a table with any half that is
        # not named. That is the same arrangement cannotCraftYet has: a decision
        # written down beats a check quietly passing, and a half that turns up
        # here without one is a fault in whoever changed the ranking.
        $known = ''
        if ($recipes.PSObject.Properties.Name -contains 'halves' -and
            $recipes.halves.PSObject.Properties.Name -contains $half) {
            $hv = $recipes.halves.$half
            if ($hv.PSObject.Properties.Name -contains 'rungsNobodyCanGatherFor') {
                $known = [string]$hv.rungsNobodyCanGatherFor
            }
        }
        $unstandable = @()
        foreach ($r in $RANKS) {
            $on = 0
            $can = 0
            $need = ''
            foreach ($row in $rowsOf[$half]) {
                if ([string]$row.rank -ne $r) { continue }
                $on++
                $ir = [string]$row.inputRank
                if (-not $ir) { $can++; continue }
                if ([array]::IndexOf($RANKS, $ir) -le [array]::IndexOf($RANKS, $r)) { $can++; continue }
                if (-not $need) { $need = $ir + ' work from a ' + [string]$row.inputRankWho }
            }
            if ($on -eq 0 -or $can -gt 0) { continue }
            $unstandable += ('{0} ({1} recipe(s), every one wanting {2})' -f $r, $on, $need)
        }
        # One line per half and not one per rung. The Bladebinder fails on three
        # rungs for the same reason and printing that reason three times buries
        # the halves underneath it.
        if ($unstandable.Count -gt 0) {
            if ($known) {
                Note ("{0}: nobody standing on these rungs can gather for anything they open: {1}. The table names this half itself and says why, so it is a decision rather than a fault." -f `
                      $half, ($unstandable -join '; '))
            } else {
                Bad ("{0}: nobody standing on these rungs can gather for anything they open: {1}. Reaching that rank opens nothing anybody there can make, and nothing in the table says this was decided." -f `
                     $half, ($unstandable -join '; '))
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

Head 'The chain: what a recipe asks for against what it is ranked at'

# THIS IS THE ANSWER TO PATRICK'S QUESTION, AS A NUMBER.
#
# Every owned row of recipes.json now carries inputItems, each with the class
# that produces it and the rank that class gets it at, and inputRank, which is
# the dearest of those. Comparing inputRank against the row's own rank says
# exactly how far a profession's ladder sits from the ladders that feed it.
#
# A row whose rank matches its inputRank is in step: you can gather the makings
# on the same rung you are allowed to use them. A row ranked BELOW what its
# inputs cost is the dead end that started all of this, a novice Hearthcook
# handed a recipe wanting a crop only an expert Farmer may grow. A row ranked
# ABOVE what its inputs cost is the other kind of waste: the makings are in
# your pack and the bench still refuses you.
#
# Only the rows the server is asked about are counted, for the same reason the
# ladder counts above skip tempering: a row the gate is never asked about
# cannot be in step or out of it with anything.
if ($recipes) {
    $inStep = 0; $outStep = 0; $noChain = 0; $far = @()
    $perHalf = @{}
    foreach ($k in $recipes.recipes.PSObject.Properties.Name) {
        $row = $recipes.recipes.$k
        if ($row.PSObject.Properties.Name -contains 'fires' -and -not $row.fires) { continue }
        $half = [string]$row.owner + '/' + [string]$row.half
        if (-not $perHalf.ContainsKey($half)) {
            $perHalf[$half] = [pscustomobject]@{ Chained = 0; Loose = 0; Sum = 0; Worst = 0; InStep = 0 }
        }
        $ir = [string]$row.inputRank
        if (-not $ir) { $noChain++; $perHalf[$half].Loose++; continue }
        $a = [array]::IndexOf($RANKS, [string]$row.rank)
        $b = [array]::IndexOf($RANKS, $ir)
        if ($a -lt 0 -or $b -lt 0) { $noChain++; $perHalf[$half].Loose++; continue }
        $gap = $a - $b
        $perHalf[$half].Chained++
        $perHalf[$half].Sum += [Math]::Abs($gap)
        if ([Math]::Abs($gap) -gt $perHalf[$half].Worst) { $perHalf[$half].Worst = [Math]::Abs($gap) }
        if ($gap -eq 0) { $inStep++; $perHalf[$half].InStep++ } else { $outStep++ }
        if ([Math]::Abs($gap) -gt 1) {
            # Which input it was. The row carries inputRank as the dearest of
            # them; this finds the one that set it, so the line names a thing
            # rather than a rank.
            $dearest = ''
            foreach ($it in $row.inputItems) {
                if ([string]$it.producedAt -eq $ir) { $dearest = [string]$it.name; break }
            }
            if (-not $dearest) { $dearest = 'what it asks for' }
            $which = 'above'
            if ($gap -lt 0) { $which = 'below' }
            $far += ('{0}: {1} is ranked {2} and its dearest input, {3}, is {4} work for a {5}. {6} rung(s) {7} what it costs.' -f `
                     $half, [string]$row.name, [string]$row.rank, $dearest, $ir, [string]$row.inputRankWho, [Math]::Abs($gap), $which)
        }
    }

    if ($perHalf.Count -eq 0) {
        Note 'no recipe row carries inputItems yet, so rebuild the table with tools\Build-RecipeTable.ps1 and run this again'
    } else {
        foreach ($half in ($perHalf.Keys | Sort-Object)) {
            $h = $perHalf[$half]
            $tot = $h.Chained + $h.Loose
            if ($h.Chained -eq 0) {
                Say ('  {0}  {1} row(s), and NOT ONE of them asks for anything a class in this world produces, so there is no chain to read here at all' -f $half.PadRight(24), $tot)
                continue
            }
            $avg = [Math]::Round(($h.Sum / [double]$h.Chained), 2)
            Say ('  {0}  {1} of {2} row(s) have a producer behind them: {3} sit exactly on what their inputs cost, average gap {4} rung(s), worst {5}' -f `
                 $half.PadRight(24), $h.Chained, $tot, $h.InStep, $avg, $h.Worst)
        }
        Say ''
        Say ('  {0} row(s) are in step with what their inputs cost, {1} are not, and {2} ask for nothing any class produces.' -f $inStep, $outStep, $noChain)
    }

    # More than one rung apart is the imbalance worth a name. One rung is the
    # ranking rules rounding against each other; two or more means somebody
    # reaches a rank and the work it opens is either already in their pack or
    # still out of their reach.
    #
    # It does NOT set the exit code. An empty rung is always wrong and this
    # script exits 1 for it; a recipe out of step with its inputs is a thing
    # somebody has to decide about, and a script that refused to finish over it
    # would be refusing to report the rest.
    if ($far.Count -gt 0) {
        Note ("{0} recipe(s) are more than one rung away from what their inputs cost" -f $far.Count)
        foreach ($f in ($far | Select-Object -First 10)) { Note ('  ' + $f) }
        if ($far.Count -gt 10) { Note ("  ... and {0} more, every one of them in tools\recipes.json with its inputItems" -f ($far.Count - 10)) }
    } else {
        Ok 'no recipe is more than one rung away from what its inputs cost'
    }
}

Head 'Where a profession sits below the class that grows what it asks for'

# THE OTHER HALF OF PATRICK'S QUESTION, AND THE HALF THAT WAS MISSING.
#
# The chain above reads inputRank, which is what an input costs at the CHEAPEST
# class that produces it, because that is what a recipe costs to gather for. It
# cannot see the class that has to climb furthest for the same item, and for the
# Farmer that is every item: all 11 crops in harvests.json are also plants a
# gatherer picks at the same rank or lower, so the farmer sets no inputRank
# anywhere in the table and was invisible in this report until 21 September.
#
# alsoProducedBy on an input names every class that has to be higher up its own
# ladder for the same thing. A Cook row ranked below one of those is the
# imbalance in Patrick's own words, farmer against cook, stated as a row and a
# rank rather than as a feeling.
#
# It does NOT set the exit code, for the reason the chain gaps do not: which of
# the two ladders should move is a decision, and a Confectioner baking with an
# apple a gatherer picked at novice is defensible whatever rank the farmer who
# grows one has to hold.
if ($recipes) {
    $cross = @{}
    $crossSaid = New-Object 'System.Collections.Generic.List[string]'
    $crossRows = 0
    foreach ($k in $recipes.recipes.PSObject.Properties.Name) {
        $row = $recipes.recipes.$k
        if ($row.PSObject.Properties.Name -contains 'fires' -and -not $row.fires) { continue }
        $at = [array]::IndexOf($RANKS, [string]$row.rank)
        if ($at -lt 0) { continue }
        $worst = -1
        $worstWho = ''
        $worstWhat = ''
        foreach ($it in $row.inputItems) {
            if (-not ($it.PSObject.Properties.Name -contains 'alsoProducedBy')) { continue }
            foreach ($other in $it.alsoProducedBy) {
                $oAt = [array]::IndexOf($RANKS, [string]$other.at)
                if ($oAt -le $at) { continue }
                if ($oAt -gt $worst) { $worst = $oAt; $worstWho = [string]$other.who; $worstWhat = [string]$it.name }
            }
        }
        if ($worst -lt 0) { continue }
        $crossRows++
        $pair = ([string]$row.owner + '/' + [string]$row.half + ' against the ' + $worstWho)
        if (-not $cross.ContainsKey($pair)) { $cross[$pair] = 0 }
        $cross[$pair]++
        if ($crossSaid.Count -lt 8) {
            $crossSaid.Add(('{0} is ranked {1} and wants {2}, which a {3} has to be {4} to produce' -f `
                            [string]$row.name, [string]$row.rank, $worstWhat, $worstWho, $RANKS[$worst]))
        }
    }
    if ($crossRows -eq 0) {
        Ok 'no recipe the server is asked about is ranked below a class that has to climb higher for something on its list'
    } else {
        Note ("{0} recipe(s) the server is asked about are ranked below a class that has to climb higher for something they ask for" -f $crossRows)
        foreach ($pair in ($cross.Keys | Sort-Object { -$cross[$_] })) { Note ('  {0,5}  {1}' -f $cross[$pair], $pair) }
        foreach ($s in $crossSaid) { Note ('  ' + $s) }
        if ($crossRows -gt $crossSaid.Count) {
            Note ("  ... and {0} more, every one of them in tools\recipes.json under alsoProducedBy" -f ($crossRows - $crossSaid.Count))
        }
    }
}

Head 'What this still cannot answer'
Say '  What a smelter and a tanning rack cost. Leather Strips are wanted by 924 recipes,'
Say '  Steel Ingot by 888 and Leather by 665, and not one of the three comes out of the'
Say '  ground: they come out of a recipe in the same table, one of the 1679 unowned rows'
Say '  anybody may make. Following that one extra hop is what would put the Smith''s'
Say '  ladder against the Miner''s. Until it is done those rows are ranked by what they'
Say '  sell for, they say so in their rankFrom field, and they are the rows counted'
Say '  above as asking for nothing any class produces.'

Write-Host ''
if ($script:fail -gt 0) {
    Write-Host ("{0} ladder problem(s). Every one of them is a rung somebody cannot climb." -f $script:fail) -ForegroundColor Red
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 1
}
# WHAT THIS LINE MAY CLAIM IS WHAT WAS CHECKED. It used to say every ladder had
# a bottom rung and nothing above an empty one, which was true of the counts and
# false of the Bladebinder, whose bottom rung held 41 recipes nobody at that rank
# could gather for. A green line that says more than the checks above did is
# worse than no line, because it is the sentence somebody reads instead of the
# output.
Write-Host 'every ladder has a bottom rung, nothing above an empty one, and every rung that holds work holds something' -ForegroundColor Green
Write-Host 'somebody at that rank could gather for, except where the table names the half and says why.' -ForegroundColor Green
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
