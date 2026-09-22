<#
  Ship.ps1

  One command. Bumps the launcher version, builds it, and publishes everything
  that changed - launcher and mods both, in a single release.

      .\tools\Ship.ps1 "Fixed the map marker"

  Options:
      -NoBump          keep the current version number
      -Version 1.2.0   set it explicitly
      -ModsOnly        skip the launcher, publish only changed mod files
      -DryRun          build and diff, but upload nothing
      -Package         also rebuild the two installer files for new people

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
    & git -C $RepoDir fetch --quiet origin 2>$null | Out-Null
    $behind = 0
    try { $behind = [int]((& git -C $RepoDir rev-list --count "HEAD..origin/$branch" 2>$null | Out-String).Trim()) } catch { $behind = 0 }
    $ErrorActionPreference = $oldEap
    Say ("  branch {0}, {1} uncommitted change(s), {2} commit(s) behind origin/{0}" -f $branch, $dirty.Count, $behind) 'DarkGray'
    if (-not $Dev) {
        if ($branch -ne 'main') { Die "A main release ships from main. This is $branch. Merge it into main first, or use -Channel dev to try it on the dev server." }
        if ($behind -gt 0) { Die "main is $behind commit(s) behind origin/main. Run git pull first, so the other machine's work is in this release." }
        if ($dirty.Count) { Say '  the uncommitted changes are what this release is built from; they are committed and pushed when it is out' 'DarkGray' }
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
elseif ($NoBump) {
    $target = $current
}
else {
    $parts = $current.Split('.')
    if ($parts.Count -lt 3) { Die "Version '$current' is not in x.y.z form" }
    $parts[2] = [string]([int]$parts[2] + 1)
    $target = $parts -join '.'
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
    # Resolved twice on purpose. The build writes Thornswood.exe and removes a
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

    & (Join-Path $Here 'Build-Launcher.ps1') -Root $Root -NoPause
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
$pubArgs = @{ Notes = $Notes; Root = $Root; RepoDir = $RepoDir; ReleaseDir = $ReleaseDir; NoPause = $true }
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
$zip = Join-Path $Root '_dist\Thornswood-Setup.zip'
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
    & (Join-Path $Here 'Package-Thornswood.ps1') -Root $Root -NoPause
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
        catch { Say "  could not post to Discord: $_" 'DarkGray' }
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
        try {
            if ($Dev) { & $announce -Minutes $AnnounceMinutes -Mode update -Why $Notes -Data 'C:/Thornswood-Server-Dev/data' }
            else      { & $announce -Minutes $AnnounceMinutes -Mode update -Why $Notes }
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
if (-not $DryRun -and -not $Dev) {
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

if (-not $DryRun -and -not $Dev -and (Test-Path (Join-Path $RepoDir '.git'))) {
    Head 'Source'
    $oldEap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        & git -C $RepoDir add -A 2>$null | Out-Null
        $staged = @(& git -C $RepoDir diff --cached --name-only 2>$null | Where-Object { $_ })
        if ($staged.Count) {
            & git -C $RepoDir commit -q -m "$target`: $Notes" 2>$null | Out-Null
            Say ("  committed {0} file(s) as {1}" -f $staged.Count, $target) 'Green'
        } else { Say '  nothing new to commit' 'DarkGray' }
        $pushed = & git -C $RepoDir push -q origin HEAD 2>&1
        if ($LASTEXITCODE -eq 0) { Say '  pushed to GitHub' 'Green' }
        else { Say "  push did not go through: $pushed" 'Yellow'; Say '  Run git pull, then git push, so the other machine gets this release''s source.' 'Yellow' }
    } catch { Say "  could not commit the source: $_" 'Yellow' }
    $ErrorActionPreference = $oldEap
}

Head 'Done'
if ($DryRun) { Say 'Dry run finished. Nothing left your machine.' 'Yellow' }
elseif ($NoAnnounce) { Say 'Everyone gets it next time they open the launcher.' 'Green' }
else {
    Say ("Everyone in the world has $AnnounceMinutes minutes, then they are put " +
         'back to the launcher to pick it up.') 'Green'
}
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
