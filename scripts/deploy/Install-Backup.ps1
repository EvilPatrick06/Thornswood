<#
  Install-Backup.ps1

  Puts the nightly backup on the VPS: sends vps-nightly-backup.ps1 up, makes a
  passphrase if there is not one yet, and registers the scheduled task that
  runs it. Run it from this machine; it does the remote half over ssh.

      .\scripts\deploy\Install-Backup.ps1              install it
      .\scripts\deploy\Install-Backup.ps1 -RunNow      install it and take one straight away
      .\scripts\deploy\Install-Backup.ps1 -Status      what is there and when it last ran
      .\scripts\deploy\Install-Backup.ps1 -Remove      take the task off again

  Nothing backed up the world until this existed. The two backups that were
  there were taken sixteen minutes apart on 15 September and neither had a
  single character in it, which is the one thing here people would grieve over.

  THE PASSPHRASE. It is made on the VPS, never printed, and never committed.
  The first install copies it down to -KeyOut on this machine, and that copy is
  the whole point: a passphrase that only exists on the box is no use the day
  the box is what you lost. Put it wherever you keep the server password, and
  then it does not matter who finds a backup.

  This installs the on-box half. Getting the backups off the box is
  Fetch-Backups.ps1, which runs here, and restoring one is docs\RESTORING.md.
