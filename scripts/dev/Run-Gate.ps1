<#
.SYNOPSIS
  Runs the gate harnesses for build.yml's "Run the gate harnesses" step: every
  one on main, under the trace task's trace on the VPS, and on a pull request
  built on the VPS only those its change can reach (#3114).

.DESCRIPTION
  build.yml's gate step runs this and nothing else:

      .\scripts\dev\Run-Gate.ps1 -Throttle 6 -BudgetSeconds 1800

  THE GATE. Every harness scripts\dev\Gate-Harnesses.ps1 lists, run through
  scripts\dev\Nightly-Harnesses.ps1 -Throttle at once with this build's
  share of the cores: the machine's cores over the builds the box runs at
  once, the runners records\build-runners.json lists.

  ON MAIN, ON THE VPS. Patrick chose on 22 Oct 2026 (option A on his page,
  q-3114-map-refresh) that every main build's gate is traced, so pull
  requests can be held to a map that is never more than a merge or two
  old. Only an administrator can start the trace, so this asks the trace
  task (scripts\dev\Trace-Gate-Task.ps1, which runs as SYSTEM) through the
  runner's own folder, <runner>\trace:
    tree.gz     every path in this commit's tree with its mode and object,
                so a pull request can measure its change from this tree
                without fetching it (Affected-Harnesses.js tree)
    ask.json    this run, its commit, its checkout and this process
    answer.json the task's answer: tracing, or why not
    starts.jsonl  Nightly-Harnesses.ps1 -StartLog, which process was which
                harness's
    done.json   the gate ended, and how
  A main build is never held up by it: no answer in -AnswerSeconds, or any
  answer but tracing, runs the gate untraced and that commit leaves no map.
  The gate is the whole gate either way; the trace only watches it.

  ON A PULL REQUEST, ON THE VPS. The task leaves the newest map in every
  build runner's <runner>\gate-map, a folder the runner's account may read
  and not change. Affected-Harnesses.js pick builds the map from it and
  measures the change from the traced tree to this checkout's HEAD,
  GitHub's merge of the pull request into main, and this runs only what
  that change can reach, printing why each one runs. Anything that goes
  wrong on the way (no map, a map that does not read, pick failing) runs
  the whole gate and says why; so does any change to the scripts that list,
  choose and run the harnesses, and a GitHub-hosted runner, which has no map.

  THE NOTE. It writes whole=true to the step's outputs only when every gate
  harness ran. build.yml keeps the note main's build looks for (#3182, the
  job "tested") only then, so main skips its build only for a tree a pull
  request ran the whole gate on, and otherwise builds in full and is
  traced. Main and the nightly run the whole gate every time, so whatever a
  harness left out would have caught is still caught there.

  The trace task, the map's folders and how they are kept from the
  runners' accounts: scripts\dev\Trace-Gate-Task.ps1. Why a map is enough:
  scripts\dev\Affected-Harnesses.js. tests\test-3114-run-gate.ps1 holds
  all of this.

.PARAMETER Throttle
  The most harnesses at once, as Nightly-Harnesses.ps1 takes it.

.PARAMETER BudgetSeconds
  As Nightly-Harnesses.ps1 takes it: a harness starts only when its whole
  clock still fits.

.PARAMETER AnswerSeconds
  How long a main build waits for the trace task to say it is tracing.

.PARAMETER StartLog
  Where Nightly-Harnesses.ps1 -StartLog writes which process was which
  harness's, for .github\workflows\trace-gate.yml, the trace taken by hand
  (scripts\dev\Trace-Gate.ps1). A main build the trace task traces writes
  its own in <runner>\trace.
