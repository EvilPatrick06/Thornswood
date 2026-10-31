<#
.SYNOPSIS
  Hands the newest traced gate map from the box to runners off it, through
  main's build log (#4009).

.DESCRIPTION
  The trace task (scripts\dev\Trace-Gate-Task.ps1) leaves the map pull
  requests are held to only in the box's build runners' <runner>\gate-map
  folders. A pull request built anywhere else (One's runners, #3860, or
  GitHub's hosted runner) found no map there and ran the whole gate: #3861's
  own build on thornswood-pr-one ran all of it in about 13 minutes (run
  40424800152), where a box build from a fresh map runs only what its change
  reaches.

      .\scripts\dev\Gate-Map.ps1 -Hand
      .\scripts\dev\Gate-Map.ps1 -Fetch <dir>      (the token in GATE_MAP_TOKEN)

  -Hand, in main's push build on a box build runner (build.yml, after the
  gate; in any other build it says so and prints nothing):
  builds the map from this runner's newest traces (Affected-Harnesses.js
  build) and prints it, gzipped, with the traced tree, into the job's log
  as GATE-MAP lines: each part in numbered pieces, then its sha256. It never
  fails the build: with no map, or one that does not read, it says so and
  prints none.

  -Fetch, in a pull request's gate off the box (scripts\dev\Run-Gate.ps1):
  reads main's newest finished build.yml runs on a push to main of this
  repository, newest first, and from the first whose launcher job's log
  holds a whole map writes latest.json, <key>.map.json and <key>.tree.gz
  into <dir>, the shape of the box's gate-map, with the built map in place
  of the traces. Exit 0 with a map in <dir>, 1 without, saying why.

  SINCE #4983 no build of this repository runs on the box, so nothing runs
  -Hand and main's builds hold no map: -Fetch reads them, says so and exits
  1, and a pull request runs the whole gate. The box still takes the traces,
  through the private repository's trace-gate.yml, but no main build hands
  them on; #4983 has that written down.

  WHY THE LOG. It was to be an artifact, but this private repository's
  artifact storage is used up (#3399: the tested-tree note's upload failed
  and took every pull request's build red), and a log costs no storage and
  is kept 90 days, as scripts\dev\Tested-Tree.js found. The built map is
  about 23 KB gzipped and the tree about 75 KB, where the raw traces would
  be far more.

  WHY ONLY MAIN'S BUILD. A pull request's code runs in its own build and
  can print anything into its own log. So a map counts only from a run that
  GitHub says is build.yml on a push to main of this repository, read back
  for each run. Main's build runs main's code, and what it hands on is the
  box's folder, which no runner account can change (Trace-Gate-Task.ps1).
  The map it hands on is the newest the box had when its gate ended,
  usually the one before its own: Affected-Harnesses.js pick measures a
  pull request's change from the traced tree, so the merges since count as
  part of it, as on the box.

  The token is the job's own (actions: read, for another run's job logs).
  -Fetch reads it from GATE_MAP_TOKEN and takes it out of the environment
  before anything else, so it is never typed or on a command line (#4079,
  tests\test-secrets-off-command-lines.ps1). Run-Gate.ps1 takes it out of
  the step's environment before any harness starts and sets it only around
  this call. tests\test-4009-gate-map.ps1 holds both halves.

.PARAMETER Hand
  Print this runner's newest map into the job's log.

.PARAMETER Fetch
  The folder to write main's newest handed-on map into.

.PARAMETER Repository
  owner/name, GITHUB_REPOSITORY by default.
