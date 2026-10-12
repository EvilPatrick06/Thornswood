# Scripts this runs whole go to a stand-in box, so the freshness guard lets them be (#2118).
$env:THORNSWOOD_HARNESS = '1'
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'scripts\mods\LoadOrder.ps1')
. (Join-Path $repo 'scripts\release\Release-Name.ps1')
$publisher = Join-Path $repo 'scripts\release\Publish-Update.ps1'
$ast = [Management.Automation.Language.Parser]::ParseFile($publisher, [ref]$null, [ref]$null)
# The DEV marks rule lives in Dev-News.ps1 since 6 Oct, shared by a dev publish,
# a dev publish with nothing new and a main Ship (Refresh-DevNews.ps1).
. (Join-Path $repo 'scripts\release\Dev-News.ps1')
foreach ($name in 'Val', 'Set-Prop', 'Get-ReferenceInServerOrder', 'Get-ActiveOrderKey') {
    $fn = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    if ($null -eq $fn) { throw "Publisher lacks $name" }
    Invoke-Expression $fn.Extent.Text
}
function Say($message, $color) {}
function Die($message) { throw $message }
function Assert($condition, $message) { if (-not $condition) { throw $message }; Write-Host "PASS $message" }
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('ts-parity-' + [guid]::NewGuid().ToString('N'))
$Root = $tmp; $DistDir = Join-Path $tmp 'dist'; $GameDir = Join-Path $tmp 'Game'
[IO.Directory]::CreateDirectory($DistDir) | Out-Null
[IO.Directory]::CreateDirectory((Join-Path $GameDir 'Data')) | Out-Null
function Get-LoadOrderManifestUrl($root) { 'fixture' }
function Get-LoadOrderManifest($url) { return ,@('Skyrim.esm', 'Update.esm', 'Dawnguard.esm', 'HearthFires.esm', 'Dragonborn.esm', 'Thornswood-Content.esp') }
# The whole manifest Publish-Update reads since #1715: a server that loads no
# light plugin, so no light list and the whole order is the full one.
function Get-LoadOrderManifestDoc($url) { $f = [string[]](Get-LoadOrderManifest $url); return [pscustomobject]@{ Full = $f; Light = [string[]]@(); All = $f } }
foreach ($name in (Get-LoadOrderManifest 'fixture') + @('FNIS.esp')) {
    $b = [byte[]]::new(24)
    [Text.Encoding]::ASCII.GetBytes('TES4').CopyTo($b, 0)
    if ($name -eq 'FNIS.esp') { [BitConverter]::GetBytes([uint32]0x200).CopyTo($b, 8) }
    [IO.File]::WriteAllBytes((Join-Path $GameDir "Data\$name"), $b)
}
$list = Join-Path $tmp 'plugins.txt'
[IO.File]::WriteAllLines($list, @('*Thornswood-Content.esp', '*FNIS.esp', 'CBBE 3BA Vanilla Outfits.esp'))
$original = [IO.File]::ReadAllText($list)
$packed = Get-ReferenceInServerOrder $list
Assert (([IO.File]::ReadAllLines($packed)) -contains '*FNIS.esp') 'Existing light plugins remain enabled'
Assert ([IO.File]::ReadAllText($list) -eq $original) 'Packing never modifies the source list'
$key = Get-ActiveOrderKey $list (Join-Path $GameDir 'Data')
[IO.File]::WriteAllLines($list, @('*Thornswood-Content.esp', '*FNIS.esp', '*CBBE 3BA Vanilla Outfits.esp'))
Assert ((Get-ActiveOrderKey $list (Join-Path $GameDir 'Data')) -eq $key) 'Removing an absent plugin reference cannot require a new character'
[IO.File]::WriteAllLines($list, @('*FNIS.esp', '*Thornswood-Content.esp'))
Assert ((Get-ActiveOrderKey $list (Join-Path $GameDir 'Data')) -ne $key) 'Changing the installed plugin order still changes the save warning key'
# #2031: the key is taken from the list in the server's order, so two machines
# whose own lists order the server's plugins differently ship the same order
# and get the same key. Alpha.esp and Beta.esp are full plugins the fixture
# server names in that order.
$fixtureManifest = ${function:Get-LoadOrderManifest}
function Get-LoadOrderManifest($url) { return ,@('Skyrim.esm', 'Update.esm', 'Dawnguard.esm', 'HearthFires.esm', 'Dragonborn.esm', 'Alpha.esp', 'Beta.esp', 'Thornswood-Content.esp') }
foreach ($name in 'Alpha.esp', 'Beta.esp') {
    $b = [byte[]]::new(24); [Text.Encoding]::ASCII.GetBytes('TES4').CopyTo($b, 0)
    [IO.File]::WriteAllBytes((Join-Path $GameDir "Data\$name"), $b)
}
$keyOut = Join-Path $DistDir 'order-key.txt'
function Get-ShippedKey([string[]]$lines) {
    [IO.File]::WriteAllLines($list, $lines)
    $shipped = Get-ReferenceInServerOrder $list $keyOut -Quiet
    return (Get-ActiveOrderKey $shipped (Join-Path $GameDir 'Data'))
}
$machineA = Get-ShippedKey @('*Alpha.esp', '*Beta.esp', '*Thornswood-Content.esp', '*FNIS.esp')
$machineB = Get-ShippedKey @('*Thornswood-Content.esp', '*Beta.esp', '*Alpha.esp', '*FNIS.esp')
Assert ($machineA -eq $machineB) 'Two machines whose own orders differ ship the server order and get the same key (#2031)'
$lightMoved = Get-ShippedKey @('*FNIS.esp', '*Alpha.esp', '*Beta.esp', '*Thornswood-Content.esp')
Assert ($lightMoved -ne $machineA) 'A plugin the server does not place moving among the shipped plugins still changes the key'
Set-Item function:Get-LoadOrderManifest $fixtureManifest
foreach ($channel in 'main', 'dev') {
    foreach ($missing in 'CBBE 3BA Vanilla Outfits.esp', 'Thornswood-Content.esp') {
        $file = Join-Path $GameDir "Data\$missing"
        $saved = if ([IO.File]::Exists($file)) { [IO.File]::ReadAllBytes($file) } else { $null }
        if ($saved) { [IO.File]::Delete($file) }
        [IO.File]::WriteAllLines($list, @('*Thornswood-Content.esp', '*FNIS.esp', "*$missing"))
        $refused = $false
        try { $null = Get-ReferenceInServerOrder $list } catch { $refused = $_.Exception.Message -like "*missing*" }
        Assert $refused "$channel refuses an enabled missing plugin: $missing"
        if ($saved) { [IO.File]::WriteAllBytes($file, $saved) }
    }
}
# Use actual git ancestry in a disposable repository, with one unfinished Dev commit.
$gitDir = Join-Path $tmp 'repo'; [IO.Directory]::CreateDirectory($gitDir) | Out-Null
& git -C $gitDir init -q
& git -C $gitDir -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm base --allow-empty
$base = (& git -C $gitDir rev-parse HEAD).Trim()
& git -C $gitDir -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm main --allow-empty
$main = (& git -C $gitDir rev-parse HEAD).Trim()
# Unfinished work carries a change Main does not have. An empty commit has
# nothing for Main to be missing, so it would count as published by content.
[IO.File]::WriteAllText((Join-Path $gitDir 'unfinished.txt'), 'not on main')
& git -C $gitDir add unfinished.txt
& git -C $gitDir -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm unfinished
$unfinished = (& git -C $gitDir rev-parse HEAD).Trim()
# A branch squash merged onto main, the way pull requests merge here: the
# branch commit a Dev release was built from never becomes an ancestor of
# main, and main gains the same change as a new commit.
& git -C $gitDir checkout -q --detach $main
[IO.File]::WriteAllText((Join-Path $gitDir 'squashed.txt'), 'merged by squash')
& git -C $gitDir add squashed.txt
& git -C $gitDir -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm 'branch work'
$branch = (& git -C $gitDir rev-parse HEAD).Trim()
[IO.File]::WriteAllText((Join-Path $gitDir 'more.txt'), 'only on the branch')
& git -C $gitDir add more.txt
& git -C $gitDir -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm 'branch work main never took'
$branchMore = (& git -C $gitDir rev-parse HEAD).Trim()
& git -C $gitDir checkout -q --detach $main
[IO.File]::WriteAllText((Join-Path $gitDir 'squashed.txt'), 'merged by squash')
& git -C $gitDir add squashed.txt
& git -C $gitDir -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm 'branch work (#1)'
$squashed = (& git -C $gitDir rev-parse HEAD).Trim()
# Main then moves the same lines on, the way a newer engine pin or the next
# gamemode change does, so merging the branch into main's tip now conflicts.
[IO.File]::WriteAllText((Join-Path $gitDir 'squashed.txt'), 'changed again on main')
& git -C $gitDir add squashed.txt
& git -C $gitDir -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm 'later main work on the same lines'
$movedOn = (& git -C $gitDir rev-parse HEAD).Trim()
# The tags Ship pushes for each dev release (Add-ReleaseTag), annotated, with
# the tagger's own clock: a note from before sourceCommit is matched to its
# release by them (#2401). The ids and times are the real ones of 1 to 3 Oct.
function Tag-DevRelease([string]$commit, [string]$id, [string]$taggedAt, [switch]$Dirty) {
    $msg = "Thornswood dev release $id`n`nlauncher  1.1.103.2`npacks     $id`nbaseline  $id`nbranch    HEAD"
    if ($Dirty) { $msg += "`nbuilt with 1 uncommitted change(s) on top of this commit" }
    $env:GIT_COMMITTER_DATE = $taggedAt
    try { & git -C $gitDir -c user.name=Fixture -c user.email=fixture@example.invalid tag -a "release/dev/$id" $commit -m $msg }
    finally { Remove-Item Env:GIT_COMMITTER_DATE -ErrorAction SilentlyContinue }
}
Tag-DevRelease $base '20261001-200344-dev' '2026-10-01T20:04:26-06:00'
Tag-DevRelease $base '20261002-015344-dev' '2026-10-02T01:54:30-06:00' -Dirty
Tag-DevRelease $unfinished '20261003-131311-dev' '2026-10-03T13:14:13-06:00'
# A tag made by hand without -a has no tagger and no message: no proof.
& git -C $gitDir tag 'release/dev/20260930-120000-dev' $base
$mainDoc = [pscustomobject]@{ launcherVersion='1.1.105'; release=[pscustomobject]@{commit=$main;uncommitted=0}; news=@() }
# The dev feed's own release is ahead of main, as it is between main
# releases: it says nothing about the notes from before sourceCommit.
$doc = [pscustomobject]@{ release=[pscustomobject]@{commit=$unfinished;uncommitted=0}; mainVersion='1.1.103' }
$notes = @([pscustomobject]@{title='Renamed Main feature';channel='dev';sourceCommit=$base},
    [pscustomobject]@{date='10-1-2026 8:04 PM';title='Legacy feature';channel='dev'},
    [pscustomobject]@{title='Unfinished Dev work';channel='dev';sourceCommit=$unfinished},
    [pscustomobject]@{title='New dirty work';channel='dev';sourceCommit=''},
    [pscustomobject]@{date='10-3-2026 1:13 PM';title='Legacy work main never took';channel=''},
    [pscustomobject]@{date='9-30-2026 12:00 PM';title='Legacy note with no annotated tag';channel='dev'},
    [pscustomobject]@{date='9-30-2026';title='Legacy note with a bare date';channel='dev'})
