<#
  test-5148-engine-pin.ps1

      pwsh -NoProfile -File .\tests\test-5148-engine-pin.ps1

  Issue #5148: the engine pin follows the fork by itself. This holds
    1. the pin blocks of THIRD-PARTY.md and site\data\site\credits.md to the
       records, as Write-EnginePinText.ps1 -Check does, so a hand edit inside
       one, or a record moved without the pages, is red here;
    2. Update-EnginePinText over a planted checkout: a moved record makes
       -Check name the blocks, a write makes them match, the page keeps its
       own line ends, the text outside the blocks is left as it was, and main's
       engine is read from the page and kept;
    3. Get-EnginePinStep over stand-in GitHub answers, one for each step
       engine-pin.yml takes, and that it never starts engine.yml again for a
       head whose record ended red;
    4. Get-EnginePinNotes: the fork pull requests by merge commit, the
       Thornswood issues they name, and their Test tasks in the shape
       done-on-merge.yml reads;
    5. engine-pin.yml's shape: the tick, the three jobs, which token each
       holds, that only the read only job runs the npm build, every action by
       commit, and no secret or self-hosted runner;
    6. that engine.yml's runs carry the commit in their title, that
       build-pr.yml can be started on the pin branch, and that the record of
       GitHub's settings lets the run's token open pull requests (Patrick's
       yes, 31 Oct 2026).

  Read only, apart from a planted folder under TEMP, which it removes. Runs
  anywhere pwsh runs and asks GitHub nothing.
#>
[CmdletBinding()]
param()
$env:THORNSWOOD_HARNESS = '1'
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$root = Split-Path -Parent $Here
. (Join-Path $root 'scripts/release/ForkEngineBuild.ps1')
. (Join-Path $root 'scripts/release/EnginePin.ps1')

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

# ---- 1. the pages match the records ------------------------------------------
$diff = @(Update-EnginePinText -Repo $root -Check)
Yes ('every pin block of THIRD-PARTY.md and credits.md matches the records (' + $(if ($diff.Count) { 'differs: ' + ($diff -join '; ') } else { 'all five' }) + ')') ($diff.Count -eq 0)
$facts = Get-EnginePinFacts $root
Yes 'the records name one engine, and the facts read from them' ($facts.Commit -match '^[0-9a-f]{40}$' -and $facts.ServerSha256 -match '^[0-9a-f]{64}$' -and $facts.FrontFiles -gt 0)

