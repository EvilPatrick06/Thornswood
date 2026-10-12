<#
  test-2401-legacy-dev-marks.ps1

      pwsh -NoProfile -File .\tests\test-2401-legacy-dev-marks.ps1

  The dev News tab marks a note from before sourceCommit by the dev release it
  came with, not by the dev feed's newest release (#2401).

  WHAT HAPPENED. Patrick, 12 Oct: "dev News tab still says 20 notes are labled
  dev which isnt right it should only be 4". Read that morning from the site:
  main's release 20261011-175014 (7cece557, clean); the dev feed's release
  20261012-080945-dev (13f88fcc), 40 notes, 20 marked DEV. The 4 newest
  (tonight's dev Ships) were rightly DEV. The other 16 were the notes of 1 to
  3 Oct, written before Publish-Update recorded a sourceCommit, all shipped on
  main 1.1.105 on 3 Oct. Update-DevNewsChannels gave every such note the
  proof of the dev feed's current release, which is ahead of main between main
  releases, so all 16 read as DEV.

  WHAT THIS DRIVES, offline: the real 40 notes of the dev feed of 12 Oct (date,
  title, whether it has a sourceCommit, its mark) and the real 44 dev release
  tags of 1 to 12 Oct (id, the tagger's time and zone, whether the release was
  built with uncommitted files, and the two of 2 Oct 2:35 and 2:36 PM built
  from one commit), in a scratch git repository with one commit a release on
  one line, main's release at the commit of 20261011-174543-dev, as 7cece557
  was. Update-DevNewsChannels must leave DEV on the 4 newest and take it off
  the 1 to 3 Oct notes. One of those, "Merchant purses and dungeon rewards",
  came with 20261002-015344-dev, built with 1 uncommitted change: nothing can
  prove it, so it keeps the mark it has, DEV or not.

  Everything it writes is under its own temp folder, which it removes.
#>
$env:THORNSWOOD_HARNESS = '1'
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'scripts\release\Dev-News.ps1')

$script:pass = 0; $script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" -ForegroundColor Red }
}

