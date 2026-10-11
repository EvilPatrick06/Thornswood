<#
  test-start-screen-art.ps1

  The sealed scroll's pictures ride in every pack that carries the start
  screen's page. Issue #883.

  WHAT HAPPENED. Djinn, 28 September, on the Main launcher: the first start
  after the update went straight to the character slots, with no scroll.
  thornswood-select.js puts the scroll up first and, if either of its two
  pictures does not load, takes it down again with "a scroll picture is
  missing, straight to the slots". Every one of the 75 packs on the Main feed
  was listed on 28 September and not one carries thornswood-scroll.webp or
  thornswood-scroll-open.webp, while the Main pack baseline (published.json)
  lists both as published since 25 September 17:54 UTC: Main update
  20260925-1654 recorded them and was pulled from version.json four minutes
  later, and the baseline kept them. An install that only ever took packs has
  the page and not its pictures. The dev feed carries them (20260927-2226-dev
  on), which is why the dev build shows the scroll.

  So Ship-Rules.ps1 names the pictures that travel with the page
  ($ShipTravelsWith), and Publish-Update.ps1 adds them to any pack that
  carries the page. This holds the list to the pictures the page itself names,
  runs Get-ShipTravelsWith, and runs the block lifted out of the shipped
  Publish-Update.ps1 between its markers.

  Read only.
#>
[CmdletBinding()]
param([string]$RepoRoot)
# Scripts this runs whole go to a stand-in box, so the freshness guard lets them be (#2118).
$env:THORNSWOOD_HARNESS = '1'

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent $Here }

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

$rules   = Join-Path $RepoRoot 'scripts/release/Ship-Rules.ps1'
$publish = Join-Path $RepoRoot 'scripts/release/Publish-Update.ps1'
$select  = Join-Path $RepoRoot 'game/ui/thornswood-select.js'
$ui      = Join-Path $RepoRoot 'game/ui'

. $rules
$pageKey = 'Data\Platform\UI\thornswood-select.js'

# ---- the cause: a missing picture takes the scroll down ----------------------
$page = [IO.File]::ReadAllText($select)
Yes 'the page still answers a missing picture by going straight to the slots' ($page.IndexOf("introEnd('a scroll picture is missing, straight to the slots')") -ge 0)

