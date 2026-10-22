<#
.SYNOPSIS
  Traces one run of the pull request gate on the VPS: which files every gate
  harness opens, on the box, as the build runner runs it (#3114).

.DESCRIPTION
  Run on the shipping machine, by somebody with the box's administrator key:

      .\scripts\dev\Trace-Gate.ps1 -SelfTest     # the trace's own check, a minute
      .\scripts\dev\Trace-Gate.ps1               # the whole gate, about fifteen minutes
      .\scripts\dev\Trace-Gate.ps1 -PushRun <run> # step 5 again, from temp\trace-gate-<run>

  WHY. A pull request should run only the gate harnesses its change can
  affect (scripts\dev\Affected-Harnesses.js), and which those are is
  measured on the machine the gate runs on, not guessed from a Linux run:
  a harness that asks which system it is on, or names a Windows path, can
  read other files on Windows. Patrick chose this on 22 Oct 2026 (option C on
  his page, q-3114-affected) after the Linux study in docs\AFFECTED-HARNESSES.md.

  WHAT IT DOES.
    1. The self-test on the box (scripts\dev\Trace-Gate-Box.ps1 selftest): a
       probe whose file work is known runs under a trace, and every open it
       made must come back, on it and on the child processes it started,
       with nothing lost. Without -SelfTest a failed self-test stops here.
    2. Starts the gate's trace session on the box, then dispatches
       .github\workflows\trace-gate.yml on -Ref, which runs the gate on a
       build runner the way build.yml does, with Nightly-Harnesses.ps1
       -StartLog saying which process was which harness's.
    3. Waits for that run, then stops the session whatever happened, so the
       box is never left tracing. A trace that lost an event is refused.
    4. Reads the trace on the box against the run's start log and brings
       back only the paths inside the run's checkout, a list for each
       harness. The trace itself never leaves the box and is deleted there.
    5. Pushes those lists, the start log and a summary to a branch of their
       own, claude/3114-trace-<run>, made with git's plumbing, so nothing in
       this checkout changes. A cloud session builds the read map from it.

  The session and the trace are in C:\Thornswood-Trace on the box, which only
  administrators can read: a trace sees the name of every file anything on
  the box opens. -Clean stops any session a run left and empties it.

.PARAMETER SelfTest
  Only the self-test.

.PARAMETER Clean
  Stop any trace session and empty C:\Thornswood-Trace on the box.

.PARAMETER PushRun
  Only step 5, for a run whose read finished and whose push did not: pushes
  what temp\trace-gate-<run> in this checkout kept. Nothing is traced or
  run, and nothing touches the box.

.PARAMETER Ref
  The branch trace-gate.yml runs on, and so the commit traced. main.

.PARAMETER WaitMinutes
  How long the run may take before this stops waiting and stops the session.
  50: the run's own limit is 40, and a build runner may be busy first.
#>
[CmdletBinding()]
param(
    [switch]$SelfTest,
    [switch]$Clean,
    [string]$PushRun = '',
    [string]$Ref = 'main',
    [int]$WaitMinutes = 50,
    [string]$Repo = 'EvilPatrick06/Thornswood',
    [string]$Vps = '',
    [string]$User = ''
)

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent (Split-Path -Parent $Here)
. (Join-Path $RepoRoot 'scripts\vps\Send-Script.ps1')
if (-not $Vps) { $Vps = Get-ThornswoodVpsAddress }
if (-not $User) { $User = Get-ThornswoodVpsUser }
$ssh = @('-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=10')
$BoxScript = Join-Path $Here 'Trace-Gate-Box.ps1'

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; exit 1 }

