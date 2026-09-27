<#
.SYNOPSIS
  Runs what follows a published tip, the host feed remirror and the VirusTotal
  upload for the installer the Downloads page offers, and says which of them did
  not happen.

.DESCRIPTION
  WHAT A TIP IS. The tip customers get is `version.json`, written and pushed by
  Publish-Update.ps1. Launchers poll the feed url in it, which is the site host
  feed (`docs\FEED.md`, and `Get-HostFeedVersionUrl` in `Feed-Rules.ps1`:
  https://thornswood.net/feed/version.json live, /feed-dev for dev). So once the
  publisher has written that file, two things are left before the tip is the one
  the world reads, and neither used to be part of shipping:

    the remirror   Remirror-Site-Feed.ps1, the website lane's script. Main takes
                   the Thornswood-Releases tip to thornswood.net/feed/, dev
                   takes the Thornswood-Releases-dev tip to
                   thornswood.net/feed-dev/, with the assets each feed names.
    VirusTotal     Publish-VirusTotal.ps1, the installer lane's upload hook, on
                   the installer exe that the Downloads page offers, so the link
                   the page prints beside its SHA-256 is a report rather than
                   item-not-found. The page wiring for those download urls is
                   the website lane's.

  THIS SCRIPT IMPLEMENTS NEITHER OF THEM. It is the one place that knows a
  release has two things after it, in what order, on which channel, and what to
  say when one did not happen. Remirror-Site-Feed.ps1 asked for exactly this
  call in its own header: "After the release is published and before the news
  step, one line."

  WHERE IT LOOKS FOR THEM, so no lane has to rename anything. The website lane
  has settled its name and place: scripts\deploy\Remirror-Site-Feed.ps1, taking
  -Dev or -Channel, main by default. The installer lane's upload is expected at
  scripts\release\Publish-VirusTotal.ps1 and its name is not settled yet, so that
  one is also looked for as any *VirusTotal*.ps1 under scripts\ whose name begins
  Publish, Send, Upload or Invoke and that takes a -Path or a -File. A name
  holding "comment" is never taken: Add-VirusTotalComment.ps1 writes a comment on
  a report and is a different job. -RemirrorScript and -VirusTotalScript name one
  outright when it lands outside all of that.

  Whatever is found is called with the parameters it actually declares, read off
  its own param block: -Dev or -Channel, -FeedDir or -ReleaseDir, -Path or
  -File. So a script that lands under another folder, or with the other name for
  the same thing, still runs.

  A HOOK THAT IS NOT ON THE MACHINE IS A LINE, NOT A FAILURE. The remirror
  script is the website lane's to land and this one cannot do its job, so a
  release that runs before it arrives says which file it looked for and where,
  and hands back 0. What does count as not completing is a hook that is here and
  stopped: then this hands back non-zero, Ship says so on its last screen, and
  the tip is still published, still announced, and nothing is unpublished.

  THERE IS NO THIRD STEP FOR THE LAUNCHER, and that is the Launcher lane's
  answer rather than an omission. A launcher polls the feed and updates itself,
  so the remirror IS the launcher update reaching people. Ship's mid-release
  Install-Launcher.ps1 refreshes the install on the machine that shipped
  (C:\Thornswood for main, C:\Thornswood-DevBuild for dev) and nothing else, so
  re-running it after the tip would refresh that one install again.

  THE SAME BLOCK RUNS ON DEV, on purpose. Everything goes to dev first
  (CONTRIBUTING.md, decided 23 September), so the dev channel is where this gets
  exercised several times a week rather than once a fortnight. Dev remirrors to
  /feed-dev, and its VirusTotal step asks about whatever installer exe is on the
  machine, which a dev release did not rebuild: the hook asks VirusTotal before
  it sends anything, so on most dev releases that is one read and nothing else.

  ONE HALF AT A TIME, WHICH IS WHY -Only EXISTS. Ship runs this twice: -Only
  Remirror before the site news, the Discord post and the server's countdown,
  because those three send people to fetch a release the feed has to be serving
  first, and -Only VirusTotal after them, because an upload of most of a gigabyte
  that nobody is waiting on must not hold up a five minute warning to everybody
  in the world. Run by hand with neither, both halves run in that order.

  Both halves ask before they act, so running this again after a failure does
  nothing the first run already did.

    .\scripts\release\Publish-PostShip.ps1                     after a main release
    .\scripts\release\Publish-PostShip.ps1 -Channel dev        after a dev release
    .\scripts\release\Publish-PostShip.ps1 -Only Remirror      the feed, nothing else
    .\scripts\release\Publish-PostShip.ps1 -SkipVirusTotal     the same, said the other way

.PARAMETER Channel
  main or dev. main remirrors the Thornswood-Releases tip to
  thornswood.net/feed/; dev remirrors the Thornswood-Releases-dev tip to
  thornswood.net/feed-dev/. Passed on as -Dev, or as -Channel to a script that
  takes that instead.

.PARAMETER ReleaseDir
  The clone or worktree holding the version.json that was just published, passed
  to the remirror as its -FeedDir (or -ReleaseDir, whichever it declares). Left
  out, that script works it out from the channel, the same way
  Publish-Update.ps1 does.

.PARAMETER Root
  The install the release was built from. Only used to find the installer for
  the VirusTotal half, in the staging folder for that root.

.PARAMETER DistRoot
  Where releases are staged, so the installer is looked for in the same place
  Package-Thornswood.ps1 built it and Publish-Installer.ps1 published it from.

.PARAMETER Installer
  The file to hand the VirusTotal hook, when it is not the Thornswood-Setup.exe
  in the staging folder. That exe is what the Downloads page offers, so its hash
  is the one the page prints a VirusTotal link for.

.PARAMETER AlsoLauncher
  Hands the shipped launcher exe to the VirusTotal hook as well. Off, because the
  Downloads page lists the installer and not the launcher, so no page link is
  waiting on a launcher report and version.json needs nothing from VirusTotal
  either. On for the day the page offers the launcher on its own.

.PARAMETER Only
  Remirror or VirusTotal, to run that half and not the other. Ship uses it to put
  the feed before the announcements and the upload after them. Left out, both
  halves run, the feed first.

.PARAMETER RemirrorScript
  The remirror script outright, for a machine or a branch where it is somewhere
  this would not find it.

.PARAMETER VirusTotalScript
  The VirusTotal upload hook outright, on the same terms.

.PARAMETER SkipRemirror
  Leaves the site serving the feed it already had. A launcher falls back to the
  GitHub feed only when the site feed does not answer at all, so an unmirrored
  feed offers people the release it last held rather than this one.

.PARAMETER SkipVirusTotal
  Leaves the report the Downloads page links as whatever it was, for when a tip
  is wanted now and nobody wants to wait on an upload of most of a gigabyte.

.PARAMETER NoPause
  Exits without waiting for Enter, so Ship can call this without stopping for a
  keypress nobody is there to give.

.EXAMPLE
  .\scripts\release\Publish-PostShip.ps1 -Channel dev

  Puts the dev tip on thornswood.net/feed-dev and asks VirusTotal about the
  installer this machine holds.

.NOTES
  Exit codes: 0 both halves are done, were skipped on purpose, or are waiting on
  a script that is not on this branch yet, and 1 a half that is here stopped.
  Ship.ps1 reads that code, still tells the site, the Discord and the server, and
  says on its last screen which line to run again.
#>
[CmdletBinding()]
param(
    [ValidateSet('main', 'dev')][string]$Channel = 'main',
    [string]$ReleaseDir,
    [string]$Root = 'C:\Thornswood',
    [string]$DistRoot = (& (Join-Path $PSScriptRoot 'Where.ps1') Dist),
    [string]$Installer,
    [switch]$AlsoLauncher,
    [ValidateSet('Both', 'Remirror', 'VirusTotal')][string]$Only = 'Both',
    [string]$RemirrorScript,
    [string]$VirusTotalScript,
    [switch]$SkipRemirror,
    [switch]$SkipVirusTotal,
    [switch]$NoPause
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$ScriptsDir = Split-Path -Parent $Here

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }

$Dev = ($Channel -eq 'dev')
$devArg = if ($Dev) { ' -Dev' } else { '' }
$failed = New-Object System.Collections.ArrayList
$waiting = New-Object System.Collections.ArrayList

# What a script declares it takes, read off its own param block. A hook is
# called with those and nothing else, so two lanes calling the same thing by
# different names, -FeedDir against -ReleaseDir, is not a reason for either to
# rename anything.
function Get-Accepts([string]$path) {
    $tokens = $null; $errors = $null
    $ast = $null
    try { $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) } catch { return @() }
    if ($null -eq $ast -or $null -eq $ast.ParamBlock) { return @() }
    return @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
}

