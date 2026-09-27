<#
  Get-Logs.ps1

  Brings the server's own logs down to this machine so they can be read whole.

  Chargen-Log.ps1 already asks the VPS a set of questions and prints the
  answers. That is the right shape when you know what you are looking for. It
  is the wrong shape when you do not: a filter can only ever return the lines
  somebody already thought to search for, and the line that explains a problem
  is almost never one of them. The second and third time a bug has been chased
  here it was a line nobody would have grepped for, sitting next to one that
  was.

  So this one filters nothing. It copies the tail of each log into
  Thornswood-Repo\logs and tells you where it put them.

      .\Get-Logs.ps1                pull the last 4000 lines of each
      .\Get-Logs.ps1 -Lines 40000   pull a lot more
      .\Get-Logs.ps1 -All           pull the whole thing, however big it is

  Three files come back:

      site.log      the website, the Discord door and the launcher check in
      bot.log       the Discord bot, the panel and the site watcher
      server.log    the game server, which is where character creation,
                    connections, item handouts and gamemode errors are
      voice.log     the voice and register service
      health.json   what the voice service says about itself right now

  Nothing on the VPS is changed. Everything here is a read.
#>
[CmdletBinding()]
param(
    [string]$Vps   = '',
    [string]$User  = 'Administrator',
    [int]$Lines    = 4000,
    [switch]$All,
    [int]$Port     = 0,
    [string]$Out   = '',
    <#
      Which server's logs. Every path in here was the live one, written when
      there was only one server, so the dev server's logs could not be fetched
      at all and the voice health check asked the live service whichever you
      meant. That is the third copy of the same shape in one evening, after
      Publish-Server's verify block and the installer's own answer check.

      -Dev takes the dev roots and the dev voice port. The files land in
      logs\dev\ so a dev pull cannot overwrite a live one, which matters
      because the interesting thing is usually the difference.
    #>
    [switch]$Dev,
    [switch]$NoPause
)

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here 'Vps.ps1')
if (-not $Vps) { $Vps = Get-ThornswoodVpsAddress }
if (-not $Out) {
    $Out = Join-Path (Split-Path -Parent (Split-Path -Parent $Here)) 'logs'
    if ($Dev) { $Out = Join-Path $Out 'dev' }
}
# The dev voice service is its own process on its own port. See -Dev.
if (-not $Port) { $Port = if ($Dev) { 7789 } else { 7778 } }
if (-not (Test-Path -LiteralPath $Out)) { New-Item -ItemType Directory -Path $Out -Force | Out-Null }

$target = "$User@$Vps"

# Every log the server side writes, and what it is for. Adding one here is the
# only change needed to have it come down with the rest.
$srvRoot   = if ($Dev) { 'C:\Thornswood-Server-Dev' } else { 'C:\Thornswood-Server' }
$voiceRoot = if ($Dev) { 'C:\Thornswood-Voice-Dev' }  else { 'C:\Thornswood-Voice' }
# There is one site and one bot, live or dev: the dev launcher and the dev
# server both talk to the same site, so these two do not move with -Dev.
$docsRoot  = 'C:\Thornswood-Docs'
$botRoot   = 'C:\Thornswood-Bot'
Say ("  reading the {0} server at {1}" -f $(if ($Dev) { 'DEV' } else { 'live' }), $srvRoot) 'DarkGray'

$logs = @(
    @{ Name = 'server.log'; Path = (Join-Path $srvRoot 'server.log'); What = 'the game server' }
    # Thornswood's own lines and nothing else. server.log is about four fifths
    # engine noise on a normal day, so this is the one to read first and
    # server.log is where you go when the answer is not in it.
    @{ Name = 'thornswood.log'; Path = (Join-Path $srvRoot 'thornswood.log'); What = 'the gamemode, without the engine noise' }
    <#
      THE DOOR'S OWN LOG, WHICH HAS NEVER COME DOWN WITH THE REST.

      note() in the door block writes every line twice: once through
      console.log, which lands in server.log among four fifths engine noise,
      and once appended to private\door.log, which is the door's own story in
      order with nothing else in it. That second file is the one to read when
      the question is why nobody can get in, and until now there was no way to
      look at it short of an ssh somebody typed by hand.

      21 September: "still can't tp says no list". The answer to that was in
      private, and nothing fetched private.
    #>
    @{ Name = 'door.log'; Path = (Join-Path $srvRoot 'private\door.log'); What = 'the door: who it let in and what the site said' }
    @{ Name = 'voice.log';  Path = (Join-Path $voiceRoot 'voice.log');   What = 'voice and the character register' }
    <#
      The site, added 23 September. It printed everything it worked out into
      a handle nobody held: no redirect on the task and no file anywhere on
      the box. The sentences discordGet works out for every kind of refusal,
      which exist because a dead token, a rate limit and somebody genuinely
      not in the Discord used to look identical, had never once been
      readable. server.js writes them here now and rolls the file at 4 MB,
      keeping five, so site.log.1 to .5 are the older ones if the answer is
      not in the current one.
    #>
    @{ Name = 'site.log';   Path = (Join-Path $docsRoot 'site.log');     What = 'the website and the Discord door' }
    # The bot has written this all along and nothing ever fetched it, which
    # is why the site watcher's startup line had to be read over ssh by hand.
    @{ Name = 'bot.log';    Path = (Join-Path $botRoot 'bot.log');       What = 'the Discord bot, the panel and the site watcher' }
)

