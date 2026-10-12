# tests\test-runner-isolation.ps1
# Issue #2161. Offline: scripts\vps\Check-RunnerIsolation.ps1 against made-up
# runner facts and the repository's own workflows, and the ACL reading in
# scripts\vps\Get-RunnerFacts.ps1 against stand-in rules. Nothing reaches the
# VPS or GitHub.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$check = Join-Path $repo 'scripts\vps\Check-RunnerIsolation.ps1'
$collector = Join-Path $repo 'scripts\vps\Get-RunnerFacts.ps1'
$pass = 0; $fail = 0
function T([bool]$ok, [string]$what) { if ($ok) { Write-Host "PASS  $what"; $script:pass++ } else { Write-Host "FAIL  $what"; $script:fail++ } }

foreach ($s in $check, $collector) {
    $errs = $null; [void][Management.Automation.Language.Parser]::ParseFile($s, [ref]$null, [ref]$errs)
    T ($errs.Count -eq 0) ((Split-Path -Leaf $s) + ' parses')
}
$craw = Get-Content -LiteralPath $collector -Raw
T ($craw -notmatch '(?m)^\s*[^#\n]*\b(Set-|Remove-|New-Item|Stop-|Start-|Restart-|Register-|Unregister-|Disable-|Enable-|Add-LocalGroupMember|icacls)\w*') 'the collector calls nothing that changes anything'
T ($craw -notmatch 'Get-Content') 'the collector reads no file contents'
$xraw = Get-Content -LiteralPath $check -Raw
T ($xraw -notmatch 'gh api[^\n]*( -X | --method | -f | --field | -F )|gh (issue|pr|label) ') 'the check only ever GETs from GitHub and files nothing'

# ---- ACL reading ----------------------------------------------------------
. $collector -Define
$R = [int][Security.AccessControl.FileSystemRights]'ReadAndExecute'
$W = [int][Security.AccessControl.FileSystemRights]'Write'
$acct = 'S-1-5-21-1-2-3-1001'; $users = 'S-1-5-32-545'
$sids = @($acct, $users, 'S-1-1-0', 'S-1-5-11', 'S-1-5-6')
$x = Get-AclReach @(@{ Sid = $users; Type = 'Allow'; Rights = $R }) $sids
T ($x.read -and -not $x.write) 'read through the Users group is read'
$x = Get-AclReach @(@{ Sid = $users; Type = 'Allow'; Rights = $R }, @{ Sid = $acct; Type = 'Deny'; Rights = $R -bor $W }) $sids
T (-not $x.read -and -not $x.write -and $x.denied) 'a deny on the account beats an allow through a group'
$x = Get-AclReach @(@{ Sid = $acct; Type = 'Allow'; Rights = $W }) $sids
T ($x.write -and -not $x.read) 'write without read is write only (Dumps)'
$x = Get-AclReach @(@{ Sid = 'S-1-5-32-544'; Type = 'Allow'; Rights = $R -bor $W }) $sids
T (-not $x.read -and -not $x.write) 'Administrators only is no reach'

