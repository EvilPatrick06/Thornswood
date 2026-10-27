<#
  test-runner-hook.ps1

      pwsh -NoProfile -File .\tests\test-runner-hook.ps1

  Issue #3889. A runner takes any job whose labels it all carries, and the
  labels come from the workflow file of the ref that runs, so a branch's own
  copy of a workflow could ask for the signing runner (records\
  sign-runners.json) and run there. scripts\deploy\Install-Runner.ps1 gives a
  signing runner a job-started hook that lets through only main's and a v
  tag's jobs of this repository, and ends any other job before its steps:
  a failed hook alone is one failed step, and a step marked if: always()
  still runs after it (actions/runner v2.337.0, StepsRunner.cs).

  This holds:
    1. the hook's rule (Test-SignJobRef, lifted out of Install-Runner.ps1)
       against every kind of ref a job can carry;
    2. the hook as the box gets it, taken from a dry run and run here: a job
       it takes ends 0, a job it refuses ends 1 and says so, and it never
       stops a process that is not Runner.Worker.exe (here that would be
       this harness);
    3. Set-RunnerHook, run on a scratch .env: it names the hook or takes the
       line off, and keeps the runner's own lines and TEMP and TMP;
    4. what the install and -Lock send, read from dry runs: a signing
       runner's hook is written and read back before its .env names it and
       before config.cmd first starts the service, every other runner's
       hook line is taken off, and an off-box runner gets no hook.
  Every run is -DryRunTo with stand-ins for gh; nothing reaches the box or
  GitHub, and no ACL, account or service is touched.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here
$script = Join-Path $Repo 'scripts\deploy\Install-Runner.ps1'
$ps = (Get-Process -Id $PID).Path

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

$text = [IO.File]::ReadAllText($script)
$t = $null; $e = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$t, [ref]$e)
Yes 'Install-Runner.ps1 parses' (-not $e -or $e.Count -eq 0)
# The value of a top-level "$name = @'...'@" or "$name = $other + @'...'@".
function HereOf([string]$name) {
    $a = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and "$($n.Left)" -eq ('$' + $name) }, $false))
    if (-not $a.Count) { return $null }
    $s = @($a[0].Right.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $n.StringConstantType -eq 'SingleQuotedHereString' }, $true))
    if (-not $s.Count) { return $null }
    return $s[0].Value
}
$hookLib = HereOf 'hookLib'
$lockLib = HereOf 'lockLib'
Yes 'the hook''s rule and the locks are blocks of their own' ([bool]$hookLib -and [bool]$lockLib)

