<#
  Set-Turnstile.ps1

  Puts Cloudflare Turnstile's two keys for the report form into the site's
  config.json on the VPS and restarts the site, so /report draws the check
  and the site asks Cloudflare about every pass (#3216, Patrick's answer on
  22 Oct 2026). Or takes both out again with -Off.

    pwsh scripts/deploy/Set-Turnstile.ps1 -PublicSiteKey 0x4AAAAAAA...   asks for the secret, not shown
    pwsh scripts/deploy/Set-Turnstile.ps1 -Off                     no widget and no check

  The site key is public: the page hands it to every browser, so it may go on
  the command line. The secret is asked for hidden and goes to the box on
  ssh's standard input (Send-Secret.ps1, #451), never on a command line and
  never in a file. Both come from the widget in Cloudflare: the answer to the
  call that made it, or the dashboard's Turnstile page for that widget. The
  widget is made for thornswood.net in Managed mode; the page draws it with
  the action 'report', which the site checks.

  Only the two keys change in config.json, through SiteConfigSet.ps1, the
  block Deploy-Docs -Password and Rotate-ServerPassword use (#2317): every
  other setting is kept, and a file that is there and will not parse is left
  exactly as it is, with nothing written and the site not restarted. The
  site key is written first, so a run that stops between the two leaves the
  site key alone, which the site reads as off (turnstileOn() wants both).

  Afterwards it asks the restarted site what the report form is told
  (/api/report/form on the box itself) and says whether the check is on.
#>
[CmdletBinding()]
param(
  [ValidatePattern('^0x[0-9A-Za-z_-]{10,80}$')][string]$PublicSiteKey = '',
  [switch]$Off,
  [string]$Vps  = '',
  [string]$User = '',
  [string]$DocsRoot = 'C:/Thornswood-Docs'
)

$ErrorActionPreference = 'Stop'
$ssh  = @('-o','BatchMode=yes','-o','StrictHostKeyChecking=yes')
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here '..\vps\Vps.ps1')
. (Join-Path $Here '..\vps\Send-Script.ps1')
. (Join-Path $Here '..\vps\Send-Secret.ps1')
. (Join-Path $Here 'SiteConfigSet.ps1')
if (-not $User) { $User = Get-ThornswoodVpsUser }
if (-not $Vps) { $Vps = Get-ThornswoodVpsAddress }

if ($Off -and $PublicSiteKey) { throw 'Either -PublicSiteKey or -Off, not both. Nothing was sent.' }
if (-not $Off -and -not $PublicSiteKey) { throw 'Name the widget''s site key with -PublicSiteKey 0x..., or take the check out with -Off. Nothing was sent.' }

$secret = ''
if (-not $Off) {
  $secret = Read-ThornswoodSecret '  The Turnstile secret key for that widget (it is not shown)'
  if (-not $secret) { Write-Host '  nothing was typed, nothing changed'; return }
}

$docsWin = $DocsRoot.Replace('/','\')
$want = if ($Off) { 'off' } else { 'on' }

Write-Host ''
Write-Host ('Turning the report form''s Turnstile check ' + $want + '...')
Invoke-ThornswoodSecretRemote -Target "$User@$Vps" -SshArgs $ssh -Secret $secret -Script @"
`$ErrorActionPreference = 'Stop'
`$pw = `$ThornswoodSecret; `$ThornswoodSecret = `$null
`$turnstileSecret = `$pw
if ('$want' -eq 'on' -and -not `$turnstileSecret) { 'NOTHING ARRIVED on standard input. Nothing written, the check is as it was.'; return }
`$pw = '$PublicSiteKey'
$(Get-ThornswoodSiteConfigSet -ConfigPath "$docsWin\config.json" -Key 'turnstileSiteKey' -What 'turnstile keys')
`$pw = `$turnstileSecret; `$turnstileSecret = `$null
$(Get-ThornswoodSiteConfigSet -ConfigPath "$docsWin\config.json" -Key 'turnstileSecret' -What 'turnstile keys')
`$pw = `$null

Get-CimInstance Win32_Process |
  Where-Object { `$_.Name -eq 'node.exe' -and `$_.CommandLine -like '*Thornswood-Docs*' } |
  ForEach-Object { Stop-Process -Id `$_.ProcessId -Force -EA SilentlyContinue }
Start-Sleep -Seconds 1
Start-ScheduledTask -TaskName 'Thornswood Docs' -EA SilentlyContinue
Start-Sleep -Seconds 3
if (-not (Get-NetTCPConnection -LocalPort 3001 -State Listen -EA SilentlyContinue)) { 'SITE DID NOT COME BACK'; return }
'site restarted'
`$told = ''
try { `$told = [string](Invoke-RestMethod -Uri 'http://127.0.0.1:3001/api/report/form' -UseBasicParsing -TimeoutSec 15).turnstile }
catch { 'THE SITE DID NOT ANSWER /api/report/form: ' + `$_.Exception.Message; return }
if (`$told -eq '$PublicSiteKey') { if ('$want' -eq 'on') { 'the report form is told the site key: the check is on' } else { 'the report form is told no key: the check is off' } }
else { 'THE REPORT FORM IS TOLD ' + (`$(if (`$told) { 'ANOTHER KEY' } else { 'NO KEY' })) + ', so the check is not ' + '$want' }
"@ | ForEach-Object { "  $_" }
$secret = $null
