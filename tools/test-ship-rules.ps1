<#
  test-ship-rules.ps1

  Two rules in Ship-Rules.ps1 that decide what leaves this machine in a pack
  or the installer.

  MARKETPLACETEXTURES.BSA. Bethesda's archive for the in-game Creations menu,
  2.8 MB, which every pack and the installer carried because it was in
  neither vanilla list and Vortex does not provide it. Both pack baselines on
  Patrick's machine list it, so the fix has to leave it out WITHOUT the next
  pack listing it as removed, or every launcher deletes a Bethesda file off
  every tester. This drives the diff and the removal filter lifted by text out
  of the shipped Publish-Update.ps1, the same way test-master-flag.ps1 lifts
  its functions out of Deploy-Gamemode.ps1, so it tests the real code.

  THE LOOSE ART REPORT. Get-ShipLooseArt names, a folder at a time, the loose
  textures and meshes an installer is about to carry that are neither ours nor
  the collection's. On 22 September that was 547 MB nobody had accounted for.

  Where this machine has a pack baseline and a Profile\OwnGame\files.txt, it
  measures against them too, and says SKIP where it cannot.

  Read only.
#>
[CmdletBinding()]
param([string]$Root = 'C:\Thornswood')

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }

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

. (Join-Path $Here 'Ship-Rules.ps1')

$bsa = 'Data\MarketplaceTextures.bsa'

# ---- the rule itself ---------------------------------------------------------
Yes 'MarketplaceTextures.bsa is one machine''s own: never shipped, never removed' (Test-ShipMachine $bsa)
Yes 'whatever the case of the path' (Test-ShipMachine 'data\marketplacetextures.bsa')
Yes 'only at the Data root, not a file of that name in a mod folder' (-not (Test-ShipMachine 'Data\textures\MarketplaceTextures.bsa'))
Yes 'and not a name that merely starts the same way' (-not (Test-ShipMachine 'Data\MarketplaceTextures.bsa.bak'))
Yes 'it is not a runtime path, which would list it as removed' (-not (Test-ShipRuntime $bsa))
Yes 'it is not on the list every pack deletes' (@(Get-ShipDeleteAlways) -notcontains $bsa)
Yes 'a mod''s own archive beside it still ships' (-not (Test-ShipMachine 'Data\SkyUI_SE.bsa'))
Yes 'and so does our own plugin' (-not (Test-ShipMachine 'Data\Thornswood-Content.esp'))

# ---- the shipped diff, lifted out of Publish-Update.ps1 ------------------------
#
# From the line that starts the two lists to the line that filters removals by
# Test-Machine, plus Test-Machine itself. If either is renamed this fails
# rather than quietly testing nothing.
$pubPath = Join-Path $Here 'Publish-Update.ps1'
$pub = Get-Content -LiteralPath $pubPath -Raw
$tm = [regex]::Match($pub, '(?m)^function Test-Machine\(.*$')
$diff = [regex]::Match($pub, '(?ms)^\$changed = @\(\); \$removed = @\(\)\r?$.*?^\$removed\s+= @\(\$removed \| Where-Object \{[^\r\n]*Test-Machine[^\r\n]*\r?$')
Yes 'Publish-Update.ps1 still defines Test-Machine on one line' $tm.Success
Yes 'Publish-Update.ps1 still builds the removals and filters them by Test-Machine' $diff.Success
Yes 'and its scan still leaves out what Test-Machine claims' ($pub -match 'if \(Test-Machine \$rel\) \{ continue \}')
if (-not $tm.Success -or -not $diff.Success) { Done }
. ([scriptblock]::Create($tm.Value))

