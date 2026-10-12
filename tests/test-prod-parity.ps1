# tests\test-prod-parity.ps1
# Issue #2165. Offline: scripts\vps\Check-ProdParity.ps1 against made-up box
# facts, and scripts\vps\Get-ProdFacts.ps1's redaction against stand-in tasks
# and settings. Nothing reaches the VPS.
if ($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows) { Write-Host 'Windows only'; exit 0 }
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$check = Join-Path $repo 'scripts\vps\Check-ProdParity.ps1'
$collector = Join-Path $repo 'scripts\vps\Get-ProdFacts.ps1'
$pass = 0; $fail = 0
function T([bool]$ok, [string]$what) { if ($ok) { Write-Host "PASS  $what"; $script:pass++ } else { Write-Host "FAIL  $what"; $script:fail++ } }

foreach ($s in $check, $collector) {
    $errs = $null; [void][Management.Automation.Language.Parser]::ParseFile($s, [ref]$null, [ref]$errs)
    T ($errs.Count -eq 0) ((Split-Path -Leaf $s) + ' parses')
}
$craw = Get-Content -LiteralPath $collector -Raw
T ($craw -notmatch '(?m)^\s*[^#\n]*\b(Set-|Remove-|New-Item|Stop-|Start-|Restart-|Register-|Unregister-|Disable-|Enable-)\w+') 'the collector calls no cmdlet that changes anything'

# ---- redaction in the collector ------------------------------------------
. $collector -Define
$fakeTask = [pscustomobject]@{
    TaskName = 'Thornswood Fake'; State = 'Ready'
    Principal = [pscustomobject]@{ UserId = 'SYSTEM'; RunLevel = 'Highest' }
    Triggers = @()
    Actions = @([pscustomobject]@{ Execute = 'node.exe'; Arguments = 'server.js --key hunter2-PLANTED-SECRET' })
}
$tf = ConvertTo-TaskFact $fakeTask | ConvertTo-Json -Compress
T ($tf -notmatch 'PLANTED') 'a task argument never leaves the collector'
T ($tf -match '"argsSha256":"[0-9a-f]{64}"') 'only its sha256 does'
$shape = ConvertTo-SettingShape ([pscustomobject]@{ botKey = 'PLANTED-SECRET-VALUE'; port = 3001; on = $true; list = @(1, 2); blank = '' }) | ConvertTo-Json -Compress
T ($shape -notmatch 'PLANTED') 'a setting value never leaves the collector'
T ($shape -match '"botKey":"string"' -and $shape -match '"port":"number"' -and $shape -match '"on":"bool"' -and $shape -match '"blank":"empty"') 'only key names and value types do'

