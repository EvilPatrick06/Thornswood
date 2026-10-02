<#
.SYNOPSIS
  Says whether the gamemode running on the VPS is the one in this repo.

.DESCRIPTION
  Read only. It hashes game\gamemode.js here, hashes C:\Thornswood-Server\gamemode.js
  up there, and compares them. Nothing is copied and nothing is restarted.

  It exists because this question came up three times on 20 September and was
  guessed at each time. Ship.ps1 does not carry gamemode.js: grep it and the
  word does not appear. The gamemode only travels by Deploy-Gamemode.ps1, which
  copies it into the server build on this machine, and then Deploy-Server.ps1,
  which is what actually sends it up. So a release can go out, twice, with the
  gamemode fix still sitting on the shipping machine and nothing saying so.

  On that day the fix for characters meeting creation a second time was
  committed, built into the local server dist, and not up there, while 1.1.58
  and 1.1.59 both shipped. Testers kept reporting it.

.PARAMETER Vps
  The server. Defaults to the live one.

.EXAMPLE
  .\Check-LiveGamemode.ps1
  Prints a match or a mismatch, and names what to run if they differ.
#>
[CmdletBinding()]
param(
  [string]$Vps  = '',
  [string]$User = '',
  [string]$Remote = 'C:\Thornswood-Server\gamemode.js',
  [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$ssh = @('-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes')

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) {
  Write-Host ''
  Write-Host $m -ForegroundColor Cyan
  Write-Host ('-' * $m.Length) -ForegroundColor DarkGray
}

$Here = $PSScriptRoot
. (Join-Path $Here 'Vps.ps1')
if (-not $User) { $User = Get-ThornswoodVpsUser }
if (-not $Vps) { $Vps = Get-ThornswoodVpsAddress }
$local = Join-Path $Here '..\..\game\gamemode.js'
if (-not (Test-Path -LiteralPath $local)) { throw "not found: $local" }

Head 'Here'
$localHash = (Get-FileHash -LiteralPath $local -Algorithm SHA256).Hash.ToLowerInvariant()
$localSize = (Get-Item -LiteralPath $local).Length
Say ("  game\gamemode.js  {0:N0} bytes" -f $localSize)
Say "  $localHash"

Head 'There'
# Base64 and -EncodedCommand, because nesting quotes inside the ssh argument
# makes the remote shell re-parse the line and try to run the answer as a
# command. Deploy-Server.ps1 has done it this way since 17 September.
# $ProgressPreference or PowerShell wraps the answer in CLIXML progress records.
$script = @"
`$ProgressPreference = 'SilentlyContinue'
if (Test-Path -LiteralPath '$Remote') {
  `$f = Get-Item -LiteralPath '$Remote'
  (Get-FileHash -LiteralPath '$Remote' -Algorithm SHA256).Hash + '|' + `$f.Length + '|' + `$f.LastWriteTimeUtc.ToString('s')
} else { 'MISSING||' }
"@
$enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
$answer = (Invoke-ThornswoodNative { & ssh @ssh "$User@$Vps" "powershell -NoProfile -EncodedCommand $enc" } 2>&1) -join ''
if ($LASTEXITCODE -ne 0) {
  Say "  could not reach the server: $answer" 'Yellow'
  if (-not $NoPause) { [void](Read-Host 'Enter to exit') }
  exit 1
}

$parts = ($answer.Trim() -split '\|')
$remoteHash = $parts[0].Trim().ToLowerInvariant()

if ($remoteHash -eq 'missing') {
  Say "  $Remote is not there at all." 'Red'
  Head 'Verdict'
  Say '  The server has no gamemode.js. Run:' 'Red'
  Say '      .\scripts\deploy\Deploy-Gamemode.ps1' 'Red'
  Say '      .\scripts\deploy\Deploy-Server.ps1' 'Red'
  if (-not $NoPause) { [void](Read-Host 'Enter to exit') }
  exit 1
}

Say ("  $Remote  {0:N0} bytes" -f [int64]$parts[1])
Say "  $remoteHash"
if ($parts.Count -gt 2 -and $parts[2]) { Say "  written $($parts[2]) UTC" 'DarkGray' }

Head 'Verdict'
if ($remoteHash -eq $localHash) {
  Say '  MATCH. The server is running the gamemode in this repo.' 'Green'
  if (-not $NoPause) { [void](Read-Host 'Enter to exit') }
  exit 0
}

Say '  DIFFERENT. The server is running an older gamemode than this repo has.' 'Yellow'
Say '  Anything committed to game\gamemode.js since then is not live, however' 'Yellow'
Say '  many launcher releases have gone out: Ship.ps1 does not carry it.' 'Yellow'
Say ''
Say '  Put it right with, in this order:' 'Yellow'
Say '      .\scripts\deploy\Deploy-Gamemode.ps1' 'Yellow'
Say '      .\scripts\deploy\Deploy-Server.ps1' 'Yellow'
Say '  The second one stops and starts the task, so it bounces the process too.' 'Yellow'
if (-not $NoPause) { [void](Read-Host 'Enter to exit') }
exit 2
