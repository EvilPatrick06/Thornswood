<#
  test-server-task-priority.ps1

      pwsh -NoProfile -File .\tests\test-server-task-priority.ps1

  The game server's scheduled task starts it at normal priority: normal for
  the processor, the disk and memory, the same as a service on the box.

  WHY. The first-move stall: the server stopped for seconds, on 5 October for
  48 s, when somebody first entered a cell. The kernel trace of 4 October
  17:19 (logs\dev\stall-trace-20261004-173319) has the dev server's main
  thread reading its own memory back from pagefile.sys at low I/O priority,
  24 ms a read on average where normal priority reads on the same disk took a
  median of 0.1 to 0.5 ms: 91 such reads made a login take 1.9 s, 51 the 2.1 s
  after a move into WhiterunWorld. The low priority came from the task.
  Install-ThornswoodServer.ps1 registered it without -Priority, Task
  Scheduler's default is 7, and on the VPS on 5 October both game servers ran
  BelowNormal with I/O priority 1 and memory priority 2, under the build
  runners, the bot and lsass at Normal, 2 and 5.

  HOW.
    1. Read, not run, wherever PowerShell runs: the installer is parsed, its
       one New-ScheduledTaskSettingsSet found and the -Priority it passes read
       (none is 7, the default every Thornswood task on the VPS shows). It
       must be 4 to 6, the band Microsoft's table starts as
       NORMAL_PRIORITY_CLASS.
    2. On Windows, that same call is run for real (it only builds the
       settings; nothing is registered by it), and a task with those settings
       and a made-up name is registered. Its principal is the installer's
       own call run for real (SYSTEM, as a service) when this shell is
       elevated, and otherwise the person running this, logged on
       interactively, so no admin and no password. Its action has the
       installer's shape, cmd.exe /c starting a program, so what is measured
       is cmd's child, as node is. It is started, and that process is asked
       what Windows gave it: priority class (GetPriorityClass), I/O priority
       (NtQueryInformationProcess, ProcessIoPriority) and memory priority
       (GetProcessInformation, ProcessMemoryPriority). They must be Normal, 2
       and 5, what the VPS measured for its services. The task and its two
       processes are removed again whatever happens, and the test checks they
       are gone. Where a task cannot be registered or does not start for this
       account (a build runner's service account has no session to start it
       in), this part says SKIP and why.

  -Installer reads another copy of the installer, so the same test runs on the
  one from before this change:

      git show 2c872310:scripts/deploy/Install-ThornswoodServer.ps1 > $env:TEMP\install-before.ps1
      pwsh -NoProfile -File .\tests\test-server-task-priority.ps1 -Installer $env:TEMP\install-before.ps1

  Registers and removes one task named Thornswood priority harness <guid> (for
  SYSTEM when elevated, else for the account running it) and stops the
  cmd.exe and Windows PowerShell it started; writes nothing else.
#>
[CmdletBinding()]
param([string]$Installer)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, the repository is one folder up.
$Repo = Split-Path -Parent $Here
if (-not $Installer) { $Installer = [IO.Path]::Combine($Repo, 'scripts', 'deploy', 'Install-ThornswoodServer.ps1') }
$Installer = [IO.Path]::GetFullPath($Installer)

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Done {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail) { exit 1 }
    exit 0
}

# ---- 1. read, not run ------------------------------------------------------------
Write-Host "installer: $Installer"
$t = $null; $e = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($Installer, [ref]$t, [ref]$e)
Yes 'the installer parses' (-not $e -or $e.Count -eq 0)
$calls = @($ast.FindAll({ param($n)
    $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'New-ScheduledTaskSettingsSet' }, $true))
Yes 'the installer builds the server task''s settings in one place' ($calls.Count -eq 1)
if ($calls.Count -ne 1) { Done }
$call = $calls[0]

