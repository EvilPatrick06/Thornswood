<#
.SYNOPSIS
  Builds the launcher and publishes everything that changed, launcher and
  mods both, in a single release, to the main build or the dev build.

.DESCRIPTION
  One command. Builds the launcher and publishes everything that changed,
  launcher and mods both, in a single release.

  THE VERSION IS BUMPED BEFOREHAND, not here, by Bump-Version.ps1, and the bump
  reaches main through a pull request like any other change: main refuses a
  push from everybody, the owner included. Ship only reads this repository and
  writes nothing back to it. A main release is refused if anything is
  uncommitted or unpushed, or if a file under tools is one git does not know,
  so what ships and what is written down are the same thing.

      .\tools\Bump-Version.ps1        then the branch and pull request it prints
      git checkout main; git pull     once that pull request is merged
      .\tools\Ship.ps1 "..."

  THE NOTE IS WHAT CUSTOMERS READ, in the launcher's News tab, on the site and
  in #news. It takes several lines and splits them: the first line is the
  title, a line starting with a dash becomes a bullet, and the rest becomes the
  body. A one-line note leaves the body empty and the details as nothing but
  the version and the download size, which is how "Everything from dev" reached
  people on 22 September and told them nothing.

      .\tools\Ship.ps1 "The map marker points at the right door now
      It pointed one building east in four towns, which is why directions from
      other people never matched what you saw.
      - Map markers in Riverwood, Whiterun, Falkreath and Rorikstead
      - Nothing to reinstall, it arrives with the update"

  EVERY OPTION HAS ITS OWN .PARAMETER BELOW, and Get-Help puts each one beside
  what the param block declares, so nobody has to open this file to see them:

      Get-Help .\tools\Ship.ps1 -Full
      Get-Help .\tools\Ship.ps1 -Parameter Channel

  This header used to carry a hand-written list of five options, laid out as
  if it were all of them, while the param block declared thirteen. -Channel,
  the one the whole dev workflow runs on, was in the param block and nowhere
  else, and Get-Help printed nothing but the syntax line (entry 260 on the To
  Do List). tools\test-script-index.ps1 now fails the build check when a
  parameter is declared here without a .PARAMETER of its own.

.PARAMETER Notes
  What customers read about this release: the launcher's News tab, the site
  and #news for a main release, the dev launcher's News tab and the dev
  updates channel for a dev release. Mandatory, and the only option taken by
  position, so it can come first without its name. The first line is the
  title, a line starting with a dash becomes a bullet, and the rest becomes
  the body. The server's warning before the restart carries the title only.

.PARAMETER Version
  A dev build's number, for example 1.2.0.1, in place of the one Ship would
  work out from the dev feed. It is written into app\Updater.cs for the build
  and put back afterwards, so it only ever lives in the dev feed.

  A main release refuses it. Main ships the number already on main, and
  .\tools\Bump-Version.ps1 -To 1.2.0 moves that number first, through its own
  pull request, before Ship runs without -Version. The same number main
  already has is let through, because it changes nothing. -ModsOnly keeps the
  number where it is whatever this says.

.PARAMETER NoBump
  Kept for anything that passes it. Every main release now keeps the version
  number, so it changes nothing.

.PARAMETER ModsOnly
  Skips the launcher and publishes only the mod files that changed. The
  version number stays where it is.

.PARAMETER DryRun
  Builds and works out what would ship, and uploads no pack, publishes no
  feed and tells nobody: no news post, no warning from the server. The git
  checks are skipped, and the feed, the baseline and the version number are
  put back afterwards.

  IT STILL CHANGES THIS MACHINE, so do not run it while the game is open here.
  It closes any running Skyrim, SKSE loader or SkyMP client, matched by name
  wherever it runs from, and it does that even with -ModsOnly, because
  the publisher closes the game before it reads a single file. Without
  -ModsOnly it also closes the launcher and puts the new Thornswood.exe in
  <Root>\Launcher. It copies the plugins into the game folder. The pack it
  makes stays in -DistRoot, and every pack-*.zip there older than the ten
  newest is deleted. The first -Channel dev run on a machine makes the dev
  branch of the releases repo and pushes it to GitHub, dry run or not.

  DO NOT GIVE IT -Package. The installer step does not look at -DryRun, so on
  the main channel it rebuilds the installer and Package-Thornswood.ps1 puts
  it on the site, which is a real publish.

.PARAMETER Package
  Also rebuilds the two installer files for new people, after the release is
  out. Twenty minutes or more. A dev release never touches the installer.

.PARAMETER Root
  The Thornswood install whose launcher is built and whose files are
  published. Left out, it is the first of C:\Thornswood and Thornswood on any
  other fixed drive that has Launcher\Thornswood.exe in it, and for a dev
  release that folder with -DevBuild on the end, where the main launcher's
  Settings page installs the dev build.

.PARAMETER DistRoot
  Where releases are staged and zipped, passed straight through to
  Publish-Update and Package-Thornswood so all three agree. Not under -Root:
  that is the folder people play from.

.PARAMETER MoveServer
  Lets a main release change the server address in version.json. Without it,
  a release whose config.json names a different server from the one the feed
  has stops before anything is published, because that address moves
  everybody.

.PARAMETER NoPause
  Exits without waiting for Enter, so Ship can be chained after something
  else without stopping for a keypress nobody is there to give.

.PARAMETER AnnounceMinutes
  How many minutes of warning the server gives everybody in the world before
  putting them back to the launcher to pick up the release.

.PARAMETER NoAnnounce
  Ships quietly. The server is not told and nobody is put out; people pick
  the release up the next time they open the launcher.

.PARAMETER Channel
  main or dev, and main when it is left out.

  main is the build everybody plays on, and ships only what is already on
  GitHub. It refuses a release that is not on main or on a hotfix/ branch,
  that is behind or ahead of the same branch on origin, that has anything
  uncommitted, that has a file under tools git does not know about (the
  build and Go.ps1 would take it anyway), or that asks for a new number with
  -Version. A hotfix/ branch is the live build plus one fix and its version
  bump, cut from the commit the live release was built from. Ship refuses
  one that is not on GitHub, and it is Patrick's call like any live release.

  dev builds and publishes the second launcher: the dev branch of the
  releases repo, the dev server, and a version like 1.1.35.3 that a main
  release always outranks. It may ship from any branch, on either machine.

  THERE IS ONE DEV FEED AND THE LAST DEV SHIP WINS. Both machines publish to
  the same one, so a dev Ship replaces whatever the other machine put there.
  Say in #dev before taking it. A main Ship resets dev to match main. A
  hotfix does not, because the work on dev was not in it.

  Everything goes to dev first, decided by Patrick on 23 September: "even
  small changes go to the dev build launcher for pretesting". A main Ship is
  for a security fix or for something that leaves the game untestable, and he
  says which.

.EXAMPLE
  .\tools\Ship.ps1 -Channel dev "The map marker points at the right door now"

  Puts this branch on the dev build and the dev server for testing. Say in
  #dev first: the last dev Ship wins.