#>
[CmdletBinding()]
param(
    [int]$Throttle = 6,
    [int]$BudgetSeconds = 1800,
    [int]$AnswerSeconds = 60,
    [string]$StartLog = ''
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent (Split-Path -Parent $Here)
$Affected = Join-Path $Here 'Affected-Harnesses.js'

function Say([string]$m) { Write-Host $m }
function Set-StepOutput([string]$name, [string]$value) {
    if ($env:GITHUB_OUTPUT) { Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value ($name + '=' + $value) }
}
# Written whole and then renamed, so the task never reads half a file.
function Write-Whole([string]$file, [string]$text) {
    $tmp = $file + '.tmp'
    [IO.File]::WriteAllText($tmp, $text)
    Move-Item -LiteralPath $tmp -Destination $file -Force
}

$gate = @(& (Join-Path $Here 'Gate-Harnesses.ps1'))
if ($LASTEXITCODE -ne 0) { exit 1 }
$builds = @((Get-Content -LiteralPath (Join-Path $Repo 'records\build-runners.json') -Raw | ConvertFrom-Json).runners).Count
$share = [Math]::Min(6, [Math]::Max(1, [Math]::Floor([Environment]::ProcessorCount / [Math]::Max(1, $builds))))

# The runner's own folder: RUNNER_TEMP is <runner>\_work\_temp there.
$root = ''
if ($env:RUNNER_ENVIRONMENT -eq 'self-hosted' -and $env:RUNNER_TEMP) { $root = Split-Path -Parent (Split-Path -Parent $env:RUNNER_TEMP) }

# The harnesses a pull request's change can reach, or $null for the whole gate.
function Select-Affected {
    if (-not $root) { Say 'The whole gate runs: the traced map is on the VPS, and this runner is not.'; return $null }
    $maps = Join-Path $root 'gate-map'
    $latest = Join-Path $maps 'latest.json'
    if (-not (Test-Path -LiteralPath $latest)) { Say ('The whole gate runs: there is no traced map in ' + $maps + ' yet.'); return $null }
    try {
        $m = [IO.File]::ReadAllText($latest) | ConvertFrom-Json
        if ([string]$m.commit -notmatch '^[0-9a-f]{40}$' -or [string]$m.key -notmatch '^\d+-\d+$') { Say ('The whole gate runs: ' + $latest + ' names no commit and run.'); return $null }
        $traces = Join-Path $maps ([string]$m.key + '.traces.jsonl.gz')
        $tree = Join-Path $maps ([string]$m.key + '.tree.gz')
        $read = $m.read
        if ($read -is [datetime]) { $read = $read.ToUniversalTime().ToString('yyyy-MM-dd HH:mm') + ' UTC' }
        Say ('The traced map: main ' + ([string]$m.commit).Substring(0, 8) + ', build run ' + $m.key + ', read ' + $read + '.')
        $gateFile = Join-Path $env:RUNNER_TEMP 'gate.txt'
        $out = Join-Path $env:RUNNER_TEMP 'gate-picked.txt'
        [IO.File]::WriteAllLines($gateFile, [string[]]$gate)
        # Its lines to the log, not into this function's answer.
        & node $Affected pick $traces $tree ([string]$m.commit) $gateFile $out 2>&1 | ForEach-Object { Say ([string]$_) }
        if ($LASTEXITCODE -ne 0) { Say ('The whole gate runs: Affected-Harnesses.js pick failed (exit ' + $LASTEXITCODE + '), the lines above say why.'); return $null }
        $picked = @([IO.File]::ReadAllLines($out) | Where-Object { $_.Trim() })
        $strange = @($picked | Where-Object { $gate -notcontains $_ })
        if ($strange.Count) { Say ('The whole gate runs: pick named what is not on the gate: ' + ($strange -join ', ')); return $null }
        if ($picked.Count -ge $gate.Count) { return $null }
        return ,$picked
    } catch {
        Say ('The whole gate runs: the traced map could not be used (' + $_.Exception.Message + ').')
        return $null
    }
}

# Asks the trace task to trace this gate. Returns the ask, or $null when
# the gate runs untraced, having said why.
function Request-Trace {
    if (-not $root) { return $null }
    $dir = Join-Path $root 'trace'
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { Say ('Not traced: there is no ' + $dir + ', so the trace task is not installed for this runner (Trace-Gate.ps1 -Install).'); return $null }
    $key = [string]$env:GITHUB_RUN_ID + '-' + [string]$env:GITHUB_RUN_ATTEMPT
    if ($key -notmatch '^\d+-\d+$') { Say 'Not traced: GitHub gave no run and attempt.'; return $null }
    foreach ($f in 'ask.json', 'answer.json', 'done.json', 'starts.jsonl', 'tree.gz') {
        Remove-Item -LiteralPath (Join-Path $dir $f) -Force -ErrorAction SilentlyContinue
    }
    & node $Affected tree HEAD (Join-Path $dir 'tree.gz') 2>&1 | ForEach-Object { Say ([string]$_) }
    if ($LASTEXITCODE -ne 0) { Say 'Not traced: the tree could not be listed for the map.'; return $null }
    $commit = (& git rev-parse HEAD | Out-String).Trim()
    if ($commit -notmatch '^[0-9a-f]{40}$') { Say ('Not traced: git gave no commit for HEAD (' + $commit + ').'); return $null }
    $me = [Diagnostics.Process]::GetCurrentProcess()
    $ask = [ordered]@{
        key = $key; commit = $commit; workspace = (Get-Location).Path
        pid = $me.Id; started = $me.StartTime.ToUniversalTime().ToString('o')
    }
    Write-Whole (Join-Path $dir 'ask.json') ($ask | ConvertTo-Json -Compress)
    $answer = Join-Path $dir 'answer.json'
    $until = [DateTime]::UtcNow.AddSeconds($AnswerSeconds)
    while ([DateTime]::UtcNow -lt $until) {
        if (Test-Path -LiteralPath $answer) {
            $a = $null
            try { $a = [IO.File]::ReadAllText($answer) | ConvertFrom-Json } catch { Say ('the trace task''s answer did not read yet: ' + $_.Exception.Message) }
            if ($a -and [string]$a.key -eq $key) {
                if ([string]$a.state -eq 'tracing') {
                    Say ('Traced: the trace task is tracing this gate (run ' + $key + ').')
                    return [pscustomobject]@{ Key = $key; Dir = $dir; Starts = (Join-Path $dir 'starts.jsonl') }
                }
                Say ('Not traced: ' + $a.why)
                return $null
            }
        }
        Start-Sleep -Milliseconds 500
    }
    Remove-Item -LiteralPath (Join-Path $dir 'ask.json') -Force -ErrorAction SilentlyContinue
    Say ('Not traced: the trace task did not answer in ' + $AnswerSeconds + ' s.')
    return $null
}

$run = $gate
$whole = $true
$trace = $null
if ($env:GITHUB_EVENT_NAME -eq 'pull_request') {
    $picked = Select-Affected
    if ($null -ne $picked) { $run = $picked; $whole = $false }
} elseif ($env:GITHUB_EVENT_NAME -eq 'push' -and $env:GITHUB_REF -eq 'refs/heads/main') {
    $trace = Request-Trace
}

$code = 0
if ($run.Count) {
    $with = @{ Only = ($run -join ' '); Throttle = $Throttle; Share = $share; BudgetSeconds = $BudgetSeconds }
    if ($trace) { $with.StartLog = $trace.Starts } elseif ($StartLog) { $with.StartLog = $StartLog }
    & (Join-Path $Here 'Nightly-Harnesses.ps1') @with
    $code = $LASTEXITCODE
} else {
    Say 'No gate harness can be affected by this change, so none runs.'
}
if ($trace) {
    Write-Whole (Join-Path $trace.Dir 'done.json') (([ordered]@{ key = $trace.Key; code = $code }) | ConvertTo-Json -Compress)
    Say 'The trace task reads the trace at low priority now and leaves the map for pull requests; this build does not wait for it.'
}
if ($whole) { Set-StepOutput 'whole' 'true' }
exit $code
