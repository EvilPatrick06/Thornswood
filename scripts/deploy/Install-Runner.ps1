<#
  Install-Runner.ps1

  Puts a GitHub Actions runner on the VPS, so the build check runs on every
  pull request without paying for minutes. Run it from this machine; it
  does the remote half over ssh, the same way Install-Backup.ps1 does.

      .\scripts\deploy\Install-Runner.ps1            install it, or put it right
      .\scripts\deploy\Install-Runner.ps1 -Status    what is there and whether GitHub sees it
      .\scripts\deploy\Install-Runner.ps1 -Remove    take it off the box and off GitHub

  WHY. Every run of .github\workflows\build.yml has failed in seconds since
  02:10 on 25 September, because GitHub's own runners are blocked on billing.
  Decided by Patrick on 25 September (issue #437): a runner on the VPS rather
  than paying for minutes. build.yml asks for [self-hosted, Windows,
  thornswood-vps], which is this runner and nothing else.

  WHAT IT DOES ON THE BOX, in order:
    1. Checks what the build check needs is there: pwsh, node, python and git
       on the machine PATH, the .NET Framework csc, and WPF in Windows
       PowerShell. It installs none of them; it names the script that does.
    2. Makes a local account, thornswood-runner, that is in no group but
       Users. Its password is made on the box, handed to the service once and
       never printed, stored or sent anywhere.
    3. Denies that account every C:\Thornswood-* folder but its own, so a job
       cannot read the site's config, the bot's token or the backups, and
       cannot write into anything live.
    4. Downloads the runner release GitHub calls latest, checked against the
       SHA-256 GitHub publishes in that release's notes, and registers it as a
       service that runs as that account.
    5. Registers a task that keeps the runner at normal priority, never
       above it, so a build shares the five cores with the game server, the
       site, voice and the bot rather than taking them. Below normal until
       25 September, when Patrick wanted a check in about five minutes.
    6. Tells Windows Defender to skip the runner's own folder, so the few
       hundred processes a check starts are not each scanned on the way in.

  It needs gh on this machine, signed in as somebody who can administer the
  repository (Patrick): the registration token comes from
  gh api -X POST repos/<repo>/actions/runners/registration-token. The token
  lasts an hour and is never printed.

  Safe to run again. An existing runner is replaced, the account keeps its
  name and gets a new password, and the folder denials are made again.
#>
[CmdletBinding()]
param(
  [string]$VpsHost    = '',
  [string]$VpsUser    = 'Administrator',
  [string]$Repo       = 'EvilPatrick06/Thornswood',
  [string]$Root       = 'C:\Thornswood-Runner',
  [string]$Account    = 'thornswood-runner',
  [string]$RunnerName = 'thornswood-vps',
  # The label build.yml asks for. Change the two together.
  [string]$Label      = 'thornswood-vps',
  [string]$TaskName   = 'Thornswood Runner Priority',
  [switch]$Status,
  [switch]$Remove,
  [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here '..\vps\Vps.ps1')
if (-not $VpsHost) { $VpsHost = Get-ThornswoodVpsAddress }

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }
function Done() { Write-Host ''; if (-not $NoPause) { [void](Read-Host 'Enter to close') }; exit 0 }

$target = "$VpsUser@$VpsHost"
$ssh = @('-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=accept-new')
foreach ($t in 'ssh', 'scp', 'gh') {
  if (-not (Get-Command $t -ErrorAction SilentlyContinue)) {
    if ($t -ne 'gh') { Die "$t is not on PATH. Windows ships it: Settings, Apps, Optional features, OpenSSH Client." }
    Die 'gh is not on PATH. Install GitHub CLI from https://cli.github.com and run gh auth login.'
  }
}

# Short scripts go on the command line; the install is longer than cmd.exe's
# 8,191 characters once encoded, so it goes as a file and is deleted after,
# the same way Setup-Domain.ps1 does it. The file carries the registration
# token for the few seconds it exists; the account's password is never in it.
function Remote($script) {
  $e = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
  $cmd = "powershell -NoProfile -EncodedCommand $e"
  if ($cmd.Length -le 6000) {
    return & ssh @ssh $target $cmd 2>&1
  }
  $far = 'C:/Windows/Temp/thornswood-runner-install.ps1'
  $tmp = [IO.Path]::GetTempFileName()
  try {
    Set-Content -LiteralPath $tmp -Value $script -Encoding UTF8
    & scp @ssh $tmp "${target}:$far" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "could not send a script to $VpsHost" }
    & ssh @ssh $target "powershell -NoProfile -ExecutionPolicy Bypass -File $far" 2>&1
    & ssh @ssh $target "powershell -NoProfile -Command Remove-Item -LiteralPath '$far' -Force" 2>&1 | Out-Null
  }
  finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
}
# gh with its output kept apart from its errors, and a failure that says which
# call it was. Named so it never shadows gh itself.
function Invoke-Gh {
  $out = & gh @args 2>$null
  if ($LASTEXITCODE -ne 0) { throw ('gh ' + ($args -join ' ') + ' failed') }
  return $out
}

