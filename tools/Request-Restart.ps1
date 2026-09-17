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
  [string]$Vps  = '192.135.112.23',
  [string]$User = 'Administrator',
  [string]$Data = 'C:/Thornswood-Server/data'
)

$ErrorActionPreference = 'Stop'
$ssh = @('-o','BatchMode=yes','-o','StrictHostKeyChecking=no')

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