# The dev release tags of 1 to 12 Oct as they are on GitHub: id, when Ship
# tagged it on the shipping machine's clock, built with uncommitted files,
# built from the same commit as the one before it.
$tags = @(
    ,@('20261001-170723-dev', '2026-10-01T17:08:14-06:00', $false, $false)
    ,@('20261001-185615-dev', '2026-10-01T18:57:06-06:00', $false, $false)
    ,@('20261001-195002-dev', '2026-10-01T19:50:53-06:00', $false, $false)
    ,@('20261001-200344-dev', '2026-10-01T20:04:26-06:00', $false, $false)
    ,@('20261001-204154-dev', '2026-10-01T20:42:49-06:00', $false, $false)
    ,@('20261001-215555-dev', '2026-10-01T21:56:40-06:00', $false, $false)
    ,@('20261001-220727-dev', '2026-10-01T22:08:07-06:00', $false, $false)
    ,@('20261001-223010-dev', '2026-10-01T22:30:49-06:00', $false, $false)
    ,@('20261001-224424-dev', '2026-10-01T22:45:08-06:00', $false, $false)
    ,@('20261001-231219-dev', '2026-10-01T23:13:03-06:00', $false, $false)
    ,@('20261001-232427-dev', '2026-10-01T23:25:08-06:00', $false, $false)
    ,@('20261001-234201-dev', '2026-10-01T23:42:43-06:00', $false, $false)
    ,@('20261001-235244-dev', '2026-10-01T23:53:30-06:00', $false, $false)
    ,@('20261002-001423-dev', '2026-10-02T00:15:07-06:00', $false, $false)
    ,@('20261002-003521-dev', '2026-10-02T00:36:06-06:00', $false, $false)
    ,@('20261002-010717-dev', '2026-10-02T01:07:57-06:00', $false, $false)
    ,@('20261002-015344-dev', '2026-10-02T01:54:30-06:00', $true, $false)
    ,@('20261002-143545-dev', '2026-10-02T14:37:15-06:00', $false, $false)
    ,@('20261002-143641-dev', '2026-10-02T14:37:57-06:00', $false, $true)
    ,@('20261003-131311-dev', '2026-10-03T13:14:13-06:00', $false, $false)
    ,@('20261003-143423-dev', '2026-10-03T14:35:17-06:00', $false, $false)
    ,@('20261003-173559-dev', '2026-10-03T17:37:01-06:00', $false, $false)
    ,@('20261003-180655-dev', '2026-10-03T18:07:41-06:00', $false, $false)
    ,@('20261003-185740-dev', '2026-10-03T18:58:35-06:00', $true, $false)
    ,@('20261003-192349-dev', '2026-10-03T19:24:55-06:00', $true, $false)
    ,@('20261003-224149-dev', '2026-10-03T22:43:10-06:00', $false, $false)
    ,@('20261003-231349-dev', '2026-10-03T23:14:55-06:00', $false, $false)
    ,@('20261004-001131-dev', '2026-10-04T00:13:21-06:00', $true, $false)
    ,@('20261004-124437-dev', '2026-10-04T12:45:39-06:00', $false, $false)
    ,@('20261004-184346-dev', '2026-10-04T18:44:39-06:00', $false, $false)
    ,@('20261004-225259-dev', '2026-10-04T22:54:04-06:00', $false, $false)
    ,@('20261004-235750-dev', '2026-10-04T23:58:48-06:00', $false, $false)
    ,@('20261005-130756-dev', '2026-10-05T13:08:54-06:00', $false, $false)
    ,@('20261005-140602-dev', '2026-10-05T14:06:37-04:00', $false, $false)
    ,@('20261005-152448-dev', '2026-10-05T15:25:27-04:00', $false, $false)
    ,@('20261005-225302-dev', '2026-10-05T22:54:05-06:00', $false, $false)
    ,@('20261006-141047-dev', '2026-10-06T14:11:23-04:00', $true, $false)
    ,@('20261008-160255-dev', '2026-10-08T16:03:30-04:00', $false, $false)
    ,@('20261011-145512-dev', '2026-10-11T14:56:41-06:00', $false, $false)
    ,@('20261011-174543-dev', '2026-10-11T17:47:25-06:00', $false, $false)
    ,@('20261011-221215-dev', '2026-10-11T22:13:56-06:00', $false, $false)
    ,@('20261012-004958-dev', '2026-10-12T00:53:48-06:00', $false, $false)
    ,@('20261012-021714-dev', '2026-10-12T02:21:35-06:00', $false, $false)
    ,@('20261012-080945-dev', '2026-10-12T08:11:19-06:00', $false, $false)
)
# The dev feed's 40 notes as the site served them on 12 Oct: date, title,
# whether it carries a sourceCommit, its mark, and the release it came with
# (measured; the code under test is never told it).
$notes = @(
    ,@('10-12-2026 8:10 AM', 'No bounty for a killing in town, and crashes reach staff', $true, 'dev', '20261012-080945-dev')
    ,@('10-12-2026 2:20 AM', 'The look panel steps aside, and a quicker game folder', $true, 'dev', '20261012-021714-dev')
    ,@('10-12-2026 12:52 AM', 'Notice boards are back, and house parts leave the forge', $true, 'dev', '20261012-004958-dev')
    ,@('10-11-2026 10:13 PM', 'Keys, deeds and forges', $true, 'dev', '20261011-221215-dev')
    ,@('10-11-2026 5:46 PM', 'The launcher gets ready in seconds', $true, '', '20261011-174543-dev')
    ,@('10-11-2026 2:56 PM', 'Worn gear updates at once and keys stop repeating after panels', $true, '', '20261011-145512-dev')
    ,@('10-8-2026 4:03 PM', 'The game notes what is in your hands when you draw', $true, '', '20261008-160255-dev')
    ,@('10-6-2026 2:11 PM', 'Number keys are your favourites hotkeys again', $true, '', '20261006-141047-dev')
    ,@('10-5-2026 10:53 PM', 'Add-on hair and beards, steadier voice, and panels that close with their own key', $true, '', '20261005-225302-dev')
    ,@('10-5-2026 3:25 PM', 'The emote wheel closes after two minutes', $true, '', '20261005-152448-dev')
    ,@('10-5-2026 1:08 PM', 'Dev and main match again', $true, '', '20261005-130756-dev')
    ,@('10-5-2026 2:06 PM', 'Clearer small crest icons in the launcher and on the site', $true, '', '20261005-140602-dev')
    ,@('10-4-2026 11:58 PM', 'Supplies wait for your character', $true, '', '20261004-235750-dev')
    ,@('10-4-2026 10:53 PM', 'Merchants keep what they buy', $true, '', '20261004-225259-dev')
    ,@('10-4-2026 6:44 PM', 'Riekling and Goblin clothes stay on at doors', $true, '', '20261004-184346-dev')
    ,@('10-4-2026 12:45 PM', 'Starting clothes arrive with your character', $true, '', '20261004-124437-dev')
    ,@('10-4-2026 12:12 AM', 'Creation can finish dressing and open', $true, '', '20261004-001131-dev')
    ,@('10-3-2026 11:14 PM', 'Starting clothes fixes stay installed', $true, '', '20261003-231349-dev')
    ,@('10-3-2026 10:42 PM', 'Starting clothes and drawn gear corrections', $true, '', '20261003-224149-dev')
    ,@('10-3-2026 7:24 PM', 'Starting clothes finish loading before creation', $true, '', '20261003-192349-dev')
    ,@('10-3-2026 6:58 PM', 'Covered bodies restored', $true, '', '20261003-185740-dev')
    ,@('10-3-2026 6:07 PM', 'The start scroll responds again', $true, '', '20261003-180655-dev')
    ,@('10-3-2026 5:36 PM', 'Starting clothes and emotes behave correctly', $true, '', '20261003-173559-dev')
    ,@('10-3-2026 2:34 PM', 'Both builds now match', $true, '', '20261003-143423-dev')
    ,@('10-3-2026 1:13 PM', 'The new collection is ready', $false, 'dev', '20261003-131311-dev')
    ,@('10-2-2026 2:37 PM', 'Safer updates and a quieter journal key', $false, 'dev', '20261002-143641-dev')
    ,@('10-2-2026 1:54 AM', 'Merchant purses and dungeon rewards', $false, 'dev', '20261002-015344-dev')
    ,@('10-2-2026 1:07 AM', 'Dungeon chests pay by the place''s tier', $false, 'dev', '20261002-010717-dev')
    ,@('10-2-2026 12:35 AM', 'Dev build: reliable book prices and submissions', $false, 'dev', '20261002-003521-dev')
    ,@('10-2-2026 12:14 AM', 'A message board stands in each town', $false, 'dev', '20261002-001423-dev')
    ,@('10-1-2026 11:53 PM', 'The notice board opens when you click it', $false, 'dev', '20261001-235244-dev')
    ,@('10-1-2026 11:42 PM', 'Dev launchers stay on the Dev feed', $false, 'dev', '20261001-234201-dev')
    ,@('10-1-2026 11:24 PM', 'The drop box is the notice board', $false, 'dev', '20261001-232427-dev')
    ,@('10-1-2026 11:12 PM', 'A price list can be left at the hold box', $false, 'dev', '20261001-231219-dev')
    ,@('10-1-2026 10:44 PM', 'Stand up works with the wheel open', $false, 'dev', '20261001-224424-dev')
    ,@('10-1-2026 10:30 PM', 'A lute stays put until you choose it', $false, 'dev', '20261001-223010-dev')
    ,@('10-1-2026 10:07 PM', 'The emote wheel stays in the middle', $false, 'dev', '20261001-220727-dev')
    ,@('10-1-2026 9:56 PM', 'A group book is on J for a business or a faction', $false, 'dev', '20261001-215555-dev')
    ,@('10-1-2026 8:42 PM', 'NPC populations and shared supplies', $false, 'dev', '20261001-204154-dev')
    ,@('10-1-2026 8:04 PM', 'A lost server now returns you to the main menu', $false, 'dev', '20261001-200344-dev')
)
$newest4 = @($notes[0..3] | ForEach-Object { $_[1] })
$legacy = @($notes | Where-Object { -not $_[2] })
$dirtyOne = 'Merchant purses and dungeon rewards'

