<#
  Publish-Discord.ps1

  Posts the newest release into the Discord #news channel.

  Uses the webhook Build-Discord.py made, which is why this needs no bot
  running and no token: a webhook is a one way address into one channel and
  nothing else.

    .\Publish-Discord.ps1
    .\Publish-Discord.ps1 -Quiet
    .\Publish-Discord.ps1 -Dev
    .\Publish-Discord.ps1 -DryRun

  -DryRun prints what it would post and sends nothing.

  IT REMEMBERS WHAT IT POSTED. Until 23 September this script always posted
  whatever was newest in the feed and had no idea it had posted it before, so
  running it twice, or running it days after a release to see what it does,
  announced that release again to everybody. It now writes the version and
  the title it posted into discord\announced.json and refuses to say the same
  thing twice. -Force is how a post that really does need repeating is made,
  and it is the only way.

  That file is one line per channel and it is NOT in git: the two builds
  announce different versions and each shipping machine has its own history,
  so a tracked copy would be a merge conflict on every release.

  Called by Ship.ps1 at the end of every release, so it is usually not run on
  its own. If tools\discord\news-webhook.txt is not there it does nothing and
  says so quietly, so a machine without the Discord set up still ships fine.

  -Dev is the dev build's release, and it is a different channel, a different
  feed and a different webhook. It reads the dev release worktree
  (Thornswood-Releases-dev) rather than the live one, and it posts through
  tools\discord\dev-webhook.txt, which Set-DevNews.ps1 writes and which points
  at the dev updates channel. Nothing about a dev release reaches #news, the
  website or the main launcher: Ship.ps1 does not run Publish-News.ps1 on a
  dev release, and a dev publish only ever writes the dev feed, which only the
  dev launcher reads.

  Two things this used to get wrong, both visible in the channel:

  A webhook post does not inherit the application's avatar. Without an
  avatar_url every release arrived under the plain blue Discord mark while the
  bot's own messages, right above it in the same channel, carried the
  Thornswood logo.

  And it posted the detail lines raw. The launcher's feed is a developer's
  changelog, so the first bullet under a release title was "Launcher 1.0.197",
  which the embed already says in its footer. Publish-News.ps1 has always
  stripped those on the way to the website. The same list is stripped here.
#>
[CmdletBinding()]
param(
  [string]$Webhook,
  # The dev build's release, into the dev updates channel. See the note above.
  [switch]$Dev,
  # Print the post and send nothing.
  [switch]$DryRun,
  # Post it even though this exact release has been announced already. For a
  # post that was deleted, or a channel that was cleared.
  [switch]$Force,
  # Where the LIVE version.json is. Same reason Publish-News.ps1 has this:
  # releases moved into their own public repo, and the copy still sitting in
  # this repo stopped being updated the day that happened. Reading the stale
  # one would post a release nobody shipped.
  [string]$ReleaseDir = 'C:\Users\evilp\Downloads\Thornswood-Releases',
  [string]$Site = 'https://thornswood.net',
  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

# Ship.ps1 runs under strict mode, and reaching for a property a JSON object
# simply does not have throws there rather than returning nothing. A news entry
# written without a file list has no 'files' property at all, so reading it
# straight off the object took the whole post down with "The property 'files'
# cannot be found on this object", while the same script run on its own worked.
# Publish-News.ps1 has had these two for the same reason. Every property on a
# news entry is read through them.
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

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }

# A dev release is announced somewhere else entirely, through a webhook of its
# own, so there is no way for one to arrive in #news by accident.
$hookName = if ($Dev) { 'dev-webhook.txt' } else { 'news-webhook.txt' }
if (-not $Webhook) {
  $f = Join-Path $Here "discord\$hookName"
  if (Test-Path -LiteralPath $f) { $Webhook = (Get-Content $f -Raw).Trim() }
}
if (-not $Webhook) {
  if (-not $Quiet) {
    if ($Dev) {
      Write-Host '  no dev webhook set up, the dev updates channel was not told' -ForegroundColor DarkGray
      Write-Host '  .\tools\Set-DevNews.ps1 points it at that channel' -ForegroundColor DarkGray
    } else {
      Write-Host '  no Discord webhook set up, skipping' -ForegroundColor DarkGray
    }
  }
  return
}

# The dev build follows its own release branch, checked out as a worktree
# beside the live clone. Reading the live one here would announce main's last
# release into the dev channel every time a dev build went out.
if ($Dev -and -not $PSBoundParameters.ContainsKey('ReleaseDir')) {
  $ReleaseDir = Join-Path (Split-Path -Parent $ReleaseDir) 'Thornswood-Releases-dev'
}

$repoV = Join-Path (Split-Path -Parent $Here) 'version.json'
$liveV = Join-Path $ReleaseDir 'version.json'
$vf = $null
if (Test-Path -LiteralPath $liveV) { $vf = $liveV }
elseif (Test-Path -LiteralPath $repoV) {
  $vf = $repoV
  if (-not $Quiet) {
    Write-Host "  no version.json in $ReleaseDir, falling back to the copy in this repo." -ForegroundColor Yellow
    Write-Host "  That one is stale, so this may post a release that never shipped." -ForegroundColor Yellow
  }
} else {
  if (-not $Quiet) { Write-Host '  no version.json anywhere, nothing posted' -ForegroundColor DarkGray }
  return
}