$null = Update-DevNewsChannels $doc $notes $mainDoc $gitDir
Assert ($notes[0].channel -eq '') 'A published ancestor is promoted despite a different news title'
Assert ($notes[1].channel -eq '') 'A legacy note clears when its own Dev release is on Main, though the newest Dev release is ahead of Main (#2401)'
Assert ($notes[2].channel -eq 'dev') 'Unmerged Dev work remains marked Dev'
Assert ($notes[3].channel -eq 'dev') 'A new dirty note cannot borrow an earlier clean release source'
Assert ($notes[4].channel -eq 'dev') 'A legacy note whose own Dev release Main does not have is marked Dev'
Assert ($notes[5].channel -eq 'dev' -and $notes[6].channel -eq 'dev') 'A legacy note with no release found keeps its mark'
$notes[5].channel = ''; $notes[6].channel = ''
$null = Update-DevNewsChannels $doc $notes $mainDoc $gitDir
Assert ($notes[5].channel -eq '' -and $notes[6].channel -eq '') 'and keeps an unmarked one unmarked'
# The release a legacy note came with is its proof, not the dev feed's own:
# a dirty current release changes nothing for it.
$doc.release.uncommitted = 1; $notes[1].channel = 'dev'
$null = Update-DevNewsChannels $doc $notes $mainDoc $gitDir
Assert ($notes[1].channel -eq '') 'A dirty newest Dev release leaves a legacy note to its own release'
$dirtyLegacy = @([pscustomobject]@{date='10-2-2026 1:54 AM';title='From a dirty release';channel='dev'},
    [pscustomobject]@{date='10-2-2026 1:54 AM';title='From a dirty release, unmarked';channel=''})