# The last pack carried the archive, a mesh that has since gone, and one of our
# overlays. The game folder now has the archive and the overlay. The scan
# leaves out what Test-Machine claims, as Publish-Update's does.
$prev = @{}
$prev[$bsa] = '2938167:639246568900000000'
$prev['Data\meshes\gone\old.nif'] = '100:1'
$prev['Data\Platform\Plugins\thornswood-hud.js'] = '10:1'
$onDisk = @($bsa, 'Data\Platform\Plugins\thornswood-hud.js')
$now = @{}
foreach ($rel in $onDisk) {
    if (Test-Machine $rel) { continue }
    $now[$rel] = $prev[$rel]
}
. ([scriptblock]::Create($diff.Value))

Yes 'the next pack does not carry MarketplaceTextures.bsa' (-not $now.ContainsKey($bsa))
Yes 'and does not list it as changed' ($changed -notcontains $bsa)
Yes 'and does not list it as removed, so no tester loses it' ($removed -notcontains $bsa)
Yes 'the lifted diff is live: a mesh that really went is still removed' ($removed -contains 'Data\meshes\gone\old.nif')
Yes 'and our overlay is neither changed nor removed' (($changed -notcontains 'Data\Platform\Plugins\thornswood-hud.js') -and ($removed -notcontains 'Data\Platform\Plugins\thornswood-hud.js'))

# ---- the installer asks the same question ----------------------------------------
$pkg = Get-Content -LiteralPath (Join-Path $Here 'Package-Thornswood.ps1') -Raw
Yes 'Package-Thornswood.ps1 dot-sources Ship-Rules.ps1' ($pkg -match '\. \(Join-Path \$Here ''Ship-Rules\.ps1''\)')
Yes 'and its filter loop leaves out what Test-ShipMachine claims' ($pkg -match 'if \(Test-ShipMachine \$rel\) \{')
Yes 'and it reports the loose art it is about to ship' ($pkg -match '\$loose = Get-ShipLooseArt \$ship')

# ---- the loose art report --------------------------------------------------------
function Row([string]$rel, [long]$len) { return [pscustomobject]@{ Rel = $rel; Len = $len } }
$ship = @(
    (Row 'Data\textures\LoA Reborn Paladin Legendary\body.dds' 5000),
    (Row 'Data\textures\LoA Reborn Paladin Legendary\sub\hands.dds' 3000),
    (Row 'Data\Textures\LostArk\a.dds' 1000),
    (Row 'Data\textures\lostark\b.dds' 500),
    (Row 'Data\meshes\armor\commonclothes\travel.nif' 4000),
    (Row 'Data\meshes\animationdatasinglefile.txt' 700),
    (Row 'Data\meshes\interface\logo\logo.nif' 10562),
    (Row 'Data\meshes\interface\logo\logo01ae.nif' 10562),
    (Row 'Data\textures\interface\objects\Mainmenuwallpaper.dds' 8388736),
    (Row 'Data\Scripts\rp_trapcactusscript.pex' 900),
    (Row 'Data\Platform\UI\index.html' 2000),
    (Row 'Data\texturesOld\x.dds' 50),
    (Row 'Data\Thornswood-Content.esp' 64)
)
$loose = Get-ShipLooseArt $ship
$by = @{}
foreach ($l in $loose) { $by[$l.Folder] = $l }