# A byte order mark is not JSON and ConvertFrom-Json stops on the first
# character, which is the trap that has bitten every other reader of this file.
$v = ((Get-Content $vf -Raw) -replace '^\uFEFF', '') | ConvertFrom-Json
$n = @(PropList $v 'news')[0]
if (-not $n) { if (-not $Quiet) { Write-Host '  nothing to post' }; return }

$logo = "$Site/logo.png"
# Who the post is from. Said once, used in three places.
$devName = if ($Dev) { 'Thornswood dev' } else { 'Thornswood' }

# ------------------------------------------------------------------ cleaning
# The same list Publish-News.ps1 strips on the way to the website. Lines that
# mean something to you and nothing to anybody reading the channel.
$noise = @(
  '^\s*Launcher rebuilt\s*:',
  '^\s*Launcher \d+\.\d+',
  'files? to download',
  '[\\/](SKSE|Data|tools)[\\/]'
)

$lines = @()
foreach ($d in @(PropList $n 'details')) {
  $line = ([string]$d).TrimEnd()
  # Blank lines are the section breaks in a hand written release and they are
  # worth keeping, so they survive the filter that drops everything else empty.
  if (-not $line.Trim()) { $lines += ''; continue }
  if ($noise | Where-Object { $line -match $_ }) { continue }
  $lines += $line
}

# ------------------------------------------------------------------- shaping
# A release is written as run on prose with bare capitalised headings in it.
# Discord will not do anything with that on its own, so the headings are found
# and made headings, and everything else becomes a bullet.
$sb = New-Object Text.StringBuilder
$prevBlank = $true
foreach ($line in $lines) {
  if (-not $line.Trim()) {
    if (-not $prevBlank) { [void]$sb.Append("`n") }
    $prevBlank = $true
    continue
  }
  $prevBlank = $false

  # A whole line in capitals is a section on its own: MODS ADDED, LAUNCHER.
  if ($line -cmatch '^[A-Z][A-Z0-9 ,''&.\-]{3,}$') {
    [void]$sb.Append("`n**" + $line.TrimEnd('.') + "**`n")
    continue
  }
  # A capitalised run then a full stop then prose: "THE COLLECTION. Thornswood's
  # mod list is published on Nexus now, ..."
  $m = [regex]::Match($line, '^([A-Z][A-Z0-9 ,''&\-]{3,})\.\s+(.*)$')
  if ($m.Success) {
    [void]$sb.Append("`n**" + $m.Groups[1].Value + "**`n" + $m.Groups[2].Value + "`n")
    continue
  }
  [void]$sb.Append('- ' + $line + "`n")
}

$text = ($sb.ToString() -replace "`n{3,}", "`n`n").Trim()
if (-not $text) { $text = (Prop $n 'body').Trim() }

# Discord takes 4096 characters in one description and 6000 across a whole
# message, so a release the size of 1.1 does not fit in one and is not meant
# to. Two embeds carry almost six thousand of it between them, split on a line
# break rather than mid sentence, and whatever is left is on the website.
$first = ''
$second = ''
$over = $false
if ($text.Length -le 3900) {
  $first = $text
} else {
  $cut = $text.Substring(0, 3900)
  $at = $cut.LastIndexOf("`n")
  if ($at -gt 500) { $cut = $cut.Substring(0, $at) }
  $first = $cut.TrimEnd()
  $rest = $text.Substring($first.Length).TrimStart()
  if ($rest.Length -le 1900) {
    $second = $rest
  } else {
    $cut2 = $rest.Substring(0, 1900)
    $at2 = $cut2.LastIndexOf("`n")
    if ($at2 -gt 300) { $cut2 = $cut2.Substring(0, $at2) }
    $second = $cut2.TrimEnd()
    $over = $true
  }
}

# The else has to sit on the closing brace. PowerShell treats a newline in
# front of it as the end of the statement and then fails on a stray else.
# The website's news page is main's list. A dev release is not on it and never
# will be, so a dev post links to nothing rather than to somewhere wrong.
$tail = if ($Dev) {
  if ($over) { "`n`n(the rest is in the dev launcher's News tab)" } else { '' }
} elseif ($over) { "`n`n[Read the rest on the website]($Site/news)" }
  else { "`n`n[Every release]($Site/news)" }
if ($second) { $second += $tail } else { $first += $tail }

$count = @(PropList $n 'files').Count
# Built from a char code rather than typed in, because a .ps1 saved without a
# byte order mark is read as ANSI by Windows PowerShell and a middle dot typed
# straight into the file comes out the other end as something else.
$dot   = [string][char]0x00B7
$foot  = $(if ($Dev) { 'dev build ' } else { 'launcher ' }) + (Prop $v 'launcherVersion')
$date  = Prop $n 'date'
if ($date)    { $foot += "  $dot  $date" }
if ($count)   { $foot += "  $dot  $count file$(if ($count -ne 1) {'s'}) changed" }