$null = Update-DevNewsChannels $doc $dirtyLegacy $mainDoc $gitDir
Assert ($dirtyLegacy[0].channel -eq 'dev' -and $dirtyLegacy[1].channel -eq '') 'Dirty legacy releases cannot be declared promoted, and keep the mark they have'
$notes[0].channel = 'dev'; $before = $notes | ConvertTo-Json -Depth 5 -Compress
$null = Update-DevNewsChannels $doc $notes $null $gitDir
Assert (($notes | ConvertTo-Json -Depth 5 -Compress) -eq $before) 'An unreadable Main feed preserves news marks'
Assert ($doc.mainVersion -eq '1.1.103') 'An unreadable Main feed preserves the last known Main version'
$squashMain = [pscustomobject]@{ launcherVersion='1.1.106'; release=[pscustomobject]@{commit=$squashed;uncommitted=0}; news=@() }
$squashDoc = [pscustomobject]@{ release=[pscustomobject]@{commit=$branch;uncommitted=0}; mainVersion='1.1.105' }
# Two releases a minute apart from one commit, as on 2 Oct at 2:35 and 2:36 PM.
Tag-DevRelease $branch '20261002-143545-dev' '2026-10-02T14:37:15-06:00'
Tag-DevRelease $branch '20261002-143641-dev' '2026-10-02T14:37:57-06:00'
$squashNotes = @([pscustomobject]@{title='Branch work';channel='dev';sourceCommit=$branch},
    [pscustomobject]@{date='10-2-2026 2:37 PM';title='Older legacy note';channel='dev'},
    [pscustomobject]@{title='Branch work main never took';channel='dev';sourceCommit=$branchMore},
    [pscustomobject]@{title='Unfinished Dev work';channel='dev';sourceCommit=$unfinished})
