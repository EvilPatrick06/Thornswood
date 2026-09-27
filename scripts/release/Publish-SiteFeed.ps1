<#
.SYNOPSIS
  Mirrors the tip of the update feed onto the site, so thornswood.net/feed and
  thornswood.net/feed-dev serve the version.json and the assets every launcher
  reads after the #649 host cutover.

.DESCRIPTION
  WHY THIS EXISTS. The launcher asks the site for version.json first
  (Config.AfterLoad, Updater.Check, docs\FEED.md), and Feed-Rules.ps1 lets a
  pack url be a thornswood.net feed asset. site\server.js serves both out of
  files on the VPS: <SiteRoot>\feed\version.json and
  <SiteRoot>\feed\assets\<sha256>, and <SiteRoot>\feed-dev\... for the dev
  channel. Nothing put those files there. Publish-Update.ps1 uploads the
  assets to Thornswood-Releases and, with -HostAssetUrls, writes the site urls
  into version.json, and then somebody had to remember to copy the bytes
  across by hand. A feed that names bytes the site does not hold answers 404
  to every launcher, and then Play stays off.

  So this is the remirror, as one command Ship runs at the end of a release.
  It is Website's to own; it calls nothing of its own invention and it reads
  the same Feed-Rules.ps1 the publisher does.

  IN WHAT ORDER, AND WHY IT MATTERS. Assets first, version.json last. A
  version.json that arrives before the bytes it names is a feed that offers an
  update nobody can download. The other way round is harmless: an asset the
  live feed does not mention yet is a file nobody asks for.

  WHAT IT REFUSES. A pack, launcher or client runtime whose url is a
  thornswood.net feed asset, that is neither on the VPS already nor on this
  machine to send, stops the mirror before version.json goes anywhere. That is
  the one case where sending version.json would break a launcher that is
  working today.

    .\scripts\release\Publish-SiteFeed.ps1                        the live feed
    .\scripts\release\Publish-SiteFeed.ps1 -Channel dev           the dev feed
    .\scripts\release\Publish-SiteFeed.ps1 -Plan                  says what it would send and sends nothing
    .\scripts\release\Publish-SiteFeed.ps1 -All                   every asset the feed names, not only the site-url ones

.PARAMETER Channel
  main or dev. main mirrors into <SiteRoot>\feed, dev into
  <SiteRoot>\feed-dev, which is the shape site\server.js serves and
  Feed-Rules.ps1 allows.

.PARAMETER ReleaseDir
  The releases clone whose version.json is the tip. Left out, it is
  Thornswood-Releases beside this repository, or the Thornswood-Releases-dev
  worktree on the dev channel, which is where Ship.ps1 and Publish-Update.ps1
  both keep them.

.PARAMETER Root
  The install the release was built from. Its Launcher folder is where the
  shipped exe is read from when the feed names it as a site asset.

.PARAMETER DistRoot
  Where releases are staged and zipped, the same folder Publish-Update.ps1
  wrote the packs into. The pack zips and the client runtime zip are found
  under it by name and matched to the feed by sha256, never by name alone.

.PARAMETER Vps
  The box the site runs on.

.PARAMETER User
  The account on it. The key is your own, put there by Setup-SshKey.ps1;
  nothing here holds a password.

.PARAMETER SiteRoot
  Where the site is installed on the VPS, the folder Deploy-Docs.ps1 fills.
  feed and feed-dev sit inside it, beside data, public and files.

.PARAMETER All
  Also mirrors the assets whose feed url still points at GitHub, so the site
  can serve a feed that has not been cut over yet. Without it, only the assets
  the feed already names on thornswood.net are sent, because those are the only
  ones a launcher cannot get anywhere else.

.PARAMETER Plan
  Works out what would be sent and sends nothing. Reaches the VPS only to ask
  which assets are already there, and not even that with -Offline.

.PARAMETER Offline
  Talks to nothing. With -Plan it lists what the feed names and which of those
  are on this machine, which is what a test can check without a VPS.

.PARAMETER NoVerify
  Skips the reading back: the sha256 of each file that was sent, measured on
  the VPS, and the https GET of version.json and HEAD of each asset sent.
  Faster on a big release, and then nothing has proved the mirror works.

.PARAMETER NoPause
  Exits without waiting for Enter, so Ship can call this without stopping for
  a keypress nobody is there to give.

