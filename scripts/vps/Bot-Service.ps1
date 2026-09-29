<#
  Bot-Service.ps1

  Runs the Thornswood bot as a Windows service under its own account, and
  stops and starts it by name (issue #465). Functions only, run ON the VPS as
  Administrator: Install-Bot.ps1 sends this in front of its own script, the
  way it sends Write-BotToken.ps1.

      Install-ThornswoodBotService   build the service program, put the
                                     service in place of the old loop, grant
                                     its account what the bot reads and
                                     writes, start it by name
      Restart-ThornswoodBotService   stop by name, sweep, start by name
      Get-ThornswoodServiceSid       NT SERVICE\<name>'s SID, before the
                                     service exists (sc.exe showsid agrees)

  WHY. The bot ran as SYSTEM, every right on the box that holds every secret,
  for a program that decodes images people upload (the join card) and talks to
  Discord all day. It ran under run.ps1, a PowerShell loop in the scheduled
  task 'Thornswood Bot', and nothing stopped it by name: stopping the task left
  python running, so every script that restarted the bot killed python by its
  command line, and the watchdog could not restart a hung bot at all.

  NOW. The service ThornswoodBot runs BotService.cs (built here, on the box,
  by the .NET Framework's csc), which runs python bot.py and rolls bot.log by
  size while it runs. Its account is NT SERVICE\ThornswoodBot, a virtual
  account Windows makes for the service: it has no password, so there is
  nothing to keep, rotate or send (Send-Secret.ps1 has nothing to carry), and
  it is nobody's but the bot's. It keeps one privilege, the one for walking
  folders, like the site's account (Deploy-Docs.ps1 -RunAs), because the
  impersonation right every service gets by default is the usual way from a
  service account to SYSTEM. Its rights on files are granted below and are
  the bot's own folder plus what bot.py reads, measured in bot.py on 29 Sep.

  tests\test-bot-service.ps1 runs these functions here, against stand-ins for
  the service manager and against scratch folders with the real icacls.
#>

# NT SERVICE\<name> is S-1-5-80- and the SHA-1 of the name in upper case as
# UTF-16, read as five 32 bit numbers. Worked out rather than looked up,
# because the account does not exist until the service does, and the files
# are granted before it is started.
function Get-ThornswoodServiceSid([string]$Name) {
  $sha = [Security.Cryptography.SHA1]::Create()
  try { $h = $sha.ComputeHash([Text.Encoding]::Unicode.GetBytes($Name.ToUpperInvariant())) }
  finally { $sha.Dispose() }
  $parts = @()
  for ($i = 0; $i -lt 20; $i += 4) { $parts += [BitConverter]::ToUInt32($h, $i) }
  return ('S-1-5-80-' + ($parts -join '-'))
}

# The python the service runs, by its full path, from the machine PATH as it
# is now (sshd hands out the PATH from before python was installed).
function Get-ThornswoodBotPython() {
  $env:PATH = [Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('PATH', 'User')
  $p = Get-Command python -CommandType Application -EA SilentlyContinue | Select-Object -First 1
  if ($p) { return $p.Source }
  return ''
}

# What stops the service's account running the bot, one line each, or
# nothing. A python or a library installed for one person lives under
# C:\Users\<them>, which no other account may read, so the service would
# start and fail on its first import. Install-Bot installs python for all
# users and pip then installs beside it, but a python put on by hand, or a
# pip that fell back to a user install, would not be.
function Test-ThornswoodBotPython([string]$Python) {
  # A native program's standard error is a line to read here, not a stop.
  $ErrorActionPreference = 'Continue'
  $bad = @()
  if (-not $Python -or -not (Test-Path -LiteralPath $Python)) { return @('python was not found on this box') }
  $users = '^[A-Za-z]:\\Users\\'
  if ($Python -match $users) { $bad += ('python is installed for one person, at ' + $Python + ', which the service''s account cannot read. Install it for all users.') }
  $said = @(& $Python -c 'import discord, PIL, certifi; print(discord.__file__); print(PIL.__file__); print(certifi.where())' 2>&1 | ForEach-Object { "$_".Trim() })
  if ($LASTEXITCODE -ne 0) { return ($bad + @('python cannot import discord, PIL and certifi, so the libraries did not install')) }
  foreach ($l in $said) {
    if ($l -match $users) { $bad += ('a library is installed for one person, at ' + $l + ', which the service''s account cannot read. Install requirements.txt as Administrator, for all users.') }
  }
  return $bad
}

# Builds BotService.cs with the .NET Framework's own compiler, which every
# Windows Server has. @{ Ok; Lines }.
function Build-ThornswoodBotHost([string]$Source, [string]$Out) {
  # A native program's standard error is a line to read here, not a stop.
  $ErrorActionPreference = 'Continue'
  $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
  if (-not (Test-Path -LiteralPath $csc)) { $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
  if (-not (Test-Path -LiteralPath $csc)) { return @{ Ok = $false; Lines = @('no .NET Framework compiler at ' + $csc) } }
  if (Test-Path -LiteralPath $Out) { Remove-Item -LiteralPath $Out -Force }
  $said = @(& $csc /nologo /target:exe /optimize+ ('/out:' + $Out) /r:System.ServiceProcess.dll /r:System.Web.Extensions.dll $Source 2>&1 |
            ForEach-Object { "$_" } | Where-Object { $_ -and $_ -notmatch 'C# 5|Copyright|provided as part of|LinkID' })
  return @{ Ok = ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $Out)); Lines = $said }
}

# A copy of the bot nobody's service started: one somebody ran by hand, or
# the old run.ps1 loop and its python. Either still holds the token and
# answers tickets. Only ever called with the service stopped, so anything
# left with the bot's folder on its command line is not the service's. This
# is the one place anything here looks at a command line: stopping and
# starting the bot is by the service's name.
function Stop-ThornswoodBotStrays([string]$Root) {
  $mark = $Root.TrimEnd('\') + '\'
  foreach ($p in @(Get-CimInstance Win32_Process -EA SilentlyContinue |
                   Where-Object { $_.Name -match '^(python|pythonw|powershell|cmd)' -and $_.CommandLine -and $_.ProcessId -ne $PID })) {
    if ($p.CommandLine.IndexOf($mark, [StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
    Stop-Process -Id $p.ProcessId -Force -EA SilentlyContinue
    'stopped a copy of the bot no service started, pid ' + $p.ProcessId + ' (' + $p.Name + ')'
  }
}

# The old loop, taken off once: its scheduled task, whatever it was running,
# and its two files. The service replaces all of it.
function Remove-ThornswoodBotLoop([string]$Root, [string]$Task) {
  $t = Get-ScheduledTask -TaskName $Task -EA SilentlyContinue
  if ($t) {
    Stop-ScheduledTask -TaskName $Task -EA SilentlyContinue
    Unregister-ScheduledTask -TaskName $Task -Confirm:$false -EA SilentlyContinue
    if (Get-ScheduledTask -TaskName $Task -EA SilentlyContinue) { 'COULD NOT REMOVE the old scheduled task ' + $Task }
    else { 'removed the old scheduled task ' + $Task + ', which ran the bot as SYSTEM' }
  }
  Stop-ThornswoodBotStrays $Root
  foreach ($f in 'run.ps1', 'roll-log.ps1') {
    $p = Join-Path $Root $f
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -EA SilentlyContinue; 'removed ' + $p }
  }
}

# What the service's account may touch, and nothing else of Thornswood's:
#   the bot's folder, Modify: bot.log and its rolls, heartbeat.json,
#     and the few records bot.py keeps beside itself. The same shape as
#     the site's account on its own folder.
#   service\ under it, read only and not inherited from the folder, so the
#     account cannot change the program or host.json that start it.
#   bot.env.json, read. It is protected (Install-Bot), so this is the one
#     rule on it besides SYSTEM and Administrators.
#   the watchdog's folder, read on the files in it (alerts.jsonl, what the
#     webhook already posted), and Modify on alerts-sent-bot.txt, the one file
#     there the bot writes. The webhook's own file is protected and stays out
#     of reach.
#   the site's data folder, read on the files directly in it: trouble.json,
#     inbox.json and moderation.log are what the bot reads, and the site
#     writes each through a new file, so a grant on the file itself would go
#     with the next write. That folder also holds the site's other records,
#     sessions.json among them; see the issue filed for it.
#   each game server's private\moderation.log, read, on that file only,
#     because private\ also holds door.json and its key.
# Writes back only the access rules of an ACL from Get-Acl. Set-Acl can also
# try to write the audit part, which needs SeSecurityPrivilege: Administrator
# has it, and the build runner's account does not, so on the runner Set-Acl
# refused the grant on bot.env.json (issue #1120). Nothing here changes
# auditing, so .NET is asked to persist what changed, the access rules.
function Set-ThornswoodAclAccess([string]$Path, $Acl) {
  $item = Get-Item -LiteralPath $Path -Force
  if ($PSVersionTable.PSEdition -eq 'Core') {
    if ($item -is [IO.DirectoryInfo]) { [IO.FileSystemAclExtensions]::SetAccessControl([IO.DirectoryInfo]$item, [Security.AccessControl.DirectorySecurity]$Acl) }
    else { [IO.FileSystemAclExtensions]::SetAccessControl([IO.FileInfo]$item, [Security.AccessControl.FileSecurity]$Acl) }
  } else { $item.SetAccessControl($Acl) }
}

# Given again at every install; the same rule added twice is kept once.
# Built in .NET rather than with icacls, because icacls will not name an
# account Windows cannot look up, and the service's is granted in the tests
# on a machine that has no such service.
function Grant-ThornswoodBotAccess {
  param([string]$Sid, [string]$Root, [string]$WatchRoot, [string]$DocsData, [string[]]$ModLogs = @())
  # $how: 'tree' is this folder and everything under it, 'files' the files
  # directly in this folder, '' the one file.
  function Give([string]$path, [string]$rights, [string]$how, [string]$what) {
    if (-not (Test-Path -LiteralPath $path)) { return ('not there yet, nothing granted: ' + $path) }
    $inherit = [Security.AccessControl.InheritanceFlags]::None
    $prop = [Security.AccessControl.PropagationFlags]::None
    if ($how -eq 'tree') { $inherit = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit' }
    if ($how -eq 'files') { $inherit = [Security.AccessControl.InheritanceFlags]::ObjectInherit; $prop = [Security.AccessControl.PropagationFlags]::NoPropagateInherit }
    try {
      $acl = Get-Acl -LiteralPath $path
      $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(
        (New-Object Security.Principal.SecurityIdentifier($Sid)), $rights, $inherit, $prop, 'Allow')))
      Set-ThornswoodAclAccess $path $acl
      return ('granted ' + $what + ' on ' + $path)
    } catch { return ('COULD NOT GRANT ' + $what + ' on ' + $path + ': ' + $_.Exception.Message) }
  }
  Give $Root 'Modify' 'tree' 'the bot''s account Modify'
  $svc = Join-Path $Root 'service'
  if (Test-Path -LiteralPath $svc) {
    try {
      $acl = Get-Acl -LiteralPath $svc
      $acl.SetAccessRuleProtection($true, $false)
      foreach ($r in @($acl.Access)) { [void]$acl.RemoveAccessRule($r) }
      $inherit = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
      $none = [Security.AccessControl.PropagationFlags]::None
      # SYSTEM, Administrators, and whoever runs this, which is Administrator
      # over ssh, the same three bot.env.json keeps.
      foreach ($s in @('S-1-5-18', 'S-1-5-32-544', [Security.Principal.WindowsIdentity]::GetCurrent().User.Value)) {
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(
          (New-Object Security.Principal.SecurityIdentifier($s)), 'FullControl', $inherit, $none, 'Allow')))
      }
      $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(
        (New-Object Security.Principal.SecurityIdentifier($Sid)), 'ReadAndExecute', $inherit, $none, 'Allow')))
      Set-ThornswoodAclAccess $svc $acl
      'the service program''s folder is read only to the bot''s account: ' + $svc
    } catch { 'COULD NOT LOCK ' + $svc + ': ' + $_.Exception.Message }
  }
  Give (Join-Path $Root 'bot.env.json') 'Read' '' 'the bot''s account read'
  if ($WatchRoot) {
    if (Test-Path -LiteralPath $WatchRoot) {
      Give $WatchRoot 'Read' 'files' 'the bot''s account read on the files'
      $sent = Join-Path $WatchRoot 'alerts-sent-bot.txt'
      if (-not (Test-Path -LiteralPath $sent)) { [IO.File]::WriteAllText($sent, '') }
      Give $sent 'Modify' '' 'the bot''s account Modify'
    } else { 'not there yet, nothing granted: ' + $WatchRoot + '. Run Install-Bot.ps1 again after Watch-Services.ps1 -Install' }
  }
  if ($DocsData) { Give $DocsData 'Read' 'files' 'the bot''s account read on the files' }
  foreach ($m in $ModLogs) { Give $m 'Read' '' 'the bot''s account read' }
}