$service = 'actions.runner.' + $Repo.Replace('/', '-') + '.' + $RunnerName

# ------------------------------------------------------------------ status --
if ($Status) {
  Head 'On the VPS'
  Remote @"
`$ErrorActionPreference = 'SilentlyContinue'
if (Test-Path '$Root\config.cmd') { 'runner    in $Root' } else { 'runner    NOT THERE' }
`$s = Get-Service -Name '$service'
if (`$s) { 'service   ' + `$s.Status + ', starts ' + `$s.StartType } else { 'service   NOT REGISTERED' }
`$w = Get-CimInstance Win32_Service -Filter "Name='$service'"
if (`$w) { 'runs as   ' + `$w.StartName }
foreach (`$p in (Get-Process Runner.Listener, Runner.Worker)) { 'process   ' + `$p.ProcessName + ' at ' + `$p.PriorityClass }
if (Get-LocalUser -Name '$Account') { 'account   $Account' } else { 'account   NOT THERE' }
if (Get-ScheduledTask -TaskName '$TaskName') { 'priority  task registered' } else { 'priority  task NOT REGISTERED' }
"@ | ForEach-Object { Say "  $_" }
  Head 'On GitHub'
  try {
    $r = (Invoke-Gh api "repos/$Repo/actions/runners" | Out-String) | ConvertFrom-Json
    $mine = @($r.runners | Where-Object { $_.name -eq $RunnerName })
    if ($mine.Count) { foreach ($m in $mine) { Say ('  ' + $m.name + ', ' + $m.status + $(if ($m.busy) { ', running a job' } else { '' }) + ', labels ' + (($m.labels | ForEach-Object { $_.name }) -join ', ')) } }
    else { Say "  no runner called $RunnerName is registered" 'Yellow' }
  }
  catch { Say ('  could not ask GitHub: ' + $_.Exception.Message) 'Yellow' }
  Done
}

# ------------------------------------------------------------------ remove --
if ($Remove) {
  Head 'Removing the runner'
  $tok = $null
  try { $tok = (Invoke-Gh api -X POST "repos/$Repo/actions/runners/remove-token" --jq .token | Out-String).Trim() } catch { Say '  could not get a removal token; the box is cleaned and GitHub is left to forget it' 'Yellow' }
  Remote @"
`$ErrorActionPreference = 'Continue'
if ((Test-Path '$Root\config.cmd') -and '$tok') {
  Push-Location '$Root'
  & .\config.cmd remove --token '$tok' 2>&1 | Select-Object -Last 3
  Pop-Location
}
Stop-Service -Name '$service' -Force -EA SilentlyContinue
& sc.exe delete '$service' 2>&1 | Out-Null
Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false -EA SilentlyContinue
foreach (`$d in (Get-ChildItem 'C:\' -Directory -Filter 'Thornswood-*' -EA SilentlyContinue)) {
  & icacls.exe `$d.FullName /remove:d '$Account' /T /C /Q 2>&1 | Out-Null
}
Remove-LocalUser -Name '$Account' -EA SilentlyContinue
Remove-Item -LiteralPath '$Root' -Recurse -Force -EA SilentlyContinue
if (Test-Path '$Root') { 'the folder is still there, something holds a file in it' } else { 'runner, account, task and folder removed' }
"@ | ForEach-Object { Say "  $_" }
  Done
}

# ----------------------------------------------------------------- install --
Head 'The runner release'
$rel = (Invoke-Gh api repos/actions/runner/releases/latest | Out-String) | ConvertFrom-Json
$version = ([string]$rel.tag_name).TrimStart('v')
if ($version -notmatch '^\d+\.\d+\.\d+$') { Die "GitHub's latest actions/runner release has a tag this does not understand: $($rel.tag_name)" }
$m = [regex]::Match([string]$rel.body, '<!--\s*BEGIN SHA win-x64\s*-->\s*([0-9a-fA-F]{64})\s*<!--\s*END SHA win-x64\s*-->')
if (-not $m.Success) { Die "The notes of actions/runner $version carry no SHA-256 for win-x64, so there is nothing to check the download against. Nothing was sent." }
$sha = $m.Groups[1].Value.ToUpperInvariant()
$zipName = "actions-runner-win-x64-$version.zip"
$zipUrl = "https://github.com/actions/runner/releases/download/v$version/$zipName"
Say "  actions/runner $version, SHA-256 $sha" 'Green'

Head 'What the build check needs, on the VPS'
$need = Remote @"
`$env:PATH = [Environment]::GetEnvironmentVariable('PATH','Machine')
foreach (`$c in 'pwsh','node','python','git') {
  `$g = Get-Command `$c -EA SilentlyContinue
  if (`$g) { 'HAVE ' + `$c + ' ' + `$g.Source } else { 'MISSING ' + `$c }
}
`$csc = Join-Path `$env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (Test-Path `$csc) { 'HAVE csc ' + `$csc } else { 'MISSING csc' }
try { Add-Type -AssemblyName PresentationFramework; 'HAVE wpf' } catch { 'MISSING wpf' }
"@
$need | ForEach-Object { Say "  $_" }
$missing = @($need | Where-Object { "$_" -like 'MISSING *' } | ForEach-Object { "$_".Substring(8) })
if ($missing.Count) {
  $how = @()
  if ($missing -contains 'pwsh' -or $missing -contains 'node' -or $missing -contains 'git') { $how += ".\scripts\vps\Remote.ps1 -File .\scripts\vps\Bootstrap-VPS.ps1 -Arguments '-IncludeGit'   (PowerShell 7, Node, Git, for all users; from this machine, it runs on the VPS)" }
  if ($missing -contains 'python') { $how += '.\scripts\deploy\Install-Bot.ps1   (Python for all users; the bot needs it anyway)' }
  if ($missing -contains 'csc' -or $missing -contains 'wpf') { $how += 'the box needs Windows Server with the Desktop Experience and .NET Framework 4.8; that is not a script' }
  Die ("The VPS is missing " + ($missing -join ', ') + ". Nothing was installed. Put them there with:" + [Environment]::NewLine + '    ' + ($how -join ([Environment]::NewLine + '    ')))
}

Head 'Registration token'
$token = (Invoke-Gh api -X POST "repos/$Repo/actions/runners/registration-token" --jq .token | Out-String).Trim()
if (-not $token) { Die "GitHub gave no registration token. gh has to be signed in as somebody who administers $Repo." }
Say '  got one, good for an hour, not shown' 'Green'

Head 'Installing it on the VPS'
$out = Remote @"
`$ErrorActionPreference = 'Stop'
`$root = '$Root'
`$acct = '$Account'

# The account. In Users and nothing else. A password nobody ever sees: made
# here, set, handed to config.cmd for the service, and dropped. Letters and
# digits only: config.cmd is a batch file, and cmd.exe reads & | % ^ < > in
# its arguments as its own, and the .NET generator used before put them in
# (25 Sep). Upper, lower and digit each at least once, which the box's
# password rule wants.
`$rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
function Pick([string]`$from, [int]`$n) {
  `$bytes = New-Object byte[] `$n
  `$rng.GetBytes(`$bytes)
  -join (`$bytes | ForEach-Object { `$from[`$_ % `$from.Length] })
}
`$up = 'ABCDEFGHJKLMNPQRSTUVWXYZ'; `$lo = 'abcdefghijkmnopqrstuvwxyz'; `$dg = '23456789'
`$pw = (Pick `$up 1) + (Pick `$lo 1) + (Pick `$dg 1) + (Pick (`$up + `$lo + `$dg) 37)
`$sec = ConvertTo-SecureString `$pw -AsPlainText -Force
# The description is at most 48 characters; New-LocalUser refuses a longer
# one, which stopped the first install on 25 Sep.
if (Get-LocalUser -Name `$acct -EA SilentlyContinue) {
  Set-LocalUser -Name `$acct -Password `$sec -PasswordNeverExpires `$true
  'account ' + `$acct + ' was there, new password set'
} else {
  New-LocalUser -Name `$acct -Password `$sec -PasswordNeverExpires -UserMayNotChangePassword -Description 'Thornswood build check runner' | Out-Null
  Add-LocalGroupMember -Group 'Users' -Member `$acct -EA SilentlyContinue
  'account ' + `$acct + ' made'
}

# Every live Thornswood folder is closed to it: read and write both.
foreach (`$d in (Get-ChildItem 'C:\' -Directory -Filter 'Thornswood-*' -EA SilentlyContinue)) {
  if (`$d.FullName -eq `$root) { continue }
  & icacls.exe `$d.FullName /deny (`$acct + ':(OI)(CI)F') /C /Q 2>&1 | Out-Null
  'closed to it: ' + `$d.FullName
}

# A runner already here is taken off first, so a second run replaces it.
`$svc = '$service'
if (Get-Service -Name `$svc -EA SilentlyContinue) {
  Stop-Service -Name `$svc -Force -EA SilentlyContinue
  & sc.exe delete `$svc 2>&1 | Out-Null
  'the service that was there is removed'
}
if (Test-Path (Join-Path `$root '.runner')) {
  Remove-Item -LiteralPath (Join-Path `$root '.runner'), (Join-Path `$root '.credentials'), (Join-Path `$root '.credentials_rsaparams') -Force -EA SilentlyContinue
}
if (-not (Test-Path `$root)) { New-Item -ItemType Directory -Path `$root -Force | Out-Null }

# The runner itself, checked before it is unpacked.
if (-not (Test-Path (Join-Path `$root 'bin\Runner.Listener.exe')) -or -not (Test-Path (Join-Path `$root 'version-$version.txt'))) {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  `$zip = Join-Path `$env:TEMP '$zipName'
  Invoke-WebRequest -UseBasicParsing -Uri '$zipUrl' -OutFile `$zip
  `$got = (Get-FileHash -LiteralPath `$zip -Algorithm SHA256).Hash
  if (`$got -ne '$sha') {
    Remove-Item -LiteralPath `$zip -Force -EA SilentlyContinue
    throw ('actions/runner $version does not match the SHA-256 GitHub published for it, so it was not installed. Got ' + `$got)
  }
  Remove-Item -Path (Join-Path `$root 'bin'), (Join-Path `$root 'externals') -Recurse -Force -EA SilentlyContinue
  Expand-Archive -LiteralPath `$zip -DestinationPath `$root -Force
  Remove-Item -LiteralPath `$zip -Force
  Get-ChildItem `$root -Filter 'version-*.txt' | Remove-Item -Force
  Set-Content -LiteralPath (Join-Path `$root 'version-$version.txt') -Value '$version'
  'downloaded actions/runner $version, checksum matched'
} else { 'actions/runner $version already unpacked' }

# Windows Defender scans every process a test starts, several hundred per
# check, which was most of its five minutes. The runner's own folder only;
# every live C:\Thornswood-* folder stays scanned. The repository is
# private, so what runs here is the team's own code.
try { Add-MpPreference -ExclusionPath `$root -EA Stop; 'Defender skips ' + `$root } catch { 'Defender exclusion not set: ' + `$_.Exception.Message }

# Its own folder is the one place it may write.
& icacls.exe `$root /grant (`$acct + ':(OI)(CI)M') /T /C /Q 2>&1 | Out-Null

Push-Location `$root
`$cfg = & .\config.cmd --unattended --url 'https://github.com/$Repo' --token '$token' --name '$RunnerName' --labels '$Label' --work '_work' --replace --runasservice --windowslogonaccount (".\" + `$acct) --windowslogonpassword `$pw 2>&1
`$code = `$LASTEXITCODE
Pop-Location
`$pw = `$null; `$sec = `$null
`$cfg | Where-Object { "`$_" -match 'Runner successfully|Settings Saved|Service .* started|error|Error|failed' } | ForEach-Object { '  config: ' + "`$_".Trim() }
if (`$code -ne 0) { throw ('config.cmd stopped with ' + `$code) }

# Normal priority since 25 September (below normal until then). Patrick
# wanted a check in about five minutes, and at below normal every test
# waited behind whatever the box was doing. Jobs are started by
# Runner.Listener and inherit its priority. At start and every five
# minutes, in case the service restarts.
`$fix = 'Get-Process Runner.Listener, Runner.Worker -EA SilentlyContinue | ForEach-Object { `$_.PriorityClass = ''Normal'' }'
`$act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -WindowStyle Hidden -Command "' + `$fix + '"')
`$t1 = New-ScheduledTaskTrigger -AtStartup
`$t2 = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)
Register-ScheduledTask -TaskName '$TaskName' -Action `$act -Trigger `$t1, `$t2 -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
Start-ScheduledTask -TaskName '$TaskName'
Start-Sleep -Seconds 5
`$s = Get-Service -Name `$svc -EA SilentlyContinue
if (`$s) { 'service ' + `$s.Status } else { 'SERVICE NOT FOUND' }
foreach (`$p in (Get-Process Runner.Listener -EA SilentlyContinue)) { 'listener at ' + `$p.PriorityClass }
"@
$out | ForEach-Object { Say "  $_" }
$token = $null
if ("$out" -notmatch 'service Running') { Die 'The runner service is not running. The lines above say where it stopped; .\scripts\deploy\Install-Runner.ps1 -Status shows what is there.' }

Head 'GitHub'
Start-Sleep -Seconds 10
$r = (Invoke-Gh api "repos/$Repo/actions/runners" | Out-String) | ConvertFrom-Json
$mine = @($r.runners | Where-Object { $_.name -eq $RunnerName })
if (-not $mine.Count) { Die "The service runs but GitHub does not list a runner called $RunnerName yet. Give it a minute and run -Status." }
Say ('  ' + $mine[0].name + ' is ' + $mine[0].status) 'Green'
Say ''
Say '  The build check runs on it from the next push to a pull request, and the nightly checks every night.' 'Gray'
Done