# Where a hook is. Named outright, else the expected path, else the other
# obvious folder, else anywhere under scripts\ by the pattern, so the lane that
# owns it can land it where it belongs without this script being edited to match.
#
# $needs keeps the pattern search honest where a name is not settled: a
# candidate has to declare one of those parameters, and a name holding "comment"
# is never a candidate, because Add-VirusTotalComment.ps1 also takes a -Path and
# writes a comment rather than sending a file.
function Find-Hook([string]$given, [string[]]$expected, [string]$pattern, [string[]]$verbs, [string[]]$needs) {
    if ($given) {
        if (Test-Path -LiteralPath $given) { return (Resolve-Path -LiteralPath $given).ProviderPath }
        return ''
    }
    foreach ($rel in $expected) {
        $p = Join-Path $ScriptsDir $rel
        if (Test-Path -LiteralPath $p) { return (Resolve-Path -LiteralPath $p).ProviderPath }
    }
    $hits = @(Get-ChildItem -LiteralPath $ScriptsDir -Filter $pattern -File -Recurse -EA SilentlyContinue |
              Where-Object { $_.Name -notmatch '(?i)comment' } |
              Sort-Object FullName)
    if ($verbs.Count) {
        $hits = @($hits | Where-Object {
            $name = $_.Name
            @($verbs | Where-Object { $name -like ($_ + '-*') }).Count -gt 0
        })
    }
    if ($needs.Count) {
        $hits = @($hits | Where-Object {
            $accepts = Get-Accepts $_.FullName
            @($needs | Where-Object { $accepts -contains $_ }).Count -gt 0
        })
    }
    if ($hits.Count) { return $hits[0].FullName }
    return ''
}