# ---- 2. a planted checkout ---------------------------------------------------
$plant = Join-Path ([IO.Path]::GetTempPath()) ('test-5148-' + [Guid]::NewGuid().ToString('N').Substring(0, 10))
try {
    foreach ($d in 'records', 'site/data/site') { $null = New-Item -ItemType Directory -Force -Path (Join-Path $plant $d) }
    foreach ($f in 'records/server-build.json', 'records/client-build.json', 'records/front-build.json', 'site/data/site/credits.md') {
        Copy-Item -LiteralPath (Join-Path $root $f) -Destination (Join-Path $plant $f)
    }
    # THIRD-PARTY.md with CR LF, as a Windows checkout holds it.
    $tp = [IO.File]::ReadAllText((Join-Path $root 'THIRD-PARTY.md')).Replace("`r`n", "`n").Replace("`n", "`r`n")
    [IO.File]::WriteAllText((Join-Path $plant 'THIRD-PARTY.md'), $tp, (New-Object Text.UTF8Encoding($false)))
    $main = Get-EnginePinMain $plant
    Yes 'the engine main runs is read from "On our servers"' ($main -match '^[0-9a-f]{40}$')
    Yes 'the planted checkout matches as it is, CR LF and all' (@(Update-EnginePinText -Repo $plant -Check).Count -eq 0)

    $new = 'abcdef0123456789abcdef0123456789abcdef01'
    $sp = Join-Path $plant 'records/server-build.json'
    $s = [IO.File]::ReadAllText($sp) | ConvertFrom-Json
    $s.source.commit = $new; $s.sha256 = ('5' * 64)
    [IO.File]::WriteAllText($sp, ($s | ConvertTo-Json -Depth 10))
    foreach ($n in 'client-build.json', 'front-build.json') {
        $p = Join-Path $plant "records/$n"
        $j = [IO.File]::ReadAllText($p) | ConvertFrom-Json
        $j.forkCommit = $(if ($n -eq 'client-build.json') { $new.Substring(0, 8) } else { $new })
        [IO.File]::WriteAllText($p, ($j | ConvertTo-Json -Depth 10))
    }
    $named = @(Update-EnginePinText -Repo $plant -Check)
    Yes ('a moved record makes -Check name all five blocks (' + ($named -join '; ') + ')') ($named.Count -eq 5)
    $wrote = @(Update-EnginePinText -Repo $plant)
    Yes 'a write changes the two pages' ($wrote.Count -eq 2)
    Yes '  and then every block matches' (@(Update-EnginePinText -Repo $plant -Check).Count -eq 0)
    $after = [IO.File]::ReadAllText((Join-Path $plant 'THIRD-PARTY.md'))
    Yes '  THIRD-PARTY.md keeps its CR LF line ends' (-not ($after -replace "`r`n", '').Contains("`n"))
    Yes '  it names the new commit and the new SHA256' ($after.Contains($new) -and $after.Contains('5' * 64))
    Yes '  and no longer the old commit, apart from main''s' (-not $after.Contains($facts.Commit) -or $facts.Commit -eq $main)
    Yes '  main''s engine is kept' ((Get-EnginePinMain $plant) -eq $main)
    $outside = { param($t) ([regex]::Replace($t.Replace("`r`n", "`n"), '(?ms)^[ ]*<!-- engine-pin:(\w+) -->\n.*?^[ ]*<!-- /engine-pin:\1 -->', '')) }
    Yes '  the text outside the blocks is as it was' ((& $outside $after) -eq (& $outside $tp))
    $cr = [IO.File]::ReadAllText((Join-Path $plant 'site/data/site/credits.md'))
    Yes '  credits.md links the new commit' ($cr.Contains("/tree/$new)"))

    # Main runs the pin: "Main runs ... as well" and one source link.
    $null = Update-EnginePinText -Repo $plant -Main $new
    $same = [IO.File]::ReadAllText((Join-Path $plant 'THIRD-PARTY.md'))
    Yes 'when main runs the pin the page says so, with one source link' ($same.Contains("Main runs ``$new`` as well") -and -not $same.Contains('For the engine Main runs until then'))
    Yes '  and main is read back from that line' ((Get-EnginePinMain $plant) -eq $new)

    $broken = $after -replace '<!-- /engine-pin:front -->', ''
    [IO.File]::WriteAllText((Join-Path $plant 'THIRD-PARTY.md'), $broken)
    $threw = $false; try { $null = Update-EnginePinText -Repo $plant } catch { $threw = $true }
    Yes 'a block with no end marker stops the write' $threw
    Yes '  and -Check names it' (@(Update-EnginePinText -Repo $plant -Check | Where-Object { $_ -match 'front' }).Count -eq 1)
} finally {
    Remove-Item -LiteralPath $plant -Recurse -Force -ErrorAction SilentlyContinue
}

