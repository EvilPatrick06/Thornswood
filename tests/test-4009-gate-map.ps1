<#
  test-4009-gate-map.ps1

      pwsh -NoProfile -File .\tests\test-4009-gate-map.ps1

  Issue #4009: a pull request built off the box (One's runners, GitHub's
  hosted runner) had no traced map and ran the whole gate. Main's build now
  prints the box's newest map into its log (scripts\dev\Gate-Map.ps1 -Hand),
  and a gate off the box reads it back from main's newest finished builds
  (Gate-Map.ps1 -Fetch). This holds:

    1. -Hand on a box runner with a map prints the built map and the tree as
       numbered GATE-MAP pieces with each part's sha256, and with no map it
       prints none and still exits 0, so it never fails main's build;
    2. -Fetch, against a stand-in for GitHub's API, writes latest.json, the
       map and the tree from main's newest build that handed one on, and
       Affected-Harnesses.js pick picks from them as from the box's folder;
    3. it passes over a run that is not build.yml on a push to main of this
       repository, a job that did not get through the hand-on step, and a
       log whose pieces are missing or do not match their sha256, and says
       why; with nothing usable, or no token, it exits 1; it takes the
       token from GATE_MAP_TOKEN and leaves none in the environment, and
       nothing hands it one on a command line (#4079);
    4. build.yml no longer runs -Hand: only a main build on the box could,
       and none runs there since #4983. Since 31 Oct 2026 the gate runs in
       shares that read no map, so none is given the job's token.

  Writes only its scratch folder, in the system's temp folder, and deletes it.
#>
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" } else { $script:fail++; Write-Host "FAIL  $what" }
}
function Gzip([string]$text) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    $ms = New-Object IO.MemoryStream
    $gz = New-Object IO.Compression.GZipStream($ms, [IO.Compression.CompressionMode]::Compress)
    $gz.Write($bytes, 0, $bytes.Length); $gz.Close()
    , $ms.ToArray()
}