Head 'Pulling'

foreach ($l in $logs) {
    $dest = Join-Path $Out $l.Name

    <#
      Read on the far side, not here.

      scp would copy the file, which is the obvious thing and the wrong one:
      server.log grows without bound and there is no reason to move eighty
      megabytes across the internet to read the end of it. Get-Content -Tail
      reads backwards from the end on the machine that already has the file.

      -Raw is deliberately not used. The point is a line count, and -Raw would
      hand back one enormous string with the tail applied to nothing.
    #>
    $tail = if ($All) { '' } else { " -Tail $Lines" }
    $remote = "if (Test-Path -LiteralPath '$($l.Path)') { Get-Content -LiteralPath '$($l.Path)'$tail } else { 'MISSING: $($l.Path)' }"
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($remote))

    $text = & ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new $target "powershell -NoProfile -EncodedCommand $enc" 2>&1

    if ($LASTEXITCODE -ne 0 -and -not $text) {
        Say ("  {0,-12} could not be read. ssh exit {1}" -f $l.Name, $LASTEXITCODE) 'Red'
        continue
    }

    $text | Set-Content -LiteralPath $dest -Encoding UTF8
    $size = if (Test-Path -LiteralPath $dest) { (Get-Item -LiteralPath $dest).Length } else { 0 }
    $count = @($text).Count
    Say ("  {0,-12} {1,7:n0} lines  {2,9:n0} bytes   {3}" -f $l.Name, $count, $size, $l.What) 'Gray'
}

<#
  What the service says about itself. Small, and it is the fastest way to tell
  a stale process from a fresh one, which has cost days here before.

  THROUGH THE SITE FIRST, BECAUSE THAT IS HOW EVERYTHING ELSE REACHES IT.

  This asked http://<vps>:7778/health and nothing else, and on 21 and 22
  September it printed "no answer from <live>:7778" on every pull.
  That read as the voice service being down. It was not: measured on
  22 September, https://thornswood.net/voice/health answers 200 and says

      {"ok":true,"build":"owners-5","auth":"on","bind":"127.0.0.1", ...}

  bind is 127.0.0.1. The service is deliberately on loopback with Caddy
  carrying /voice/, which is exactly what Install-Voice's own -Bind parameter
  describes, and the raw port is therefore shut from outside ON PURPOSE. Both
  services were healthy the entire time this said they were not.

  A check that cries wolf is worse than no check, because the next real outage
  reads as the same yellow line everybody has learned to scroll past. So the
  site is asked first, the raw port is the fallback for a box with no Caddy in
  front of it, and the answer's own bind is printed so the shape of the
  install is visible rather than inferred.
#>
$dest = Join-Path $Out 'health.json'
$voicePath = if ($Dev) { 'voice-dev' } else { 'voice' }
$tries = @(
    @{ Url = "https://thornswood.net/$voicePath/health"; How = 'through the site' }
    @{ Url = "http://${Vps}:$Port/health";               How = "straight at $Vps`:$Port" }
)

$h = $null; $how = ''
foreach ($t in $tries) {
    try {
        $h = Invoke-RestMethod -Uri $t.Url -TimeoutSec 8
        $how = $t.How
        break
    } catch { }
}

if ($h) {
    ($h | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $dest -Encoding UTF8
    $build = if ($h.PSObject.Properties['build']) { $h.build } else { '(no build in the answer)' }
    $bind  = if ($h.PSObject.Properties['bind'])  { $h.bind }  else { '?' }
    $auth  = if ($h.PSObject.Properties['auth'])  { $h.auth }  else { '?' }
    Say ("  {0,-12} build {1}, {2}, bound to {3}, auth {4}" -f 'health.json', $build, $how, $bind, $auth) 'Gray'
    if ($bind -eq '127.0.0.1') {
        Say '               loopback only, so the raw port is shut from outside on purpose' 'DarkGray'
    }
} else {
    ("the voice service did not answer through the site or on the raw port. " +
     "Both were tried.") | Set-Content -LiteralPath $dest -Encoding UTF8
    Say ("  {0,-12} NO ANSWER through the site or on {1}:{2}. This one is real." -f 'health.json', $Vps, $Port) 'Red'
}

Head 'Where they are'
Say "  $Out" 'White'
Write-Host ''
Say 'Nothing on the server was changed. These are copies.' 'DarkGray'
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