# ---- the list is the pictures the page names ---------------------------------
Yes 'Ship-Rules has $ShipTravelsWith with the page as a key' ((Get-Variable ShipTravelsWith -EA SilentlyContinue) -and $ShipTravelsWith.ContainsKey($pageKey))
$named = @([regex]::Matches($page, 'src="(thornswood-[A-Za-z0-9-]+\.(?:webp|png|jpg|gif|svg))"') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
Yes "the page names its pictures: $($named -join ', ')" ($named.Count -ge 2)
$list = @()
if ((Get-Variable ShipTravelsWith -EA SilentlyContinue) -and $ShipTravelsWith.ContainsKey($pageKey)) { $list = @($ShipTravelsWith[$pageKey]) }
foreach ($n in $named) {
    Yes "  $n travels with the page" ($list -contains ('Data\Platform\UI\' + $n))
    Yes "  $n is in game\ui, where Go.ps1 copies it from" (Test-Path -LiteralPath (Join-Path $ui $n))
}
foreach ($w in $list) {
    Yes "  $w is a picture the page names, not a stray" ($named -contains (Split-Path $w -Leaf))
    Yes "  $w is ours and would be packed (not another server's, not this machine's)" (-not (Test-ShipOtherServer $w) -and -not (Test-ShipMachine $w))
}
$go = [IO.File]::ReadAllText((Join-Path $RepoRoot 'scripts/release/Go.ps1'))
Yes 'Go.ps1 puts the .webp pictures into the game folder a Ship scans' ($go -match 'Get-ChildItem -LiteralPath \$uiSrc -Filter \*\.webp')

# ---- Get-ShipTravelsWith -----------------------------------------------------
Yes 'Ship-Rules has Get-ShipTravelsWith' ([bool](Get-Command Get-ShipTravelsWith -EA SilentlyContinue))
if (-not (Get-Command Get-ShipTravelsWith -EA SilentlyContinue)) { Done }
$a = @(Get-ShipTravelsWith @($pageKey, 'Data\Platform\Plugins\thornswood-front.js'))
Yes "a pack with the page gets both pictures: $($a -join ', ')" ($a.Count -eq 2 -and $a -contains 'Data\Platform\UI\thornswood-scroll.webp' -and $a -contains 'Data\Platform\UI\thornswood-scroll-open.webp')
$b = @(Get-ShipTravelsWith @('Data\Platform\Plugins\thornswood-front.js', 'Data\Platform\UI\thornswood-party.js'))
Yes 'a pack without the page gets nothing extra' ($b.Count -eq 0)
$c = @(Get-ShipTravelsWith @($pageKey, 'Data\Platform\UI\thornswood-scroll.webp'))
Yes 'a picture already in the pack is not added twice' ($c.Count -eq 1 -and $c[0] -eq 'Data\Platform\UI\thornswood-scroll-open.webp')
$d = @(Get-ShipTravelsWith @('data\platform\ui\THORNSWOOD-SELECT.JS'))
Yes 'the page is matched whatever the case of the path' ($d.Count -eq 2)
Yes 'nothing changed, nothing added' (@(Get-ShipTravelsWith @()).Count -eq 0)

# ---- the block in Publish-Update, run as shipped ----------------------------
$pu = [IO.File]::ReadAllText($publish)
$start = '# ==== thornswood travels with ===='
$end   = '# ==== end thornswood travels with ===='
$i = $pu.IndexOf($start); $j = $pu.IndexOf($end)
Yes 'Publish-Update.ps1 has the travels-with block' ($i -ge 0 -and $j -gt $i)
if ($i -lt 0 -or $j -le $i) { Done }
$block = $pu.Substring($i, $j - $i)
$diff = $pu.IndexOf('$changed = @(); $removed = @()')
$pack = $pu.IndexOf("Head 'Building the pack'")
Yes '  after the diff and before the pack is built' ($diff -ge 0 -and $diff -lt $i -and $pack -gt $j)
$size = $pu.IndexOf('$changedBytes = 0')
Yes '  and before the size is counted, so the release says its real size' ($size -gt $j)

# The 20260927-1633 pack: the page, the front, the client and the party strip.
# The game folder has both pictures, the baseline says they are published.
$now = @{
    'Data\Platform\UI\thornswood-select.js'       = '46366:1'
    'Data\Platform\UI\thornswood-scroll.webp'      = '8706:639259556940137994'
    'Data\Platform\UI\thornswood-scroll-open.webp' = '38764:639259556940127993'
    'Data\Platform\Plugins\thornswood-front.js'    = '288624:1'
}
$changed = @('Data\Platform\UI\thornswood-select.js', 'Data\Platform\Plugins\thornswood-front.js')
Invoke-Expression $block
Yes "the 1633 pack would have carried both pictures: $($changed.Count) files" ($changed.Count -eq 4 -and $changed -contains 'Data\Platform\UI\thornswood-scroll.webp' -and $changed -contains 'Data\Platform\UI\thornswood-scroll-open.webp')

$now = @{ 'Data\Platform\UI\thornswood-select.js' = '46366:1'; 'Data\Platform\UI\thornswood-scroll.webp' = '8706:1' }
$changed = @('Data\Platform\UI\thornswood-select.js')
Invoke-Expression $block
Yes 'a picture missing from the game folder is not packed' ($changed.Count -eq 2 -and $changed -notcontains 'Data\Platform\UI\thornswood-scroll-open.webp')

$now = @{ 'Data\Platform\Plugins\thornswood-front.js' = '288624:1'; 'Data\Platform\UI\thornswood-scroll.webp' = '8706:1' }
$changed = @('Data\Platform\Plugins\thornswood-front.js')
Invoke-Expression $block
Yes 'a pack without the page stays as it was' ($changed.Count -eq 1)

Done
