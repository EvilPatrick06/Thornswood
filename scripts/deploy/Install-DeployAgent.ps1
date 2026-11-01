<#
  Install-DeployAgent.ps1

  Puts the box deploy agent on the VPS (#5180): the Windows service
  ThornswoodDeployAgent, C:\Thornswood-Agent\thornswood-agent.exe, from the
  newest signed agent-v<version> Release that .github\workflows\deploy-agent.yml
  published. After this the agent updates itself from each newer signed
  Release, so this runs once, and again only to put it back.
  docs\DEPLOY-AGENT.md says what the agent does.

      .\scripts\deploy\Install-DeployAgent.ps1            install, or move to the newest Release
      .\scripts\deploy\Install-DeployAgent.ps1 -Status    what is there, its check and its log
      .\scripts\deploy\Install-DeployAgent.ps1 -Remove    take it off again (not a gate verb)

  From a cloud thread, which has no ssh, the deploy gate runs the first two
  with main's script (scripts\vps\gate\verbs.json):

      pwsh scripts/vps/Box-Run.ps1 -Line 'Install-DeployAgent'
      pwsh scripts/vps/Box-Run.ps1 -Line 'Install-DeployAgent -Status'

  WHAT IT CHECKS BEFORE ANYTHING IS STOPPED. On the box, in Windows
  PowerShell 5.1: the Release's manifest.cat passes launcher\app\Signature.cs
  (the check every installed launcher holds an update to, #912) for the
  ExpectedSigner launcher\app\Updater.cs names, both sent from this checkout,
  so the name and the check live in one place; Test-FileCatalog says the
  catalog holds manifest.json; the manifest names this Release and the
  program's sha256 and size; and the program itself passes the same
  signature check. Any one wrong and nothing is stopped or changed.

  WHAT IT RUNS AS. LocalSystem, the account the deploy gate's broker runs as:
  the agent replaces files in the dev server's folder, takes the server
  folders' turn with the nightly backup (#3247), and mints its own short
  GitHub token from the box admin App's key, which only SYSTEM,
  Administrators and the admin service can read (Install-AdminService.ps1,
  #4076). The token it asks for carries Deployments write and Contents read
  on this repository and nothing else. Its folder takes nothing from C:\: SYSTEM
  and Administrators only.

  WHEN IT ENDS. The service manager starts it again when it ends with an error
  code (sc failure, failureflag 1): that is how a self-update starts the new
  program (it ends with 3 once the new one is in place). Not a loop on a
  failure: a program that will not start is three restarts and then stopped,
  for a day, and this script's -Status says so.

  WHAT IT CANNOT DO YET. Until the box admin App holds Deployments: Read and
  write (its permissions page, then Accept on its installation, an owner's
  step), the agent runs and every pass says GitHub gave it no token; -Status
  shows that line. Nothing is applied meanwhile.

  Keep it ASCII: Windows PowerShell 5.1 at the far end reads what is sent as
  ANSI.
#>
[CmdletBinding()]
param(
    [string]$VpsHost = '',
    [string]$VpsUser = '',
    [string]$Root    = 'C:\Thornswood-Agent',
    # owner/name of the repository whose Deployments and Releases the agent
    # reads. Left out, it is this checkout's origin, so no account is built in
    # and the move to an organization (#5184) needs no edit here.
    [string]$Repo    = '',
    # A Release to install instead of the newest, agent-v<a.b.c>.
    [string]$Tag     = '',
    [switch]$Status,
    [switch]$Remove,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$RepoDir = (Resolve-Path (Join-Path $Here '..\..')).Path
. (Join-Path $Here '..\vps\Vps.ps1')
. (Join-Path $Here '..\vps\Send-Script.ps1')
if (-not $VpsUser) { $VpsUser = Get-ThornswoodVpsUser }
if (-not $VpsHost) { $VpsHost = Get-ThornswoodVpsAddress }

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

if ($Status -and $Remove) { Die '-Status and -Remove each do one thing, so pass one of them. Nothing was sent.' }
if ($Tag -and $Tag -notmatch '^agent-v\d+\.\d+\.\d+$') { Die "-Tag $Tag is not agent-v<a.b.c>. Nothing was sent." }
if ($Root -notmatch '^[A-Za-z]:\\[A-Za-z0-9._\\-]+$') { Die "-Root $Root is not a plain folder on the box. Nothing was sent." }
if (-not $Repo) {
    # The gate's checkout reads ssh://git@ssh.github.com:443/<owner>/<name>.git
    # (Install-Gate.ps1); a port is not part of owner/name (Ship.ps1 Get-SourceRepo).
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Die 'git is not on the path, so this checkout cannot say which repository it is; pass -Repo owner/name. Nothing was sent.' }
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $remote = [string](@(& git -C $RepoDir remote get-url origin 2>$null) | Select-Object -First 1) }
    finally { $ErrorActionPreference = $old }
    if ($remote -match 'github\.com(?::\d+(?=/))?[:/](.+?)(?:\.git)?\s*$') { $Repo = $Matches[1] }
    else { Die "this checkout's origin ($remote) is not a GitHub repository; pass -Repo owner/name. Nothing was sent." }
}
if ($Repo -notmatch '^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$') { Die "-Repo $Repo is not owner/name. Nothing was sent." }

$target = "$VpsUser@$VpsHost"
$ssh = @('-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes')
function Remote($script) { return Invoke-ThornswoodRemote -Target $target -SshArgs $ssh -Script $script }

$service = 'ThornswoodDeployAgent'
$exe = $Root.TrimEnd('\') + '\thornswood-agent.exe'

# ------------------------------------------------------------------ status --
if ($Status) {
    $out = @(Remote @"
`$s = Get-Service -Name '$service' -ErrorAction SilentlyContinue
if (-not `$s) { 'NOT INSTALLED: there is no service $service'; exit 0 }
'service $service is ' + `$s.Status + ', start ' + `$s.StartType
if (Test-Path -LiteralPath '$exe') { & '$exe' version 2>&1 | ForEach-Object { "`$_" } }
'--- the agent''s own check ---'
& '$exe' check 2>&1 | ForEach-Object { "`$_" }
'--- agent.log, last 30 ---'
`$log = '$Root\logs\agent.log'
if (Test-Path -LiteralPath `$log) { Get-Content -LiteralPath `$log -Tail 30 } else { 'no log yet' }
"@)
    foreach ($l in $out) { Say ("  $l") }
    exit 0
}

# ------------------------------------------------------------------ remove --
if ($Remove) {
    $out = @(Remote @"
`$s = Get-Service -Name '$service' -ErrorAction SilentlyContinue
if (`$s) {
  if (`$s.Status -ne 'Stopped') { Stop-Service -Name '$service' -Force; `$s.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(60)) }
  & sc.exe delete '$service' | Out-Null
  'REMOVED the service $service; $Root is left with its logs'
} else { 'NOT INSTALLED' }
"@)
    foreach ($l in $out) { Say ("  $l") }
    exit 0
}

# ----------------------------------------------------------------- install --
# The signer and the check, from this checkout, sent with the script.
$updater = [IO.File]::ReadAllText((Join-Path $RepoDir 'launcher\app\Updater.cs'))
$m = [regex]::Match($updater, 'ExpectedSigner\s*=\s*"([^"]+)"')
if (-not $m.Success) { Die 'ExpectedSigner is not in launcher\app\Updater.cs. Nothing was sent.' }
$signer = $m.Groups[1].Value.Trim()
if ($signer -notmatch '^[A-Za-z0-9 .,-]+$') { Die 'ExpectedSigner holds characters this script will not send. Nothing was sent.' }
$sigCs = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $RepoDir 'launcher\app\Signature.cs')))

Say "Installing the deploy agent on $VpsHost from the newest signed Release..." Cyan
$out = @(Remote @"
`$ErrorActionPreference = 'Stop'
`$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
`$root = '$Root'
`$exe = '$exe'
`$service = '$service'
`$want = '$Tag'
`$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
`$stage = Join-Path `$root ('.stage-' + `$stamp)
`$h = @{ 'User-Agent' = 'thornswood-install-deploy-agent'; Accept = 'application/vnd.github+json' }

function Refuse([string]`$why) { 'REFUSED: ' + `$why + '. Nothing was stopped or changed.'; if (Test-Path -LiteralPath `$stage) { Remove-Item -LiteralPath `$stage -Recurse -Force }; exit 1 }

# The folder: nothing from C:\, SYSTEM and Administrators only.
if (-not (Test-Path -LiteralPath `$root)) { New-Item -ItemType Directory -Path `$root | Out-Null }
& icacls.exe `$root /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
if (`$LASTEXITCODE -ne 0) { Refuse ('icacls could not set the rules on ' + `$root) }
New-Item -ItemType Directory -Force -Path (Join-Path `$stage 'files') | Out-Null

# Which Release. Published Releases only: GitHub lists no draft to a caller
# with no token.
try { `$rels = @(Invoke-RestMethod -Uri 'https://api.github.com/repos/$Repo/releases?per_page=50' -Headers `$h) }
catch { Refuse ('GitHub would not list the Releases: ' + `$_.Exception.Message) }
`$best = `$null; `$bestV = `$null
foreach (`$r in `$rels) {
  if (`$r.draft -or `$r.tag_name -notmatch '^agent-v(\d+\.\d+\.\d+)$') { continue }
  `$v = [version]`$Matches[1]
  if (`$want -and `$r.tag_name -ne `$want) { continue }
  if (-not `$bestV -or `$v -gt `$bestV) { `$best = `$r; `$bestV = `$v }
}
if (-not `$best) { if (`$want) { Refuse ('there is no published Release ' + `$want) } else { Refuse 'there is no published agent-v Release yet: deploy-agent.yml makes one when its change reaches main' } }
'release ' + `$best.tag_name

function Fetch([string]`$name, [string]`$to) {
  `$a = @(`$best.assets | Where-Object { `$_.name -eq `$name })
  if (`$a.Count -ne 1) { Refuse ('release ' + `$best.tag_name + ' carries no ' + `$name) }
  Invoke-WebRequest -Uri `$a[0].browser_download_url -Headers @{ 'User-Agent' = 'thornswood-install-deploy-agent' } -OutFile `$to -UseBasicParsing
  if ((Get-Item -LiteralPath `$to).Length -ne `$a[0].size) { Refuse (`$name + ' did not come down whole') }
}
`$man = Join-Path `$stage 'files\manifest.json'
`$cat = Join-Path `$stage 'manifest.cat'
`$new = Join-Path `$stage 'thornswood-agent.exe'
Fetch 'manifest.json' `$man
Fetch 'manifest.cat' `$cat
Fetch 'thornswood-agent.exe' `$new

# The launcher's own check (Signature.cs), on the catalog and on the program.
`$src = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$sigCs'))
`$sha = [Security.Cryptography.SHA256]::Create()
`$hash = -join (`$sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(`$src)) | Select-Object -First 8 | ForEach-Object { `$_.ToString('x2') })
`$ns = 'ThornswoodSign' + `$hash
if (-not ((`$ns + '.Signature') -as [type])) { Add-Type -TypeDefinition ([regex]::Replace(`$src, '(?m)^namespace Thornswood\s*`$', ('namespace ' + `$ns))) -Language CSharp }
`$t = (`$ns + '.Signature') -as [type]
foreach (`$f in `$cat, `$new) {
  `$said = ''
  `$why = `$t::Refusal(`$f, '$signer', [ref]`$said)
  if (`$why) { Refuse ((Split-Path -Leaf `$f) + ' ' + `$why) }
}
`$st = [string](Test-FileCatalog -CatalogFilePath `$cat -Path (Join-Path `$stage 'files'))
if (`$st -ne 'Valid') { Refuse ('the signed catalog does not hold manifest.json (Test-FileCatalog said ' + `$st + ')') }
`$m = [IO.File]::ReadAllText(`$man) | ConvertFrom-Json
if (`$m.tag -ne `$best.tag_name -or ('agent-v' + `$m.version) -ne `$best.tag_name) { Refuse ('the signed manifest says ' + `$m.tag + ', not ' + `$best.tag_name) }
`$entry = @(`$m.parts.agent | Where-Object { `$_.name -eq 'thornswood-agent.exe' })
if (`$entry.Count -ne 1) { Refuse 'the signed manifest lists no thornswood-agent.exe' }
`$got = (Get-FileHash -LiteralPath `$new -Algorithm SHA256).Hash.ToLowerInvariant()
if (`$got -ne `$entry[0].sha256 -or (Get-Item -LiteralPath `$new).Length -ne `$entry[0].size) { Refuse 'the program is not the one the signed manifest lists' }
'signed and held to its manifest: ' + `$best.tag_name + ', sha256 ' + `$got.Substring(0, 12)

# agent.json names the repository; anything else in it is kept.
`$cfgPath = Join-Path `$root 'agent.json'
`$cfg = New-Object PSObject
if (Test-Path -LiteralPath `$cfgPath) { try { `$cfg = [IO.File]::ReadAllText(`$cfgPath) | ConvertFrom-Json } catch { Refuse (`$cfgPath + ' does not read as JSON: ' + `$_.Exception.Message) } }
`$cfg | Add-Member -NotePropertyName repo -NotePropertyValue '$Repo' -Force
`$cfg | Add-Member -NotePropertyName home -NotePropertyValue `$root -Force
[IO.File]::WriteAllText(`$cfgPath, (`$cfg | ConvertTo-Json -Depth 10))
'agent.json names $Repo'

# In place, with the one it replaces kept beside it until the new one runs.
`$svc = Get-Service -Name `$service -ErrorAction SilentlyContinue
if (`$svc -and `$svc.Status -ne 'Stopped') {
  Stop-Service -Name `$service -Force
  `$svc.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(120))
}
`$prev = `$exe + '.prev'
if (Test-Path -LiteralPath `$exe) { Move-Item -LiteralPath `$exe -Destination `$prev -Force }
Move-Item -LiteralPath `$new -Destination `$exe -Force
Remove-Item -LiteralPath `$stage -Recurse -Force

if (-not `$svc) {
  # The path has no spaces (-Root is held to that), so it needs no quotes of
  # its own, which Windows PowerShell 5.1 would not pass through whole.
  & sc.exe create `$service binPath= (`$exe + ' service') start= delayed-auto obj= LocalSystem DisplayName= 'Thornswood deploy agent' | Out-Null
  if (`$LASTEXITCODE -ne 0) { 'COULD NOT MAKE the service ' + `$service; exit 1 }
  & sc.exe description `$service 'Applies Thornswood Deployments from signed GitHub Releases (#5180). Outbound only.' | Out-Null
}
& sc.exe failure `$service reset= 86400 actions= restart/10000/restart/10000/restart/60000 | Out-Null
& sc.exe failureflag `$service 1 | Out-Null

Start-Service -Name `$service
`$svc = Get-Service -Name `$service
try { `$svc.WaitForStatus('Running', [TimeSpan]::FromSeconds(60)) } catch { }
`$svc.Refresh()
if (`$svc.Status -ne 'Running') {
  'the new agent did not start (' + `$svc.Status + ')'
  if (Test-Path -LiteralPath `$prev) {
    Stop-Service -Name `$service -Force -ErrorAction SilentlyContinue
    Move-Item -LiteralPath `$prev -Destination `$exe -Force
    Start-Service -Name `$service -ErrorAction SilentlyContinue
    'PUT BACK: the agent it replaced is in place again'
  }
  exit 1
}
Remove-Item -LiteralPath `$prev -Force -ErrorAction SilentlyContinue
& `$exe version 2>&1 | ForEach-Object { "`$_" }
'--- the agent''s own check ---'
& `$exe check 2>&1 | ForEach-Object { "`$_" }
'INSTALLED: ' + `$service + ' runs ' + `$best.tag_name
"@)
foreach ($l in $out) { Say ("  $l") }
if ($out -match '^INSTALLED: ') { Say 'The deploy agent is installed and running.' Green; exit 0 }
Die 'The deploy agent is not installed; the lines above say why.'
