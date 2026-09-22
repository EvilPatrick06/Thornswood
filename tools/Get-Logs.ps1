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

      server.log    the game server, which is where character creation,
                    connections, item handouts and gamemode errors are
      voice.log     the voice and register service
      health.json   what the voice service says about itself right now

  Nothing on the VPS is changed. Everything here is a read.
#>
[CmdletBinding()]
param(
    [string]$Vps   = '192.135.112.23',
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
if (-not $Out) {
    $Out = Join-Path (Split-Path -Parent $Here) 'logs'
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

    $text = & ssh -o BatchMode=yes -o StrictHostKeyChecking=no $target "powershell -NoProfile -EncodedCommand $enc" 2>&1

    if ($LASTEXITCODE -ne 0 -and -not $text) {
        Say ("  {0,-12} could not be read. ssh exit {1}" -f $l.Name, $LASTEXITCODE) 'Red'
        continue
    }

    $text | Set-Content -LiteralPath $dest -Encoding UTF8
    $size = if (Test-Path -LiteralPath $dest) { (Get-Item -LiteralPath $dest).Length } else { 0 }
    $count = @($text).Count
    Say ("  {0,-12} {1,7:n0} lines  {2,9:n0} bytes   {3}" -f $l.Name, $count, $size, $l.What) 'Gray'
}

# What the service says about itself. Small, and it is the fastest way to tell
# a stale process from a fresh one, which has cost days here before.
$dest = Join-Path $Out 'health.json'
try {
    $h = Invoke-RestMethod -Uri "http://${Vps}:$Port/health" -TimeoutSec 8
    ($h | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $dest -Encoding UTF8
    $build = if ($h.PSObject.Properties['build']) { $h.build } else { '(no build in the answer)' }
    Say ("  {0,-12} build {1}" -f 'health.json', $build) 'Gray'
} catch {
    "the voice service did not answer: $($_.Exception.Message)" | Set-Content -LiteralPath $dest -Encoding UTF8
    Say ("  {0,-12} no answer from {1}:{2}" -f 'health.json', $Vps, $Port) 'Yellow'
}

Head 'Where they are'
Say "  $Out" 'White'
Write-Host ''
Say 'Nothing on the server was changed. These are copies.' 'DarkGray'
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