.EXAMPLE
  .\scripts\release\Publish-SiteFeed.ps1 -Channel dev

  Puts the dev tip on thornswood.net/feed-dev: the assets it names, then
  version.json, then reads both back over https.

.NOTES
  Exit codes: 0 the site serves the tip, 1 something stopped and the message
  says which asset or which step. Ship.ps1 reads that code and says at the end
  which of its three follow-ons did not complete.
#>
[CmdletBinding()]
param(
    [ValidateSet('main', 'dev')][string]$Channel = 'main',
    [string]$ReleaseDir,
    [string]$Root = 'C:\Thornswood',
    [string]$DistRoot = (& (Join-Path $PSScriptRoot 'Where.ps1') Dist),
    [string]$Vps = '192.135.112.23',
    [string]$User = 'Administrator',
    [string]$SiteRoot = 'C:/Thornswood-Docs',
    [switch]$All,
    [switch]$Plan,
    [switch]$Offline,
    [switch]$NoVerify,
    [switch]$NoPause
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here 'Feed-Rules.ps1')

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) {
    Write-Host ''
    Write-Host "STOP. $m" -ForegroundColor Red
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to exit') }
    exit 1
}

$ssh = @('-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=accept-new')
$Dev = ($Channel -eq 'dev')
$FeedName = if ($Dev) { 'feed-dev' } else { 'feed' }
$siteWin = $SiteRoot.Replace('/', '\')

# Runs a command on the VPS and hands back what it said. The same shape as
# Deploy-Docs.ps1, Publish-Installer.ps1 and the other fourteen scripts that
# talk to the box: a short script travels on the command line, a long one goes
# as a file, because sshd on Windows hands the command to cmd.exe and cmd.exe
# stops at 8,191 characters without saying so.
function Remote($script) {
    $e = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
    $cmd = "powershell -NoProfile -EncodedCommand $e"
    if ($cmd.Length -le 6000) {
        return & ssh @ssh "$User@$Vps" $cmd 2>&1
    }
    $far = 'C:/Windows/Temp/thornswood-remote.ps1'
    $tmp = [IO.Path]::GetTempFileName()
    try {
        Set-Content -LiteralPath $tmp -Value $script -Encoding UTF8
        & scp @ssh $tmp "$User@${Vps}:$far" 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "could not send a script to $Vps" }
        & ssh @ssh "$User@$Vps" "powershell -NoProfile -ExecutionPolicy Bypass -File $far" 2>&1
        & ssh @ssh "$User@$Vps" "powershell -NoProfile -Command Remove-Item -LiteralPath '$far' -Force" 2>&1 | Out-Null
    }
    finally { Remove-Item -LiteralPath $tmp -Force -EA SilentlyContinue }
}

function Send($local, $remote) {
    & scp @ssh $local "$User@${Vps}:$remote"
    if ($LASTEXITCODE -ne 0) { throw "scp failed: $local" }
}

