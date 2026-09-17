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
    [int]$Port     = 7778,
    [string]$Out   = '',
    [switch]$NoPause
)

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $Out) { $Out = Join-Path (Split-Path -Parent $Here) 'logs' }
if (-not (Test-Path -LiteralPath $Out)) { New-Item -ItemType Directory -Path $Out -Force | Out-Null }

$target = "$User@$Vps"

# Every log the server side writes, and what it is for. Adding one here is the
# only change needed to have it come down with the rest.
$logs = @(
    @{ Name = 'server.log'; Path = 'C:\Thornswood-Server\server.log'; What = 'the game server' }
    @{ Name = 'voice.log';  Path = 'C:\Thornswood-Voice\voice.log';   What = 'voice and the character register' }
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
