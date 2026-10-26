<#
  test-3534-clone-report.ps1

      pwsh -NoProfile -File .\tests\test-3534-clone-report.ps1

  WHY THIS EXISTS. Issue #3534. The weekly review could not read One's
  worktrees and stashes, and when the Local Desk read them by hand on 26 Oct
  2026 the shared clone held 29 worktrees, 7 stashes and about 96 dead
  branches (#3537). scripts\dev\Report-Clone.ps1 on One reports them through
  .github\workflows\clone-report.yml's log, and -Read reads them anywhere.

  What it checks:
    1. clone-report.yml: started by hand only, with one report input; its
       token has no permissions; on a VPS runner with a timeout; the report
       through the environment, nothing pasted into the script; no checkout
       and no action;
    2. the report, from a scratch clone made here with a bare origin: the
       clone detached, a worktree on a branch GitHub no longer has, one with
       changes nobody committed, one on a branch still there, a stash, an
       archived stash, a folder in worktrees\ no worktree owns and one in
       temp\; each is in the report as it is;
    3. the rules: the stash, the gone branch (the branch and its worktree),
       the changes left, the unowned folder and an old report are each named,
       and the worktree on a live branch and a fresh report are not; a clone
       on a branch is named;
    4. the hand-back: the report packed as Report-Clone.ps1 packs it, put
       through clone-report.yml's own step lifted out and run here, and read
       back with Read-ReportFromLog, with and without GitHub's timestamps,
       is the same report; a changed line, a missing end line and an input
       that is not a clone report are each refused;
    5. -Read against a stand-in gh: the newest run that ended well, exit 3
       with what breaks the rules, and exit 2 when there is no run yet.

  Nothing connects anywhere. Everything it writes is in its own temp folder.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $Here

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Done {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail) { exit 1 }
    exit 0
}

$script = Join-Path $repo 'scripts/dev/Report-Clone.ps1'
$wf = Join-Path $repo '.github/workflows/clone-report.yml'
foreach ($p in $script, $wf) { Yes ((Split-Path -Leaf $p) + ' is there') (Test-Path -LiteralPath $p) }
if (-not (Test-Path -LiteralPath $script) -or -not (Test-Path -LiteralPath $wf)) { Done }
$e = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$null, [ref]$e)
Yes 'Report-Clone.ps1 parses' (@($e).Count -eq 0)

