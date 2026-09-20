<#
  Request-Restart.ps1

  Tells the live server to warn everybody and then clear them out, without
  needing to be standing in the world to type /restart.

  Drops a small json file into the server's data folder over ssh. The gamemode
  checks for it every tick and a half, acts on it, and deletes it, so a file
  left behind by a crash cannot fire again on the next boot.

    .\Request-Restart.ps1                     5 minutes, an update
    .\Request-Restart.ps1 -Minutes 10
    .\Request-Restart.ps1 -Mode restart -Why "a server rebuild"
    .\Request-Restart.ps1 -Cancel
    .\Request-Restart.ps1 -Mode restart -ThenRestart

  -ThenRestart waits out the countdown and then bounces the process, which is
  the half this script does not do on its own. A kick with nothing restarting
  behind it leaves everybody who reconnects in an empty world with no NPCs,
  and they stay that way until the process is bounced. Without the switch the
  script says so at the end rather than assuming you knew.

  Mode decides the wording and whether anybody is put out.

    notice   the server is about to blink. A freeze of a few seconds, then
             everything carries on. Nobody is disconnected. This is what a
             server build push actually is.
    update   a pack has been published, so everyone has to quit to the
             launcher to pick it up. Ends with a kick.
    restart  the server itself is going down for longer. Ends with a kick.
#>
[CmdletBinding()]
param(
  [double]$Minutes = 5,
  [ValidateSet('notice','update','restart')]
  [string]$Mode = 'update',
  [string]$Why  = 'an update',
  [switch]$Cancel,
  # Wait out the countdown and then bounce the process, because the kick on its
  # own is what strands people in an empty world. See the block at the bottom.
  [switch]$ThenRestart,
  [string]$Vps  = '192.135.112.23',
  [string]$User = 'Administrator',
  [string]$Data = 'C:/Thornswood-Server/data'
)

$ErrorActionPreference = 'Stop'
$ssh = @('-o','BatchMode=yes','-o','StrictHostKeyChecking=no')

if ($ThenRestart -and $Cancel) { throw 'Use one or the other: -Cancel calls it off, -ThenRestart sees it through.' }
if ($ThenRestart -and $Mode -eq 'notice') {
  throw 'A notice disconnects nobody, so there is nothing to restart afterwards. Drop -ThenRestart, or use -Mode restart.'
}

if ($Cancel) {
  $body = '{"cancel":true}'
  $what = 'cancelling'
} else {
  if ($Minutes -le 0) { throw 'Minutes has to be more than zero.' }
  $secs = [int][Math]::Round($Minutes * 60)
  $body = @{ seconds = $secs; mode = $Mode; why = $Why } | ConvertTo-Json -Compress
  $what = "$Mode in $Minutes min for $Why"
}

# Written through a base64 hop so quoting survives ssh, cmd and PowerShell.
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($body))
$remote = @"
`$ErrorActionPreference = 'Stop'
if (-not (Test-Path '$Data')) { New-Item -ItemType Directory -Path '$Data' -Force | Out-Null }
[IO.File]::WriteAllBytes((Join-Path '$Data' 'restart.json'),
                         [Convert]::FromBase64String('$b64'))
'dropped'
"@
$enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($remote))

$out = & ssh @ssh "$User@$Vps" "powershell -NoProfile -EncodedCommand $enc" 2>&1
if ($LASTEXITCODE -ne 0) {
  Write-Host "  could not reach the server to announce it: $out" -ForegroundColor Yellow
  exit 1
}

Write-Host "  server told: $what" -ForegroundColor Green

# The kick is only half of it, and the missing half is not obvious from here.
#
# 'update' and 'restart' both end in everybody being disconnected. A kick with
# no process restart behind it leaves the kicked character in a state where the
# reconnecting client is never sent the world: they come back to an empty
# Skyrim with no NPCs in it, and they stay that way until the process is
# bounced. gamemode.js records 13 reconnects like that on 17 September, and it
# was reported again on 20 September.
#
# Deploy-Server.ps1 calls this and then stops and starts the task, so that path
# was always whole. Running this by hand is where the half happens, so -ThenRestart
# sees it through and the bare call says what it is leaving undone.
if ($Mode -ne 'notice') {
  if ($ThenRestart) {
    $wait = [int][Math]::Round($Minutes * 60) + 15   # the countdown, plus the tick that acts on it
    Write-Host ''
    Write-Host "  -ThenRestart: waiting $wait seconds for the countdown, then restarting the process." -ForegroundColor Cyan
    Write-Host '  Leave this window open. Ctrl+C stops the restart, not the kick.' -ForegroundColor DarkGray
    Start-Sleep -Seconds $wait
    $restart = Join-Path $PSScriptRoot 'Restart-Server.ps1'
    if (-not (Test-Path -LiteralPath $restart)) {
      Write-Host "  Restart-Server.ps1 is missing, so the process was NOT restarted." -ForegroundColor Red
      Write-Host '  Bounce it yourself or people will come back to an empty world.' -ForegroundColor Red
      exit 1
    }
    # -Now because the room was just cleared on purpose: the online check would
    # refuse on anybody who has already reconnected, which is exactly who this
    # is for.
    & $restart -Service game -Now -Vps $Vps -User $User -NoPause
    if ($LASTEXITCODE -ne 0) {
      Write-Host '  The restart did not go through. Run .\tools\Restart-Server.ps1 yourself.' -ForegroundColor Red
      exit 1
    }
    Write-Host '  kicked and restarted. Nobody is stranded.' -ForegroundColor Green
  } else {
    Write-Host ''
    Write-Host '  This mode ends in a kick, and a kick on its own is not enough.' -ForegroundColor Yellow
    Write-Host '  Anybody kicked without the process being restarted comes back to' -ForegroundColor Yellow
    Write-Host '  an empty world with no NPCs and stays that way. Either add' -ForegroundColor Yellow
    Write-Host '      -ThenRestart' -ForegroundColor Yellow
    Write-Host '  to this command, or follow it with:' -ForegroundColor Yellow
    Write-Host '      .\tools\Restart-Server.ps1' -ForegroundColor Yellow
    Write-Host '  unless you are running Deploy-Server.ps1, which does it for you.' -ForegroundColor Yellow
  }
}