# The launcher was SkyrimTogether.exe and is Thornswood.exe now, and an install
# made before the rename still carries the old name, so both are looked for.
function Get-LauncherExe([string]$dir) {
    foreach ($n in 'Thornswood.exe', 'SkyrimTogether.exe') {
        $p = Join-Path $dir $n
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return ''
}

Head 'Thornswood - the site feed'

# ------------------------------------------------------------ the tip
if (-not $ReleaseDir) {
    $repoDir = Split-Path -Parent $Here
    $repoDir = Split-Path -Parent $repoDir
    $beside = Split-Path -Parent $repoDir
    $ReleaseDir = Join-Path $beside $(if ($Dev) { 'Thornswood-Releases-dev' } else { 'Thornswood-Releases' })
}
$versionFile = Join-Path $ReleaseDir 'version.json'
if (-not (Test-Path -LiteralPath $versionFile)) {
    Die ("There is no version.json in $ReleaseDir, so there is no tip to mirror. Point -ReleaseDir at the releases clone " +
         'for this channel, the one Publish-Update.ps1 writes.')
}
# A byte order mark is not JSON, and ConvertFrom-Json stops on the first
# character with something unhelpful about an unexpected token.
$doc = ((Get-Content -LiteralPath $versionFile -Raw) -replace '^\uFEFF', '') | ConvertFrom-Json
$tip = ''
if ($doc.PSObject.Properties['launcherVersion']) { $tip = [string]$doc.launcherVersion }
Say ("  $Channel tip: launcher $tip, from $versionFile") 'DarkGray'
Say ("  into $siteWin\$FeedName on $Vps") 'DarkGray'

# ------------------------------------------------------- what the feed names
#
# Every asset a launcher can be asked to download: each pack, the launcher
# itself, and the client runtime. Must is the ones the site HAS to hold,
# because the feed sends launchers to thornswood.net for them and nowhere else.
# The rest are on Thornswood-Releases as well, which is the rollback path that
# stays hot (docs\FEED.md), so the mirror is optional for those and -All asks
# for them anyway.
$want = New-Object System.Collections.ArrayList
$seen = @{}
function Add-Want([string]$sha, [string]$url, [string]$what) {
    $s = ([string]$sha).Trim().ToLowerInvariant()
    if ($s -notmatch '^[a-f0-9]{64}$') { return }
    if ($seen.ContainsKey($s)) { return }
    $seen[$s] = $true
    $must = $false
    if (Test-HostFeedAssetUrl $url) {
        # A dev pack url under /feed/assets is the live feed's to serve, not
        # this one's, so the channel has to match before it counts as ours.
        $mine = Get-HostFeedAssetUrl $s -Dev:$Dev
        $must = ([string]$url).Trim().StartsWith($mine, [StringComparison]::OrdinalIgnoreCase)
    }
    [void]$want.Add([pscustomobject]@{ Sha = $s; Url = ([string]$url).Trim(); What = $what; Must = $must; Path = '' })
}

if ($doc.PSObject.Properties['packs']) {
    foreach ($p in @($doc.packs)) {
        if ($null -eq $p) { continue }
        $pu = ''
        if ($p.PSObject.Properties['url']) { $pu = [string]$p.url }
        $ps = ''
        if ($p.PSObject.Properties['sha256']) { $ps = [string]$p.sha256 }
        $packId = ''
        if ($p.PSObject.Properties['id']) { $packId = [string]$p.id }
        Add-Want $ps $pu ("pack $packId")
    }
}
if ($doc.PSObject.Properties['launcherSha256'] -and $doc.PSObject.Properties['launcherUrl']) {
    Add-Want ([string]$doc.launcherSha256) ([string]$doc.launcherUrl) ("launcher $tip")
}
if ($doc.PSObject.Properties['clientRuntime'] -and $doc.clientRuntime) {
    $cr = $doc.clientRuntime
    $cs = ''
    if ($cr.PSObject.Properties['sha256']) { $cs = [string]$cr.sha256 }
    $cu = ''
    if ($cr.PSObject.Properties['url']) { $cu = [string]$cr.url }
    $ck = ''
    if ($cr.PSObject.Properties['forkCommit']) { $ck = [string]$cr.forkCommit }
    Add-Want $cs $cu ("client runtime $ck")
}

$mustCount = @($want | Where-Object { $_.Must }).Count
Say ("  the feed names {0} asset(s), {1} of them on thornswood.net/$FeedName" -f $want.Count, $mustCount) 'DarkGray'
if (-not $All -and $mustCount -eq 0) {
    Say '  no asset on this feed is a site asset yet, so only version.json is mirrored.' 'Yellow'
    Say '  Publish-Update.ps1 -HostAssetUrls is what writes the site urls into the feed.' 'DarkGray'
}

# ------------------------------------------------------ what is on this disk
#
# By sha256, never by name. A pack zip is named after the release that made it
# and the feed names it by its bytes, and the two are only the same thing while
# nothing has been rebuilt. The candidates are what Publish-Update.ps1 wrote:
# the pack zips and the client runtime zip under the staging folder, and the
# launcher exe in the install it built.
$wanted = @{}
foreach ($w in $want) { $wanted[$w.Sha] = $w }
$candidates = New-Object System.Collections.ArrayList
$stage = Join-Path (Join-Path $DistRoot (Split-Path -Leaf $Root.TrimEnd('\'))) '_dist'
foreach ($dir in @($stage, $DistRoot)) {
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    foreach ($pattern in 'pack-*.zip', 'client-runtime-*.zip') {
        foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter $pattern -File -Recurse -EA SilentlyContinue)) {
            [void]$candidates.Add($f.FullName)
        }
    }
}
$exe = Get-LauncherExe (Join-Path $Root 'Launcher')
if ($exe) { [void]$candidates.Add($exe) }

$have = @{}
foreach ($path in @($candidates | Select-Object -Unique)) {
    if ($have.Count -ge $wanted.Count) { break }
    $h = ''
    try { $h = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() } catch { continue }
    if (-not $wanted.ContainsKey($h)) { continue }
    if (-not $have.ContainsKey($h)) { $have[$h] = $path; $wanted[$h].Path = $path }
}
Say ("  {0} of them are on this machine to send" -f $have.Count) 'DarkGray'

# ------------------------------------------------------------ the plan only
if ($Plan) {
    Head 'What would be sent'
    foreach ($w in $want) {
        if (-not ($All -or $w.Must)) { continue }
        $where = if ($w.Path) { $w.Path } else { 'NOT on this machine' }
        Say ("  {0}  {1}  {2}" -f $w.Sha.Substring(0, 12), $w.What, $where) $(if ($w.Path) { 'Gray' } else { 'Yellow' })
    }
    Say ("  and version.json, last, naming launcher $tip") 'DarkGray'
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 0
}
if ($Offline) { Die '-Offline only says what would be sent, so it needs -Plan. Nothing was mirrored.' }

# ------------------------------------------------- what the site already has
Head 'The site'
$there = @{}
try {
    Remote ("if (-not (Test-Path '$siteWin\$FeedName\assets')) { New-Item -ItemType Directory -Path '$siteWin\$FeedName\assets' -Force | Out-Null }`r`n'ready'") | Out-Null
    $names = @(Remote "Get-ChildItem '$siteWin\$FeedName\assets' -File -EA SilentlyContinue | ForEach-Object Name")
    foreach ($n in $names) {
        if ($n -isnot [string]) { continue }
        $t = $n.Trim().ToLowerInvariant()
        if ($t -match '^[a-f0-9]{64}$') { $there[$t] = $true }
    }
} catch {
    Die ("Could not reach $Vps to read $siteWin\$FeedName. " + $_.Exception.Message +
         " Nothing was mirrored, so the site still serves whatever it served before.")
}
Say ("  $FeedName/assets holds $($there.Count) file(s) already") 'DarkGray'

# --------------------------------------------------------------- the sending
$send = @($want | Where-Object { ($All -or $_.Must) -and -not $there.ContainsKey($_.Sha) })
$cannot = @($send | Where-Object { $_.Must -and -not $_.Path })
if ($cannot.Count) {
    foreach ($c in $cannot) { Say ("  " + $c.What + " (" + $c.Sha.Substring(0, 12) + ") is neither on the site nor on this machine") 'Red' }
    Die ("The feed sends launchers to thornswood.net for $($cannot.Count) asset(s) that nobody holds any more, so they would answer 404 and " +
         'the update would stop for everybody. version.json was NOT sent, so the site still serves the feed it was serving. ' +
         'Publish that asset again, or take it off the feed with .\scripts\release\Repair-Manifest.ps1, then run this again.')
}

$sent = New-Object System.Collections.ArrayList
foreach ($w in @($send | Where-Object { $_.Path })) {
    $mb = 0
    try { $mb = [math]::Round((Get-Item -LiteralPath $w.Path).Length / 1MB, 1) } catch { }
    Say ("  sending {0} ({1} MB) as {2}" -f $w.What, $mb, $w.Sha.Substring(0, 12)) 'DarkGray'
    try { Send $w.Path "$SiteRoot/$FeedName/assets/$($w.Sha)" }
    catch {
        Die ('Sending ' + $w.What + ' to the site stopped: ' + $_.Exception.Message +
             ' version.json was NOT sent, so the site still serves the feed it was serving.')
    }
    [void]$sent.Add($w)
}
$skipped = @($send | Where-Object { -not $_.Path })
if ($skipped.Count) {
    Say ("  $($skipped.Count) asset(s) the feed still holds on GitHub are not on this machine, so they were not mirrored") 'Yellow'
    Say '  Those still download from Thornswood-Releases, which is what the rollback path is for.' 'DarkGray'
}
if (-not $sent.Count) { Say '  every asset the site has to hold was already there' 'Green' }

# The bytes, read back off the VPS. scp says nothing about what landed, and an
# asset is named after its own sha256, so a file whose contents are not that
# hash is a file the launcher will delete and an update that fails.
if ($sent.Count -and -not $NoVerify) {
    $lines = @($sent | ForEach-Object { "'$($_.Sha)'" }) -join ','
    $read = @(Remote @"
foreach (`$s in @($lines)) {
  `$f = Join-Path '$siteWin\$FeedName\assets' `$s
  if (Test-Path -LiteralPath `$f) { `$s + '|' + (Get-FileHash -LiteralPath `$f -Algorithm SHA256).Hash.ToLower() }
  else { `$s + '|missing' }
}
"@)
    $bad = @()
    foreach ($l in $read) {
        if ($l -isnot [string]) { continue }
        $parts = $l.Trim().Split('|')
        if ($parts.Count -ne 2) { continue }
        if ($parts[0] -ne $parts[1]) { $bad += $parts[0] }
    }
    if ($bad.Count) {
        Die ("$($bad.Count) asset(s) did not land as the bytes they are named after ($($bad -join ', ')). version.json was NOT sent. " +
             'Run this again; if it repeats, the disk on the VPS or the transfer is the thing to look at.')
    }
    Say "  the $($sent.Count) file(s) sent read back as their own sha256 on the VPS" 'Green'
}

# ------------------------------------------------------------ version.json
# Last, on purpose. See the ordering note at the top of this script.
Head 'version.json'
try { Send $versionFile "$SiteRoot/$FeedName/version.json" }
catch {
    Die ('version.json did not reach the site: ' + $_.Exception.Message +
         ' The assets are up there, so nothing is broken; the site simply serves the older feed until this runs again.')
}
Say "  $FeedName/version.json is now the tip, launcher $tip" 'Green'

# --------------------------------------------------------------- read it back
if (-not $NoVerify) {
    Head 'Reading it back'
    $feedUrl = Get-HostFeedVersionUrl -Dev:$Dev
    try {
        # Windows PowerShell 5.1 defaults to an older TLS on some machines and
        # then every https read here fails for a reason that has nothing to do
        # with the site.
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch { }
    try {
        $live = Invoke-WebRequest -Uri $feedUrl -UseBasicParsing -TimeoutSec 30
        $liveDoc = ([string]$live.Content -replace '^\uFEFF', '') | ConvertFrom-Json
        $liveTip = ''
        if ($liveDoc.PSObject.Properties['launcherVersion']) { $liveTip = [string]$liveDoc.launcherVersion }
        if ($liveTip -ne $tip) {
            Die ("$feedUrl answers with launcher $liveTip, not $tip. The file went up, so this is the site serving something else: " +
                 'check that the site is running and that -SiteRoot is where Deploy-Docs.ps1 installed it.')
        }
        Say "  $feedUrl says launcher $liveTip" 'Green'
    } catch {
        Die ("$feedUrl could not be read: " + $_.Exception.Message +
             ' The files are on the VPS. Until this answers, every launcher falls back to the GitHub feed.')
    }
    $checkAssets = @($sent | Where-Object { $_.Must })
    if (-not $checkAssets.Count) { $checkAssets = @($want | Where-Object { $_.Must } | Select-Object -First 3) }
    $bad = @()
    foreach ($a in $checkAssets) {
        try {
            $r = Invoke-WebRequest -Uri $a.Url -Method Head -UseBasicParsing -TimeoutSec 30
            if ([int]$r.StatusCode -ne 200) { $bad += $a.What }
        } catch { $bad += $a.What }
    }
    if ($bad.Count) {
        Die ("$($bad.Count) asset(s) the feed names do not answer over https ($($bad -join ', ')). version.json is up, so launchers are " +
             'being sent at a download that fails. Run this again, and look at the site log on the VPS.')
    }
    if ($checkAssets.Count) { Say ("  $($checkAssets.Count) asset url(s) answer 200") 'Green' }
}

Head 'Done'
Say ("thornswood.net/$FeedName serves launcher $tip and the assets it names.") 'Green'
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
# Said out loud, because scp and ssh leave their own exit codes behind and
# Ship.ps1 reads this one to decide whether the release is complete.
exit 0