Yes 'one row per folder: LoA, LostArk, armor and the loose meshes' ($loose.Count -eq 4)
Yes 'biggest first' ($loose.Count -ge 1 -and $loose[0].Folder -eq 'Data\textures\LoA Reborn Paladin Legendary')
Yes 'a folder counts everything under it, subfolders too' ($by.ContainsKey('Data\textures\LoA Reborn Paladin Legendary') -and $by['Data\textures\LoA Reborn Paladin Legendary'].Files -eq 2 -and $by['Data\textures\LoA Reborn Paladin Legendary'].Bytes -eq 8000)
Yes 'two spellings of one folder are one row' ($by.ContainsKey('Data\Textures\LostArk') -and $by['Data\Textures\LostArk'].Files -eq 2 -and $by['Data\Textures\LostArk'].Bytes -eq 1500)
Yes 'files straight under Data\meshes are a row of their own' ($by.ContainsKey('Data\meshes') -and $by['Data\meshes'].Files -eq 1)
Yes 'the menu backdrop is ours and is not reported' (-not $by.ContainsKey('Data\meshes\interface') -and -not $by.ContainsKey('Data\textures\interface'))
Yes 'scripts, the front and our plugin are not loose art' (-not ($loose | Where-Object { $_.Folder -notlike 'Data\textures*' -and $_.Folder -notlike 'Data\meshes*' }))
Yes 'a folder that only starts with textures is not textures' (-not ($loose | Where-Object { $_.Folder -like 'Data\texturesOld*' }))
$none = Get-ShipLooseArt @((Row 'Data\meshes\interface\logo\logo.nif' 1), (Row 'Data\Scripts\a.pex' 1))
Yes 'nothing to report is an empty list, not nothing' (($null -ne $none) -and $none.Count -eq 0)
$one = Get-ShipLooseArt @((Row 'Data\meshes\MCE\robe.nif' 29))
Yes 'one folder is still a list of one' ($one.Count -eq 1 -and $one[0].Folder -eq 'Data\meshes\MCE' -and $one[0].Bytes -eq 29)
Yes 'the three files Go.ps1 writes are the three called ours' ((@($ShipOwnArt) | Where-Object { (Get-Content -LiteralPath (Join-Path $Here 'Go.ps1') -Raw).Contains("'" + $_ + "'") }).Count -eq 3)

# ---- measured on this machine, where it can be ------------------------------------
$baseline = Join-Path $env:LOCALAPPDATA 'Thornswood\published.json'
if ($env:LOCALAPPDATA -and (Test-Path -LiteralPath $baseline)) {
    $keys = @(((Get-Content -LiteralPath $baseline -Raw) -replace '^\uFEFF', '' | ConvertFrom-Json).PSObject.Properties.Name)
    if ($keys -contains $bsa) {
        Write-Host "      this machine's last pack carried $bsa, so a vanilla rule would have deleted it"
    }
    Yes 'whatever the last pack carried, the archive is not removed by the next' (@($keys | Where-Object { $_ -ieq $bsa -and -not (Test-Machine $_) }).Count -eq 0)
} else {
    Write-Host 'SKIP  no pack baseline on this machine'
}

$record = Join-Path $Root 'Profile\OwnGame\files.txt'
if (Test-Path -LiteralPath $record) {
    # What the installer carries under textures and meshes out of an own game
    # folder: everything the record does not mark as the collection's (V).
    $rows = @()
    foreach ($line in [IO.File]::ReadLines($record)) {
        $p = $line.Split([char[]]'|', 5)
        if ($p.Count -ne 5 -or $p[1] -eq 'V') { continue }
        $rows += [pscustomobject]@{ Rel = $p[4]; Len = [long]$p[2] }
    }
    $measured = Get-ShipLooseArt $rows
    $mf = 0; $mb = [long]0
    foreach ($l in $measured) { $mf += $l.Files; $mb += $l.Bytes }
    Write-Host ("      {0} holds {1:n0} loose file(s), {2:n1} MB, in {3} folder(s) that are not ours:" -f $record, $mf, ($mb / 1MB), $measured.Count)
    foreach ($l in $measured) { Write-Host ("        {0,8:n1} MB {1,6:n0} file(s)  {2}" -f ($l.Bytes / 1MB), $l.Files, $l.Folder) }
    $oursThere = @($rows | Where-Object { @($ShipOwnArt) -contains $_.Rel })
    Yes ("the record's {0} file(s) of our menu backdrop are not reported" -f $oursThere.Count) ((Get-ShipLooseArt $oursThere).Count -eq 0)
    $inRecord = @($rows | Where-Object { $_.Rel -ieq $bsa })
    if ($inRecord.Count) {
        Yes 'the record''s MarketplaceTextures.bsa is left out' (Test-ShipMachine $inRecord[0].Rel)
    }
} else {
    Write-Host "SKIP  no $record on this machine"
}

Done