$gateMap = Join-Path (Join-Path (Join-Path $repo 'scripts') 'dev') 'Gate-Map.ps1'
$affected = Join-Path (Join-Path (Join-Path $repo 'scripts') 'dev') 'Affected-Harnesses.js'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('gate-map-' + [Guid]::NewGuid().ToString('N'))
$keepEnv = @{}
foreach ($n in 'RUNNER_ENVIRONMENT', 'RUNNER_TEMP', 'GITHUB_EVENT_NAME', 'GITHUB_REF', 'GATE_MAP_TOKEN') { $keepEnv[$n] = [Environment]::GetEnvironmentVariable($n) }
try {
    # ---- the box runner's folder, and the map the trace task left in it
    $root = Join-Path $scratch 'Thornswood-Runner'
    $temp = Join-Path (Join-Path $root '_work') '_temp'
    $maps = Join-Path $root 'gate-map'
    $null = New-Item -ItemType Directory -Force -Path $temp, $maps
    $key = '39800000001-1'
    $commit = ((& git -C $repo rev-parse HEAD) -join '').Trim()
    # Two harnesses: one reads README.md, which every commit has, one always
    # runs. Enough lines that the map takes more than one piece.
    $traces = @(
        '{"harness":"test-a.js","platform":"windows","listings":"enumerated","exit":0,"seconds":1,"skipped":false,"execs":["node.exe"],"paths":{"README.md":"read"}}',
        '{"harness":"test-c.js","platform":"windows","listings":"enumerated","exit":0,"seconds":1,"skipped":false,"always":"another process (git.exe) opened .git in the checkout while it ran","execs":["node.exe"],"paths":{}}'
    )
    for ($i = 0; $i -lt 400; $i++) { $traces += ('{"harness":"test-z' + $i + '.js","platform":"windows","listings":"enumerated","exit":0,"seconds":1,"skipped":false,"execs":["node.exe"],"paths":{"docs/z' + $i + '-' + [Guid]::NewGuid().ToString('N') + '.md":"read"}}') }
    [IO.File]::WriteAllBytes((Join-Path $maps ($key + '.traces.jsonl.gz')), (Gzip ($traces -join "`n")))
    $null = & node $affected tree $commit (Join-Path $maps ($key + '.tree.gz'))
    Set-Content -LiteralPath (Join-Path $maps 'latest.json') -Value ('{"key":"' + $key + '","commit":"' + $commit + '","read":"2026-10-27T03:00:00Z","harnesses":402}')

    # ---- 1. -Hand
    function Invoke-Hand([string]$event = 'push', [string]$ref = 'refs/heads/main') {
        $env:RUNNER_ENVIRONMENT = 'self-hosted'; $env:RUNNER_TEMP = $temp; $env:GITHUB_EVENT_NAME = $event; $env:GITHUB_REF = $ref
        $out = @(& pwsh -NoProfile -File $gateMap -Hand 2>&1 | ForEach-Object { "$_" })
        [pscustomobject]@{ Code = $LASTEXITCODE; Lines = $out; Text = ($out -join "`n") }
    }
    $h = Invoke-Hand
    $mapLines = @($h.Lines | Where-Object { $_ -match "^GATE-MAP $key $commit map \d+/\d+ " })
    $treeLines = @($h.Lines | Where-Object { $_ -match "^GATE-MAP $key $commit tree \d+/\d+ " })
    Yes ('-Hand on a box runner exits 0 and says which map (exit ' + $h.Code + ')') ($h.Code -eq 0 -and $h.Text -match ('Handing on the map of main ' + $commit.Substring(0, 8) + ', build run ' + $key))
    Yes ('  prints the map and the tree in numbered pieces (' + $mapLines.Count + ' and ' + $treeLines.Count + ')') ($mapLines.Count -ge 1 -and $treeLines.Count -ge 1 -and $mapLines[0] -match " map 1/$($mapLines.Count) ")
    Yes '  each piece one log line of at most 8000 characters of base64' (@($h.Lines | Where-Object { $_ -match '^GATE-MAP .* \d+/\d+ (\S+)$' -and $Matches[1].Length -gt 8000 }).Count -eq 0)
    Yes '  and each part''s sha256' (@($h.Lines | Where-Object { $_ -match "^GATE-MAP $key $commit (map|tree) sha256 [0-9a-f]{64}$" }).Count -eq 2)
    Yes '  and leaves nothing of its own in the runner''s temp folder' (-not @(Get-ChildItem -LiteralPath $temp).Count)
    $pr = Invoke-Hand 'pull_request' 'refs/pull/7/merge'
    Yes '-Hand in a pull request''s build prints no map, and exits 0' ($pr.Code -eq 0 -and $pr.Text -match 'only main''s push build' -and $pr.Text -notmatch 'GATE-MAP ')
    $br = Invoke-Hand 'push' 'refs/heads/my-branch'
    Yes '  nor in a branch''s push build' ($br.Code -eq 0 -and $br.Text -notmatch 'GATE-MAP ')
    Move-Item -LiteralPath (Join-Path $maps 'latest.json') -Destination (Join-Path $scratch 'latest.json')
    $none = Invoke-Hand
    Yes '-Hand with no map prints none and exits 0, so main''s build never fails on it' ($none.Code -eq 0 -and $none.Text -match 'No map handed on' -and $none.Text -notmatch 'GATE-MAP ')
    Move-Item -LiteralPath (Join-Path $scratch 'latest.json') -Destination (Join-Path $maps 'latest.json')
    $env:RUNNER_ENVIRONMENT = 'github-hosted'
    $off = @(& pwsh -NoProfile -File $gateMap -Hand 2>&1 | ForEach-Object { "$_" })
    Yes '  and so does a runner off the box' ($LASTEXITCODE -eq 0 -and ($off -join "`n") -match 'No map handed on' -and ($off -join "`n") -notmatch 'GATE-MAP ')

    # ---- 2. and 3. -Fetch, against a stand-in for GitHub
    # A job log is the step's lines with GitHub's timestamp before each.
    function Log([string[]]$lines) { $lines | ForEach-Object { '2026-10-27T03:30:00.0000000Z ' + $_ } }
    $good = Log $h.Lines
    $broken = Log @($h.Lines | ForEach-Object { if ($_ -match "^GATE-MAP .* map 1/") { $_.Substring(0, $_.Length - 8) + 'AAAAAAAA' } else { $_ } })
    $short = Log @($h.Lines | Where-Object { $_ -notmatch "^GATE-MAP .* tree 1/" })
    $step = @{ name = 'Hand the traced map to runners off the box'; conclusion = 'success' }
    function Run([long]$id, [string]$event = 'push', [string]$branch = 'main', [string]$path = '.github/workflows/build.yml', [string]$repoName = 'o/r') {
        @{ id = $id; event = $event; head_branch = $branch; path = $path; head_repository = @{ full_name = $repoName }; head_sha = $commit; updated_at = '2026-10-27T03:31:00Z' }
    }
    $global:GateMapStub = $null
    $global:GateMapAsked = @()
    function global:Invoke-RestMethod {
        param([string]$Method, [string]$Uri, $Headers)
        $global:GateMapAsked += $Uri
        if ($Headers.Authorization -ne 'Bearer t0ken') { throw 'no token' }
        if ($Uri -match '/workflows/build\.yml/runs\?branch=main&event=push&status=completed') { return @{ workflow_runs = $global:GateMapStub.Runs } }
        if ($Uri -match '/runs/(\d+)/jobs') { return @{ jobs = $global:GateMapStub.Jobs[$Matches[1]] } }
        throw ('no stand-in for ' + $Uri)
    }
    function global:Invoke-WebRequest {
        param([string]$Method, [string]$Uri, $Headers, [string]$OutFile, [switch]$UseBasicParsing)
        if ($Uri -notmatch '/jobs/(\d+)/logs$') { throw ('no stand-in for ' + $Uri) }
        [IO.File]::WriteAllLines($OutFile, [string[]]$global:GateMapStub.Logs[$Matches[1]])
    }
    $fetched = Join-Path $scratch 'fetched'
    function Invoke-Fetch([string]$token = 't0ken') {
        Remove-Item -LiteralPath $fetched -Recurse -Force -ErrorAction SilentlyContinue
        $env:GATE_MAP_TOKEN = $token
        $out = @(& $gateMap -Fetch $fetched -Repository 'o/r' 6>&1 | ForEach-Object { "$_" })
        [pscustomobject]@{ Code = $LASTEXITCODE; Text = ($out -join "`n"); Left = (Test-Path -LiteralPath Env:GATE_MAP_TOKEN) }
    }
    $job = { param($id, $name = 'Launcher builds (VPS fallback)', $s = $step) @(@{ id = $id; name = $name; steps = @(@{ name = 'Run the gate harnesses'; conclusion = 'success' }, $s) }) }

    $global:GateMapStub = @{ Runs = @((Run 900)); Jobs = @{ '900' = (& $job 9001) }; Logs = @{ '9001' = $good } }
    $f = Invoke-Fetch
    Yes ('-Fetch writes main''s newest handed-on map (exit ' + $f.Code + ')') ($f.Code -eq 0 -and $f.Text -match 'run 900 handed on' -and (Test-Path -LiteralPath (Join-Path $fetched 'latest.json')))
    Yes '  taking its token from GATE_MAP_TOKEN, which it leaves out of the environment' (-not $f.Left)
    $lj = $null
    if (Test-Path -LiteralPath (Join-Path $fetched 'latest.json')) { $lj = [IO.File]::ReadAllText((Join-Path $fetched 'latest.json')) | ConvertFrom-Json }
    Yes '  latest.json names the box''s run and commit' ($lj -and $lj.key -eq $key -and $lj.commit -eq $commit)
    $built = Join-Path $scratch 'built.json'
    $null = & node $affected build (Join-Path $maps ($key + '.traces.jsonl.gz')) $built $commit
    Yes '  the map is the one main''s build built, byte for byte' ((Test-Path -LiteralPath (Join-Path $fetched ($key + '.map.json'))) -and ([IO.File]::ReadAllText($built) -eq [IO.File]::ReadAllText((Join-Path $fetched ($key + '.map.json')))))
    Yes '  and the tree the box''s' ((Get-FileHash -LiteralPath (Join-Path $fetched ($key + '.tree.gz'))).Hash -eq (Get-FileHash -LiteralPath (Join-Path $maps ($key + '.tree.gz'))).Hash)
    $gateFile = Join-Path $scratch 'gate.txt'
    $picked = Join-Path $scratch 'picked.txt'
    [IO.File]::WriteAllLines($gateFile, [string[]]@('test-a.js', 'test-c.js', 'test-z1.js'))
    $p = @(& node $affected pick (Join-Path $fetched ($key + '.map.json')) (Join-Path $fetched ($key + '.tree.gz')) $commit $gateFile $picked 2>&1 | ForEach-Object { "$_" })
    Yes ('Affected-Harnesses.js pick picks from it as from the box''s folder: ' + (($p | Select-Object -First 1) -join '')) ($LASTEXITCODE -eq 0 -and @([IO.File]::ReadAllLines($picked)) -join ' ' -eq 'test-c.js')
    $p = @(& node $affected pick (Join-Path $fetched ($key + '.map.json')) (Join-Path $fetched ($key + '.tree.gz')) ('0' * 40) $gateFile $picked 2>&1 | ForEach-Object { "$_" })
    Yes '  and refuses a map of another commit than latest.json names' ($LASTEXITCODE -ne 0)

    $global:GateMapStub = @{
        Runs = @((Run 905 'pull_request'), (Run 904 'push' 'my-branch'), (Run 903 'push' 'main' '.github/workflows/build-pr.yml'), (Run 902 'push' 'main' '.github/workflows/build.yml' 'fork/r'), (Run 901), (Run 900))
        Jobs = @{ '901' = (& $job 9011 'Launcher builds (VPS fallback)' @{ name = 'Hand the traced map to runners off the box'; conclusion = 'skipped' }); '900' = (& $job 9001) }
        Logs = @{ '9001' = $good }
    }
    $f = Invoke-Fetch
    Yes ('-Fetch passes over a pull request''s run, a branch''s, another workflow''s and a fork''s (exit ' + $f.Code + ')') ($f.Code -eq 0 -and $f.Text -match 'Passed over run 905' -and $f.Text -match 'Passed over run 904' -and $f.Text -match 'Passed over run 903' -and $f.Text -match 'Passed over run 902')
    Yes '  and a build whose job did not get through the hand-on step, and takes the next' ($f.Text -match 'run 901: no launcher job' -and $f.Text -match 'run 900 handed on')
    Yes '  and never reads a passed-over run''s jobs' (-not @($global:GateMapAsked | Where-Object { $_ -match '/runs/(90[2-5])/jobs' }).Count)

    $global:GateMapStub = @{ Runs = @((Run 911), (Run 910)); Jobs = @{ '911' = (& $job 9111); '910' = (& $job 9101) }; Logs = @{ '9111' = $broken; '9101' = $short } }
    $f = Invoke-Fetch
    Yes ('a log whose piece does not match its sha256, or that lacks one, is passed over, and with nothing else it exits 1 (exit ' + $f.Code + ')') ($f.Code -eq 1 -and $f.Text -match 'run 911: its map does not match its sha256' -and $f.Text -match 'run 910: its log lacks piece 1 of the tree' -and -not (Test-Path -LiteralPath (Join-Path $fetched 'latest.json')))
    $global:GateMapStub = @{ Runs = @((Run 920)); Jobs = @{ '920' = (& $job 9201) }; Logs = @{ '9201' = @('2026-10-27T03:30:00.0000000Z nothing here') } }
    $f = Invoke-Fetch
    Yes '  so is a log with no map' ($f.Code -eq 1 -and $f.Text -match 'its log holds no map')
    $f = Invoke-Fetch ''
    Yes 'with no token it exits 1 and asks GitHub nothing' ($f.Code -eq 1 -and $f.Text -match 'No token')
} finally {
    Remove-Item -LiteralPath Function:\Invoke-RestMethod, Function:\Invoke-WebRequest, Variable:\GateMapStub, Variable:\GateMapAsked -ErrorAction SilentlyContinue
    foreach ($n in $keepEnv.Keys) { [Environment]::SetEnvironmentVariable($n, $keepEnv[$n]) }
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

# ---- 4. build.yml
$b = [IO.File]::ReadAllText((Join-Path (Join-Path (Join-Path $repo '.github') 'workflows') 'build.yml')).Replace("`r`n", "`n")
Yes 'build.yml no longer hands a map on, since no build of it runs on the box (#4983)' (-not $b.Contains('Gate-Map.ps1 -Hand') -and $b.IndexOf("        id: gate`n") -gt 0)
# 31 Oct 2026: the gate runs in shares (the job "gate"), each a share of the
# whole gate that reads no map, since none can be handed on.
Yes '  and gives the gate''s shares no token, as they read no map' (-not $b.Contains('GATE_MAP_TOKEN:'))
Yes '  and the build job may read another run''s job logs' (([regex]::Matches($b, '(?m)^    permissions:\n      actions: read\n      contents: read\n')).Count -ge 1)
$rg = [IO.File]::ReadAllText((Join-Path (Join-Path (Join-Path $repo 'scripts') 'dev') 'Run-Gate.ps1'))
Yes 'Run-Gate.ps1 hands Gate-Map.ps1 no token on its command line (#4079)' ($rg.Contains("& (Join-Path `$Here 'Gate-Map.ps1') -Fetch `$maps 2>&1") -and -not ($rg -match '-Token\b'))
Yes 'Run-Gate.ps1 takes the token out of the environment before any harness starts' ($rg.IndexOf('Remove-Item -LiteralPath Env:GATE_MAP_TOKEN') -gt 0 -and $rg.IndexOf('Remove-Item -LiteralPath Env:GATE_MAP_TOKEN') -lt $rg.IndexOf("& (Join-Path `$Here 'Nightly-Harnesses.ps1')"))

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