# The box script with what it is told set above it. A long one goes by scp
# (Send-Script.ps1).
function Invoke-Box([string]$mode, [hashtable]$vars = @{}) {
    $pre = "`$ProgressPreference = 'SilentlyContinue'`r`n`$TraceMode = '" + $mode + "'`r`n"
    foreach ($k in $vars.Keys) {
        $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([string]$vars[$k]))
        $pre += '$' + $k + " = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('" + $b64 + "'))`r`n"
    }
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = @(Invoke-ThornswoodRemote -Target "$User@$Vps" -SshArgs $ssh -Bypass -Script ($pre + [IO.File]::ReadAllText($BoxScript)) |
        ForEach-Object { [string]$_ } | Where-Object { $_ -notmatch 'post-quantum|store now, decrypt later|openssh\.com/pq\.html' })
    $rc = $LASTEXITCODE
    $ErrorActionPreference = $old
    return [pscustomobject]@{ Code = $rc; Lines = $out }
}
function Show($box) {
    foreach ($l in $box.Lines) {
        if ($l -eq 'BEGIN') { break }
        $c = 'Gray'
        if ($l -match '^PASS ') { $c = 'Green' } elseif ($l -match '^(FAIL|REFUSED)') { $c = 'Red' }
        Say "  $l" $c
    }
}
function Invoke-Gh {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = @(& gh @args 2>&1 | ForEach-Object { [string]$_ })
    $rc = $LASTEXITCODE
    $ErrorActionPreference = $old
    if ($rc -ne 0) { throw ('gh ' + ($args -join ' ') + ' failed (exit ' + $rc + '): ' + ($out -join ' ')) }
    return $out
}

# Step 5: the files of a read pushed to claude/3114-trace-<run>. The tree is
# made in an index of its own (GIT_INDEX_FILE), with every file named on the
# command line, so nothing goes through a pipe into git, whose bytes depend on
# the PowerShell: pwsh ends what it pipes with a line break of its own, so the
# list that ended in one reached git mktree with a blank line after it, which
# git refuses outside --batch ("input format error", run 39731778532, and
# reproduced with pwsh 7.6.7). This checkout's own index and files are not
# touched.
function Push-Trace([string]$runId, [string]$work) {
    $meta = [IO.File]::ReadAllText((Join-Path $work 'run.json')) | ConvertFrom-Json
    $branch = 'claude/3114-trace-' + $runId
    $index = Join-Path $work 'index'
    Remove-Item -LiteralPath $index -Force -ErrorAction SilentlyContinue
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $env:GIT_INDEX_FILE = $index
    try {
        foreach ($f in 'traces.jsonl.gz', 'starts.jsonl', 'run.json', 'summary.txt') {
            $sha = (& git -C $RepoRoot hash-object -w (Join-Path $work $f)).Trim()
            if ($LASTEXITCODE -ne 0) { Die "git could not store $f" }
            & git -C $RepoRoot update-index --add --cacheinfo ('100644,' + $sha + ',' + $f)
            if ($LASTEXITCODE -ne 0) { Die "git could not put $f in the tree" }
        }
        $tree = (& git -C $RepoRoot write-tree).Trim()
        if ($LASTEXITCODE -ne 0) { Die 'git could not make the tree' }
    } finally { Remove-Item Env:\GIT_INDEX_FILE -ErrorAction SilentlyContinue }
    $commit = (& git -C $RepoRoot commit-tree $tree -m ("Gate trace of " + ([string]$meta.commit).Substring(0, 8) + ", run " + $runId + " (#3114)")).Trim()
    if ($LASTEXITCODE -ne 0) { Die 'git could not make the commit' }
    & git -C $RepoRoot push origin ($commit + ':refs/heads/' + $branch)
    $pushed = $LASTEXITCODE
    $ErrorActionPreference = $old
    if ($pushed -ne 0) { Die ("the push did not go (exit $pushed). The files are in $work.") }
    Remove-Item -LiteralPath $work -Recurse -Force
    Say "  $branch, commit $commit" 'Green'
}

if ($PushRun) {
    if ($PushRun -notmatch '^\d+$') { Die "-PushRun takes a run's number, not '$PushRun'." }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Die 'git is not on PATH.' }
    $work = Join-Path $RepoRoot ('temp\trace-gate-' + $PushRun)
    foreach ($f in 'traces.jsonl.gz', 'starts.jsonl', 'run.json', 'summary.txt') {
        if (-not (Test-Path -LiteralPath (Join-Path $work $f))) { Die "$work has no $f, so that run's read did not finish here. Trace again." }
    }
    Head ('5. Pushed for the read map, from run ' + $PushRun + "'s kept read")
    Push-Trace $PushRun $work
    exit 0
}

if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) { Die 'ssh is not on PATH.' }

if ($Clean) {
    Head 'Emptying the trace folder on the box'
    $b = Invoke-Box 'clean'; Show $b
    exit $b.Code
}