# ---- 3. the step, over stand-in answers --------------------------------------
$H = '1111111111111111111111111111111111111111'
$P = '2222222222222222222222222222222222222222'
function New-World { return @{ head = $H; prs = @(); files = @{}; branchPin = $null; forkRuns = @(); arts = @{}; engineRuns = @() } }
function Get-Answer($w) {
    return {
        param([string]$path)
        if ($path -like 'repos/EvilPatrick06/skymp/branches/*') { return [pscustomobject]@{ commit = [pscustomobject]@{ sha = $w.head } } }
        if ($path -like 'repos/EvilPatrick06/Thornswood/pulls?state=open*') { return , @($w.prs) }
        if ($path -match '^repos/EvilPatrick06/Thornswood/pulls/(\d+)/files') { return , @($w.files[[int]$Matches[1]]) }
        if ($path -like 'repos/EvilPatrick06/Thornswood/contents/engine/skymp*') { if ($w.branchPin) { return [pscustomobject]@{ sha = $w.branchPin } } ; throw 'Not Found (HTTP 404)' }
        if ($path -like 'repos/EvilPatrick06/skymp/actions/workflows/*') { return [pscustomobject]@{ workflow_runs = @($w.forkRuns) } }
        if ($path -match '^repos/EvilPatrick06/skymp/actions/runs/(\d+)/artifacts') { return [pscustomobject]@{ artifacts = @($w.arts[[long]$Matches[1]]) } }
        if ($path -like 'repos/EvilPatrick06/Thornswood/actions/workflows/engine.yml/runs*') { return [pscustomobject]@{ workflow_runs = @($w.engineRuns) } }
        throw "the stand-in has no answer for $path"
    }.GetNewClosure()
}
function Step($w, [string]$pin = $P) { return (Get-EnginePinStep $pin (Get-Answer $w)) }
$green = [pscustomobject]@{ id = 7; status = 'completed'; conclusion = 'success'; head_sha = $H; head_branch = 'thornswood/engine-changes'; event = 'push'; html_url = 'https://example/7'; repository = [pscustomobject]@{ full_name = 'EvilPatrick06/skymp' }; head_repository = [pscustomobject]@{ full_name = 'EvilPatrick06/skymp' } }
$art = [pscustomobject]@{ name = "thornswood-engine-$H"; expired = $false }

$w = New-World
Yes 'pinned: main pins the fork''s head' ((Step $w $H).Step -eq 'pinned')

$w = New-World
$w.prs = @([pscustomobject]@{ number = 41; html_url = 'u'; head = [pscustomobject]@{ ref = 'claude/pin-by-hand' } })
$w.files[41] = @([pscustomobject]@{ filename = 'engine/skymp' })
$s = Step $w
Yes 'aside: another open pull request moves engine/skymp, and it is named' ($s.Step -eq 'aside' -and $s.Pr -eq 41)
$w.files[41] = @([pscustomobject]@{ filename = 'README.md' })
Yes '  a pull request that does not move it is no reason to wait' ((Step $w).Step -ne 'aside')

$w = New-World
$w.branchPin = $H
$s = Step $w
Yes 'ready: engine-pin/next pins the head, with no pull request open' ($s.Step -eq 'ready' -and -not $s.Pr)
$w.prs = @([pscustomobject]@{ number = 42; html_url = 'u'; head = [pscustomobject]@{ ref = $EnginePinBranch } })
$s = Step $w
Yes '  and with its pull request open, which is not a reason to stand aside' ($s.Step -eq 'ready' -and $s.Pr -eq 42)

$w = New-World
$w.forkRuns = @([pscustomobject]@{ id = 8; status = 'in_progress'; conclusion = $null; head_sha = $H; head_branch = 'thornswood/engine-changes'; event = 'push'; html_url = 'https://example/8'; repository = [pscustomobject]@{ full_name = 'EvilPatrick06/skymp' }; head_repository = [pscustomobject]@{ full_name = 'EvilPatrick06/skymp' } })
Yes 'building: the fork is still building the head' ((Step $w).Step -eq 'building')

$w = New-World
Yes 'no-build: the fork has no build of the head' ((Step $w).Step -eq 'no-build')

