<#
  Remirror-Site-Feed.ps1

  Puts the release feed on the site, so https://thornswood.net/feed/version.json
  is the same file as the tip of Thornswood-Releases and every asset it names
  can be downloaded from thornswood.net.

  WHY IT EXISTS. Since the #649 host cutover a launcher reads version.json from
  the site first and only falls back to the GitHub Contents API, and
  Publish-Update.ps1 -HostAssetUrls writes pack, launcher and clientRuntime urls
  as https://thornswood.net/feed/assets/<sha256>. Its own comment says "Website
  mirrors the bytes to /feed/assets/<sha256>", and nothing did: the mirror was
  somebody copying files by hand. A feed published without it points every
  launcher at bytes that answer 404, and a 404 on a pack fails the whole update
  and leaves Play off.

  WHAT IT SENDS, and in this order, because the order is the safety:

    1. every asset the feed names that is missing up there, each one to
       <sha256>.part and then renamed, so a dropped connection cannot leave a
       short file sitting at the name of its own hash
    2. version.json, last, and only when every asset it names is up there

  So the worst a failed run leaves is a site feed one release behind, which is
  what launchers were already reading, rather than a feed pointing at nothing.
  Nothing is ever deleted: an asset the current feed does not name is left
  alone, because an older feed may still name it.

      .\scripts\deploy\Remirror-Site-Feed.ps1 -Check   says what it would send
      .\scripts\deploy\Remirror-Site-Feed.ps1          the live feed, to /feed
      .\scripts\deploy\Remirror-Site-Feed.ps1 -Dev     the dev feed, to /feed-dev
      .\scripts\deploy\Remirror-Site-Feed.ps1 -Verify  re-sends any asset up
                                                       there whose bytes do not
                                                       hash to its own name
      .\scripts\deploy\Remirror-Site-Feed.ps1 -AssetDir D:\packs
                                                       another folder to look
                                                       for the bytes in

  HOW SHIP SHOULD CALL IT. After the release is published and before the news
  step, one line:

      & (Join-Path $Here '..\deploy\Remirror-Site-Feed.ps1') -Dev:$Dev

  in a try/catch, the way Ship calls Publish-News.ps1. It exits 1 when it
  refused to publish the feed, which is a line on screen for whoever shipped
  rather than a reason to fail a release that is already out on GitHub.

  Nothing about the installer's VirusTotal report is this script's business.
  That upload belongs to whoever publishes the installer, and
  scripts\release\Publish-Installer.ps1 says what the site needs from it.

  Reads the releases clone, and writes only to the site's feed folders.