.EXAMPLE
  .\tools\Ship.ps1 -DryRun "The map marker points at the right door now"

  Builds and works out what would ship without publishing it. It closes a
  running game and puts the new launcher in place on this machine, so run it
  with the game closed. Get-Help .\tools\Ship.ps1 -Parameter DryRun lists
  everything it still changes.

.EXAMPLE
  .\tools\Ship.ps1 "The map marker points at the right door now"

  A main release, from main, pulled, with the version number already moved by
  Bump-Version.ps1 and merged. Only when Patrick has said it goes live.

.NOTES
  The installer package is the one thing publishing does not touch, and that is
  on purpose: it is a 21 GB copy and a 13 GB compress, twenty minutes or more,
  for a release that is usually a handful of small files. Shipping does not wait
  for that.

  What it does instead is count. Someone installing from a stale package
  downloads every update since, on first launch, before they can play, and that
  goes wrong quietly, so every run says how many releases behind it is. Rebuild
  it when the number gets big enough to annoy a new person, or when something
  left the build that should not ship at all.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Notes,
    [string]$Version,
    [switch]$NoBump,
    [switch]$ModsOnly,
    [switch]$DryRun,
    [switch]$Package,
    [string]$Root = 'C:\Thornswood'
    # Where releases are staged and zipped, passed straight through to
    # Publish-Update and Package-Thornswood so all three agree. Not under
    # $Root: that is the folder people play from.
    ,[string]$DistRoot = 'C:\Thornswood-Dev\dist'
    ,[switch]$MoveServer
    # So this can be chained after something else without stopping to wait for
    # a keypress nobody is there to give.
    ,[switch]$NoPause
    # Once a pack is published, everybody in the world is running files the
    # release has moved past, and the only way they pick it up is to quit to
    # the launcher. So the server is told to warn them and then put them out.
    # Minutes of notice, or -NoAnnounce to ship quietly.
    ,[double]$AnnounceMinutes = 5
    ,[switch]$NoAnnounce
    # main is the build everybody plays on. dev builds and publishes the second
    # launcher: the dev branch of the releases repo, the dev server, a version
    # like 1.1.35.3 that a main release always outranks. New work goes out on
    # dev first and gets broken there; a plain Ship afterwards promotes it all
    # to main and resets dev to match.
    ,[ValidateSet('main', 'dev')][string]$Channel = 'main'
)


