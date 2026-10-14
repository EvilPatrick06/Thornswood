<#
  test-watch-outside.ps1

      pwsh -NoProfile -File .\tests\test-watch-outside.ps1
      powershell -NoProfile -File .\tests\test-watch-outside.ps1

  scripts\vps\Watch-Outside.ps1 runs on One, outside the VPS, and tells staff
  in Discord when the site, a feed, the certificate, the address, the build
  runner, code signing or the Nexus collection breaks, once, and once more
  when it is fixed (issue #448).

  These drive the real script, dot-sourced, with the functions that touch
  the internet, the VPS or the clock (Get-Http, Get-Cert, Get-Dns,
  Get-Runners, Get-AzureToken, Send-Webhook, Send-ToVps, Get-Now) replaced by
  a table of fake answers. Nothing leaves the machine and nothing is posted.
  The cases: everything fine, a certificate near its end and then renewed,
  the site down and back, the runner offline and back, code signing with the
  wrong identity, the address moved, a feed that is not a feed, the messages
  handed to the VPS watchdog's outbox (#447's path), the VPS unreachable so
  the webhook posts them, the watchdog not installed, a webhook that fails and
  then works, no webhook at all, and this machine offline. And once, the real
  Send-ToVps with ssh replaced by a stand-in that runs the script it would
  have sent on the VPS here, against a folder standing in for the watchdog's.

  Read only apart from files under its own temp folder.
#>
[CmdletBinding()]
param([string]$ScriptPath, [string]$Temp)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
if (-not $ScriptPath) { $ScriptPath = Join-Path $Root 'scripts\vps\Watch-Outside.ps1' }
if (-not $Temp) { $Temp = [IO.Path]::GetTempPath() }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
  if ($cond) { $script:pass++; Write-Host "PASS  $what" -ForegroundColor Green }
  else       { $script:fail++; Write-Host "FAIL  $what" -ForegroundColor Red }
}

Yes 'Watch-Outside.ps1 is there' (Test-Path -LiteralPath $ScriptPath)
if (-not (Test-Path -LiteralPath $ScriptPath)) { Write-Host ''; Write-Host '0 passed, 1 failed' -ForegroundColor Red; exit 1 }

. $ScriptPath
$ErrorActionPreference = 'Stop'

# ---- the settings, read from this repository ---------------------------------
$S = Read-Settings $Root ''
Yes 'the live feed is Updater.cs''s MainFeed' ((@($S.Feeds | Where-Object { $_.Name -eq 'feed' })[0].Url) -eq 'https://thornswood.net/feed/version.json')
Yes 'the dev feed is Updater.cs''s DevFeed' ((@($S.Feeds | Where-Object { $_.Name -eq 'feed-dev' })[0].Url) -eq 'https://thornswood.net/feed-dev/version.json')
Yes 'the site is the feed''s host' ($S.Site -eq 'https://thornswood.net/' -and $S.SiteHost -eq 'thornswood.net')
Yes 'the pinned identity comes from Signature.cs' (@($S.Identities).Count -ge 1 -and @($S.Identities)[0] -match '^1\.3\.6\.1\.4\.1\.311\.97\.')
Yes 'the signing account comes from records\signing\metadata.json' ($S.SignAccount -and $S.SignProfile -and $S.SignEndpoint -match '^https://')
Yes 'the collection comes from Config.cs' ($S.NexusSlug -and $S.NexusGame)
Yes 'the VPS address comes from scripts\vps\vps.json' ($S.VpsAddress -match '^\d+\.\d+\.\d+\.\d+$')
Yes 'the certificate line is 14 days' ($S.CertDays -eq 14)
Yes 'the VPS user comes from scripts\vps\vps.json' ($S.VpsUser -eq 'Administrator')
Yes 'the watchdog''s folder is Watch-Services.ps1''s own -Root' ($S.WatchRoot -eq 'C:\Thornswood-Watch')
Yes 'the webhook''s channel is #staff-updates, bot\staff-channel.txt''s id (#2501)' ($S.StaffChannel -eq '1549254991082946570')

# Fixed values from here on, so nothing below depends on what the repository says.
$S.VpsAddress = '192.0.2.10'
$S.Identities = @('1.3.6.1.4.1.311.97.1.2.3.4')

