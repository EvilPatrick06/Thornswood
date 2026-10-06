<#
  Install-Runner.ps1

  Puts a GitHub Actions runner on the VPS, so the build check runs on every
  pull request without paying for minutes. Run it from this machine; it
  does the remote half over ssh, the same way Install-Backup.ps1 does.

      .\scripts\deploy\Install-Runner.ps1              install the first one, or put it right
      .\scripts\deploy\Install-Runner.ps1 -Number 3    the third, beside the others
      .\scripts\deploy\Install-Runner.ps1 -Status      what is there and whether GitHub sees it
      .\scripts\deploy\Install-Runner.ps1 -Remove      take it off the box and off GitHub
      .\scripts\deploy\Install-Runner.ps1 -Lock        lock every runner on the box again,
                                                    touching no runner and no job, and
                                                    take off the old priority watchers

  WHY. Every run of .github\workflows\build.yml has failed in seconds since
  02:10 on 25 September, because GitHub's own runners are blocked on billing.
  Decided by Patrick on 25 September (issue #437): a runner on the VPS rather
  than paying for minutes. build.yml asks for [self-hosted, Windows,
  thornswood-vps], which is every runner this puts there and nothing else.

  SEVERAL OF THEM. A runner takes one job at a time. On 4 October the queue
  was an hour long: eleven checks waiting while one ran, because the lanes
  open pull requests in bursts (five in seven seconds at 17:46) and every
  merge to main runs the check again. Patrick added a second runner that
  evening and asked for more. -Number n puts the nth beside the others: its
  own folder, account and runner name, each with the number on the end
  (C:\Thornswood-Runner3, thornswood-runner3, thornswood-vps-3), and the
  same label, so GitHub hands a waiting job to whichever is free. 1 is the
  first, with the names it has always had. -Status and -Remove take -Number
  the same way; -Lock does every runner on the box.

  WHAT IT DOES ON THE BOX, in order:
    1. Checks what the build check needs is there: pwsh, node, python and git
       on the machine PATH, the .NET Framework csc, and WPF in Windows
       PowerShell. It installs none of them; it names the script that does.
    2. Makes a local account, thornswood-runner, that is in no group but
       Users. Its password is made on the box, handed to the service once and
       never printed, stored or sent anywhere.
    3. Denies that account every C:\Thornswood-* folder but its own, so a job
       cannot read the site's config, the bot's token or the backups, and
       cannot write into anything live. And locks its own folder to SYSTEM,
       Administrators and that account (below).
    4. Downloads a pinned actions/runner win-x64 zip (version + SHA-256
       hardcoded below, #1372), checked against that pin, and registers it as a
       service that runs as that account.
    5. Takes off the priority watcher task an older install left (NO
       PRIORITY TASK, below).
    6. Tells Windows Defender to skip the runner's own folder, so the few
       hundred processes a check starts are not each scanned on the way in.

  It needs gh on this machine, signed in as somebody who can administer the
  repository (Patrick): the registration token comes from
  gh api -X POST repos/<repo>/actions/runners/registration-token. The token
  lasts an hour and is never printed.

  ITS OWN FOLDER TAKES NOTHING FROM C:\. A folder made under C:\ inherits
  Windows' rule that BUILTIN\Users may read it, and every service account on
  the box is in Users, every other runner's included. A runner's folder holds
  the credentials GitHub gave it (.runner, .credentials), so until 4 October
  the first runner's account could read the second's: the second's install
  shut its own account out of the first's folder, and nothing shut the first
  out of the second's, which did not exist when the first was installed. Now
  each runner's folder is locked the way #1105 locked the server folders:
  inheritance off, SYSTEM and Administrators Full Control, its own account
  Modify, and nobody else, which holds for runners added later as well.

  -LOCK puts that right on a box as it is, without replacing anything: for
  every runner service there, it locks the runner's folder, and shuts its
  account out of every C:\Thornswood-* folder but its own, saying which it
  had to close, and it takes off every priority watcher task left on the
  box. No service is stopped and no job is touched. An install ends by doing
  the same for every runner, so adding one leaves all of them locked.

  NO PRIORITY TASK (#1969). Until 5 October each install registered a task,
  Thornswood Runner Priority (Thornswood Runner N Priority from the second
  on), that set Runner.Listener and Runner.Worker to Normal at start and
  every five minutes: a timer that repairs state, which Developer-Guide.md
  "Fix the cause, no band-aids" does not allow. Until 25 September it set
  them to BelowNormal, which is where they ran then; since then it had nothing
  to repair. The runner is a Windows service (config.cmd --runasservice),
  and the service control manager starts a service at Normal, I/O priority 2
  and memory priority 5; the runner sets no priority of its own on Windows
  (actions/runner lowers a job's processes only on Linux, through
  oom_score_adj, in ProcessInvoker.cs). On the VPS on 5 October the runners
  measured Normal, 2 and 5 (PR #1967), and the watcher could not have given
  them the 2 and the 5: its line changes the class only, so a program a
  priority 7 task started went from BelowNormal, I/O 1, memory 2 to Normal,
  1 and 2, measured the same day (tests\test-runner-priority.ps1). The
  install, -Lock and -Remove take every such task off the box and name it;
  -Status says when one is still there. A build still shares the five cores
  with the game server, the site, voice and the bot at the same priority as
  them, never above.

  Safe to run again. An existing runner is replaced, the account keeps its
  name and gets a new password, and the folder denials are made again.
  Replacing one stops the job it is running; -Lock does not.
#>
[CmdletBinding()]
param(
  [string]$VpsHost    = '',
  [string]$VpsUser    = '',
  [string]$Repo       = 'EvilPatrick06/Thornswood',
  # Which runner. 1 is the first, with the names below; from 2 up, the three
  # names after it get the number on the end unless they are given.
  [ValidateRange(1, 99)][int]$Number = 1,
  [string]$Root       = 'C:\Thornswood-Runner',
  [string]$Account    = 'thornswood-runner',
  [string]$RunnerName = 'thornswood-vps',
  # The label build.yml asks for. Change the two together.
  [string]$Label      = 'thornswood-vps',
  [switch]$Status,
  [switch]$Remove,
  [switch]$Lock,
  [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here '..\vps\Vps.ps1')
. (Join-Path $Here '..\vps\Send-Script.ps1')
. (Join-Path $Here '..\vps\Send-Secret.ps1')
if (-not $VpsUser) { $VpsUser = Get-ThornswoodVpsUser }
if (-not $VpsHost) { $VpsHost = Get-ThornswoodVpsAddress }

# The nth runner's names, the header's SEVERAL OF THEM. A name given on the
# command line wins. 'thornswood-runner99' is 19 characters, inside the 20 a
# local account may have.
if ($Number -gt 1) {
  if (-not $PSBoundParameters.ContainsKey('Root'))       { $Root = 'C:\Thornswood-Runner' + $Number }
  if (-not $PSBoundParameters.ContainsKey('Account'))    { $Account = 'thornswood-runner' + $Number }
  if (-not $PSBoundParameters.ContainsKey('RunnerName')) { $RunnerName = 'thornswood-vps-' + $Number }
}

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }
function Done() { Write-Host ''; if (-not $NoPause) { [void](Read-Host 'Enter to close') }; exit 0 }

$target = "$VpsUser@$VpsHost"
$ssh = @('-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes')
foreach ($t in 'ssh', 'scp', 'gh') {
  if (-not (Get-Command $t -ErrorAction SilentlyContinue)) {
    if ($t -ne 'gh') { Die "$t is not on PATH. Windows ships it: Settings, Apps, Optional features, OpenSSH Client." }
    Die 'gh is not on PATH. Install GitHub CLI from https://cli.github.com and run gh auth login.'
  }
}

# Short scripts go on the command line; the install is longer than cmd.exe's
# 8,191 characters once encoded, so it goes as a file and is deleted after,
# the same way Setup-Domain.ps1 does it. The registration token is never in
# the file: it goes on ssh's standard input (Send-Secret.ps1, issue #451).
function Remote($script) {
  # Send-Script.ps1 (issue #1070): a long script goes as a file of its own
  # name, removed after, and the far side's exit code comes back.
  return Invoke-ThornswoodRemote -Target $target -SshArgs $ssh -Script $script
}
# gh with its output kept apart from its errors, and a failure that says which
# call it was. Named so it never shadows gh itself.
function Invoke-Gh {
  $out = & gh @args 2>$null
  if ($LASTEXITCODE -ne 0) { throw ('gh ' + ($args -join ' ') + ' failed') }
  return $out
}

$service = 'actions.runner.' + $Repo.Replace('/', '-') + '.' + $RunnerName

# ------------------------------------------------------------- the locks --
# Run on the box, by the install for its own folder and by -Lock and the end
# of every install for each runner there (the header's ITS OWN FOLDER TAKES
# NOTHING FROM C:\ and -LOCK). Windows PowerShell 5.1 turns a native
# program's stderr into an error record, so these run with Continue and judge
# icacls by its exit code (#941).
$lockLib = @'
$broadSids = @('S-1-5-32-545', 'S-1-1-0', 'S-1-5-11', 'S-1-3-0')
function Lock-RunnerRoot([string]$root, [string]$acct) {
  $ErrorActionPreference = 'Continue'
  $out = & icacls.exe $root /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' ($acct + ':(OI)(CI)M') /C /Q 2>&1
  if ($LASTEXITCODE -ne 0) { throw ('icacls could not give ' + $root + ' its rules: ' + (($out | ForEach-Object { "$_" }) -join ' ')) }
  $out = & icacls.exe $root /inheritance:r /C /Q 2>&1
  if ($LASTEXITCODE -ne 0) { throw ('icacls could not stop ' + $root + ' taking rules from C:\: ' + (($out | ForEach-Object { "$_" }) -join ' ')) }
  $null = & icacls.exe $root /remove:g '*S-1-5-32-545' '*S-1-1-0' '*S-1-5-11' '*S-1-3-0' /C /Q 2>&1
  # Read back: nothing taken from C:\, and nothing broad left on it.
  $acl = Get-Acl -LiteralPath $root
  $open = @($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]) |
            Where-Object { "$($_.AccessControlType)" -eq 'Allow' -and $broadSids -contains $_.IdentityReference.Value })
  if (-not $acl.AreAccessRulesProtected -or $open.Count) {
    throw ($root + ' is still open: ' + $(if (-not $acl.AreAccessRulesProtected) { 'it takes rules from C:\' } else { (@($open | ForEach-Object { $_.IdentityReference.Value }) -join ', ') + ' may read it' }))
  }
  # By name where Windows still knows the account, by SID where it does not
  # (a runner taken off since leaves its deny behind).
  $who = @($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]) |
           Where-Object { "$($_.AccessControlType)" -eq 'Allow' } |
           ForEach-Object { $n = $_.IdentityReference.Value; try { $n = ("$($_.IdentityReference.Translate([Security.Principal.NTAccount]))" -split '\\')[-1] } catch { }; $n } | Sort-Object -Unique)
  $root + ' is locked: only ' + ($who -join ', ') + ' may use it'
}
# Shuts the account out of every C:\Thornswood-* folder but its own, and says
# which of them it could have read until now: one with a rule letting it or
# Users, Everyone or Authenticated Users in, and no deny for it. An account
# may be given as *<SID>, the way icacls takes one. $parent is C:\ except in
# tests\test-runner-lock.ps1, which runs both of these on scratch folders.
function Close-RunnerAccount([string]$acct, [string]$own, [string]$parent = 'C:\') {
  $ErrorActionPreference = 'Continue'
  $sid = ''
  if ($acct.StartsWith('*')) { $sid = $acct.Substring(1) }
  else { try { $sid = (New-Object Security.Principal.NTAccount($acct)).Translate([Security.Principal.SecurityIdentifier]).Value } catch { } }
  if (-not $sid) { throw ('there is no account called ' + $acct + ' on this box') }
  $had = 0; $shut = 0; $wasOpen = @()
  foreach ($d in @(Get-ChildItem -LiteralPath $parent -Directory -Filter 'Thornswood-*' -EA SilentlyContinue)) {
    if ($d.FullName -eq $own) { continue }
    $rules = $null
    try { $rules = @((Get-Acl -LiteralPath $d.FullName).GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) } catch { }
    if ($null -ne $rules -and @($rules | Where-Object { "$($_.AccessControlType)" -eq 'Deny' -and $_.IdentityReference.Value -eq $sid }).Count) { $had++; continue }
    $open = ($null -eq $rules) -or @($rules | Where-Object { "$($_.AccessControlType)" -eq 'Allow' -and ($broadSids -contains $_.IdentityReference.Value -or $_.IdentityReference.Value -eq $sid) }).Count
    $null = & icacls.exe $d.FullName /deny ($acct + ':(OI)(CI)F') /C /Q 2>&1
    if ($LASTEXITCODE -ne 0) { throw ('icacls could not shut ' + $acct + ' out of ' + $d.FullName) }
    if ($open) { $wasOpen += $d.FullName } else { $shut++ }
  }
  foreach ($w in $wasOpen) { $acct + ' COULD READ ' + $w + ' until now; shut out of it' }
  $acct + ': already shut out of ' + $had + ' folder(s)' + $(if ($shut) { ', and a deny added on ' + $shut + ' that were closed to it anyway' } else { '' })
}
'@

# ------------------------------------------------------ the old watchers --
# The header's NO PRIORITY TASK. Sent with the install, -Lock, -Remove and
# -Status. A watcher is a task named the way installs before #1969 named
# theirs: '<prefix> Priority' or '<prefix> <n> Priority'. $prefix is
# 'Thornswood Runner' except in tests\test-runner-priority.ps1, which runs
# these on scratch tasks of its own.
$watcherLib = @'
function Get-RunnerWatchers([string]$prefix = 'Thornswood Runner') {
  $like = '^' + [regex]::Escape($prefix) + '( \d+)? Priority$'
  @(Get-ScheduledTask -EA SilentlyContinue | Where-Object { $_.TaskName -match $like })
}
function Remove-RunnerWatchers([string]$prefix = 'Thornswood Runner') {
  $found = @(Get-RunnerWatchers $prefix)
  if (-not $found.Count) { 'no priority watcher task on this box'; return }
  foreach ($w in $found) {
    try {
      Unregister-ScheduledTask -TaskName $w.TaskName -TaskPath $w.TaskPath -Confirm:$false -ErrorAction Stop
      'took off the priority watcher task ' + $w.TaskName + ' (#1969)'
    } catch { 'COULD NOT TAKE OFF the priority watcher task ' + $w.TaskName + ': ' + $_.Exception.Message }
  }
}
'@

# Every runner service on the box, by what Windows says it is: its folder is
# the one its RunnerService.exe is in, its account the one it runs as. Then
# the old priority watchers, which belong to no one runner.
$lockAll = $lockLib + $watcherLib + @'

$ErrorActionPreference = 'Continue'
$bad = 0
foreach ($line in @(Remove-RunnerWatchers)) { $line; if ($line -like 'COULD NOT*') { $bad++ } }
$services = @(Get-CimInstance Win32_Service -Filter "Name LIKE 'actions.runner.%'" -EA SilentlyContinue)
if (-not $services.Count) { 'no runner service on this box' }
foreach ($svc in $services) {
  $exe = ('' + $svc.PathName).Trim().Trim('"')
  $root = Split-Path -Parent (Split-Path -Parent $exe)
  $acct = (('' + $svc.StartName) -split '\\')[-1]
  if ($root -notlike 'C:\Thornswood-Runner*') { $svc.Name + ' runs from ' + $exe + ', not a C:\Thornswood-Runner folder, so it was left alone'; $bad++; continue }
  if (-not $acct -or $acct -match '^(LocalSystem|LocalService|NetworkService)$') { $svc.Name + ' runs as ' + $svc.StartName + ', not an account of its own, so it was left alone'; $bad++; continue }
  try {
    Lock-RunnerRoot $root $acct
    Close-RunnerAccount $acct $root
  } catch { 'NOT LOCKED: ' + $svc.Name + ': ' + $_.Exception.Message; $bad++ }
}
if ($bad) { exit 1 }
'@

# ------------------------------------------------------------------ status --
if ($Status) {
  Head 'On the VPS'
  Remote ($watcherLib + @"
`$ErrorActionPreference = 'SilentlyContinue'
if (Test-Path '$Root\config.cmd') { 'runner    in $Root' } else { 'runner    NOT THERE' }
`$s = Get-Service -Name '$service'
if (`$s) { 'service   ' + `$s.Status + ', starts ' + `$s.StartType } else { 'service   NOT REGISTERED' }
`$w = Get-CimInstance Win32_Service -Filter "Name='$service'"
if (`$w) { 'runs as   ' + `$w.StartName }
foreach (`$p in (Get-Process Runner.Listener, Runner.Worker)) { 'process   ' + `$p.ProcessName + ' at ' + `$p.PriorityClass }
if (Get-LocalUser -Name '$Account') { 'account   $Account' } else { 'account   NOT THERE' }
if (Test-Path '$Root') {
  `$a = Get-Acl -LiteralPath '$Root'
  `$wide = @(`$a.GetAccessRules(`$true, `$true, [Security.Principal.SecurityIdentifier]) | Where-Object { "`$(`$_.AccessControlType)" -eq 'Allow' -and @('S-1-5-32-545', 'S-1-1-0', 'S-1-5-11', 'S-1-3-0') -contains `$_.IdentityReference.Value })
  if (`$a.AreAccessRulesProtected -and -not `$wide.Count) { 'folder    locked: takes nothing from C:\' } else { 'folder    OPEN to every account on the box: -Lock locks it' }
}
`$old = @(Get-RunnerWatchers)
if (`$old.Count) { 'priority  OLD WATCHER TASK still here: ' + ((`$old | ForEach-Object { `$_.TaskName }) -join ', ') + '. -Lock takes it off' }
else { 'priority  no watcher task; the service starts the runner at normal' }
"@) | ForEach-Object { Say "  $_" }
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
  # The removal token goes on ssh's standard input and reaches config.cmd in
  # its environment, never on a command line (Send-Secret.ps1, issue #451).
  Invoke-ThornswoodSecretRemote -Target $target -SshArgs $ssh -Secret ([string]$tok) -Script ($watcherLib + "`n" + @"
`$ErrorActionPreference = 'Continue'
`$t = `$ThornswoodSecret; `$ThornswoodSecret = `$null
if ((Test-Path '$Root\config.cmd') -and `$t) {
  Push-Location '$Root'
  `$env:ACTIONS_RUNNER_INPUT_TOKEN = `$t; `$t = `$null
  & .\config.cmd remove 2>&1 | Select-Object -Last 3
  Remove-Item Env:\ACTIONS_RUNNER_INPUT_TOKEN -EA SilentlyContinue
  Pop-Location
}
Stop-Service -Name '$service' -Force -EA SilentlyContinue
& sc.exe delete '$service' 2>&1 | Out-Null
Remove-RunnerWatchers
foreach (`$d in (Get-ChildItem 'C:\' -Directory -Filter 'Thornswood-*' -EA SilentlyContinue)) {
  & icacls.exe `$d.FullName /remove:d '$Account' /T /C /Q 2>&1 | Out-Null
}
Remove-LocalUser -Name '$Account' -EA SilentlyContinue
Remove-Item -LiteralPath '$Root' -Recurse -Force -EA SilentlyContinue
if (Test-Path '$Root') { 'the folder is still there, something holds a file in it' } else { 'runner, account and folder removed' }
"@) | ForEach-Object { Say "  $_" }
  Done
}

# -------------------------------------------------------------------- lock --
if ($Lock) {
  Head 'Every runner on the box, locked'
  $said = @(Remote $lockAll)
  $code = $LASTEXITCODE
  $said | ForEach-Object { Say "  $_" }
  if ($code -ne 0) { Die "the lock did not finish for every runner (exit $code); the lines above say which." }
  Done
}

# ----------------------------------------------------------------- install --
Head 'The runner release'
# Pin (#1372): do not follow releases/latest. Bump these two together after
# checking https://github.com/actions/runner/releases and the win-x64 SHA in
# that release's notes (<!-- BEGIN SHA win-x64 --> ... <!-- END SHA win-x64 -->).
$version = '2.337.0'
$sha = '1150692AFA94E71F872017E254EA55B6EECE1EECE3FE7E3A6D4C93D0A1B85CFC'
if ($version -notmatch '^\d+\.\d+\.\d+$') { Die "Pinned actions/runner version is nonsense: $version" }
if ($sha -notmatch '^[0-9A-F]{64}$') { Die "Pinned actions/runner SHA-256 is nonsense: $sha" }
$zipName = "actions-runner-win-x64-$version.zip"
$zipUrl = "https://github.com/actions/runner/releases/download/v$version/$zipName"
Say "  actions/runner $version (pinned), SHA-256 $sha" 'Green'

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
# The token goes on ssh's standard input (Send-Secret.ps1, issue #451): on no
# command line and in no file on either machine. Until then it was written
# into this script, which is long enough to go up as a file, so it sat in
# C:\Windows\Temp on the VPS while the install ran.
$out = Invoke-ThornswoodSecretRemote -Target $target -SshArgs $ssh -Secret $token -Script ($lockLib + $watcherLib + "`n" + @"
`$ErrorActionPreference = 'Stop'
`$regToken = `$ThornswoodSecret; `$ThornswoodSecret = `$null
if (-not `$regToken) { throw 'NOTHING ARRIVED on standard input, so there is no registration token. Nothing was installed.' }
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
# Locked before config.cmd writes GitHub's credentials into it.
Lock-RunnerRoot `$root `$acct

# The runner itself, checked before it is unpacked.
if (-not (Test-Path (Join-Path `$root 'bin\Runner.Listener.exe')) -or -not (Test-Path (Join-Path `$root 'version-$version.txt'))) {
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
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

# The token and the account's password reach config.cmd in its environment,
# not its arguments, so neither is in the box's process list (issue #451).
# The runner reads ACTIONS_RUNNER_INPUT_<argument> for any argument not given
# and clears it once read (actions/runner, CommandSettings.cs).
Push-Location `$root
`$env:ACTIONS_RUNNER_INPUT_TOKEN = `$regToken
`$env:ACTIONS_RUNNER_INPUT_WINDOWSLOGONPASSWORD = `$pw
try {
  `$cfg = & .\config.cmd --unattended --url 'https://github.com/$Repo' --name '$RunnerName' --labels '$Label' --work '_work' --replace --runasservice --windowslogonaccount (".\" + `$acct) 2>&1
  `$code = `$LASTEXITCODE
} finally {
  Remove-Item Env:\ACTIONS_RUNNER_INPUT_TOKEN, Env:\ACTIONS_RUNNER_INPUT_WINDOWSLOGONPASSWORD -EA SilentlyContinue
}
Pop-Location
`$pw = `$null; `$sec = `$null; `$regToken = `$null
`$cfg | Where-Object { "`$_" -match 'Runner successfully|Settings Saved|Service .* started|error|Error|failed' } | ForEach-Object { '  config: ' + "`$_".Trim() }
if (`$code -ne 0) { throw ('config.cmd stopped with ' + `$code) }

# Normal priority, from the service: the service control manager starts
# RunnerService.exe at Normal, I/O priority 2 and memory priority 5, and
# Runner.Listener, Runner.Worker and every job inherit it. The task an
# older install registered to set it every five minutes goes (the header's
# NO PRIORITY TASK, #1969).
Remove-RunnerWatchers
Start-Sleep -Seconds 5
`$s = Get-Service -Name `$svc -EA SilentlyContinue
if (`$s) { 'service ' + `$s.Status } else { 'SERVICE NOT FOUND' }
foreach (`$p in (Get-Process Runner.Listener -EA SilentlyContinue)) { 'listener at ' + `$p.PriorityClass }
"@)
$out | ForEach-Object { Say "  $_" }
$token = $null
if ("$out" -notmatch 'service Running') { Die 'The runner service is not running. The lines above say where it stopped; .\scripts\deploy\Install-Runner.ps1 -Status shows what is there.' }

Head 'GitHub'
Start-Sleep -Seconds 10
$r = (Invoke-Gh api "repos/$Repo/actions/runners" | Out-String) | ConvertFrom-Json
$mine = @($r.runners | Where-Object { $_.name -eq $RunnerName })
if (-not $mine.Count) { Die "The service runs but GitHub does not list a runner called $RunnerName yet. Give it a minute and run -Status." }
Say ('  ' + $mine[0].name + ' is ' + $mine[0].status) 'Green'

# Every runner, this one included, so adding one leaves all of them locked.
Head 'Every runner on the box, locked'
$said = @(Remote $lockAll)
$code = $LASTEXITCODE
$said | ForEach-Object { Say "  $_" }
if ($code -ne 0) { Die "the runner is installed, but the lock did not finish for every runner (exit $code); the lines above say which. .\scripts\deploy\Install-Runner.ps1 -Lock tries again without touching any runner." }
Say ''
Say '  GitHub hands it a waiting build check, nightly or release build as soon as it is free.' 'Gray'
Done
