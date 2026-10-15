<#
  test-2513-every-harness-listed.ps1

      pwsh -NoProfile -File .\tests\test-2513-every-harness-listed.ps1

  Issue #2513. A harness ran on a pull request only if its author also typed
  its name into .github\workflows\build.yml, and nothing checked that they
  did. test-release-baseline.ps1 and test-publish-refusals.ps1 went red on
  main and the build stayed green, because neither was named there.

  So every tests\test-*.ps1 and tests\test-*.js is either named in build.yml
  or has a line in tests\gate-excluded.txt, "name  reason". This fails on:
    1. a harness that is in neither;
    2. an excluded line with no reason;
    3. an excluded line naming a file that is not in tests\;
    4. an excluded line naming a harness build.yml already runs.
  The same reader is then run over a planted repository with one of each,
  so a reader that finds nothing anywhere cannot pass by accident.

  Read only, apart from the planted folder under TEMP, which it removes.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

# What is wrong in one repository, as a list of lines. Empty means nothing.
function Get-Unlisted([string]$repo) {
    $problems = New-Object System.Collections.Generic.List[string]
    $yml = [IO.File]::ReadAllText((Join-Path $repo '.github\workflows\build.yml'))
    $tests = Join-Path $repo 'tests'
    $names = @(Get-ChildItem -LiteralPath $tests -File |
        Where-Object { $_.Name -like 'test-*.ps1' -or $_.Name -like 'test-*.js' } |
        ForEach-Object { $_.Name })
    $inYml = @{}
    foreach ($n in $names) {
        # Named as a list element ('name') or run by path (tests\name), not
        # merely mentioned in a comment.
        $e = [regex]::Escape($n)
        if ($yml -match ("'" + $e + "'") -or $yml -match ('tests[\\/]' + $e + '(?![\w.-])')) { $inYml[$n] = $true }
    }
    $excluded = @{}
    $listFile = Join-Path $tests 'gate-excluded.txt'
    if (Test-Path -LiteralPath $listFile) {
        $i = 0
        foreach ($line in [IO.File]::ReadAllLines($listFile)) {
            $i++
            $t = $line.Trim()
            if (-not $t -or $t.StartsWith('#')) { continue }
            $m = [regex]::Match($t, '^(\S+)(?:\s+(.*))?$')
            $n = $m.Groups[1].Value
            $why = $m.Groups[2].Value.Trim()
            if (-not $why) { $problems.Add("gate-excluded.txt line ${i}: $n has no reason") }
            if (-not (Test-Path -LiteralPath (Join-Path $tests $n))) { $problems.Add("gate-excluded.txt line ${i}: $n is not a file in tests") }
            if ($inYml.ContainsKey($n)) { $problems.Add("gate-excluded.txt line ${i}: $n is already run by build.yml") }
            $excluded[$n] = $true
        }
    }
    foreach ($n in $names) {
        if (-not $inYml.ContainsKey($n) -and -not $excluded.ContainsKey($n)) {
            $problems.Add("$n is in neither build.yml nor tests\gate-excluded.txt")
        }
    }
    return ,$problems
}

# 1. This repository.
$real = Get-Unlisted $Repo
foreach ($p in $real) { Write-Host "        $p" }
Yes 'every harness in tests is named in build.yml or excluded with a reason' ($real.Count -eq 0)

$yml = [IO.File]::ReadAllText((Join-Path $Repo '.github\workflows\build.yml'))
Yes 'test-release-baseline.ps1 and test-publish-refusals.ps1 are in build.yml (#2513)' (
    $yml.Contains("'test-release-baseline.ps1'") -and $yml.Contains("'test-publish-refusals.ps1'"))
Yes 'and this check is too' ($yml.Contains("'test-2513-every-harness-listed.ps1'"))
$pr = [IO.File]::ReadAllText((Join-Path $Repo '.github\workflows\build-pr.yml'))
Yes 'and so is build-pr.yml, generated from it' (
    $pr.Contains("'test-release-baseline.ps1'") -and $pr.Contains("'test-2513-every-harness-listed.ps1'"))

# 2. A planted repository with one of each fault, and one good of each kind.
$work = Join-Path ([IO.Path]::GetTempPath()) ('ts-2513-' + [Guid]::NewGuid().ToString('N'))
try {
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $work '.github\workflows'), (Join-Path $work 'tests')
    foreach ($n in 'test-listed.ps1', 'test-ok-excluded.js', 'test-forgotten.ps1', 'test-no-reason.js', 'test-both.ps1') {
        Set-Content -LiteralPath (Join-Path $work "tests\$n") -Value '# stand-in'
    }
    Set-Content -LiteralPath (Join-Path $work '.github\workflows\build.yml') -Value @(
        "          `$six = 'test-listed.ps1', 'test-both.ps1'")
    Set-Content -LiteralPath (Join-Path $work 'tests\gate-excluded.txt') -Value @(
        '# comment lines are skipped',
        'test-ok-excluded.js  needs a game install',
        'test-no-reason.js',
        'test-gone.ps1  removed long ago',
        'test-both.ps1  listed twice')
    $got = (Get-Unlisted $work) -join "`n"
    Yes 'planted: a harness in neither is named' ($got -match 'test-forgotten\.ps1 is in neither')
    Yes 'planted: an excluded line with no reason is named' ($got -match 'test-no-reason\.js has no reason')
    Yes 'planted: an excluded file that is gone is named' ($got -match 'test-gone\.ps1 is not a file')
    Yes 'planted: an excluded harness build.yml runs is named' ($got -match 'test-both\.ps1 is already run')
    Yes 'planted: a listed harness and a properly excluded one are not named' (
        $got -notmatch 'test-listed\.ps1' -and $got -notmatch 'test-ok-excluded\.js')
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -EA SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