#>
[CmdletBinding()]
param(
  [string]$VpsHost  = '',
  [string]$VpsUser  = '',
  [string]$Root     = 'C:\Thornswood-Backup',
  [string]$TaskName = 'Thornswood Backup',
  # Quarter past three in the morning, well clear of when anybody is playing.
  # (It used to say "after the nightly restart"; no script here registers one.)
  [string]$At       = '03:15',
  # Where the copy of the passphrase lands on this machine. Outside the repo
  # on purpose: it must never be committed.
  [string]$KeyOut   = "$env:USERPROFILE\Documents\thornswood-backup-key.txt",
  [switch]$RunNow,
  # Registers the task as it was before #2612, SYSTEM and Highest. The way
  # back if LOCAL SERVICE ever cannot do the job; say why on the issue.
  [switch]$AsSystem,
  [switch]$Status,
  [switch]$Remove,
  [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here '..\vps\Vps.ps1')
. (Join-Path $Here '..\vps\Send-Script.ps1')
. (Join-Path $Here 'ServiceAccount.ps1')
if (-not $VpsUser) { $VpsUser = Get-ThornswoodVpsUser }
if (-not $VpsHost) { $VpsHost = Get-ThornswoodVpsAddress }

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

$target = "$VpsUser@$VpsHost"
$ssh = @('-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes')
foreach ($t in 'ssh', 'scp') {
  if (-not (Get-Command $t -ErrorAction SilentlyContinue)) {
    Die "$t is not on PATH. Windows ships it: Settings, Apps, Optional features, OpenSSH Client."
  }
}

function Remote($script) {
  # Send-Script.ps1 (issue #1166, the same way as #1070): a long script goes
  # on ssh's standard input (nothing of it is left on the box), and the far
  # side's exit code comes back.
  return Invoke-ThornswoodRemote -Target $target -SshArgs $ssh -Script $script
}

$script = Join-Path $Here '..\vps\vps-nightly-backup.ps1'
$keyFile = Join-Path $Root 'key.txt'
$runner = Join-Path $Root 'vps-nightly-backup.ps1'

# ------------------------------------------------------------------ status --
if ($Status) {
  Head 'On the VPS'
  Remote @"
`$ErrorActionPreference = 'SilentlyContinue'
if (Test-Path '$runner') { 'script    ' + (Get-Item '$runner').LastWriteTime } else { 'script    NOT THERE' }
# Length only. The passphrase itself is never printed by anything here.
if (Test-Path '$keyFile') { 'passphrase present, ' + (Get-Item '$keyFile').Length + ' bytes' } else { 'passphrase NOT THERE, so encrypted backups cannot run' }
`$t = Get-ScheduledTask -TaskName '$TaskName' -EA SilentlyContinue
if (`$t) {
  `$i = Get-ScheduledTaskInfo -TaskName '$TaskName'
  'task      ' + `$t.State + ', last ran ' + `$i.LastRunTime + ' result ' + `$i.LastTaskResult
  'next      ' + `$i.NextRunTime
} else { 'task      NOT REGISTERED' }
`$f = Get-ChildItem '$Root' -File -EA SilentlyContinue | Where-Object { `$_.Name -like 'thornswood-*.zip*' } | Sort-Object Name -Descending
'backups   ' + @(`$f).Count
foreach (`$b in (`$f | Select-Object -First 12)) { '  ' + `$b.Name + '  ' + [math]::Round(`$b.Length/1MB,2) + ' MB  ' + `$b.LastWriteTime }
if (Test-Path '$Root\backup.log') { ''; '--- backup.log, last 12 ---'; Get-Content '$Root\backup.log' -Tail 12 }
"@ | ForEach-Object { Say "  $_" }
  Write-Host ''
  if (-not $NoPause) { [void](Read-Host 'Enter to close') }
  exit 0
}

# ------------------------------------------------------------------ remove --
if ($Remove) {
  Head 'Removing the task'
  Say '  The backups themselves and the passphrase are left alone.' 'DarkGray'
  Remote @"
Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false -EA SilentlyContinue
if (Get-ScheduledTask -TaskName '$TaskName' -EA SilentlyContinue) { 'STILL THERE' } else { 'task removed' }
"@ | ForEach-Object { Say "  $_" }
  Write-Host ''
  if (-not $NoPause) { [void](Read-Host 'Enter to close') }
  exit 0
}

# ----------------------------------------------------------------- install --
if (-not (Test-Path -LiteralPath $script)) { Die "There is no vps-nightly-backup.ps1 next to this script." }

Head 'Checking it parses before sending it'
$errs = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$null, [ref]$errs)
if ($errs -and $errs.Count) { $errs | Select-Object -First 5 | ForEach-Object { Say ('  ' + $_.Message) 'Red' }; Die 'vps-nightly-backup.ps1 does not parse. Nothing was sent.' }
Say '  vps-nightly-backup.ps1 parses' 'Green'

Head 'Sending it up'
# The folder holds the passphrase and every backup, and the backups hold every
# secret on the box. Made under C:\, it would inherit the rule that lets
# BUILTIN\Users read it, and every service account there is in Users (issue
# #1173). So it takes nothing from C:\: SYSTEM,
# Administrators, and whoever runs this (Administrator over ssh); the task's
# own SID is added once it is registered (#2612). Any other
# rule set on it by name, a deny for the build runner, stays. Every run, so a
# box set up before this is put right by the next one.
$locked = Remote @"
if (-not (Test-Path '$Root')) { [void](New-Item -ItemType Directory -Path '$Root' -Force) }
try {
  `$broad = @('S-1-1-0', 'S-1-5-11', 'S-1-5-32-545', 'S-1-3-0')
  `$acl = Get-Acl -LiteralPath '$Root'
  `$acl.SetAccessRuleProtection(`$true, `$false)
  foreach (`$r in @(`$acl.GetAccessRules(`$true, `$false, [Security.Principal.SecurityIdentifier]))) {
    if (`$broad -contains `$r.IdentityReference.Value) { [void]`$acl.RemoveAccessRuleSpecific(`$r) }
  }
  foreach (`$s in @('S-1-5-18', 'S-1-5-32-544', [Security.Principal.WindowsIdentity]::GetCurrent().User.Value)) {
    `$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier(`$s)), 'FullControl', 'ContainerInherit, ObjectInherit', 'None', 'Allow')))
  }
  # Only the access rules are written back (issue #1120).
  (Get-Item -LiteralPath '$Root' -Force).SetAccessControl(`$acl)
  'LOCKED'
} catch { 'COULD NOT LOCK: ' + `$_.Exception.Message }
"@
if ("$locked" -notmatch 'LOCKED') { Die ("could not lock $Root to SYSTEM and Administrators: " + "$locked" + '. Nothing was sent.') }
Say "  $Root is SYSTEM's and Administrators' only" 'Green'
Invoke-ThornswoodNative { & scp @ssh $script "${target}:$($Root.Replace('\','/'))/vps-nightly-backup.ps1" }
if ($LASTEXITCODE -ne 0) { Die 'scp failed.' }
Say "  $runner" 'Green'

