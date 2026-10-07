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
  uncommitted or unpushed, or if a file in a folder a release is built from is
  one git does not know, so what ships and what is written down are the same
  thing.

      .\scripts\release\Bump-Version.ps1        then the branch and pull request it prints
      git checkout main; git pull     once that pull request is merged
      .\scripts\release\Ship.ps1 "..."

  THE NOTE IS WHAT CUSTOMERS READ, in the launcher's News tab, on the site and
  in #news. It takes several lines and splits them: the first line is the
  title, a line starting with a dash becomes a bullet, and the rest becomes the
  body. A one-line note leaves the body empty and the details as nothing but
  the version and the download size, which is how "Everything from dev" reached
  people on 22 September and told them nothing.

      .\scripts\release\Ship.ps1 "The map marker points at the right door now
      It pointed one building east in four towns, which is why directions from
      other people never matched what you saw.
      - Map markers in Riverwood, Whiterun, Falkreath and Rorikstead
      - Nothing to reinstall, it arrives with the update"

  EVERY OPTION HAS ITS OWN .PARAMETER BELOW, and Get-Help puts each one beside
  what the param block declares, so nobody has to open this file to see them:

      Get-Help .\scripts\release\Ship.ps1 -Full
      Get-Help .\scripts\release\Ship.ps1 -Parameter Channel

  AFTER A SUCCESSFUL TIP the host feed is remirrored, then the site news and
  Discord / server countdown tell people to update. Publish-PostShip.ps1, keyed
  off -Channel, owns the remirror and calls the website lane's script:

      1  the host feed remirror   scripts\deploy\Remirror-Site-Feed.ps1, the
                                  website lane's. It checks every asset the
                                  feed names is on thornswood.net/feed/ (-Dev:
                                  /feed-dev/). Since #907 the publisher has
                                  already sent version.json to the VPS store
                                  there, so this finds it in place.
      2  the site news            Publish-News.ps1, then the #news post and the
                                  server's countdown, all unchanged and the news
                                  main only, as they always were.

  VirusTotal is no longer part of publish (#802). Code signing covers trust
  (#390). Publish-VirusTotal.ps1 stays as an optional manual tool.

  The feed is mirrored before the news steps tell people to update, because
  they send everybody to fetch a release the feed has to be serving.

  A MAIN SHIP ALSO MOVES THE DEV FEED'S DEV MARKS, right after the remirror:
  Refresh-DevNews.ps1 marks DEV only the dev notes main still does not have
  and sets the dev feed's mainVersion, and sends nothing else (Dev-News.ps1).

  NOTHING NEW IS NOT ANNOUNCED. When the publisher released nothing (exit
  code 2) Ship says so and stops: no remirror, no news, no Discord post, no
  server countdown, no tag. A dev Ship with nothing new still brings the dev
  feed's DEV marks up to date with main, and says whether it did.

  LAST, THE TAG (#444). A release goes by one name, the id its packs carry
  (20260928-1630, or 20260928-2324-dev on dev), and the feed records its
  launcher, packs, baseline and commit against it (Release-Name.ps1). Once the
  publisher has sent the feed, Ship tags that commit release/main/<id> or
  release/dev/<id> and pushes the tag. Never on a dry run, and a tag that did
  not go on is a line at the end, not a failed release.

  NO SWITCH TURNS THE REMIRROR OFF, asked for by the website and launcher
  lanes on 27 September: the block runs on every release, dev and main, so the
  dev channel exercises it several times a week. A dry run runs none of it,
  because a dry run publishes nothing to follow.

  AND THE REMIRROR CANNOT FAIL A RELEASE. It runs after the release is on the
  feed, so nothing there can unpublish anything. A script another lane has not
  landed is a line naming it. A remirror that exits 1 has refused to publish a
  feed naming bytes the site does not hold, which leaves the site one release
  behind rather than pointing launchers at a 404, and the website lane asked for
  that to be a line as well: "Exit 1 = refused publish (do not fail the
  release)". So Ship says on its last screen what did not happen and what to run,
  and still exits 0.

  This header used to carry a hand-written list of five options, laid out as
  if it were all of them, while the param block declared thirteen. -Channel,
  the one the whole dev workflow runs on, was in the param block and nowhere
  else, and Get-Help printed nothing but the syntax line (entry 260 on the To
  Do List). tests\test-script-index.ps1 now fails the build check when a
  parameter is declared here without a .PARAMETER of its own.

.PARAMETER Notes
  What customers read about this release: the launcher's News tab, the site
  and #news for a main release, the dev launcher's News tab and the dev
  updates channel for a dev release. Mandatory, and the only option taken by
  position, so it can come first without its name. The first line is the
  title, a line starting with a dash becomes a bullet, and the rest becomes
  the body. The server's warning before the restart carries the title only.
  Since 25 September Ship refuses notes without a title of three words or
  more and at least one "- " detail line.

.PARAMETER Version
  A dev build's number, for example 1.2.0.1, in place of the one Ship would
  work out from the dev feed. It is written into app\Updater.cs for the build
  and put back afterwards, so it only ever lives in the dev feed.

  A main release refuses it. Main ships the number already on main, and
  .\scripts\release\Bump-Version.ps1 -To 1.2.0 moves that number first, through its own
  pull request, before Ship runs without -Version. The same number main
  already has is let through, because it changes nothing. -ModsOnly keeps the
  number where it is whatever this says.

.PARAMETER NoBump
  Kept for anything that passes it. Every main release now keeps the version
  number, so it changes nothing.

.PARAMETER ModsOnly
  Skips the launcher and publishes only the mod files that changed. The
  version number stays where it is.

  Since issue #921 a Ship does this by itself when nothing the launcher is
  compiled from (launcher\, records\client-build.json, Build-Launcher.ps1)
  changed since the launcher on that channel's feed: no new version, no
  build, no signing, and the feed keeps the launcher it has.

.PARAMETER RebuildLauncher
  Build, sign and publish a new launcher even when nothing it is compiled
  from changed since the one on the feed.

.PARAMETER DryRun
  Builds and works out what would ship, and uploads no pack, publishes no
  feed and tells nobody: no news post, no warning from the server. The git
  checks are skipped, and the feed, the baseline and the version number are
  put back afterwards.

  DryRun is non-destructive for close and prune (issue #494): it does not
  close a running game or launcher, and it does not delete old pack-*.zip
  under -DistRoot. It logs what a real Ship would close or prune. Without
  -ModsOnly it still builds and may put the new Thornswood.exe in
  <Root>\Launcher (without closing anything first) and copies the plugins
  into the game folder. The pack it makes stays in -DistRoot. The first
  -Channel dev run on a machine makes the dev branch of the releases repo
  and pushes it to GitHub, so a dry run on a machine whose releases repo
  has no dev branch stops rather than make one: run -Channel dev once
  without -DryRun.

  With -Package the installer is not rebuilt, because Package-Thornswood.ps1
  puts what it builds on the site. The dry run says so and prints the
  -NoPublish line that builds one and publishes nothing.

.PARAMETER Package
  Also rebuilds the two installer files for new people, after the release is
  out, and puts them on the site. Twenty minutes or more. Not on a -DryRun,
  and a dev release never touches the installer.

.PARAMETER Root
  The Thornswood install whose launcher is built and whose files are
  published. Left out, it is the folder this machine builds the channel's
  release from, which Where.ps1 ShipRoot and ShipRootDev answer (#1692): the
  one Setup-ShipMachine.ps1 -Root recorded, or else the first of
  C:\Thornswood and Thornswood on any other fixed drive that has
  Launcher\Thornswood.exe in it, and for a dev release that folder with
  -DevBuild on the end, where the main launcher's Settings page installs the
  dev build. A folder Vortex deploys into is refused either way, before
  anything is built.

.PARAMETER DistRoot
  Where releases are staged and zipped, passed straight through to
  Publish-Update and Package-Thornswood so all three agree. Not under -Root:
  that is the folder people play from.

.PARAMETER MoveServer
  Lets a main release change the server address in version.json. Without it,
  a release whose config.json names a different server from the one the feed
  has stops before anything is published, because that address moves
  everybody.

.PARAMETER AcceptSize
  Passed straight to Publish-Update, which refuses a release bigger than its
  cap (-MaxReleaseMB, 3072 by default) and lists the biggest files, because
  the release that nearly went out on 17 September was the whole mod
  collection. Give it only once you have read what made the release that big.

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
  uncommitted, that has a file in a folder a release is built from that git
  does not know about (the build and Go.ps1 would take it anyway), or that
  asks for a new number with
  -Version. A hotfix/ branch is the live build plus one fix and its version
  bump, cut from the commit the live release was built from. Ship refuses
  one that is not on GitHub, and it is Patrick's call like any live release.

  dev builds and publishes the second launcher: the dev branch of the
  releases repo, the dev server, and a version like 1.1.35.3 that a main
  release always outranks. It may ship from any branch, on either machine.

  THERE IS ONE DEV FEED AND THE LAST DEV SHIP WINS. Both machines publish to
  the same one, so a dev Ship replaces whatever the other machine put there.
  Say in #staff-general before taking it. A main Ship resets dev to match main. A
  hotfix does not, because the work on dev was not in it.

  Everything goes to dev first, decided by Patrick on 23 September: "even
  small changes go to the dev build launcher for pretesting". A main Ship is
  for a security fix or for something that leaves the game untestable, and he
  says which.

.PARAMETER AllowUncoveredBodies
  Lets a main release go out while a body in the game folder is nude (issue
  #405). A main release reads the collection revision this machine has
  installed and tells every launcher to match it, so it refuses while
  scripts\mods\Check-CoveredBodies.ps1 finds a nude body here; a dev release
  only warns. Give it for a security fix that cannot wait for the covered
  bodies' collection revision, and only on Patrick's word. A body mesh the
  check cannot read refuses on both channels, with or without it (#1956).

.EXAMPLE
  .\scripts\release\Ship.ps1 -Channel dev "The map marker points at the right door now"

  Puts this branch on the dev build and the dev server for testing. Say in
  #staff-general first: the last dev Ship wins.

.EXAMPLE
  .\scripts\release\Ship.ps1 -DryRun "The map marker points at the right door now"

  Builds and works out what would ship without publishing it. It does not
  close a running game and does not prune old packs; it may still put the
  new launcher in place without closing anything. Get-Help
  .\scripts\release\Ship.ps1 -Parameter DryRun lists what a dry run still does.

.EXAMPLE
  .\scripts\release\Ship.ps1 "The map marker points at the right door now"

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
    ,[string]$DistRoot = (& (Join-Path $PSScriptRoot 'Where.ps1') Dist)
    ,[switch]$MoveServer
    # Passed straight to Publish-Update, which refuses a release bigger than
    # its cap because the one that nearly went out on 17 September was the
    # whole mod collection. Without this here the refusal could only be
    # answered by running the publisher by hand, around everything Ship checks.
    ,[switch]$AcceptSize
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
    # Build, sign and publish a new launcher even when nothing it is compiled
    # from changed since the one on the feed (issue #921).
    ,[switch]$RebuildLauncher
    # A main release with a nude body in the game folder (issue #405).
    ,[switch]$AllowUncoveredBodies
)


# The launcher, Thornswood.exe in the launcher folder.
function Get-LauncherExe([string]$dir) {
    return (Join-Path $dir 'Thornswood.exe')
}

# ==== thornswood release launcher ====
# WHERE THE SHIPPED EXE COMES FROM, since issue #457: a clean runner, not this
# machine. .github\workflows\release.yml builds Thornswood.exe on a dated
# Windows image from the tagged commit, writes SHA256SUMS beside it, and
# attaches both to the draft release for that tag. A main release downloads that
# asset and checks it against SHA256SUMS rather than compiling the binary that
# reaches every launcher here, so the person shipping never runs csc on what
# ships. Byte-identical local and runner builds are not possible with the
# Framework 4 csc, which stamps a build time and a fresh MVID into the PE, so
# nothing compares against a local build: the runner's exe IS the shipped exe,
# and its checksum file is what proves the download is that exe and nothing else.

# Which repository the release.yml draft is on: the source clone's origin, where
# the workflow runs and creates it, not the releases clone the packs go to.
function Get-SourceRepo([string]$repoDir) {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $remote = ''
    try { $remote = (& git -C $repoDir remote get-url origin 2>$null | Select-Object -First 1) } catch { }
    $ErrorActionPreference = $old
    if ($remote -and $remote -match 'github\.com[:/](.+?)(?:\.git)?\s*$') { return $Matches[1] }
    return 'EvilPatrick06/Thornswood'
}

# Downloads Thornswood.exe and SHA256SUMS for tag v<version> into $into and
# checks the exe against its line in SHA256SUMS. Returns '' when the verified
# exe is sitting in $into, or a sentence saying why not, for the caller to Die
# on: nothing here compiles anything or writes to the repository.
function Get-ReleaseLauncher([string]$repo, [string]$version, [string]$into) {
    $tag = 'v' + $version
    if (-not (Get-Command gh -EA SilentlyContinue)) {
        return 'gh is not installed, so the launcher CI built cannot be downloaded. Install the GitHub CLI, gh auth login, then Ship again.'
    }
    New-Item -ItemType Directory -Force -Path $into | Out-Null
    foreach ($n in 'Thornswood.exe', 'SHA256SUMS') {
        $p = Join-Path $into $n
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
    }
    $repoArg = @(); if ($repo) { $repoArg = @('--repo', $repo) }
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & gh release download $tag @repoArg --dir $into --pattern 'Thornswood.exe' --pattern 'SHA256SUMS' --clobber 2>&1 | Out-Host
    $rc = $LASTEXITCODE
    $ErrorActionPreference = $old
    $exe = Join-Path $into 'Thornswood.exe'
    $sums = Join-Path $into 'SHA256SUMS'
    if ($rc -ne 0 -or -not (Test-Path -LiteralPath $exe) -or -not (Test-Path -LiteralPath $sums)) {
        return ("There is no verified launcher for $tag on $repo yet. CI builds the exe that ships; this machine does not compile it. " +
                "Push the tag to build it, wait for the ""Build the release launcher"" run to attach Thornswood.exe and SHA256SUMS to the " +
                "draft release, then run this same Ship again:`r`n" +
                "    git tag $tag`r`n" +
                "    git push origin $tag")
    }
    # SHA256SUMS is "<hash>  Thornswood.exe", the sha256sum shape, so the line
    # for the exe is found and its hash compared with the download's.
    $want = ''
    foreach ($line in [IO.File]::ReadAllLines($sums)) {
        $m = [regex]::Match($line, '(?i)^\s*([0-9a-f]{64})\s+\*?Thornswood\.exe\s*$')
        if ($m.Success) { $want = $m.Groups[1].Value.ToLower(); break }
    }
    if (-not $want) { return "SHA256SUMS from $tag has no line for Thornswood.exe, so the download cannot be verified. Nothing was published." }
    $got = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLower()
    if ($got -ne $want) {
        return ("The launcher downloaded for $tag does not match its SHA256SUMS (wanted $want, got $got). Do not ship it. Nothing was published.")
    }
    return ''
}

# THE SETUP PROGRAM COMES FROM CI TOO, issue #932. Package-Thornswood.ps1
# builds the installer around setup-stub.exe, which Build-Launcher.ps1
# compiles. A main Ship takes the launcher CI built and never runs
# Build-Launcher, so on 28 September Ship -Package on main stopped on
# "setup-stub.exe is missing" after the release was already published, and
# the stub in a shared clone's out\ is whatever the last local build left,
# from whichever branch. release.yml builds the stub beside the launcher from
# the same tagged commit and lists both in SHA256SUMS; this downloads it into
# $into and checks it, the same way as the launcher. Returns '' when the
# verified stub is in $into, or a sentence saying why not. A release drafted
# before #932 has no stub: building that tag again attaches one.
function Get-ReleaseStub([string]$repo, [string]$version, [string]$into) {
    $tag = 'v' + $version
    $again = ("Build the release for $tag again, which attaches the setup program beside the launcher, wait for the " +
              """Build the release launcher"" run to finish, then run this same Ship again:`r`n" +
              "    gh workflow run release.yml --repo $repo -f tag=$tag")
    if (-not (Get-Command gh -EA SilentlyContinue)) {
        return 'gh is not installed, so the setup program CI built cannot be downloaded. Install the GitHub CLI, gh auth login, then Ship again.'
    }
    New-Item -ItemType Directory -Force -Path $into | Out-Null
    foreach ($n in 'setup-stub.exe', 'SHA256SUMS') {
        $p = Join-Path $into $n
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
    }
    $repoArg = @(); if ($repo) { $repoArg = @('--repo', $repo) }
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & gh release download $tag @repoArg --dir $into --pattern 'setup-stub.exe' --pattern 'SHA256SUMS' --clobber 2>&1 | Out-Host
    $rc = $LASTEXITCODE
    $ErrorActionPreference = $old
    $stub = Join-Path $into 'setup-stub.exe'
    $sums = Join-Path $into 'SHA256SUMS'
    if ($rc -ne 0 -or -not (Test-Path -LiteralPath $stub) -or -not (Test-Path -LiteralPath $sums)) {
        return ("The release for $tag on $repo has no setup program (setup-stub.exe), so -Package would build an installer " +
                "with nothing to run it. Nothing was published. " + $again)
    }
    $want = ''
    foreach ($line in [IO.File]::ReadAllLines($sums)) {
        $m = [regex]::Match($line, '(?i)^\s*([0-9a-f]{64})\s+\*?setup-stub\.exe\s*$')
        if ($m.Success) { $want = $m.Groups[1].Value.ToLower(); break }
    }
    if (-not $want) { return ("SHA256SUMS from $tag has no line for setup-stub.exe, so the download cannot be verified. Nothing was published. " + $again) }
    $got = (Get-FileHash -LiteralPath $stub -Algorithm SHA256).Hash.ToLower()
    if ($got -ne $want) {
        return ("The setup program downloaded for $tag does not match its SHA256SUMS (wanted $want, got $got). Do not ship it. Nothing was published.")
    }
    return ''
}

# THE TAG IS OLDER THAN THE LAUNCHER ON MAIN, issue #883. The exe CI built for
# v<version> is the source at that tag, so a main Ship that has not moved the
# version takes the exe of the last bump and quietly leaves out every launcher
# change merged since. 20260927-1633 went out that way: its Thornswood.exe is
# byte for byte the one from 20260927-0508 (sha256 38d4cd5d...), built from
# v1.1.101 (deace6b), so Main never got the menu music fix (#772, #779) that
# its own notes announced. And records\client-build.json is compiled into the
# exe, so the stale launcher called the new client runtime in that same pack
# "not the recorded build" and put the old skymp5-client.js back.
# Returns the changed paths under launcher\ and records\client-build.json
# between the tag and HEAD, or nothing when the tag is not here to compare
# with (Get-ReleaseLauncher stops that Ship anyway). Markdown is not built.
function Get-LauncherDrift([string]$repoDir, [string]$tag) {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        & git -C $repoDir rev-parse --verify --quiet "refs/tags/$tag" *> $null
        if ($LASTEXITCODE -ne 0) {
            & git -C $repoDir fetch --quiet origin "refs/tags/$($tag):refs/tags/$tag" *> $null
            & git -C $repoDir rev-parse --verify --quiet "refs/tags/$tag" *> $null
            if ($LASTEXITCODE -ne 0) { return @() }
        }
        $paths = @(& git -C $repoDir diff --name-only "refs/tags/$tag" HEAD -- launcher records/client-build.json ':(exclude,glob)**/*.md' 2>$null |
                   Where-Object { $_ })
        if ($LASTEXITCODE -ne 0) { return @() }
        return $paths
    } finally { $ErrorActionPreference = $old }
}

# THE EXE CI BUILT IS NOT SIGNED, issue #921. release.yml compiles on the VPS
# runner, which holds no signing certificate, so Sign-Artifact.ps1 there says
# "not signing" and every v<version> draft carries an unsigned Thornswood.exe.
# 20260927-1633 put exactly that on Main as 1.1.101 (sha256 38d4cd5d...), an
# hour before the publish sign gate existed. Since then the gate refuses it,
# which is safe but means no main Ship can go out at all.
# So a main Ship signs the verified download here, with the same Sign-Artifact
# and records\signing\signing.json a dev build signs with, -Required so a machine that
# cannot sign stops, and reads it back against ExpectedSigner before a byte of
# it is installed or packed. Already signed by us: left alone. Returns '' when
# the exe is signed by ExpectedSigner, or a sentence saying why not.
# Needs Get-PublishSignRefusal (Assert-PublishSigned.ps1) dot-sourced first.
function Set-ReleaseLauncherSignature([string]$exe, [string]$signer, [string]$expectedSigner) {
    if (-not $exe -or -not (Test-Path -LiteralPath $exe)) {
        return "There is no launcher at $exe to sign. Nothing was published."
    }
    if (-not $expectedSigner) {
        return 'ExpectedSigner is empty, so there is nothing to check the signature against. Nothing was published.'
    }
    if (-not (Get-PublishSignRefusal -Path $exe -ExpectedSigner $expectedSigner)) { return '' }
    if (-not $signer -or -not (Test-Path -LiteralPath $signer)) {
        return "Sign-Artifact.ps1 is not at $signer, so the launcher CI built cannot be signed. Nothing was published."
    }
    $global:LASTEXITCODE = 0
    & $signer -Path $exe -Required | Out-Host
    $rc = $LASTEXITCODE
    if ($rc -ne 0) {
        return ("Signing the launcher CI built stopped with exit code $rc. A main release has to be signed, " +
                'the same as a dev one: Ship from the machine that holds records\signing\signing.json. Nothing was published.')
    }
    $why = Get-PublishSignRefusal -Path $exe -ExpectedSigner $expectedSigner
    if ($why) { return ('Signing said it worked, but ' + $why) }
    return ''
}

# WHAT THE LAUNCHER IS COMPILED FROM, as one sha256, issue #921. Every file
# under launcher\ but the Markdown (the code, ui.xaml, the art, the video, the
# WebView2 loader, the manifest), records\client-build.json, which is compiled
# in, and Build-Launcher.ps1, which writes the version resource and picks what
# goes in. Read off the working tree, not git, so a dev Ship of uncommitted
# work counts it. Paths with / and sorted ordinally, so the same tree gives the
# same answer on any machine; a line ending changed by git's autocrlf gives a
# different one, which costs a rebuild and nothing worse.
function Get-LauncherInputHash([string]$repoDir) {
    $lines = New-Object System.Collections.Generic.List[string]
    $launcherDir = Join-Path $repoDir 'launcher'
    if (Test-Path -LiteralPath $launcherDir) {
        foreach ($f in @(Get-ChildItem -LiteralPath $launcherDir -Recurse -File -Force -EA SilentlyContinue |
                         Where-Object { $_.Extension -ne '.md' })) {
            $rel = 'launcher/' + $f.FullName.Substring($launcherDir.Length).TrimStart('\', '/').Replace('\', '/')
            $lines.Add($rel + "`t" + (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant())
        }
    }
    foreach ($rel in 'records/client-build.json', 'scripts/release/Build-Launcher.ps1') {
        $p = Join-Path $repoDir $rel
        $h = 'missing'
        if (Test-Path -LiteralPath $p) { $h = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() }
        $lines.Add($rel + "`t" + $h)
    }
    $arr = $lines.ToArray()
    [Array]::Sort($arr, [StringComparer]::Ordinal)
    $bytes = [Text.Encoding]::UTF8.GetBytes(($arr -join "`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return (-join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })) }
    finally { $sha.Dispose() }
}

# The launcher a channel's feed offers now ($branch is the channel, main or
# dev), read from the site and from the copy last received into $dir when the
# site cannot say. $null when there is no feed to read.
function Get-PublishedLauncher([string]$dir, [string]$branch) {
    # The feed as the site serves it (Read-SiteFeed, Feed-Store.ps1, #907),
    # which is what launchers have; the copy last received into $dir only when
    # the site cannot be read. Until #907 this read origin/<branch> of the
    # Thornswood-Releases clone.
    $doc = $null
    if (Get-Command Read-SiteFeed -ErrorAction SilentlyContinue) {
        try { $doc = Read-SiteFeed $branch } catch { $doc = $null }
    }
    if ($null -eq $doc) {
        if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { return $null }
        $f = Join-Path $dir 'version.json'
        if (-not (Test-Path -LiteralPath $f)) { return $null }
        try { $doc = ([IO.File]::ReadAllText($f) -replace ('^' + [char]0xFEFF), '') | ConvertFrom-Json } catch { return $null }
    }
    if ($null -eq $doc) { return $null }
    function Field($o, [string]$k) { if ($o -and $o.PSObject.Properties[$k] -and $null -ne $o.$k) { return ([string]$o.$k).Trim() } return '' }
    return [pscustomobject]@{
        Version = (Field $doc 'launcherVersion')
        Url     = (Field $doc 'launcherUrl')
        Sha     = (Field $doc 'launcherSha256')
        Inputs  = (Field $doc 'launcherInputs')
    }
}

# True only when the feed names a whole launcher (version, url, sha256) AND the
# fingerprint it was published with is this one. A feed with no fingerprint,
# which is every feed before issue #921, is never "unchanged".
function Test-LauncherUnchanged($published, [string]$inputs) {
    if ($null -eq $published -or -not $inputs) { return $false }
    if (-not $published.Inputs -or -not $published.Version -or -not $published.Url) { return $false }
    if ($published.Sha -notmatch '^[0-9a-fA-F]{64}$') { return $false }
    return ($published.Inputs -eq $inputs)
}
# ==== end thornswood release launcher ====

function Assert-DevVersionSelection([string]$selected, [string]$current, [bool]$aligned, [string[]]$published) {
    if ($aligned -and $selected -ne $current) {
        Die "Main-equivalent source ships $current in both channels. Use a separate branch for a different Dev version."
    }
    function Normalized([string]$text) {
        $v = [version]$text
        return [version]::new($v.Major, $v.Minor, [Math]::Max(0, $v.Build), [Math]::Max(0, $v.Revision))
    }
    $candidate = Normalized $selected
    foreach ($text in @($published)) {
        if ($text -and (Normalized $text) -gt $candidate) {
            Die "Dev cannot downgrade the published version $text to $selected. Bump Main above the published Dev version before shipping both channels."
        }
    }
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
# Which of the three follow-ons did not complete, read back in the Done
# section and by the exit code at the end. Empty on every release that went out
# whole, which is the usual one, so it is seeded here like the two above.
$script:PostShipFailed = @()

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; Write-Host ''; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$RepoDir = Split-Path -Parent (Split-Path -Parent $Here)
# Launcher / setup-stub .pdb stay on this machine only (Ship-Rules, issue #462).
. (Join-Path $Here 'Ship-Rules.ps1')
# The publish sign helpers, loaded here rather than at the publish gate because
# a main Ship signs and checks the exe CI built before it is installed (#921).
. (Join-Path $Here 'Assert-PublishSigned.ps1')
# The feed and its baseline live on the VPS beside the feed the site serves,
# and each channel has a working folder on this machine that Publish-Update
# receives them into and sends them back from (Feed-Store.ps1, #907). Until
# then they were clones of Thornswood-Releases beside this repository.
. (Join-Path $Here 'Feed-Store.ps1')
# The release's one name and its tag (#444).
. (Join-Path $Here 'Release-Name.ps1')
$Dev = ($Channel -eq 'dev')
$ReleaseDir = Get-FeedStoreDir $Channel
$MainReleaseDir = Get-FeedStoreDir 'main'

# ---- where the release is built from ----------------------------------------
#
# The folder this machine builds the channel's release from, which Where.ps1
# answers for Ship, Check-ShipReady, Setup-ShipMachine and Build-Generated
# alike (#1692): the one Setup-ShipMachine.ps1 -Root recorded, or else the
# launcher install, C:\Thornswood or Thornswood on another fixed drive, and for
# dev that plus -DevBuild, where the main launcher's Settings page installs it
# (DevBuild.cs). -Root still wins.
if (-not $PSBoundParameters.ContainsKey('Root')) {
    try { $Root = [string](& (Join-Path $Here 'Where.ps1') $(if ($Dev) { 'ShipRootDev' } else { 'ShipRoot' })) }
    catch { Die ($_.Exception.Message + ' Nothing was built.') }
}

# ------------------------------------------------------------ dev channel
# The dev build has its own feed and baseline on the VPS (feed-dev), and its
# own working folder here. Until #907 it was a git worktree of the dev branch
# of Thornswood-Releases, made on first use.
if ($Dev) {
    if (-not (Test-Path (Join-Path $Root 'Launcher'))) {
        Die "No dev build at $Root. Install it from the main launcher's Settings page (The dev build) first, or record the folder this machine builds dev from: .\scripts\release\Setup-ShipMachine.ps1 -Channel dev -Root <folder>."
    }
}

# A folder Vortex deploys into is the collection's source, not a release
# folder (#1692, docs\COLLECTION-REVISION-2.md step 8): Vortex writes its own
# record, Data\vortex.deployment.json, into it, Build-Generated never builds
# there, so a Ship from it could only stop at the generated files, and on
# 4 October one did, after it had built and installed the launcher there.
# Refused here, before anything is built, whichever way the folder was named.
if (Test-Path -LiteralPath (Join-Path $Root 'Game\Data\vortex.deployment.json')) {
    Die ("$Root is a folder Vortex deploys into (Game\Data\vortex.deployment.json is there), so a release is never built from it. Nothing was built. " +
         "Ship with -Root <the release folder>, or record it once: .\scripts\release\Setup-ShipMachine.ps1 -Channel $Channel -Root <the release folder>.")
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
# IT REFUSES NOW. Patrick, 25 September, after two dev posts in a row went
# out as "The scroll glows" and "Dev build: ...", beside earlier ones with a
# title and three bullets each: every post must have details and be as good
# as those. A title of at least three words that is not a placeholder, and
# at least one "- " line saying what somebody will notice. Checked before
# anything is built, so nothing is half done when it stops.
$noteLines = @($Notes -split "`r?`n")
$noteTitle = (@($noteLines | Where-Object { $_.Trim() }) + @(''))[0].Trim()
$noteBullets = @($noteLines | Where-Object { $_ -match '^\s*-\s*\S' -and ($_ -replace '^\s*-\s*', '').Trim().Length -ge 12 })
$placeholder = $noteTitle -match '^[\W_]*$' -or $noteTitle -match '^(test|testing|wip|update|updates|fix|fixes|changes|stuff|dev|build|misc)\W*$'
if ($placeholder -or @($noteTitle -split '\s+' | Where-Object { $_ }).Count -lt 3 -or $noteBullets.Count -lt 1) {
    Write-Host ''
    Say '  STOP. These notes are what people read in the launcher, on the site and' 'Red'
    Say '  in Discord, and they need a real title and details. Nothing was built.' 'Red'
    if ($placeholder -or @($noteTitle -split '\s+' | Where-Object { $_ }).Count -lt 3) { Say "  The title '$noteTitle' is too short to say what changed." 'Yellow' }
    if ($noteBullets.Count -lt 1) { Say '  There is no detail line: at least one line starting with "- ".' 'Yellow' }
    Write-Host ''
    Say '  The shape, written from the side of the person playing:' 'DarkGray'
    Say '      .\scripts\release\Ship.ps1 -Channel dev "The scroll''s Continue gives you the full three minutes' 'DarkGray'
    Say '      - Time spent reading the sealed scroll no longer counts against choosing a character.' 'DarkGray'
    Say '      - After you press Continue you get the whole three minutes to pick one."' 'DarkGray'
    exit 1
}

# And what the words may be. Note-Rules.ps1 says why: on 26 and 27 September
# notes went out saying players, naming PR #239, env variables, code names and
# the shipping machine, and one list said "Launcher 1.1.101" twice.
. (Join-Path $PSScriptRoot 'Note-Rules.ps1')
$noteProblems = @(Get-NoteProblems $Notes)
if ($noteProblems.Count) {
    Write-Host ''
    Say '  STOP. These notes are for the people who play, and they say things only' 'Red'
    Say '  we would understand. Nothing was built. Rewrite these:' 'Red'
    foreach ($p in $noteProblems) { Say "    $p" 'Yellow' }
    Write-Host ''
    Say '  Say what somebody will notice in the game or the launcher, in plain words.' 'DarkGray'
    exit 1
}
Write-Host "  $Notes" -ForegroundColor DarkGray

# The words in the files people read, not only the notes. Note-Rules above
# reads the release notes. Check-Words reads the launcher help and window,
# and every other page a Ship sends out (issue #1081). A dev Ship may be run
# from any branch, including one whose pull request build never ran or went
# red, so this runs here, before anything is built, and on a dry run too.
# Each hit names its file, its line and its rule. exit in that script ends
# the process it runs in, so it runs in a child: a clean tree comes back
# here and the Ship goes on, and a hit stops the Ship.
$wordsScript = Join-Path $RepoDir 'scripts\dev\Check-Words.ps1'
if (-not (Test-Path -LiteralPath $wordsScript)) {
    Die 'scripts\dev\Check-Words.ps1 is not there, so the words people read cannot be checked. Nothing was built.'
}
$wordsHost = (Get-Process -Id $PID).Path
$global:LASTEXITCODE = 0
$wordsText = [string](& $wordsHost -NoProfile -ExecutionPolicy Bypass -File $wordsScript -Root $RepoDir 2>&1 | Out-String)
$wordsCode = $LASTEXITCODE
if ($wordsText.Trim()) { Write-Host $wordsText.TrimEnd() }
$hitLines = @($wordsText -split "`r?`n" | Where-Object { $_ -match '::error ' } | ForEach-Object { $_.Trim() })
if ($wordsCode -ne 0 -or $hitLines.Count -gt 0) {
    $named = if ($hitLines.Count) { $hitLines -join ' | ' } else { 'Check-Words.ps1 exited ' + $wordsCode + ' and named no hit' }
    Die ('The writing rules do not hold. Nothing was built. ' + $named)
}

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
    # And the files git has never been told about, which the line above
    # leaves out, in every folder a release is built from: the site's art goes
    # into the menu, and game, launcher and installer hold the plugins, the
    # launcher source and the installer. Ignored ones are not counted (the
    # webhooks, records\signing\signing.json, __pycache__, a log), because
    # counting them would stop every main release. tools\ went on 29 September
    # (issue #440, phase 10).
    $moreRoots = @(@('scripts', 'records', 'site', 'game', 'launcher', 'installer') | Where-Object { Test-Path -LiteralPath (Join-Path $RepoDir $_) })
    $loose = @(& git -C $RepoDir ls-files --others --exclude-standard -- @moreRoots 2>$null | Where-Object { $_ })
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
        # nothing unknown in a folder a release is built from, nothing that is
        # not on GitHub.
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
        # ships all the same: Go.ps1 copies every game\plugins\*.js into
        # the game folder and the build compiles every launcher\app\*.cs, whether
        # git knows them or not. So a scratch plugin would pass this gate and go
        # out in the pack while GitHub had never seen it, which is where the
        # entry's worry, "a scratch file with something private in it lands
        # next", had moved to once Ship stopped committing. Found in the
        # review of entry 205 on 24 Sep.
        #
        # One ignored file does ship and is not counted: local\thornswood-
        # front.zip, which Go.ps1 unpacks into Data\Platform\UI. local\ keeps it
        # out of git and it has never been committed. Whether it should be is
        # not a question this gate can settle.
        if ($loose.Count) {
            foreach ($d in $loose | Select-Object -First 10) { Say "    $d" 'Yellow' }
            Die ("There are $($loose.Count) file(s) in a folder a release is built from that git does not know about. The build " +
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
$updaterCs = Join-Path $Here '..\..\launcher\app\Updater.cs'
if (-not (Test-Path $updaterCs)) { Die "Could not find $updaterCs" }

$src = Get-Content $updaterCs -Raw
$m = [regex]::Match($src, 'Version\s*=\s*"([^"]+)"')
if (-not $m.Success) { Die 'Could not read the version out of app\Updater.cs' }
$current = $m.Groups[1].Value
$MainSourceAligned = $false
if (Test-Path -LiteralPath (Join-Path $RepoDir '.git')) {
    $releaseSource = Get-ReleaseSource $RepoDir
    $originMain = Invoke-ReleaseGit $RepoDir @('rev-parse', '--verify', 'refs/remotes/origin/main')
    $MainSourceAligned = $releaseSource.Uncommitted -eq 0 -and $originMain.Code -eq 0 -and
        $releaseSource.Commit -eq $originMain.First
}

# NO NEW LAUNCHER WHEN NOTHING LAUNCHER-SIDE CHANGED, issue #921. Patrick, 28
# Sep: "it should be signed only when a new installer goes up on the website so
# we aren't signing for every single update". Every signed launcher refuses an
# unsigned update, so the launcher cannot go out unsigned; what can stop is a
# new one going out at all. A dev Ship used to bump 1.1.x.N, rebuild and sign
# every time, even for a pack of textures. Now the feed records a fingerprint
# of what the exe is compiled from (launcherInputs), and a Ship whose sources
# match it keeps the launcher already published: same bytes, same sha256, no
# build, no signing call, only the packs go out, exactly as -ModsOnly does.
# The first Ship after this change finds no fingerprint and builds as before.
# -RebuildLauncher or -Version builds one anyway.
$LauncherInputs = Get-LauncherInputHash $RepoDir
if (-not $ModsOnly -and -not $RebuildLauncher -and -not $Version) {
    $feedBranch = if ($Dev) { 'dev' } else { 'main' }
    $pubLauncher = Get-PublishedLauncher $ReleaseDir $feedBranch
    if ((Test-LauncherUnchanged $pubLauncher $LauncherInputs) -and
        (-not $MainSourceAligned -or $pubLauncher.Version -eq $current)) {
        Head 'The launcher'
        Say ("  nothing it is built from changed since $($pubLauncher.Version) went out, so that one stays: " +
             'no rebuild, no signing, only the packs. -RebuildLauncher to build one anyway.') 'Green'
        $ModsOnly = $true
    }
}

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
             ".\scripts\release\Bump-Version.ps1 -To $Version and its pull request, then Ship without -Version.")
    }
    $target = $Version
}
elseif ($Dev) {
    # Separate Dev work uses the main version with a fourth number.
    # Clean Main-equivalent source is aligned below after the history check.
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

    # WHAT IS PUBLISHED, READ OFF THE SITE, NOT OFF THIS DISK. Until 25
    # September both numbers came from the version.json files in this
    # machine's releases clones, which nothing here pulled first. Djinn's clone
    # was days old and still said 1.1.92, so his dev Ship went out as 1.1.92.3
    # while every dev launcher was on 1.1.94.x: lower, so never offered. And
    # the count after the last dot came from the dev feed's current number
    # only, so the next Ship after it would have restarted at .1 under numbers
    # already out. From then until #907 both were read from origin in the
    # clones, and the dev number climbed past every launcherVersion in the dev
    # branch's history. Now main's number is the feed the site serves, and
    # "every dev number ever published" is launchers.txt in the dev store on
    # the VPS, which every send of the dev feed adds to (Feed-Store.ps1) and
    # the one-off move seeded from the dev branch's whole history.
    function Read-Published([string]$ch) {
        try {
            $d = Read-SiteFeed $ch
            if ($null -ne $d -and $d.PSObject.Properties['launcherVersion']) { return [string]$d.launcherVersion }
        } catch {
            Say "  could not read the $ch feed from the site ($($_.Exception.Message)), so this uses the copy last received here, which may be old" 'Yellow'
        }
        $f = Join-Path (Get-FeedStoreDir $ch) 'version.json'
        if (-not (Test-Path -LiteralPath $f)) { return '' }
        return [string]((Get-Content -LiteralPath $f -Raw | ConvertFrom-Json).launcherVersion)
    }
    function Read-EverPublished([string]$ch) {
        try { return @(Get-FeedStoreLaunchers $ch) }
        catch {
            Say "  could not read the launchers $ch has published from the VPS ($($_.Exception.Message)); the number climbs from the current feed only" 'Yellow'
            return @()
        }
    }

    $base = $current
    try {
        $mainWas = Read-Published 'main'
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

    $seen = @()
    try { $seen = @(Read-EverPublished 'dev') } catch { }
    try { $was = Read-Published 'dev'; if ($was) { $seen += $was } } catch { }
    $n = 1
    foreach ($v in $seen) {
        if ($v.StartsWith("$base.")) {
            $k = 0
            if ([int]::TryParse($v.Substring($base.Length + 1), [ref]$k) -and $k -ge $n) { $n = $k + 1 }
        }
    }
    $target = "$base.$n"
    # Past every dev number already out, whatever base that was on: a lower
    # one is never offered to a launcher that took the higher.
    $top = ''
    foreach ($v in $seen) { if ($v -and (-not $top -or (Compare-Ver $v $top) -gt 0)) { $top = $v } }
    if ($top -and (Compare-Ver $top $target) -ge 0) {
        $tp = @($top -split '\.')
        if ($tp.Count -ge 4) { $k = 0; [void][int]::TryParse($tp[3], [ref]$k); $next = (($tp[0..2] -join '.') + '.' + ($k + 1)) }
        else { $next = (($tp[0..2] -join '.') + '.1') }
        Say "  dev has already published $top, so this goes out as $next rather than $target" 'Yellow'
        $target = $next
    }
    # The same clean source as Main gets the same version in both feeds.
    # Separate branch builds retain the monotonic fourth number above.
    # Never downgrade a Dev launcher when promoting: bump Main first.
    if ($MainSourceAligned) {
        $target = $current
    }
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

if ($Dev -and -not $ModsOnly) {
    # Applies to explicit -Version too; it cannot bypass the history check.
    $publishedVersions = @()
    if (-not $Version) { $publishedVersions += @($seen) + @($mainWas) }
    try { $publishedVersions += @(Get-FeedStoreLaunchers 'dev') } catch { Say '  Dev version history could not be read; checking the current feeds' 'Yellow' }
    foreach ($ch in 'main', 'dev') {
        $liveLauncher = Get-PublishedLauncher (Get-FeedStoreDir $ch) $ch
        if ($liveLauncher -and $liveLauncher.Version) { $publishedVersions += $liveLauncher.Version }
    }
    Assert-DevVersionSelection $target $current $MainSourceAligned $publishedVersions
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

# A main release ships the exe CI built for v$target, so the launcher on main
# has to be the launcher at that tag (Get-LauncherDrift above, issue #883).
# -ModsOnly publishes no exe, but the live launcher still judges the pack's
# client runtime by the record compiled into it, so that one file counts there.
if (-not $Dev -and (Test-Path -LiteralPath (Join-Path $RepoDir '.git'))) {
    $drift = @(Get-LauncherDrift $RepoDir ('v' + $target))
    if ($ModsOnly) { $drift = @($drift | Where-Object { $_ -eq 'records/client-build.json' }) }
    if ($drift.Count) {
        foreach ($d in $drift | Select-Object -First 10) { Say "    $d" 'Yellow' }
        $why = ("$($drift.Count) launcher file(s) changed on this branch after v$target was tagged, and the exe CI built for v$target has none of it. " +
                "Every launcher already on $target would keep the old one anyway. Move the version first: " +
                ".\scripts\release\Bump-Version.ps1, its pull request, the new tag, then Ship again.")
        if ($DryRun) { Say "  $why" 'Yellow' } else { Die $why }
    }
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

# ------------------------------------------------------------ setup program
# A main release with -Package builds the installer around the setup program
# CI built for this tag (Get-ReleaseStub, issue #932), fetched here, before
# anything is built or published, so a release with none stops now and not
# after it is out. A dev Ship compiles its own with Build-Launcher below, and
# Package-Thornswood finds it in out\ as before.
$ciStub = ''
if ($Package -and -not $Dev -and -not $DryRun) {
    Head 'The setup program from CI'
    $stubDir = & (Join-Path $Here 'Get-ScratchDir.ps1') ('Thornswood-setup-' + (Split-Path -Leaf $Root.TrimEnd('\')))
    $why = Get-ReleaseStub (Get-SourceRepo $RepoDir) $target $stubDir
    if ($why) {
        Unbump 'there is no verified setup program to package'
        Die $why
    }
    $ciStub = Join-Path $stubDir 'setup-stub.exe'
    Say ("  verified against SHA256SUMS, {0:n0} KB" -f ((Get-Item -LiteralPath $ciStub).Length / 1KB)) 'Green'
}

# ------------------------------------------------------------ generated files
# Issue #1247, Patrick 29 Sep: the behavior files (Pandora) and BodySlide's bodies
# are made in Thornswood's own folder on this machine, by
# scripts\mods\Build-Generated.ps1, as a step before a Ship; the Steam copy is
# the person's own. A release carries what is in the folder, so a folder whose
# files were built for another mod list, from other files, or never, would
# send everybody animations and bodies that do not match the collection.
# Get-GeneratedState reads the record Build-Generated wrote against this
# machine now (scripts\mods\Generated.ps1). Both channels stop: the files ship
# on both. Before the launcher is built and installed (#1692): on 4 October a
# dev Ship built and installed it, closing the running launcher, and only
# then stopped here. And before the covered bodies, which read what it built.
$GameDir = Join-Path $Root 'Game'
if (-not (Test-Path -LiteralPath (Join-Path $GameDir 'SkyrimSE.exe'))) { $GameDir = '' }
Head 'Generated files'
if ($GameDir) {
    . (Join-Path $Here '..\mods\Generated.ps1')
    $genState = $null
    try { $genState = Get-GeneratedState $Root (Join-Path $RepoDir 'records\generated.json') }
    catch {
        Unbump 'the generated files could not be checked'
        Die ($_.Exception.Message + ' Nothing was built or published.')
    }
    if (-not $genState.Current) {
        Unbump 'the generated files are out of date'
        Die (Get-GeneratedStaleSays $genState $Channel)
    }
    Say ("  {0} file(s) Build-Generated made for this mod list, as it made them" -f $genState.Record.Files.Count) 'Green'
} else {
    Say '  no own game folder here, so there are none to check' 'DarkGray'
}

# ------------------------------------------------------------ node
# The SkyUI menus step below reads the game folder with node (#960). Without
# node it used to say so in yellow and ship unread, so a machine with no node
# published without the one check that keeps the SkyUI error box off every
# login (#1913). A game folder means that check has something to read, so no
# node stops the release here, before the launcher is built and installed,
# Go.ps1 copies anything, or anything is published.
if ($GameDir -and -not (Get-Command node -ErrorAction SilentlyContinue)) {
    Unbump 'node is not on this machine'
    Die ('node is not on this machine, and Ship reads SkyUI''s menus in the game folder with it (scripts\mods\Check-SkyUIMenus.js), ' +
         'so a release never gives everybody the SkyUI error box on the way in. Install it with ' +
         'winget install --id OpenJS.NodeJS.LTS -e (Developer-Guide.md, "Install the tools"), open a new window, and Ship again. ' +
         'Nothing was built or published.')
}

# ------------------------------------------------------------ build
if (-not $ModsOnly) {
    # The exe's time going in, so a build that put nothing in place is told
    # from one that did.
    $launchDir = Join-Path $Root 'Launcher'
    $before = [datetime]::MinValue
    $p = Get-LauncherExe $launchDir
    if (Test-Path -LiteralPath $p) { $before = (Get-Item -LiteralPath $p).LastWriteTimeUtc }

    # The build and the install are two scripts since 24 September (To Do List
    # entry 243). The build compiles into a folder of its own, so csc never
    # meets the launcher still running from the install, and Install-Launcher
    # then closes the game and the launcher, puts the exe in place and does
    # the shortcut and the icon, which is everything the build used to do.
    $buildOut = & (Join-Path $Here 'Get-ScratchDir.ps1') ('Thornswood-launcher-' + (Split-Path -Leaf $Root.TrimEnd('\')))

    if (-not $Dev -and -not $DryRun) {
        # A MAIN RELEASE TAKES THE EXE CI BUILT, and verifies it, since issue
        # #457. The binary that reaches every launcher is compiled on a clean
        # runner from the tagged commit, not here, and this checks it against
        # its SHA256SUMS before a byte of it is packed. A dev build and a dry
        # run still compile below: dev is pretest with no tag or release of its
        # own, and a dry run publishes nothing, so neither is the shipped binary.
        Head 'The launcher from CI'
        $srcRepo = Get-SourceRepo $RepoDir
        Say "  taking the exe CI built for v$target from $srcRepo" 'DarkGray'
        $why = Get-ReleaseLauncher $srcRepo $target $buildOut
        if ($why) {
            Unbump 'there is no verified launcher to ship'
            Die $why
        }
        Say ("  verified against SHA256SUMS, {0:n0} KB" -f ((Get-Item (Join-Path $buildOut 'Thornswood.exe')).Length / 1KB)) 'Green'

        # Signed here, before it is installed or packed (issue #921): CI has no
        # certificate, so the draft's exe is unsigned, and every launcher from
        # dev 1.1.101.17 on refuses an unsigned update.
        Head 'Signing the launcher from CI'
        try {
            $ciSigner = Get-ExpectedSignerFragment -RepoRoot $RepoDir
        } catch {
            Unbump 'ExpectedSigner could not be read'
            Die ($_.Exception.Message + ' Nothing was published.')
        }
        $why = Set-ReleaseLauncherSignature (Join-Path $buildOut 'Thornswood.exe') (Join-Path $Here 'Sign-Artifact.ps1') $ciSigner
        if ($why) {
            Unbump 'the launcher from CI is not signed'
            Die $why
        }
        Say '  Authenticode Valid, signed by ExpectedSigner' 'Green'
    }
    else {
        Head 'Building the launcher'
        & (Join-Path $Here 'Build-Launcher.ps1') -Root $Root -OutDir $buildOut -NoPause
        $buildCode = $LASTEXITCODE

        <#
          The build script's own answer, read before anything else.

          Whether the launcher built used to be judged only on an exe appearing
          with a newer timestamp. Compiling happens near the start, so every
          step after csc was invisible here: the stub, the signing, anything
          added later.

          On 18 September that shipped a release that had already stopped.
          Build-Launcher printed "STOP. Signing failed. Nothing was published."
          and exited 1 because the Azure certificate profile did not exist yet.
          The exe from the compile was sitting there and it was newer than
          before, so the check below passed, and Ship went on to build the pack,
          upload it, rewrite version.json, post the news, tell Discord and tell
          everybody in the world they had five minutes. 1.1.48 went out unsigned,
          announcing that nothing had been published.
        #>
        if ($buildCode -ne 0) {
            Unbump 'the launcher build failed'
            Die ('The launcher build stopped with exit code ' + $buildCode +
                 '. Nothing was published. The errors are above.')
        }
    }

    # DryRun is non-destructive for close/prune (#494): -NoClose skips Stop-Game
    # and Stop-Launcher; prune is skipped via -NoClose / KeepPacks on Publish-Update.
    $installArgs = @{ Root = $Root; From = $buildOut; NoPause = $true }
    if ($DryRun) { $installArgs['NoClose'] = $true }
    & (Join-Path $Here 'Install-Launcher.ps1') @installArgs
    $installCode = $LASTEXITCODE
    if ($installCode -ne 0) {
        Unbump 'the launcher could not be put in place'
        Die ('Putting the new launcher into ' + $launchDir + ' stopped with exit code ' + $installCode +
             '. Nothing was published. The errors are above.')
    }

    $exe = Get-LauncherExe $launchDir
    $inPlace = Test-Path -LiteralPath $exe
    if ($inPlace) { $inPlace = ((Get-Item -LiteralPath $exe).LastWriteTimeUtc -gt $before) }
    if (-not $inPlace) {
        Unbump 'nothing was put in place'
        Die 'The launcher is not in place. Look at the errors above.'
    }
    Say ("  in place, {0:n0} KB" -f ((Get-Item $exe).Length / 1KB)) 'Green'
    # Keep matching .pdb beside this release's version on the shipping machine.
    # Packs, the installer and public release assets never carry them (#462).
    $kept = @(Save-ShipSymbols $buildOut $target)
    $stubPdb = Join-Path (& (Join-Path $Here 'Where.ps1') Out) 'setup-stub.pdb'
    if (Test-Path -LiteralPath $stubPdb) {
        $extra = @(Save-ShipSymbols (Split-Path -Parent (Resolve-Path $stubPdb)) $target)
        if ($extra.Count -gt 0) { $kept = $kept + $extra }
    }
    if ($kept.Count -gt 0) {
        Say ("  symbols kept under {0} ({1} file(s))" -f (Get-ShipSymbolDir $target), $kept.Count) 'DarkGray'
    }
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
# and has no business talking to the VPS. $GameDir is the game folder the
# generated files were checked in, above, or '' when there is none.

Head 'The in game plugins'
$goArgs = @{ SkipServer = $true }
if ($GameDir) { $goArgs['Game'] = $GameDir } else { $goArgs['Vortex'] = $true }
# Write-Host does not go down the pipeline, so Out-Null does not quiet it.
# 6 is the information stream Write-Host actually uses. Nothing is lost:
# Go.ps1 reports in colour, and the check below is
# what decides whether this step passed.
& (Join-Path $Here 'Go.ps1') @goArgs 6>$null | Out-Null
# Except for one thing: a file this repository tracks that Go.ps1 could not
# find, which is a path gone wrong and exits 1 (issue #440, phase 0).
if ($LASTEXITCODE -ne 0) {
    Unbump 'Go.ps1 could not find files this repository has'
    Die 'Go.ps1 could not find files this repository has. Run .\scripts\release\Go.ps1 -SkipServer to see which. Nothing was published.'
}

# Other trouble Go.ps1 reports in yellow and still exits 0 on, so the files are checked
# rather than the exit code. This is the guard that makes the step worth having:
# a plugin that did not land stops the release instead of shipping stale.
if ($GameDir) {
    $plugSrc = Join-Path $Here '..\..\game\plugins'
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
        Die 'game\plugins has no .js in it. Nothing was published.'
    }
    Say "  $seen plugin(s) in the game folder match this source" 'Green'
} else {
    Say '  installed into the Steam copy; no own game folder to check them against' 'Yellow'
}

# ------------------------------------------------------- load order copies (#477 / #557)
# Require the named Thornswood Vortex profile. When Profile\OwnGame has a baked
# copy it must match. Differing copies stop Ship naming which lists diverge.
Head 'The load order copies'
. (Join-Path $Here '..\mods\LoadOrder.ps1')
try {
    $twProfile = Assert-VortexProfile 'Thornswood'
} catch {
    Unbump 'Vortex profile Thornswood was not found'
    Die $_.Exception.Message
}
$profileDir = Join-Path $Root 'Profile'
$copies = @{
    'Vortex Thornswood\plugins.txt' = (Join-Path $twProfile 'plugins.txt')
}
$ownPlugins = Join-Path $profileDir 'OwnGame\plugins.txt'
if (Test-Path -LiteralPath $ownPlugins) {
    $copies['Profile\OwnGame\plugins.txt'] = $ownPlugins
}
$loCopies = @{}
foreach ($k in @($copies.Keys)) {
    $pluginsPath = $copies[$k]
    $loPath = Join-Path (Split-Path -Parent $pluginsPath) 'loadorder.txt'
    if (Test-Path -LiteralPath $loPath) {
        $loCopies[($k -replace 'plugins\.txt$', 'loadorder.txt')] = $loPath
    }
}
$diffs = @(Get-LoadOrderCopyDiffs $copies)
$diffs += @(Get-LoadOrderCopyDiffs $loCopies)
if ($diffs.Count -gt 0) {
    foreach ($line in $diffs) { Say "  $line" 'Red' }
    Unbump 'load order copies diverge'
    Die ("Load order copies that must match diverge:`n  " + ($diffs -join "`n  ") + "`nBake OwnGame from the Thornswood Vortex profile (launcher Settings, Maintenance, bring the folder up to date), or fix the lists, then Ship again.")
}
Say ("  Thornswood profile at $twProfile; load order copies agree") 'Green'

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
    Die 'The game folder does not hold the recorded client. Run .\scripts\release\Sync-Client.ps1, then Ship again.'
}
if ($LASTEXITCODE -ne 0) {
    Unbump 'the client build could not be checked'
    Die 'Sync-Client.ps1 refused. Rebuild the client, run .\scripts\release\New-ClientBuildRecord.ps1, and Ship again.'
}

# ------------------------------------------------------------ covered bodies
# Issue #405, Patrick 28 Sep: "no nudity in players or NPCs for both males and
# females". The bodies come from the Nexus collection, and a release tells every
# launcher which collection revision to match by reading the one installed
# here, so a main release out of a game folder whose body is nude points
# everybody at a nude body. Check-CoveredBodies.ps1 reads the shapes in each
# body mesh: 0 covered, 2 a nude body, 1 unreadable. Main refuses on 2 unless
# -AllowUncoveredBodies; dev warns, so work can still be tried on the dev build
# while the covered bodies' revision is on its way. 1 refuses on both channels
# (#1956, Patrick 5 Oct), as the SkyUI menus step below does since #1913.
Head 'Covered bodies'
if ($GameDir) {
    $global:LASTEXITCODE = 0
    & (Join-Path $Here '..\mods\Check-CoveredBodies.ps1') -Game $GameDir -Quiet
    $bodiesExit = $LASTEXITCODE
    if ($bodiesExit -eq 2 -and -not $Dev -and -not $AllowUncoveredBodies) {
        Unbump 'a body in the game folder is nude'
        Die 'A body in the game folder is nude, and a main release would point everybody at this collection revision. Install the collection revision with the covered bodies (issue #405), bring the game folder up to date, and Ship again. -AllowUncoveredBodies ships anyway, on Patrick''s word only.'
    }
    if ($bodiesExit -eq 2) { Say '  a body in the game folder is nude (issue #405); shipping anyway' 'Yellow' }
    elseif ($bodiesExit -ne 0) {
        # Anything but 0 and 2, 1 for a mesh or a Data folder it could not read
        # or the check itself failing, refuses on both channels, the way the
        # SkyUI menus step does (#1956, Patrick 5 Oct). A check that cannot read
        # is not a pass: the unread mesh may be the nude one.
        Unbump 'the body meshes could not all be read'
        Die ("The body meshes in the game folder could not all be read (Check-CoveredBodies.ps1 exit $bodiesExit), so whether a body is nude is not known. " +
             'The red lines above say what could not be read. Fix or replace it in the game folder, and Ship again. -AllowUncoveredBodies does not let this through.')
    }
} else {
    Say '  no game folder here, so the bodies were not read' 'DarkGray'
}

# ------------------------------------------------------------ SkyUI's menus
# Issue #960, 28 Sep: dev showed "SKYUI ERROR CODE 6", menu file version
# mismatch, required 5.2 SE, detected 6.11 SE. SkyUI's script and its menus
# came from different releases: SkyUI 5.2's loose scripts, which dev packs
# carried, over the collection's newer SkyUI. Check-SkyUIMenus.js reads the
# script and the menus the way the game picks them (loose over archive, later
# plugin's archive over earlier): 0 they agree, 2 they do not, 1 unreadable.
# Paths every pack deletes are read as gone, since every install loses them
# with this release. It refuses both channels: the box is on every login.
# node is on the machine by now: Ship stopped before the build without it
# (#1913).
Head 'SkyUI menus'
if ($GameDir) {
    $skyuiPlugins = Join-Path (Get-ShipLoadOrderDir $Root $profileDir) 'plugins.txt'
    $global:LASTEXITCODE = 0
    & node (Join-Path $Here '..\mods\Check-SkyUIMenus.js') --data (Join-Path $GameDir 'Data') --plugins $skyuiPlugins --gone (@(Get-ShipDeleteAlways) -join ';') --quiet
    $skyuiExit = $LASTEXITCODE
    if ($skyuiExit -eq 2) {
        Unbump 'SkyUI''s menus are not the version its script wants'
        Die 'SkyUI''s menus in the game folder are not the version its script wants, so everybody would get the SkyUI error box on the way in. See the lines above for which file wins and where it comes from, fix that, and Ship again.'
    }
    # Anything else, 1 for a menu, a script or a plugins.txt it could not read
    # or node failing, refuses too (#1913). A check that cannot read is not a
    # pass: an unread menu may be the one that does not match, and the box it
    # would bring up is on every login, on both channels.
    if ($skyuiExit -ne 0) {
        Unbump 'SkyUI''s menus could not all be read'
        Die ("SkyUI's menus could not all be read (Check-SkyUIMenus.js exit $skyuiExit), so whether everybody gets the SkyUI error box on the way in is not known. " +
             'The UNREAD and FAIL lines above say which file. Fix or replace it in the game folder, and Ship again.')
    }
} else {
    Say '  no game folder here, so SkyUI''s menus were not read' 'DarkGray'
}

# HOW FAR BEHIND the public installer is: the zip on disk against the releases
# the feed lists. Asked twice, and the two answers differ on purpose. Before
# publishing, the gate just below reads it to refuse a main release that would
# leave an already-behind installer further behind. After publishing, the
# closing note reads it again, by which point version.json carries this
# release's pack (a dry run puts it back), so a fresh installer that was current
# now reads as one behind. Reading the zip and the feed each time keeps both
# answers true to the disk rather than to a value cached before the publish.
#
# Staged out of the play install since 22 September: one folder per install
# root under the dev tree, the same shape Publish-Update and Package-Thornswood
# use, so the three agree on one answer. -DistRoot moves the lot. The old
# $Root\_dist is still read when it is the only one there, so a machine that has
# not published since the move still finds its installer.
function Measure-Installer {
    $distDir = Join-Path (Join-Path $DistRoot (Split-Path -Leaf $Root.TrimEnd('\'))) '_dist'
    $z = Join-Path $distDir 'Thornswood-Setup.zip'
    if (-not (Test-Path -LiteralPath $z)) {
        $wasZip = Join-Path $Root '_dist\Thornswood-Setup.zip'
        if (Test-Path -LiteralPath $wasZip) { $z = $wasZip }
    }
    $have = Test-Path $z
    $count = 0
    $when = [datetime]::MinValue
    if ($have) {
        $when = (Get-Item $z).LastWriteTime
        $vf = Join-Path $ReleaseDir 'version.json'
        if (Test-Path $vf) {
            $doc = Get-Content $vf -Raw | ConvertFrom-Json
            if ($doc.PSObject.Properties['packs'] -and $doc.packs) {
                $seen = @{}
                foreach ($p in @($doc.packs)) {
                    # ids are yyyyMMdd-HHmm, yyyyMMdd-HHmmss since #1057, with
                    # -2 -3 on the split ones, and three parts of one release
                    # are still one release; two releases in one minute are two.
                    $m = [regex]::Match("$($p.id)", '^\d{8}-\d{4}(\d{2})?')
                    if (-not $m.Success) { continue }
                    if ($seen.ContainsKey($m.Value)) { continue }
                    $seen[$m.Value] = $true
                    $t = [datetime]::MinValue
                    if ([datetime]::TryParseExact($m.Value.Substring(0, 13), 'yyyyMMdd-HHmm', $null, 'None', [ref]$t)) {
                        if ($t -gt $when) { $count++ }
                    }
                }
            }
        }
    }
    return [pscustomobject]@{ DistDir = $distDir; Zip = $z; HaveZip = $have; Behind = $count; ZipTime = $when }
}

# ---------------------------------------------------- the installer gate
# A MAIN RELEASE REFUSES TO GO OUT WHILE THE PUBLIC INSTALLER IS BEHIND, and
# this is the whole of that rule. Every main Ship adds a pack the installer does
# not carry, so an already-stale Thornswood-Setup.zip only gets staler, and a
# new person installing from it sits through the whole pile on first launch. The
# closing note has counted this for a long time and warned; a warning on the one
# screen nobody rereads let the installer drift release after release.
#
# BEFORE PUBLISH, on purpose. A refusal after the pack is on the feed would
# leave a release out with #news, the site and the server never told, which is
# the half-published state the -Package failure note further down calls worse
# than an installer one release behind. Here nothing has shipped yet, so the
# operator rebuilds and runs again with everything intact.
#
# -Package is the way through: it rebuilds the installer after this release, so
# the two go out together, and a release that carries -Package is not refused
# for behind because the rebuild is coming. A dev release never refuses: it does
# not touch the installer, and its closing note still warns. A hotfix never
# refuses either: it is the live build plus one urgent fix, and holding it for a
# twenty-minute installer rebuild is the opposite of what a hotfix is for.
if (-not $Dev -and -not $hotfix -and -not $DryRun -and -not $Package) {
    $ins = Measure-Installer
    if ($ins.HaveZip -and $ins.Behind -gt 0) {
        Unbump 'the installer is behind and nothing here was going to rebuild it'
        Die (("Thornswood-Setup.zip is {0} release{1} behind, built {2:d MMM HH:mm}, and a main release would leave it further behind. " -f `
                 $ins.Behind, $(if ($ins.Behind -eq 1) { '' } else { 's' }), $ins.ZipTime) +
             'Anyone installing from it would sit through all of those on first launch. Rebuild it as part of this ' +
             'release by adding -Package, or run .\scripts\release\Package-Thornswood.ps1 -OneFile first, then Ship.')
    }
}


# ------------------------------------------------------------ publish sign gate
# Site and feed only. Local Build-Launcher may print "not signing" and leave an
# unsigned exe on disk; that must not reach Releases or the host feed.
# CONTRIBUTING: only a signing machine may Ship, dev included. Soft skip is for
# build machines, not for publish. Assert-PublishSigned.ps1 is dot-sourced at
# the top, beside Ship-Rules.ps1.
$signCfg = Join-Path $Here '..\..\records\signing\signing.json'
$signWhy = Get-SigningConfigRefusal -ConfigPath $signCfg -RepoRoot $RepoDir
if ($signWhy) {
    Unbump 'this machine cannot sign'
    Die $signWhy
}
if (-not $ModsOnly) {
    $pubExe = Get-LauncherExe (Join-Path $Root 'Launcher')
    try {
        $expectWho = Get-ExpectedSignerFragment -RepoRoot $RepoDir
    } catch {
        Unbump 'ExpectedSigner could not be read'
        Die ($_.Exception.Message + ' Nothing was published.')
    }
    $signWhy = Get-PublishSignRefusal -Path $pubExe -ExpectedSigner $expectWho
    if ($signWhy) {
        Unbump 'the launcher is not signed for publish'
        Die $signWhy
    }
    Say ("  publish sign gate: $(Split-Path -Leaf $pubExe) Authenticode Valid, ExpectedSigner $expectWho") 'Green'
} else {
    Say '  publish sign gate: signing.json ready (mods-only; launcher tip not published)' 'DarkGray'
}

# ------------------------------------------------------------ publish
Head 'Publishing'
# A hashtable, not an array. Splatting an array passes everything positionally,
# so '-Notes' binds as a value rather than a parameter name.
$pubArgs = @{ Notes = $Notes; Root = $Root; RepoDir = $RepoDir; ReleaseDir = $ReleaseDir; DistRoot = $DistRoot; NoPause = $true }
if ($MoveServer) { $pubArgs['MoveServer'] = $true }
if ($AcceptSize) { $pubArgs['AcceptSize'] = $true }
if (-not $ModsOnly) { $pubArgs['Launcher'] = $true; $pubArgs['LauncherInputs'] = $LauncherInputs }
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
    # DryRun is non-destructive for close/prune (issue #494): do not Stop-Game
    # and do not delete old pack-*.zip; log what a real Ship would do instead.
    $pubArgs['NoUpload'] = $true
    $pubArgs['NoPush'] = $true
    $pubArgs['NoClose'] = $true
    $pubArgs['KeepPacks'] = 0
    Say '  dry run, nothing will be uploaded or pushed' 'Yellow'
    Say '  dry run: will not close a running game and will not prune old packs' 'Yellow'

    foreach ($f in @(
        (Join-Path $ReleaseDir 'version.json'),
        (Join-Path $ReleaseDir 'published.json')
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
# The id the publisher sets once the feed is on the VPS, and nothing before
# that; the release tag below goes on only then (#444). Cleared first, so a
# run earlier in this same window can never be tagged by this one.
$global:ThornswoodPublishedRelease = ''
# What a dev publish with nothing new did with the dev feed's DEV marks
# (Dev-News.ps1), said in Done below. Cleared for the same reason.
$global:ThornswoodDevMarks = $null
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
# version check has nothing to say about it. What it does have is the id the
# publisher sets only once the feed is on the VPS ($global:ThornswoodPublishedRelease,
# #444), so a publisher that says 0 without naming a release sent nothing,
# launcher or not. Until 6 Oct a mods only Ship had no witness here at all, and
# a publish with nothing new that said 0 went on to the Discord and the server.
#
# Only for a publisher that said 0. Exit code 2 is the publisher saying nothing
# was released, and the block for it below says so and tells nobody; this
# check used to stand in front of it for any Ship with a launcher, so that
# block never ran for one. Anything else is a publisher that stopped, below too.
if (-not $DryRun -and $published -eq 0) {
    $landed = ''
    try {
        $vf = Join-Path $ReleaseDir 'version.json'
        if (Test-Path $vf) {
            $landed = [string]((Get-Content $vf -Raw | ConvertFrom-Json).launcherVersion)
        }
    } catch { }
    $notOut = ''
    if (-not $global:ThornswoodPublishedRelease) { $notOut = 'The publisher named no release it sent to the VPS.' }
    elseif (-not $ModsOnly -and $landed -ne $target) {
        $notOut = "version.json still says $(if ($landed) { $landed } else { 'nothing at all' }), not $target."
    }
    if ($notOut) {
        Write-Host ''
        Say "NOTHING WAS PUBLISHED. $notOut" 'Red'
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
  How far behind the installer is now, worked out before anything can exit.

  This used to sit below the early return further down, so the one run that
  most needed it never printed: ship something, get told nothing changed,
  leave, and the package quietly stays another release behind. A count that
  only appears on the runs where it is least urgent is not a warning.

  Measure-Installer is the same reading the gate above the publish took, run
  again because version.json has moved: by now it carries this release's pack
  (a dry run put it back), so a fresh installer reads as one behind, which is
  what the closing note says.
#>
$ins = Measure-Installer
$DistDir = $ins.DistDir
$haveZip = $ins.HaveZip
$behind = $ins.Behind
$zipTime = $ins.ZipTime

function Show-Installer {
    if (-not $haveZip) {
        Head 'The installer'
        Say '  there is no Thornswood-Setup.zip yet, so nobody new can install.' 'Yellow'
        Say '  .\scripts\release\Package-Thornswood.ps1 -OneFile   builds it' 'Yellow'
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
    Say '  .\scripts\release\Package-Thornswood.ps1 -OneFile   to rebuild it, twenty minutes or so' 'Yellow'
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
#
# AND NOBODY IS TOLD. Everything after this block announces a release: the
# remirror, the site news, the Discord post, the server's countdown and the
# tag. A run that released nothing has nothing for any of them, so it stops
# here and says what it did and did not do. A dev publish with nothing new
# still brings the dev feed's DEV marks up to date with main (Dev-News.ps1);
# it says how that went in $global:ThornswoodDevMarks, read back here.
if ($published -eq 2) {
    if ($target -ne $current) {
        Unbump 'nothing was published'
        Say '  Rebuild the launcher next time you do ship, so the exe matches.' 'DarkGray'
    }
    Show-Installer
    Head 'Done'
    Say 'Nothing was released. The build already matches the last release.' 'Yellow'
    Say ('  No news entry was added, ' + $(if ($Dev) { 'the dev updates channel' } else { '#news' }) +
         ' was not posted to, and no server was told.') 'Yellow'
    $devMarks = $global:ThornswoodDevMarks
    if (-not $Dev) {
        Say "  The dev feed's DEV marks were not touched: main's feed did not move." 'DarkGray'
    } elseif ($DryRun) {
        Say "  Dry run: the dev feed's DEV marks were worked out and not sent." 'DarkGray'
        if ($null -ne $devMarks) { foreach ($l in @($devMarks.Lines)) { Say "    $l" 'DarkGray' } }
    } elseif ($null -ne $devMarks -and $devMarks.Done) {
        Say "  The dev feed's DEV marks were refreshed against main:" 'Green'
        foreach ($l in @($devMarks.Lines)) { Say "    $l" 'DarkGray' }
    } else {
        Say "  The dev feed's DEV marks were NOT refreshed." 'Red'
        if ($null -ne $devMarks) { foreach ($l in @($devMarks.Lines)) { Say "    $l" 'Red' } }
        Say '    .\scripts\release\Refresh-DevNews.ps1   does it on its own' 'Yellow'
    }
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 0
}

# ------------------------------------------------------------ the installer
if ($Dev) {
    Head 'The installer'
    Say '  dev release, the installer is not touched' 'DarkGray'
}
elseif ($Package -and $DryRun) {
    # A DRY RUN DOES NOT REBUILD THE INSTALLER. Package-Thornswood.ps1 puts
    # what it builds on the site, through Publish-Installer.ps1 over ssh, unless
    # it is given -NoPublish, and this called it without. So -DryRun -Package
    # put a new installer in front of every new person, which is the opposite
    # of a dry run. Found on 24 September by the script index run (entry 260).
    #
    # Skipped rather than built with -NoPublish. That build is twenty minutes,
    # and it would leave a Thornswood-Setup.zip in the staging folder that the
    # site does not have, so the next Ship would call the installer current
    # while the one people download is not. A dry run leaves nothing behind
    # that changes what the next release says; see the Publishing section.
    Show-Installer
    Say '  dry run, so not rebuilt: Package-Thornswood.ps1 puts what it builds on the site' 'Yellow'
    Say ('  .\scripts\release\Package-Thornswood.ps1 -OneFile -NoPublish -OutDir "' + $DistDir + '"   builds it and publishes nothing') 'DarkGray'
}
elseif ($Package) {
    Head 'Rebuilding the installer'
    # THE ONE FILE SHAPE, issue #1213: the payload attached to
    # Thornswood-Setup.exe, which is what the site has carried since the
    # payload came under a gigabyte (Package-Thornswood.ps1 -OneFile says why).
    # Without it Package-Thornswood builds the two file shape, a small exe that
    # downloads Thornswood-Setup.zip, and a main Ship would put that on the
    # site under the same name. Which shape the site carries is Patrick's, asked
    # on #1213; this keeps the one it has.
    $pkgArgs = @{ Root = $Root; OutDir = $DistDir; NoPause = $true; OneFile = $true }
    if ($ciStub) { $pkgArgs['Stub'] = $ciStub }
    & (Join-Path $Here 'Package-Thornswood.ps1') @pkgArgs

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
        Say '  rebuilt is Thornswood-Setup.exe, so anybody installing from scratch' 'Red'
        Say '  sits through this release on first launch.' 'Red'
        Say '  .\scripts\release\Package-Thornswood.ps1 -OneFile   to put that right' 'Yellow'
    }
}
else {
    Show-Installer
}

# ------------------------------------------------------- after the tip is out
<#
  THE TWO THINGS THAT FOLLOW A TIP, and until now neither was part of shipping.

  The host feed. Since the #649 cutover the tip customers get is version.json,
  and launchers poll the feed url in it, which is thornswood.net/feed, or
  /feed-dev on the dev channel (Config.AfterLoad, Updater.Check, docs\FEED.md).
  Publish-Update.ps1 writes that file and pushes it to the releases repository;
  the copy the site serves is a file on the VPS that somebody had to remirror by
  hand after every release. Until it is remirrored the site answers with the
  release it last held, which is the release people are offered, and where the
  feed names thornswood.net assets the bytes have to be up there too or the
  download answers 404.

  VirusTotal is no longer part of publish. Code signing covers trust for the
  installer (#390). Publish-VirusTotal.ps1 stays as an optional manual tool.

  AND NOTHING FOR THE LAUNCHER, which the header says at more length: the
  remirror is how a launcher update reaches anybody, and Install-Launcher.ps1
  above refreshed this machine's own install before the publish.

  ONE SCRIPT, KEYED OFF THE CHANNEL, AND IT OWNS THE REMIRROR.
  Publish-PostShip.ps1 calls the website lane's Remirror-Site-Feed.ps1. It finds
  it by name under scripts\ and calls it with the parameters it declares, so
  that lane does not have to rename anything to fit, and a hook that has not
  landed yet is a line rather than a failed release. Ship reads one exit code,
  Website has one command to run by hand, and the remirror asks before it acts,
  so running it again after a failure does nothing the first run already did.

  ORDER, pinned by the website lane: the remirror, then the site news, the
  Discord post and the server's countdown. Those tell people to update, and the
  feed has to be serving the release before anybody is sent to fetch it.

  WHAT A FAILURE DOES. The tip is already on the feed by the time this runs, so
  none of it can unpublish anything, and dying here would leave a release out
  with #news, the site and the server never told, which the installer note
  further up calls the worse half state. So it reports what happened, the release
  is announced either way, and the Done section names what did not complete with
  the line that puts it right. Ship still exits 0: the website lane's rule is
  that a refused remirror is a line and not a failed release, and a release that
  is on the feed, in #news and on the server is out.
#>
function Invoke-PostShip([string]$what, [string]$leaf, [hashtable]$withArgs, [string]$putRight) {
    $path = Join-Path $Here $leaf
    if (-not (Test-Path -LiteralPath $path)) {
        Say "  $what did NOT run: $leaf is not beside Ship.ps1." 'Red'
        $script:PostShipFailed += [pscustomobject]@{ What = $what; PutRight = $putRight }
        return
    }
    # global:, never a bare assignment, for the reason at the client build step:
    # run from a prompt, a bare $LASTEXITCODE = 0 makes a copy this script owns
    # while the child's exit lands in the global one.
    $global:LASTEXITCODE = 0
    try { & $path @withArgs }
    catch {
        Say "  $what stopped: $($_.Exception.Message)" 'Red'
        $script:PostShipFailed += [pscustomobject]@{ What = $what; PutRight = $putRight }
        return
    }
    if ($LASTEXITCODE -ne 0) {
        Say "  $what stopped with exit code $LASTEXITCODE. The lines above say why." 'Red'
        $script:PostShipFailed += [pscustomobject]@{ What = $what; PutRight = $putRight }
        return
    }
    Say "  $what done" 'Green'
}

$chan = if ($Dev) { 'dev' } else { 'main' }
$chanArg = if ($Dev) { ' -Channel dev' } else { '' }
# What both calls give it: the same channel, the same install, the same staging
# folder, one half each. The remirror works its own clone out from the channel,
# so nothing here passes it one.
$postArgs = @{ Channel = $chan; Root = $Root; DistRoot = $DistRoot; NoPause = $true }

if (-not $DryRun) {
    Head 'The host feed'
    Invoke-PostShip 'the host feed remirror' 'Publish-PostShip.ps1' ($postArgs + @{ Only = 'Remirror' }) `
        ".\scripts\release\Publish-PostShip.ps1$chanArg -Only Remirror"

    # THE DEV FEED'S DEV MARKS FOLLOW MAIN AT ONCE (Dev-News.ps1). Main's feed
    # is on the VPS by now, so the dev News tab can stop marking DEV what this
    # release just gave everybody. Until 6 Oct the marks moved only on the next
    # dev Ship, so after every main release finished work read as DEV until
    # somebody shipped dev, and on 5 Oct somebody did, only for that.
    # Refresh-DevNews.ps1 sends the dev feed's version.json alone, and only when
    # a mark or mainVersion moved: no dev release, no pack, no post, no server.
    # Like the remirror it cannot fail this release; a refusal is a line in Done
    # with the command that does it again.
    if (-not $Dev) {
        Head "The dev feed's DEV marks"
        Invoke-PostShip "the dev feed's DEV marks" 'Refresh-DevNews.ps1' @{ RepoDir = $RepoDir; NoPause = $true } `
            '.\scripts\release\Refresh-DevNews.ps1'
    }
}

# ------------------------------------------------------------------- news
# The site's News page reads the same feed the launcher does, so it is current
# the moment a release goes out rather than whenever somebody remembers.
if (-not $DryRun -and -not $Dev) {
    $newsScript = Join-Path $Here '..\ops\Publish-News.ps1'
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
    $discordScript = Join-Path $Here '..\ops\Publish-Discord.ps1'
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
    $announce = Join-Path $Here '..\vps\Request-Restart.ps1'
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
            Say '  .\scripts\vps\Request-Restart.ps1 when the server is reachable.' 'DarkGray'
        }
    } else {
        Say '  Request-Restart.ps1 is missing, nobody was told.' 'Yellow'
    }
}

# Main and Dev are independent releases. Publishing Main must preserve Dev's
# feed, baseline, release identity and history. Advance Dev with its own Ship.
# The one thing a main Ship changes on the dev feed is which notes are marked
# DEV, and mainVersion, after the remirror above (Refresh-DevNews.ps1).

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

# ==== thornswood release tag ====
# THE COMMIT THIS RELEASE WAS BUILT FROM GETS A TAG (#444): release/main/<id>
# or release/dev/<id>, the id the feed names the release by (Release-Name.ps1),
# annotated with its launcher, packs and baseline, and pushed. Only after the
# publisher has said it sent the feed, never on a dry run, and last, so a slow
# or refused push never holds up the news or the countdown. A tag that did not
# go on is a line in Done with the command that finishes it, like the other
# follow-ons: the release is out either way.
if (-not $DryRun -and $global:ThornswoodPublishedRelease) {
    Head 'The tag'
    $tagged = Add-ReleaseTag $RepoDir (Join-Path $ReleaseDir 'version.json') ([string]$global:ThornswoodPublishedRelease) 'origin' `
        ('https://thornswood.net/' + $(if ($Dev) { 'feed-dev' } else { 'feed' }) + '/version.json')
    if (-not $tagged.Why) {
        Say "  $($tagged.Tag) marks $($tagged.Commit.Substring(0, 12)), and it is on GitHub" 'Green'
    } else {
        Say "  $($tagged.Why)" $(if ($tagged.PutRight) { 'Red' } else { 'Yellow' })
        if ($tagged.PutRight) { $script:PostShipFailed += [pscustomobject]@{ What = 'the release tag'; PutRight = $tagged.PutRight } }
    }
}
# ==== end thornswood release tag ====

Head 'Done'
# Repeated here on purpose. A red line in the middle of a release log is a line
# nobody reads: the last screen is the one that gets looked at.
if ($script:InstallerFailed) {
    Say ("The installer did NOT rebuild (exit $script:InstallerFailed). The release went out " +
         'without it.') 'Red'
    Say '  .\scripts\release\Package-Thornswood.ps1 -OneFile' 'Yellow'
    Write-Host ''
}
# The release is out either way, and the people who would have read the post
# do not know it. Said here because this is the screen that gets looked at.
if ($global:ThornswoodDiscordResult -eq 'failed') {
    Say ('The release went out, but ' +
         $(if ($Dev) { 'the dev updates channel' } else { '#news' }) +
         ' was NOT told.') 'Yellow'
    Say ('  .\scripts\ops\Publish-Discord.ps1' + $(if ($Dev) { ' -Dev' } else { '' }) +
         '   posts it on its own') 'Yellow'
    Write-Host ''
}
# Said again here for the same reason as the installer and the Discord above:
# the last screen is the one that gets looked at, and one red line in the middle
# of a release log is a line nobody reads.
if ($script:PostShipFailed.Count) {
    Say 'The release is out and stays out. What did not happen after it:' 'Yellow'
    foreach ($f in $script:PostShipFailed) {
        Say ("  $($f.What)") 'Red'
        Say ("    $($f.PutRight)") 'Yellow'
    }
    Say '  Until they run, the site may be serving the feed it had, which is the release' 'DarkGray'
    Say '  people are offered, or the Downloads page still shows an old build' 'DarkGray'
    Say '  item-not-found. Each line above asks before it acts, so it can be run twice.' 'DarkGray'
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
# AND SHIP STILL EXITS 0 WHEN ONE OF THOSE DID NOT HAPPEN, asked for by the
# website lane on 27 September: "Exit 1 = refused publish (do not fail the
# release)". This section used to exit 1 on it, which was this lane's own reading
# of the standing order that the tip and its follow-ons go out together. A
# release that is on the feed, in #news and on the server is out, and a remirror
# that refused rather than publish a feed naming missing bytes did the careful
# thing. The lines above are the record, and they name what to run.