# ---- the fakes ------------------------------------------------------------
$HookUrl = 'https://discord.com/api/webhooks/123456/SECRETHOOKTOKEN_abc'
$script:clock = [datetime]::new(2026, 10, 1, 12, 0, 0, [DateTimeKind]::Local)
$script:posted = New-Object 'System.Collections.Generic.List[string]'
$script:hookFails = $false
$script:asked = New-Object 'System.Collections.Generic.List[string]'

function Reset-World {
  $script:online = $true
  $script:site = 200
  $script:feed = 200
  $script:feedBody = '{"launcherVersion":"1.2.4","launcherUrl":"https://thornswood.net/feed/assets/abc","packs":[],"baseline":{"id":"20261012-115531"}}'
  $script:launcher = 206
  $script:certEnd = $script:clock.ToUniversalTime().AddDays(60)
  $script:certProblems = 'None'
  $script:dns = @('192.0.2.10')
  $script:rdapEnd = '2027-09-15T01:11:45Z'
  $script:runner = 'online'
  $script:runner2 = ''
  $script:token = 'eyFAKE'
  $script:sign = 200
  $script:signBody = '["1.3.6.1.4.1.311.97.1.2.3.4"]'
  $script:nexus = '{"data":{"collection":{"name":"Thornswood","latestPublishedRevision":{"revisionNumber":1}}}}'
}

function Get-Now { return $script:clock }
function Get-Http([string]$url, [string]$method = 'GET', [string]$body = '', [hashtable]$headers = @{}, [switch]$FirstByte, [int]$timeout = 20) {
  $script:asked.Add($url)
  if (-not $script:online) { return @{ Code = 0; Body = ''; Error = 'could not be reached' } }
  if ($url -eq 'https://api.github.com/' -or $url -like 'https://discord.com/api/v10/gateway') { return @{ Code = 200; Body = '{}'; Error = '' } }
  if ($url -eq 'https://thornswood.net/') { return @{ Code = $script:site; Body = ''; Error = $(if ($script:site) { '' } else { 'did not answer within 20 seconds' }) } }
  if ($url -like 'https://thornswood.net/feed*/version.json') { return @{ Code = $script:feed; Body = $script:feedBody; Error = '' } }
  if ($url -like 'https://thornswood.net/feed/assets/*') { return @{ Code = $script:launcher; Body = ''; Error = '' } }
  if ($url -like 'https://rdap.org/domain/*') { return @{ Code = 200; Body = ('{"events":[{"eventAction":"expiration","eventDate":"' + $script:rdapEnd + '"}]}'); Error = '' } }
  if ($url -like '*codesigning.azure.net/*') {
    $script:signAuth = $headers['Authorization']
    return @{ Code = $script:sign; Body = $script:signBody; Error = '' }
  }
  if ($url -eq 'https://api.nexusmods.com/v2/graphql') { $script:nexusQuery = $body; return @{ Code = 200; Body = $script:nexus; Error = '' } }
  if ($url -eq $HookUrl -and $method -eq 'GET') { return @{ Code = $script:hookCode; Body = $script:hookBody; Error = '' } }
  return @{ Code = 0; Body = ''; Error = 'not in the table' }
}
function Get-Cert([string]$hostName) { return @{ NotAfter = $script:certEnd; Problems = $script:certProblems; Error = '' } }
function Get-Dns([string]$name) { return @{ Addresses = @($script:dns); Error = $(if (@($script:dns).Count) { '' } else { 'does not resolve' }) } }
function Get-Runners([string]$repo) {
  if ($script:runner -eq 'gh-fails') { return @{ Runners = @(); Error = 'gh could not ask GitHub: HTTP 401' } }
  $list = @(@{ Name = 'thornswood-vps'; Status = $script:runner; Busy = $false })
  # A numbered runner beside it (Install-Runner.ps1 -Number), and one whose
  # name only starts the same, which is not one of them.
  if ($script:runner2) { $list += @{ Name = 'thornswood-vps-2'; Status = $script:runner2; Busy = $true }; $list += @{ Name = 'thornswood-vpsx'; Status = 'offline'; Busy = $false } }
  return @{ Runners = $list; Error = '' }
}
function Get-AzureToken { if ($script:token) { return @{ Token = $script:token; Error = '' } } else { return @{ Token = ''; Error = 'az on this machine has no Azure sign in (az account get-access-token failed)' } } }
function Send-Webhook([string]$url, [string]$text) {
  if ($script:hookFails) { return 'HTTP 500' }
  $script:posted.Add($text)
  return ''
}
# The VPS path. 'down' is ssh not reaching the box, the case the webhook is
# for, and the default, so the cases above it count what the webhook posts.
$realSendToVps = ${function:Send-ToVps}
$script:vps = 'down'
$script:handed = New-Object 'System.Collections.Generic.List[string]'
function Send-ToVps($S, [string[]]$rows) {
  if ($script:vps -eq 'down') { return 'ssh could not reach the VPS (exit 255)' }
  if ($script:vps -eq 'nowatcher') { return 'the watchdog is not installed on the VPS (no C:\Thornswood-Watch\watch.ps1)' }
  foreach ($r in $rows) { $script:handed.Add($r) }
  return ''
}
function Handed([string]$like) { return @($script:handed | Where-Object { $_ -like $like }).Count }