# ---- 1. the workflow -----------------------------------------------------------
Write-Host ''; Write-Host 'the workflow'
$y = [IO.File]::ReadAllText($wf) -replace "`r`n", "`n"
$code = (@($y -split "`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n")
$on = [regex]::Match($code, '(?ms)^on:\n(.*?)^\S').Groups[1].Value
Yes 'started by hand only' ($on -match '(?m)^  workflow_dispatch:' -and @([regex]::Matches($on, '(?m)^  \S')).Count -eq 1)
Yes '  with one required string input, report' ($on -match '(?ms)inputs:\n\s+report:\n\s+description:[^\n]*\n\s+required: true\n\s+type: string\s*$')
Yes 'its token is given no permissions' ($code -match '(?m)^permissions:\s*\{\}\s*$' -and $code -notmatch '(?m)^\s+permissions:')
Yes 'on any VPS runner, with a timeout' ($code -match '(?m)^    runs-on: \[self-hosted, Windows, thornswood-vps\]$' -and $code -match '(?m)^    timeout-minutes: \d+$')
Yes 'no checkout, no action, no environment, no secret' ($code -notmatch 'uses:' -and $code -notmatch '(?m)^\s+environment:' -and $code -notmatch 'secrets\.')
Yes 'the report comes in through the environment' ($code.Contains('CLONE_REPORT: ${{ inputs.report }}'))
$step = [regex]::Match($code, '(?ms)- name: Check the report and print it\n.*?run: \|\n(.*)$').Groups[1].Value
Yes '  and nothing is pasted into the script' ($step.Length -gt 0 -and $step -notmatch '\$\{\{')
$stepScript = (@($step -split "`n" | ForEach-Object { $_ -replace '^          ', '' }) -join "`n")

# ---- 2. the report -------------------------------------------------------------------
Write-Host ''; Write-Host 'the report'
. $script -Load
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-3534c-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
function G([string]$Where) { $o = @(& git -C $Where @args 2>&1 | ForEach-Object { "$_" }); if ($LASTEXITCODE -ne 0) { throw ("git " + ($args -join ' ') + ': ' + ($o -join ' ')) }; return $o }
try {
    $origin = Join-Path $tmp 'origin.git'
    $clone = Join-Path $tmp 'clone'
    G $tmp init -q --bare $origin | Out-Null
    G $tmp init -q -b main $clone | Out-Null
    G $clone config user.email t@example.com | Out-Null
    G $clone config user.name t | Out-Null
    G $clone config commit.gpgsign false | Out-Null
    [IO.File]::WriteAllText((Join-Path $clone 'a.txt'), 'one')
    G $clone add a.txt | Out-Null
    G $clone commit -q -m one | Out-Null
    G $clone remote add origin $origin | Out-Null
    G $clone push -q origin main | Out-Null
    foreach ($b in 'claude/merged', 'claude/live') { G $clone branch $b | Out-Null; G $clone push -q -u origin $b | Out-Null }
    G $clone fetch -q origin | Out-Null
    # GitHub deleted claude/merged after its pull request merged.
    G $origin branch -D claude/merged | Out-Null
    G $clone fetch -q --prune origin | Out-Null
    G $clone worktree add -q (Join-Path $clone 'worktrees/claude-merged') claude/merged | Out-Null
    G $clone worktree add -q (Join-Path $clone 'worktrees/claude-live') claude/live | Out-Null
    G $clone worktree add -q --detach (Join-Path $clone 'worktrees/scratch') | Out-Null
    [IO.File]::WriteAllText((Join-Path $clone 'worktrees/scratch/b.txt'), 'nobody committed this')
    [IO.File]::WriteAllText((Join-Path $clone 'a.txt'), 'two')
    G $clone stash push -q -m 'wip before main refresh' | Out-Null
    $stashSha = @(G $clone rev-parse 'stash@{0}')[0]
    G $clone update-ref refs/stash-archive/one $stashSha | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $clone 'worktrees/left-behind') | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $clone 'temp/2573') -Force | Out-Null
    G $clone checkout -q --detach origin/main | Out-Null

    $out = Join-Path $tmp 'report.json'
    $o = @(& $script -Clone $clone -OutFile $out 6>&1 2>&1 | ForEach-Object { "$_" })
    Yes ("-OutFile writes the report and sends nothing (exit $LASTEXITCODE)") ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $out) -and ($o -join ' ') -match 'nothing sent')
    $r = [IO.File]::ReadAllText($out) | ConvertFrom-Json
    $c = @($r.clones)[0]
    Yes 'it is a clone report, with when and where it was made' ($r.kind -eq 'thornswood-clone-report' -and ([IO.File]::ReadAllText($out) -match '"made_at":"\d{4}-\d\d-\d\dT[\d:]+Z"') -and $r.machine)
    Yes 'the clone is detached at origin/main' ($null -eq $c.branch -and $c.head -eq $c.origin_main)
    $wt = @($c.worktrees)
    $by = @{}; foreach ($w in $wt) { $by[(Split-Path -Leaf $w.path)] = $w }
    Yes ("three worktrees, the clone itself not among them ($($wt.Count))") ($wt.Count -eq 3 -and $by.ContainsKey('claude-merged') -and $by.ContainsKey('claude-live') -and $by.ContainsKey('scratch'))
    Yes '  each with its branch, or detached' ($by['claude-merged'].branch -eq 'claude/merged' -and $by['scratch'].detached -and $null -eq $by['scratch'].branch)
    Yes '  and its uncommitted changes counted' ($by['scratch'].dirty -eq 1 -and $by['claude-live'].dirty -eq 0)
    Yes 'the stash, with its message, and the archived one counted' (@($c.stashes).Count -eq 1 -and @($c.stashes)[0].message -match 'wip before main refresh' -and $c.stash_archive -eq 1)
    $bm = @($c.branches | Where-Object { $_.name -eq 'claude/merged' })
    $bl = @($c.branches | Where-Object { $_.name -eq 'claude/live' })
    Yes 'the branch GitHub deleted is gone, the live one is not' ($bm.Count -eq 1 -and $bm[0].gone -and $bl.Count -eq 1 -and -not $bl[0].gone -and $bl[0].behind_main -eq 0)
    Yes 'the folder in worktrees\ no worktree owns, and the one in temp\' (@($c.unowned_worktree_folders | ForEach-Object { $_.name }) -join ',' -eq 'left-behind' -and @($c.temp | ForEach-Object { $_.name }) -contains '2573')

    # ---- 3. the rules ----
    Write-Host ''; Write-Host 'the rules'
    $d = Find-CloneDrift $r (Get-Date)
    Yes 'the stash is named' ($d['stash'].Count -eq 1)
    Yes 'the gone branch is named, and its worktree' ($d['branch gone'].Count -eq 2 -and @($d['branch gone'] | Where-Object { $_ -match 'worktree .*claude-merged on claude/merged' }).Count -eq 1)
    Yes 'the changes nobody committed are named' ($d['changes left'].Count -eq 1 -and $d['changes left'][0] -match 'scratch: 1 changed')
    Yes 'the unowned folder is named' ($d['folder unowned'].Count -eq 1 -and $d['folder unowned'][0] -match 'left-behind')
    Yes 'the worktree on a live branch is not, nor a fresh report, nor a detached clone' (@($d['branch gone'] + $d['changes left'] | Where-Object { $_ -match 'claude-live' }).Count -eq 0 -and $d['old report'].Count -eq 0 -and $d['clone on a branch'].Count -eq 0)
    $d = Find-CloneDrift $r (Get-Date).AddDays(3)
    Yes 'a report three days old is named' ($d['old report'].Count -eq 1)
    $r2 = [IO.File]::ReadAllText($out) | ConvertFrom-Json
    @($r2.clones)[0].branch = 'claude/live'
    Yes 'a clone on a branch is named' ((Find-CloneDrift $r2 (Get-Date))['clone on a branch'].Count -eq 1)

    # ---- 4. the hand-back ----
    Write-Host ''; Write-Host 'the hand-back'
    $json = [IO.File]::ReadAllText($out)
    $packed = ConvertTo-Packed $json
    $runStep = {
        param([string]$value)
        $was = $env:CLONE_REPORT
        $env:CLONE_REPORT = $value
        try {
            $o = @(& ([scriptblock]::Create($stepScript)) 6>&1 2>&1 | ForEach-Object { "$_" })
            return [pscustomobject]@{ Ok = $true; Lines = $o }
        } catch { return [pscustomobject]@{ Ok = $false; Lines = @($_.Exception.Message) } }
        finally { $env:CLONE_REPORT = $was }
    }
    $s = & $runStep $packed
    Yes 'the workflow''s step takes the packed report' ($s.Ok -and ($s.Lines -join ' ') -match 'a clone report from')
    Yes '  and its own text never holds the marker' ($stepScript -notmatch 'CLONE-JSON')
    $back = Read-ReportFromLog $s.Lines
    Yes 'read back from the log, it is the same report' (($back | ConvertTo-Json -Depth 8 -Compress) -eq ($r | ConvertTo-Json -Depth 8 -Compress))
    $stamped = @($s.Lines | ForEach-Object { '2026-10-26T18:00:00.1234567Z ' + $_ })
    Yes '  with GitHub''s timestamps on every line too' ((Read-ReportFromLog $stamped).made_at -eq $r.made_at)
    $refused = { param($lines) try { Read-ReportFromLog $lines | Out-Null; return '' } catch { return $_.Exception.Message } }
    $mid = [array]::IndexOf($s.Lines, @($s.Lines | Where-Object { $_ -match '^CLONE-JSON [A-Za-z0-9+/=]+$' })[0])
    $bent = @($s.Lines); $bent[$mid] = 'CLONE-JSON ' + ('A' * ($bent[$mid].Length - 11))
    Yes 'a changed line is refused' ((& $refused $bent) -match 'sha256|bytes')
    Yes 'a log with no end line is refused' ((& $refused @($s.Lines | Where-Object { $_ -ne 'CLONE-JSON end' })) -match 'no CLONE-JSON end line')
    $notReport = ConvertTo-Packed '{"kind":"something else"}'
    Yes 'an input that is not a clone report fails the run' (-not (& $runStep $notReport).Ok -and -not (& $runStep 'not base64!').Ok)

    # ---- 5. -Read ----
    Write-Host ''; Write-Host '-Read'
    $global:TSlog = ($s.Lines -join "`n")
    $global:TSruns = '{"workflow_runs":[{"id":77}]}'
    function gh {
        $a = @($args | ForEach-Object { [string]$_ })
        $p = @($a | Where-Object { $_ -match '^repos/' }) | Select-Object -First 1
        $global:LASTEXITCODE = 0
        if ($p -match '/actions/workflows/clone-report\.yml/runs\?status=success') { return $global:TSruns }
        if ($p -match '/actions/runs/77/jobs$') { return '{"jobs":[{"id":5}]}' }
        if ($p -match '/actions/jobs/5/logs$') { return $global:TSlog }
        $global:LASTEXITCODE = 1
        return 'gh: Not Found (HTTP 404)'
    }
    $o = @(& $script -Read 6>&1 2>&1 | ForEach-Object { "$_" })
    $rc = $LASTEXITCODE
    $t = $o -join "`n"
    Yes ("the newest report that ended well, read: exit 3 with what breaks the rules ($rc)") ($rc -eq 3 -and $t -match '(?m)^stash: 1$' -and $t -match '(?m)^branch gone: 2$' -and $t -match '3 worktree\(s\), 1 stash\(es\), 1 archived')
    $global:TSruns = '{"workflow_runs":[]}'
    $o = @(& $script -Read 6>&1 2>&1 | ForEach-Object { "$_" })
    Yes 'no report yet: exit 2, saying how One sends one' ($LASTEXITCODE -eq 2 -and ($o -join ' ') -match '-Install')
    Remove-Item Function:\gh
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Done
