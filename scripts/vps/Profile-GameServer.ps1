<#
  Profile-GameServer.ps1

      .\scripts\vps\Profile-GameServer.ps1                    the dev server, two minutes
      .\scripts\vps\Profile-GameServer.ps1 -Server main -Seconds 60

  Where a game server's processor time goes (#3181). Each one used about a
  ninth of a core all day with nobody on, and nothing said whether it was the
  NPC activity, the saves it caused or the engine's own loop. This drops
  profile.json in the server's data folder over ssh, as Request-Restart.ps1
  drops restart.json; the gamemode's CPU PROFILE ON REQUEST block samples its
  own process for -Seconds and writes profiles\newest.txt and
  profiles\newest.cpuprofile beside it. This waits for them and prints
  newest.txt: how much of a core the JavaScript thread was busy, then where,
  by file and by function. newest.cpuprofile stays on the box for a closer
  look (Chrome's DevTools or VS Code open it).

  Nothing restarts, no port is opened, and nobody on the server is put out:
  the sampling costs a few percent of one core while it runs. Needs a
  gamemode with the block in it (#3181) on that server.
#>
[CmdletBinding()]
param(
  [ValidateSet('dev', 'main')]
  [string]$Server = 'dev',
  [ValidateRange(1, 600)]
  [int]$Seconds = 120,
  [string]$Vps  = '',
  [string]$User = '',
  [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here 'Vps.ps1')
. (Join-Path $Here 'Send-Script.ps1')
if (-not $User) { $User = Get-ThornswoodVpsUser }
if (-not $Vps) { $Vps = Get-ThornswoodVpsAddress }
$ssh = @('-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes')

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Done([int]$code) { Write-Host ''; if (-not $NoPause) { [void](Read-Host 'Enter to close') }; exit $code }

$root = @{ dev = 'C:\Thornswood-Server-Dev'; main = 'C:\Thornswood-Server' }[$Server]
$body = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((@{ seconds = $Seconds } | ConvertTo-Json -Compress)))

Write-Host ''
Write-Host "  THORNSWOOD  -  where the $Server server's processor time goes" -ForegroundColor White
Say "  sampling $Seconds s in $root; this waits for it" 'DarkGray'

# The data folder is the one server-settings.json names, as the gamemode reads
# it, relative to the server's own folder when it is not a whole path.
$said = @(Invoke-ThornswoodRemote -Target "$User@$Vps" -SshArgs $ssh -Script @"
`$ErrorActionPreference = 'Stop'
`$ProgressPreference = 'SilentlyContinue'
`$cfg = Get-Content -LiteralPath '$root\server-settings.json' -Raw | ConvertFrom-Json
`$data = [string]`$cfg.dataDir
if (-not `$data) { `$data = 'data' }
if (-not [IO.Path]::IsPathRooted(`$data)) { `$data = Join-Path '$root' `$data }
`$out = Join-Path `$data 'profiles\newest.txt'
`$asked = Get-Date
[IO.File]::WriteAllBytes((Join-Path `$data 'profile.json'), [Convert]::FromBase64String('$body'))
'ASKED     ' + (Join-Path `$data 'profile.json')
# Up to five seconds before the gamemode sees it, then the sampling, then the write.
`$deadline = `$asked.AddSeconds($Seconds + 30)
while ((Get-Date) -lt `$deadline) {
  Start-Sleep -Seconds 2
  if ((Test-Path -LiteralPath `$out) -and (Get-Item -LiteralPath `$out).LastWriteTime -gt `$asked) { break }
}
if ((Test-Path -LiteralPath `$out) -and (Get-Item -LiteralPath `$out).LastWriteTime -gt `$asked) {
  'WROTE     ' + `$out
  Get-Content -LiteralPath `$out
} elseif (Test-Path -LiteralPath (Join-Path `$data 'profile.json')) {
  'FAILED    the request is still there after ' + ($Seconds + 30) + ' s, so the gamemode never picked it up. Is the gamemode on this server one with the CPU PROFILE ON REQUEST block (#3181)?'
} else {
  'FAILED    the gamemode took the request but wrote no newest.txt in ' + ($Seconds + 30) + ' s. Its log says why (lines starting cpu profile):'
  Get-Content -LiteralPath '$root\server.log' -Tail 4000 | Where-Object { `$_ -match 'cpu profile' } | Select-Object -Last 10
}
"@)

$failed = $false
foreach ($l in $said) {
  $c = 'Gray'
  if ("$l" -match '^FAILED') { $c = 'Red'; $failed = $true }
  elseif ("$l" -match '^(ASKED|WROTE)') { $c = 'Green' }
  Say "  $l" $c
}
if (-not @($said | Where-Object { "$_" -match '^WROTE ' }).Count) { $failed = $true }
Done ([int]$failed)
