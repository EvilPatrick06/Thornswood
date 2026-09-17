<#
  Setup-Domain.ps1

  Puts thornswood.net in front of the docs site, with a real certificate.

  Run this AFTER the domain is bought and its DNS A record points at the VPS.
  It checks that first and stops if it does not, because a certificate request
  against a name that does not resolve here gets you rate limited by Let's
  Encrypt rather than a certificate.

    .\Setup-Domain.ps1
    .\Setup-Domain.ps1 -Domain thornswood.net -Email you@example.com

  Caddy rather than win-acme and node's own TLS. Caddy obtains the certificate,
  renews it on its own forever, redirects plain HTTP to HTTPS and proxies to
  the docs site, and the whole configuration is four lines. The alternative is
  a certificate request, an export to PEM, node reading two files, and a
  renewal task that everyone forgets until the site goes down 90 days later.

  The docs site is also moved onto loopback by this, so port 3001 stops being
  a way around the certificate.
#>
[CmdletBinding()]
param(
  [string]$Domain = 'thornswood.net',
  [string]$Email,
  [string]$Vps  = '192.135.112.23',
  [string]$User = 'Administrator',
  [string]$Root = 'C:/Thornswood-Docs',
  [string]$CaddyDir = 'C:/Thornswood-Caddy',
  [switch]$SkipDnsCheck
)

$ErrorActionPreference = 'Stop'
$ssh = @('-o','BatchMode=yes','-o','StrictHostKeyChecking=no')

function Remote($script) {
  $e = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
  & ssh @ssh "$User@$Vps" "powershell -NoProfile -EncodedCommand $e" 2>&1
}

# ------------------------------------------------------------------- dns --
if (-not $SkipDnsCheck) {
  Write-Host "Checking where $Domain points..."
  $ips = @()
  foreach ($name in @($Domain, "www.$Domain")) {
    try {
      $ips += (Resolve-DnsName $name -Type A -ErrorAction Stop |
               Where-Object { $_.IPAddress }).IPAddress
    } catch { }
  }
  $ips = $ips | Sort-Object -Unique
  if (-not $ips) {
    throw "$Domain does not resolve yet. Add an A record for @ and www pointing at $Vps, then wait for it to spread. Minutes usually, up to an hour."
  }
  if ($ips -notcontains $Vps) {
    throw "$Domain resolves to $($ips -join ', ') and not $Vps. Fix the A record first."
  }
  Write-Host "  points at $Vps" -ForegroundColor Green
}

# ----------------------------------------------------------------- caddy --
$caddyWin = $CaddyDir.Replace('/','\')
$rootWin  = $Root.Replace('/','\')
$emailLine = if ($Email) { "`n`temail $Email" } else { '' }

Write-Host ''
Write-Host 'Setting up Caddy on the VPS...'

$caddyfile = @"
{$emailLine
}

$Domain, www.$Domain {
	encode gzip
	reverse_proxy 127.0.0.1:3001
}
"@
$cfg64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($caddyfile))

Remote @"
`$ErrorActionPreference = 'Stop'
`$dir = '$caddyWin'
if (-not (Test-Path `$dir)) { New-Item -ItemType Directory -Path `$dir -Force | Out-Null }

if (-not (Test-Path (Join-Path `$dir 'caddy.exe'))) {
  'downloading caddy'
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Invoke-WebRequest -UseBasicParsing ``
    -Uri 'https://caddyserver.com/api/download?os=windows&arch=amd64' ``
    -OutFile (Join-Path `$dir 'caddy.exe')
  'downloaded'
} else { 'caddy already here' }

[IO.File]::WriteAllBytes((Join-Path `$dir 'Caddyfile'),
                         [Convert]::FromBase64String('$cfg64'))
'Caddyfile written'

foreach (`$p in 80,443) {
  `$n = 'Thornswood Web ' + `$p
  if (-not (Get-NetFirewallRule -DisplayName `$n -EA SilentlyContinue)) {
    New-NetFirewallRule -DisplayName `$n -Direction Inbound -Protocol TCP ``
      -LocalPort `$p -Action Allow | Out-Null
    'opened ' + `$p
  }
}
"@ | ForEach-Object { "  $_" }

# The docs site moves to loopback, so 3001 is no longer a plain HTTP way in.
Write-Host ''
Write-Host 'Closing port 3001 to the outside...'
Remote @"
`$ErrorActionPreference = 'Continue'
Get-NetFirewallRule -DisplayName 'Thornswood Docs' -EA SilentlyContinue |
  Remove-NetFirewallRule -EA SilentlyContinue

`$t = Get-ScheduledTask -TaskName 'Thornswood Docs' -EA SilentlyContinue
if (`$t) {
  `$node = (Get-Command node -EA SilentlyContinue).Source
  `$a = New-ScheduledTaskAction -Execute `$node -Argument '$rootWin\server.js' -WorkingDirectory '$rootWin'
  Set-ScheduledTask -TaskName 'Thornswood Docs' -Action `$a | Out-Null
}
[Environment]::SetEnvironmentVariable('THORNSWOOD_DOCS_LOCAL','1','Machine')

Get-CimInstance Win32_Process |
  Where-Object { `$_.Name -eq 'node.exe' -and `$_.CommandLine -like '*Thornswood-Docs*' } |
  ForEach-Object { Stop-Process -Id `$_.ProcessId -Force -EA SilentlyContinue }
Start-Sleep -Seconds 1
Start-ScheduledTask -TaskName 'Thornswood Docs' -EA SilentlyContinue
'docs restarted on loopback'
"@ | ForEach-Object { "  $_" }

Write-Host ''
Write-Host 'Starting Caddy...'
Remote @"
`$ErrorActionPreference = 'Continue'
`$dir = '$caddyWin'
`$exe = Join-Path `$dir 'caddy.exe'

Get-Process caddy -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue

if (-not (Get-ScheduledTask -TaskName 'Thornswood Web' -EA SilentlyContinue)) {
  `$a = New-ScheduledTaskAction -Execute `$exe ``
        -Argument 'run --config Caddyfile' -WorkingDirectory `$dir
  `$t = New-ScheduledTaskTrigger -AtStartup
  `$s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries ``
        -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
  Register-ScheduledTask -TaskName 'Thornswood Web' -Action `$a -Trigger `$t ``
    -Settings `$s -RunLevel Highest -User 'SYSTEM' | Out-Null
  'scheduled task created'
}

Start-ScheduledTask -TaskName 'Thornswood Web'
# The first start asks Let's Encrypt for a certificate, which takes a moment.
Start-Sleep -Seconds 12
`$p = Get-Process caddy -EA SilentlyContinue
if (`$p) { 'caddy up, pid ' + `$p.Id } else { 'CADDY DID NOT START' }
"@ | ForEach-Object { "  $_" }

Write-Host ''
Write-Host "  https://$Domain" -ForegroundColor Green
Write-Host ''
Write-Host '  The first load can take a few seconds while the certificate is issued.'
Write-Host '  If it does not come up, the log is on the VPS:'
Write-Host "    Get-ScheduledTask 'Thornswood Web' | Get-ScheduledTaskInfo"