Head '1. The self-test on the box'
$b = Invoke-Box 'selftest'
Show $b
if ($b.Code -ne 0) { Die ('the self-test did not pass (exit ' + $b.Code + '), so a gate trace from this box would prove nothing. The lines above say what was missing.') }
if ($SelfTest) { exit 0 }

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Die 'gh is not on PATH.' }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Die 'git is not on PATH.' }

Head '2. The gate, traced'
$b = Invoke-Box 'start'; Show $b
if ($b.Code -ne 0) { Die ('the trace session did not start (exit ' + $b.Code + '). Nothing was dispatched.') }
$run = $null
$conclusion = ''
try {
    $asked = [DateTime]::UtcNow.AddSeconds(-5)
    $null = Invoke-Gh workflow run trace-gate.yml --repo $Repo --ref $Ref
    Say "  dispatched trace-gate.yml on $Ref"
    for ($i = 0; $i -lt 24 -and -not $run; $i++) {
        Start-Sleep -Seconds 5
        $list = (Invoke-Gh run list --repo $Repo --workflow trace-gate.yml --branch $Ref --event workflow_dispatch --limit 5 --json 'databaseId,createdAt,url') -join "`n" | ConvertFrom-Json
        $run = @($list | Where-Object { ([DateTime]$_.createdAt).ToUniversalTime() -ge $asked } | Sort-Object createdAt | Select-Object -First 1)[0]
    }
    if (-not $run) { throw 'the dispatched run did not show up within two minutes' }
    Say ('  run ' + $run.url)
    $until = [DateTime]::UtcNow.AddMinutes($WaitMinutes)
    while ([DateTime]::UtcNow -lt $until) {
        $v = (Invoke-Gh run view $run.databaseId --repo $Repo --json 'status,conclusion') -join "`n" | ConvertFrom-Json
        if ($v.status -eq 'completed') { $conclusion = $v.conclusion; break }
        Start-Sleep -Seconds 30
    }
    if (-not $conclusion) { Say "  the run did not finish in $WaitMinutes minutes" 'Yellow' }
} finally {
    Head '3. The session stopped'
    $s = Invoke-Box 'stop'; Show $s
}
if (-not $conclusion) { $null = Invoke-Box 'clean'; Die 'no finished run, so there is nothing to read. The trace was deleted.' }
if ($s.Code -ne 0) { $null = Invoke-Box 'clean'; Die 'the trace was refused (above) and deleted.' }
Say "  the run ended: $conclusion"

Head '4. The trace read on the box'
$work = Join-Path $RepoRoot ('temp\trace-gate-' + $run.databaseId)
$null = New-Item -ItemType Directory -Force -Path $work
$null = Invoke-Gh run download $run.databaseId --repo $Repo -n gate-trace -D $work
$starts = [IO.File]::ReadAllText((Join-Path $work 'starts.jsonl'))
$meta = [IO.File]::ReadAllText((Join-Path $work 'run.json')) | ConvertFrom-Json
Say ('  ' + @($starts -split "`n" | Where-Object { $_ -match '"pid"' }).Count + ' harnesses started, commit ' + $meta.commit + ', checkout ' + $meta.workspace)
$r = Invoke-Box 'read' @{ TraceStarts = $starts; TraceWorkspace = $meta.workspace }
Show $r
if ($r.Code -ne 0) { $null = Invoke-Box 'clean'; Die ('the read did not finish (exit ' + $r.Code + '). The trace was deleted.') }
$at = [Array]::IndexOf($r.Lines, 'BEGIN'); $to = [Array]::IndexOf($r.Lines, 'END')
if ($at -lt 0 -or $to -lt $at) { Die 'the read printed no traces between BEGIN and END.' }
$gz = [Convert]::FromBase64String((($r.Lines[($at + 1)..($to - 1)]) -join ''))
[IO.File]::WriteAllBytes((Join-Path $work 'traces.jsonl.gz'), $gz)
$summary = @(
    'Gate trace of ' + $meta.commit + ', run ' + $run.url + ' (' + $conclusion + ')',
    'Made by scripts\dev\Trace-Gate.ps1 on ' + [Environment]::MachineName + ' at ' + [DateTime]::UtcNow.ToString('u'),
    ''
) + @($r.Lines | Select-Object -First $at)
[IO.File]::WriteAllText((Join-Path $work 'summary.txt'), ($summary -join "`n") + "`n")
Say ('  ' + $gz.Length + ' bytes of traces, gzipped')

Head '5. Pushed for the read map'
Push-Trace $run.databaseId $work
exit 0