# The -Priority the call passes: a number written in it, or Task Scheduler's
# default of 7 when there is none. Anything else (a variable, an expression)
# is reported as it is written and fails below, because it cannot be read here.
$asked = 7
$how = 'none passed, so Task Scheduler''s default'
$el = $call.CommandElements
for ($i = 1; $i -lt $el.Count; $i++) {
    $p = $el[$i]
    if ($p -is [System.Management.Automation.Language.CommandParameterAst] -and $p.ParameterName -eq 'Priority') {
        $arg = $p.Argument
        if (-not $arg -and $i + 1 -lt $el.Count) { $arg = $el[$i + 1] }
        if ($arg -is [System.Management.Automation.Language.ConstantExpressionAst] -and $arg.Value -is [int]) {
            $asked = [int]$arg.Value; $how = 'passed as -Priority ' + $asked
        } else {
            $asked = $null; $how = 'passed as ' + $(if ($arg) { $arg.Extent.Text } else { 'nothing' })
        }
    }
}
Yes ("the server task's priority is in the normal band 4 to 6 ($asked, $how)") ($asked -is [int] -and $asked -ge 4 -and $asked -le 6)

# ---- 2. run, through Task Scheduler ----------------------------------------------
$onWindows = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
if (-not $onWindows) { Write-Host 'SKIP  the task part needs Windows and its Task Scheduler'; Done }
Import-Module ScheduledTasks -ErrorAction SilentlyContinue
if (-not (Get-Module ScheduledTasks)) { Write-Host 'SKIP  the ScheduledTasks module did not load'; Done }

$settings = & ([scriptblock]::Create($call.Extent.Text))
Yes ('run for real, the installer''s settings carry priority ' + $settings.Priority) ($settings.Priority -eq $asked)

