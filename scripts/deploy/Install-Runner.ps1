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
      .\scripts\deploy\Install-Runner.ps1 -OffBox      a pull request runner on THIS machine,
                                                    not the VPS (#1306), run elevated
      .\scripts\deploy\Install-Runner.ps1 -NetworkOnly -Number 4 -AllowHost pypi.org
                                                    the outbound firewall rules alone for
                                                    the fourth VPS runner's account (#2161)

  OFF THE BOX (-OffBox, issue #1306). build.yml sends a pull request to the
  label thornswood-pr, which no runner on the VPS carries, so code nobody has
  merged never runs beside the live server. -OffBox puts that runner on the
  machine this is run on (One, or a spare PC), in an elevated PowerShell, with
  no ssh at all: the same scripts the VPS gets run here instead. Its defaults
  are C:\Thornswood-RunnerPR, the account thornswood-pr, the runner name
  thornswood-pr-<computer> and the label thornswood-pr (-Number n puts the
  number on the end of each, the same as on the box). What changes from the box:
    - The account is shut out of every C:\Thornswood* folder, not only
      C:\Thornswood-*: on a developer machine the play build and the vault
      are C:\Thornswood and C:\Thornswood Vault, and neither has the hyphen
      (nor had C:\ThornswoodTemps&Worktrees, the worktrees until #2900).
      -AlsoDeny adds any other folder (another drive, say) to that list.
    - Defender keeps scanning the runner's folder unless -DefenderSkip is given.
      On the VPS the speed was worth it; on a machine people work on, a pull
      request's code is exactly what the scanner is for.
  Kept as on the box: an account in Users and nothing else with a password
  nobody sees, the runner's own folder locked to SYSTEM, Administrators and that
  account with nothing taken from C:\, the pinned runner zip, the service at
  normal priority, and the old priority tasks taken off. -Status, -Remove and
  -Lock take -OffBox too. -DryRunTo <file> writes the scripts it would run to
  that file and runs none of them, with a stand-in for every gh call, so
  tests\test-runner-offbox.ps1 can read them without touching an ACL, a
  service, an account or GitHub.

  NETWORK ONLY (-NetworkOnly, issue #2161). Patrick decided on 11 October 2026
  that the VPS runner accounts get the same outbound limit as an off-box
  runner. -NetworkOnly puts on THE NETWORK guard below and nothing else, for
  the one account -Number (or -Account) names: no account, service, runner,
  folder lock, read deny or Defender setting is touched, and no runner job is
  stopped. Without -OffBox it goes to the VPS over ssh like -Lock; with
  -OffBox it is this machine. It is the one mode that may name an account
  carrying the VPS label (full -OffBox still refuses it). -NetworkOnly -Status
  counts the rules, -NetworkOnly -Remove takes only that group off (the
  rollback), and -DryRunTo writes the script instead, as everywhere else.
  Fetch the lists again now and then the same way (run it again).

  WHAT A PULL REQUEST JOB MAY REACH (-OffBox, or -NetworkOnly for the network
  alone). Two guards, put on by the
  install and by -OffBox -Lock, taken off by -OffBox -Remove, shown by -Status
  and written out by -DryRunTo like everything else:
    - THE NETWORK. Outbound block rules in Windows Firewall, in a group of
      their own ('Thornswood PR runner <account>'), that match only programs
      running as the runner's account (-LocalUser, the account's SID) and
      cover every address except GitHub's (the web, api, git and actions
      lists of https://api.github.com/meta, fetched when it runs), loopback,
      and whatever -AllowHost names resolve to then. Windows Firewall puts a
      block rule above any allow rule, so "block everything, allow GitHub"
      cannot be two rules: the block rules ARE the complement of GitHub's
      ranges. What that does not do: it has no idea of host names (a rule is
      addresses; the actions list is broad Azure space shared with others);
      the lists change, so -OffBox -Lock fetches them again and puts the
      rules back (a new GitHub range is blocked until then, which fails
      closed); DNS questions go out through the DNS Client service, not the
      account, so a job can still ask a name server (a DNS tunnel is possible);
      a job that asks a service running as another account to fetch for it
      (BITS, say) is not this account's traffic. build.yml installs the pinned
      ruff from PyPI, which is not GitHub: that step fails closed unless
      -AllowHost pypi.org,files.pythonhosted.org is given (their addresses at
      that moment; a CDN moves them).
    - WHAT IT MAY READ outside C:\Thornswood*. A deny for the account on the
      root of every other fixed or removable drive, on every profile in
      C:\Users but its own and Default (Public included), and on
      C:\ProgramData\ssh and C:\ProgramData\Docker. Each deny sits on that one
      folder and is inherited below it; -Remove takes exactly those off. What
      that does not do: a child with inheritance switched off keeps its own
      rules; Windows, Program Files and the rest of ProgramData stay readable,
      as every account's are, because the tools a build needs live there;
      and the runner and its jobs are one account, so a job can read the
      runner's own .credentials (GitHub's design, the same on the VPS).

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

  HOW MANY BUILD AT ONCE (#2994). More runners than the box's six cores can
  carry only slow every build down: with seven at once on 21 October each
  harness step took 34 to 39 minutes and the 40-minute limit cancelled
  builds that were passing. The heavy jobs ask for a second label,
  thornswood-build, which only the runners records\build-runners.json lists
  carry (1 to 4). This install registers a listed runner with it;
  Set-BuildRunners.ps1 puts GitHub right for runners already there.

  WHAT IT DOES ON THE BOX, in order:
    1. Checks what the build check needs is there: pwsh, node, python and git
       on the machine PATH, MSBuild and the .NET Framework 4.8.1 reference
       assemblies the launcher's project files build with (#498; until
       15 Oct it checked the in-box csc, which builds nothing past C# 5), and
       WPF in Windows PowerShell. It installs none of them; it names the
       script that does.
    2. Makes a local account, thornswood-runner, that is in no group but
       Users. Its password is made on the box, handed to the service once and
       never printed, stored or sent anywhere.
    3. Denies that account every C:\Thornswood-* folder but its own and
       C:\Thornswood-Dumps (CRASH DUMPS, below), so a job cannot read the
       site's config, the bot's token or the backups, and cannot write into
       anything live. And locks its own folder to SYSTEM, Administrators and
       that account (below).
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
  account out of every C:\Thornswood-* folder but its own and Dumps, saying
  which it had to close, takes off a deny an earlier install put on Dumps
  for it, and it takes off every priority watcher task left on the box. No
  service is stopped and no job is touched. An install ends by doing the
  same for every runner, so adding one leaves all of them locked.

  CRASH DUMPS (#2127, #2488). Patrick decided on 11 October 2026 (#2127)
  that C:\Thornswood-Dumps is read by SYSTEM and Administrators only, and that
  LOCAL SERVICE and every local thornswood-runner* account may make and write
  files there and read nothing: Windows Error Reporting writes a crashing
  node.exe's dump there as the account that node ran as, a build's included.
  scripts\vps\Lock-VpsFolders.ps1 gives the folder those rules. Until 12
  October this script still put a full-control deny for each runner account
  on every C:\Thornswood-* folder, Dumps included, and a deny beats the write
  allow, so a build that crashed node left no dump: adding runners 5 and 6
  that day put the deny back on runners 1 to 4 (#2488). icacls /deny also
  takes away the account's own allow rules on that folder (measured 12
  October on a scratch folder), so the deny took the write with it. Now the
  folder is Lock-VpsFolders.ps1's alone on the VPS: the install, -Lock and
  the lock at the end of an install put no deny on it, take off the one an
  earlier install left there for a runner account and say so, and say when
  Users still reach it, which means Lock-VpsFolders.ps1 has not been run
  since. After a deny comes off, Lock-VpsFolders.ps1 is run again to give
  the write back.
  Off the box (-OffBox) nothing gives a pull request runner write there, so
  Dumps is shut to it like every other C:\Thornswood* folder.
  tests\test-runner-lock.ps1 holds it.

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
  -Status says when one is still there. A build shares the box's six cores
  at Normal with the site, Caddy and the bot, never above them. Since
  12 Oct 2026 the game servers and voice run High, above every build:
  Patrick's decision, "we need to fix it so the servers run on high
  priority" (#2491, Install-ThornswoodServer.ps1 and Install-Voice.ps1).

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
  # A pull request runner on this machine rather than the VPS (#1306).
  [switch]$OffBox,
  # The outbound firewall rules alone for one runner account (#2161, NETWORK
  # ONLY above). With -Status or -Remove, those rules alone.
  [switch]$NetworkOnly,
  # Folders the runner's account is shut out of as well as C:\Thornswood*.
  [string[]]$AlsoDeny = @(),
  # -OffBox or -NetworkOnly: host names a job may reach besides GitHub,
  # resolved to addresses when it runs (WHAT A PULL REQUEST JOB MAY REACH).
  [string[]]$AllowHost = @(),
  # -OffBox only: let Defender skip the runner's folder as it does on the VPS.
  [switch]$DefenderSkip,
  # Write the scripts it would run to this file and run none of them; every gh
  # call gets a stand-in answer. For tests\test-runner-offbox.ps1.
  [string]$DryRunTo = '',
  [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
# A list typed as a,b,c reaches [string[]] as three items in this PowerShell
# (& .\Install-Runner.ps1) but as ONE string through pwsh -File, which then
# failed to resolve "pypi.org,files.pythonhosted.org,..." on the box (#2161,
# 21 Oct) or, for -AlsoDeny, named one folder that is not there and was passed
# over. Both are split on commas here, however the script was started. No
# host name has a comma, and no folder these deny does.
$AllowHost = @($AllowHost | ForEach-Object { "$_" -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$AlsoDeny = @($AlsoDeny | ForEach-Object { "$_" -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here '..\vps\Vps.ps1')
. (Join-Path $Here '..\vps\Send-Script.ps1')
. (Join-Path $Here '..\vps\Send-Secret.ps1')
if (-not $OffBox) {
  if (-not $VpsUser) { $VpsUser = Get-ThornswoodVpsUser }
  if (-not $VpsHost) { $VpsHost = Get-ThornswoodVpsAddress }
}

# The nth runner's names, the header's SEVERAL OF THEM. A name given on the
# command line wins. 'thornswood-runner99' is 19 characters, inside the 20 a
# local account may have.
if ($Number -gt 1) {
  if (-not $PSBoundParameters.ContainsKey('Root'))       { $Root = 'C:\Thornswood-Runner' + $Number }
  if (-not $PSBoundParameters.ContainsKey('Account'))    { $Account = 'thornswood-runner' + $Number }
  if (-not $PSBoundParameters.ContainsKey('RunnerName')) { $RunnerName = 'thornswood-vps-' + $Number }
}
# Off the box (the header's OFF THE BOX). Its own names, so it can never be
# mistaken for, or replace, a runner on the VPS. thornswood-pr99 is 15
# characters, inside the 20 a local account may have.
$liveFilter = 'Thornswood-*'
if ($OffBox) {
  $n = $(if ($Number -gt 1) { '' + $Number } else { '' })
  if (-not $PSBoundParameters.ContainsKey('Root'))       { $Root = 'C:\Thornswood-RunnerPR' + $n }
  if (-not $PSBoundParameters.ContainsKey('Account'))    { $Account = 'thornswood-pr' + $n }
  if (-not $PSBoundParameters.ContainsKey('RunnerName')) { $RunnerName = 'thornswood-pr-' + [Environment]::MachineName.ToLower() + $(if ($n) { '-' + $n } else { '' }) }
  if (-not $PSBoundParameters.ContainsKey('Label'))      { $Label = 'thornswood-pr' }
  $liveFilter = 'Thornswood*'
  if ($Label -match 'thornswood-vps' -and -not $NetworkOnly) { Write-Host 'STOP. -OffBox never takes the VPS label: build.yml would send it main and release builds.' -ForegroundColor Red; exit 1 }
}
# HOW MANY BUILD AT ONCE (#2994). A VPS runner that records\build-runners.json
# lists is registered with its build label as well, so a reinstall keeps the
# cap Set-BuildRunners.ps1 put on GitHub. An off-box runner never carries it.
$registerLabels = $Label
if (-not $OffBox -and -not $PSBoundParameters.ContainsKey('Label')) {
  $buildRecord = Get-Content -LiteralPath (Join-Path $Here '..\..\records\build-runners.json') -Raw | ConvertFrom-Json
  if (@($buildRecord.runners | ForEach-Object { [int]$_ }) -contains $Number) { $registerLabels = $Label + ',' + $buildRecord.label }
}
# On the box, the folders records\runner-isolation.json says no runner may
# reach that are not C:\Thornswood-* (C:\ProgramData\ssh, the
# administrator's profile) are denied with the Thornswood ones, at every
# install and every -Lock. Until 21 Oct only C:\Thornswood-* and a hand-given
# -AlsoDeny were, and Check-RunnerIsolation.ps1 -Collect read on 21 Oct that
# every runner account's rights on C:\ProgramData\ssh included read (#2161).
# A noReach entry that is a file, or under C:\Thornswood-*, is passed over
# here: the box script skips anything that is not a folder, and the
# Thornswood folders are denied by $liveFilter already.
if (-not $OffBox) {
  $isolation = Get-Content -LiteralPath (Join-Path $Here '..\..\records\runner-isolation.json') -Raw | ConvertFrom-Json
  $AlsoDeny = @(@($AlsoDeny) + @($isolation.noReach | Where-Object { $_ -and $_ -notlike 'C:\Thornswood-*' }) | Select-Object -Unique)
}
# The lists the scripts below are given, as PowerShell source. $leaveList is
# the folders under C:\ that Lock-VpsFolders.ps1 gives the runner accounts
# write on, which this script never denies them (the header's CRASH DUMPS).
$alsoDenyList = '@(' + ((@($AlsoDeny | Where-Object { $_ }) | ForEach-Object { "'" + $_.Replace("'", "''") + "'" }) -join ', ') + ')'
$leaveList = $(if ($OffBox) { '@()' } else { "@('Thornswood-Dumps')" })
$defenderOn = $(if ($OffBox -and -not $DefenderSkip) { '$false' } else { '$true' })
$where = $(if ($OffBox) { 'this machine' } else { 'the VPS' })
$guardGroup = 'Thornswood PR runner ' + $Account

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }
function Done() { Write-Host ''; if (-not $NoPause) { [void](Read-Host 'Enter to close') }; exit 0 }

$target = "$VpsUser@$VpsHost"
$ssh = @('-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes')
$tools = @('ssh', 'scp', 'gh')
if ($OffBox) { $tools = @('gh') }
if ($DryRunTo) { $tools = @() }
if ($NetworkOnly -and $Lock) { Write-Host 'STOP. -NetworkOnly and -Lock are two different jobs: run them one at a time.' -ForegroundColor Red; exit 1 }
if ($OffBox -and -not $DryRunTo) {
  $me = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { Die '-OffBox makes an account, a service and folder rules on this machine, so it needs PowerShell run as administrator.' }
}
foreach ($t in $tools) {
  if (-not (Get-Command $t -ErrorAction SilentlyContinue)) {
    if ($t -ne 'gh') { Die "$t is not on PATH. Windows ships it: Settings, Apps, Optional features, OpenSSH Client." }
    Die 'gh is not on PATH. Install GitHub CLI from https://cli.github.com and run gh auth login.'
  }
}

# Short scripts go on the command line; the install is longer than cmd.exe's
# 8,191 characters once encoded, so it goes as a file and is deleted after,
# the same way Setup-Domain.ps1 does it. The registration token is never in
# the file: it goes on ssh's standard input (Send-Secret.ps1, issue #451).
# -OffBox runs the same scripts here, in a Windows PowerShell of their own (they
# end with exit, which would close this one), from a file removed after. A
# secret goes on that PowerShell's standard input, never in the file or on its
# command line, the same promise Send-Secret.ps1 keeps over ssh. -DryRunTo
# writes them down instead and runs nothing.
function Invoke-Here([string]$script, $secret = $null) {
  if ($DryRunTo) {
    Add-Content -LiteralPath $DryRunTo -Value ("# ==== a script it would run" + $(if ($null -ne $secret) { ', with a secret on standard input' } else { '' }) + " ====`r`n" + $script) -Encoding UTF8
    $global:LASTEXITCODE = 0
    return @('DRY RUN, nothing ran', 'service Running')
  }
  $pre = $(if ($null -ne $secret) { '$ThornswoodSecret = [Console]::In.ReadToEnd().Trim()' + "`r`n" } else { '' })
  $file = Join-Path ([IO.Path]::GetTempPath()) ('ts-runner-' + [Guid]::NewGuid().ToString('N') + '.ps1')
  [IO.File]::WriteAllText($file, $pre + $script, (New-Object Text.UTF8Encoding $true))
  $ErrorActionPreference = 'Continue'
  try {
    if ($null -ne $secret) { $out = @([string]$secret | & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $file 2>&1 | ForEach-Object { "$_" }) }
    else { $out = @(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $file 2>&1 | ForEach-Object { "$_" }) }
  } finally { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
  return $out
}
function Remote($script) {
  if ($OffBox -or $DryRunTo) { return Invoke-Here $script }
  # Send-Script.ps1 (issue #1070): a long script goes as a file of its own
  # name, removed after, and the far side's exit code comes back.
  return Invoke-ThornswoodRemote -Target $target -SshArgs $ssh -Script $script
}
function Send-WithSecret($secret, [string]$script) {
  if ($OffBox -or $DryRunTo) { return Invoke-Here $script $secret }
  return Invoke-ThornswoodSecretRemote -Target $target -SshArgs $ssh -Secret $secret -Script $script
}
# gh with its output kept apart from its errors, and a failure that says which
# call it was. Named so it never shadows gh itself.
function Invoke-Gh {
  # The exit code decides, not stderr: under Stop, Windows PowerShell 5.1 threw
  # on any line gh wrote there (a notice, a warning) even through 2>$null, and
  # a failure came out as NativeCommandError instead of the message below.
  $ErrorActionPreference = 'Continue'
  if ($DryRunTo) {
    # Stand-ins, so a dry run asks GitHub nothing.
    $a = $args -join ' '
    if ($a -match 'registration-token|remove-token') { return 'DRY-RUN-TOKEN-NOT-REAL' }
    if ($a -match '^api meta') { return '{"web":["140.82.112.0/20","2a0a:a440::/29"],"api":["192.30.252.0/22"],"git":["140.82.112.0/20"],"actions":["4.148.0.0/16"]}' }
    return ('{"runners":[{"name":"' + $RunnerName + '","status":"online (dry run)","busy":false,"labels":[{"name":"' + $Label + '"}]}]}')
  }
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
  # (a runner taken off since leaves its deny behind). A collection translates
  # without throwing for one it cannot name, and hands that one back as its SID.
  $ids = New-Object Security.Principal.IdentityReferenceCollection
  foreach ($r in @($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]) | Where-Object { "$($_.AccessControlType)" -eq 'Allow' })) { $ids.Add($r.IdentityReference) }
  $who = @($ids.Translate([Security.Principal.NTAccount], $false) | ForEach-Object { ("$($_.Value)" -split '\\')[-1] } | Sort-Object -Unique)
  $root + ' is locked: only ' + ($who -join ', ') + ' may use it'
}
# Shuts the account out of every C:\Thornswood-* folder but its own, and says
# which of them it could have read until now: one with a rule letting it or
# Users, Everyone or Authenticated Users in, and no deny for it. An account
# may be given as *<SID>, the way icacls takes one. $parent is C:\ except in
# tests\test-runner-lock.ps1, which runs both of these on scratch folders.
# $filter is 'Thornswood-*' on the VPS and 'Thornswood*' off it (-OffBox), where
# the worktrees and the play build have no hyphen. $also is -AlsoDeny.
# $leave names the folders under $parent that Lock-VpsFolders.ps1 gives the
# runner accounts write on (Thornswood-Dumps on the VPS, the header's CRASH
# DUMPS): never denied, and a deny an earlier install put there for this
# account is taken off and named.
function Close-RunnerAccount([string]$acct, [string]$own, [string]$parent = 'C:\', [string]$filter = 'Thornswood-*', [string[]]$also = @(), [string[]]$leave = @()) {
  $ErrorActionPreference = 'Continue'
  $sid = ''
  if ($acct.StartsWith('*')) { $sid = $acct.Substring(1) }
  else {
    try { $sid = (New-Object Security.Principal.NTAccount($acct)).Translate([Security.Principal.SecurityIdentifier]).Value }
    catch { throw ('there is no account called ' + $acct + ' on this box: ' + $_.Exception.Message) }
  }
  if (-not $sid) { throw ('there is no account called ' + $acct + ' on this box') }
  $had = 0; $shut = 0; $wasOpen = @()
  $dirs = @(@(Get-ChildItem -LiteralPath $parent -Directory -Filter $filter -EA SilentlyContinue) +
            @($also | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) } | ForEach-Object { Get-Item -LiteralPath $_ }))
  foreach ($d in $dirs) {
    if ($d.FullName -eq $own) { continue }
    if ($leave -contains $d.Name -and $d.Parent.FullName.TrimEnd('\') -eq $parent.TrimEnd('\')) {
      $mine = @((Get-Acl -LiteralPath $d.FullName).GetAccessRules($true, $false, [Security.Principal.SecurityIdentifier]) |
                Where-Object { "$($_.AccessControlType)" -eq 'Deny' -and $_.IdentityReference.Value -eq $sid })
      if ($mine.Count) {
        $null = & icacls.exe $d.FullName /remove:d ('*' + $sid) /C /Q 2>&1
        $left = @((Get-Acl -LiteralPath $d.FullName).GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]) |
                  Where-Object { "$($_.AccessControlType)" -eq 'Deny' -and $_.IdentityReference.Value -eq $sid })
        if ($LASTEXITCODE -ne 0 -or $left.Count) { throw ('icacls could not take ' + $acct + '''s deny off ' + $d.FullName + ', which Lock-VpsFolders.ps1 gives it write on (#2127)') }
        $acct + ': took off the deny an earlier install put on ' + $d.FullName + '; that deny also took its write away, so run Lock-VpsFolders.ps1 to give it write and no read there again (#2127, #2488)'
      }
      continue
    }
    $rules = $null
    # Rules that cannot be read are taken as open, so the folder is denied and
    # named with those it could read, and why they could not be read is said.
    try { $rules = @((Get-Acl -LiteralPath $d.FullName -ErrorAction Stop).GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) }
    catch { $acct + ': the rules on ' + $d.FullName + ' could not be read (' + $_.Exception.Message + '), so it is counted as one it could read' }
    if ($null -ne $rules -and @($rules | Where-Object { "$($_.AccessControlType)" -eq 'Deny' -and $_.IdentityReference.Value -eq $sid }).Count) { $had++; continue }
    $open = ($null -eq $rules) -or @($rules | Where-Object { "$($_.AccessControlType)" -eq 'Allow' -and ($broadSids -contains $_.IdentityReference.Value -or $_.IdentityReference.Value -eq $sid) }).Count
    $null = & icacls.exe $d.FullName /deny ($acct + ':(OI)(CI)F') /C /Q 2>&1
    if ($LASTEXITCODE -ne 0) { throw ('icacls could not shut ' + $acct + ' out of ' + $d.FullName) }
    if ($open) { $wasOpen += $d.FullName } else { $shut++ }
  }
  foreach ($w in $wasOpen) { $acct + ' COULD READ ' + $w + ' until now; shut out of it' }
  $acct + ': already shut out of ' + $had + ' folder(s)' + $(if ($shut) { ', and a deny added on ' + $shut + ' that were closed to it anyway' } else { '' })
}
# Says, once for the box, what each $leave folder is: Lock-VpsFolders.ps1's,
# and whether Users, Everyone or Authenticated Users still reach it, which
# means that script has not been run on it, and every runner may read it.
function Show-LeftFolders([string]$parent = 'C:\', [string[]]$leave = @()) {
  foreach ($n in $leave) {
    $p = Join-Path $parent $n
    if (-not (Test-Path -LiteralPath $p -PathType Container)) { continue }
    $acl = Get-Acl -LiteralPath $p
    $broad = @($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]) | Where-Object { "$($_.AccessControlType)" -eq 'Allow' -and $broadSids -contains $_.IdentityReference.Value })
    if ($broad.Count) { $p + ' is left to Lock-VpsFolders.ps1 (#2127), and USERS STILL REACH IT, so every runner may read it: run .\scripts\vps\Remote.ps1 -File .\scripts\vps\Lock-VpsFolders.ps1 from the repository' }
    else { $p + ' is left to Lock-VpsFolders.ps1 (#2127): no deny from here, and Users do not reach it' }
  }
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

# ------------------------------------------------- the off-box guards --
# The header's WHAT A PULL REQUEST JOB MAY REACH. $rangeLib runs here, on the
# machine that runs this script, and turns the address lists GitHub publishes
# into the ranges to block; tests\test-runner-offbox.ps1 lifts it out and
# checks its arithmetic. $guardLib runs where the runner is.
$rangeLib = @'
function ConvertTo-RunnerRange([string]$cidr) {
  $parts = $cidr.Trim().Split('/')
  $ip = [Net.IPAddress]::Parse($parts[0])
  $bytes = $ip.GetAddressBytes()
  $bits = $bytes.Length * 8
  $len = $(if ($parts.Count -gt 1) { [int]$parts[1] } else { $bits })
  if ($len -lt 0 -or $len -gt $bits) { throw ('not an address range: ' + $cidr) }
  $n = [bigint]0
  foreach ($b in $bytes) { $n = $n * 256 + $b }
  $size = [bigint]::Pow(2, $bits - $len)
  $lo = $n - ($n % $size)
  New-Object PSObject -Property @{ V = $(if ($bits -eq 32) { 4 } else { 6 }); Lo = $lo; Hi = $lo + $size - 1 }
}
function ConvertFrom-RunnerNumber([bigint]$n, [int]$v) {
  $count = $(if ($v -eq 4) { 4 } else { 16 })
  $bytes = New-Object byte[] $count
  for ($i = $count - 1; $i -ge 0; $i--) { $bytes[$i] = [byte][int]($n % 256); $n = [bigint]::Divide($n, 256) }
  ([Net.IPAddress]$bytes).ToString()
}
# Every address, IPv4 and IPv6, that is in none of $allow, as Windows Firewall
# ranges (a-b, or a lone address).
function Get-RunnerBlockRanges([string[]]$allow) {
  $out = New-Object Collections.Generic.List[string]
  $all = @($allow | Where-Object { $_ } | ForEach-Object { ConvertTo-RunnerRange $_ })
  foreach ($v in 4, 6) {
    $top = [bigint]::Pow(2, $(if ($v -eq 4) { 32 } else { 128 })) - 1
    $next = [bigint]0
    foreach ($r in @($all | Where-Object { $_.V -eq $v } | Sort-Object -Property Lo)) {
      if ($r.Lo -gt $next) {
        $a = ConvertFrom-RunnerNumber $next $v; $b = ConvertFrom-RunnerNumber ($r.Lo - 1) $v
        $out.Add($(if ($a -eq $b) { $a } else { $a + '-' + $b }))
      }
      if ($r.Hi + 1 -gt $next) { $next = $r.Hi + 1 }
    }
    if ($next -le $top) { $out.Add((ConvertFrom-RunnerNumber $next $v) + '-' + (ConvertFrom-RunnerNumber $top $v)) }
  }
  $out.ToArray()
}
'@
$guardLib = @'
# Outbound block rules for the account alone, replacing any it had.
function Set-RunnerFirewall([string]$acct, [string]$group, [string[]]$blocks, [int]$per = 500) {
  $sid = $(if ($acct.StartsWith('*')) { $acct.Substring(1) } else { (New-Object Security.Principal.NTAccount($acct)).Translate([Security.Principal.SecurityIdentifier]).Value })
  if (-not @($blocks).Count) { throw 'there is no address list to block, so the firewall was left as it was' }
  @(Get-NetFirewallRule -Group $group -EA SilentlyContinue) | ForEach-Object { Remove-NetFirewallRule -Name $_.Name }
  $why = 'Install-Runner.ps1 (#1306, #2161): this account reaches GitHub, loopback and the -AllowHost names only. -NetworkOnly -Remove takes it off.'
  $n = 0
  for ($i = 0; $i -lt $blocks.Count; $i += $per) {
    $n++
    $chunk = @($blocks[$i..([Math]::Min($i + $per, $blocks.Count) - 1)])
    New-NetFirewallRule -DisplayName ($group + ' ' + $n) -Group $group -Direction Outbound -Action Block -Profile Any -LocalUser ('D:(A;;CC;;;' + $sid + ')') -RemoteAddress $chunk -Description $why -EA Stop | Out-Null
  }
  'firewall: ' + $acct + ' may reach GitHub and this machine only, ' + $blocks.Count + ' blocked range(s) in ' + $n + ' outbound rule(s), group ' + $group
}
function Remove-RunnerFirewall([string]$group) {
  $r = @(Get-NetFirewallRule -Group $group -EA SilentlyContinue)
  if (-not $r.Count) { 'firewall: no rule in ' + $group; return }
  $r | ForEach-Object { Remove-NetFirewallRule -Name $_.Name }
  'firewall: took off ' + $r.Count + ' rule(s) in ' + $group
}
function Get-RunnerFirewall([string]$group) {
  $r = @(Get-NetFirewallRule -Group $group -EA SilentlyContinue)
  if ($r.Count) { 'firewall  ' + $r.Count + ' outbound block rule(s), ' + @($r | Where-Object { "$($_.Enabled)" -eq 'True' }).Count + ' on (group ' + $group + ')' } else { 'firewall  NO RULES: a pull request job may reach anywhere. -OffBox -Lock puts them on' }
}
# The folders outside C:\Thornswood* it is shut out of. $users, $programData
# and $drives are C:\Users, C:\ProgramData and the other drives except in
# tests\test-runner-offbox.ps1, which gives scratch folders.
function Get-RunnerReadDenies([string]$acct, [string]$users = 'C:\Users', [string]$programData = $env:ProgramData, $drives = $null) {
  if ($null -eq $drives) {
    $sys = '' + $env:SystemDrive
    $drives = @(Get-CimInstance Win32_LogicalDisk -EA SilentlyContinue | Where-Object { ($_.DriveType -eq 2 -or $_.DriveType -eq 3) -and $_.DeviceID -ne $sys } | ForEach-Object { $_.DeviceID + '\' })
  }
  $name = $acct.Split('\')[-1]
  $keep = @('Default', 'Default User', 'All Users')
  $out = @($drives | Where-Object { $_ })
  $out += @(Get-ChildItem -LiteralPath $users -Directory -Force -EA SilentlyContinue |
            Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -and $keep -notcontains $_.Name -and $_.Name -ne $name -and $_.Name -notlike ($name + '.*') } |
            ForEach-Object { $_.FullName })
  foreach ($p in 'ssh', 'Docker') { $out += (Join-Path $programData $p) }
  @($out | Where-Object { Test-Path -LiteralPath $_ -PathType Container })
}
function Close-RunnerReads([string]$acct, [string[]]$paths) {
  $ErrorActionPreference = 'Continue'
  foreach ($p in $paths) {
    $null = & icacls.exe $p /deny ($acct + ':(OI)(CI)F') /C /Q 2>&1
    if ($LASTEXITCODE -eq 0) { 'shut out of: ' + $p } else { 'COULD NOT shut ' + $acct + ' out of ' + $p }
  }
}
function Open-RunnerReads([string]$acct, [string[]]$paths) {
  $ErrorActionPreference = 'Continue'
  foreach ($p in $paths) { $null = & icacls.exe $p /remove:d $acct /C /Q 2>&1 }
  'deny taken off ' + @($paths).Count + ' folder(s) outside C:\Thornswood*'
}
'@
. ([scriptblock]::Create($rangeLib))
# Where the runner is: the guards, as source. $mode is apply, remove or status.
function Get-GuardScript([string]$mode, [string[]]$blocks = @()) {
  $list = '@(' + ((@($blocks) | ForEach-Object { "'" + $_ + "'" }) -join ', ') + ')'
  $head = $guardLib + "`n`$grdAcct = '" + $Account.Replace("'", "''") + "'`n`$grdGroup = '" + $guardGroup.Replace("'", "''") + "'`n"
  if ($mode -eq 'status') { return $head + 'Get-RunnerFirewall $grdGroup' }
  if ($mode -eq 'network-remove') { return $head + "Remove-RunnerFirewall `$grdGroup`n" }
  if ($mode -eq 'network') { return $head + "`$grdBlocks = " + $list + "`nSet-RunnerFirewall `$grdAcct `$grdGroup `$grdBlocks`n" }
  if ($mode -eq 'remove') { return $head + "Remove-RunnerFirewall `$grdGroup`nOpen-RunnerReads `$grdAcct (Get-RunnerReadDenies `$grdAcct)`n" }
  return $head + "`$grdBlocks = " + $list + "`nSet-RunnerFirewall `$grdAcct `$grdGroup `$grdBlocks`nClose-RunnerReads `$grdAcct (Get-RunnerReadDenies `$grdAcct)`n"
}
# GitHub's published lists, loopback and -AllowHost, as the ranges to block.
function Get-GuardBlocks {
  $meta = (Invoke-Gh api meta | Out-String) | ConvertFrom-Json
  $allow = @('127.0.0.0/8', '::1/128')
  foreach ($k in 'web', 'api', 'git', 'actions') {
    $got = @($meta.$k | Where-Object { $_ })
    if (-not $got.Count) { throw ('api.github.com/meta has no ' + $k + ' list, so no firewall rule was made') }
    $allow += $got
  }
  # The dry run resolves each name too, so a name the real run cannot resolve
  # stops the dry run the same way; it writes the stand-in 203.0.113.7 rather
  # than the addresses, as it writes stand-in GitHub lists.
  foreach ($h in @($AllowHost | Where-Object { $_ })) {
    $ips = @()
    try { $ips = @([Net.Dns]::GetHostAddresses($h) | ForEach-Object { $_.IPAddressToString }) } catch { throw ('-AllowHost ' + $h + ' does not resolve: ' + $_.Exception.Message) }
    if (-not $ips.Count) { throw ('-AllowHost ' + $h + ' resolves to nothing') }
    if ($DryRunTo) {
      $allow += '203.0.113.7/32'
      Say ('  -AllowHost ' + $h + ': ' + ($ips -join ', ') + ' (as of now; the dry run writes 203.0.113.7)') 'Yellow'
      continue
    }
    $allow += $ips
    Say ('  -AllowHost ' + $h + ': ' + ($ips -join ', ') + ' (as of now)') 'Yellow'
  }
  Get-RunnerBlockRanges $allow
}

# Every runner service on the box, by what Windows says it is: its folder is
# the one its RunnerService.exe is in, its account the one it runs as. Then
# the old priority watchers, which belong to no one runner.
$lockAll = $lockLib + $watcherLib + "`n`$liveFilter = '" + $liveFilter + "'`n`$alsoDeny = " + $alsoDenyList + "`n`$leave = " + $leaveList + "`n" + @'

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
    Close-RunnerAccount $acct $root 'C:\' $liveFilter $alsoDeny $leave
  } catch { 'NOT LOCKED: ' + $svc.Name + ': ' + $_.Exception.Message; $bad++ }
}
Show-LeftFolders 'C:\' $leave
if ($bad) { exit 1 }
'@

# ------------------------------------------------------------ network only --
# The header's NETWORK ONLY: the firewall group for one account, nothing else.
if ($NetworkOnly) {
  if ($Status) {
    Head ('Outbound rules for ' + $Account + ' on ' + $where)
    Remote (Get-GuardScript 'status') | ForEach-Object { Say "  $_" }
    Done
  }
  if ($Remove) {
    Head ('Outbound rules for ' + $Account + ' on ' + $where + ', taken off')
    $said = @(Remote (Get-GuardScript 'network-remove'))
    $code = $LASTEXITCODE
    $said | ForEach-Object { Say "  $_" }
    if ($code -ne 0) { Die "the rules may not all be off (exit $code); the lines above say which." }
    Done
  }
  Head ('What ' + $Account + ' may reach from ' + $where)
  try { $blocks = @(Get-GuardBlocks) } catch { Die ('no firewall rule was changed: ' + $_.Exception.Message) }
  $said = @(Remote (Get-GuardScript 'network' $blocks))
  $code = $LASTEXITCODE
  $said | ForEach-Object { Say "  $_" }
  if ($code -ne 0) { Die "the firewall rules did not go on (exit $code); the lines above say which. Nothing else was changed." }
  Done
}

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
  if ($OffBox) { Remote (Get-GuardScript 'status') | ForEach-Object { Say "  $_" } }
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
  Send-WithSecret ([string]$tok) ($watcherLib + "`n" + @"
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
foreach (`$d in @(@(Get-ChildItem 'C:\' -Directory -Filter '$liveFilter' -EA SilentlyContinue | ForEach-Object { `$_.FullName }) + $alsoDenyList)) {
  if (Test-Path -LiteralPath `$d) { & icacls.exe `$d /remove:d '$Account' /T /C /Q 2>&1 | Out-Null }
}
$(if ($OffBox) { Get-GuardScript 'remove' } else { Get-GuardScript 'network-remove' })
# What the install put outside the folder goes too: the Defender skip, which
# would leave a later folder at this path unscanned, and the account's
# profile, which Remove-LocalUser leaves (a later account of the same name
# then gets a <name>.<computer> profile beside it). Measured on the VPS on
# 20 Oct 2026: C:\Users\thornswood-runner5 and 6 left from removed runners.
if (@((Get-MpPreference -EA SilentlyContinue).ExclusionPath) -contains '$Root') {
  try { Remove-MpPreference -ExclusionPath '$Root' -EA Stop; 'Defender scans $Root again' } catch { 'COULD NOT take off the Defender skip for $Root' + ': ' + `$_.Exception.Message }
}
`$sid = ''
`$u = Get-LocalUser -Name '$Account' -EA SilentlyContinue
if (`$u) { `$sid = `$u.SID.Value }
Remove-LocalUser -Name '$Account' -EA SilentlyContinue
if (`$sid) {
  foreach (`$p in @(Get-CimInstance Win32_UserProfile -Filter "SID='`$sid'" -EA SilentlyContinue)) {
    try { `$p | Remove-CimInstance -EA Stop; 'profile ' + `$p.LocalPath + ' removed' } catch { 'COULD NOT remove the profile ' + `$p.LocalPath + ': ' + `$_.Exception.Message }
  }
}
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
  if ($OffBox) {
    # The header's WHAT A PULL REQUEST JOB MAY REACH: GitHub's lists fetched
    # again, so a range GitHub added since is let through.
    Head 'What a pull request job may reach and read'
    try { $blocks = @(Get-GuardBlocks) } catch { Die ('no firewall rule was changed: ' + $_.Exception.Message) }
    $said = @(Remote (Get-GuardScript 'apply' $blocks))
    $code = $LASTEXITCODE
    $said | ForEach-Object { Say "  $_" }
    if ($code -ne 0 -or ($said -join ' ') -match 'COULD NOT') { Die "the guards did not all go on (exit $code); the lines above say which." }
  }
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

Head "What the build check needs, on $where"
$need = Remote @"
`$env:PATH = [Environment]::GetEnvironmentVariable('PATH','Machine')
foreach (`$c in 'pwsh','node','python','git') {
  `$g = Get-Command `$c -EA SilentlyContinue
  if (`$g) { 'HAVE ' + `$c + ' ' + `$g.Source } else { 'MISSING ' + `$c }
}
`$pf86 = `${env:ProgramFiles(x86)}
`$vw = Join-Path `$pf86 'Microsoft Visual Studio\Installer\vswhere.exe'
`$msb = `$null
if (Test-Path `$vw) { `$msb = @(& `$vw -latest -products '*' -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe' 2>`$null | Where-Object { `$_ -and (`$_ -notmatch '\\amd64\\|\\arm64\\') }) | Select-Object -First 1 }
if (`$msb) { 'HAVE msbuild ' + `$msb } else { 'MISSING msbuild' }
`$ref = Join-Path `$pf86 'Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8.1'
if (Test-Path (Join-Path `$ref 'mscorlib.dll')) { 'HAVE net481refs ' + `$ref } else { 'MISSING net481refs' }
try { Add-Type -AssemblyName PresentationFramework; 'HAVE wpf' } catch { 'MISSING wpf' }
"@
$need | ForEach-Object { Say "  $_" }
$missing = @($need | Where-Object { "$_" -like 'MISSING *' } | ForEach-Object { "$_".Substring(8) })
if ($missing.Count) {
  $how = @()
  if ($missing -contains 'pwsh' -or $missing -contains 'node' -or $missing -contains 'git') { $how += ".\scripts\vps\Remote.ps1 -File .\scripts\vps\Bootstrap-VPS.ps1 -Arguments '-IncludeGit'   (PowerShell 7, Node, Git, for all users; from this machine, it runs on the VPS)" }
  if ($missing -contains 'python') { $how += '.\scripts\deploy\Install-Bot.ps1   (Python for all users; the bot needs it anyway)' }
  if ($missing -contains 'msbuild' -or $missing -contains 'net481refs') { $how += ".\scripts\vps\Remote.ps1 -File .\scripts\vps\Bootstrap-VPS.ps1 -Arguments '-IncludeBuildTools -SkipFirewall'   (MSBuild and the .NET Framework 4.8.1 reference assemblies the launcher builds with, #498)" }
  if ($missing -contains 'wpf') { $how += 'the box needs Windows Server with the Desktop Experience and .NET Framework 4.8; that is not a script' }
  Die ("$where is missing " + ($missing -join ', ') + ". Nothing was installed. Put them there with:" + [Environment]::NewLine + '    ' + ($how -join ([Environment]::NewLine + '    ')))
}

Head 'Registration token'
$token = (Invoke-Gh api -X POST "repos/$Repo/actions/runners/registration-token" --jq .token | Out-String).Trim()
if (-not $token) { Die "GitHub gave no registration token. gh has to be signed in as somebody who administers $Repo." }
Say '  got one, good for an hour, not shown' 'Green'

$guard = ''
if ($OffBox) {
  Head 'What a pull request job may reach'
  try { $guard = Get-GuardScript 'apply' @(Get-GuardBlocks) } catch { Die ('nothing was installed: ' + $_.Exception.Message) }
  Say '  GitHub''s address lists fetched; every other address is blocked for the account' 'Green'
}

Head "Installing it on $where"
# The token goes on ssh's standard input (Send-Secret.ps1, issue #451): on no
# command line and in no file on either machine. Until then it was written
# into this script, which is long enough to go up as a file, so it sat in
# C:\Windows\Temp on the VPS while the install ran.
$out = Send-WithSecret $token ($lockLib + $watcherLib + "`n" + @"
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

# Every live Thornswood folder is closed to it: read and write both. Off the
# box that is every C:\Thornswood* folder, and -AlsoDeny's besides. On the
# box Dumps is left to Lock-VpsFolders.ps1 (the header's CRASH DUMPS). The
# same Close-RunnerAccount -Lock runs, so the two can never disagree again.
Close-RunnerAccount `$acct `$root 'C:\' '$liveFilter' $alsoDenyList $leaveList
# Off the box: the network and the reads (WHAT A PULL REQUEST JOB MAY REACH),
# before the runner can take a job.
$guard

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
# Off the box (-OffBox) it keeps scanning unless -DefenderSkip says otherwise.
if ($defenderOn) {
  try { Add-MpPreference -ExclusionPath `$root -EA Stop; 'Defender skips ' + `$root } catch { 'Defender exclusion not set: ' + `$_.Exception.Message }
} else { 'Defender still scans ' + `$root + ' (off the box; -DefenderSkip to change that)' }

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
  `$cfg = & .\config.cmd --unattended --url 'https://github.com/$Repo' --name '$RunnerName' --labels '$registerLabels' --work '_work' --replace --runasservice --windowslogonaccount (".\" + `$acct) 2>&1
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
if ($OffBox -and "$out" -match 'COULD NOT shut') { Die 'The runner is installed, but a folder outside C:\Thornswood* could not be closed to it (the lines above). .\scripts\deploy\Install-Runner.ps1 -OffBox -Lock tries again.' }
if ("$out" -notmatch 'service Running') { Die 'The runner service is not running. The lines above say where it stopped; .\scripts\deploy\Install-Runner.ps1 -Status shows what is there.' }

Head 'GitHub'
# GitHub shows the runner online once its listener has connected, a few
# seconds after the service starts; how long that takes is on GitHub's side,
# outside this script, so GitHub is asked every 3 seconds until it says so,
# for a minute at most. Until #2357 this was a fixed 10 second wait and one
# ask, and the wait ran in every -DryRunTo too, where the stand-in answers at
# once: nine of them in tests\test-runner-offbox.ps1, 90 of its 100 seconds
# in the nightly.
$askUntil = (Get-Date).AddSeconds(60)
while ($true) {
  $r = (Invoke-Gh api "repos/$Repo/actions/runners" | Out-String) | ConvertFrom-Json
  $mine = @($r.runners | Where-Object { $_.name -eq $RunnerName })
  if (($mine.Count -and "$($mine[0].status)" -like 'online*') -or (Get-Date) -ge $askUntil) { break }
  Start-Sleep -Seconds 3
}
if (-not $mine.Count) { Die "The service runs but GitHub did not list a runner called $RunnerName within a minute. Run -Status to ask again." }
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