$w = New-World
$w.forkRuns = @($green); $w.arts[[long]7] = $art
Yes 'record: the head is built and nothing recorded it' ((Step $w).Step -eq 'record')
$w.engineRuns = @([pscustomobject]@{ id = 90; status = 'completed'; conclusion = 'success'; display_title = 'Engine build of 3333333333333333333333333333333333333333'; html_url = 'u' })
Yes '  a record of another commit is not this one''s' ((Step $w).Step -eq 'record')
$w.engineRuns = @([pscustomobject]@{ id = 91; status = 'in_progress'; conclusion = $null; display_title = "Engine build of $H"; html_url = 'u' })
Yes 'recording: engine.yml is recording the head' ((Step $w).Step -eq 'recording')
$w.engineRuns = @([pscustomobject]@{ id = 92; status = 'completed'; conclusion = 'success'; display_title = "Engine build of $H"; html_url = 'u' })
$s = Step $w
Yes 'pin: engine.yml recorded the head green, and its run is named' ($s.Step -eq 'pin' -and $s.Run -eq 92)
$w.engineRuns = @([pscustomobject]@{ id = 93; status = 'completed'; conclusion = 'failure'; display_title = "Engine build of $H"; html_url = 'u' },
                  [pscustomobject]@{ id = 92; status = 'completed'; conclusion = 'success'; display_title = "Engine build of $H"; html_url = 'u' })
$s = Step $w
Yes 'red: the newest record of the head ended red, which is said and never started again' ($s.Step -eq 'red' -and $s.Run -eq 93)

# ---- 4. the notes -------------------------------------------------------------
$fake = {
    param([string]$path)
    if ($path -like 'repos/EvilPatrick06/skymp/compare/*') {
        return [pscustomobject]@{ commits = @(
            [pscustomobject]@{ commit = [pscustomobject]@{ message = "Merge pull request #133 from EvilPatrick06/claude/x`n`nLoading" } },
            [pscustomobject]@{ commit = [pscustomobject]@{ message = 'A commit of its own' } },
            [pscustomobject]@{ commit = [pscustomobject]@{ message = 'Merge pull request #81 from EvilPatrick06/herald/y' } }) }
    }
    if ($path -eq 'repos/EvilPatrick06/skymp/pulls/133') {
        return [pscustomobject]@{ number = 133; title = 'The loading screen is cleared (Thornswood #3130)'
            body = "Fixes the flash.`r`n`r`nRelease note: The loading screen shows no flash`r`n- The screen stays dark until the picture is up.`r`n`r`nTest task for Thornswood #3130: No flash before the loading screen`r`nServer: Main`r`n`r`n1. Load in.`r`nWhat should happen: no flash.`r`n`r`n---`r`nfooter" }
    }
    if ($path -eq 'repos/EvilPatrick06/skymp/pulls/81') { return [pscustomobject]@{ number = 81; title = 'An equipped form is not drunk'; body = $script:body81 } }
    throw "no answer for $path"
}
$script:body81 = 'Refs Thornswood #1649 and thornswood #1383.'
$n = Get-EnginePinNotes $P $H $fake
Yes 'the fork pull requests come from merge commits alone' ($n.Count -eq 2 -and $n.PullRequests[0] -like '- fork #133: *')
Yes 'the Thornswood issues they name, in order' (($n.Issues -join ',') -eq '1383,1649,3130')
Yes 'a Test task comes over as done-on-merge.yml reads it, ending at the rule' ($n.TestTasks.Count -eq 1 -and $n.TestTasks[0].StartsWith('Test task for #3130: No flash before the loading screen') -and $n.TestTasks[0].Contains('What should happen: no flash.') -and -not $n.TestTasks[0].Contains('footer'))
# The release note (plan part 8): the fork pull requests' own lines joined,
# and the ones with no line named, never taken as none.
Yes 'the release note is the fork pull requests'' own lines, and one with no line is named' (
    $n.ReleaseNote -eq "The loading screen shows no flash`n- The screen stays dark until the picture is up." -and (@($n.NoNote) -join ',') -eq '81')