$null = Update-DevNewsChannels $squashDoc $squashNotes $squashMain $gitDir
Assert ($squashNotes[0].channel -eq '') 'A Dev source squash merged onto Main is promoted though it is not an ancestor'
Assert ($squashNotes[1].channel -eq '') 'Legacy notes clear when the preceding Dev release was squash merged onto Main'
Assert ($squashNotes[2].channel -eq 'dev') 'A branch commit with a change Main never took stays marked Dev'
Assert ($squashNotes[3].channel -eq 'dev') 'Work on no branch Main took stays marked Dev'
$squashNotes[0].channel = 'dev'
$null = Update-DevNewsChannels $squashDoc @([pscustomobject]@{title='Gone';channel='dev';sourceCommit=('0' * 40)}) $squashMain $gitDir
Assert ($squashNotes[0].channel -eq 'dev') 'Only the notes passed in are touched'
$gone = @([pscustomobject]@{title='Gone';channel='dev';sourceCommit=('f' * 40)})
$null = Update-DevNewsChannels $squashDoc $gone $squashMain $gitDir
Assert ($gone[0].channel -eq 'dev') 'A Dev source this clone does not have proves nothing and stays marked'
$laterMain = [pscustomobject]@{ launcherVersion='1.1.107'; release=[pscustomobject]@{commit=$movedOn;uncommitted=0}; news=@() }
$later = @([pscustomobject]@{title='Branch work';channel='dev';sourceCommit=$branch},
    [pscustomobject]@{title='Branch work main never took';channel='dev';sourceCommit=$branchMore})
$null = Update-DevNewsChannels $squashDoc $later $laterMain $gitDir
Assert ($later[0].channel -eq '') 'Squash merged work stays promoted after Main changes the same lines again'
Assert ($later[1].channel -eq 'dev') 'and work Main never took is still marked once Main has moved on'
[IO.Directory]::CreateDirectory((Join-Path $gitDir 'game')) | Out-Null
[IO.File]::WriteAllText((Join-Path $gitDir 'game\untracked-plugin.js'), 'new work')
Assert ((Get-ReleaseSource $gitDir).Uncommitted -eq 1) 'Untracked shipping inputs prevent source parity claims'
Write-Host 'PASS reference publication and source-based news promotion'
