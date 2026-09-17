<#
  Publish-Discord.ps1

  Posts the newest release into the Discord #news channel.

  Uses the webhook Build-Discord.py made, which is why this needs no bot
  running and no token: a webhook is a one way address into one channel and
  nothing else.

    .\Publish-Discord.ps1
    .\Publish-Discord.ps1 -Quiet

  Called by Ship.ps1 at the end of every release, so it is usually not run on
  its own. If tools\discord\news-webhook.txt is not there it does nothing and
  says so quietly, so a machine without the Discord set up still ships fine.

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

if (-not $Webhook) {
  $f = Join-Path $Here 'discord\news-webhook.txt'
  if (Test-Path -LiteralPath $f) { $Webhook = (Get-Content $f -Raw).Trim() }
}
if (-not $Webhook) {
  if (-not $Quiet) { Write-Host '  no Discord webhook set up, skipping' -ForegroundColor DarkGray }
  return
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
$tail = if ($over) { "`n`n[Read the rest on the website]($Site/news)" } else { "`n`n[Every release]($Site/news)" }
if ($second) { $second += $tail } else { $first += $tail }

$count = @(PropList $n 'files').Count
# Built from a char code rather than typed in, because a .ps1 saved without a
# byte order mark is read as ANSI by Windows PowerShell and a middle dot typed
# straight into the file comes out the other end as something else.
$dot   = [string][char]0x00B7
$foot  = 'launcher ' + (Prop $v 'launcherVersion')
$date  = Prop $n 'date'
if ($date)    { $foot += "  $dot  $date" }
if ($count)   { $foot += "  $dot  $count file$(if ($count -ne 1) {'s'}) changed" }

$title = Prop $n 'title'
if ($title.Length -gt 250) { $title = $title.Substring(0, 247) + '...' }

$last = @{
  description = $(if ($second) { $second } else { $first })
  color       = 13214795          # the launcher's gold
  footer      = @{ text = $foot; icon_url = $logo }
  timestamp   = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
}

if ($second) {
  $embeds = @(
    @{
      author      = @{ name = 'Thornswood'; url = $Site; icon_url = $logo }
      title       = $title
      url         = "$Site/news"
      description = $first
      color       = 13214795
      thumbnail   = @{ url = $logo }
    },
    $last
  )
} else {
  $last['author']    = @{ name = 'Thornswood'; url = $Site; icon_url = $logo }
  $last['title']     = $title
  $last['url']       = "$Site/news"
  $last['thumbnail'] = @{ url = $logo }
  $embeds = @($last)
}

$payload = @{
  username   = 'Thornswood'
  # Without this a webhook posts under the plain blue Discord mark, whatever
  # avatar the application itself has.
  avatar_url = $logo
  embeds     = $embeds
} | ConvertTo-Json -Depth 8

try {
  Invoke-RestMethod -Uri $Webhook -Method Post -ContentType 'application/json' `
    -Body ([Text.Encoding]::UTF8.GetBytes($payload)) | Out-Null
  if (-not $Quiet) { Write-Host "  posted to Discord: $title" }
} catch {
  if (-not $Quiet) { Write-Host "  could not post to Discord: $_" -ForegroundColor DarkGray }
}