#>
[CmdletBinding(DefaultParameterSetName = 'Fetch')]
param(
    [Parameter(ParameterSetName = 'Hand', Mandatory = $true)]
    [switch]$Hand,
    [Parameter(ParameterSetName = 'Fetch', Mandatory = $true)]
    [string]$Fetch,
    [Parameter(ParameterSetName = 'Fetch')]
    [string]$Repository = $env:GITHUB_REPOSITORY
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Api = 'https://api.github.com'
$Mark = 'GATE-MAP'
# Characters of base64 on one log line.
$Piece = 8000
# How many of main's newest finished builds are read before giving up.
$Look = 8
$JobNames = @('Launcher builds (VPS fallback)', 'Launcher builds')
$StepName = 'Hand the traced map to runners off the box'

function Say([string]$m) { Write-Host $m }
# -Fetch only: a token that may read this repository's Actions runs and job
# logs, out of the environment at once (#4079).
$Token = ''
if ($PSCmdlet.ParameterSetName -eq 'Fetch') {
    $Token = [string]$env:GATE_MAP_TOKEN
    Remove-Item -LiteralPath Env:GATE_MAP_TOKEN -ErrorAction SilentlyContinue
}
function Get-Sha256([byte[]]$bytes) {
    $h = [Security.Cryptography.SHA256]::Create()
    try { return (($h.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '') } finally { $h.Dispose() }
}
function Compress-Bytes([byte[]]$bytes) {
    $ms = New-Object IO.MemoryStream
    $gz = New-Object IO.Compression.GZipStream($ms, [IO.Compression.CompressionLevel]::Optimal)
    $gz.Write($bytes, 0, $bytes.Length); $gz.Close()
    , $ms.ToArray()
}
function Expand-Bytes([byte[]]$bytes) {
    $in = New-Object IO.MemoryStream(, $bytes)
    $gz = New-Object IO.Compression.GZipStream($in, [IO.Compression.CompressionMode]::Decompress)
    $out = New-Object IO.MemoryStream
    $gz.CopyTo($out); $gz.Close()
    , $out.ToArray()
}

# ------------------------------------------------------------------ -Hand ---
if ($Hand) {
    # Only main's build: a map in a pull request's log is never read.
    if ($env:GITHUB_EVENT_NAME -ne 'push' -or $env:GITHUB_REF -ne 'refs/heads/main') { Say 'No map handed on: only main''s push build hands one on.'; exit 0 }
    $maps = ''
    if ($env:RUNNER_ENVIRONMENT -eq 'self-hosted' -and $env:RUNNER_TEMP) { $maps = Join-Path (Split-Path -Parent (Split-Path -Parent $env:RUNNER_TEMP)) 'gate-map' }
    $latest = $(if ($maps) { Join-Path $maps 'latest.json' } else { '' })
    if (-not $latest -or -not (Test-Path -LiteralPath $latest)) { Say 'No map handed on to runners off the box: this runner has no traced map.'; exit 0 }
    try {
        $m = [IO.File]::ReadAllText($latest) | ConvertFrom-Json
        $key = [string]$m.key; $commit = [string]$m.commit
        if ($commit -notmatch '^[0-9a-f]{40}$' -or $key -notmatch '^\d+-\d+$') { throw ($latest + ' names no commit and run') }
        $traces = Join-Path $maps ($key + '.traces.jsonl.gz')
        $tree = Join-Path $maps ($key + '.tree.gz')
        $built = Join-Path $env:RUNNER_TEMP ('gate-map-' + $key + '.json')
        & node (Join-Path $Here 'Affected-Harnesses.js') build $traces $built $commit 2>&1 | ForEach-Object { Say ([string]$_) }
        if ($LASTEXITCODE -ne 0) { throw ('Affected-Harnesses.js build failed (exit ' + $LASTEXITCODE + ')') }
        $parts = [ordered]@{ map = (Compress-Bytes ([IO.File]::ReadAllBytes($built))); tree = [IO.File]::ReadAllBytes($tree) }
        Remove-Item -LiteralPath $built -Force -ErrorAction SilentlyContinue
    } catch {
        Say ('No map handed on to runners off the box: ' + $_.Exception.Message + '.')
        exit 0
    }
    Say ('Handing on the map of main ' + $commit.Substring(0, 8) + ', build run ' + $key + ', read ' + $m.read + ', to runners off the box:')
    foreach ($name in $parts.Keys) {
        $b64 = [Convert]::ToBase64String($parts[$name])
        $n = [Math]::Max(1, [int][Math]::Ceiling($b64.Length / $Piece))
        for ($i = 0; $i -lt $n; $i++) {
            $len = [Math]::Min($Piece, $b64.Length - $i * $Piece)
            Write-Host ('{0} {1} {2} {3} {4}/{5} {6}' -f $Mark, $key, $commit, $name, ($i + 1), $n, $b64.Substring($i * $Piece, $len))
        }
        Write-Host ('{0} {1} {2} {3} sha256 {4}' -f $Mark, $key, $commit, $name, (Get-Sha256 $parts[$name]))
    }
    exit 0
}

# ----------------------------------------------------------------- -Fetch ---
# The map in one job log's lines, or a string saying why there is none.
function Read-HandedMap([string[]]$lines) {
    $pieces = @{}; $counts = @{}; $sums = @{}; $key = ''; $commit = ''
    foreach ($l in $lines) {
        $x = [regex]::Match($l, '(?:^|\s)GATE-MAP (\d+-\d+) ([0-9a-f]{40}) (map|tree) (?:(\d+)/(\d+) ([A-Za-z0-9+/=]+)|sha256 ([0-9a-f]{64}))\s*$')
        if (-not $x.Success) { continue }
        if (-not $key) { $key = $x.Groups[1].Value; $commit = $x.Groups[2].Value }
        if ($x.Groups[1].Value -ne $key -or $x.Groups[2].Value -ne $commit) { return 'it names two maps' }
        $part = $x.Groups[3].Value
        if ($x.Groups[7].Success) { $sums[$part] = $x.Groups[7].Value; continue }
        $counts[$part] = [int]$x.Groups[5].Value
        $pieces[$part + ' ' + $x.Groups[4].Value] = $x.Groups[6].Value
    }
    if (-not $key) { return 'its log holds no map' }
    $out = @{}
    foreach ($part in 'map', 'tree') {
        if (-not $counts.ContainsKey($part) -or -not $sums.ContainsKey($part)) { return ('its log holds no whole ' + $part) }
        $b64 = ''
        for ($i = 1; $i -le $counts[$part]; $i++) {
            if (-not $pieces.ContainsKey($part + ' ' + $i)) { return ('its log lacks piece ' + $i + ' of the ' + $part) }
            $b64 += $pieces[$part + ' ' + $i]
        }
        try { $bytes = [Convert]::FromBase64String($b64) } catch { return ('its ' + $part + ' is not base64') }
        if ((Get-Sha256 $bytes) -ne $sums[$part]) { return ('its ' + $part + ' does not match its sha256') }
        $out[$part] = $bytes
    }
    [pscustomobject]@{ Key = $key; Commit = $commit; Map = (Expand-Bytes $out['map']); Tree = $out['tree'] }
}

if (-not $Token) { Say 'No token to read main''s builds on GitHub with.'; exit 1 }
if ($Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { Say ('No repository to look in (' + $Repository + ').'); exit 1 }
$headers = @{ Authorization = ('Bearer ' + $Token); Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28' }
$base = $Api + '/repos/' + $Repository + '/actions'
try {
    $list = Invoke-RestMethod -Method Get -Uri ($base + '/workflows/build.yml/runs?branch=main&event=push&status=completed&per_page=' + $Look) -Headers $headers
} catch {
    Say ('GitHub would not list main''s builds: ' + $_.Exception.Message)
    exit 1
}
$runs = @($list.workflow_runs)
if (-not $runs.Count) { Say 'GitHub lists no finished build of main.'; exit 1 }
foreach ($run in $runs) {
    $what = 'main''s build run ' + $run.id
    if ([string]$run.event -ne 'push' -or [string]$run.head_branch -ne 'main' -or [string]$run.path -notmatch '^\.github/workflows/build\.yml(@|$)' -or [string]$run.head_repository.full_name -ne $Repository) {
        Say ('Passed over run ' + $run.id + ': it is ' + $run.path + ' on ' + $run.event + ' to ' + $run.head_branch + ', not build.yml on a push to main.')
        continue
    }
    try {
        $jobs = Invoke-RestMethod -Method Get -Uri ($base + '/runs/' + $run.id + '/jobs?per_page=30') -Headers $headers
    } catch {
        Say ('Passed over ' + $what + ': GitHub would not give its jobs (' + $_.Exception.Message + ').')
        continue
    }
    $job = @($jobs.jobs | Where-Object { $JobNames -contains [string]$_.name -and @($_.steps | Where-Object { [string]$_.name -eq $StepName -and [string]$_.conclusion -eq 'success' }).Count } | Select-Object -First 1)
    if (-not $job.Count) { Say ('Passed over ' + $what + ': no launcher job of it got through "' + $StepName + '".'); continue }
    $logFile = Join-Path ([IO.Path]::GetTempPath()) ('gate-map-log-' + $job[0].id + '.txt')
    try {
        # The answer is a redirect to the log, and PowerShell 7 drops the
        # token on it, as it should.
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Method Get -Uri ($base + '/jobs/' + $job[0].id + '/logs') -Headers $headers -OutFile $logFile -UseBasicParsing
        $got = Read-HandedMap ([IO.File]::ReadAllLines($logFile))
    } catch {
        Say ('Passed over ' + $what + ': its log would not download (' + $_.Exception.Message + ').')
        continue
    } finally {
        Remove-Item -LiteralPath $logFile -Force -ErrorAction SilentlyContinue
    }
    if ($got -is [string]) { Say ('Passed over ' + $what + ': ' + $got + '.'); continue }
    if (Test-Path -LiteralPath $Fetch) { Remove-Item -LiteralPath $Fetch -Recurse -Force }
    $null = New-Item -ItemType Directory -Force -Path $Fetch
    [IO.File]::WriteAllBytes((Join-Path $Fetch ($got.Key + '.map.json')), $got.Map)
    [IO.File]::WriteAllBytes((Join-Path $Fetch ($got.Key + '.tree.gz')), $got.Tree)
    # read: when main's build handed it on, as the box's latest.json says when
    # the trace task read it.
    [IO.File]::WriteAllText((Join-Path $Fetch 'latest.json'), (([ordered]@{ key = $got.Key; commit = $got.Commit; read = ([datetime]$run.updated_at).ToUniversalTime().ToString('o') }) | ConvertTo-Json -Compress))
    Say ('The map ' + $what + ' handed on: the box''s trace of main ' + $got.Commit.Substring(0, 8) + ', build run ' + $got.Key + '.')
    exit 0
}
Say ('None of main''s ' + $runs.Count + ' newest finished builds handed on a map that could be read.')
exit 1
