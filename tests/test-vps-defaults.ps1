<#
  test-vps-defaults.ps1

  The cheap half of issue #459: admin scripts no longer default -Vps to a
  literal address. They read scripts\vps\vps.json through Vps.ps1, and an
  explicit -Vps still wins.

  Checks:
    1. Vps.ps1 and every changed script parse (Parser.ParseFile).
    2. No script defaults $Vps or $VpsHost to the literal address.
    3. Repo files carrying the literal are only the baked set plus vps.json.
    4. Vps.ps1 resolves the same address with an empty default and with an
       explicit override (the fill pattern every changed script uses).
#>
[CmdletBinding()]
param()

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
function Done {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail) { exit 1 }
    exit 0
}

$VpsPs1 = Join-Path $Repo 'scripts\vps\Vps.ps1'
$VpsJson = Join-Path $Repo 'scripts\vps\vps.json'
Yes 'scripts\vps\Vps.ps1 exists' (Test-Path -LiteralPath $VpsPs1)
Yes 'scripts\vps\vps.json exists' (Test-Path -LiteralPath $VpsJson)
Yes 'the tools\Vps.ps1 forwarding copy is gone (issue #440)' (-not (Test-Path -LiteralPath ([IO.Path]::Combine($Repo, 'tools', 'Vps.ps1'))))

$expectedAddress = (Get-Content -LiteralPath $VpsJson -Raw | ConvertFrom-Json).address
Yes 'vps.json has an address' (-not [string]::IsNullOrWhiteSpace($expectedAddress))

# ---- 1. ParseFile over Vps.ps1 and every script that dotsources it ---------
$changed = @(Get-ChildItem -Path (Join-Path $Repo 'scripts') -Filter *.ps1 -Recurse -File |
    Where-Object {
        $raw = Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue
        $raw -and ($raw.Contains('Get-ThornswoodVpsAddress') -or $_.Name -eq 'Vps.ps1')
    })
Yes ("found changed scripts ({0})" -f $changed.Count) ($changed.Count -ge 30)

$parseFails = @()
foreach ($f in $changed) {
    $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errs)
    if (@($errs).Count -gt 0) {
        $parseFails += ('{0}: {1}' -f $f.FullName.Substring($Repo.Length + 1), $errs[0].Message)
    }
}
Yes 'every changed script parses' ($parseFails.Count -eq 0)
foreach ($p in $parseFails) { Write-Host "  $p" -ForegroundColor Red }

# ---- 2. no $Vps / $VpsHost literal defaults --------------------------------
$literalDefaults = @(Select-String -Path (Join-Path $Repo 'scripts\*\*.ps1'), (Join-Path $Repo 'scripts\*\*\*.ps1') `
    -Pattern '\$Vps(?:Host)?\s*=\s*[''"]192\.135\.112\.23' -ErrorAction SilentlyContinue)
Yes 'no script defaults $Vps or $VpsHost to the literal' ($literalDefaults.Count -eq 0)
foreach ($h in $literalDefaults) {
    Write-Host ("  {0}:{1}" -f $h.Path.Substring($Repo.Length + 1), $h.LineNumber) -ForegroundColor Red
}

# ---- 3. grep literal count falls to baked set + vps.json -------------------
$baked = @(
    'scripts/vps/vps.json',
    'launcher/app/Config.cs',
    'game/plugins/thornswood-emotes.js',
    'game/plugins/thornswood-front.js',
    'game/plugins/thornswood-mark.js',
    'game/plugins/thornswood-voice.js',
    'config.example.json',
    'DEVELOPING.md',
    'docs/FEED.md',
    'docs/IT-IS-DOWN.md',
    'docs/MOVING-THE-SERVER.md',
    'docs/OWNERSHIP.md',
    'docs/RESTORING.md',
    'docs/SYSTEM.md',
    'docs/archive/WORKING-NOTES.md',
    'docs/archive/todo-list-2026-09-25.md',
    'site/data/board.json',
    'tests/test-voice-mute.js',
    'voice/test-urls.js'
)
$bakedSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($b in $baked) { [void]$bakedSet.Add(($b -replace '\\', '/')) }

Push-Location $Repo
try {
    $carriers = @(git grep -l '192\.135\.112\.23')
} finally { Pop-Location }
# untracked vps.json
if (Test-Path -LiteralPath $VpsJson) {
    $rel = 'scripts/vps/vps.json'
    if ($carriers -notcontains $rel -and $carriers -notcontains ($rel -replace '/', '\')) {
        $carriers += $rel
    }
}
$carriersNorm = @($carriers | ForEach-Object { ($_ -replace '\\', '/') })
$unexpected = @($carriersNorm | Where-Object { -not $bakedSet.Contains($_) })
$missing = @($baked | Where-Object { $carriersNorm -notcontains ($_ -replace '\\', '/') -and $_ -ne 'scripts/vps/vps.json' })
# vps.json must be present as a carrier once we count the file itself
Yes 'vps.json is among the carriers' ($carriersNorm -contains 'scripts/vps/vps.json')
Yes ("literal carriers are only the baked set + vps.json ({0} files)" -f $carriersNorm.Count) ($unexpected.Count -eq 0)
foreach ($u in $unexpected) { Write-Host "  unexpected: $u" -ForegroundColor Red }

# ---- 4. fill pattern: empty default vs explicit -Vps -----------------------
. $VpsPs1
$fromHelper = Get-ThornswoodVpsAddress
Yes 'Vps.ps1 resolves the json address' ($fromHelper -eq $expectedAddress)

# Simulate the fill every changed script does
$Vps = ''
if (-not $Vps) { $Vps = Get-ThornswoodVpsAddress }
Yes 'empty default fills from Vps.ps1' ($Vps -eq $expectedAddress)

$Vps = '203.0.113.9'
if (-not $Vps) { $Vps = Get-ThornswoodVpsAddress }
Yes 'explicit -Vps still wins' ($Vps -eq '203.0.113.9')

$VpsHost = ''
if (-not $VpsHost) { $VpsHost = Get-ThornswoodVpsAddress }
Yes 'empty $VpsHost fills from Vps.ps1' ($VpsHost -eq $expectedAddress)

$VpsHost = '198.51.100.4'
if (-not $VpsHost) { $VpsHost = Get-ThornswoodVpsAddress }
Yes 'explicit -VpsHost still wins' ($VpsHost -eq '198.51.100.4')

# Every changed script (except Vps.ps1 itself) contains the fill line
$missingFill = @()
foreach ($f in $changed) {
    if ($f.Name -eq 'Vps.ps1') { continue }
    $raw = Get-Content -LiteralPath $f.FullName -Raw
    if ($raw -notmatch 'Get-ThornswoodVpsAddress') {
        $missingFill += $f.FullName.Substring($Repo.Length + 1)
    }
}
Yes 'every changed script calls Get-ThornswoodVpsAddress' ($missingFill.Count -eq 0)
foreach ($m in $missingFill) { Write-Host "  $m" -ForegroundColor Red }

Done