# The launcher was SkyrimTogether.exe and is Thornswood.exe now. It replaces
# itself in place when it updates rather than being reinstalled, so an install
# made before the rename still carries the old name and both have to be looked
# for, newest first.
function Get-LauncherExe([string]$dir) {
    foreach ($n in 'Thornswood.exe', 'SkyrimTogether.exe') {
        $p = Join-Path $dir $n
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return (Join-Path $dir 'Thornswood.exe')
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Declared here because Set-StrictMode is on: reading a variable that was never
# set is an error, and the whole point of this one is that it is usually never
# set. Non-zero means the installer rebuild failed, and the Done section says
# so again at the end.
$script:InstallerFailed = 0
# What Publish-Discord.ps1 did, read back after it runs. It sets this in the
# global scope; seeded here so strict mode has something to read either way.
$global:ThornswoodDiscordResult = ''
# Set by the git gate when a live release comes from a hotfix/ branch, and
# read again where dev is reset to match main. Seeded for strict mode.
$hotfix = $false

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; Write-Host ''; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$RepoDir = Split-Path -Parent $Here
# version.json lives in the public releases clone now, beside the source one.
# Falls back to the source repo when that clone is not there yet, which is the
# same thing Publish-Update does, so both agree about where the feed is.
$ReleaseDir = Join-Path (Split-Path -Parent $RepoDir) 'Thornswood-Releases'
if (-not (Test-Path (Join-Path $ReleaseDir '.git'))) { $ReleaseDir = $RepoDir }
$MainReleaseDir = $ReleaseDir
$Dev = ($Channel -eq 'dev')

# ---- where the launcher is installed ----------------------------------------
#
# C:\Thornswood on most machines. A second developer may have put it on
# another drive, so when C: has no launcher every fixed drive is tried for
# <drive>:\Thornswood\Launcher\Thornswood.exe. The dev build is always the
# main root plus -DevBuild, on the same drive; that is where the main
# launcher's Settings page installs it (DevBuild.cs). -Root still wins.
function Find-Root {
    $first = 'C:\Thornswood'
    if (Test-Path -LiteralPath (Join-Path $first 'Launcher\Thornswood.exe')) { return $first }
    foreach ($d in @(Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Za-z]:\\$' })) {
        $cand = Join-Path $d.Root 'Thornswood'
        if (Test-Path -LiteralPath (Join-Path $cand 'Launcher\Thornswood.exe')) { return $cand }
    }
    return $first
}
if (-not $PSBoundParameters.ContainsKey('Root')) { $Root = Find-Root }

# ------------------------------------------------------------ dev channel
# The dev build follows the dev branch of the releases repo. That branch is
# checked out as a git worktree beside the main clone, so both feeds sit on
# disk at once and a publish to one cannot touch the other. Made on first use,
# from main's tip, so the first dev version.json is exactly what main has.
function Ensure-DevReleases([string]$mainRel) {
    $devRel = Join-Path (Split-Path -Parent $mainRel) 'Thornswood-Releases-dev'
    if (Test-Path (Join-Path $devRel 'version.json')) { return $devRel }
    if (-not (Test-Path (Join-Path $mainRel '.git'))) {
        Die "The dev channel needs the releases clone at $mainRel first."
    }
    Write-Host "  making the dev release worktree at $devRel" -ForegroundColor DarkGray
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        & git -C $mainRel fetch origin 2>&1 | Out-Null
        $remoteDev = & git -C $mainRel ls-remote --heads origin dev 2>$null
        if ($remoteDev) {
            & git -C $mainRel worktree add $devRel dev 2>&1 | Out-Host
        } else {
            & git -C $mainRel worktree add -b dev $devRel origin/main 2>&1 | Out-Host
            & git -C $devRel push -u origin dev 2>&1 | Out-Host
        }
    } finally { $ErrorActionPreference = $old }
    if (-not (Test-Path (Join-Path $devRel 'version.json'))) { Die "Could not make the dev release worktree at $devRel." }
    return $devRel
}

if ($Dev) {
    if (-not $PSBoundParameters.ContainsKey('Root')) { $Root = (Find-Root) + '-DevBuild' }
    if (-not (Test-Path (Join-Path $Root 'Launcher'))) {
        Die "No dev build at $Root. Install it from the main launcher's Settings page (The dev build) first."
    }
    if ($MainReleaseDir -eq $RepoDir) { Die 'The dev channel needs the public releases clone, Thornswood-Releases, beside this repo.' }
    $ReleaseDir = Ensure-DevReleases $MainReleaseDir
}

Write-Host ''
Write-Host '  SHIP' -ForegroundColor White

# What goes in -Notes is what customers read, in three places: the launcher's
# News tab, the site's News page and the #news post in Discord. It has always
# taken several lines and split them, first line the title, a line starting
# with a dash into the details, the rest into the body, and that was in none of
# the help text, so every release went out as one line with an empty body.
#
# On 22 September one read "Everything from dev, the final theme for everybody,
# and one card a person on the sessions page". Patrick, fairly: that does not
# tell people what was actually added. It names where the work came from.
#
# This does not refuse a one-line note. Refusing to publish over the wording of
# a release note would be worse than the note. It says so once, with the shape
# to copy, at the top where there is still time to stop.
if ($Notes -notmatch "`n") {
    Write-Host ''
    Say '  This note is one line, so the release goes out with no body and no' 'Yellow'
    Say '  details beyond the version and the download size. That is what people' 'Yellow'
    Say '  see in the launcher, on the site and in Discord.' 'Yellow'
    Write-Host ''
    Say '  The shape that fills them in:' 'DarkGray'
    Say '      .\tools\Ship.ps1 "A title, written from their side' 'DarkGray'
    Say '      A sentence or two of what changed and why anybody would care.' 'DarkGray'
    Say '      - one thing they will notice' 'DarkGray'
    Say '      - another thing they will notice"' 'DarkGray'
    Write-Host ''
    Say '  Carrying on with the one line.' 'DarkGray'
}
Write-Host "  $Notes" -ForegroundColor DarkGray

# ------------------------------------------------------------ git
# Two people ship from two machines. A main release is what everybody gets,
# so it comes off main, with nothing uncommitted and nothing unpulled: the
# other machine's last push has to be in this build or the release loses it.
# A dev release is for trying things, so it may come off any branch, and the
# feed says which. Skipped with -DryRun and when this is not a git clone.
if (-not $DryRun -and (Test-Path (Join-Path $RepoDir '.git'))) {
    Head 'Git'
    # git talks on stderr even when all is well, which Stop turns into a halt.
    $oldEap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $branch = (& git -C $RepoDir rev-parse --abbrev-ref HEAD 2>$null | Out-String).Trim()
    $dirty = @(& git -C $RepoDir status --porcelain --untracked-files=no 2>$null | Where-Object { $_ })
    # And the files under tools that git has never been told about, which the
    # line above leaves out. Ignored ones are not counted: measured 24 Sep, all
    # 14 files under tools on Patrick's machine that git does not track are
    # ignored (the webhooks, signing.json, __pycache__, a log, the front's zip),
    # and counting them would stop every main release.
    $loose = @(& git -C $RepoDir ls-files --others --exclude-standard -- tools 2>$null | Where-Object { $_ })
    & git -C $RepoDir fetch --quiet origin 2>$null | Out-Null
    $behind = 0
    $ahead = 0
    try { $behind = [int]((& git -C $RepoDir rev-list --count "HEAD..origin/$branch" 2>$null | Out-String).Trim()) } catch { $behind = 0 }
    try { $ahead  = [int]((& git -C $RepoDir rev-list --count "origin/$branch..HEAD" 2>$null | Out-String).Trim()) } catch { $ahead = 0 }
    $ErrorActionPreference = $oldEap
    Say ("  branch {0}, {1} uncommitted change(s), {2} behind and {3} ahead of origin/{0}" -f $branch, $dirty.Count, $behind, $ahead) 'DarkGray'
    if (-not $Dev) {
        # A HOTFIX is the one live release that does not come off main.
        # Patrick, 24 September, with a tester on the main build who could not
        # get in and a day of dev work sitting on main: "the only thing that
        # should be going to main now is the fix for him". A branch named
        # hotfix/... starts from the commit the live release was built from and
        # carries only the fix and its version bump; 1.1.93 went out that way.
        # Every other check below still applies to it: nothing uncommitted,
        # nothing unknown under tools, nothing that is not on GitHub.
        $hotfix = $branch -like 'hotfix/*'
        if ($branch -ne 'main' -and -not $hotfix) { Die "A main release ships from main. This is $branch. Merge it into main first, or use -Channel dev to try it on the dev server." }
        if ($hotfix) {
            # The counts above come out 0 and 0 when origin has no such branch,
            # because git refuses the range and prints nothing. For main that
            # cannot happen; for a hotfix it would let a branch that exists on
            # one disk only go out to everyone. Found by the verification of
            # hotfix 1.1.93.
            & git -C $RepoDir rev-parse --verify --quiet "refs/remotes/origin/$branch" *> $null
            if ($LASTEXITCODE -ne 0) { Die "$branch is not on GitHub. A release ships only what is already there: git push -u origin $branch, then Ship." }
            Say "  a hotfix: a live release from $branch, which is the live build plus its fix and nothing else from main" 'Yellow'
        }
        if ($behind -gt 0) { Die "$branch is $behind commit(s) behind origin/$branch. Run git pull first, so the other machine's work is in this release." }

        # A MAIN RELEASE NOW SHIPS ONLY WHAT IS ALREADY ON GITHUB, and these
        # three refusals are the whole of that rule.
        #
        # Ship used to build from the working tree and then commit and push it
        # afterwards, so a release could go out carrying code that existed on
        # one disk. That worked because Ship could write to main. It cannot any
        # more, by design, so anything not already pushed would simply be lost:
        # the release reaches every launcher and the source never lands.
        #
        # So: nothing uncommitted, nothing unpushed, and then what shipped and
        # what is written down are the same thing by construction rather than
        # by a step at the end that might fail.
        if ($dirty.Count) {
            foreach ($d in $dirty | Select-Object -First 10) { Say "    $d" 'Yellow' }
            Die ("There are $($dirty.Count) uncommitted change(s). A release ships what is on GitHub, and " +
                 "Ship no longer commits anything itself, so these would not travel. Put them on a branch " +
                 "and through a pull request, or put them back, then Ship.")
        }
        # The uncommitted count above never saw a NEW file, and a new file
        # ships all the same: Go.ps1 copies every tools\ts-plugins\*.js into
        # the game folder and the build compiles every tools\app\*.cs, whether
        # git knows them or not. So a scratch plugin would pass this gate and go
        # out in the pack while GitHub had never seen it, which is where the
        # entry's worry, "a scratch file with something private in it lands
        # next", had moved to once Ship stopped committing. Found in the
        # review of entry 205 on 24 Sep.
        #
        # One ignored file does ship and is not counted: tools\thornswood-
        # front.zip, which Go.ps1 unpacks into Data\Platform\UI. *.zip keeps it
        # out of git and it has never been committed. Whether it should be is
        # not a question this gate can settle.
        if ($loose.Count) {
            foreach ($d in $loose | Select-Object -First 10) { Say "    $d" 'Yellow' }
            Die ("There are $($loose.Count) file(s) under tools that git does not know about. The build " +
                 "and Go.ps1 take them anyway, so they would go out in this release without being on GitHub. " +
                 "Put them through a pull request, delete them, or add them to .gitignore, then Ship.")
        }
        if ($ahead -gt 0) {
            # Not "git push": main refuses a push from everybody since
            # enforce_admins went on, so that advice sent people into a refusal.
            Die ("$branch is $ahead commit(s) ahead of origin/$branch. A release has to be buildable from what " +
                 "everybody else can see, and main takes commits only through a pull request: move them to " +
                 "a branch, push that, merge its pull request, git pull, then Ship.")
        }
    } elseif ($behind -gt 0) {
        Say "  this branch is $behind commit(s) behind origin; the dev build will not carry them" 'Yellow'
    }
}

# ------------------------------------------------------------ version
$updaterCs = Join-Path $Here 'app\Updater.cs'
if (-not (Test-Path $updaterCs)) { Die "Could not find $updaterCs" }

$src = Get-Content $updaterCs -Raw
$m = [regex]::Match($src, 'Version\s*=\s*"([^"]+)"')
if (-not $m.Success) { Die 'Could not read the version out of app\Updater.cs' }
$current = $m.Groups[1].Value

if ($ModsOnly) {
    $target = $current
}
elseif ($Version) {
    # A main release ships the number already on main, like everything else in
    # it. -Version used to write a new one into Updater.cs here, and on a
    # release that went out nothing committed it or put it back, so every
    # launcher would be told a version main had never heard of and the next
    # main Ship would find Updater.cs uncommitted. Found in the review of
    # entry 205 on 24 Sep. A dev build still takes it: its source is put back
    # after the build and the number only ever lives in the dev feed.
    if (-not $Dev -and $Version -ne $current) {
        Die ("A main release ships the version already on main, $current. Move it first with " +
             ".\tools\Bump-Version.ps1 -To $Version and its pull request, then Ship without -Version.")
    }
    $target = $Version
}
elseif ($Dev) {
    # A dev build is the main version with a fourth number: 1.1.35.1, .2, .3.
    # Read off the dev feed so it climbs from wherever dev is, and starts
    # again at .1 whenever main has moved on. The launcher compares numbers
    # part by part, so 1.1.36 beats every 1.1.35.x and a promoted main release
    # always wins.
    #
    # THE BASE IS THE HIGHER OF THIS BRANCH AND WHAT MAIN HAS PUBLISHED, and
    # it used to be this branch alone.
    #
    # 21 September. 1.1.76 was rolled back, which put main on 1.1.77, and the
    # three fixes that came off it went onto a branch cut BEFORE that bump, so
    # its Updater.cs still said 1.1.76. Shipping that branch to dev produced
    # 1.1.76.1, and the run said so plainly: "main is on 1.1.77, this one is on
    # 1.1.76.1". Updater.IsNewer compares part by part, so 1.1.76.1 is LOWER
    # than 1.1.77, and every dev launcher that had taken the 1.1.77 reset was
    # never offered the build at all. Published, uploaded, announced in Discord,
    # and unreachable.
    #
    # The comment above already stated the rule this broke: a promoted main
    # release always wins. That holds while dev ships from main. It stops
    # holding the moment dev ships from a branch behind main, which is exactly
    # what a rollback forces, because a rollback is the case where main moves
    # forward and the work does not.
    #
    # Reading the MAIN feed rather than main's Updater.cs is deliberate: what
    # matters is the number people's launchers actually have, and that is the
    # number that was published.
    function Compare-Ver([string]$a, [string]$b) {
        $x = @(); $y = @()
        foreach ($p in ($a -split '\.')) { $k = 0; if ([int]::TryParse($p, [ref]$k)) { $x += $k } }
        foreach ($p in ($b -split '\.')) { $k = 0; if ([int]::TryParse($p, [ref]$k)) { $y += $k } }
        for ($i = 0; $i -lt [Math]::Max($x.Count, $y.Count); $i++) {
            $u = if ($i -lt $x.Count) { $x[$i] } else { 0 }
            $v = if ($i -lt $y.Count) { $y[$i] } else { 0 }
            if ($u -ne $v) { return $(if ($u -gt $v) { 1 } else { -1 }) }
        }
        return 0
    }

    $base = $current
    try {
        $mainWas = [string]((Get-Content (Join-Path $MainReleaseDir 'version.json') -Raw | ConvertFrom-Json).launcherVersion)
        # Only the first three parts of main's number. Main never carries a
        # fourth, but reading defensively costs nothing and a 1.1.77.2 base
        # would produce a five part version nobody can read.
        if ($mainWas) {
            $mb = ($mainWas -split '\.')
            if ($mb.Count -ge 3) { $mainWas = ($mb[0..2] -join '.') }
            if ((Compare-Ver $mainWas $base) -gt 0) {
                Say "  this branch says $base and main has published $mainWas, so dev climbs from $mainWas" 'Yellow'
                $base = $mainWas
            }
        }
    } catch { }

    $n = 1
    try {
        $was = [string]((Get-Content (Join-Path $ReleaseDir 'version.json') -Raw | ConvertFrom-Json).launcherVersion)
        if ($was.StartsWith("$base.")) {
            $tail = $was.Substring($base.Length + 1)
            $k = 0
            if ([int]::TryParse($tail, [ref]$k)) { $n = $k + 1 }
        }
    } catch { }
    $target = "$base.$n"
}
else {
    # A MAIN RELEASE NO LONGER BUMPS THE VERSION, and this is the change that
    # lets branch protection apply to everybody.
    #
    # It used to bump Updater.cs here and then, after publishing, `git add -A`
    # and push the result straight to main. That push is why enforce_admins had
    # to stay off: turning it on refuses it, and the release would reach every
    # launcher while the source commit never landed, so the repo would say
    # something different from what shipped. The worst half-state there is, on
    # every release.
    #
    # The bump is its own commit now, made by Bump-Version.ps1 before any of
    # this runs, and it goes through whatever the branch rules are like any
    # other change. Ship only READS the repository, so nothing it does needs
    # write access to main.
    #
    # -NoBump is kept and means the same as it always did, so anything that
    # passed it keeps working; it is simply what every main release does now.
    $target = $current
}

if ($target -ne $current) {
    Head 'Version'
    Say "  $current  ->  $target" 'Green'
    $src = $src -replace 'Version\s*=\s*"[^"]+"', ('Version = "' + $target + '"')
    Set-Content $updaterCs $src -Encoding UTF8 -NoNewline
}
else {
    Head 'Version'
    Say "  staying on $current" 'DarkGray'
}

# The new version goes into Updater.cs before anything is built, because the
# exe has to carry it. Anything that stops the release after that point has to
# put it back, or a failed run burns a number and the launcher people are
# running claims a version that was never published.
function Unbump([string]$why) {
    if ($target -eq $current) { return }
    $back = Get-Content $updaterCs -Raw
    $back = $back -replace 'Version\s*=\s*"[^"]+"', ('Version = "' + $current + '"')
    Set-Content $updaterCs $back -Encoding UTF8 -NoNewline
    Head 'Version'
    Say "  put back to $current, $why" 'Yellow'
}

# ------------------------------------------------------------ build
if (-not $ModsOnly) {
    Head 'Building the launcher'
    # Resolved twice on purpose. The install writes Thornswood.exe and removes a
    # SkyrimTogether.exe left over from before the rename, so the path that
    # existed going in is not necessarily the path that exists coming out.
    # Holding on to the first answer makes a build that worked look like a
    # build that produced nothing.
    $launchDir = Join-Path $Root 'Launcher'
    $before = [datetime]::MinValue
    foreach ($n in 'Thornswood.exe', 'SkyrimTogether.exe') {
        $p = Join-Path $launchDir $n
        if (Test-Path -LiteralPath $p) {
            $t = (Get-Item -LiteralPath $p).LastWriteTimeUtc
            if ($t -gt $before) { $before = $t }
        }
    }

    # The build and the install are two scripts since 24 September (To Do List
    # entry 243). The build compiles into a folder of its own, so csc never
    # meets the launcher still running from the install, and Install-Launcher
    # then closes the game and the launcher, puts the exe in place and does
    # the shortcut and the icon, which is everything the build used to do.
    $buildOut = Join-Path ([IO.Path]::GetTempPath()) ('Thornswood-launcher-' + (Split-Path -Leaf $Root.TrimEnd('\')))
    & (Join-Path $Here 'Build-Launcher.ps1') -Root $Root -OutDir $buildOut -NoPause
    $buildCode = $LASTEXITCODE

    <#
      The build script's own answer, read before anything else.

      Whether the launcher built used to be judged only on an exe appearing with
      a newer timestamp. Compiling happens near the start, so every step after
      csc was invisible here: the stub, the signing, anything added later.

      On 18 September that shipped a release that had already stopped.
      Build-Launcher printed "STOP. Signing failed. Nothing was published." and
      exited 1 because the Azure certificate profile did not exist yet. The exe
      from the compile was sitting there and it was newer than before, so the
      check below passed, and Ship went on to build the pack, upload it, rewrite
      version.json, post the news, tell Discord and tell everybody in the world
      they had five minutes. 1.1.48 went out unsigned, announcing that nothing
      had been published.
    #>
    if ($buildCode -ne 0) {
        Unbump 'the launcher build failed'
        Die ('The launcher build stopped with exit code ' + $buildCode +
             '. Nothing was published. The errors are above.')
    }

    & (Join-Path $Here 'Install-Launcher.ps1') -Root $Root -From $buildOut -NoPause
    $installCode = $LASTEXITCODE
    if ($installCode -ne 0) {
        Unbump 'the launcher could not be put in place'
        Die ('Putting the new launcher into ' + $launchDir + ' stopped with exit code ' + $installCode +
             '. Nothing was published. The errors are above.')
    }

    $exe = Get-LauncherExe $launchDir
    $built = Test-Path -LiteralPath $exe
    if ($built) { $built = ((Get-Item -LiteralPath $exe).LastWriteTimeUtc -gt $before) }
    if (-not $built) {
        Unbump 'nothing was built'
        Die 'The launcher did not build. Look at the errors above.'
    }
    Say ("  built, {0:n0} KB" -f ((Get-Item $exe).Length / 1KB)) 'Green'
    if ($Dev -and $target -ne $current) {
        $back = Get-Content $updaterCs -Raw
        $back = $back -replace 'Version\s*=\s*"[^"]+"', ('Version = "' + $current + '"')
        Set-Content $updaterCs $back -Encoding UTF8 -NoNewline
        Say "  source put back to $current, the exe carries $target" 'DarkGray'
        $current = $target   # so nothing below tries to unbump a version the source no longer has
    }
}

# ------------------------------------------------------- the in game plugins
# The plugins are source in this repo and files in the game folder, and Go.ps1
# is the only thing that moves one to the other. Ship never did it, so a release
# carried whichever copy happened to be sitting in the folder. On 17 Sep that
# published a dev build with day old plugins from a machine where the source had
# changed and nobody had run Go, and the publisher could not see it: to the
# publisher the file simply had not changed.
#
# So it happens here, before anything is scanned, into the same folder the
# client patch and the publisher use. SkipServer because this is a build step
# and has no business talking to the VPS.
$GameDir = Join-Path $Root 'Game'
if (-not (Test-Path -LiteralPath (Join-Path $GameDir 'SkyrimSE.exe'))) { $GameDir = '' }

Head 'The in game plugins'
$goArgs = @{ SkipServer = $true }
if ($GameDir) { $goArgs['Game'] = $GameDir } else { $goArgs['Vortex'] = $true }
# Write-Host does not go down the pipeline, so Out-Null does not quiet it.
# 6 is the information stream Write-Host actually uses. Nothing is lost:
# Go.ps1 reports in colour and exits 0 either way, and the check below is
# what decides whether this step passed.
& (Join-Path $Here 'Go.ps1') @goArgs 6>$null | Out-Null

# Go.ps1 reports trouble in yellow and still exits 0, so the files are checked
# rather than the exit code. This is the guard that makes the step worth having:
# a plugin that did not land stops the release instead of shipping stale.
if ($GameDir) {
    $plugSrc = Join-Path $Here 'ts-plugins'
    $plugDst = Join-Path $GameDir 'Data\Platform\Plugins'
    $stale = @()
    $seen  = 0
    foreach ($f in @(Get-ChildItem -LiteralPath $plugSrc -Filter '*.js' -File -EA SilentlyContinue)) {
        $seen++
        $dst = Join-Path $plugDst $f.Name
        if (-not (Test-Path -LiteralPath $dst)) { $stale += ($f.Name + ' never arrived'); continue }
        $a = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
        $b = (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash
        if ($a -ne $b) { $stale += ($f.Name + ' in the game folder is not this source') }
    }
    if ($stale.Count) {
        foreach ($line in $stale) { Say "  $line" 'Red' }
        Unbump 'the in game plugins are not this source'
        Die 'The plugins in the game folder are not the ones in this repo. Nothing was published.'
    }
    if ($seen -eq 0) {
        Unbump 'there are no in game plugins to ship'
        Die 'tools\ts-plugins has no .js in it. Nothing was published.'
    }
    Say "  $seen plugin(s) in the game folder match this source" 'Green'
} else {
    Say '  installed into the Steam copy; no own game folder to check them against' 'Yellow'
}

# ------------------------------------------------------------ client build
# The client runtime is built from the fork and recorded in client-build.json.
# Until 20 September the copy in the game folder was whatever another server's
# launcher had last written into the Steam copy, patched by text; now a release
# refuses to go out unless the six recorded files are the recorded build, byte
# for byte, in the folder this release packs. Sync-Client.ps1 -Check answers
# that without copying anything: 0 all in place, 2 something differs, 1 the
# build itself is not the recorded one or the record is missing.
Head 'Client build'
# global:, never a bare assignment. Run from a prompt, as Ship always is, a
# bare $LASTEXITCODE = 0 makes a copy that belongs to this script alone, while
# a child script's exit lands in the global one. On 19 Sep a refused check was
# read as this script's own 0 and a dev release went out over it.
$global:LASTEXITCODE = 0
$syncArgs = @{ Check = $true; NoPause = $true }
if ($GameDir) { $syncArgs['Game'] = $GameDir }
& (Join-Path $Here 'Sync-Client.ps1') @syncArgs
if ($LASTEXITCODE -eq 2) {
    Unbump 'the client in the game folder is not the recorded build'
    Die 'The game folder does not hold the recorded client. Run .\tools\Sync-Client.ps1, then Ship again.'
}
if ($LASTEXITCODE -ne 0) {
    Unbump 'the client build could not be checked'
    Die 'Sync-Client.ps1 refused. Rebuild the client, run .\tools\New-ClientBuildRecord.ps1, and Ship again.'
}

# ------------------------------------------------------------ publish
Head 'Publishing'
# A hashtable, not an array. Splatting an array passes everything positionally,
# so '-Notes' binds as a value rather than a parameter name.
$pubArgs = @{ Notes = $Notes; Root = $Root; RepoDir = $RepoDir; ReleaseDir = $ReleaseDir; DistRoot = $DistRoot; NoPause = $true }
if ($MoveServer) { $pubArgs['MoveServer'] = $true }
if (-not $ModsOnly) { $pubArgs['Launcher'] = $true }
if ($Dev) { $pubArgs['Channel'] = 'dev'; $pubArgs['VersionOverride'] = $target }
# A dry run has to leave nothing behind, and NoUpload plus NoPush is not that.
#
# Those two stop the release LEAVING the machine. They do not stop the
# publisher writing version.json in the release clone or recording the release
# in its baseline, and it does both. So a dry run quietly consumed the next
# real release: the publisher had already written down that this source was
# published, and the Ship that followed correctly reported nothing had changed
# and shipped nothing. That happened twice on 17 Sep before anybody noticed,
# and the second time it looked exactly like a broken release.
#
# The two files are put back afterwards rather than the publisher being taught
# a third flag, because the publisher is the one script that must behave the
# same on a real release whatever else changes here.
$dryKeep = @()
if ($DryRun) {
    $pubArgs['NoUpload'] = $true
    $pubArgs['NoPush'] = $true
    Say '  dry run, nothing will be uploaded or pushed' 'Yellow'

    $stateName = if ($Dev) { 'published-dev.json' } else { 'published.json' }
    foreach ($f in @(
        (Join-Path $ReleaseDir 'version.json'),
        (Join-Path (Join-Path $env:LOCALAPPDATA 'Thornswood') $stateName)
    )) {
        if (Test-Path -LiteralPath $f) {
            $tmp = [IO.Path]::GetTempFileName()
            Copy-Item -LiteralPath $f -Destination $tmp -Force
            $dryKeep += [pscustomobject]@{ Path = $f; Copy = $tmp }
        } else {
            $dryKeep += [pscustomobject]@{ Path = $f; Copy = '' }
        }
    }
}

# global: for the reason at the client patch step.
$global:LASTEXITCODE = 0
& (Join-Path $Here 'Publish-Update.ps1') @pubArgs
$published = $LASTEXITCODE

if ($DryRun) {
    foreach ($k in $dryKeep) {
        try {
            if ($k.Copy) {
                Copy-Item -LiteralPath $k.Copy -Destination $k.Path -Force
                Remove-Item -LiteralPath $k.Copy -Force -EA SilentlyContinue
            } elseif (Test-Path -LiteralPath $k.Path) {
                # It did not exist before the dry run, so it must not after.
                Remove-Item -LiteralPath $k.Path -Force
            }
        } catch {
            Say ("  could not put " + $k.Path + " back: " + $_.Exception.Message) 'Red'
            Say '  the next release may think it has already gone out. Check it.' 'Red'
        }
    }
    # AND THE VERSION, which is the third file and was missed.
    #
    # The two above were put back because a dry run had twice consumed the next
    # real release. Updater.cs is the same fault with a different face: the bump
    # happens before the build, because the exe has to carry the number, and
    # nothing put it back. Measured 21 September: a dry run went 1.1.67 to
    # 1.1.68, left it there, and the real Ship that followed minutes later went
    # 1.1.68 to 1.1.69. 1.1.68 does not exist and never will.
    #
    # Unbump is the function written for exactly this and its own comment says
    # why: "a failed run burns a number and the launcher people are running
    # claims a version that was never published." A dry run is a run that does
    # not publish, so it is one of those.
    Unbump 'the dry run published nothing'
    Say '  dry run cleaned up: the feed, the baseline and the version are as they were' 'DarkGray'
}

# Ground truth, as well as the exit code.
#
# The publisher stopped dead on a missing baseline, printed STOP in red, and
# this script carried on to tell the Discord and empty the server for a
# release that does not exist. The guard below was already there and did not
# fire. The exit did reach the global $LASTEXITCODE; this script was reading a
# copy of its own, made by a bare $LASTEXITCODE = 0 (see the client patch
# step). The exit code is trustworthy now, and this check stays because a
# written version.json is a better witness than any number.
#
# version.json is the fact. It is the file the whole world reads to find out
# what the current launcher is, and the publisher writes it last, after every
# upload has landed. If it does not name the version just built, nothing was
# published, whatever any exit code says.
# A mods only release leaves the launcher version where it was, so the
# version check below has nothing to say about it; the exit code check
# further down still catches a publisher that stopped.
if (-not $DryRun -and -not $ModsOnly) {
    $landed = ''
    try {
        $vf = Join-Path $ReleaseDir 'version.json'
        if (Test-Path $vf) {
            $landed = [string]((Get-Content $vf -Raw | ConvertFrom-Json).launcherVersion)
        }
    } catch { }
    if ($landed -ne $target) {
        $said = if ($landed) { $landed } else { 'nothing at all' }
        Write-Host ''
        Say "NOTHING WAS PUBLISHED. version.json still says $said, not $target." 'Red'
        Say 'Read the publisher output above for the reason. The Discord has not' 'Red'
        Say 'been told, the server has not been touched, and nobody has been sent' 'Red'
        Say 'an update that does not exist.' 'Red'
        if ($target -ne $current) { Unbump 'the publish failed' }
        Write-Host ''
        if (-not $NoPause) { [void](Read-Host 'Enter to exit') }
        exit 1
    }
}

<#
  How far behind the installer is, worked out before anything can exit.

  This used to sit below the early return further down, so the one run that
  most needed it never printed: ship something, get told nothing changed,
  leave, and the package quietly stays another release behind. A count that
  only appears on the runs where it is least urgent is not a warning.
#>
# Staged out of the play install since 22 September: one folder per install
# root under the dev tree, the same shape Publish-Update and
# Package-Thornswood use, so the three agree on one answer. -DistRoot moves
# the lot. The old $Root\_dist is still read when it is the only one there, so
# a machine that has not published since the move still finds its installer.
$DistDir = Join-Path (Join-Path $DistRoot (Split-Path -Leaf $Root.TrimEnd('\'))) '_dist'
$zip = Join-Path $DistDir 'Thornswood-Setup.zip'
if (-not (Test-Path -LiteralPath $zip)) {
    $wasZip = Join-Path $Root '_dist\Thornswood-Setup.zip'
    if (Test-Path -LiteralPath $wasZip) { $zip = $wasZip }
}
$behind = 0
$haveZip = Test-Path $zip

if ($haveZip) {
    $zipTime = (Get-Item $zip).LastWriteTime
    $vf = Join-Path $ReleaseDir 'version.json'
    if (Test-Path $vf) {
        $doc = Get-Content $vf -Raw | ConvertFrom-Json
        if ($doc.PSObject.Properties['packs'] -and $doc.packs) {
            $seen = @{}
            foreach ($p in @($doc.packs)) {
                # ids are yyyyMMdd-HHmm, with -1 -2 -3 on the split ones, and
                # three parts of one release are still one release.
                $stamp = "$($p.id)"
                if ($stamp.Length -lt 13) { continue }
                $stamp = $stamp.Substring(0, 13)
                if ($seen.ContainsKey($stamp)) { continue }
                $seen[$stamp] = $true
                $when = [datetime]::MinValue
                if ([datetime]::TryParseExact($stamp, 'yyyyMMdd-HHmm', $null, 'None', [ref]$when)) {
                    if ($when -gt $zipTime) { $behind++ }
                }
            }
        }
    }
}

function Show-Installer {
    if (-not $haveZip) {
        Head 'The installer'
        Say '  there is no Thornswood-Setup.zip yet, so nobody new can install.' 'Yellow'
        Say '  .\tools\Package-Thornswood.ps1   builds it' 'Yellow'
        return
    }
    if ($behind -le 0) {
        Head 'The installer'
        Say '  Thornswood-Setup.zip is current' 'Green'
        return
    }
    Head 'The installer'
    Say ("  Thornswood-Setup.zip is {0} release{1} behind, built {2:d MMM HH:mm}." -f `
         $behind, $(if ($behind -eq 1) { '' } else { 's' }), $zipTime) 'Yellow'
    Say '  Anyone installing from it sits through all of those on first launch.' 'Yellow'
    Say '  Nobody who already has the game is affected.' 'DarkGray'
    Say '  .\tools\Package-Thornswood.ps1   to rebuild it, twenty minutes or so' 'Yellow'
}

# Anything other than 0 or 2 means the publisher stopped on an error. It used
# to carry on regardless: the site was told, the Discord was posted to, and the
# server counted everybody down and put them back to the launcher to collect an
# update that had never been published. That happened twice in one evening and
# each time the only sign was one red line halfway up the output.
#
# The version was bumped into Updater.cs before the build, so put it back
# rather than leaving a number nothing was ever published under. Otherwise the
# next attempt climbs again and the gap between what this machine calls itself
# and what the world has gets wider every time.
if ($published -ne 0 -and $published -ne 2) {
    Write-Host ''
    Say "The publisher stopped with exit code $published, so NOTHING was published." 'Red'
    Say 'The error is above, in the Publishing section.' 'Red'
    if ($target -ne $current) { Unbump 'the publish failed' }
    Say 'Nobody has been told and nobody has been moved. Fix it and run this again.' 'Yellow'
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 1
}

# Exit code 2 means the publisher found nothing worth a release. The version
# was already bumped and written into Updater.cs before the build, so put it
# back rather than leaving a number that was never published.
if ($published -eq 2) {
    if ($target -ne $current) {
        Unbump 'nothing was published'
        Say '  Rebuild the launcher next time you do ship, so the exe matches.' 'DarkGray'
    }
    Show-Installer
    Head 'Done'
    Say 'Nothing shipped. The build already matches the last release.' 'Yellow'
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 0
}

# ------------------------------------------------------------ the installer
if ($Dev) {
    Head 'The installer'
    Say '  dev release, the installer is not touched' 'DarkGray'
}
elseif ($Package) {
    Head 'Rebuilding the installer'
    & (Join-Path $Here 'Package-Thornswood.ps1') -Root $Root -OutDir $DistDir -NoPause

    # AND READ WHETHER IT WORKED, which is the same fault as the build step
    # above and entry 118 on the list: Ship called a script and never looked at
    # what it said. With -Package the installer is what a new person downloads,
    # so a packager that stopped halfway left the release saying it had been
    # rebuilt when it had not.
    #
    # IT DOES NOT STOP THE RELEASE, and that is deliberate rather than a
    # half fix. This step runs long after 'Publishing': the pack is already on
    # the feed by the time it starts. Dying here would leave a release that is
    # out with the site never told, the Discord never posted to and the server
    # never asked to restart, which is worse than an installer one release
    # behind. So it says exactly what happened, in red, with the command to put
    # it right. That the installer is rebuilt after the release goes out is its
    # own question and it is on the list.
    #
    # Package-Thornswood.ps1 ends with an explicit exit 0 for this, because a
    # script that runs off the end hands back whatever its last native command
    # left behind and it runs 7z and winget.
    if ($LASTEXITCODE -ne 0) {
        $script:InstallerFailed = $LASTEXITCODE
        Say "  THE INSTALLER DID NOT BUILD. Package-Thornswood.ps1 exited with $LASTEXITCODE." 'Red'
        Say '  The release itself is already published and is fine. What is not' 'Red'
        Say '  rebuilt is Thornswood-Setup.zip, so anybody installing from scratch' 'Red'
        Say '  sits through this release on first launch.' 'Red'
        Say '  .\tools\Package-Thornswood.ps1   to put that right' 'Yellow'
    }
}
else {
    Show-Installer
}

# ------------------------------------------------------------------- news
# The site's News page reads the same feed the launcher does, so it is current
# the moment a release goes out rather than whenever somebody remembers.
if (-not $DryRun -and -not $Dev) {
    $newsScript = Join-Path $Here 'Publish-News.ps1'
    if (Test-Path -LiteralPath $newsScript) {
        Head 'Telling the site'
        try { & $newsScript }
        catch { Say "  could not reach the site: $_" 'DarkGray' }
    }
}

# ----------------------------------------------------------------- discord
# Publish-Discord.ps1 has said "called by Ship.ps1 at the end of every release"
# since the day it was written, and nothing here ever called it. The webhook
# was set up, the script worked, and #news sat empty through every release.
# It exits quietly on its own if no webhook is configured, so there is nothing
# to guard here.
# A dev release goes to the dev updates channel and nowhere else. Not #news,
# not the website (the news step above is skipped for dev), and not the main
# launcher, which reads main's feed. The dev launcher's News tab gets it from
# the dev feed, as it always did; this is so the people testing it are told
# without anybody having to watch a version number.
if (-not $DryRun) {
    $discordScript = Join-Path $Here 'Publish-Discord.ps1'
    if (Test-Path -LiteralPath $discordScript) {
        Head 'Telling the Discord'
        try {
            if ($Dev) { & $discordScript -Dev }
            else      { & $discordScript }
        }
        catch {
            Say "  could not post to Discord: $_" 'Red'
            $global:ThornswoodDiscordResult = 'failed'
        }
    } else {
        Say ('  Publish-Discord.ps1 is missing, ' +
             $(if ($Dev) { 'the dev updates channel' } else { '#news' }) +
             ' was not told.') 'Yellow'
    }
}

# --------------------------------------------------------------- announce
if (-not $DryRun -and -not $NoAnnounce) {
    Head 'Telling the server'
    $announce = Join-Path $Here 'Request-Restart.ps1'
    if (Test-Path -LiteralPath $announce) {
        # THE TITLE ONLY, never the whole note.
        #
        # This is a line on screen in front of somebody mid-sentence with five
        # minutes before they are put back to the launcher. The full note has a
        # body and bullets now, and the 1.1.80 release sent all of it: four
        # bullet points and a paragraph, as an in-game warning. The News tab is
        # where the rest belongs and it is one click away.
        $why = ($Notes -split "`r?`n")[0].Trim()
        if (-not $why) { $why = $Notes }
        try {
            if ($Dev) { & $announce -Minutes $AnnounceMinutes -Mode update -Why $why -Data 'C:/Thornswood-Server-Dev/data' }
            else      { & $announce -Minutes $AnnounceMinutes -Mode update -Why $why }
        } catch {
            Say "  could not announce it: $_" 'Yellow'
            Say '  Ship still worked. Tell people yourself, or run' 'DarkGray'
            Say '  .\tools\Request-Restart.ps1 when the server is reachable.' 'DarkGray'
        }
    } else {
        Say '  Request-Restart.ps1 is missing, nobody was told.' 'Yellow'
    }
}

# ------------------------------------------------------- dev follows main
# Everything on dev was in this release, because a main pack is the difference
# from main's last release and the dev changes are part of that. So the dev
# feed is set to exactly what main now has, with the dev ports and the dev
# voice address kept, and the dev baseline becomes main's. Dev launchers take the main pack and the main
# launcher version, and the next Ship -Channel dev starts at .1 again.
#
# NOT AFTER A HOTFIX. A hotfix is the live build plus one fix, and the work
# sitting on dev was not in it, so "everything on dev was in this release" is
# false and the reset would take dev testers back to the hotfix until the next
# dev Ship. Dev is left as it was; its next Ship still climbs from the hotfix's
# number, because the dev version is read off main's published feed.
if (-not $DryRun -and -not $Dev -and -not $hotfix) {
    $devRel = Join-Path (Split-Path -Parent $MainReleaseDir) 'Thornswood-Releases-dev'
    if (Test-Path (Join-Path $devRel 'version.json')) {
        Head 'Resetting dev to match'
        try {
            $mainDoc = Get-Content (Join-Path $MainReleaseDir 'version.json') -Raw | ConvertFrom-Json
            $devDoc  = Get-Content (Join-Path $devRel 'version.json') -Raw | ConvertFrom-Json
            foreach ($keep in 'serverPort', 'voicePort', 'voiceUrl') {
                if ($devDoc.PSObject.Properties[$keep]) {
                    if ($mainDoc.PSObject.Properties[$keep]) { $mainDoc.$keep = $devDoc.$keep }
                    else { $mainDoc | Add-Member -NotePropertyName $keep -NotePropertyValue $devDoc.$keep }
                }
            }
            [IO.File]::WriteAllText((Join-Path $devRel 'version.json'), ($mainDoc | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
            $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            Push-Location $devRel
            try {
                & git add version.json 2>&1 | Out-Null
                & git commit -m "Dev follows main $target" 2>&1 | Out-Null
                & git push -u origin HEAD 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) { Say '  the dev feed did not push, run Ship -Channel dev once to sort it' 'Yellow' }
                else { Say "  dev feed now matches main $target, dev ports kept" 'Green' }
            } finally { Pop-Location; $ErrorActionPreference = $old }
            $stateDir = Join-Path $env:LOCALAPPDATA 'Thornswood'
            $mainState = Join-Path $stateDir 'published.json'
            if (Test-Path $mainState) { Copy-Item $mainState (Join-Path $stateDir 'published-dev.json') -Force; Say '  dev baseline is now main''s' 'Green' }
        } catch {
            Say "  could not reset the dev feed: $_" 'Yellow'
        }
    }
}

# SHIP NO LONGER COMMITS OR PUSHES ANYTHING.
#
# It used to `git add -A` here, commit the whole working tree under the release
# message, and push it straight to main. Two things were wrong with that and
# both have their own entry on the list. It swept up whatever happened to be
# sitting in the repo, so a release commit could carry eight unrelated things
# and could not be reverted. And it needed write access to main, which is the
# single reason enforce_admins had to stay off in branch protection: with the
# rules applying to the owner too, that push is refused, the release still
# reaches every launcher, and the source never lands.
#
# Now the version is bumped and committed by Bump-Version.ps1 beforehand, the
# Git gate above refuses a release with anything uncommitted or unpushed, and
# by the time anything is published the repository already says exactly what
# shipped. There is nothing left to do here, which is the point.
if (-not $DryRun -and -not $Dev -and (Test-Path (Join-Path $RepoDir '.git'))) {
    Head 'Source'
    Say "  already on GitHub. The gate above refused anything uncommitted or unpushed," 'DarkGray'
    Say "  so what shipped and what is written down are the same thing." 'DarkGray'
}

Head 'Done'
# Repeated here on purpose. A red line in the middle of a release log is a line
# nobody reads: the last screen is the one that gets looked at.
if ($script:InstallerFailed) {
    Say ("The installer did NOT rebuild (exit $script:InstallerFailed). The release went out " +
         'without it.') 'Red'
    Say '  .\tools\Package-Thornswood.ps1' 'Yellow'
    Write-Host ''
}
# The release is out either way, and the people who would have read the post
# do not know it. Said here because this is the screen that gets looked at.
if ($global:ThornswoodDiscordResult -eq 'failed') {
    Say ('The release went out, but ' +
         $(if ($Dev) { 'the dev updates channel' } else { '#news' }) +
         ' was NOT told.') 'Yellow'
    Say ('  .\tools\Publish-Discord.ps1' + $(if ($Dev) { ' -Dev' } else { '' }) +
         '   posts it on its own') 'Yellow'
    Write-Host ''
}
if ($DryRun) { Say 'Dry run finished. Nothing left your machine.' 'Yellow' }
elseif ($NoAnnounce) { Say 'Everyone gets it next time they open the launcher.' 'Green' }
else {
    Say ("Everyone in the world has $AnnounceMinutes minutes, then they are put " +
         'back to the launcher to pick it up.') 'Green'
}
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