$script:body81 = "Refs Thornswood #1649.`n`nRelease note: none"
$n = Get-EnginePinNotes $P $H $fake
Yes '  a fork pull request that says none adds nothing and is not named' ($n.ReleaseNote -eq "The loading screen shows no flash`n- The screen stays dark until the picture is up." -and @($n.NoNote).Count -eq 0)
$script:body81 = "Refs Thornswood #1649.`n`nRelease note: An equipped form stays on`n- A worn piece is never drunk by mistake."
$n = Get-EnginePinNotes $P $H $fake
Yes '  two notes join into one, the second headline as a line under the first' ($n.ReleaseNote -eq "The loading screen shows no flash`n- The screen stays dark until the picture is up.`n- An equipped form stays on`n- A worn piece is never drunk by mistake.")
$pin = [IO.File]::ReadAllText((Join-Path $root 'scripts/release/Update-EnginePin.ps1'))
Yes '  the pin body writes the joined note, none, or names the fork pull requests with no line' ($pin -match "'Release note: ' \+ \`$nl\[0\]" -and $pin -match "'Release note: none'" -and $pin -match 'carry no "Release note:" line')

# ---- 5. engine-pin.yml ----------------------------------------------------------
$wf = [IO.File]::ReadAllText((Join-Path $root '.github/workflows/engine-pin.yml')).Replace("`r`n", "`n")
$code = (@($wf -split "`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n")
# A job by name, read after "jobs:" alone: "push" is a trigger under "on:" too.
$jobsText = $code.Substring([Math]::Max(0, $code.IndexOf("`njobs:")))
function Get-Job([string]$name) { return [regex]::Match($jobsText, "(?ms)^  ${name}:\n.*?(?=^  \S|\z)").Value }
$look = Get-Job 'look'; $make = Get-Job 'make'; $push = Get-Job 'push'
Yes 'engine-pin.yml ticks on a schedule and runs by hand' ($code -match "(?m)^  schedule:\n    - cron: '[^']+'" -and $code -match '(?m)^  workflow_dispatch:')
Yes '  a push to main that moves engine/skymp starts a look (plan part 8)' ($code -match '(?m)^  push:\n    branches: \[main\]\n    paths: \[engine/skymp\]$')
$eng0 = [IO.File]::ReadAllText((Join-Path $root '.github/workflows/engine.yml')).Replace("`r`n", "`n")
Yes '  engine.yml starts a look when a record run on main ends (plan part 8)' ($eng0 -match 'gh workflow run engine-pin\.yml --repo \$env:GITHUB_REPOSITORY --ref main')
Yes '  one tick at a time, never cancelling the one before' ($code -match '(?m)^  group: engine-pin\n  cancel-in-progress: false')
Yes '  the workflow''s own token reads only' ($code -match '(?m)^permissions:\n  contents: read\n(?!  )')
Yes '  three jobs, look, make and push' ($look -and $make -and $push)
Yes '  make holds a token that only reads' ($make -match '(?m)^    permissions:\n      contents: read\n      actions: read\n(?!      )')
Yes '  the npm build (Update-EnginePin.ps1, which runs Build-Front.ps1) is in make alone' ($make -match 'Update-EnginePin\.ps1' -and $look -notmatch 'Update-EnginePin|Build-Front|setup-node|yarn|npx' -and $push -notmatch 'Update-EnginePin|Build-Front|setup-node|yarn|npx')
Yes '  push holds the pin to one commit on main with only a pin''s paths before it pushes' ($push -match 'is not one commit on main' -and $push -match 'changes more than a pin' -and $push.IndexOf('changes more than a pin') -lt $push.IndexOf('push --force'))
Yes '  push starts the build check on the branch, then opens or updates the pull request' ($push -match 'gh workflow run build-pr\.yml --repo \$env:GITHUB_REPOSITORY --ref engine-pin/next' -and $push.IndexOf('build-pr.yml') -lt $push.IndexOf('Open-EnginePinPr.ps1'))
Yes '  both places that open the pull request then start the release note check on the branch (plan part 8)' (
    @([regex]::Matches($look + $push, 'gh workflow run pr-body\.yml --repo \$env:GITHUB_REPOSITORY --ref engine-pin/next')).Count -eq 2 -and
    $push.IndexOf('Open-EnginePinPr.ps1') -lt $push.IndexOf('pr-body.yml') -and $look.IndexOf('Open-EnginePinPr.ps1') -lt $look.IndexOf('pr-body.yml'))
$pb = [IO.File]::ReadAllText((Join-Path $root '.github/workflows/pr-body.yml')).Replace("`r`n", "`n")
Yes '  pr-body.yml can be started by hand, and then reads the branch''s open pull request with a token that only reads' ($pb -match '(?m)^  workflow_dispatch:\s*$' -and $pb -match '(?m)^permissions:\n  contents: read\n  pull-requests: read\n(?!  )' -and $pb -match 'pulls\?state=open&head=')
Yes '  both places that open the pull request then start the test task check on the branch, whose result main requires (#5199)' (
    $push.IndexOf('Open-EnginePinPr.ps1') -lt $push.IndexOf('gh workflow run test-tasks.yml --repo $env:GITHUB_REPOSITORY --ref engine-pin/next') -and
    $look.IndexOf('Open-EnginePinPr.ps1') -ge 0 -and $look.IndexOf('Open-EnginePinPr.ps1') -lt $look.IndexOf('gh workflow run test-tasks.yml --repo $env:GITHUB_REPOSITORY --ref engine-pin/next'))
Yes '  look starts engine.yml only on the record step, and goes red on red' ($look -match "if: steps\.look\.outputs\.step == 'record'" -and $look -match "if \(\`$s\.Step -eq 'red'\) \{[^}]*exit 1")
Yes '  every checkout keeps no credentials on disk' (@([regex]::Matches($code, 'uses: actions/checkout@')).Count -eq 3 -and @([regex]::Matches($code, 'persist-credentials: false')).Count -eq 3)
Yes '  every job has a timeout' (@([regex]::Matches($code, '(?m)^    timeout-minutes: \d+$')).Count -eq 3)
$uses = @([regex]::Matches($code, '(?m)uses: (\S+)') | ForEach-Object { $_.Groups[1].Value })
Yes ('  every action is named by a full commit (' + $uses.Count + ')') ($uses.Count -gt 0 -and @($uses | Where-Object { $_ -notmatch '@[0-9a-f]{40}$' }).Count -eq 0)
Yes '  no secret and no self-hosted runner' ($code -notmatch 'secrets\.' -and $code -notmatch 'self-hosted' -and @([regex]::Matches($code, '(?m)^    runs-on: ubuntu-latest$')).Count -eq 3)
Yes '  the hand-back mark is put together, never written whole' ((@($wf -split "`n" | Where-Object { $_ -notmatch '^#' }) -join "`n") -cnotmatch 'ENGINE-PIN' -and $code -match "'ENGINE' \+ '-PIN'")

# ---- 6. around it -----------------------------------------------------------------
$eng = [IO.File]::ReadAllText((Join-Path $root '.github/workflows/engine.yml')).Replace("`r`n", "`n")
Yes 'engine.yml''s runs carry the commit in their title, which Get-EnginePinStep finds them by' ($eng -match "(?m)^run-name: Engine build of \$\{\{ inputs\.commit \|\| 'the pin' \}\}$")
$bp = [IO.File]::ReadAllText((Join-Path $root '.github/workflows/build-pr.yml')).Replace("`r`n", "`n")
Yes 'build-pr.yml can be started by hand on the pin branch' ($bp -match '(?m)^on:\n  pull_request:\n  workflow_dispatch:\n')
$tt = [IO.File]::ReadAllText((Join-Path $root '.github/workflows/test-tasks.yml')).Replace("`r`n", "`n")
Yes 'test-tasks.yml can be started by hand on the pin branch' ($tt -match '(?m)^  workflow_dispatch:\s*$')
$gs = [IO.File]::ReadAllText((Join-Path $root 'records/github-settings.json')) | ConvertFrom-Json
Yes 'the run''s token may open pull requests, and its default stays read' ($gs.workflow_token.can_approve_pull_request_reviews -eq $true -and $gs.workflow_token.default_workflow_permissions -eq 'read')
Yes 'fork pull requests still get no write token and no secret' ($gs.fork_pull_requests.send_write_tokens_to_workflows -eq $false -and $gs.fork_pull_requests.send_secrets_and_variables -eq $false)

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