$dir = Join-Path $Temp ('thornswood-watchoutside-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Path $dir -Force
$P = Paths $dir
[IO.File]::WriteAllText($P.Hook, $HookUrl)

function Tick([int]$minutes = 5) { $script:clock = $script:clock.AddMinutes($minutes) }
function Pass-Once { $r = Invoke-Watch $S $P -Remember; Tick; return $r }
function Posted([string]$like) { return @($script:posted | Where-Object { $_ -like $like }).Count }
function Clear-Posted { $script:posted.Clear() }

try {
  # ---- everything fine ----------------------------------------------------
  Reset-World
  $r = Pass-Once
  Yes 'a healthy world: every check ran' ($r.Count -eq 9)
  Yes 'a healthy world: nothing is wrong' (@($r.Values | Where-Object { $_.Bad }).Count -eq 0)
  Yes 'a healthy world: nothing is posted' ($script:posted.Count -eq 0)
  Yes 'signing was asked with the Azure token as a bearer' ($script:signAuth -eq 'Bearer eyFAKE')
  Yes 'Nexus was asked for the collection from Config.cs' ($script:nexusQuery -match $S.NexusSlug)

  # ---- the hourly and daily ones are not asked every run -------------------
  $script:asked.Clear()
  $null = Pass-Once
  Yes 'the domain is not asked again five minutes later' (@($script:asked | Where-Object { $_ -like 'https://rdap.org/*' }).Count -eq 0)
  Yes 'Nexus is not asked again five minutes later' (@($script:asked | Where-Object { $_ -like '*nexusmods*' }).Count -eq 0)
  Yes 'the site is asked again' (@($script:asked | Where-Object { $_ -eq 'https://thornswood.net/' }).Count -eq 1)

  # ---- certificate near its end, then renewed ------------------------------
  Reset-World
  Tick 60
  $script:certEnd = $script:clock.ToUniversalTime().AddDays(10)
  $null = Pass-Once
  Yes 'certificate at 10 days: one message at once' ((Posted '*certificate for thornswood.net needs a look*') -eq 1)
  Yes 'it says when it runs out and how many days' ((Posted '*in 10 days*') -eq 1)
  Yes 'it says what to do' ((Posted '*Caddy*') -eq 1)
  Tick 60; $null = Pass-Once
  Tick 60; $null = Pass-Once
  Yes 'still near its end an hour and two hours later: no second message' ((Posted '*certificate for thornswood.net*') -eq 1)
  $script:certEnd = $script:clock.ToUniversalTime().AddDays(89)
  Tick 60; $null = Pass-Once
  Yes 'renewed: one message saying it is fine again' ((Posted '*certificate for thornswood.net is fine again*') -eq 1)
  Tick 60; $null = Pass-Once
  Yes 'and no more after that' ((Posted '*certificate for thornswood.net*') -eq 2)
  Clear-Posted

  # Out of date entirely, and a certificate Windows will not accept.
  $script:certEnd = $script:clock.ToUniversalTime().AddDays(-1)
  Yes 'a certificate that ran out is wrong' ((Check-Cert $S).Bad -and (Check-Cert $S).Why -match 'ran out')
  $script:certEnd = $script:clock.ToUniversalTime().AddDays(60); $script:certProblems = 'RemoteCertificateNameMismatch'
  Yes 'a certificate Windows does not accept is wrong' ((Check-Cert $S).Bad -and (Check-Cert $S).Why -match 'NameMismatch')
  $script:certEnd = $script:clock.ToUniversalTime().AddDays(15); $script:certProblems = 'None'
  Yes 'a certificate at 15 days is fine' (-not (Check-Cert $S).Bad)

  # ---- site down, then back -------------------------------------------------
  Reset-World
  $script:site = 0
  $null = Pass-Once
  Yes 'site down on one run: nothing yet, one slow answer is not an outage' ((Posted '*thornswood.net, asked from outside the VPS, is down*') -eq 0)
  $null = Pass-Once
  Yes 'site down on two runs: one message' ((Posted '*thornswood.net, asked from outside the VPS, is down*') -eq 1)
  $down = @($script:posted | Where-Object { $_ -like '*is down*' })[0]
  Yes 'the message starts bold with what is wrong' ($down -like '`*`*https://thornswood.net, asked from outside the VPS, is down.`*`* *')
  Yes 'the message says why, in words' ($down -match 'did not answer within 20 seconds')
  Yes 'an address at the start of the reason keeps its small letters' ($down -cmatch '\*\* https://thornswood\.net/ did not')
  Yes 'the message says when, in each reader''s own clock' ($down -match '<t:\d+:f>')
  Yes 'the message says it was checked from outside the VPS' ($down -match 'Checked from One, outside the VPS, every 5 minutes')
  $null = Pass-Once; $null = Pass-Once; $null = Pass-Once
  Yes 'still down three runs later: still one message' ((Posted '*is down*') -eq 1)
  $script:site = 200
  $null = Pass-Once
  Yes 'answering once: not back yet, a flap stays one outage' ((Posted '*is back*') -eq 0)
  $script:site = 0
  $null = Pass-Once
  $script:site = 200
  $null = Pass-Once; $null = Pass-Once
  Yes 'down again in between: still one down message' ((Posted '*is down*') -eq 1)
  Yes 'answering on two runs in a row: one back message' ((Posted '*thornswood.net, asked from outside the VPS, is back*') -eq 1)
  $back = @($script:posted | Where-Object { $_ -like '*is back*' })[0]
  Yes 'the back message says how long it was down' ($back -match 'after about \d+ minutes')
  $null = Pass-Once
  Yes 'nothing more once it is back' ($script:posted.Count -eq 2)
  Clear-Posted

  # ---- runner offline, then back --------------------------------------------
  Reset-World
  $script:runner = 'offline'
  $null = Pass-Once; $null = Pass-Once
  Yes 'runner offline for two runs: nothing yet, it restarts itself on updates' ((Posted '*build runner*') -eq 0)
  $null = Pass-Once
  Yes 'runner offline for three runs: one message' ((Posted '*build runners, thornswood-vps and the numbered ones, are not all online on GitHub*') -eq 1)
  Yes 'it says what that stops' ((Posted '*Launcher builds*') -eq 1)
  $null = Pass-Once
  $script:runner = 'online'
  $null = Pass-Once; $null = Pass-Once
  Yes 'runner online two runs in a row: one message saying so' ((Posted '*build runners, thornswood-vps and the numbered ones, are all online again*') -eq 1)
  Yes 'two messages in all for the runner' ((Posted '*build runner*') -eq 2)
  Clear-Posted

  # ---- a numbered runner offline while the first is online (4 October) ------
  Reset-World
  $script:runner2 = 'online'
  Yes 'two runners online: both counted, and one that only starts with the name is not' ((Check-Runner $S).Line -eq 'all 2 online, 1 running a job' -and -not (Check-Runner $S).Bad)
  $script:runner2 = 'offline'
  Yes 'the second offline is wrong too, and named' ((Check-Runner $S).Bad -and (Check-Runner $S).Why -eq 'GitHub shows thornswood-vps-2 offline, of 2')
  $null = Pass-Once; $null = Pass-Once; $null = Pass-Once
  Yes '  told once, after three runs, naming it' ((Posted '*are not all online on GitHub*thornswood-vps-2 offline*') -eq 1)
  $script:runner2 = 'online'
  $null = Pass-Once; $null = Pass-Once
  Yes '  and back once' ((Posted '*are all online again*') -eq 1)
  Clear-Posted
  Reset-World
  $script:runner = 'gh-fails'
  Yes 'GitHub not answering gh is told as One''s side' ((Check-Runner $S).Bad -and (Check-Runner $S).Why -match 'One could not ask GitHub')
  Reset-World

  # ---- code signing ---------------------------------------------------------
  $script:signBody = '["1.3.6.1.4.1.311.97.9.9.9"]'
  Yes 'signing with another identity is wrong' ((Check-Signing $S).Bad -and (Check-Signing $S).Why -match 'identity the launcher pins')
  $script:signBody = '["1.3.6.1.4.1.311.97.1.2.3.4"]'; $script:sign = 403
  Yes 'signing refusing the sign in is wrong' ((Check-Signing $S).Why -match 'HTTP 403')
  $script:sign = 404
  Yes 'signing without the account is wrong' ((Check-Signing $S).Why -match 'not there')
  $script:sign = 200; $script:token = ''
  Yes 'no az sign in on One is wrong and says az login' ((Check-Signing $S).Why -match 'az login')
  Reset-World
  Yes 'signing with the pinned identity is fine' (-not (Check-Signing $S).Bad)

  # ---- the address, the feed, the domain, Nexus ------------------------------
  $script:dns = @('203.0.113.5')
  Yes 'the name pointing elsewhere is wrong' ((Check-Dns $S).Bad -and (Check-Dns $S).Why -match '203\.0\.113\.5')
  $script:dns = @('192.0.2.10', '203.0.113.5')
  Yes 'the name pointing at the VPS and somewhere else is wrong' ((Check-Dns $S).Bad)
  $script:dns = @()
  Yes 'the name not resolving is wrong' ((Check-Dns $S).Bad)
  Reset-World
  $feedDef = @($S.Feeds)[0]
  $script:feedBody = '<html>not a feed</html>'
  Yes 'a feed that is not a feed is wrong' ((Check-Feed $S $feedDef).Bad -and (Check-Feed $S $feedDef).Why -match 'not with a feed')
  Reset-World
  Yes 'a feed with no packs but a release record is right (#1050: feeds carry no packs)' (-not (Check-Feed $S $feedDef).Bad -and (Check-Feed $S $feedDef).Line -match 'release 20261012-115531')
  $script:feedBody = '{"launcherVersion":"1.2.4","launcherUrl":"https://thornswood.net/feed/assets/abc","packs":[]}'
  Yes 'a feed with no release record is wrong' ((Check-Feed $S $feedDef).Bad -and (Check-Feed $S $feedDef).Why -match 'no release record')
  $script:feedBody = '{"launcherVersion":"1.2.4","packs":[],"baseline":{"id":"20261012-115531"}}'
  Yes 'a feed with no launcherUrl is wrong' ((Check-Feed $S $feedDef).Bad -and (Check-Feed $S $feedDef).Why -match 'no launcherUrl')
  Reset-World; $script:feed = 502
  Yes 'a feed answering 502 is wrong' ((Check-Feed $S $feedDef).Why -match 'HTTP 502')
  Reset-World; $script:launcher = 404
  Yes 'a feed whose launcher does not download is wrong' ((Check-Feed $S $feedDef).Why -match 'launcher it names')
  Reset-World; $script:rdapEnd = $script:clock.ToUniversalTime().AddDays(20).ToString('o')
  Yes 'a domain with 20 days left is wrong' ((Check-Domain $S).Bad)
  Reset-World; $script:nexus = '{"data":{"collection":null}}'
  Yes 'a collection Nexus no longer has is wrong' ((Check-Nexus $S).Bad)
  Reset-World

  # ---- a webhook that fails, then works ---------------------------------------
  Clear-Posted
  $script:hookFails = $true
  $script:dns = @('203.0.113.5')
  $null = Pass-Once; $null = Pass-Once
  Yes 'webhook failing: the message waits in the outbox' ((Get-Content -LiteralPath $P.Alerts -Raw) -match 'does not point at the VPS')
  Yes 'and nothing was counted as posted' (-not (Test-Path -LiteralPath $P.Sent) -or -not ((Get-Content -LiteralPath $P.Sent -Raw) -match '-dns-down'))
  $log = Get-Content -LiteralPath $P.Log -Raw
  Yes 'watch.log says it could not post, once' (([regex]::Matches($log, 'could not post outside-\d+-dns-down')).Count -eq 1)
  $script:hookFails = $false
  $null = Pass-Once
  Yes 'webhook working again: the waiting message is posted' ((Posted '*does not point at the VPS*') -eq 1)
  $null = Pass-Once
  Yes 'and only once' ((Posted '*does not point at the VPS*') -eq 1)
  Reset-World
  $null = Pass-Once; $null = Pass-Once
  Clear-Posted

  # Every row in the outbox has the VPS outbox's shape.
  $rows = @(Get-Content -LiteralPath $P.Alerts | ForEach-Object { ConvertFrom-Json $_ })
  $shape = @($rows | Where-Object { $_.id -like 'outside-*' -and $_.at -gt 0 -and $_.service -like 'outside *' -and @('down', 'back') -contains $_.kind -and $_.text })
  Yes ('every outbox row has id, at, service, kind and text, ' + $rows.Count + ' rows') ($rows.Count -gt 0 -and $shape.Count -eq $rows.Count)

  # ---- no webhook at all ----------------------------------------------------------
  Remove-Item -LiteralPath $P.Hook -Force
  $script:site = 0
  $null = Pass-Once; $null = Pass-Once
  Yes 'no webhook: nothing is posted' ($script:posted.Count -eq 0)
  Yes 'no webhook: watch.log says where to set one' ((Get-Content -LiteralPath $P.Log -Raw) -match 'no webhook in .*-SetWebhook')
  [IO.File]::WriteAllText($P.Hook, $HookUrl)
  $null = Pass-Once
  Yes 'webhook set later: the waiting message goes out' ((Posted '*is down*') -eq 1)
  Reset-World; $null = Pass-Once; $null = Pass-Once
  Clear-Posted

  # ---- this machine offline ----------------------------------------------------------
  $before = Get-Content -LiteralPath $P.Outages -Raw
  $rowsBefore = @(Get-Content -LiteralPath $P.Alerts).Count
  $script:online = $false
  $r = Pass-Once; $null = Pass-Once; $null = Pass-Once
  Yes 'One offline: the pass says so' ($null -eq $r)
  Yes 'One offline: nothing is told, however long' ($script:posted.Count -eq 0 -and @(Get-Content -LiteralPath $P.Alerts).Count -eq $rowsBefore)
  Yes 'One offline: what is down is left as it was' ((Get-Content -LiteralPath $P.Outages -Raw) -eq $before)
  Yes 'One offline: watch.log says this machine is offline' ((Get-Content -LiteralPath $P.Log -Raw) -match 'this machine is offline')
  Reset-World

  # ---- looking without -Remember ---------------------------------------------------------
  $look = Join-Path $dir 'look'
  $PL = Paths $look
  $script:site = 0
  $r = Invoke-Watch $S $PL
  Yes 'a look without -Remember sees the site down' ($r['site'].Bad)
  Yes 'a look without -Remember writes nothing and posts nothing' (-not (Test-Path -LiteralPath $look) -and $script:posted.Count -eq 0)
  Reset-World

  # ---- #447's path: the VPS watchdog's outbox -------------------------------------------
  Clear-Posted
  $script:vps = 'up'
  $script:site = 0
  $null = Pass-Once; $null = Pass-Once
  Yes 'VPS reachable: the down message is handed to the watchdog''s outbox' ((Handed '*asked from outside the VPS, is down*') -eq 1)
  Yes 'VPS reachable: nothing goes through the webhook from here' ($script:posted.Count -eq 0)
  $row = $null
  if ($script:handed.Count) { $row = ConvertFrom-Json @($script:handed)[0] }
  Yes 'what is handed is the VPS outbox''s shape: id, at, service, kind, text' ($row -and $row.id -like 'outside-*-site-down' -and $row.at -gt 0 -and $row.service -eq 'outside site' -and $row.kind -eq 'down' -and $row.text -like '`*`**')
  Yes 'its id is kept in alerts-sent-vps.txt' ((Get-Content -LiteralPath $P.SentVps -Raw) -match 'outside-\d+-site-down')
  $null = Pass-Once; $null = Pass-Once
  Yes 'handed once, never again' ((Handed '*is down*') -eq 1)
  $script:site = 200
  $null = Pass-Once; $null = Pass-Once
  Yes 'the back message takes the same path' ((Handed '*asked from outside the VPS, is back*') -eq 1 -and $script:posted.Count -eq 0)
  Yes 'watch.log says what was handed to the VPS' ((Get-Content -LiteralPath $P.Log -Raw) -match 'handed 1 message\(s\) to the watchdog''s outbox on the VPS')

  # The box gone: the webhook from here, the case this exists for.
  $script:handed.Clear()
  $script:vps = 'down'
  $script:site = 0
  $null = Pass-Once; $null = Pass-Once
  Yes 'VPS unreachable: the down message is posted through the webhook from One' ((Posted '*is down*') -eq 1 -and $script:handed.Count -eq 0)
  Yes 'watch.log says why it went that way' ((Get-Content -LiteralPath $P.Log -Raw) -match 'the VPS did not take 1 message\(s\): ssh could not reach the VPS')
  # The box back before the site is: the back message goes the usual way, and the down message is not said again.
  $script:vps = 'up'
  $script:site = 200
  $null = Pass-Once; $null = Pass-Once
  Yes 'VPS back: the back message is handed to it' ((Handed '*is back*') -eq 1)
  Yes 'VPS back: the down message the webhook already said is not handed again' ((Handed '*is down*') -eq 0 -and (Posted '*is down*') -eq 1)
  Clear-Posted; $script:handed.Clear()

  # The watchdog not installed on the box: the webhook from here too.
  $script:vps = 'nowatcher'
  $script:site = 0
  $null = Pass-Once; $null = Pass-Once
  Yes 'watchdog not installed: posted through the webhook from One' ((Posted '*is down*') -eq 1)
  Yes 'watch.log names what is missing on the VPS' ((Get-Content -LiteralPath $P.Log -Raw) -match 'watchdog is not installed on the VPS')
  # Neither path: it waits, and the VPS takes it when it can.
  $script:vps = 'down'; $script:hookFails = $true
  $script:site = 200; $null = Pass-Once; $null = Pass-Once
  Yes 'neither path: the back message waits' ((Posted '*is back*') -eq 0 -and $script:handed.Count -eq 0)
  $script:vps = 'up'; $script:hookFails = $false
  $null = Pass-Once
  Yes 'the VPS reachable again: the waiting message is handed, once' ((Handed '*is back*') -eq 1)
  $null = Pass-Once
  Yes 'and not again' ((Handed '*is back*') -eq 1 -and (Posted '*is back*') -eq 0)
  Clear-Posted; $script:handed.Clear()
  $script:vps = 'down'
  Reset-World

  # The real Send-ToVps, with ssh replaced by a stand-in that runs the script
  # it would have sent to the VPS here, reading the same standard input,
  # against a folder standing in for the watchdog's.
  $box = Join-Path $dir 'vps'
  $null = New-Item -ItemType Directory -Path $box -Force
  $script:sshArgs = @()
  function ssh {
    $script:sshArgs = @($args)
    $cmd = '' + $args[$args.Count - 1]
    $enc = $cmd.Substring($cmd.LastIndexOf(' ') + 1)
    $input | powershell -NoProfile -NonInteractive -EncodedCommand $enc
  }
  $S2 = @{}; foreach ($k in $S.Keys) { $S2[$k] = $S[$k] }
  $S2.WatchRoot = $box
  $rows = @('{"id":"outside-1-site-down","at":1790000000,"service":"outside site","kind":"down","text":"**Down.** Why. <t:1790000000:f>"}',
            '{"id":"outside-2-site-back","at":1790000300,"service":"outside site","kind":"back","text":"**Back.** Fine since then."}')
  $w = & $realSendToVps $S2 $rows
  Yes 'the real Send-ToVps with no watchdog there says so' ($w -match 'watchdog is not installed')
  Set-Content -LiteralPath (Join-Path $box 'watch.ps1') -Value '# stands in for the watchdog'
  [IO.File]::WriteAllText((Join-Path $box 'alerts.jsonl'), '{"id":"20261001-caddy-down","at":1,"service":"caddy","kind":"down","text":"x"}' + "`r`n")
  $w = & $realSendToVps $S2 $rows
  Yes 'the real Send-ToVps: the VPS says it took both' ($w -eq '')
  $got = @(Get-Content -LiteralPath (Join-Path $box 'alerts.jsonl'))
  Yes 'both lines are appended after the watchdog''s own, exactly as sent' ($got.Count -eq 3 -and $got[1] -eq $rows[0] -and $got[2] -eq $rows[1])
  Yes 'each ends with a line ending, so the bot does not wait for more of it' ([IO.File]::ReadAllText((Join-Path $box 'alerts.jsonl')).EndsWith("`r`n"))
  Yes 'ssh is asked without a prompt, as the VPS user' ($script:sshArgs -contains 'BatchMode=yes' -and $script:sshArgs -contains ('Administrator@' + $S.VpsAddress))
  Yes 'the message text is not on the command line, only on standard input' (-not ((@($script:sshArgs) -join ' ') -match 'Down|Fine since'))
  Remove-Item function:ssh

  # ---- where the webhook posts (#2501) ----------------------------------------------------
  # Asked of Discord by a GET on the webhook itself, which answers with its
  # channel_id. -SetWebhook refuses any channel but #staff-updates and -Status
  # says which it is; both go through Webhook-Channel.
  $script:hookCode = 200; $script:hookBody = '{"id":"123456","channel_id":"1549254991082946570","name":"Watchdog"}'
  $wc = Webhook-Channel $HookUrl
  Yes 'Webhook-Channel: a webhook in #staff-updates says so' ($wc.Channel -eq '1549254991082946570' -and -not $wc.Why)
  $script:hookBody = '{"id":"123456","channel_id":"1550176792726343700","name":"Watchdog"}'
  $wc = Webhook-Channel $HookUrl
  Yes 'Webhook-Channel: one in the dev updates channel names that channel, not #staff-updates' ($wc.Channel -eq '1550176792726343700' -and $wc.Channel -ne $S.StaffChannel)
  $script:hookCode = 404; $script:hookBody = '{"message":"Unknown Webhook"}'
  $wc = Webhook-Channel $HookUrl
  Yes 'Webhook-Channel: a deleted webhook is no channel, and says why' (-not $wc.Channel -and $wc.Why -match '404')
  Yes 'Webhook-Channel: neither answer holds the address' ((('' + $wc.Why) -notmatch 'SECRETHOOKTOKEN') -and (('' + $wc.Why) -notmatch 'api/webhooks'))

  # ---- words and secrets ----------------------------------------------------------------
  $all = (Get-Content -LiteralPath $P.Alerts -Raw) + (Get-Content -LiteralPath $P.Log -Raw)
  Yes 'the webhook address is in neither the outbox nor watch.log' ($all -notmatch 'SECRETHOOKTOKEN' -and $all -notmatch 'api/webhooks')
  Yes 'the Azure token is in neither' ($all -notmatch 'eyFAKE')
  $words = (Get-Content -LiteralPath $ScriptPath -Raw) + $all
  Yes 'no em dash in the script or anything it wrote' ($words.IndexOf([char]0x2014) -lt 0)
  Yes 'never the word player' ($words -notmatch '(?i)\bplayers?\b')
}
finally {
  Remove-Item -LiteralPath $dir -Recurse -Force -EA SilentlyContinue
}

Write-Host ''
$c = 'Green'; if ($script:fail) { $c = 'Red' }
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail) -ForegroundColor $c
if ($script:fail) { exit 1 }
exit 0