Head 'The passphrase'
# A new box, and this machine already has the passphrase every backup so far
# was made with: that one goes up, rather than the box making its own. A new
# one there would leave this machine's copy unable to open anything the new
# box takes, and the "already a copy here" below would keep it that way
# without a word (issue #454). Sent as a file, never on a command line.
$there = Remote "if (Test-Path '$keyFile') { 'KEY THERE' } else { 'KEY NONE' }"
if ("$there" -match 'KEY NONE' -and (Test-Path -LiteralPath $KeyOut)) {
  Invoke-ThornswoodNative { & scp @ssh $KeyOut "${target}:$($keyFile.Replace('\','/'))" }
  if ($LASTEXITCODE -ne 0) { Die 'could not send the passphrase up. Nothing was registered.' }
  Say "  sent this machine's copy up from $KeyOut, so every backup opens with the same file" 'Green'
}
$made = Remote @"
if (Test-Path '$keyFile') {
  'already there, left alone'
} else {
  # Made on the box, out of the system random number generator, and written
  # once. It is not printed here and it is not in the task definition.
  `$b = New-Object byte[] 48
  ([System.Security.Cryptography.RandomNumberGenerator]::Create()).GetBytes(`$b)
  [IO.File]::WriteAllText('$keyFile', [Convert]::ToBase64String(`$b))
  'made a new one'
}
"@
$made | ForEach-Object { Say "  $_" }

if (-not (Test-Path -LiteralPath $KeyOut)) {
  Say '  Copying it down to this machine, because a passphrase that only lives' 'DarkGray'
  Say '  on the box is no use the day the box is what you lost.' 'DarkGray'
  Invoke-ThornswoodNative { & scp @ssh "${target}:$($keyFile.Replace('\','/'))" $KeyOut }
  if ($LASTEXITCODE -ne 0) { Say '  could not copy it down. Do that before you rely on any of this.' 'Red' }
  else { Say "  $KeyOut" 'Green' }
} else {
  Say "  There is already a copy at $KeyOut, so that was left alone." 'DarkGray'
}

Head 'Registering the task'
# Issue #2612. LOCAL SERVICE, Limited, with a SID of the task's own, not
# SYSTEM: the task reads the service folders and writes only its own, and
# stops, starts and installs nothing. Every grant names that SID, never
# LOCAL SERVICE, which the game, voice and Caddy tasks run as too (#2578)
# and which must not read the backups or the passphrase. When the SID or a
# grant cannot be made the task goes back on SYSTEM and says so. -AsSystem
# registers it as it was, and is the way back.
$sources = @('C:\Thornswood-Server', 'C:\Thornswood-Server-Dev', 'C:\Thornswood-Docs', 'C:\Thornswood-Bot',
             'C:\Thornswood-Caddy', 'C:\Thornswood-Voice', 'C:\Thornswood-Deletions')
$registered = @(Remote @"
`$a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File "$runner"'
$(Get-ThornswoodServiceAccountScript)
`$t = New-ScheduledTaskTrigger -Daily -At '$At'
`$s = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd -ExecutionTimeLimit (New-TimeSpan -Hours 1)
`$asSystem = `$$([bool]$AsSystem)
# The fail-safe, before the task is touched: nothing broad, and not LOCAL
# SERVICE as a whole, may read the backups or the passphrase.
`$bad = @(Test-ThornswoodServiceCannotReach @('$Root', '$keyFile'))
if (`$bad.Count) { foreach (`$b in `$bad) { 'FAIL-SAFE ' + `$b } }
else {
  Register-ScheduledTask -TaskName '$TaskName' -Action `$a -Trigger `$t -Principal (New-ThornswoodServicePrincipal -AsSystem:`$asSystem) -Settings `$s -Force | Out-Null
  if (`$asSystem) { 'on SYSTEM, Highest, as -AsSystem asked' }
  else {
    try {
      `$sid = Get-ThornswoodTaskSid '$TaskName'
      if (-not `$sid) { throw 'the task has no SID of its own' }
      `$who = New-Object Security.Principal.SecurityIdentifier(`$sid)
      `$tree = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
      `$acl = Get-Acl -LiteralPath '$Root'
      `$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(`$who, 'FullControl', `$tree, 'None', 'Allow')))
      Set-ThornswoodServiceAcl '$Root' `$acl
      'full control of $Root'
      foreach (`$src in @('$($sources -join "', '")')) {
        if (-not (Test-Path -LiteralPath `$src)) { continue }
        # The folder, and every folder under it that takes no rules from
        # above (a server's private, which its installer locks).
        `$dirs = @(Get-Item -LiteralPath `$src -Force) + @(Get-ChildItem -LiteralPath `$src -Directory -Recurse -Force -EA SilentlyContinue |
                   Where-Object { `$_.FullName -notmatch '\\node_modules(\\|`$)' -and (Get-Acl -LiteralPath `$_.FullName).AreAccessRulesProtected })
        foreach (`$d in `$dirs) {
          `$r = Get-Acl -LiteralPath `$d.FullName
          `$r.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(`$who, 'ReadAndExecute', `$tree, 'None', 'Allow')))
          Set-ThornswoodServiceAcl `$d.FullName `$r
        }
        'read ' + `$src + ' (' + `$dirs.Count + ' folder(s) given the rule)'
      }
      'on LOCAL SERVICE, Limited, as ' + `$sid
    } catch {
      Register-ScheduledTask -TaskName '$TaskName' -Action `$a -Trigger `$t -Principal (New-ThornswoodServicePrincipal -AsSystem) -Settings `$s -Force | Out-Null
      'BACK ON SYSTEM: ' + `$_.Exception.Message
    }
  }
}
`$x = Get-ScheduledTask -TaskName '$TaskName' -EA SilentlyContinue
if (`$x) { 'registered, ' + `$x.State + ', next ' + (Get-ScheduledTaskInfo -TaskName '$TaskName').NextRunTime } else { 'REGISTER FAILED' }
"@)
$registered | ForEach-Object { Say "  $_" }
if ("$registered" -match 'FAIL-SAFE') { Die "$Root can be read by more than it should, so the task was left as it was. Fix that and run this again." }

if ($RunNow) {
  Head 'Taking one now'
  Remote @"
Start-ScheduledTask -TaskName '$TaskName'
Start-Sleep -Seconds 45
Get-Content '$Root\backup.log' -Tail 20 -EA SilentlyContinue
"@ | ForEach-Object { Say "  $_" }
}

Head 'What is left to do'
Say '  1. Put the passphrase where you keep the server password. It is at' 'DarkGray'
Say "     $KeyOut on this machine. Losing it makes every backup noise." 'DarkGray'
Say '  2. Run .\scripts\vps\Fetch-Backups.ps1 -Schedule once, so this machine pulls' 'DarkGray'
Say '     them off the box every day. A backup only on the server is not a backup.' 'DarkGray'
Say '  3. Restore one, once, following docs\RESTORING.md, and write the date' 'DarkGray'
Say '     in it. Until that has been done none of this is known to work.' 'DarkGray'
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
