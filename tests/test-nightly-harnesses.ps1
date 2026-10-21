<#
  test-nightly-harnesses.ps1

      pwsh -NoProfile -File .\tests\test-nightly-harnesses.ps1

  Issue #2357. The nightly's one job used 43 of its 45 minutes on 12 Oct,
  and a job cancelled at 45 prints nothing more: not the harnesses that
  failed, not the ten slowest. scripts\dev\Nightly-Harnesses.ps1 now runs the
  harnesses in shares, one job each, inside a time it is given. This runs it
  against stand-in harnesses in a scratch repository and proves:

    1. every harness is in exactly one share: two shares between them run
       each one once, and none twice;
    2. a harness that passes, one that fails, one past its clock (named in
       its header) and one that leaves a process running are each printed
       as they end, and the summary names the two that failed, the one that
       timed out as timed out, the slowest, and exits 1;
    3. a harness whose clock would not fit in what is left of the budget is
       not started, is named "not run, out of time", turns the share red,
       and the summary is still printed;
    4. nightly.yml runs it once for each share in its matrix, tells it how
       many shares the matrix has, keeps one share's failure from cancelling
       the other, and gives it a budget inside the job's minutes;
    5. -Only (#2970) runs the harnesses named, split by commas or spaces, and
       no others, refuses a name that is no harness before anything runs,
       and is red when a named one fails;
    6. harnesses.yml starts only by dispatch, reads the repository and
       nothing more, runs on the VPS runners, and hands the names to -Only
       through the environment, never pasted into a script it runs.

  Writes only into a scratch folder under TEMP, which it removes.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $Here
$script = Join-Path $repo 'scripts\dev\Nightly-Harnesses.ps1'
. (Join-Path $PSScriptRoot 'Windows.ps1')

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('ts-nightly-harnesses-' + [Guid]::NewGuid().ToString('N'))
$utf8 = New-Object Text.UTF8Encoding($false)
function Put([string]$path, [string]$text) {
    $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $path))
    [IO.File]::WriteAllText($path, $text, $utf8)
}
function Run([string]$root, [string[]]$more) {
    $out = Join-Path $work ('out-' + [Guid]::NewGuid().ToString('N'))
    $said = @(& pwsh -NoProfile -NonInteractive -File $script -Root $root -OutDir $out @more 2>&1 | ForEach-Object { "$_" })
    return @{ Code = $LASTEXITCODE; Said = ($said -join "`n") }
}
function Ran([string]$said) {
    return @([regex]::Matches($said, '(?m)^--- (\S+)  \(') | ForEach-Object { $_.Groups[1].Value })
}

