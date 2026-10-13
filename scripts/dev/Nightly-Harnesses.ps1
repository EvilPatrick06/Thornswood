<#
.SYNOPSIS
  Runs one share of the test harnesses for the nightly checks, one at a time and each on a clock, and always ends by naming every harness that failed and the ten slowest, inside the time it is given.

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

  tests\test-nightly-harnesses.ps1 runs this against stand-in harnesses.

.PARAMETER Shard
  Which share to run, from 1.

.PARAMETER Of
  How many shares there are. nightly.yml passes the length of its matrix.

.PARAMETER BudgetSeconds
  How long this may take in all. A harness starts only when the time used so
  far plus its clock is no more than this. nightly.yml gives 2400 seconds of a
  45 minute job.

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
    [string]$Root = '',
    [string]$OutDir = ''
)

$ErrorActionPreference = 'Stop'
if ($Of -lt 1 -or $Shard -lt 1 -or $Shard -gt $Of) { Write-Host "::error::-Shard $Shard -Of $Of names no share"; exit 2 }
if (-not $Root) { $Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$Root = [IO.Path]::GetFullPath($Root)
if (-not $OutDir) {
    $base = $(if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() })
    $OutDir = Join-Path $base ('harness-out-' + $Shard)
}

$PER_HARNESS = 300
$MAX_CLOCK = 600
function Clock-Of($path) {
    $head = [IO.File]::ReadAllText($path)
    if ($head.Length -gt 8000) { $head = $head.Substring(0, 8000) }
    $m = [regex]::Match($head, '(?im)^[\s#/*<]*NIGHTLY CLOCK:\s*(\d+) seconds')
    if ($m.Success) { [Math]::Min([int]$m.Groups[1].Value, $MAX_CLOCK) } else { $PER_HARNESS }
}

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
# An empty file for stdin: no harness reads it, and one that tried would
# otherwise wait on the runner's for ever.
$nothing = Join-Path $OutDir 'stdin.empty'
Set-Content -Path $nothing -Value $null -NoNewline

# What a harness left running after it ended: the processes it started, and
# theirs, found by parent id and killed. Only ones started after the harness,
# so a pid Windows has since handed to something else is left alone.
function Kill-Left($id, $since) {
    $procs = @(Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId, Name, CreationDate)
    $mine = @{ $id = $true }; $left = @()
    do {
        $more = @($procs | Where-Object { $mine[[int]$_.ParentProcessId] -and -not $mine[[int]$_.ProcessId] -and $_.CreationDate -ge $since })
        foreach ($q in $more) { $mine[[int]$q.ProcessId] = $true; $left += $q }
    } while ($more.Count)
    foreach ($q in $left) { Stop-Process -Id $q.ProcessId -Force -ErrorAction SilentlyContinue }
    @($left | ForEach-Object { $_.Name })
}

# Start-Process joins -ArgumentList with spaces and quotes nothing, so a path
# is quoted here. $p.Handle is read at once because without it ExitCode comes
# back empty once the process is gone.
function Run-One($exe, $argList, $name, $path, $clock) {
    $file = $name -replace '[\\/]', '_'
    $o = Join-Path $OutDir ($file + '.out'); $e = Join-Path $OutDir ($file + '.err')
    $since = (Get-Date).AddSeconds(-1)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $p = Start-Process -FilePath $exe -ArgumentList $argList -NoNewWindow -PassThru -WorkingDirectory $Root `
           -RedirectStandardInput $nothing -RedirectStandardOutput $o -RedirectStandardError $e
    $null = $p.Handle
    $timedOut = -not $p.WaitForExit($clock * 1000)
    if ($timedOut) { & taskkill.exe /T /F /PID $p.Id 2>&1 | Out-Null; $null = $p.WaitForExit(10000) }
    $code = if ($timedOut) { -1 } else { $p.ExitCode }
    $secs = [Math]::Round($sw.Elapsed.TotalSeconds, 1)
    $left = @(Kill-Left $p.Id $since)
    Write-Host ("--- {0}  ({1}s{2})" -f $name, $secs, $(if ($clock -ne $PER_HARNESS) { ', on a ' + $clock + ' s clock it names' } else { '' }))
    foreach ($f in $o, $e) { if (Test-Path $f) { $txt = Get-Content -Raw $f; if ($txt) { Write-Host $txt.TrimEnd() } } }
    if ($timedOut) { Write-Host ("::error file={0}::harness timed out after {1}s and was killed" -f $path, $clock) }
    elseif ($code -ne 0) { Write-Host ("::error file={0}::harness failed (exit {1})" -f $path, $code) }
    if ($left.Count) { Write-Host ("::warning file={0}::harness left {1} process(es) running when it ended, now killed: {2}" -f $path, $left.Count, ($left -join ', ')) }
    [pscustomobject]@{ Name = $name; Path = $path; Code = $code; TimedOut = $timedOut; Secs = $secs }
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
$mine = @(for ($i = 0; $i -lt $every.Count; $i++) { if (($i % $Of) -eq ($Shard - 1)) { $every[$i] } })
Write-Host ("share {0} of {1}: {2} of the {3} harnesses, {4} s to run them in" -f $Shard, $Of, $mine.Count, $every.Count, $BudgetSeconds)

$clockAll = [Diagnostics.Stopwatch]::StartNew()
$results = @()
$notRun = @()
foreach ($t in $mine) {
    $clock = Clock-Of $t.File.FullName
    if ($clockAll.Elapsed.TotalSeconds + $clock -gt $BudgetSeconds) {
        $notRun += $t.Name
        Write-Host ("::error file={0}::not run, out of time: {1}s used of {2}s and its clock is {3}s" -f $t.File.FullName, [Math]::Round($clockAll.Elapsed.TotalSeconds), $BudgetSeconds, $clock)
        continue
    }
    if ($t.File.Extension -eq '.js') { $results += Run-One 'node' @('"' + $t.File.FullName + '"') $t.Name $t.File.FullName $clock }
    else { $results += Run-One 'pwsh' @('-NoProfile', '-File', ('"' + $t.File.FullName + '"')) $t.Name $t.File.FullName $clock }
}

$failed = @($results | Where-Object { $_.Code -ne 0 } | ForEach-Object { if ($_.TimedOut) { $_.Name + ' (timed out)' } else { $_.Name } })
Write-Host ''
Write-Host ('slowest: ' + ((@($results | Sort-Object Secs -Descending | Select-Object -First 10) | ForEach-Object { '{0} {1}s' -f $_.Name, $_.Secs }) -join ', '))
Write-Host ('all of them, added up: {0}s, in {1}s' -f [Math]::Round(($results | Measure-Object Secs -Sum).Sum), [Math]::Round($clockAll.Elapsed.TotalSeconds))
if ($notRun.Count) {
    Write-Host ''
    Write-Host ("{0} harness(es) not run, out of this share's {1} s; nightly.yml needs another share: {2}" -f $notRun.Count, $BudgetSeconds, ($notRun -join ', '))
}
if ($failed.Count) {
    Write-Host ''
    Write-Host ("{0} harness(es) failed: {1}" -f $failed.Count, ($failed -join ', '))
}
if ($failed.Count -or $notRun.Count) { exit 1 }
Write-Host 'every harness passed'
exit 0