$title = Prop $n 'title'
# Said in the title as well as the footer. The dev channel is the one place
# the two builds' notes could ever be taken for each other.
if ($Dev) { $title = 'Dev build: ' + $title }
if ($title.Length -gt 250) { $title = $title.Substring(0, 247) + '...' }

# ------------------------------------------------------------- said before?
# Keyed by channel, because a dev release and a main release are different
# announcements of different versions and the dev feed is shared between both
# machines. The version alone is not enough on its own: a dev build can be
# reshipped under the same number with a different note, and that note is
# worth saying. The pair is what gets remembered.
$stateFile = Join-Path $Here 'discord\announced.json'
$stateKey = if ($Dev) { 'dev' } else { 'main' }
$said = @{}
if (Test-Path -LiteralPath $stateFile) {
  # A file that will not parse is treated as no file at all. It is a note to
  # ourselves about what was posted, and refusing to ship over a corrupted
  # note would be the tail wagging the dog.
  try {
    $raw = ((Get-Content $stateFile -Raw) -replace '^\uFEFF', '') | ConvertFrom-Json
    foreach ($p in $raw.PSObject.Properties) { $said[$p.Name] = $p.Value }
  } catch {
    if (-not $Quiet) { Write-Host '  announced.json will not parse, treating it as empty' -ForegroundColor DarkGray }
  }
}
$stamp = (Prop $v 'launcherVersion') + '|' + $title
if ($said.ContainsKey($stateKey) -and (Prop $said[$stateKey] 'stamp') -eq $stamp -and -not $Force) {
  if (-not $Quiet) {
    Write-Host ('  already announced ' + (Prop $v 'launcherVersion') + ' in ' +
                $(if ($Dev) { 'the dev updates channel' } else { '#news' }) +
                ', nothing posted') -ForegroundColor DarkGray
    Write-Host '  -Force says it again anyway' -ForegroundColor DarkGray
  }
  $global:ThornswoodDiscordResult = 'already'
  return
}

$last = @{
  description = $(if ($second) { $second } else { $first })
  # Gold for the release everybody gets, a colder blue for the dev build, so
  # the two are never taken for each other at a glance.
  color       = $(if ($Dev) { 5477574 } else { 13214795 })
  footer      = @{ text = $foot; icon_url = $logo }
  timestamp   = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
}

if ($second) {
  $embeds = @(
    @{
      author      = @{ name = $devName; url = $Site; icon_url = $logo }
      title       = $title
      url         = "$Site/news"
      description = $first
      color       = $(if ($Dev) { 5477574 } else { 13214795 })
      thumbnail   = @{ url = $logo }
    },
    $last
  )
} else {
  $last['author']    = @{ name = $devName; url = $Site; icon_url = $logo }
  $last['title']     = $title
  $last['url']       = "$Site/news"
  $last['thumbnail'] = @{ url = $logo }
  $embeds = @($last)
}

$payload = @{
  username   = $devName
  # Without this a webhook posts under the plain blue Discord mark, whatever
  # avatar the application itself has.
  avatar_url = $logo
  embeds     = $embeds
} | ConvertTo-Json -Depth 8

if ($DryRun) {
  Write-Host ''
  Write-Host "  would post to $(if ($Dev) { 'the dev updates channel' } else { '#news' }): $title" -ForegroundColor Yellow
  Write-Host '  ---' -ForegroundColor DarkGray
  foreach ($e in $embeds) {
    ($e.description -split "`n") | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
  }
  Write-Host '  ---' -ForegroundColor DarkGray
  Write-Host "  $foot" -ForegroundColor DarkGray
  Write-Host ''
  Write-Host '  -DryRun, so nothing was sent.' -ForegroundColor Yellow
  return
}

try {
  Invoke-RestMethod -Uri $Webhook -Method Post -ContentType 'application/json' `
    -Body ([Text.Encoding]::UTF8.GetBytes($payload)) | Out-Null
  if (-not $Quiet) { Write-Host "  posted to Discord: $title" }
  $global:ThornswoodDiscordResult = 'posted'
  # AFTER the post returns and never before. A file written first turns a
  # failed post into a release nobody is ever told about, because the next
  # run would read it and refuse.
  try {
    $said[$stateKey] = @{ stamp = $stamp; version = (Prop $v 'launcherVersion')
                          title = $title; at = (Get-Date).ToUniversalTime().ToString('s') + 'Z' }
    ($said | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $stateFile -Encoding UTF8
  } catch {
    if (-not $Quiet) { Write-Host "  posted, but could not write announced.json: $_" -ForegroundColor Yellow }
  }
} catch {
  # Said in colour and said again by Ship at the end. A release whose
  # announcement failed is a release nobody knows about, and a grey line in
  # the middle of a long log is a line nobody reads.
  Write-Host "  COULD NOT POST TO DISCORD: $_" -ForegroundColor Red
  $global:ThornswoodDiscordResult = 'failed'
}
