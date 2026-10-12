<#
  Setup-Discord.ps1

  Builds the Thornswood Discord: roles, categories, channels, permissions and
  the words in the read only channels, in one run.

  Run it again any time. Anything already there is left alone and anything
  missing is made. It does NOT rewrite the read only posts unless you ask, so
  a run to add one channel no longer deletes and re-sends every rule, welcome
  and faq message in the server.

    .\Setup-Discord.ps1            roles, channels, permissions, settings
    .\Setup-Discord.ps1 -Posts     also rewrites the read only posts from
                                    content.py. Use this when the wording moved.
    .\Setup-Discord.ps1 -Check     changes nothing at all, just says what it
                                    would do
    .\Setup-Discord.ps1 -Prune     also deletes channels this no longer wants

  First time only, before running it:

    1. https://discord.com/developers/applications
       The same application the website login uses is fine, or make a new one.
    2. Bot in the sidebar, then Reset Token, and copy what it gives you.
    3. Still under Bot, turn ON "Server Members Intent". Leave the rest off.
    4. OAuth2, URL Generator, tick "bot" and then "Administrator". Open the URL
       it builds and add the bot to your server. Administrator is for the build
       only: it makes the Owner and Dev roles, which carry Administrator, and
       Discord refuses that from a bot without it.

  Two permission sets. Administrator for a build, and a smaller set for the
  rest of the time, which is all the running bot needs. A build that finishes
  with nothing failed ends on the invite link with that smaller set and a line
  saying to untick Administrator on the bot's role. Tick it again before the
  next build. To see that link without building anything, from the repository
  folder, with the id from the developer portal's General Information page:

    python bot\Build-Discord.py --invite <application id>
    5. Server Settings, Roles: drag the bot's own role to the TOP. It cannot
       make roles above itself.
    6. Server Settings, Enable Community, so forums, the announcement channel
       and the rules screen exist at all.

  It asks for the token rather than taking it on the command line, so it stays
  out of your history. Nothing writes it to disk.
