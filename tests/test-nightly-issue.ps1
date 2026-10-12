<#
  test-nightly-issue.ps1

      pwsh -NoProfile -File .\tests\test-nightly-issue.ps1

  The nightly keeps one "Nightly checks failed" issue on the board, never
  two, and closes it by itself the first night every check passes. Issues
  #905 and #1120: on 29 September the nightly opened #1120 beside #905, and
  both stayed open after the checks they reported were fixed, because only a
  person ever closed one.

  HOW. scripts\dev\Nightly-Issue.ps1 is dot-sourced with no -Result, so it
  only defines its functions, and Invoke-RestMethod is a stand-in here that
  keeps issues in memory and answers the way GitHub does: pages of 100, a
  JSON array handed down the pipe as ONE object (which is what broke the
  old step on 28 September), pull requests among the issues. Then:
    1. 150 other open issues, #905 on the second page and #1120 after it,
       and a pull request with the same title: a failed night adds to #905,
       closes #1120 as its duplicate, opens nothing, and leaves the pull
       request alone.
    2. With none open, a failed night opens one; a second failed night adds
       to it rather than opening another.
    3. A green night closes the open one with a line naming the run, and a
       green night with none open changes nothing.
    4. nightly.yml runs the script in its last job, which waits for every
       other job and runs whether they passed or failed, but not after a
       cancel (#2357): -Result failure when any of them did not succeed,
       -Result success only when all of them did, both with the
       token, the repository and the run, and the old inline step is gone.
  Never connects to anything.
#>
[CmdletBinding()]
param()

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

$script:Issues = $null
$script:Calls = $null
$script:Next = 0
function Reset-Fake {
    $script:Issues = New-Object System.Collections.ArrayList
    $script:Calls = New-Object System.Collections.ArrayList
    $script:Next = 2000
}
function Add-FakeIssue([int]$Number, [string]$Title, [switch]$Pr) {
    $i = [pscustomobject]@{ number = $Number; title = $Title; state = 'open'; comments = (New-Object System.Collections.ArrayList); pull_request = $null; state_reason = $null }
    if ($Pr) { $i.pull_request = [pscustomobject]@{ url = 'x' } }
    [void]$script:Issues.Add($i)
    return $i
}
function Find-FakeIssue([int]$n) { return @($script:Issues | Where-Object { $_.number -eq $n })[0] }

# Stands in for GitHub. Answers only what Nightly-Issue.ps1 asks.
function Invoke-RestMethod {
    param([string]$Method = 'GET', $Headers, [string]$Uri, $Body, [string]$ContentType)
    [void]$script:Calls.Add(("{0} {1}" -f $Method, $Uri))
    if (-not ($Uri -match '^https://api\.github\.com/repos/tester/thornswood/(.+)$')) { throw "unexpected uri $Uri" }
    $path = $Matches[1]
    $b = $null
    if ($Body) { $b = $Body | ConvertFrom-Json }
    if ($Method -eq 'GET' -and $path -match '^issues\?(.*)$') {
        $q = $Matches[1]
        if ($q -notmatch 'state=open') { throw 'asked for more than open issues' }
        $page = 1; if ($q -match '(?:^|&)page=(\d+)') { $page = [int]$Matches[1] }
        $per = 30; if ($q -match '(?:^|&)per_page=(\d+)') { $per = [int]$Matches[1] }
        $open = @($script:Issues | Where-Object { $_.state -eq 'open' })
        if ($q -match 'direction=asc') { $open = @($open | Sort-Object number) } else { $open = @($open | Sort-Object number -Descending) }
        $slice = @($open | Select-Object -Skip (($page - 1) * $per) -First $per)
        # GitHub's JSON array arrives as one object, the way the real one does.
        Write-Output -NoEnumerate $slice
        return
    }
    if ($Method -eq 'POST' -and $path -eq 'issues') {
        $script:Next++
        $i = Add-FakeIssue $script:Next ([string]$b.title)
        [void]$i.comments.Add([string]$b.body)
        return [pscustomobject]@{ number = $i.number }
    }
    if ($Method -eq 'POST' -and $path -match '^issues/(\d+)/comments$') {
        $i = Find-FakeIssue ([int]$Matches[1])
        [void]$i.comments.Add([string]$b.body)
        return [pscustomobject]@{ id = 1 }
    }
    if ($Method -eq 'PATCH' -and $path -match '^issues/(\d+)$') {
        $i = Find-FakeIssue ([int]$Matches[1])
        $i.state = [string]$b.state
        $i.state_reason = [string]$b.state_reason
        return [pscustomobject]@{ number = $i.number }
    }
    throw "unexpected call $Method $path"
}

$env:GH_TOKEN = 'not-a-token'
$env:REPO = 'tester/thornswood'
. (Join-Path $repo 'scripts\dev\Nightly-Issue.ps1')
$run = 'https://github.com/tester/thornswood/actions/runs/1'

# ---- 1. the 29 September board -----------------------------------------------
Reset-Fake
for ($n = 1; $n -le 150; $n++) { [void](Add-FakeIssue ($n + 300) "something else $n") }
$i905 = Add-FakeIssue 905 'Nightly checks failed'
$pr = Add-FakeIssue 906 'Nightly checks failed' -Pr
$i1120 = Add-FakeIssue 1120 'Nightly checks failed'
$said = Update-NightlyIssue -Result failure -Run $run -Day '2026-09-30'
Yes "a failed night reads past the first page (asked for pages: $(@($script:Calls | Where-Object { $_ -match 'page=' }).Count))" (@($script:Calls | Where-Object { $_ -match '^GET .*page=2' }).Count -eq 1)
Yes '  and adds to #905, the oldest' ($i905.state -eq 'open' -and @($i905.comments | Where-Object { $_ -match [regex]::Escape($run) -and $_ -match '2026-09-30' }).Count -eq 1)
Yes '  and closes #1120 as its duplicate, saying so' ($i1120.state -eq 'closed' -and @($i1120.comments | Where-Object { $_ -match 'duplicate of #905' }).Count -eq 1)
Yes '  and opens nothing' (@($script:Issues | Where-Object { $_.number -gt 2000 }).Count -eq 0)
Yes '  and leaves the pull request with the same title alone' ($pr.state -eq 'open' -and $pr.comments.Count -eq 0)
Yes "  and says what it did ($said)" ($said -match 'added to #905' -and $said -match 'closed #1120')

# ---- 2. none open, then two failed nights -------------------------------------
Reset-Fake
for ($n = 1; $n -le 120; $n++) { [void](Add-FakeIssue ($n + 300) "something else $n") }
$said = Update-NightlyIssue -Result failure -Run $run -Day '2026-10-01'
$mine = @($script:Issues | Where-Object { $_.title -eq 'Nightly checks failed' })
Yes "with none open, a failed night opens one ($said)" ($mine.Count -eq 1 -and $said -match '^opened #')
Yes '  whose body says the nightly closes it by itself' ($mine[0].comments[0] -match 'closes this by itself')
$said = Update-NightlyIssue -Result failure -Run ($run + '2') -Day '2026-10-02'
$mine = @($script:Issues | Where-Object { $_.title -eq 'Nightly checks failed' })
Yes "a second failed night adds to it, never a second issue ($said)" ($mine.Count -eq 1 -and $mine[0].comments.Count -eq 2 -and $mine[0].state -eq 'open')

# ---- 3. a green night ------------------------------------------------------------
$said = Update-NightlyIssue -Result success -Run ($run + '3') -Day '2026-10-03'
Yes "a green night closes it by itself ($said)" ($mine[0].state -eq 'closed' -and $mine[0].state_reason -eq 'completed')
Yes '  with a line naming the green run' (@($mine[0].comments | Where-Object { $_ -match 'passed on 2026-10-03' -and $_ -match [regex]::Escape($run + '3') }).Count -eq 1)
$before = $script:Calls.Count
$said = Update-NightlyIssue -Result success -Run ($run + '4') -Day '2026-10-04'
Yes "a green night with none open changes nothing ($said)" (@($script:Calls | Select-Object -Skip $before | Where-Object { $_ -notmatch '^GET ' }).Count -eq 0)
$said = Update-NightlyIssue -Result failure -Run ($run + '5') -Day '2026-10-05'
Yes "and the next failed night opens a fresh one ($said)" (@($script:Issues | Where-Object { $_.title -eq 'Nightly checks failed' -and $_.state -eq 'open' }).Count -eq 1)

# ---- 4. the workflow runs it ----------------------------------------------------
$y = [IO.File]::ReadAllText((Join-Path $repo '.github\workflows\nightly.yml'))
# Every job but the last, by its id, and the last one: the job that tells the board.
$jobIds = @([regex]::Matches(($y -split '(?m)^jobs:\s*$', 2)[1], '(?m)^  ([A-Za-z0-9_-]+):\s*$') | ForEach-Object { $_.Groups[1].Value })
$boardId = $(if ($jobIds.Count) { $jobIds[-1] } else { '' })
$others = @($jobIds | Where-Object { $_ -ne $boardId })
$boardJob = [regex]::Match($y, '(?s)(?m)^  ' + [regex]::Escape($boardId) + ':\s*$(.*)\z').Groups[1].Value
$needs = [regex]::Match($boardJob, '(?m)^    needs:\s*\[([^\]]*)\]').Groups[1].Value -split '\s*,\s*' | Where-Object { $_ }
Yes ("nightly.yml: its last job ($boardId) waits for every other job ($($others -join ', '))") ($others.Count -ge 1 -and (@($others | Where-Object { $needs -notcontains $_ }).Count -eq 0))
Yes '  and runs whether they passed or failed, but not after somebody cancels the run' ($boardJob -match '(?m)^    if: \$\{\{ !cancelled\(\) \}\}\s*$')
$failCond = '(?m)^\s+if: \$\{\{ ' + (($others | ForEach-Object { "needs\.$_\.result != 'success'" }) -join ' \|\| ') + ' \}\}\s*$'
$okCond = '(?m)^\s+if: \$\{\{ ' + (($others | ForEach-Object { "needs\.$_\.result == 'success'" }) -join ' && ') + ' \}\}\s*$'
$failStep = [regex]::Match($boardJob, '(?s)- name: Put a failure on the board\s+(if: [^\r\n]*)(.*?)(?=\r?\n      - name: |\z)')
$okStep = [regex]::Match($boardJob, '(?s)- name: Close the failure when every check passed\s+(if: [^\r\n]*)(.*?)(?=\r?\n      - name: |\z)')
Yes 'nightly.yml: when any job did not succeed it runs Nightly-Issue.ps1 -Result failure' ($failStep.Success -and ('    ' + $failStep.Groups[1].Value) -match $failCond -and $failStep.Groups[2].Value -match [regex]::Escape('.\scripts\dev\Nightly-Issue.ps1 -Result failure'))
Yes 'nightly.yml: only when every job succeeded it runs Nightly-Issue.ps1 -Result success' ($okStep.Success -and ('    ' + $okStep.Groups[1].Value) -match $okCond -and $okStep.Groups[2].Value -match [regex]::Escape('.\scripts\dev\Nightly-Issue.ps1 -Result success'))
Yes '  and nothing else in the file tells the board' (([regex]::Matches($y, 'Nightly-Issue\.ps1 -Result')).Count -eq 2)
foreach ($m in @($failStep, $okStep)) {
    if (-not $m.Success) { continue }
    $v = $m.Groups[2].Value
    Yes '  with the token, the repository and the run' ($v -match 'GH_TOKEN: \$\{\{ secrets\.GITHUB_TOKEN \}\}' -and $v -match 'REPO: \$\{\{ github\.repository \}\}' -and $v -match 'RUN: \$\{\{ github\.server_url \}\}')
}
Yes '  and the old inline step, first page only, is gone' ($y -notmatch 'Close this once the nightly run is green again')
Yes '  and the success step is the last, so it sees every check above it' ($y.TrimEnd() -match 'Nightly-Issue\.ps1 -Result success$')
Yes 'the workflow may close issues (issues: write)' ($y -match '(?m)^\s+issues: write')

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