# One half, and what its exit code meant. Reading that code is the whole point
# of this script: entry 118 on the To Do List is Ship calling something and
# never looking at what it said, and a half that stopped has to be a line
# somebody sees rather than a silence.
function Invoke-Half([string]$what, [string]$path, [hashtable]$withArgs, [string]$putRight) {
    $global:LASTEXITCODE = 0
    try { & $path @withArgs }
    catch {
        Say "  $what stopped: $($_.Exception.Message)" 'Red'
        [void]$failed.Add([pscustomobject]@{ What = $what; PutRight = $putRight })
        return
    }
    if ($LASTEXITCODE -ne 0) {
        Say "  $what stopped with exit code $LASTEXITCODE. The lines above say why." 'Red'
        [void]$failed.Add([pscustomobject]@{ What = $what; PutRight = $putRight })
        return
    }
}

Write-Host ''
$what = switch ($Only) {
    'Remirror'   { 'THE HOST FEED' }
    'VirusTotal' { 'VIRUSTOTAL' }
    default      { 'THE HOST FEED AND VIRUSTOTAL' }
}
Write-Host "  AFTER THE TIP, $Channel : $what" -ForegroundColor White

# ------------------------------------------------------------ the remirror
if ($Only -eq 'VirusTotal') {
    Say '  the host feed was this release''s first call, before anybody was told' 'DarkGray'
}
elseif ($SkipRemirror) {
    Head 'The host feed'
    Say '  -SkipRemirror, so the site goes on serving the feed it had, and anybody' 'Yellow'
    Say '  reading it is offered that release rather than this one.' 'Yellow'
    Say ("  .\scripts\deploy\Remirror-Site-Feed.ps1$devArg   mirrors it") 'DarkGray'
}
else {
    Head 'The host feed'
    $mirror = Find-Hook $RemirrorScript @('deploy\Remirror-Site-Feed.ps1', 'release\Remirror-Site-Feed.ps1') `
                        'Remirror-Site-Feed.ps1' @() @()
    if (-not $mirror) {
        # The website lane's script, and nothing here can mirror a feed without
        # it. Said with the path it looked for, so their pull request lands
        # beside this one rather than into a rename.
        Say '  Remirror-Site-Feed.ps1 is not on this branch, so the site still serves the' 'Yellow'
        Say '  feed it had, and anybody reading it is offered that release rather than this one.' 'Yellow'
        Say '  Expected at scripts\deploy\Remirror-Site-Feed.ps1 (the website lane owns it);' 'DarkGray'
        Say '  anywhere under scripts\ is found too, or pass -RemirrorScript.' 'DarkGray'
        [void]$waiting.Add('the host feed remirror, waiting on Remirror-Site-Feed.ps1')
    }
    else {
        # Main takes the Thornswood-Releases tip to /feed/, dev takes the
        # Thornswood-Releases-dev tip to /feed-dev/. That is the website lane's
        # contract for this script, and -Dev or -Channel is how it is said.
        $where = if ($Dev) { 'https://thornswood.net/feed-dev/' } else { 'https://thornswood.net/feed/' }
        Say "  $mirror" 'DarkGray'
        Say "  the $Channel tip to $where" 'DarkGray'
        $accepts = Get-Accepts $mirror
        $mirrorArgs = @{}
        if ($accepts -contains 'Dev') { $mirrorArgs['Dev'] = $Dev }
        elseif ($accepts -contains 'Channel') { $mirrorArgs['Channel'] = $Channel }
        if ($ReleaseDir) {
            if ($accepts -contains 'FeedDir') { $mirrorArgs['FeedDir'] = $ReleaseDir }
            elseif ($accepts -contains 'ReleaseDir') { $mirrorArgs['ReleaseDir'] = $ReleaseDir }
        }
        if ($accepts -contains 'NoPause') { $mirrorArgs['NoPause'] = $true }
        Invoke-Half 'The host feed remirror' $mirror $mirrorArgs ".\scripts\deploy\Remirror-Site-Feed.ps1$devArg"
    }
}

# ------------------------------------------------------------ VirusTotal
#
# The installer is what the Downloads page offers and the hash it prints a
# VirusTotal link for, so the exe in the staging folder is the file to hand the
# hook. Publish-Installer.ps1 already calls the same hook when it publishes a
# new installer, so this is for every release that did not rebuild one, where
# what the page offers may still have no report. The hook asks VirusTotal before
# it sends anything, which is why running this on every release, dev included,
# costs one read.
if ($Only -eq 'Remirror') {
    Say '  VirusTotal is this release''s second call, after everybody has been told' 'DarkGray'
}
elseif ($SkipVirusTotal) {
    Head 'VirusTotal'
    Say '  -SkipVirusTotal, so the report the Downloads page links is whatever it was.' 'Yellow'
    Say '  .\scripts\release\Publish-VirusTotal.ps1 -Path <the installer exe>   sends it' 'DarkGray'
}
else {
    Head 'VirusTotal'
    if (-not $Installer) {
        # The same two places Ship.ps1 measures the installer in: the staging
        # folder for this root, and the old spot under the play install for a
        # machine that has not published since that moved.
        foreach ($candidate in @(
            (Join-Path (Join-Path (Join-Path $DistRoot (Split-Path -Leaf $Root.TrimEnd('\'))) '_dist') 'Thornswood-Setup.exe'),
            (Join-Path $Root '_dist\Thornswood-Setup.exe')
        )) {
            if (Test-Path -LiteralPath $candidate) { $Installer = $candidate; break }
        }
    }
    # The launcher exe too, only when asked: the Downloads page lists the
    # installer, so no link on it is waiting on a launcher report, and
    # version.json needs nothing from VirusTotal either.
    $send = @()
    if ($Installer) { $send += $Installer }
    if ($AlsoLauncher) {
        foreach ($n in 'Thornswood.exe', 'SkyrimTogether.exe') {
            $p = Join-Path (Join-Path $Root 'Launcher') $n
            if (Test-Path -LiteralPath $p) { $send += $p; break }
        }
    }
    # The name is the installer lane's to settle, so any *VirusTotal*.ps1 that
    # reads like an upload and takes a file will do. A name holding "comment" is
    # a different job and is never taken.
    $vt = Find-Hook $VirusTotalScript @('release\Publish-VirusTotal.ps1', 'deploy\Publish-VirusTotal.ps1') `
                    '*VirusTotal*.ps1' @('Publish', 'Send', 'Upload', 'Invoke') @('Path', 'File')
    if (-not $send.Count) {
        Say '  there is no Thornswood-Setup.exe on this machine, so there is nothing to send.' 'Yellow'
        Say '  Whoever built the installer the site is serving runs the upload there:' 'DarkGray'
        Say '  .\scripts\release\Publish-VirusTotal.ps1 -Path <the installer exe>' 'DarkGray'
    }
    elseif (-not $vt) {
        Say '  no VirusTotal upload script is on this branch, so the link the Downloads page' 'Yellow'
        Say '  prints stays whatever it was, item-not-found for a file nobody has sent.' 'Yellow'
        Say '  Expected at scripts\release\Publish-VirusTotal.ps1 (the installer lane owns it,' 'DarkGray'
        Say '  and the name is theirs to settle); anything like it under scripts\ is found too,' 'DarkGray'
        Say '  or pass -VirusTotalScript. It needs VT_API_KEY and skips itself without one.' 'DarkGray'
        [void]$waiting.Add('the VirusTotal upload, waiting on the installer lane''s script')
    }
    else {
        Say "  $vt" 'DarkGray'
        if ($Dev) { Say '  a dev release did not rebuild the installer, so this is the one on disk' 'DarkGray' }
        $accepts = Get-Accepts $vt
        $names = @($accepts | Where-Object { $_ -eq 'Path' -or $_ -eq 'File' })
        if (-not $names.Count) {
            Say '  it takes neither -Path nor -File, so this cannot tell it which file to send.' 'Red'
            [void]$failed.Add([pscustomobject]@{
                What = 'The VirusTotal upload'
                PutRight = ".\scripts\release\Publish-VirusTotal.ps1   run it by hand, with whatever it names the file"
            })
        }
        else {
            $which = if ($accepts -contains 'Path') { 'Path' } else { 'File' }
            foreach ($file in $send) {
                Say "  on $file" 'DarkGray'
                $vtArgs = @{ $which = $file }
                if ($accepts -contains 'NoPause') { $vtArgs['NoPause'] = $true }
                Invoke-Half 'The VirusTotal upload' $vt $vtArgs ".\scripts\release\Publish-VirusTotal.ps1 -Path `"$file`""
            }
        }
    }
}

Head 'Done'
if ($failed.Count) {
    Say "The tip is published and stays published, but $($failed.Count) of what follows it did NOT complete:" 'Red'
    foreach ($f in $failed) {
        Say ("  $($f.What)") 'Red'
        Say ("    $($f.PutRight)") 'Yellow'
    }
    Say '  Each line above asks before it acts, so running it changes nothing else.' 'DarkGray'
}
elseif ($waiting.Count) {
    Say "Everything this branch can do after the $Channel tip is done." 'Yellow'
    foreach ($w in $waiting) { Say "  still to come: $w" 'Yellow' }
}
elseif ($Only -eq 'Both') {
    Say "Everything that follows the $Channel tip is done." 'Green'
}
else {
    Say "This half of what follows the $Channel tip is done." 'Green'
}
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
# Said out loud, because the halves leave their own exit codes behind and
# Ship.ps1 reads this one. A hook that is not here yet is not a failure: there
# is nothing on this branch that could have done its job.
if ($failed.Count) { exit 1 }
exit 0