#>
[CmdletBinding()]
param(
  [string]$Guild,
  [switch]$SkipInstall,
  # Removes channels this no longer wants. Without it they are only listed.
  # Scoped to the categories this script made, so anything you added yourself
  # is never touched.
  [switch]$Prune,
  # Rewrites the read only posts from content.py. Off by default: it deletes
  # the bot's old messages in each of those channels and sends them again, and
  # doing that on every run turns a one channel change into the whole server
  # flashing.
  [switch]$Posts,
  # Touches nothing. Says what it would make, remove and rewrite, then stops.
  [switch]$Check
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$app = Join-Path $Here '..\..\bot\Build-Discord.py'
if (-not (Test-Path -LiteralPath $app)) { throw "not found: $app" }

# The bot's Python is 3.12. Plain python is whichever is first on PATH, which
# on a PC with more than one can be too old (on One it is 3.9, #2276), so the
# py launcher's 3.12 comes first, then python if it is 3.10 or newer.
$py = $null
$pyArgs = @()
$launcher = (Get-Command py -EA SilentlyContinue).Source
if ($launcher) {
  & $launcher -3.12 -c 'import sys' 2>$null
  if ($LASTEXITCODE -eq 0) { $py = $launcher; $pyArgs = @('-3.12') }
}
if (-not $py) {
  $plain = (Get-Command python -EA SilentlyContinue).Source
  if ($plain) {
    & $plain -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>$null
    if ($LASTEXITCODE -eq 0) { $py = $plain }
  }
}
if (-not $py) { throw 'No Python 3.10 or newer found. Install Python 3.12 (py -3.12 should run it).' }

if (-not $SkipInstall) {
  Write-Host 'Making sure discord.py is here...'
  & $py @pyArgs -m pip install -q -U discord.py
  if ($LASTEXITCODE -ne 0) { throw 'pip could not install discord.py' }
  Write-Host '  ready'
}

$ss = Read-Host 'Bot token (paste it, it will not be shown)' -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss)
try { $tok = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
$ss = $null
if (-not $tok) { throw 'No token given.' }

# Only for this process. Nothing is written down and nothing outlives the run.
$env:DISCORD_TOKEN = $tok
if ($Guild) { $env:DISCORD_GUILD = $Guild }
if ($Prune) { $env:DISCORD_PRUNE = '1' }
if ($Posts) { $env:DISCORD_POSTS = '1' }
if ($Check) { $env:DISCORD_CHECK = '1' }
$tok = $null

# The one switch (#428): the site's "open", read off its public page so the
# posts say the same as the site. Anything that goes wrong is the alpha
# wording, which is what is true until somebody flips it.
$open = $false
try {
  $pub = Invoke-RestMethod -Uri 'https://thornswood.net/api/public' -TimeoutSec 15
  $open = ($pub.open -eq $true)
} catch {
  Write-Host ('  Could not ask the site whether the world is open (' + $_.Exception.Message + '), so the posts use the alpha wording.') -ForegroundColor Yellow
}
$env:THORNSWOOD_OPEN = $(if ($open) { '1' } else { '0' })
if ($Posts) {
  if ($open) { Write-Host '  The site says the world is open to everybody, so the posts say so.' }
  else { Write-Host '  The site says the world is in alpha, open by application, so the posts say so.' }
}

try {
  & $py @pyArgs $app
  $code = $LASTEXITCODE
} finally {
  $env:DISCORD_TOKEN = $null
  $env:DISCORD_PRUNE = $null
  $env:DISCORD_POSTS = $null
  $env:DISCORD_CHECK = $null
  $env:THORNSWOOD_OPEN = $null
}

# It used to say the webhook was ready whatever happened, including on the run
# that stopped on a missing intent and built nothing at all. A script that
# congratulates you for work it did not do is worse than one that says nothing.
if ($code -ne 0) {
  Write-Host ''
  Write-Host '  Nothing was built. Fix what it said above and run it again.' -ForegroundColor Yellow
  exit $code
}

$hook = Join-Path $Here '..\..\bot\news-webhook.txt'
Write-Host ''
# An empty bot\news-webhook.txt reads back as $null, and .Trim() on that threw
# before anything was said. Wrapped in a string it is '', which is refused here:
# ConvertTo-SecureString cannot take an empty string, so Discord-Hook.ps1's own
# address check never gets the chance.
$hookText = ''
if (Test-Path -LiteralPath $hook) { $hookText = "$(Get-Content -LiteralPath $hook -Raw)".Trim() }
if ((Test-Path -LiteralPath $hook) -and -not $hookText) {
  Write-Host '  bot\news-webhook.txt is empty, so nothing was sent to the VPS and releases will not' -ForegroundColor Yellow
  Write-Host '  post themselves into #news yet. Run this again once #news exists.' -ForegroundColor Yellow
} elseif ($hookText) {
  # Onto the VPS, where every machine that ships reads it (Discord-Hook.ps1); the
  # copy here is removed once the VPS has it.
  # Handed over as a SecureString (issue #1069), read from the file here.
  & (Join-Path $Here '..\ops\Discord-Hook.ps1') -Name news -Save -Url (ConvertTo-SecureString $hookText -AsPlainText -Force)
  $hookText = $null
  if ($LASTEXITCODE -eq 0) {
    Write-Host '  Release notes will post themselves into #news from now on.' -ForegroundColor Green
  } else {
    Write-Host '  The webhook is in bot\news-webhook.txt here but not on the VPS, so only this machine posts to #news.' -ForegroundColor Yellow
  }
} else {
  Write-Host '  Built, but no webhook was made, so releases will not post' -ForegroundColor Yellow
  Write-Host '  themselves into #news yet. Run this again once #news exists.' -ForegroundColor Yellow
}