# ---- comparison ------------------------------------------------------------
$sha = [Security.Cryptography.SHA256]::Create()
function RepoSha([string]$rel) { $t = ([IO.File]::ReadAllText((Join-Path $repo $rel))) -replace "`r`n", "`n"; -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($t)) | ForEach-Object { $_.ToString('x2') }) }
$now = [datetime]'2026-10-11T12:00:00Z'
function Facts { [ordered]@{
    takenUtc = '2026-10-11T12:00:00Z'; host = 'STANDIN'
    listeners = @(
        @{ proto = 'tcp'; address = '0.0.0.0'; port = 443; process = 'caddy' }, @{ proto = 'tcp'; address = '0.0.0.0'; port = 80; process = 'caddy' },
        @{ proto = 'tcp'; address = '0.0.0.0'; port = 22; process = 'sshd' }, @{ proto = 'tcp'; address = '127.0.0.1'; port = 3001; process = 'node' },
        @{ proto = 'tcp'; address = '127.0.0.1'; port = 7778; process = 'node' }, @{ proto = 'tcp'; address = '127.0.0.1'; port = 7789; process = 'node' },
        @{ proto = 'udp'; address = '0.0.0.0'; port = 7777; process = 'node' }, @{ proto = 'tcp'; address = '0.0.0.0'; port = 3000; process = 'node' },
        @{ proto = 'udp'; address = '0.0.0.0'; port = 7787; process = 'node' }, @{ proto = 'tcp'; address = '0.0.0.0'; port = 7788; process = 'node' })
    tasks = @(
        @{ name = 'Thornswood Server'; user = 'SYSTEM'; triggers = @('Boot') }, @{ name = 'Thornswood Dev Server'; user = 'SYSTEM'; triggers = @('Boot') },
        @{ name = 'Thornswood Voice'; user = 'SYSTEM'; triggers = @('Boot') }, @{ name = 'Thornswood Dev Voice'; user = 'SYSTEM'; triggers = @('Boot') },
        @{ name = 'Thornswood Docs'; user = 'NT AUTHORITY\LOCAL SERVICE'; triggers = @('Boot') }, @{ name = 'Thornswood Web'; user = 'SYSTEM'; triggers = @('Boot', 'Time') },
        @{ name = 'Thornswood Watch'; user = 'SYSTEM'; triggers = @('Time') }, @{ name = 'Thornswood Backup'; user = 'SYSTEM'; triggers = @('Daily') })
    services = @(
        @{ name = 'sshd'; account = 'LocalSystem'; state = 'Running' }, @{ name = 'ThornswoodBot'; account = 'NT SERVICE\ThornswoodBot'; state = 'Running' },
        @{ name = 'actions.runner.X.thornswood-vps'; account = '.\thornswood-runner'; state = 'Running' })
    files = [ordered]@{
        'C:\Thornswood-Caddy\Caddyfile' = (RepoSha 'scripts/deploy/Caddyfile'); 'C:\Thornswood-Docs\server.js' = (RepoSha 'site/server.js')
        'C:\Thornswood-Voice\voice-server.js' = (RepoSha 'voice/voice-server.js'); 'C:\Thornswood-Voice-Dev\voice-server.js' = (RepoSha 'voice/voice-server.js') }
    certs = @(@{ subject = 'CN=thornswood.net'; notAfterUtc = '2026-12-01T00:00:00Z' })
    versions = [ordered]@{ node = '22.11.0'; caddy = '2.8.4' }
    settings = [ordered]@{ 'C:\Thornswood-Docs\config.json' = [ordered]@{ botKey = 'string'; port = 'number' } }
    machineEnvNames = @()
} }

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('prod-parity-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null
function Run($facts, [string]$record) {
    $fp = Join-Path $scratch 'facts.json'; $rp = Join-Path $scratch 'report.md'
    Remove-Item $rp -EA SilentlyContinue
    $facts | ConvertTo-Json -Depth 6 | Set-Content $fp -Encoding utf8
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $check, '-Facts', $fp, '-Report', $rp, '-Now', '2026-10-11T12:00:00Z', '-Strict')
    if ($record) { $a += @('-Record', $record) }
    $o = & powershell @a 2>&1 | Out-String
    @{ Code = $LASTEXITCODE; Out = $o; Report = $(if (Test-Path $rp) { Get-Content $rp -Raw } else { '' }) }
}
try {
    $x = Run (Facts) ''
    T ($x.Code -eq 0) 'a box that matches the record has nothing to review'
    T ($x.Report -match '\| file \| C:\\Thornswood-Caddy\\Caddyfile \|[^\n]*\| same \| ok \|') 'the live Caddyfile is compared with scripts\deploy\Caddyfile'
    T ($x.Report -match 'botKey \(string\)' -and $x.Report -notmatch 'PLANTED') 'the report carries setting names and types only'

    $b = Facts
    ($b.listeners | Where-Object { $_.port -eq 3001 }).address = '0.0.0.0'
    $b.listeners += @{ proto = 'tcp'; address = '0.0.0.0'; port = 8080; process = 'node' }
    ($b.tasks | Where-Object { $_.name -eq 'Thornswood Docs' }).user = 'SYSTEM'
    $b.machineEnvNames = @('THORNSWOOD_DOCS_EXPOSE')
    $b.certs = @(@{ subject = 'CN=thornswood.net'; notAfterUtc = '2026-10-16T00:00:00Z' })
    $b.files.'C:\Thornswood-Caddy\Caddyfile' = ('0' * 64)
    ($b.services | Where-Object { $_.name -eq 'ThornswoodBot' }).state = 'Stopped'
    $x = Run $b ''
    T ($x.Code -eq 1) 'with -Strict, any difference to review fails'
    T ($x.Out -match 'REVIEW  listener tcp 3001: expected loopback node, found public node') 'the site on every address is caught'
    T ($x.Out -match 'REVIEW  listener tcp 8080: expected not listed in the record') 'a public port nobody wrote down is caught'
    T ($x.Out -match 'REVIEW  task Thornswood Docs: expected as LOCAL SERVICE, found as SYSTEM') 'a task running as the wrong account is caught'
    T ($x.Out -match 'REVIEW  env THORNSWOOD_DOCS_EXPOSE') 'an exposing environment variable is caught by name'
    T ($x.Out -match 'REVIEW  tls thornswood.net: expected valid, 14\+ days, found 4 days left') 'a certificate close to lapsing is caught'
    T ($x.Out -match 'REVIEW  file C:\\Thornswood-Caddy\\Caddyfile') 'a live Caddyfile that differs is caught'
    T ($x.Out -match 'REVIEW  service ThornswoodBot') 'a stopped bot service is caught'

    $rec = Get-Content (Join-Path $repo 'records\prod-parity.json') -Raw | ConvertFrom-Json
    $rec.intentional = @([pscustomobject]@{ area = 'listener'; item = 'tcp 8080'; why = 'stand-in reason' })
    $rp2 = Join-Path $scratch 'record.json'; $rec | ConvertTo-Json -Depth 6 | Set-Content $rp2 -Encoding utf8
    $c = Facts; $c.listeners += @{ proto = 'tcp'; address = '0.0.0.0'; port = 8080; process = 'node' }
    $x = Run $c $rp2
    T ($x.Code -eq 0 -and $x.Report -match 'intentional: stand-in reason') 'a difference listed as intentional is classed so, with its reason'

    $d = Facts; $d.versions.node = 'password=hunter2PLANTED'
    $x = Run $d ''
    T ($x.Code -eq 2 -and -not $x.Report) 'a report holding something shaped like a secret is refused and not written'

    $rec2 = Get-Content (Join-Path $repo 'records\prod-parity.json') -Raw
    T ($rec2 -notmatch '(?i)password\s*[=:]|BEGIN ') 'records\prod-parity.json holds no secret'
} finally { Remove-Item -LiteralPath $scratch -Recurse -Force -EA SilentlyContinue }

Write-Host "$pass passed, $fail failed"
if ($fail) { exit 1 }