if (-not ('TsPriorityProbe' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class TsPriorityProbe {
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr OpenProcess(uint access, bool inherit, int id);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", SetLastError = true)] static extern uint GetPriorityClass(IntPtr h);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool GetProcessInformation(IntPtr h, int cls, ref uint info, int size);
    [DllImport("ntdll.dll")] static extern int NtQueryInformationProcess(IntPtr h, int cls, ref uint info, int size, IntPtr returned);
    // The priority class as GetPriorityClass gives it, ProcessIoPriority (33
    // for NtQueryInformationProcess) and ProcessMemoryPriority (0 for
    // GetProcessInformation). All three need only
    // PROCESS_QUERY_LIMITED_INFORMATION, which an elevated shell has on a
    // SYSTEM process. -1 means it could not be read.
    public static int[] Read(int id) {
        IntPtr h = OpenProcess(0x1000, false, id);
        if (h == IntPtr.Zero) return new int[] { -1, -1, -1 };
        try {
            uint mem = 0, io = 0;
            uint c = GetPriorityClass(h);
            int m = GetProcessInformation(h, 0, ref mem, 4) ? (int)mem : -1;
            int i = NtQueryInformationProcess(h, 33, ref io, 4, IntPtr.Zero) == 0 ? (int)io : -1;
            return new int[] { c == 0 ? -1 : (int)c, i, m };
        } finally { CloseHandle(h); }
    }
}
'@
}
function Measure-Priority([int]$id) {
    $r = [TsPriorityProbe]::Read($id)
    $classes = @{ 0x40 = 'Idle'; 0x4000 = 'BelowNormal'; 0x20 = 'Normal'; 0x8000 = 'AboveNormal'; 0x80 = 'High'; 0x100 = 'RealTime' }
    $class = if ($classes.ContainsKey($r[0])) { $classes[$r[0]] } else { '?' }
    [pscustomobject]@{ Class = $class; Io = $r[1]; Memory = $r[2] }
}
$self = Measure-Priority $PID
Write-Host ("this shell, for comparison: {0}, I/O priority {1}, memory priority {2}" -f $self.Class, $self.Io, $self.Memory)

# The installer's own principal (SYSTEM, as a service, highest) when this shell
# is elevated and may register one, so the task is the server's in everything
# but its action. Otherwise the person running this, logged on interactively,
# which needs no admin and no password.
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
$pCalls = @($ast.FindAll({ param($n)
    $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'New-ScheduledTaskPrincipal' }, $true))
if ($admin -and $pCalls.Count -eq 1) {
    $principal = & ([scriptblock]::Create($pCalls[0].Extent.Text))
    $who = 'the installer''s own principal, ' + $principal.UserId
} else {
    $me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $principal = New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive -RunLevel Limited
    $who = $me + ', logged on interactively (not elevated, so not the installer''s SYSTEM principal)'
}

# The action has the installer's shape: cmd.exe /c starting the program, so the
# process measured is cmd's child, as node is on the VPS, and what it inherits
# through cmd is measured too. Windows PowerShell sleeping stands in for node;
# the mark in its command line is how its process is found.
# Not 'Thornswood Test...': test-deploy-swaps and test-install-server clear
# away every task named 'Thornswood Test*' (names match without case), so one
# of them running beside this deletes its task half way (on 5 October a
# scratch task named that way went, "The system cannot find the file
# specified", while another worktree's test-deploy-swaps ran, and the same
# steps under another name did not), and this task beside them would fail
# their check that no real task is left (issue #1135, the same as
# test-site-account.ps1).
$name = 'Thornswood priority harness ' + [Guid]::NewGuid().ToString('N')
$mark = [Guid]::NewGuid().ToString('N')
$ps51 = [IO.Path]::Combine($env:SystemRoot, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe')
$action = New-ScheduledTaskAction -Execute ([IO.Path]::Combine($env:SystemRoot, 'System32', 'cmd.exe')) `
                                  -Argument ('/c ""' + $ps51 + '" -NoProfile -NonInteractive -Command Start-Sleep -Seconds 90 #' + $mark + '"')
$child = $null
$parent = $null
$skip = $null
Write-Host ("registering a scratch task, $name, for $who")
try {
    try {
        Register-ScheduledTask -TaskName $name -Action $action -Settings $settings -Principal $principal -ErrorAction Stop | Out-Null
    } catch {
        $skip = 'a task could not be registered for ' + $who + ': ' + $_.Exception.Message
    }
    if (-not $skip) {
        Start-ScheduledTask -TaskName $name
        for ($i = 0; $i -lt 40 -and -not $child; $i++) {
            Start-Sleep -Milliseconds 500
            $child = @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
                       Where-Object { "$($_.CommandLine)" -like "*$mark*" }) | Select-Object -First 1
        }
        if (-not $child) {
            $info = Get-ScheduledTaskInfo -TaskName $name -ErrorAction SilentlyContinue
            $skip = 'the task was registered but no process of it appeared in 20 s (last result ' + $info.LastTaskResult + '); an account with no session cannot start an interactive task'
        }
    }
    if (-not $skip) {
        $parent = Get-CimInstance Win32_Process -Filter ("ProcessId = " + [int]$child.ParentProcessId)
        $up = Measure-Priority ([int]$child.ParentProcessId)
        $got = Measure-Priority ([int]$child.ProcessId)
        Write-Host ("the task's cmd.exe:          {0}, I/O priority {1}, memory priority {2}" -f $up.Class, $up.Io, $up.Memory)
        Write-Host ("the program cmd.exe started: {0}, I/O priority {1}, memory priority {2}" -f $got.Class, $got.Io, $got.Memory)
        Yes '  the program is cmd.exe''s child, as node is on the VPS' ($parent -and $parent.Name -eq 'cmd.exe')
        Yes '  runs at the Normal priority class (BelowNormal was measured for the servers on 5 October)' ($got.Class -eq 'Normal')
        Yes '  issues its disk reads at normal I/O priority, 2 (1, low, was measured)' ($got.Io -eq 2)
        Yes '  has normal memory priority, 5 (2 was measured)' ($got.Memory -eq 5)
    }
}
finally {
    Stop-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
    if ($child) { Stop-Process -Id ([int]$child.ProcessId) -Force -ErrorAction SilentlyContinue }
    if ($parent) { Stop-Process -Id ([int]$parent.ProcessId) -Force -ErrorAction SilentlyContinue }
}
if ($skip) { Write-Host ('SKIP  ' + $skip) }
Yes 'the scratch task is gone again' (-not (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue))
if ($child) {
    Yes '  and so are its processes' (-not (Get-Process -Id ([int]$child.ProcessId), ([int]$child.ParentProcessId) -ErrorAction SilentlyContinue))
}
Done
