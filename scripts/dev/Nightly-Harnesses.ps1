<#
.SYNOPSIS
  Runs one share of the test harnesses for the nightly checks, or the ones it is named, one at a time or a few side by side, each on a clock, and always ends by naming every harness that failed and the ten slowest, inside the time it is given.

.DESCRIPTION
  Run by .github/workflows/nightly.yml once for each of its harness jobs:

      .\scripts\dev\Nightly-Harnesses.ps1 -Shard 1 -Of 2
      .\scripts\dev\Nightly-Harnesses.ps1 -Shard 2 -Of 2

  The harnesses are every tests\test-*.js and tests\test-*.ps1, then every
  voice\test-*.js, in name order. Harness number n (from 0) belongs to share
  (n mod Of) + 1, so every harness is in exactly one share and the slow ones
  spread out by name.

  ONE AT A TIME, timed, within a share. Run in parallel inside one step on
  25 September the step hung for twenty minutes where one at a time it
  finished in five and a half: every harness's output went through one pipe,
  and a process one of them left running held it open. Each harness here is
  a process of its own with its output in files of its own, so the shares run
  side by side on separate runners (separate accounts, separate TEMP), the
  way several Launcher builds jobs have run side by side since #1690; the
  harnesses take their ports from the system for that reason (#1703, #1727,
  #1755, #1973).

  EACH ON A CLOCK, and printed the moment it ends. On 26 and 28 September the
  step ran until the job's 45 minutes were up and was cancelled with nothing
  in the log, because every harness's output was held until all of them had
  finished, and one never did. Each harness gets 300 seconds; past that it
  and everything it started are killed and it is named as timed out, and the
  rest still run. A harness whose own cases take longer says so in its
  header, with its measured time beside it ("NIGHTLY CLOCK: 600 seconds"),
  and gets that clock instead, never more than 600 (#1273).

  What a harness leaves running when it ends is killed too, and named.

  INSIDE ITS TIME (#2357). The job that runs this has 45 minutes and is
  cancelled past them, and a cancelled step prints nothing more: no list of
  what failed, no ten slowest. On 12 Oct the one harness step that ran them
  all took 43 minutes of the 45. So this is given a budget (-BudgetSeconds)
  and starts a harness only when its whole clock still fits inside it. A
  harness that does not fit is not run and is named as a failure, "not run,
  out of time", so a night that runs short is red and says which ones, and
  the summary is always printed. The cure for that line is another share in
  nightly.yml, not a longer budget.

  SIDE BY SIDE WHEN ASKED (#3114). -Throttle N runs up to N harnesses at
  once, each still a process of its own with its output in files of its own
  and printed the moment it ends, so no pipe is shared and nothing one leaves
  running can hold the step. The pull request gate (build.yml, "Run the gate
  harnesses") runs its list this way through -Only: one at a time, its 550
  harnesses took 26 of a 28 minute build on 21 Oct 2026, most of it waiting
  on timers and child processes rather than working. Harnesses side by side
  share the runner's account, so its TEMP, its profile and the checkout. One
  that writes where another reads says so in its header, with why
  ("RUNS ALONE: it builds the launcher into the checkout's out folder"), and
  runs after the rest with nothing of this run beside it.

  On Windows each harness is in a job object of its own, so the summary also
  says how much processor time the harnesses and all their children used and
  how many processes they started, and the machine's processor is read over
  the whole run. Those are the numbers -Throttle is set from: the box's six
  cores are shared by four builds at once (#2994).

  NAMED HARNESSES ON DEMAND (#2970). .github/workflows/harnesses.yml runs
  the harnesses somebody names, on the same Windows runners and the same
  way, so a harness that needs Windows PowerShell is run from a cloud
  session by dispatching that workflow, with no login on the box:

      .\scripts\dev\Nightly-Harnesses.ps1 -Only 'test-deploy-swaps.ps1 voice/test-most.js'

  -Only takes the names as the nightly prints them, split by spaces or
  commas, and runs those in place of a share. A name that is no harness here
  is refused before anything runs (exit 2), so a typo is never a green run.

  tests\test-nightly-harnesses.ps1 runs this against stand-in harnesses.

.PARAMETER Shard
  Which share to run, from 1.

.PARAMETER Of
  How many shares there are. nightly.yml passes the length of its matrix.

.PARAMETER BudgetSeconds
  How long this may take in all. A harness starts only when the time used so
  far plus its clock is no more than this. nightly.yml gives 2400 seconds of a
  45 minute job.

.PARAMETER Only
  Harness names to run in place of a share, split by spaces or commas
  (test-x.ps1, test-y.js, voice/test-z.js). Every one must be a harness
  here, or nothing runs and the exit is 2.

.PARAMETER Throttle
  How many harnesses run at once, 1 to 16. 1, one at a time, unless asked.

.PARAMETER Root
  The repository whose harnesses run. The one this script is in, unless a
  test points it at a copy.

.PARAMETER OutDir
  Where each harness's output is kept while it runs. harness-out under the
  runner's temp folder, or under TEMP off a runner.
#>
[CmdletBinding()]
param(
    [int]$Shard = 1,
    [int]$Of = 1,
    [int]$BudgetSeconds = 2400,
    [string]$Only = '',
    [int]$Throttle = 1,
    [string]$Root = '',
    [string]$OutDir = ''
)

$ErrorActionPreference = 'Stop'
if ($Of -lt 1 -or $Shard -lt 1 -or $Shard -gt $Of) { Write-Host "::error::-Shard $Shard -Of $Of names no share"; exit 2 }
if ($Throttle -lt 1 -or $Throttle -gt 16) { Write-Host "::error::-Throttle $Throttle is not 1 to 16"; exit 2 }
if (-not $Root) { $Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$Root = [IO.Path]::GetFullPath($Root)
if (-not $OutDir) {
    $base = $(if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() })
    $OutDir = Join-Path $base ('harness-out-' + $Shard)
}

$PER_HARNESS = 300
$MAX_CLOCK = 600
function Head-Of($path) {
    $head = [IO.File]::ReadAllText($path)
    if ($head.Length -gt 8000) { $head = $head.Substring(0, 8000) }
    $head
}
function Clock-Of($head) {
    $m = [regex]::Match($head, '(?im)^[\s#/*<]*NIGHTLY CLOCK:\s*(\d+) seconds')
    if ($m.Success) { [Math]::Min([int]$m.Groups[1].Value, $MAX_CLOCK) } else { $PER_HARNESS }
}
function Alone-Of($head) { [regex]::IsMatch($head, '(?im)^[\s#/*<]*RUNS ALONE:\s*\S') }

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
# An empty file for stdin: no harness reads it, and one that tried would
# otherwise wait on the runner's for ever.
$nothing = Join-Path $OutDir 'stdin.empty'
Set-Content -Path $nothing -Value $null -NoNewline

# On Windows each harness runs in a job object of its own (#3114). Every
# process it starts is in that job however it was started and whether or not
# its parent is still there, so what it left running is the job's list, read
# once, and the job's accounting is the processor time the harness and all of
# its children used and how many processes it started. Walking parent ids
# from the harness's own id, which this did before, misses a child whose
# parent ended first, and with harnesses side by side could follow an id
# Windows had handed on to another harness's process.
#
# Off Windows (a cloud session running the harnesses, #2989) there is no job
# object, and a process whose parent ends is handed to init. There each
# harness is started with a mark of its own in its environment, which every
# process it starts inherits and no re-parenting takes away, and /proc says
# which processes hold it.
$onWindows = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
if ($onWindows) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class HarnessJob {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr CreateJobObject(IntPtr attributes, string name);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool QueryInformationJobObject(IntPtr job, int infoClass, IntPtr info, int length, IntPtr returned);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool TerminateJobObject(IntPtr job, uint exitCode);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool GetSystemTimes(out long idle, out long kernel, out long user);

    public static IntPtr Create() {
        IntPtr job = CreateJobObject(IntPtr.Zero, null);
        if (job == IntPtr.Zero) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        return job;
    }
    public static bool Assign(IntPtr job, IntPtr process) { return AssignProcessToJobObject(job, process); }
    // JOBOBJECT_BASIC_ACCOUNTING_INFORMATION (class 1): processor time in
    // 100 ns ticks, user and kernel, and the processes the job has held.
    public static long[] Accounting(IntPtr job) {
        IntPtr b = Marshal.AllocHGlobal(48);
        try {
            if (!QueryInformationJobObject(job, 1, b, 48, IntPtr.Zero)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            return new long[] { Marshal.ReadInt64(b, 0) + Marshal.ReadInt64(b, 8), Marshal.ReadInt32(b, 36) };
        } finally { Marshal.FreeHGlobal(b); }
    }
    // JOBOBJECT_BASIC_PROCESS_ID_LIST (class 3): the processes in it now.
    public static long[] Pids(IntPtr job) {
        int max = 4096, size = 8 + IntPtr.Size * max;
        IntPtr b = Marshal.AllocHGlobal(size);
        try {
            if (!QueryInformationJobObject(job, 3, b, size, IntPtr.Zero)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            int n = Marshal.ReadInt32(b, 4);
            long[] ids = new long[n];
            for (int i = 0; i < n; i++) ids[i] = Marshal.ReadIntPtr(b, 8 + IntPtr.Size * i).ToInt64();
            return ids;
        } finally { Marshal.FreeHGlobal(b); }
    }
    public static void Kill(IntPtr job) { TerminateJobObject(job, 1); }
    public static void Close(IntPtr job) { CloseHandle(job); }
    // The whole machine's processor time so far: idle, and all of it.
    public static long[] SystemTimes() {
        long idle, kernel, user;
        if (!GetSystemTimes(out idle, out kernel, out user)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        return new long[] { idle, kernel + user };
    }
}
'@
}
function Get-Marked($mark) {
    $want = 'THORNSWOOD_NIGHTLY_RUN=' + $mark
    foreach ($d in [IO.Directory]::GetDirectories('/proc')) {
        $n = [IO.Path]::GetFileName($d)
        if ($n -notmatch '^\d+$' -or [int]$n -eq $PID) { continue }
        try { $env = [Text.Encoding]::Latin1.GetString([IO.File]::ReadAllBytes($d + '/environ')) }
        catch { continue <# it ended while being listed, or is not ours to read: neither is a harness's #> }
        if ($env.Split([char]0) -notcontains $want) { continue }
        $comm = ''
        try { $comm = [IO.File]::ReadAllText($d + '/comm').Trim() } catch { $comm = '(ended)' }
        [pscustomobject]@{ Id = [int]$n; Name = $comm }
    }
}

# The machine's processor, busy, as a share of all its cores between two
# readings: GetSystemTimes on Windows, the cpu line of /proc/stat elsewhere.
function Read-Cpu {
    if ($onWindows) { $t = [HarnessJob]::SystemTimes(); return @{ Idle = $t[0]; All = $t[1] } }
    $f = @(([IO.File]::ReadAllLines('/proc/stat')[0] -split '\s+') | Select-Object -Skip 1 | Where-Object { $_ } | ForEach-Object { [long]$_ })
    $all = 0L; foreach ($v in @($f | Select-Object -First 8)) { $all += $v }
    @{ Idle = $f[3] + $f[4]; All = $all }
}
function Busy-Between($a, $b) {
    $d = $b.All - $a.All
    if ($d -le 0) { return 0 }
    [Math]::Round(100.0 * (1 - ($b.Idle - $a.Idle) / $d), 1)
}

# Start-Process joins -ArgumentList with spaces and quotes nothing, so a path
# is quoted here. $p.Handle is read at once because without it ExitCode comes
# back empty once the process is gone.
function Start-One($t) {
    $file = $t.Name -replace '[\\/]', '_'
    $o = Join-Path $OutDir ($file + '.out'); $e = Join-Path $OutDir ($file + '.err')
    $mark = [Guid]::NewGuid().ToString('N')
    if ($t.File.Extension -eq '.js') { $exe = 'node'; $argList = @('"' + $t.File.FullName + '"') }
    else { $exe = 'pwsh'; $argList = @('-NoProfile', '-File', ('"' + $t.File.FullName + '"')) }
    if (-not $onWindows) { $env:THORNSWOOD_NIGHTLY_RUN = $mark }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $p = Start-Process -FilePath $exe -ArgumentList $argList -NoNewWindow -PassThru -WorkingDirectory $Root `
               -RedirectStandardInput $nothing -RedirectStandardOutput $o -RedirectStandardError $e
    } finally { Remove-Item Env:\THORNSWOOD_NIGHTLY_RUN -ErrorAction SilentlyContinue }
    $null = $p.Handle
    $job = [IntPtr]::Zero
    if ($onWindows) {
        # A harness spends its first few hundred milliseconds starting node
        # or pwsh before it can start anything of its own, so it is in its
        # job before its first child.
        # One that has already ended by then started nothing either.
        $job = [HarnessJob]::Create()
        if (-not [HarnessJob]::Assign($job, $p.Handle)) {
            $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            [HarnessJob]::Close($job); $job = [IntPtr]::Zero
            if (-not $p.HasExited) { throw ("could not put {0} in a job of its own (Windows error {1})" -f $t.Name, $err) }
        }
    }
    [pscustomobject]@{ T = $t; P = $p; Job = $job; Mark = $mark; Sw = $sw; Out = $o; Err = $e; Ended = $p.WaitForExitAsync() }
}

function Finish-One($r, [bool]$timedOut) {
    $t = $r.T; $p = $r.P
    $left = @()
    $cpu = $null; $procs = $null
    if ($onWindows -and $r.Job -ne [IntPtr]::Zero) {
        if ($timedOut) { [HarnessJob]::Kill($r.Job); $null = $p.WaitForExit(10000) }
        $acct = [HarnessJob]::Accounting($r.Job)
        $ids = @([HarnessJob]::Pids($r.Job) | Where-Object { $_ -ne $p.Id })
        foreach ($id in $ids) {
            $q = Get-Process -Id $id -ErrorAction SilentlyContinue
            if ($q) { $left += $q.ProcessName }
        }
        if ($ids.Count) { [HarnessJob]::Kill($r.Job) }
        [HarnessJob]::Close($r.Job)
        $cpu = [Math]::Round($acct[0] / 1e7, 1); $procs = [int]$acct[1]
    } elseif (-not $onWindows) {
        if ($timedOut) {
            foreach ($q in @(Get-Marked $r.Mark)) { Stop-Process -Id $q.Id -Force -ErrorAction SilentlyContinue }
            $null = $p.WaitForExit(10000)
        }
        $l = @(Get-Marked $r.Mark | Where-Object { $_.Id -ne $p.Id })
        foreach ($q in $l) { Stop-Process -Id $q.Id -Force -ErrorAction SilentlyContinue }
        $left = @($l | ForEach-Object { $_.Name })
    }
    $code = if ($timedOut) { -1 } else { $p.ExitCode }
    $secs = [Math]::Round($r.Sw.Elapsed.TotalSeconds, 1)
    $said = @()
    if ($t.Clock -ne $PER_HARNESS) { $said += 'on a ' + $t.Clock + ' s clock it names' }
    if ($null -ne $cpu) { $said += ('{0}s of processor in {1} process(es)' -f $cpu, $procs) }
    Write-Host ("--- {0}  ({1}s{2})" -f $t.Name, $secs, $(if ($said.Count) { ', ' + ($said -join ', ') } else { '' }))
    foreach ($f in $r.Out, $r.Err) { if (Test-Path $f) { $txt = Get-Content -Raw $f; if ($txt) { Write-Host $txt.TrimEnd() } } }
    $path = $t.File.FullName
    if ($timedOut) { Write-Host ("::error file={0}::harness timed out after {1}s and was killed" -f $path, $t.Clock) }
    elseif ($code -ne 0) { Write-Host ("::error file={0}::harness failed (exit {1})" -f $path, $code) }
    if ($left.Count) { Write-Host ("::warning file={0}::harness left {1} process(es) running when it ended, now killed: {2}" -f $path, $left.Count, ($left -join ', ')) }
    [pscustomobject]@{ Name = $t.Name; Path = $path; Code = $code; TimedOut = $timedOut; Secs = $secs; Cpu = $cpu; Procs = $procs }
}

# Every harness, in one order every share agrees on.
$every = @()
$tests = Join-Path $Root 'tests'
if (Test-Path -LiteralPath $tests) {
    $every += @(Get-ChildItem -LiteralPath $tests -File | Where-Object { $_.Name -like 'test-*.js' -or $_.Name -like 'test-*.ps1' } |
                Sort-Object Name | ForEach-Object { [pscustomobject]@{ Name = $_.Name; File = $_ } })
}
$voice = Join-Path $Root 'voice'
if (Test-Path -LiteralPath $voice) {
    $every += @(Get-ChildItem -LiteralPath $voice -Filter 'test-*.js' -File | Sort-Object Name |
                ForEach-Object { [pscustomobject]@{ Name = 'voice/' + $_.Name; File = $_ } })
}
if ($Only.Trim()) {
    $asked = @($Only -split '[\s,]+' | Where-Object { $_ } | Select-Object -Unique)
    $known = @{}; foreach ($t in $every) { $known[$t.Name] = $true }
    $unknown = @($asked | Where-Object { -not $known.ContainsKey($_) })
    if ($unknown.Count) { Write-Host ("::error::no such harness here, so nothing was run: " + ($unknown -join ', ')); exit 2 }
    $want = @{}; foreach ($n in $asked) { $want[$n] = $true }
    $mine = @($every | Where-Object { $want.ContainsKey($_.Name) })
    $names = $(if ($mine.Count -le 20) { ': ' + (@($mine | ForEach-Object { $_.Name }) -join ', ') } else { '' })
    Write-Host ("the {0} harness(es) asked for, of the {1}, {2} s to run them in{3}" -f $mine.Count, $every.Count, $BudgetSeconds, $names)
} else {
    $mine = @(for ($i = 0; $i -lt $every.Count; $i++) { if (($i % $Of) -eq ($Shard - 1)) { $every[$i] } })
    Write-Host ("share {0} of {1}: {2} of the {3} harnesses, {4} s to run them in" -f $Shard, $Of, $mine.Count, $every.Count, $BudgetSeconds)
}

# The order they start in: those that share nothing first, in name order, as
# many at once as -Throttle; then each one whose header says RUNS ALONE, with
# nothing else of this run beside it.
$order = @(foreach ($t in $mine) {
    $head = Head-Of $t.File.FullName
    [pscustomobject]@{ Name = $t.Name; File = $t.File; Clock = (Clock-Of $head); Alone = (Alone-Of $head) }
})
$order = @(@($order | Where-Object { -not $_.Alone }) + @($order | Where-Object { $_.Alone }))
if ($Throttle -gt 1) {
    Write-Host ("{0} at a time; {1} run alone, after the rest" -f $Throttle, @($order | Where-Object { $_.Alone }).Count)
}

$clockAll = [Diagnostics.Stopwatch]::StartNew()
$cpuFirst = Read-Cpu; $cpuLast = $cpuFirst; $cpuAt = 0.0; $cpuPeak = 0.0
$results = @()
$notRun = @()
$running = New-Object System.Collections.ArrayList
$next = 0
while ($next -lt $order.Count -or $running.Count) {
    while ($next -lt $order.Count -and $running.Count -lt $Throttle) {
        $t = $order[$next]
        if ($running.Count -and ($t.Alone -or $running[0].T.Alone)) { break }
        $next++
        if ($clockAll.Elapsed.TotalSeconds + $t.Clock -gt $BudgetSeconds) {
            $notRun += $t.Name
            Write-Host ("::error file={0}::not run, out of time: {1}s used of {2}s and its clock is {3}s" -f $t.File.FullName, [Math]::Round($clockAll.Elapsed.TotalSeconds), $BudgetSeconds, $t.Clock)
            continue
        }
        [void]$running.Add((Start-One $t))
        if ($t.Alone) { break }
    }
    if (-not $running.Count) { continue }

    # Sleep until one of them ends or the nearest clock is up, whichever is first.
    $soonest = [double]::MaxValue
    foreach ($r in $running) { $soonest = [Math]::Min($soonest, $r.T.Clock * 1000 - $r.Sw.Elapsed.TotalMilliseconds) }
    $tasks = [Threading.Tasks.Task[]]@($running | ForEach-Object { $_.Ended })
    $null = [Threading.Tasks.Task]::WaitAny($tasks, [int][Math]::Max(0, [Math]::Ceiling($soonest)))

    foreach ($r in @($running)) {
        if ($r.P.HasExited) { $results += Finish-One $r $false; $running.Remove($r) }
        elseif ($r.Sw.Elapsed.TotalSeconds -ge $r.T.Clock) { $results += Finish-One $r $true; $running.Remove($r) }
    }
    if ($clockAll.Elapsed.TotalSeconds - $cpuAt -ge 10) {
        $now = Read-Cpu
        $cpuPeak = [Math]::Max($cpuPeak, (Busy-Between $cpuLast $now))
        $cpuLast = $now; $cpuAt = $clockAll.Elapsed.TotalSeconds
    }
}
$cpuAll = Busy-Between $cpuFirst (Read-Cpu)
$cpuPeak = [Math]::Max($cpuPeak, $cpuAll)

$failed = @($results | Where-Object { $_.Code -ne 0 } | ForEach-Object { if ($_.TimedOut) { $_.Name + ' (timed out)' } else { $_.Name } })
Write-Host ''
Write-Host ('slowest: ' + ((@($results | Sort-Object Secs -Descending | Select-Object -First 10) | ForEach-Object { '{0} {1}s' -f $_.Name, $_.Secs }) -join ', '))
if ($onWindows) {
    Write-Host ('most processor: ' + ((@($results | Sort-Object Cpu -Descending | Select-Object -First 10) | ForEach-Object { '{0} {1}s' -f $_.Name, $_.Cpu }) -join ', '))
    Write-Host ('most processes: ' + ((@($results | Sort-Object Procs -Descending | Select-Object -First 10) | ForEach-Object { '{0} {1}' -f $_.Name, $_.Procs }) -join ', '))
    Write-Host ('processor used by all of them: {0}s in {1} processes' -f [Math]::Round(($results | Measure-Object Cpu -Sum).Sum), ($results | Measure-Object Procs -Sum).Sum)
}
Write-Host ('all of them, added up: {0}s, in {1}s' -f [Math]::Round(($results | Measure-Object Secs -Sum).Sum), [Math]::Round($clockAll.Elapsed.TotalSeconds))
Write-Host ('the machine''s {0} cores while they ran: {1}% busy on average, {2}% at most over 10 s' -f [Environment]::ProcessorCount, $cpuAll, $cpuPeak)
if ($notRun.Count) {
    Write-Host ''
    if ($Only.Trim()) { Write-Host ("{0} harness(es) not run, out of the {1} s; name fewer in one run: {2}" -f $notRun.Count, $BudgetSeconds, ($notRun -join ', ')) }
    else { Write-Host ("{0} harness(es) not run, out of this share's {1} s; nightly.yml needs another share: {2}" -f $notRun.Count, $BudgetSeconds, ($notRun -join ', ')) }
}
if ($failed.Count) {
    Write-Host ''
    Write-Host ("{0} harness(es) failed: {1}" -f $failed.Count, ($failed -join ', '))
}
if ($failed.Count -or $notRun.Count) { exit 1 }
Write-Host 'every harness passed'
exit 0