#>
[CmdletBinding()]
param(
  # The clone or worktree holding version.json. Left out, it is
  # Thornswood-Releases beside this repository, or Thornswood-Releases-dev with
  # -Dev, which is where Publish-Update.ps1 keeps them.
  [string]$FeedDir,
  # The dev feed, to /feed-dev. The last dev Ship wins, the same as everywhere.
  [switch]$Dev,
  # More folders to look for asset bytes in, searched before the built-in ones.
  # A file named by its own sha256 is taken at its name; a .zip or .exe is
  # hashed to find out what it is.
  [string[]]$AssetDir,
  [string]$Vps  = '',
  [string]$User = 'Administrator',
  [string]$Root = 'C:/Thornswood-Docs',
  # Says what it would send and sends nothing. It still asks the VPS what is
  # already up there when it can, and says so when it cannot.
  [switch]$Check,
  # Hash every asset up there and re-send any whose bytes do not match the name
  # they are stored under. Off by default because the assets are tens of
  # megabytes each and the name is the hash.
  [switch]$Verify,
  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$ssh = @('-o','BatchMode=yes','-o','StrictHostKeyChecking=accept-new')
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here '..\vps\Vps.ps1')
if (-not $Vps) { $Vps = Get-ThornswoodVpsAddress }
$rootWin = $Root.Replace('/','\')
$prefix  = if ($Dev) { 'feed-dev' } else { 'feed' }

function Say($m, $c = 'Gray') { if (-not $Quiet) { Write-Host $m -ForegroundColor $c } }
function Head($m) { if (-not $Quiet) { Write-Host ''; Write-Host $m -ForegroundColor Cyan } }

# Runs a script up there and hands back what it said. The same block every
# other script that talks to the VPS carries: under the limit it goes on the
# command line, and over it it is sent as a file and run from there, because
# sshd on Windows hands the command to cmd.exe and cmd.exe stops at 8,191
# characters.
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

# Only the lines, and no throw when ssh has written a word to stderr.
#
# OpenSSH warns about post-quantum key exchange on every connection, 2>&1 above
# folds that into the output as an error record, and a native command that
# writes to stderr while $ErrorActionPreference is Stop is a terminating error.
# Deploy-Docs.ps1 lost a whole deploy to that once. So every remote call comes
# through here and the caller decides what the absence of an answer means.
function RemoteLines($script) {
  $old = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try { return @(Remote $script | Where-Object { $_ -is [string] }) }
  finally { $ErrorActionPreference = $old }
}

# ConvertFrom-Json gives back an object with only the properties the file had,
# and reaching for one that is not there throws under strict mode. The same two
# readers Publish-News.ps1 carries, for the same reason.
function Prop($obj, $name) {
  if ($null -eq $obj) { return '' }
  $p = $obj.PSObject.Properties[$name]
  if ($null -eq $p) { return '' }
  return [string]$p.Value
}
function PropList($obj, $name) {
  if ($null -eq $obj) { return @() }
  $p = $obj.PSObject.Properties[$name]
  if ($null -eq $p) { return @() }
  return @($p.Value)
}

# Which urls the site is supposed to serve, and the sha256 in each one.
. (Join-Path $Here '..\release\Feed-Rules.ps1')

# ------------------------------------------------------------------ the feed
if (-not $FeedDir) {
  $repo   = & (Join-Path $Here '..\release\Where.ps1') Repo
  $beside = Split-Path -Parent $repo
  $clone  = if ($Dev) { 'Thornswood-Releases-dev' } else { 'Thornswood-Releases' }
  $FeedDir = Join-Path $beside $clone
}
$versionFile = Join-Path $FeedDir 'version.json'
if (-not (Test-Path -LiteralPath $versionFile)) {
  throw ("No version.json in $FeedDir. Clone Thornswood-Releases beside this repository " +
         '(Check-ShipReady.ps1 says how), or pass -FeedDir.')
}
# A byte order mark is not JSON, and ConvertFrom-Json stops on the first
# character with something unhelpful about a token.
$doc = ((Get-Content -LiteralPath $versionFile -Raw) -replace '^\uFEFF', '') | ConvertFrom-Json

Head "Reading $versionFile"
$packCount = @(PropList $doc 'packs').Count
Say ("  launcher {0}, {1} pack(s), for /{2}/ on the site" -f (Prop $doc 'launcherVersion'), $packCount, $prefix)

# ==== thornswood feed assets wanted ====
# tests\test-remirror-feed.ps1 runs this block on its own against a scratch
# version.json. If the markers move, it stops rather than quietly testing
# nothing. It reads $doc and $prefix and writes $need, $offSite and
# $wrongChannel, and talks to nothing.
#
# Every asset the feed names that the site is supposed to serve, in feed order,
# keyed by the sha256 in its own url. A url on GitHub needs no mirror: the
# launcher downloads it from there, and Thornswood-Releases stays the rollback
# path whether this script has run or not.
$need = [ordered]@{}
$script:offSite = 0
$script:wrongChannel = @()
function Want([string]$url, [string]$what) {
  $u = ([string]$url).Trim()
  if (-not $u) { return }
  if (-not (Test-HostFeedAssetUrl $u)) { $script:offSite++; return }
  $m = [regex]::Match($u, '/(feed|feed-dev)/assets/([a-fA-F0-9]{64})', 'IgnoreCase')
  if (-not $m.Success) { return }
  $channel = $m.Groups[1].Value.ToLowerInvariant()
  if ($channel -ne $prefix) {
    $script:wrongChannel += ("{0} is published under /{1}/" -f $what, $channel)
    return
  }
  $sha = $m.Groups[2].Value.ToLowerInvariant()
  if (-not $need.Contains($sha)) { $need[$sha] = $what }
}

Want (Prop $doc 'launcherUrl') ('launcher ' + (Prop $doc 'launcherVersion'))
if ($doc.PSObject.Properties['clientRuntime']) {
  Want (Prop $doc.clientRuntime 'url') ('client runtime ' + (Prop $doc.clientRuntime 'forkCommit'))
}
foreach ($p in (PropList $doc 'packs')) {
  if ($null -eq $p) { continue }
  Want (Prop $p 'url') ('pack ' + (Prop $p 'id'))
}
foreach ($p in (PropList $doc 'optional')) {
  if ($null -eq $p) { continue }
  Want (Prop $p 'url') ('optional pack ' + (Prop $p 'id'))
}
# ==== end thornswood feed assets wanted ====

Say ("  {0} asset(s) named on the site, {1} still named on GitHub" -f $need.Count, $script:offSite)
foreach ($w in $script:wrongChannel) {
  Say "  NOT MIRRORED: $w, and this run is /$prefix/. Run it for that channel." 'Yellow'
}

# ------------------------------------------------------- what is up there --
$there = @{}
$badUpThere = @()
$askedTheVps = $false
$wantHashes = if ($Verify) { '1' } else { '0' }
$listScript = @"
`$dir = '$rootWin\$prefix\assets'
if (-not (Test-Path `$dir)) { 'NOTHING THERE YET'; exit }
'ASKED'
Get-ChildItem `$dir -File | ForEach-Object {
  `$h = ''
  if ('$wantHashes' -eq '1') { `$h = (Get-FileHash -LiteralPath `$_.FullName -Algorithm SHA256).Hash.ToLower() }
  `$_.Name + '|' + `$_.Length + '|' + `$h
}
"@
foreach ($l in (RemoteLines $listScript)) {
  $line = $l.Trim()
  if ($line -eq 'NOTHING THERE YET' -or $line -eq 'ASKED') { $askedTheVps = $true; continue }
  $m = [regex]::Match($line, '^([a-f0-9]{64})\|(\d+)\|([a-f0-9]{64})?$')
  if (-not $m.Success) { continue }
  $name = $m.Groups[1].Value
  if ($m.Groups[3].Value -and $m.Groups[3].Value -ne $name) {
    # The name IS the hash, so bytes that do not hash to it are a short or
    # damaged file that every launcher will refuse. -Verify is what looks.
    $badUpThere += $name
    continue
  }
  $there[$name] = [int64]$m.Groups[2].Value
}
if ($askedTheVps) {
  Say ("  {0} asset(s) already on the site" -f $there.Count)
  $spare = @($there.Keys | Where-Object { -not $need.Contains($_) }).Count
  if ($spare) { Say "  and $spare the current feed does not name, left alone" 'DarkGray' }
} else {
  $said = "$Vps did not say what is already up there."
  if (-not $Check) { throw ($said + ' Nothing was sent. Check the ssh key with scripts\vps\Setup-SshKey.ps1 -Test.') }
  Say "  $said The plan below assumes the site has none of it." 'Yellow'
}
foreach ($b in $badUpThere) { Say "  BAD BYTES up there, this sends them again: $b" 'Yellow' }

# ------------------------------------------------ where the bytes are here --
# The folders a publishing machine keeps assets in, cheapest to read first. A
# file named by its own sha256 is taken at its name; a .zip or .exe has to be
# hashed. Those are what Publish-Update leaves behind for the release that just
# went out (pack-<id>.zip, client-runtime-<commit>.zip) and what Build-Launcher
# leaves in the install folder (Thornswood.exe).
$gameRoot = if ($Dev) { 'C:\Thornswood-DevBuild' } else { 'C:\Thornswood' }
$folders = @()
foreach ($d in @($AssetDir)) { if ($d) { $folders += $d } }
$folders += (Join-Path $FeedDir 'assets')
# Where.ps1 looks for the old C:\Thornswood-Dev layout, so it needs a machine
# that has a C drive to answer at all. A machine that cannot be asked still
# sends whatever -AssetDir names.
try {
  $folders += (& (Join-Path $Here '..\release\Where.ps1') Package)
  $folders += (& (Join-Path $Here '..\release\Where.ps1') Dist)
} catch {
  Say "  could not ask Where.ps1 where the build output is: $_" 'DarkGray'
}
$folders += ($gameRoot + '\Launcher')
$folders = @($folders |
  Where-Object { $_ -and (Test-Path -LiteralPath $_ -ErrorAction SilentlyContinue) } |
  Select-Object -Unique)

$found = @{}
$wanted = @($need.Keys | Where-Object { -not $there.ContainsKey($_) })
# StillWanted is read as @(StillWanted).Count / $missing = @(StillWanted).
# Publish-PostShip.ps1 sets StrictMode -Version Latest and & this script, so
# StrictMode is inherited. return @() unwraps to nothing and return @('one')
# unwraps to a string; under StrictMode reading .Count on either throws
# "The property 'Count' cannot be found" (same shape as the KeepPacks tidy
# note in Publish-Update.ps1). The @() at every call site is the defence.
# Do not lead with a comma here: ,@() makes @(StillWanted).Count answer 1
# when nothing is wanted, and the script refuses to publish an empty plan.
function StillWanted { return @($wanted | Where-Object { -not $found.ContainsKey($_) }) }
foreach ($f in $folders) {
  if (-not @(StillWanted).Count) { break }
  foreach ($file in @(Get-ChildItem -LiteralPath $f -File -ErrorAction SilentlyContinue)) {
    if (-not @(StillWanted).Count) { break }
    $byName = $file.Name.ToLowerInvariant()
    if ($byName -match '^[a-f0-9]{64}$') {
      if ($wanted -contains $byName) { $found[$byName] = $file.FullName }
      continue
    }
    if ($file.Extension -notin '.zip', '.exe') { continue }
    $h = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLower()
    if ($wanted -contains $h) { $found[$h] = $file.FullName }
  }
}
$missing = @(StillWanted)

# ----------------------------------------------------------------- the plan --
Head 'What this run does'
foreach ($sha in $need.Keys) {
  $short = $sha.Substring(0, 12)
  if ($there.ContainsKey($sha)) { Say ("  already there  {0}  {1}" -f $short, $need[$sha]) 'DarkGray' }
  elseif ($found.ContainsKey($sha)) { Say ("  to send        {0}  {1}" -f $short, $need[$sha]) 'Green' }
  else { Say ("  MISSING        {0}  {1}" -f $short, $need[$sha]) 'Red' }
}

if ($missing.Count -and -not $askedTheVps) {
  Say ''
  Say ("$($missing.Count) asset(s) are not on this machine, and the site was not asked, so") 'Yellow'
  Say '  some of them may already be up there. Run it again where ssh works.' 'Yellow'
  exit 0
}
if ($missing.Count) {
  Say ''
  Say ("$($missing.Count) asset(s) the feed names are neither on the site nor on this machine.") 'Red'
  Say '  Nothing was sent, because a feed pointing at a 404 stops every update.' 'Red'
  Say '  They are usually still on the machine that built them. Copy them anywhere' 'Yellow'
  Say '  and pass it as -AssetDir, or take them from the Thornswood-Releases release' 'Yellow'
  Say '  named for that pack id, which keeps every asset for rollback.' 'Yellow'
  exit 1
}
if ($Check) {
  Say ''
  Say ("Dry run. {0} asset(s) to send, then version.json to /$prefix/. Nothing left this machine." -f $found.Count) 'Yellow'
  exit 0
}

# ----------------------------------------------------------------- sending --
Head 'Making room'
foreach ($l in (RemoteLines @"
foreach (`$d in @('$rootWin\$prefix', '$rootWin\$prefix\assets')) {
  if (-not (Test-Path `$d)) { New-Item -ItemType Directory -Path `$d -Force | Out-Null }
}
'ready'
"@)) { Say "  $l" }

$sent = 0
if ($found.Count) { Head 'Sending the assets' }
foreach ($sha in $need.Keys) {
  if (-not $found.ContainsKey($sha)) { continue }
  $local = $found[$sha]
  $size  = (Get-Item -LiteralPath $local).Length
  Say ("  {0}  {1:N1} MB  {2}" -f $sha.Substring(0, 12), ($size / 1MB), (Split-Path -Leaf $local))
  # To .part first, then renamed up there. scp straight onto the final name
  # leaves a short file at the name of a hash when the connection drops, the
  # site serves it happily, and the launcher that downloads it fails the hash
  # check and stops the whole update.
  & scp @ssh $local "$User@${Vps}:$Root/$prefix/assets/$sha.part"
  if ($LASTEXITCODE -ne 0) { throw "scp failed: $sha ($local)" }
  $said = ((RemoteLines @"
`$p = '$rootWin\$prefix\assets\$sha.part'
`$f = '$rootWin\$prefix\assets\$sha'
`$n = (Get-Item -LiteralPath `$p).Length
if (`$n -ne $size) { Remove-Item -LiteralPath `$p -Force; 'SHORT: ' + `$n + ' bytes of $size'; exit }
Move-Item -LiteralPath `$p -Destination `$f -Force
'in place'
"@) -join ' ').Trim()
  if ($said -notmatch 'in place') { throw "$sha did not land: $said" }
  $sent++
}

# version.json last. Everything it names is up there by now, so a launcher
# reading it the same second finds every asset it asks for.
Head 'Sending version.json'
& scp @ssh $versionFile "$User@${Vps}:$Root/$prefix/version.json"
if ($LASTEXITCODE -ne 0) { throw 'scp failed: version.json' }

Head 'Done'
Say ("  {0} asset(s) sent, {1} already there, version.json published" -f $sent, $there.Count) 'Green'
Say "  https://thornswood.net/$prefix/version.json" 'Green'