$work = Join-Path ([IO.Path]::GetTempPath()) ('ts-runner-hook-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $work | Out-Null
$saved = @{}
foreach ($n in 'GITHUB_REPOSITORY', 'GITHUB_REF', 'GITHUB_WORKFLOW_REF') { $saved[$n] = [Environment]::GetEnvironmentVariable($n) }
try {
    # ---- 1. the rule ------------------------------------------------------
    . ([scriptblock]::Create($hookLib))
    $me = 'EvilPatrick06/Thornswood'
    $wf = $me + '/.github/workflows/release.yml'
    $take = @(
        @('main, by dispatch, schedule or push', $me, 'refs/heads/main', "$wf@refs/heads/main"),
        @('a v tag', $me, 'refs/tags/v1.2.7', "$wf@refs/tags/v1.2.7"),
        @('a v tag with a suffix', $me, 'refs/tags/v0.0.2163-pilot1', "$wf@refs/tags/v0.0.2163-pilot1"),
        @('the repository named in another case, as GitHub matches names', 'evilpatrick06/thornswood', 'refs/heads/main', 'evilpatrick06/thornswood/.github/workflows/nightly.yml@refs/heads/main'))
    foreach ($c in $take) {
        $why = Test-SignJobRef $me $c[1] $c[2] $c[3]
        Yes ('takes ' + $c[0]) ($why -eq '')
    }
    $refuse = @(
        @('a branch dispatch or push, the branch''s own workflow', $me, 'refs/heads/claude/x', "$wf@refs/heads/claude/x", 'neither main nor a v tag'),
        @('a pull request', $me, 'refs/pull/12/merge', "$wf@refs/pull/12/merge", 'neither main nor a v tag'),
        @('a tag that is not a v tag', $me, 'refs/tags/release-1', "$wf@refs/tags/release-1", 'neither main nor a v tag'),
        @('a V tag, since refs are matched with case', $me, 'refs/tags/V1.2.7', "$wf@refs/tags/V1.2.7", 'neither main nor a v tag'),
        @('a branch called Main', $me, 'refs/heads/Main', "$wf@refs/heads/Main", 'neither main nor a v tag'),
        @('a branch whose name starts with main', $me, 'refs/heads/main-old', "$wf@refs/heads/main-old", 'neither main nor a v tag'),
        @('main''s ref with a branch''s workflow', $me, 'refs/heads/main', "$wf@refs/heads/claude/x", 'not the copy on refs/heads/main'),
        @('a workflow ref that hides another @ in its path', $me, 'refs/heads/main', "$wf@refs/heads/claude/x@refs/heads/main", 'is not one of'),
        @('another repository''s job (the fork)', 'EvilPatrick06/skymp', 'refs/heads/main', 'EvilPatrick06/skymp/.github/workflows/x.yml@refs/heads/main', 'signs for EvilPatrick06/Thornswood alone'),
        @('a reusable workflow of another repository''s caller', $me, 'refs/heads/main', 'someone/else/.github/workflows/x.yml@refs/heads/main', 'is not one of'),
        @('a file outside .github/workflows', $me, 'refs/heads/main', "$me/x.yml@refs/heads/main", 'is not one of'),
        @('a job that says no ref', $me, '', '', 'does not say'))
    foreach ($c in $refuse) {
        $why = Test-SignJobRef $me $c[1] $c[2] $c[3]
        Yes ('refuses ' + $c[0] + " ($why)") ($why -ne '' -and $why.Contains($c[4]))
    }

    # ---- 4. what the install and -Lock send --------------------------------
    function Dry([string[]]$more) {
        $f = Join-Path $work ('dry-' + [Guid]::NewGuid().ToString('N') + '.txt')
        $ErrorActionPreference = 'Continue'
        $said = @(& $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script @more -DryRunTo $f -NoPause 2>&1 | ForEach-Object { "$_" })
        $rc = $LASTEXITCODE
        return @{ Code = $rc; Said = ($said -join "`n"); Text = $(if (Test-Path -LiteralPath $f) { [IO.File]::ReadAllText($f) } else { '' }) }
    }
    $sign = Get-Content -LiteralPath (Join-Path $Repo 'records\sign-runners.json') -Raw | ConvertFrom-Json
    $n = [int]@($sign.runners)[0]
    $acct = 'thornswood-runner' + $(if ($n -gt 1) { "$n" } else { '' })
    $hookPath = 'C:\ProgramData\Thornswood-RunnerHooks\job-started.ps1'
    $r3 = Dry @('-Number', "$n")
    Yes "a dry install of signing runner $n ends 0 (got $($r3.Code))" ($r3.Code -eq 0)
    $install = $(if ($r3.Text.Contains('config.cmd --unattended')) { $r3.Text.Substring(0, $r3.Text.IndexOf('config.cmd --unattended')) } else { '' })
    $hookFileAt = $install.IndexOf("Set-RunnerHookFile '$hookPath' `$hookText")
    $hookLineAt = $install.IndexOf("Set-RunnerHook `$root 'actions.runner.EvilPatrick06-Thornswood.thornswood-vps-$n' '$hookPath'")
    Yes '  it writes the hook and reads it back before config.cmd first starts the service' ($hookFileAt -gt 0)
    Yes '  and only then names it in the runner''s .env' ($hookLineAt -gt $hookFileAt)
    Yes "  -Lock, at the end of it, knows $acct signs and where the hook goes" ($r3.Text.Contains("`$signAccounts = @('$acct')") -and $r3.Text.Contains("`$hookPath = '$hookPath'"))
    Yes '  -Lock writes the hook before it points any .env at it, and points none at one it could not write' ($r3.Text.Contains('try { Set-RunnerHookFile $hookPath $hookText; $hookOk = $true }') -and $r3.Text.Contains('if ($hookOk) { try { Set-RunnerHook $root $svc.Name $hookPath }'))
    Yes '  and takes the hook line off every runner that does not sign' ($r3.Text.Contains("try { Set-RunnerHook `$root `$svc.Name '' }"))

    $r1 = Dry @('-Number', '1')
    $install1 = $(if ($r1.Text.Contains('config.cmd --unattended')) { $r1.Text.Substring(0, $r1.Text.IndexOf('config.cmd --unattended')) } else { '' })
    Yes "a dry install of runner 1, which does not sign, ends 0 (got $($r1.Code))" ($r1.Code -eq 0)
    Yes '  it gives that runner no hook line, and takes one off' ($install1.Contains("Set-RunnerHook `$root 'actions.runner.EvilPatrick06-Thornswood.thornswood-vps' ''") -and -not $install1.Contains('Set-RunnerHookFile ''C:'))

    $ro = Dry @('-OffBox')
    Yes "a dry -OffBox install ends 0 (got $($ro.Code))" ($ro.Code -eq 0)
    Yes '  an off-box runner signs nothing, and its -Lock writes no hook' ($ro.Text.Contains("`$signAccounts = @()") -and -not $ro.Text.Contains('Set-RunnerHookFile ''C:'))

    Yes '-Status says when a signing runner has no hook' ($text.Contains("'hook      NONE: this runner signs and takes a branch''s job. -Lock gives it the hook (#3889)'"))
    Yes 'the hook''s folder is given to Administrators, emptied of every rule, then SYSTEM and Administrators may change it and everyone may read it' ($lockLib.Contains("'/setowner', '*S-1-5-32-544', '/T'") -and $lockLib.Contains("@(`$dir, '/reset', '/T')") -and $lockLib.Contains("'*S-1-5-18:(OI)(CI)F', '*S-1-5-32-544:(OI)(CI)F', '*S-1-5-32-545:(OI)(CI)RX'") -and $lockLib.Contains("'/inheritance:r'"))
    Yes '  and is read back: its owner, who may write, and that nothing comes from above it' ($lockLib.Contains('is owned by') -and $lockLib.Contains('so the hook was not trusted') -and $lockLib.Contains('AreAccessRulesProtected) { throw ($dir'))

    # ---- 2. the hook as the box gets it ------------------------------------
    $hookText = $null
    $dryAst = [System.Management.Automation.Language.Parser]::ParseInput($r3.Text, [ref]$null, [ref]$null)
    $assign = @($dryAst.FindAll({ param($x) $x -is [System.Management.Automation.Language.AssignmentStatementAst] -and "$($x.Left)" -eq '$hookText' }, $true))
    if ($assign.Count) { $hookText = $assign[0].Right.Expression.Value }
    Yes 'the dry run carries the hook' ([bool]$hookText)
    $he = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput([string]$hookText, [ref]$null, [ref]$he)
    Yes '  and the hook parses' ([bool]$hookText -and (-not $he -or $he.Count -eq 0))
    Yes "  for this repository ($me)" ([string]$hookText -match ("(?m)^\`$repo = '" + [regex]::Escape($me) + "'$"))
    $hookFile = Join-Path $work 'job-started.ps1'
    [IO.File]::WriteAllText($hookFile, [string]$hookText, (New-Object Text.UTF8Encoding($true)))
    function Hook([string]$repository, [string]$ref, [string]$workflowRef) {
        $env:GITHUB_REPOSITORY = $repository; $env:GITHUB_REF = $ref; $env:GITHUB_WORKFLOW_REF = $workflowRef
        $ErrorActionPreference = 'Continue'
        $o = @(& $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $hookFile 2>&1 | ForEach-Object { "$_" })
        return @{ Code = $LASTEXITCODE; Out = ($o -join "`n") }
    }
    $h = Hook $me 'refs/tags/v1.2.7' "$wf@refs/tags/v1.2.7"
    Yes "the hook takes a v tag's job and ends 0 (got $($h.Code))" ($h.Code -eq 0 -and $h.Out -match 'takes this job')
    $h = Hook $me 'refs/heads/claude/x' "$wf@refs/heads/claude/x"
    Yes "the hook refuses a branch's job and ends 1 (got $($h.Code))" ($h.Code -eq 1 -and $h.Out -match '::error::REFUSED on the signing runner \(#3889\): it runs refs/heads/claude/x')
    Yes '  and stops no process that is not Runner.Worker.exe: this harness started it, and is still here' ($h.Out -match 'the job could not be ended')
} finally {
    foreach ($n in $saved.Keys) { [Environment]::SetEnvironmentVariable($n, $saved[$n]) }
    Remove-Item -LiteralPath $work -Recurse -Force -EA SilentlyContinue
}

# ---- 3. Set-RunnerHook on a scratch .env -----------------------------------
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('ts-runner-hookenv-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $scratch | Out-Null
try {
    function Get-CimInstance { $null }
    . ([scriptblock]::Create($lockLib))
    $envFile = Join-Path $scratch '.env'
    [IO.File]::WriteAllText($envFile, "http_proxy=none`r`nTEMP=C:\x\_work\_temp`r`nTMP=C:\x\_work\_temp`r`n")
    $said = Set-RunnerHook $scratch 'actions.runner.x' 'C:\h\job-started.ps1'
    $lines = @(Get-Content -LiteralPath $envFile)
    Yes 'Set-RunnerHook names the hook and keeps the runner''s own lines and TEMP and TMP' ($lines.Count -eq 4 -and $lines[0] -eq 'http_proxy=none' -and $lines -contains 'TEMP=C:\x\_work\_temp' -and $lines -contains 'ACTIONS_RUNNER_HOOK_JOB_STARTED=C:\h\job-started.ps1' -and $said -like '* now refuses *')
    Yes '  a second run changes nothing and says so' ((Set-RunnerHook $scratch 'actions.runner.x' 'C:\h\job-started.ps1') -like '* already')
    $null = Set-RunnerHook $scratch 'actions.runner.x' 'C:\other\job-started.ps1'
    Yes '  a new path replaces the old line, never beside it' (@(Get-Content -LiteralPath $envFile | Where-Object { $_ -like 'ACTIONS_RUNNER_HOOK_JOB_STARTED=*' }).Count -eq 1)
    $said = Set-RunnerHook $scratch 'actions.runner.x' ''
    $lines = @(Get-Content -LiteralPath $envFile)
    Yes '  given no hook, it takes the line off and leaves the rest' ($lines.Count -eq 3 -and -not @($lines | Where-Object { $_ -like 'ACTIONS_RUNNER_HOOK_JOB_STARTED=*' }).Count -and $said -like '* now has no job-started hook*')
    Remove-Item -LiteralPath $envFile -Force
    $null = Set-RunnerHook $scratch 'actions.runner.x' 'C:\h\job-started.ps1'
    Yes '  and makes the .env when there is none' (@(Get-Content -LiteralPath $envFile) -contains 'ACTIONS_RUNNER_HOOK_JOB_STARTED=C:\h\job-started.ps1')
} finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -EA SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
