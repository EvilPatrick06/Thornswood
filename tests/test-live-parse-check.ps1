<#
  test-live-parse-check.ps1

      pwsh -NoProfile -File .\tests\test-live-parse-check.ps1

  The live gamemode deploys check gamemode.js parses before anything is
  written or sent.

  WHY. Deploy-DevGamemode.ps1 ran node --check; Deploy-Gamemode.ps1 and
  Deploy-Server.ps1 did not, so a gamemode.js with a syntax error could go to
  the live server and stop it at start (issue #544). The live two now refuse,
  and refuse too when node is missing, since the live server is the one that
  cannot be left down.

  HOW. Reads the scripts as text: the check is there, it throws, and it comes
  before the line that writes or sends the file. Then runs node --check on a
  broken file, to show the check this relies on really fails.
#>
[CmdletBinding()]
param([string]$Tools)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, what they test is in tools\.
$Here = Join-Path (Split-Path -Parent $Here) 'tools'
if (-not $Tools) { $Tools = $Here }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function LineOf([string[]]$lines, [string]$pattern) {
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $pattern) { return $i + 1 } }
    return 0
}

# ---- Deploy-Gamemode.ps1 ------------------------------------------------------
$g = @(Get-Content -LiteralPath (Join-Path $Tools '..\scripts\deploy\Deploy-Gamemode.ps1'))
$check = LineOf $g '^\s*& node --check \$Gamemode'
$copy = LineOf $g "^Copy-Item -LiteralPath \`$Gamemode -Destination \(Join-Path \`$Dist 'gamemode.js'\)"
Yes 'Deploy-Gamemode runs node --check on gamemode.js' ($check -gt 0)
Yes '  before it copies the file into the build' ($check -gt 0 -and $copy -gt $check)
Yes '  and stops when it fails' (($g -join "`n") -match "LASTEXITCODE -ne 0\) \{ throw 'gamemode.js does not parse")
Yes '  and stops when node is missing, rather than skipping' (($g -join "`n") -match "Get-Command node[^\n]*\) \{ throw")

# ---- Deploy-Server.ps1 --------------------------------------------------------
$s = @(Get-Content -LiteralPath (Join-Path $Tools '..\scripts\deploy\Deploy-Server.ps1'))
$check = LineOf $s '^\s*& node --check \$built'
$list = LineOf $s "^\`$files = 'scam_native.node'"
# The first line that runs a call to the VPS: Remote, scp or ssh, or one of
# the functions that ask the live server who is on it. Read off the syntax
# tree, and only outside a function body, because a body runs where it is
# called and not where it is written: since #865 Warn-LiveRoom holds two
# Remote lines near the top of the file and is called after the check.
$vpsCalls = @('Remote', 'scp', 'ssh', 'OnlineNow', 'Get-LiveOnline', 'Warn-LiveRoom')
$tk = $null; $pe = $null
$sAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Tools '..\scripts\deploy\Deploy-Server.ps1'), [ref]$tk, [ref]$pe)
$first = 0
foreach ($c in $sAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
    if ($vpsCalls -notcontains $c.GetCommandName()) { continue }
    $inFn = $false
    for ($p = $c.Parent; $p; $p = $p.Parent) { if ($p -is [System.Management.Automation.Language.FunctionDefinitionAst]) { $inFn = $true; break } }
    if ($inFn) { continue }
    $at = $c.Extent.StartLineNumber
    if ($first -eq 0 -or $at -lt $first) { $first = $at }
}
Yes 'Deploy-Server runs node --check on the gamemode.js it sends' ($check -gt 0)
Yes '  before it lists what it sends' ($check -gt 0 -and $list -gt $check)
Yes '  and before anything talks to the VPS' ($check -gt 0 -and ($first -eq 0 -or $first -gt $check))
Yes '  and stops when it fails' (($s -join "`n") -match "LASTEXITCODE -ne 0\) \{ throw 'gamemode.js does not parse")

# ---- Deploy-DevGamemode.ps1 still has its own ---------------------------------
$d = @(Get-Content -LiteralPath (Join-Path $Tools '..\scripts\deploy\Deploy-DevGamemode.ps1'))
Yes 'Deploy-DevGamemode still runs node --check' ((LineOf $d '& node --check \$Gamemode') -gt 0)

# ---- node --check really fails on a broken file -------------------------------
if (Get-Command node -ErrorAction SilentlyContinue) {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('ts-parse-' + [guid]::NewGuid().ToString('N') + '.js')
    try {
        [IO.File]::WriteAllText($tmp, "function (\n")
        & node --check $tmp 2>&1 | Out-Null
        Yes 'node --check fails on a file that does not parse' ($LASTEXITCODE -ne 0)
        [IO.File]::WriteAllText($tmp, "const a = 1;`n")
        & node --check $tmp 2>&1 | Out-Null
        Yes '  and passes one that does' ($LASTEXITCODE -eq 0)
    }
    finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
