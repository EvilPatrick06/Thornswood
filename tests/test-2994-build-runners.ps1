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

  This reads the record and the workflows, and runs Set-BuildRunners.ps1
  against stand-in runner lists with -DryRunFrom, so it asks GitHub nothing
  and changes nothing. A few seconds.
#>
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here
$ps = (Get-Process -Id $PID).Path

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

# ---- 4. Set-BuildRunners.ps1 against stand-in runner lists ------------------------
$set = Under @('scripts', 'deploy', 'Set-BuildRunners.ps1')
$work = Join-Path ([IO.Path]::GetTempPath()) ('ts-2994-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $work | Out-Null
try {
    function Runner([int]$id, [string]$name, [string[]]$labels, [string]$status = 'online') {
        [ordered]@{ id = $id; name = $name; status = $status; busy = $false; labels = @($labels | ForEach-Object { [ordered]@{ name = $_ } }) }
    }
    function Write-Runners([string]$name, $list) {
        $p = Join-Path $work $name
        [IO.File]::WriteAllText($p, ([ordered]@{ total_count = @($list).Count; runners = @($list) } | ConvertTo-Json -Depth 6))
        return $p
    }
    function Write-Record([string]$name, $label, $runners) {
        $p = Join-Path $work $name
        [IO.File]::WriteAllText($p, ([ordered]@{ label = $label; runners = @($runners) } | ConvertTo-Json -Depth 4))
        return $p
    }
    function Run([string[]]$a) {
        $ErrorActionPreference = 'Continue'
        $said = @(& $ps -NoProfile -NonInteractive -File $set @a 2>&1 | ForEach-Object { "$_" })
        return @{ Code = $LASTEXITCODE; Said = ($said -join "`n") }
    }
    $base = @('self-hosted', 'Windows', 'X64', 'thornswood-vps')
    $rec4 = Write-Record 'rec4.json' 'thornswood-build' @(1, 2, 3, 4)

    $mixed = Write-Runners 'mixed.json' @(
        (Runner 1 'thornswood-vps' ($base + 'thornswood-build')),
        (Runner 2 'thornswood-vps-2' $base),
        (Runner 3 'thornswood-vps-3' ($base + 'thornswood-build')),
        (Runner 27 'thornswood-vps-5' ($base + 'thornswood-build')),
        (Runner 40 'thornswood-pr-one' @('self-hosted', 'Windows', 'thornswood-pr', 'thornswood-build')))
    $r = Run @('-Record', $rec4, '-DryRunFrom', $mixed)
    Yes "a dry run against a mixed list ends 0 (got $($r.Code))" ($r.Code -eq 0 -and $r.Said -match 'dry run: 3 change\(s\) above, none made')
    Yes '  puts the label on a listed runner that lacks it' ($r.Said -match 'thornswood-vps-2: put on thornswood-build')
    Yes '  takes it off a VPS runner the record does not list' ($r.Said -match 'thornswood-vps-5: take off thornswood-build')
    Yes '  and off an off-box runner, which never takes box builds' ($r.Said -match 'thornswood-pr-one: take off thornswood-build')
    Yes '  leaves a runner that is right alone' ($r.Said -match 'thornswood-vps: carries thornswood-build, as the record says' -and $r.Said -notmatch 'thornswood-vps-3: (put on|take off)')
    Yes '  and names a listed runner GitHub does not have' ($r.Said -match 'runner 4 is in the record but not registered')
    $r = Run @('-Record', $rec4, '-DryRunFrom', $mixed, '-Check')
    Yes "-Check against it exits 1 (got $($r.Code))" ($r.Code -eq 1 -and $r.Said -match 'differs from the record in 3 place')

    $right = Write-Runners 'right.json' @(
        (Runner 1 'thornswood-vps' ($base + 'thornswood-build')),
        (Runner 2 'thornswood-vps-2' ($base + 'thornswood-build')),
        (Runner 3 'thornswood-vps-3' ($base + 'thornswood-build')),
        (Runner 4 'thornswood-vps-4' ($base + 'thornswood-build') 'offline'),
        (Runner 27 'thornswood-vps-5' $base),
        (Runner 30 'thornswood-vps-8' $base))
    $r = Run @('-Record', $rec4, '-DryRunFrom', $right, '-Check')
    Yes "-Check exits 0 when GitHub matches the record (got $($r.Code))" ($r.Code -eq 0 -and $r.Said -match '4 runner\(s\) carry thornswood-build, so at most that many heavy jobs')

    $r = Run @('-Record', (Write-Record 'gone.json' 'thornswood-build' @(9)), '-DryRunFrom', $right)
    Yes "a record whose runners GitHub does not have stops, so no build waits forever (exit $($r.Code))" ($r.Code -eq 1 -and $r.Said -match 'STOP\. no runner the record lists is registered')
    $r = Run @('-Record', (Write-Record 'vps.json' 'thornswood-vps' @(1)), '-DryRunFrom', $right)
    Yes "a record naming the label every VPS runner carries stops (exit $($r.Code))" ($r.Code -eq 1 -and $r.Said -match 'STOP\.')
    $r = Run @('-Record', (Write-Record 'none.json' 'thornswood-build' @()), '-DryRunFrom', $right)
    Yes "a record listing no runners stops (exit $($r.Code))" ($r.Code -eq 1 -and $r.Said -match 'STOP\. the record lists no runners')

    $r = Run @('-DryRunFrom', $right, '-Check')
    Yes "with no -Record it reads records\build-runners.json (exit $($r.Code))" (@(0, 1) -contains $r.Code -and $r.Said -match '(matches|differs from) the record')
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