try {
    # The runs need Windows: the runner finds what a harness left running
    # through Win32_Process. Off Windows they are said as not run (#2957).
    if ($OnWindows) {
        # ---- 1. the shares --------------------------------------------------------
        $a = Join-Path $work 'shares'
        foreach ($n in 'a', 'b', 'c', 'd', 'e') { Put (Join-Path $a "tests\test-$n.js") "process.exit(0);`n" }
        Put (Join-Path $a 'tests\test-f.ps1') "exit 0`n"
        Put (Join-Path $a 'tests\not-a-harness.js') "process.exit(1);`n"
        Put (Join-Path $a 'voice\test-v.js') "process.exit(0);`n"
        $r1 = Run $a @('-Shard', '1', '-Of', '2')
        $r2 = Run $a @('-Shard', '2', '-Of', '2')
        $one = @(Ran $r1.Said); $two = @(Ran $r2.Said)
        $all = @($one + $two | Sort-Object)
        $want = @('test-a.js', 'test-b.js', 'test-c.js', 'test-d.js', 'test-e.js', 'test-f.ps1', 'voice/test-v.js' | Sort-Object)
        Yes ("two shares between them run every harness once (" + ($all -join ', ') + ")") (($all -join ',') -eq ($want -join ','))
        Yes '  and no harness in both' (-not @($one | Where-Object { $two -contains $_ }).Count)
        Yes ("  each share some of them ({0} and {1})" -f $one.Count, $two.Count) ($one.Count -ge 3 -and $two.Count -ge 3)
        Yes '  a file that is not test-* is no harness' (-not ($all -contains 'not-a-harness.js'))
        Yes '  both green, each saying so' ($r1.Code -eq 0 -and $r2.Code -eq 0 -and $r1.Said -match 'every harness passed' -and $r2.Said -match 'every harness passed')
        $r = Run $a @('-Shard', '3', '-Of', '2')
        Yes "  a share that is not one of them is refused (exit $($r.Code))" ($r.Code -eq 2 -and -not (Ran $r.Said).Count)

        # ---- 2. what each kind of harness looks like ------------------------------
        $b = Join-Path $work 'kinds'
        Put (Join-Path $b 'tests\test-1-pass.js') "console.log('PASS  one thing');`nprocess.exit(0);`n"
        Put (Join-Path $b 'tests\test-2-fail.ps1') "Write-Host 'FAIL  one thing'`nexit 1`n"
        Put (Join-Path $b 'tests\test-3-hang.js') "// NIGHTLY CLOCK: 3 seconds. A stand-in that never ends.`nconsole.log('started');`nsetInterval(() => {}, 1000);`n"
        Put (Join-Path $b 'tests\test-4-leaves.js') ("const { spawn } = require('child_process');`n" +
            "const c = spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], { detached: true, stdio: 'ignore' });`n" +
            "c.unref();`nconsole.log('left one running');`nprocess.exit(0);`n")
        $r = Run $b @()
        Yes "a share with a failure is red (exit $($r.Code))" ($r.Code -eq 1)
        Yes '  every harness is printed with its time and what it said' ($r.Said -match '(?m)^--- test-1-pass\.js  \([0-9.]+s\)' -and $r.Said -match 'PASS  one thing' -and $r.Said -match 'FAIL  one thing')
        Yes '  the failed one is named where it failed' ($r.Said -match '::error file=.*?test-2-fail\.ps1::harness failed \(exit 1\)')
        Yes '  the one past its clock is killed and named, on the clock its header gives' ($r.Said -match '::error file=.*?test-3-hang\.js::harness timed out after 3s and was killed' -and $r.Said -match '--- test-3-hang\.js  \([0-9.]+s, on a 3 s clock it names\)')
        Yes '  what one left running is killed and named' ($r.Said -match '::warning file=.*?test-4-leaves\.js::harness left 1 process\(es\) running when it ended, now killed: node')
        Yes '  the summary names both that failed, the one that timed out as such' ($r.Said -match '(?m)^2 harness\(es\) failed: test-2-fail\.ps1, test-3-hang\.js \(timed out\)\s*$')
        Yes '  and the slowest' ($r.Said -match '(?m)^slowest: test-3-hang\.js ' -and $r.Said -match '(?m)^all of them, added up: \d+s, in \d+s')

        # ---- 3. the budget ----------------------------------------------------------
        $c = Join-Path $work 'budget'
        Put (Join-Path $c 'tests\test-1-first.js') "// NIGHTLY CLOCK: 10 seconds`nsetTimeout(() => process.exit(0), 3000);`n"
        Put (Join-Path $c 'tests\test-2-second.js') "// NIGHTLY CLOCK: 10 seconds`nprocess.exit(0);`n"
        Put (Join-Path $c 'tests\test-3-third.js') "// NIGHTLY CLOCK: 10 seconds`nprocess.exit(0);`n"
        $r = Run $c @('-BudgetSeconds', '12')
        Yes "with 12 s to run them in, the first (clock 10) runs and passes" ((@(Ran $r.Said) -join ',') -eq 'test-1-first.js')
        Yes '  the next two, whose 10 s would not fit after it, are not started' ($r.Said -match '::error file=.*?test-2-second\.js::not run, out of time' -and $r.Said -match '::error file=.*?test-3-third\.js::not run, out of time')
        Yes '  and are named in the summary, which is still printed' ($r.Said -match "(?m)^2 harness\(es\) not run, out of this share's 12 s; nightly\.yml needs another share: test-2-second\.js, test-3-third\.js\s*$" -and $r.Said -match '(?m)^slowest: test-1-first\.js ')
        Yes "  so the share is red though nothing that ran failed (exit $($r.Code))" ($r.Code -eq 1 -and $r.Said -notmatch 'every harness passed')
        $r = Run $c @('-BudgetSeconds', '60')
        Yes "with 60 s all three run and the share is green (exit $($r.Code))" ($r.Code -eq 0 -and (@(Ran $r.Said)).Count -eq 3)

    } else {
        Write-Host 'SKIP  the runs in 1 to 3: Nightly-Harnesses.ps1 kills what a harness leaves through Win32_Process, which only Windows has'
    }

    # ---- 4. the workflow ------------------------------------------------------
    $y = [IO.File]::ReadAllText((Join-Path $repo '.github\workflows\nightly.yml'))
    $calls = @([regex]::Matches($y, 'Nightly-Harnesses\.ps1 -Shard \$\{\{ matrix\.shard \}\} -Of (\d+) -BudgetSeconds (\d+)'))
    Yes 'nightly.yml runs Nightly-Harnesses.ps1 for the share its matrix names, once' ($calls.Count -eq 1)
    $job = [regex]::Match($y, '(?s)(?m)^  harnesses:\s*$(.*?)(?=^  [A-Za-z0-9_-]+:\s*$|\z)').Groups[1].Value
    $shards = @([regex]::Match($job, '(?m)^\s+shard:\s*\[([^\]]*)\]').Groups[1].Value -split '\s*,\s*' | Where-Object { $_ })
    $of = $(if ($calls.Count) { [int]$calls[0].Groups[1].Value } else { 0 })
    Yes ("  in a job of its own whose matrix is the shares 1 to $of (" + ($shards -join ', ') + ")") ($shards.Count -ge 2 -and (($shards -join ',') -eq ((1..$of) -join ',')))
    Yes '  where one share failing does not cancel the other' ($job -match '(?m)^\s+fail-fast:\s*false\s*$')
    Yes '  on the VPS runners, the same as every nightly job' ($job -match '(?m)^\s+runs-on: \[self-hosted, Windows, thornswood-vps\]\s*$')
    $minutes = [int][regex]::Match($job, '(?m)^\s+timeout-minutes:\s*(\d+)').Groups[1].Value
    $budget = $(if ($calls.Count) { [int]$calls[0].Groups[2].Value } else { 0 })
    Yes ("  with a budget ($budget s) that leaves room inside the job's $minutes minutes for the rest of it") ($budget -gt 0 -and $minutes -gt 0 -and $budget -le ($minutes * 60 - 180))
    Yes '  and the old inline harness loop is gone from the workflow' ($y -notmatch 'function Run-One' -and $y -notmatch 'function Kill-Left')

    if ($OnWindows) {
        # ---- 5. named harnesses (-Only, #2970) -----------------------------------
        $r = Run $a @('-Only', 'test-b.js, voice/test-v.js test-f.ps1')
        Yes ("-Only runs the named harnesses and no others (" + ((@(Ran $r.Said) | Sort-Object) -join ', ') + ")") (((@(Ran $r.Said) | Sort-Object) -join ',') -eq ((@('test-b.js', 'test-f.ps1', 'voice/test-v.js') | Sort-Object) -join ','))
        Yes "  split by commas or spaces, and green when they pass (exit $($r.Code))" ($r.Code -eq 0 -and $r.Said -match 'every harness passed')
        $r = Run $a @('-Only', 'test-b.js test-nope.js')
        Yes "  a name that is no harness is refused and nothing runs (exit $($r.Code))" ($r.Code -eq 2 -and -not (Ran $r.Said).Count -and $r.Said -match 'no such harness here, so nothing was run: test-nope\.js')
        $r = Run $a @('-Only', 'not-a-harness.js')
        Yes "  a file that is not test-* cannot be named into a run (exit $($r.Code))" ($r.Code -eq 2 -and -not (Ran $r.Said).Count)
        $r = Run $b @('-Only', 'test-2-fail.ps1')
        Yes "  a named harness that fails turns the run red (exit $($r.Code))" ($r.Code -eq 1 -and $r.Said -match '(?m)^1 harness\(es\) failed: test-2-fail\.ps1\s*$')

    } else {
        Write-Host 'SKIP  the runs in 5: Nightly-Harnesses.ps1 kills what a harness leaves through Win32_Process, which only Windows has'
    }

    # ---- 6. the workflow that runs them on demand -----------------------------
    $h = [IO.File]::ReadAllText((Join-Path $repo '.github\workflows\harnesses.yml'))
    Yes 'harnesses.yml starts only when somebody dispatches it' ($h -match '(?m)^on:\s*\r?\n  workflow_dispatch:' -and $h -notmatch '(?m)^  (push|pull_request|pull_request_target|schedule):')
    Yes '  reads the repository and nothing more' ($h -match '(?m)^permissions:\s*\r?\n  contents: read\s*\r?\n(?!  )')
    Yes '  on the VPS runners, the same as the nightly' ($h -match '(?m)^\s+runs-on: \[self-hosted, Windows, thornswood-vps\]\s*$')
    Yes '  hands the names to Nightly-Harnesses.ps1 -Only through the environment' ($h -match 'HARNESSES: \$\{\{ inputs\.harnesses \}\}' -and $h -match 'Nightly-Harnesses\.ps1 -Only \$env:HARNESSES')
    $runs = @([regex]::Matches($h, '(?ms)^\s+run: \|\s*\r?\n(.*?)(?=^\s+- |\z)') | ForEach-Object { $_.Groups[1].Value })
    Yes '  and never pastes them into a script it runs' ($runs.Count -ge 1 -and -not @($runs | Where-Object { $_ -match '\$\{\{\s*inputs\.' }).Count)
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
