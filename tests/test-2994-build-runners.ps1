<#
  test-2994-build-runners.ps1

      pwsh -NoProfile -File .\tests\test-2994-build-runners.ps1

  Holds the cap on how many heavy jobs run on the box at once (#2994).
  On 21 October seven builds ran on the VPS together, each harness step took
  34 to 39 minutes instead of about 15, and the 40-minute limit cancelled
  three pull requests' builds that were passing. Past four at once the box's
  six cores finish no more builds an hour. So the heavy jobs ask for the
  label thornswood-build, which only the runners records\build-runners.json
  lists carry, and scripts\deploy\Set-BuildRunners.ps1 makes GitHub match it.

  This reads the record and the workflows. Since #3107 the labels are put
  right by the box's admin service (scripts\vps\admin\admin.js), which
  github-admin.yml asks and Set-BuildRunners.ps1 starts; the rules this test
  held Set-BuildRunners.ps1 to before (a listed runner gets the label, any
  other loses it, an off-box runner never has it, a record whose runners
  GitHub does not have stops) are held there by tests\test-3107-admin.js,
  against stand-in runner lists. Asks GitHub nothing. A few seconds.
#>
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
function Under([string[]]$parts) { [IO.Path]::Combine([string[]](@($Repo) + $parts)) }

# ---- 1. the record ---------------------------------------------------------------
$recPath = Under @('records', 'build-runners.json')
$rec = Get-Content -LiteralPath $recPath -Raw | ConvertFrom-Json
$nums = @($rec.runners | ForEach-Object { [int]$_ })
Yes "the record names the build label ($($rec.label))" ($rec.label -eq 'thornswood-build')
Yes "it lists the runners that carry it ($($nums -join ', '))" ($nums.Count -ge 1 -and @($nums | Where-Object { $_ -lt 1 }).Count -eq 0 -and @($nums | Sort-Object -Unique).Count -eq $nums.Count)
Yes '  no more than four: past four at once the box finishes no more builds an hour, each one only takes longer' ($nums.Count -le 4)
Yes '  and says what was measured' ("$($rec.measured)" -match 'jobs an hour' -and "$($rec.about)" -match 'Set-BuildRunners\.ps1')

# ---- 2. which jobs ask for it -----------------------------------------------------
# Every job on the VPS, by workflow, and whether it is heavy (a build or a
# share of the harnesses) and so asks for the build label.
$heavy = @{
    'build.yml'    = @('launcher-vps')
    'build-pr.yml' = @('launcher-vps')
    'engine.yml'   = @('engine-vps')
    'nightly.yml'  = @('harnesses')
    # The gate, run as build.yml runs it, under a trace (#3114).
    'trace-gate.yml' = @('trace')
    # Light, but it asks for a build runner because those are never the
    # runner that signs a release launcher (records\sign-runners.json, #3312).
    'release.yml'  = @('verify')
}
function Get-Jobs([string]$text) {
    $text = $text -replace "`r`n", "`n"
    $body = $text.Substring($text.IndexOf("`njobs:`n") + 7)
    $out = @{}
    $ms = @([regex]::Matches($body, '(?m)^  ([A-Za-z0-9_-]+):\s*$'))
    for ($i = 0; $i -lt $ms.Count; $i++) {
        $end = $(if ($i + 1 -lt $ms.Count) { $ms[$i + 1].Index } else { $body.Length })
        $out[$ms[$i].Groups[1].Value] = $body.Substring($ms[$i].Index, $end - $ms[$i].Index)
    }
    return $out
}
$wfDir = Under @('.github', 'workflows')
$seen = 0
foreach ($f in Get-ChildItem -LiteralPath $wfDir -Filter *.yml) {
    $jobs = Get-Jobs ([IO.File]::ReadAllText($f.FullName))
    foreach ($k in $jobs.Keys) {
        $runsOn = [regex]::Match($jobs[$k], '(?m)^    runs-on:\s*(.+)$').Groups[1].Value.Trim()
        if ($runsOn -notmatch '\bthornswood-vps\b') { continue }
        $want = @($heavy[$f.Name]) -contains $k
        $has = $runsOn -match '\bthornswood-build\b'
        if ($want) { $seen++ }
        if ($want) { Yes ("{0} {1} is heavy and asks for a build runner ({2})" -f $f.Name, $k, $runsOn) $has }
        else { Yes ("{0} {1} is light and runs on any VPS runner ({2})" -f $f.Name, $k, $runsOn) (-not $has) }
    }
}
Yes "every heavy job named here is on the box ($seen found)" ($seen -ge 4)
Yes 'the build label is never asked for without the VPS label' (
    @(Get-ChildItem -LiteralPath $wfDir -Filter *.yml | ForEach-Object { [regex]::Matches([IO.File]::ReadAllText($_.FullName), '(?m)^\s*runs-on:.*thornswood-build.*$') } | Where-Object { $_.Value -notmatch 'self-hosted, Windows, thornswood-vps, thornswood-build\]' }).Count -eq 0)

# ---- 3. Install-Runner.ps1 registers a listed runner with it ----------------------
$ir = [IO.File]::ReadAllText((Under @('scripts', 'deploy', 'Install-Runner.ps1')))
Yes 'Install-Runner.ps1 reads the same record' ($ir -match [regex]::Escape('records\build-runners.json'))
Yes '  and registers with the labels it worked out' ($ir -match [regex]::Escape("--labels '`$registerLabels'"))
Yes '  never for an off-box runner' ($ir -match [regex]::Escape("if (-not `$OffBox -and -not `$PSBoundParameters.ContainsKey('Label'))"))

# ---- 4. who puts it on GitHub ------------------------------------------------------
# Set-BuildRunners.ps1 calls no runner API itself: it starts github-admin.yml,
# whose run the box's admin service answers (#3107). The planning rules are
# in admin.js and run by tests\test-3107-admin.js.
$set = [IO.File]::ReadAllText((Under @('scripts', 'deploy', 'Set-BuildRunners.ps1')))
Yes 'Set-BuildRunners.ps1 starts github-admin.yml' ($set.Contains("`$workflow = 'github-admin.yml'") -and $set.Contains('Start-ThornswoodWorkflow'))
Yes '  and changes no label itself' ($set -notmatch 'actions/runners/|/labels')
Yes 'tests\test-3107-admin.js holds the rules' ((Test-Path -LiteralPath (Under @('tests', 'test-3107-admin.js'))) -and
    ([IO.File]::ReadAllText((Under @('tests', 'test-3107-admin.js')))).Contains('a record whose runners GitHub has none of is refused'))

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
