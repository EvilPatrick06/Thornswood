<#
  test-3114-run-gate.ps1

      pwsh -NoProfile -File .\tests\test-3114-run-gate.ps1

  Issue #3114, Patrick's option A on q-3114-map-refresh (22 Oct 2026): every
  main build's gate is traced on the VPS by the trace task
  (scripts\dev\Trace-Gate-Task.ps1), and a pull request built there runs
  only the gate harnesses its change can reach, by the newest map.
  scripts\dev\Run-Gate.ps1 is build.yml's gate step. This runs it for real
  in a scratch repository, with Gate-Harnesses.ps1 and Nightly-Harnesses.ps1
  replaced by stand-ins that list three harnesses and write down what they
  were asked to run, and a scratch runner folder standing in for the box's:

    1. a pull request on the VPS with a map runs the harnesses that read
       what it changed and those that always run, says why each runs, and
       says nothing of whole, so its build keeps no "already tested" note;
       a change nothing reads runs only those that always run;
    2. it runs the whole gate, and says whole=true, with no map, on a
       GitHub-hosted runner, with a map that does not read, and when it
       changes Run-Gate.ps1 itself;
    3. a main build on the VPS asks the trace task in <runner>\trace with
       its run, commit, checkout and process, writes the tree, runs the gate
       with -StartLog when the answer is tracing, and says done with the
       gate's exit code; with no answer, or no trace folder, it runs the
       whole gate untraced and takes its ask back;
    4. the gate's exit code is the step's, and -StartLog given by hand
       (trace-gate.yml) reaches Nightly-Harnesses.ps1;
    5. the trace task (scripts\dev\Trace-Gate-Task.ps1) parses, looks only
       in the build runners' folders it was installed for, and on Windows
       its check of an ask is run for real: an ask is refused unless it
       names a run never asked for, a full commit, a running process with
       its own start time, and a checkout inside that runner's own _work
       folder reached through no link.

  Writes only its scratch folder, in the system's temp folder, and deletes it.
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Windows.ps1')
$repo = Split-Path -Parent $PSScriptRoot
$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" } else { $script:fail++; Write-Host "FAIL  $what" }
}
function GitOk { $o = @(& git @args 2>&1); if ($LASTEXITCODE -ne 0) { throw ('git ' + ($args -join ' ') + ': ' + ($o -join ' ')) }; $o }
function Gzip([string]$text) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    $ms = New-Object IO.MemoryStream
    $gz = New-Object IO.Compression.GZipStream($ms, [IO.Compression.CompressionMode]::Compress)
    $gz.Write($bytes, 0, $bytes.Length); $gz.Close()
    , $ms.ToArray()
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('run-gate-' + [Guid]::NewGuid().ToString('N'))
$keepEnv = @{}
foreach ($n in 'RUNNER_ENVIRONMENT', 'RUNNER_TEMP', 'GITHUB_EVENT_NAME', 'GITHUB_REF', 'GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT', 'GITHUB_OUTPUT', 'STUB_RECORD', 'STUB_CODE') {
    $keepEnv[$n] = [Environment]::GetEnvironmentVariable($n)
}
$here = Get-Location
try {
    # ---- the scratch repository, with stand-ins for the lister and the runner
    $sr = Join-Path $scratch 'repo'
    $dev = Join-Path (Join-Path $sr 'scripts') 'dev'
    $null = New-Item -ItemType Directory -Force -Path $dev, (Join-Path $sr 'records')
    foreach ($f in 'Run-Gate.ps1', 'Affected-Harnesses.js') { Copy-Item -LiteralPath (Join-Path (Join-Path (Join-Path $repo 'scripts') 'dev') $f) -Destination $dev }
    Set-Content -LiteralPath (Join-Path $dev 'Gate-Harnesses.ps1') -Value "'test-a.js'`n'test-b.js'`n'test-c.js'`nexit 0"
    Set-Content -LiteralPath (Join-Path $dev 'Nightly-Harnesses.ps1') -Value @'
param([string]$Only = '', [int]$Throttle = 0, [int]$Share = 0, [int]$BudgetSeconds = 0, [string]$StartLog = '')
[IO.File]::WriteAllText($env:STUB_RECORD, (@{ Only = $Only; StartLog = $StartLog; Throttle = $Throttle; Share = $Share; Budget = $BudgetSeconds } | ConvertTo-Json -Compress))
if ($StartLog) { [IO.File]::WriteAllText($StartLog, "{`"name`":`"test-a.js`",`"pid`":1}`n") }
exit [int]$env:STUB_CODE
'@
    Set-Content -LiteralPath (Join-Path (Join-Path $sr 'records') 'build-runners.json') -Value '{"runners":[1,2]}'
    foreach ($f in 'a.txt', 'b.txt', 'd.txt') { Set-Content -LiteralPath (Join-Path $sr $f) -Value $f }
    $null = GitOk init -q $sr
    $null = GitOk -C $sr config user.name 'Run gate test'
    $null = GitOk -C $sr config user.email 'run-gate-test@example.invalid'
    $null = GitOk -C $sr config core.autocrlf false
    $null = GitOk -C $sr add -A
    $null = GitOk -C $sr commit -q -m base
    $base = ((GitOk -C $sr rev-parse HEAD) -join '').Trim()
    Set-Location -LiteralPath $sr

    # ---- the runner's folder, and the map the trace task left in it
    $root = Join-Path $scratch 'Thornswood-Runner'
    $temp = Join-Path (Join-Path $root '_work') '_temp'
    $maps = Join-Path $root 'gate-map'
    $null = New-Item -ItemType Directory -Force -Path $temp, $maps
    $key = '39800000001-1'
    $traces = @(
        '{"harness":"test-a.js","platform":"windows","listings":"enumerated","exit":0,"seconds":1,"skipped":false,"execs":["node.exe"],"paths":{"a.txt":"read"}}',
        '{"harness":"test-b.js","platform":"windows","listings":"enumerated","exit":0,"seconds":1,"skipped":false,"execs":["node.exe"],"paths":{"b.txt":"read"}}',
        '{"harness":"test-c.js","platform":"windows","listings":"enumerated","exit":0,"seconds":1,"skipped":false,"always":"another process (git.exe) opened .git in the checkout while it ran","execs":["node.exe"],"paths":{}}'
    ) -join "`n"
    [IO.File]::WriteAllBytes((Join-Path $maps ($key + '.traces.jsonl.gz')), (Gzip $traces))
    & node (Join-Path $dev 'Affected-Harnesses.js') tree HEAD (Join-Path $maps ($key + '.tree.gz'))
    Yes 'Affected-Harnesses.js tree lists a commit''s tree' ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath (Join-Path $maps ($key + '.tree.gz'))))
    $latest = Join-Path $maps 'latest.json'
    Set-Content -LiteralPath $latest -Value ('{"key":"' + $key + '","commit":"' + $base + '","read":"2026-10-22T14:00:00Z","harnesses":3}')

    $record = Join-Path $scratch 'nightly.json'
    $outFile = Join-Path $scratch 'output.txt'
    # Run-Gate.ps1 as the gate step runs it, on the event given; what it
    # printed, its exit code, what the stand-in was asked and its outputs.
    function Invoke-Gate([string]$event, [string]$runner = 'self-hosted', [string[]]$extra = @(), [int]$code = 0) {
        Remove-Item -LiteralPath $record, $outFile -Force -ErrorAction SilentlyContinue
        $env:RUNNER_ENVIRONMENT = $runner; $env:RUNNER_TEMP = $temp; $env:GITHUB_EVENT_NAME = $event
        $env:GITHUB_REF = $(if ($event -eq 'push') { 'refs/heads/main' } else { 'refs/pull/7/merge' })
        $env:GITHUB_RUN_ID = '39800000002'; $env:GITHUB_RUN_ATTEMPT = '1'
        $env:GITHUB_OUTPUT = $outFile; $env:STUB_RECORD = $record; $env:STUB_CODE = [string]$code
        $out = @(& pwsh -NoProfile -File (Join-Path $dev 'Run-Gate.ps1') -Throttle 6 -BudgetSeconds 1800 @extra 2>&1 | ForEach-Object { "$_" })
        $rc = $LASTEXITCODE
        $asked = $null
        if (Test-Path -LiteralPath $record) { $asked = [IO.File]::ReadAllText($record) | ConvertFrom-Json }
        $outputs = ''
        if (Test-Path -LiteralPath $outFile) { $outputs = [IO.File]::ReadAllText($outFile) }
        [pscustomobject]@{ Code = $rc; Text = ($out -join "`n"); Asked = $asked; Whole = ($outputs -match '(?m)^whole=true\s*$') }
    }

    # ---- 1. a pull request on the VPS, with a map
    Set-Content -LiteralPath (Join-Path $sr 'a.txt') -Value 'a, changed'
    $null = GitOk -C $sr commit -q -am 'change a'
    $r = Invoke-Gate 'pull_request'
    Yes ('a pull request runs what its change reaches and what always runs (' + $(if ($r.Asked) { $r.Asked.Only } else { 'nothing' }) + ')') ($r.Code -eq 0 -and $r.Asked -and $r.Asked.Only -eq 'test-a.js test-c.js')
    Yes '  with the throttle, the share and the budget' ($r.Asked -and $r.Asked.Throttle -eq 6 -and $r.Asked.Budget -eq 1800 -and $r.Asked.Share -ge 1)
    Yes '  says which map, and why each one runs' ($r.Text -match ('main ' + $base.Substring(0, 8)) -and $r.Text -match 'runs test-a\.js: reads a\.txt' -and $r.Text -match 'runs test-c\.js: always' -and $r.Text -match '2 of 3 gate harnesses')
    Yes '  and does not say whole, so it keeps no note' (-not $r.Whole)

    $null = GitOk -C $sr reset -q --hard $base
    Set-Content -LiteralPath (Join-Path $sr 'd.txt') -Value 'd, changed'
    $null = GitOk -C $sr commit -q -am 'change d'
    $r = Invoke-Gate 'pull_request'
    Yes 'a change nothing reads runs only what always runs' ($r.Asked -and $r.Asked.Only -eq 'test-c.js' -and -not $r.Whole)

    # ---- 2. the whole gate
    $r = Invoke-Gate 'pull_request' 'github-hosted'
    Yes 'a GitHub-hosted runner, which has no map, runs the whole gate and says whole' ($r.Asked -and $r.Asked.Only -eq 'test-a.js test-b.js test-c.js' -and $r.Whole -and $r.Text -match 'The whole gate runs')
    Move-Item -LiteralPath $latest -Destination ($latest + '.away')
    $r = Invoke-Gate 'pull_request'
    Yes 'so does a runner with no map yet' ($r.Asked -and $r.Asked.Only -eq 'test-a.js test-b.js test-c.js' -and $r.Whole -and $r.Text -match 'no traced map')
    Set-Content -LiteralPath $latest -Value '{"key":"nothing","commit":"x"}'
    $r = Invoke-Gate 'pull_request'
    Yes 'and one whose map names no commit' ($r.Asked -and $r.Asked.Only -eq 'test-a.js test-b.js test-c.js' -and $r.Whole)
    Remove-Item -LiteralPath $latest
    Move-Item -LiteralPath ($latest + '.away') -Destination $latest
    Copy-Item -LiteralPath (Join-Path $maps ($key + '.tree.gz')) -Destination (Join-Path $scratch 'tree.gz')
    [IO.File]::WriteAllText((Join-Path $maps ($key + '.tree.gz')), 'not gzip')
    $r = Invoke-Gate 'pull_request'
    Yes 'and one whose map does not read, saying pick failed' ($r.Asked -and $r.Asked.Only -eq 'test-a.js test-b.js test-c.js' -and $r.Whole -and $r.Text -match 'pick failed')
    Copy-Item -LiteralPath (Join-Path $scratch 'tree.gz') -Destination (Join-Path $maps ($key + '.tree.gz')) -Force
    Add-Content -LiteralPath (Join-Path $dev 'Run-Gate.ps1') -Value '# a change to the script that chooses'
    $null = GitOk -C $sr commit -q -am 'change Run-Gate'
    $r = Invoke-Gate 'pull_request'
    Yes 'a change to Run-Gate.ps1 runs the whole gate and says whole' ($r.Asked -and $r.Asked.Only -eq 'test-a.js test-b.js test-c.js' -and $r.Whole -and $r.Text -match 'Run-Gate\.ps1: the scripts that list, choose and run')
    $null = GitOk -C $sr reset -q --hard $base

    # ---- 3. a main build on the VPS
    $r = Invoke-Gate 'push'
    Yes 'a main build with no trace folder runs the whole gate untraced and says whole' ($r.Asked -and $r.Asked.Only -eq 'test-a.js test-b.js test-c.js' -and -not $r.Asked.StartLog -and $r.Whole -and $r.Text -match 'Not traced: there is no')
    $trace = Join-Path $root 'trace'
    $null = New-Item -ItemType Directory -Path $trace
    # The trace task, standing in: takes the ask and answers tracing.
    $task = Start-Job -ArgumentList $trace -ScriptBlock {
        param($dir)
        $ask = Join-Path $dir 'ask.json'
        for ($i = 0; $i -lt 300 -and -not (Test-Path -LiteralPath $ask); $i++) { Start-Sleep -Milliseconds 100 }
        if (-not (Test-Path -LiteralPath $ask)) { return 'no ask' }
        $text = [IO.File]::ReadAllText($ask)
        Remove-Item -LiteralPath $ask
        $a = $text | ConvertFrom-Json
        [IO.File]::WriteAllText((Join-Path $dir 'answer.json'), ('{"key":"' + $a.key + '","state":"tracing","why":""}'))
        $text
    }
    $r = Invoke-Gate 'push' -code 3
    $askText = @(Receive-Job -Job $task -Wait -AutoRemoveJob) -join ''
    $a = $null
    try { $a = $askText | ConvertFrom-Json } catch { Write-Host "the ask was not JSON: $askText" }
    $me = $null
    Yes ('a main build asks with its run, commit, checkout and process (' + $askText + ')') ($a -and $a.key -eq '39800000002-1' -and $a.commit -eq $base -and $a.workspace -eq $sr -and [int]$a.pid -gt 0 -and ($a.started -is [datetime] -or [string]$a.started -match '^\d{4}-\d\d-\d\dT'))
    Yes '  having listed its tree for the map' (Test-Path -LiteralPath (Join-Path $trace 'tree.gz'))
    Yes '  runs the whole gate with -StartLog in the runner''s trace folder' ($r.Asked -and $r.Asked.Only -eq 'test-a.js test-b.js test-c.js' -and $r.Asked.StartLog -eq (Join-Path $trace 'starts.jsonl') -and (Test-Path -LiteralPath (Join-Path $trace 'starts.jsonl')))
    $done = $null
    if (Test-Path -LiteralPath (Join-Path $trace 'done.json')) { $done = [IO.File]::ReadAllText((Join-Path $trace 'done.json')) | ConvertFrom-Json }
    Yes '  says done, with the run and the gate''s exit code' ($done -and $done.key -eq '39800000002-1' -and [int]$done.code -eq 3)
    Yes '  and the gate''s exit code is the step''s' ($r.Code -eq 3 -and $r.Text -match 'Traced: ')
    Yes '  and says whole, as it ran every harness' ($r.Whole)
    $r = Invoke-Gate 'push' -extra @('-AnswerSeconds', '2')
    Yes 'with no answer it runs untraced and takes its ask back' ($r.Asked -and -not $r.Asked.StartLog -and $r.Text -match 'did not answer' -and -not (Test-Path -LiteralPath (Join-Path $trace 'ask.json')) -and -not (Test-Path -LiteralPath (Join-Path $trace 'done.json')))

    # ---- 4. by hand
    $r = Invoke-Gate 'workflow_dispatch' -extra @('-StartLog', (Join-Path $scratch 'hand.jsonl'))
    Yes 'a dispatch runs the whole gate with the -StartLog it was given (trace-gate.yml)' ($r.Asked -and $r.Asked.Only -eq 'test-a.js test-b.js test-c.js' -and $r.Asked.StartLog -eq (Join-Path $scratch 'hand.jsonl') -and $r.Whole)
} finally {
    Set-Location -LiteralPath $here
    foreach ($n in $keepEnv.Keys) { [Environment]::SetEnvironmentVariable($n, $keepEnv[$n]) }
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

# ---- 5. the trace task
$taskFile = Join-Path (Join-Path (Join-Path $repo 'scripts') 'dev') 'Trace-Gate-Task.ps1'
$tt = [IO.File]::ReadAllText($taskFile)
$errs = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($tt, [ref]$null, [ref]$errs)
Yes 'Trace-Gate-Task.ps1 parses' (-not @($errs).Count)
Yes '  looks only in the build runners'' folders it was installed for' ($tt -match "(?m)^\`$runners = @\(\(\[IO\.File\]::ReadAllText\(\(Join-Path \`$Here 'task\.json'\)\) \| ConvertFrom-Json\)\.runners\)\s*$" -and $tt -match '(?m)^\s+foreach \(\$w in \$runners\) \{\s*$')
Yes '  reads at below normal priority, one read at a time, and deletes each trace' ($tt -match "PriorityClass = 'BelowNormal'" -and $tt -match "Remove-Item -LiteralPath \`$Read -Recurse -Force")
Yes '  stops a trace whose build ended without saying so, ran too long, or lost events' ($tt -match "elseif \(-not \(Test-Alive \`$script:active\.Ask\)\) \{ Stop-Active" -and $tt -match 'TotalMinutes -gt \$MaxMinutes\) \{ Stop-Active' -and $tt -match 'if \(\$script:lost\) \{ Stop-Active')
$fns = @{}
foreach ($f in $ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] }, $true)) { $fns[$f.Name] = $f.Extent.Text }
Yes '  has its check of an ask as Get-Ask' ($fns.ContainsKey('Get-Ask') -and $fns.ContainsKey('Test-Linked'))
if ($OnWindows -and $fns.ContainsKey('Get-Ask')) {
    $box = Join-Path ([IO.Path]::GetTempPath()) ('run-gate-task-' + [Guid]::NewGuid().ToString('N'))
    try {
        $w = [pscustomobject]@{ root = (Join-Path $box 'Thornswood-Runner') }
        $ws = Join-Path $w.root '_work\Thornswood\Thornswood'
        $outside = Join-Path $box 'elsewhere'
        $null = New-Item -ItemType Directory -Force -Path $ws, (Join-Path $w.root 'trace'), $outside
        $null = New-Item -ItemType Junction -Path (Join-Path $w.root '_work\linked') -Target $outside
        . ([ScriptBlock]::Create($fns['Get-Ask'] + "`n" + $fns['Test-Linked']))
        $script:seen = New-Object 'System.Collections.Generic.HashSet[string]'
        $null = $script:seen.Add('1-1')
        $me = [Diagnostics.Process]::GetCurrentProcess()
        function Ask($o) {
            $text = $(if ($o -is [string]) { $o } else { $o | ConvertTo-Json -Compress })
            [IO.File]::WriteAllText((Join-Path $w.root 'trace\ask.json'), $text)
            Get-Ask $w
        }
        $good = [ordered]@{ key = '2-1'; commit = ('b' * 40); workspace = $ws; pid = $me.Id; started = $me.StartTime.ToUniversalTime().ToString('o') }
        $a = Ask $good
        Yes ('on Windows, a good ask is taken (' + $a.Why + ')') ($a.Key -eq '2-1' -and $a.Why -eq '' -and $a.Workspace -eq $ws -and -not (Test-Path -LiteralPath (Join-Path $w.root 'trace\ask.json')))
        $cases = @(
            @{ What = 'a run asked for before'; Set = @{ key = '1-1' }; Want = 'asked for once' },
            @{ What = 'no full commit'; Set = @{ commit = 'abc' }; Want = 'no full commit' },
            @{ What = 'a checkout outside the runner''s _work'; Set = @{ workspace = $outside }; Want = 'not a folder in' },
            @{ What = 'a checkout named through ..'; Set = @{ workspace = ($ws + '\..\..\..\..\elsewhere') }; Want = 'not a folder in' },
            @{ What = 'a checkout reached through a link'; Set = @{ workspace = (Join-Path $w.root '_work\linked') }; Want = 'through a link' },
            @{ What = 'no process'; Set = @{ pid = 'x' }; Want = 'no process' }
        )
        foreach ($c in $cases) {
            $o = [ordered]@{}; foreach ($k in $good.Keys) { $o[$k] = $good[$k] }
            foreach ($k in $c.Set.Keys) { $o[$k] = $c.Set[$k] }
            $a = Ask $o
            Yes ('  refused: ' + $c.What + ' (' + $a.Why + ')') ($a.Why -match $c.Want)
        }
        $a = Ask 'not json'
        Yes '  refused, with no run to answer: what is not JSON' ($a.Key -eq '' -and $a.Why -match 'not JSON')
    } finally {
        Remove-Item -LiteralPath $box -Recurse -Force -ErrorAction SilentlyContinue
    }
} else {
    Write-Host 'SKIP  the check of an ask runs only on Windows, where the box is'
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