$Scratch = Join-Path ([IO.Path]::GetTempPath()) ('ts-2401-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$git = Join-Path $Scratch 'clone'
New-Item -ItemType Directory -Force -Path $git | Out-Null
$saved = @{}
foreach ($k in 'GIT_COMMITTER_NAME', 'GIT_COMMITTER_EMAIL', 'GIT_AUTHOR_NAME', 'GIT_AUTHOR_EMAIL', 'GIT_COMMITTER_DATE') { $saved[$k] = [Environment]::GetEnvironmentVariable($k) }
$env:GIT_COMMITTER_NAME = 'Thornswood test'; $env:GIT_COMMITTER_EMAIL = 'test@thornswood.invalid'
$env:GIT_AUTHOR_NAME = 'Thornswood test'; $env:GIT_AUTHOR_EMAIL = 'test@thornswood.invalid'
function G { $o = @(& git -C $git -c commit.gpgsign=false -c tag.gpgsign=false @args 2>&1 | ForEach-Object { [string]$_ }); if ($LASTEXITCODE) { throw ("git " + ($args -join ' ') + ": " + ($o -join ' ')) }; return ,$o }
try {
    [void](G init -q)
    [void](G commit -q --allow-empty -m base)
    # One commit a release, each with a change of its own (an empty commit has
    # nothing main could be missing), tagged the way Ship tags it.
    $commitOf = @{}
    $last = ''
    foreach ($t in $tags) {
        if (-not $t[3]) {
            [IO.File]::WriteAllText((Join-Path $git 'release.txt'), $t[0])
            [void](G add release.txt)
            [void](G commit -q -m ("work for " + $t[0]))
            $last = (G rev-parse HEAD)[0].Trim()
        }
        $commitOf[$t[0]] = $last
        $msg = "Thornswood dev release $($t[0])`n`nlauncher  1.2.3.2`npacks     $($t[0])`nbaseline  $($t[0])`nbranch    HEAD"
        if ($t[2]) { $msg += "`nbuilt with 1 uncommitted change(s) on top of this commit" }
        $env:GIT_COMMITTER_DATE = $t[1]
        try { [void](G tag -a ("release/dev/" + $t[0]) $last -m $msg) } finally { Remove-Item Env:GIT_COMMITTER_DATE -ErrorAction SilentlyContinue }
    }
    $mainCommit = $commitOf['20261011-174543-dev']
    $made = G tag -l 'release/dev/*'
    Yes ("the stand-in clone has 44 tagged dev releases on one line ({0})" -f $made.Count) ($made.Count -eq 44)

    function Feed {
        $news = @(foreach ($n in $notes) {
            $o = [ordered]@{ date = $n[0]; title = $n[1]; body = ''; details = @('a line'); channel = $n[3] }
            if ($n[2]) { $o['sourceCommit'] = $commitOf[$n[4]] }
            [pscustomobject]$o
        })
        return [pscustomobject][ordered]@{
            launcherVersion = '1.2.3.2'; news = $news; mainVersion = '1.2.3'
            release = [pscustomobject][ordered]@{ id = '20261012-080945-dev'; channel = 'dev'; commit = $commitOf['20261012-080945-dev']; uncommitted = 0; tag = 'release/dev/20261012-080945-dev' }
        }
    }
    $mainFeed = [pscustomobject][ordered]@{ launcherVersion = '1.2.3'; news = @()
        release = [pscustomobject][ordered]@{ id = '20261011-175014'; channel = 'main'; commit = $mainCommit; uncommitted = 0 } }

    $dev = Feed
    Yes ("the stale dev feed has 20 of its 40 notes marked DEV, 16 of them from before sourceCommit ({0})" -f @($dev.news | Where-Object { $_.channel -eq 'dev' }).Count) (
        @($dev.news | Where-Object { $_.channel -eq 'dev' }).Count -eq 20 -and $legacy.Count -eq 16)
    $r = Set-DevFeedMarks $dev $mainFeed $git
    $still = @($dev.news | Where-Object { $_.channel -eq 'dev' } | ForEach-Object { $_.title })
    Yes ("5 of 40 stay marked DEV ({0})" -f $r.Marked) ($r.Marked -eq 5)
    Yes '  the 4 newest, which main does not have' (@($newest4 | Where-Object { $still -contains $_ }).Count -eq 4)
    Yes ("  and the one whose release was built with an uncommitted change, which keeps its mark ({0})" -f $dirtyOne) ($still -contains $dirtyOne)
    Yes ("15 notes from 1 to 3 Oct lose the mark ({0} cleared)" -f @($r.Cleared).Count) (
        @($r.Cleared).Count -eq 15 -and @($legacy | Where-Object { $_[1] -ne $dirtyOne -and @($r.Cleared) -notcontains $_[1] }).Count -eq 0)
    Yes '  among them the one in two releases a minute apart from one commit' (@($r.Cleared) -contains 'Safer updates and a quieter journal key')
    Yes '  none gains it, and every note with a sourceCommit is left as it was' (@($r.Gained).Count -eq 0 -and
        @($dev.news | Where-Object { $_.PSObject.Properties['sourceCommit'] -and $newest4 -notcontains $_.title -and $_.channel -eq 'dev' }).Count -eq 0)
    Yes ("  and mainVersion is main's ({0})" -f $dev.mainVersion) ($dev.mainVersion -eq '1.2.3')

    $again = Set-DevFeedMarks $dev $mainFeed $git
    Yes 'a second pass moves nothing' (-not $again.Changed -and $again.Marked -eq 5)

    # The dirty one with no mark keeps none: no proof either way.
    $dev2 = Feed
    foreach ($n in @($dev2.news)) { if ($n.title -eq $dirtyOne) { $n.channel = '' } }
    $r2 = Set-DevFeedMarks $dev2 $mainFeed $git
    Yes ("with no mark to keep, it gains none ({0} marked)" -f $r2.Marked) ($r2.Marked -eq 4 -and @($r2.Gained).Count -eq 0)

    # Main one release back (20261008-160255-dev's commit): the 3 Oct notes
    # are still on main, and the newer work is not.
    $older = [pscustomobject][ordered]@{ launcherVersion = '1.2.0'; news = @()
        release = [pscustomobject][ordered]@{ id = '20261008-170000'; channel = 'main'; commit = $commitOf['20261008-160255-dev']; uncommitted = 0 } }
    $dev3 = Feed
    $r3 = Set-DevFeedMarks $dev3 $older $git
    Yes ("against an older main the old notes still clear and the 11 Oct ones gain DEV ({0} marked: {1})" -f $r3.Marked, (@($r3.Gained) -join '; ')) (
        $r3.Marked -eq 7 -and @($r3.Gained).Count -eq 2 -and @($r3.Gained) -contains 'The launcher gets ready in seconds' -and @($r3.Cleared).Count -eq 15)

    # A clone with no tags proves nothing about the old notes: they keep their marks.
    $made = G tag -l 'release/dev/*'
    [void](G tag -d @made)
    $dev4 = Feed
    $r4 = Set-DevFeedMarks $dev4 $mainFeed $git
    Yes ("with no release tags in the clone every old note keeps its mark ({0} marked)" -f $r4.Marked) ($r4.Marked -eq 20 -and @($r4.Cleared).Count -eq 0)
}
finally {
    foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
    Remove-Item -LiteralPath $Scratch -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