# Whether the service's name is a source in the event log yet. Only
# Administrator can make one, so the install does, and the service writes to it.
function Test-ThornswoodEventSource([string]$Name) {
  return [Diagnostics.EventLog]::SourceExists($Name)
}

# host.json beside the service program: the bot's folder and the python the
# service runs. Written as UTF-8 with no mark.
function Write-ThornswoodBotHostJson([string]$Path, [string]$Root, [string]$Python) {
  $o = [ordered]@{ root = $Root; python = $Python; script = 'bot.py' }
  [IO.File]::WriteAllText($Path, ($o | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
}

# The whole switch. Everything that can fail without touching the running
# bot is done first: python checked, the program built beside the old one.
# Only then is anything stopped. @{ Ok; Lines }.
function Install-ThornswoodBotService {
  param(
    [string]$Name = 'ThornswoodBot',
    [string]$Root = 'C:\Thornswood-Bot',
    [string]$Python,
    [string]$Source,
    [string]$Task = 'Thornswood Bot',
    [string]$WatchRoot = 'C:\Thornswood-Watch',
    [string]$DocsData = 'C:\Thornswood-Docs\data',
    [string[]]$ModLogs = @('C:\Thornswood-Server\private\moderation.log', 'C:\Thornswood-Server-Dev\private\moderation.log')
  )
  # A native program's standard error is a line to read here, not a stop.
  $ErrorActionPreference = 'Continue'
  $out = @()
  $account = 'NT SERVICE\' + $Name
  $sid = Get-ThornswoodServiceSid $Name

  if (-not $Python) { $Python = Get-ThornswoodBotPython }
  $bad = @(Test-ThornswoodBotPython $Python)
  if ($bad.Count) {
    return @{ Ok = $false; Lines = @($bad | ForEach-Object { 'CANNOT SWITCH: ' + $_ }) + @('Nothing was stopped or changed.') }
  }
  $out += 'python for the service: ' + $Python

  $dir = Join-Path $Root 'service'
  if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Force -Path $dir }
  $exe = Join-Path $dir 'ThornswoodBotService.exe'
  $new = Join-Path $dir 'ThornswoodBotService.new.exe'
  # Registered bare, below. A space would make it a path Windows reads more
  # than one way, which is how a service ends up starting something else.
  if ($exe -match '\s') { return @{ Ok = $false; Lines = @('CANNOT SWITCH: the bot''s folder has a space in its path, ' + $Root + '. Nothing was stopped or changed.') } }
  $b = Build-ThornswoodBotHost $Source $new
  if (-not $b.Ok) {
    return @{ Ok = $false; Lines = $out + @('THE SERVICE PROGRAM DID NOT BUILD. Nothing was stopped or changed.') + @($b.Lines | Select-Object -First 20) }
  }
  $out += 'built the service program from ' + (Split-Path -Leaf $Source)

  # Stopped by name, then the old loop, then any copy started by hand.
  $svc = Get-Service -Name $Name -EA SilentlyContinue
  if ($svc -and "$($svc.Status)" -ne 'Stopped') {
    try { Stop-Service -Name $Name -Force -ErrorAction Stop; $out += 'stopped the service ' + $Name }
    catch { return @{ Ok = $false; Lines = $out + @('COULD NOT STOP the service ' + $Name + ': ' + $_.Exception.Message) } }
  }
  $out += @(Remove-ThornswoodBotLoop -Root $Root -Task $Task)
  $out += @(Stop-ThornswoodBotStrays $Root)

  # The new program over the old. Windows can hold a stopped service's file
  # for a moment, so it is tried for ten seconds.
  $moved = $false
  foreach ($i in 1..10) {
    try { Move-Item -LiteralPath $new -Destination $exe -Force -ErrorAction Stop; $moved = $true; break }
    catch { Start-Sleep -Seconds 1 }
  }
  if (-not $moved) { return @{ Ok = $false; Lines = $out + @('COULD NOT REPLACE ' + $exe + '. The bot is stopped. Run this again.') } }
  Write-ThornswoodBotHostJson (Join-Path $dir 'host.json') $Root $Python

  # The service. Its program path has no spaces in it, and every setting on
  # the sc.exe lines is plain, so nothing here depends on how quotes survive
  # a native command line. No password: a virtual account has none.
  if (-not $svc) {
    try {
      New-Service -Name $Name -BinaryPathName $exe -DisplayName 'Thornswood Bot' -StartupType Automatic `
        -Description 'The Thornswood Discord bot. Installed by Install-Bot.ps1; bot.log is in its folder.' -ErrorAction Stop | Out-Null
      $out += 'made the service ' + $Name
    } catch { return @{ Ok = $false; Lines = $out + @('COULD NOT MAKE the service ' + $Name + ': ' + $_.Exception.Message) } }
  }
  foreach ($c in @(
      @('config', $Name, 'binPath=', $exe, 'start=', 'auto', 'obj=', $account),
      @('sidtype', $Name, 'unrestricted'),
      @('privs', $Name, 'SeChangeNotifyPrivilege'),
      # A crash of the service program itself: started again after a minute,
      # then after five, the count forgotten after an hour. The bot's own
      # exits are the program's to handle, and a give-up is a clean stop that
      # this does not undo.
      @('failure', $Name, 'reset=', '3600', 'actions=', 'restart/60000/restart/300000'))) {
    $said = & sc.exe @c 2>&1
    if ($LASTEXITCODE -ne 0) { return @{ Ok = $false; Lines = $out + @('COULD NOT SET ' + $c[0] + ' on ' + $Name + ': ' + (($said | Out-String).Trim())) } }
  }
  $out += 'the service runs as ' + $account + ', with one privilege, and restarts itself if it crashes'

  try {
    if (-not (Test-ThornswoodEventSource $Name)) { New-EventLog -LogName Application -Source $Name -ErrorAction Stop }
    $out += 'the bot''s exits go to the Application event log as ' + $Name
  } catch { $out += 'no event log source, so exits are in bot.log only: ' + $_.Exception.Message }

  $out += @(Grant-ThornswoodBotAccess -Sid $sid -Root $Root -WatchRoot $WatchRoot -DocsData $DocsData -ModLogs $ModLogs)

  try { Start-Service -Name $Name -ErrorAction Stop; $out += 'started the service ' + $Name }
  catch { return @{ Ok = $false; Lines = $out + @('THE SERVICE DID NOT START: ' + $_.Exception.Message) } }
  $w = Get-CimInstance Win32_Service -Filter ("Name = '" + $Name + "'") -EA SilentlyContinue
  if ($w) { $out += 'service ' + $Name + ': ' + $w.State + ', as ' + $w.StartName }
  return @{ Ok = $true; Lines = $out }
}

# Stop by name, the sweep, start by name. What -CodeOnly does after sending
# the code. $null when there is no service yet, which means the full install
# has not been run on this box.
function Restart-ThornswoodBotService([string]$Name = 'ThornswoodBot', [string]$Root = 'C:\Thornswood-Bot') {
  if (-not (Get-Service -Name $Name -EA SilentlyContinue)) { return $null }
  $out = @()
  try { Stop-Service -Name $Name -Force -ErrorAction Stop; $out += 'stopped the service ' + $Name }
  catch { $out += 'COULD NOT STOP the service ' + $Name + ': ' + $_.Exception.Message }
  $out += @(Stop-ThornswoodBotStrays $Root)
  try { Start-Service -Name $Name -ErrorAction Stop; $out += 'started the service ' + $Name }
  catch { $out += 'THE SERVICE DID NOT START: ' + $_.Exception.Message }
  return $out
}
