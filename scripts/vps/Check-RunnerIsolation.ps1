<#
.SYNOPSIS
  Checks what the self-hosted GitHub Actions runners on the VPS can reach (accounts, groups, production paths, leftovers, firewall, which workflows and pull requests run there, the repository's Actions settings) and writes a redacted report; read-only (issue #2161).

.DESCRIPTION
  -Collect is the only part that reaches anything, and it only reads:
    Get-RunnerFacts.ps1 and Get-ProdFacts.ps1 (issue #2165) on the VPS
    through Remote.ps1, and the repository's Actions settings through gh
    api GET calls (visibility, fork pull request policy, default token
    permissions, the runners and their labels, how many collaborators).
  It saves them to -Facts. Collecting is a live step: Claude's
  (claude-queue\2161-runner-isolation.md).

  Without -Collect it compares a saved -Facts file with
  records\runner-isolation.json and the workflows in .github\workflows.
  That part is offline and is what tests\test-runner-isolation.ps1 runs.

  Each row is ok, intentional (the record's reason), or risk. A risk row is
  a finding for the threat model in docs\RUNNER-ISOLATION.md, not a change:
  this script never changes a runner, an ACL, a setting or a credential.
  Rights come from reading ACLs, not from Windows' effective access check,
  and the report says so. No file contents, setting values or tokens are
  collected; the report is scanned and refused if anything shaped like a
  secret got in.

.EXAMPLE
  .\scripts\vps\Check-RunnerIsolation.ps1 -Collect -Facts $env:TEMP\runner-facts.json -Report $env:TEMP\runner-isolation.md
  .\scripts\vps\Check-RunnerIsolation.ps1 -Facts .\runner-facts.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Facts,
    [string]$Report,
    [switch]$Collect,
    [string]$Record,
    [string]$Workflows,
    [switch]$Strict
)

$ErrorActionPreference = 'Stop'
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $Record) { $Record = Join-Path $Repo 'records\runner-isolation.json' }
if (-not $Workflows) { $Workflows = Join-Path $Repo '.github\workflows' }

function Get-RemoteJson([string]$file) {
    $out = & (Join-Path $PSScriptRoot 'Remote.ps1') -File (Join-Path $PSScriptRoot $file)
    if ($LASTEXITCODE -ne 0) { throw "$file failed on the VPS" }
    $j = @($out) | Where-Object { $_ -match '^\s*\{' } | Select-Object -Last 1
    if (-not $j) { throw "$file printed nothing" }
    return ($j | ConvertFrom-Json)
}

if ($Collect) {
    $origin = (git -C $Repo remote get-url origin) -replace '\.git$', ''
    $slug = ($origin -split '[/:]')[-2..-1] -join '/'
    $repoInfo = gh api "repos/$slug" | ConvertFrom-Json
    $gh = [ordered]@{
        private = [bool]$repoInfo.private
        forkPr = (gh api "repos/$slug/actions/permissions/fork-pr-workflows-private-repos" 2>$null | ConvertFrom-Json)
        workflowToken = (gh api "repos/$slug/actions/permissions/workflow" | ConvertFrom-Json)
        runners = @((gh api "repos/$slug/actions/runners" | ConvertFrom-Json).runners | ForEach-Object { [ordered]@{ name = $_.name; labels = @($_.labels.name) } })
        collaborators = @(gh api "repos/$slug/collaborators" | ConvertFrom-Json).Count
    }
    $all = [ordered]@{ runner = (Get-RemoteJson 'Get-RunnerFacts.ps1'); prod = (Get-RemoteJson 'Get-ProdFacts.ps1'); github = $gh }
    $all | ConvertTo-Json -Depth 8 -Compress | Set-Content -LiteralPath $Facts -Encoding utf8
}

$f = Get-Content -LiteralPath $Facts -Raw | ConvertFrom-Json
$r = Get-Content -LiteralPath $Record -Raw | ConvertFrom-Json
$rows = New-Object System.Collections.Generic.List[object]
function Row([string]$Area, [string]$Item, [string]$Expected, [string]$Actual, [bool]$Ok, [string]$Kind = 'risk') {
    $cls = 'ok'; $why = ''
    if (-not $Ok) {
        $hit = @($r.intentional | Where-Object { $_.area -eq $Area -and $_.item -eq $Item }) | Select-Object -First 1
        if ($hit) { $cls = 'intentional'; $why = [string]$hit.why } else { $cls = $Kind }
    }
    $rows.Add([pscustomobject]@{ area = $Area; item = $Item; expected = $Expected; actual = $Actual; class = $cls; why = $why })
}

# ---- workflows: what runs on the production box, and for whom --------------
# Read from the files, so this half needs no box and no GitHub.
foreach ($wf in Get-ChildItem -LiteralPath $Workflows -Filter *.yml) {
    $t = [IO.File]::ReadAllText($wf.FullName)
    $lines = $t -split "\r?\n"
    # The top level block under a key: the lines below it indented by two,
    # comments left out, up to the next line that is not indented.
    function Get-TopBlock([string]$key) {
        $i = [array]::IndexOf($lines, ($lines | Where-Object { $_ -match ('^' + $key + ':\s*$') } | Select-Object -First 1))
        if ($i -lt 0) { return @() }
        $out = @()
        for ($j = $i + 1; $j -lt $lines.Count; $j++) {
            $l = $lines[$j]
            if ($l -match '^\S') { break }
            if ($l -match '^  [^\s#]') { $out += $l.Trim() }
        }
        return $out
    }
    $triggers = @(Get-TopBlock 'on' | ForEach-Object { ($_ -split ':')[0] })
    $onProd = $t -match ('runs-on:\s*\[[^\]]*\b' + [regex]::Escape($r.productionLabel) + '\b')
    $perm = (Get-TopBlock 'permissions') -join ' '
    $name = $wf.Name
    Row 'workflow' "$name runs on" "not $($r.productionLabel) for untrusted code" ("triggers " + ($triggers -join ',') + $(if ($onProd) { "; on $($r.productionLabel)" } else { '' })) (-not ($onProd -and ($triggers -contains 'pull_request' -or $triggers -contains 'pull_request_target')))
    if ($triggers -contains 'pull_request_target') { Row 'workflow' "$name pull_request_target" 'not used' 'used' $false }
    Row 'workflow' "$name token" 'permissions set per workflow, no write-all' $(if ($perm) { $perm.Trim() } else { 'not set (repository default)' }) ([bool]$perm -and $perm -notmatch 'write-all')
}

# ---- repository settings ----------------------------------------------------
if ($f.github) {
    $g = $f.github
    Row 'github' 'visibility' 'private' $(if ($g.private) { 'private' } else { 'public' }) ([bool]$g.private)
    if ($g.forkPr) { Row 'github' 'fork pull requests run workflows' 'no' $(if ($g.forkPr.run_workflows_from_fork_pull_requests) { 'yes' } else { 'no' }) (-not $g.forkPr.run_workflows_from_fork_pull_requests) }
    Row 'github' 'default workflow token' 'read' ([string]$g.workflowToken.default_workflow_permissions) ($g.workflowToken.default_workflow_permissions -eq 'read')
    Row 'github' 'collaborators who can push and so run code on the runners' 'known and few' ([string]$g.collaborators) $true
    foreach ($ru in $g.runners) { Row 'github' "runner $($ru.name) labels" 'listed' (@($ru.labels) -join ',') $true }
}

# ---- runner accounts on the box ---------------------------------------------
foreach ($ru in @($f.runner.runners)) {
    $id = $ru.account
    $bad = @($ru.groups | Where-Object { $r.forbiddenGroups -contains $_ })
    Row 'account' "$id groups" ('none of ' + ($r.forbiddenGroups -join ', ')) (@($ru.groups) -join ',') (-not $bad)
    foreach ($p in $r.noReach) {
        $x = $ru.reach.$p
        if ($null -eq $x -or $x -is [string]) { Row 'reach' "$id $p" 'no read, no write' $(if ($x) { [string]$x } else { 'not checked' }) $true; continue }
        Row 'reach' "$id $p" 'no read, no write' ("read=" + $x.read + " write=" + $x.write) (-not $x.read -and -not $x.write)
    }
    foreach ($p in $r.writeOnly) {
        $x = $ru.reach.$p
        if ($null -eq $x -or $x -is [string]) { continue }
        Row 'reach' "$id $p" 'write, no read' ("read=" + $x.read + " write=" + $x.write) (-not $x.read)
    }
    Row 'cleanup' "$id _work\_temp" "nothing older than $($r.tempMaxHours) h" ("$($ru.tempLeftFiles) files, oldest $($ru.tempOldestHours) h") (-not ($ru.tempLeftFiles -gt 0 -and [double]$ru.tempOldestHours -gt [double]$r.tempMaxHours))
    Row 'network' "$id outbound" 'limited to GitHub, as Install-Runner -OffBox does' ("$($ru.firewallRules) firewall rules name the account") ([int]$ru.firewallRules -gt 0)
    Row 'credentials' "$id .credentials" 'readable by its own jobs (GitHub design)' $(if ($ru.hasCredentials) { 'present' } else { 'absent' }) $true
}

# ---- what any local account can reach on loopback (from the #2165 facts) ----
if ($f.prod) {
    $f.prod.listeners | Where-Object { $_.address -in '127.0.0.1', '::1' -and $_.proto -eq 'tcp' } | Sort-Object port -Unique | ForEach-Object {
        Row 'loopback' "tcp $($_.port)" 'reachable by every local account, runners too' ([string]$_.process) $true
    }
}
foreach ($n in @($f.runner.machineEnvNames)) {
    Row 'env' $n 'no secret-shaped machine variable every job inherits' 'set (name only)' (-not ($n -match 'TOKEN|KEY|SECRET|PASS'))
}

# ---- report -----------------------------------------------------------------
$lines = @('# Runner isolation report', '',
    "Facts taken $($f.runner.takenUtc) on $($f.runner.host). Record: records\runner-isolation.json. Rights are read from ACLs, not Windows' effective access check.", '',
    '| Area | Item | Expected | Actual | Class |', '| --- | --- | --- | --- | --- |')
foreach ($x in $rows) { $lines += "| $($x.area) | $($x.item) | $($x.expected) | $($x.actual) | $($x.class)$(if ($x.why) { ': ' + $x.why }) |" }
$risk = @($rows | Where-Object class -eq 'risk')
$lines += ''; $lines += "$(@($rows | Where-Object class -eq 'ok').Count) ok, $(@($rows | Where-Object class -eq 'intentional').Count) intentional, $($risk.Count) risk."
$text = $lines -join "`n"
$scan = $text -replace '\b[0-9a-f]{64}\b', '' -replace 'S-1-5-21-[0-9-]+', ''
if ($scan -match '-----BEGIN|(?i)(password|secret|token)\s*[=:]\s*\S{6,}|[A-Za-z0-9+/_\-]{40,}') {
    Write-Host 'the report holds something shaped like a secret; it was not written' -ForegroundColor Red
    exit 2
}
if ($Report) { Set-Content -LiteralPath $Report -Value $text -Encoding utf8 } else { Write-Output $text }
foreach ($x in $risk) { Write-Host ("RISK  {0} {1}: expected {2}, found {3}" -f $x.area, $x.item, $x.expected, $x.actual) -ForegroundColor Yellow }
Write-Host ("{0} rows, {1} risk" -f $rows.Count, $risk.Count)
if ($Strict -and $risk.Count) { exit 1 }
exit 0