# ---- comparison -------------------------------------------------------------
$rec = Get-Content (Join-Path $repo 'records\runner-isolation.json') -Raw | ConvertFrom-Json
function Facts {
    $reach = [ordered]@{}
    foreach ($p in $rec.noReach) { $reach[$p] = [ordered]@{ read = $false; write = $false; denied = $true } }
    $reach['C:\Thornswood-Dumps'] = [ordered]@{ read = $false; write = $true; denied = $false }
    [ordered]@{
        runner = [ordered]@{ takenUtc = '2026-10-11T12:00:00Z'; host = 'STANDIN'; machineEnvNames = @('THORNSWOOD_SITE')
            runners = @([ordered]@{ service = 'actions.runner.X.thornswood-vps'; account = 'thornswood-runner'; sid = 'S-1-5-21-1-2-3-1001'; state = 'Running'
                groups = @('Users', 'GITHUB_ActionsRunner_G1'); root = 'C:\Thornswood-Runner'; hasCredentials = $true; workFolders = 3
                tempLeftFiles = 0; tempOldestHours = 0; firewallRules = 12; reach = $reach }) }
        prod = [ordered]@{ listeners = @(@{ proto = 'tcp'; address = '127.0.0.1'; port = 3001; process = 'node' }) }
        github = [ordered]@{ private = $true; forkPr = @{ run_workflows_from_fork_pull_requests = $false }; workflowToken = @{ default_workflow_permissions = 'read' }
            runners = @(@{ name = 'thornswood-vps'; labels = @('self-hosted', 'thornswood-vps') }); collaborators = 3 }
    }
}
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('runner-iso-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null
$wfOk = Join-Path $scratch 'wf'; New-Item -ItemType Directory -Path $wfOk | Out-Null
Set-Content (Join-Path $wfOk 'build.yml') "on:`n  pull_request:`n  push:`npermissions:`n  contents: read`njobs:`n  a:`n    runs-on: [self-hosted, Windows, thornswood-pr]`n"
Set-Content (Join-Path $wfOk 'nightly.yml') "on:`n  schedule:`npermissions:`n  contents: read`njobs:`n  a:`n    runs-on: [self-hosted, Windows, thornswood-vps]`n"
function Run($facts, [string]$wf) {
    $fp = Join-Path $scratch 'facts.json'; $rp = Join-Path $scratch 'report.md'
    Remove-Item $rp -EA SilentlyContinue
    $facts | ConvertTo-Json -Depth 8 | Set-Content $fp -Encoding utf8
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $check, '-Facts', $fp, '-Report', $rp, '-Strict')
    if ($wf) { $a += @('-Workflows', $wf) }
    $o = & powershell @a 2>&1 | Out-String
    @{ Code = $LASTEXITCODE; Out = $o; Report = $(if (Test-Path $rp) { Get-Content $rp -Raw } else { '' }) }
}
try {
    $x = Run (Facts) $wfOk
    T ($x.Code -eq 0) 'a locked runner, private repo and no pull request on the production label: nothing at risk'
    T ($x.Report -match 'loopback \| tcp 3001') 'loopback services every local account can reach are listed from the #2165 facts'
    T ($x.Report -match "not Windows' effective access") 'the report says rights come from reading ACLs'

    # The real build.yml, whichever way it stands (Patrick, 11 Oct 2026: hosted
    # runners by default, VPS runners as a backup, Codex lane). Any pull request
    # job left on the VPS, a fallback included, is a risk row to read, never a hard fail without -Strict.
    $x = Run (Facts) ''
    $bt = [IO.File]::ReadAllText((Join-Path $repo '.github\workflows\build.yml'))
    $prOnProd = ($bt -match '(?m)^  pull_request:') -and ($bt -match 'runs-on:\s*\[[^\]]*\bthornswood-vps\b')
    if ($prOnProd) {
        T ($x.Out -match 'RISK  workflow build\.yml runs on: expected not thornswood-vps for untrusted code') 'the real build.yml still runs pull requests on the production runners, and the check says so (until the Codex move)'
    } else {
        T ($x.Out -notmatch 'RISK  workflow build\.yml runs on' -and $x.Report -match '\| workflow \| build\.yml runs on \|[^\n]*\| ok \|') 'the real build.yml runs no pull request on the production runners, and the check says ok'
    }
    T ($x.Out -notmatch 'RISK  workflow (nightly|release|drop-claims)\.yml runs on') 'nightly, release and drop-claims stay on the VPS and are not risks (no pull request trigger)'
    $rec0 = Get-Content (Join-Path $repo 'records\runner-isolation.json') -Raw | ConvertFrom-Json
    T ([string]$rec0.decision -match 'GitHub-hosted' -and [string]$rec0.decision -match '11 Oct 2026' -and [string]$rec0.decision -match 'outbound' -and [string]$rec0.decision -notmatch 'residual') 'the record carries the decision'

    $b = Facts; $ru = $b.runner.runners[0]
    $ru.groups = @('Users', 'Administrators')
    $ru.reach['C:\Thornswood-Docs\config.json'] = [ordered]@{ read = $true; write = $false; denied = $false }
    $ru.reach['C:\Thornswood-Dumps'] = [ordered]@{ read = $true; write = $true; denied = $false }
    $ru.tempLeftFiles = 4; $ru.tempOldestHours = 50; $ru.firewallRules = 0
    $b.runner.machineEnvNames = @('GH_TOKEN')
    $b.github.private = $false; $b.github.forkPr.run_workflows_from_fork_pull_requests = $true; $b.github.workflowToken.default_workflow_permissions = 'write'
    $x = Run $b $wfOk
    T ($x.Code -eq 1) 'with -Strict, any risk fails'
    T ($x.Out -match 'RISK  account thornswood-runner groups') 'a runner in Administrators is a risk'
    T ($x.Out -match 'RISK  reach thornswood-runner C:\\Thornswood-Docs\\config\.json: expected no read, no write, found read=True') 'a runner that can read the site config is a risk'
    T ($x.Out -match 'RISK  reach thornswood-runner C:\\Thornswood-Dumps: expected write, no read') 'a runner that can read crash dumps is a risk'
    T ($x.Out -match 'RISK  cleanup thornswood-runner') 'files left in _work\_temp past the limit are a risk'
    T ($x.Out -match 'RISK  network thornswood-runner outbound') 'no outbound limit on a runner account is a risk'
    T ($x.Out -match 'RISK  env GH_TOKEN') 'a token-shaped machine variable every job inherits is a risk, by name only'
    T ($x.Out -match 'RISK  github visibility' -and $x.Out -match 'RISK  github fork pull requests' -and $x.Out -match 'RISK  github default workflow token') 'public repo, fork workflows and a write token are risks'

    $r2 = Get-Content (Join-Path $repo 'records\runner-isolation.json') -Raw | ConvertFrom-Json
    $r2.intentional = @([pscustomobject]@{ area = 'network'; item = 'thornswood-runner outbound'; why = 'stand-in reason' })
    $rp2 = Join-Path $scratch 'rec.json'; $r2 | ConvertTo-Json -Depth 6 | Set-Content $rp2 -Encoding utf8
    $c = Facts; $c.runner.runners[0].firewallRules = 0
    $fp = Join-Path $scratch 'f2.json'; $c | ConvertTo-Json -Depth 8 | Set-Content $fp -Encoding utf8
    $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $check -Facts $fp -Record $rp2 -Workflows $wfOk -Strict 2>&1 | Out-String
    T ($LASTEXITCODE -eq 0 -and $o -match 'intentional: stand-in reason') 'a risk listed as intentional is classed so, with its reason'

    $d = Facts; $d.runner.runners[0].account = 'password=hunter2PLANTED'
    $x = Run $d $wfOk
    T ($x.Code -eq 2 -and -not $x.Report) 'a report holding something shaped like a secret is refused and not written'
    T ((Get-Content (Join-Path $repo 'records\runner-isolation.json') -Raw) -notmatch '(?i)password\s*[=:]|BEGIN ') 'records\runner-isolation.json holds no secret'
} finally { Remove-Item -LiteralPath $scratch -Recurse -Force -EA SilentlyContinue }

Write-Host "$pass passed, $fail failed"
if ($fail) { exit 1 }
