$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'scripts\mods\LoadOrder.ps1')
. (Join-Path $repo 'scripts\release\Release-Name.ps1')
$publisher = Join-Path $repo 'scripts\release\Publish-Update.ps1'
$ast = [Management.Automation.Language.Parser]::ParseFile($publisher, [ref]$null, [ref]$null)
foreach ($name in 'Val', 'Set-Prop', 'Get-ReferenceInServerOrder', 'Get-ActiveOrderKey', 'Update-DevNewsChannels') {
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
$mainDoc = [pscustomobject]@{ launcherVersion='1.1.105'; release=[pscustomobject]@{commit=$main;uncommitted=0}; news=@() }
$doc = [pscustomobject]@{ release=[pscustomobject]@{commit=$base;uncommitted=0}; mainVersion='1.1.103' }
$notes = @([pscustomobject]@{title='Renamed Main feature';channel='dev';sourceCommit=$base},
    [pscustomobject]@{title='Legacy feature';channel='dev'},
    [pscustomobject]@{title='Unfinished Dev work';channel='dev';sourceCommit=$unfinished},
    [pscustomobject]@{title='New dirty work';channel='dev';sourceCommit=''})
$null = Update-DevNewsChannels $doc $notes $mainDoc $gitDir
Assert ($notes[0].channel -eq '') 'A published ancestor is promoted despite a different news title'
Assert ($notes[1].channel -eq '') 'Legacy notes clear only when their recorded Dev source is published on Main'
Assert ($notes[2].channel -eq 'dev') 'Unmerged Dev work remains marked Dev'
Assert ($notes[3].channel -eq 'dev') 'A new dirty note cannot borrow an earlier clean release source'
$doc.release.uncommitted = 1; $notes[1].channel = 'dev'
$null = Update-DevNewsChannels $doc $notes $mainDoc $gitDir
Assert ($notes[1].channel -eq 'dev') 'Dirty legacy releases cannot be declared promoted'
$notes[0].channel = 'dev'; $before = $notes | ConvertTo-Json -Depth 5 -Compress
$null = Update-DevNewsChannels $doc $notes $null $gitDir
Assert (($notes | ConvertTo-Json -Depth 5 -Compress) -eq $before) 'An unreadable Main feed preserves news marks'
Assert ($doc.mainVersion -eq '1.1.103') 'An unreadable Main feed preserves the last known Main version'
$squashMain = [pscustomobject]@{ launcherVersion='1.1.106'; release=[pscustomobject]@{commit=$squashed;uncommitted=0}; news=@() }
$squashDoc = [pscustomobject]@{ release=[pscustomobject]@{commit=$branch;uncommitted=0}; mainVersion='1.1.105' }
$squashNotes = @([pscustomobject]@{title='Branch work';channel='dev';sourceCommit=$branch},
    [pscustomobject]@{title='Older legacy note';channel='dev'},
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
