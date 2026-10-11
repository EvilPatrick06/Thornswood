<#
  test-eslint-amp-path.ps1

  The eslint part of build.yml's "Lint (warnings only)" step (issue #1343)
  has to work when the checkout, or the folder eslint is installed into,
  sits under a path holding '&', as every lane worktree under
  C:\ThornswoodTemps&Worktrees does.

  WHY THIS EXISTS. The step ran npm's eslint.cmd shim. cmd.exe reads that
  shim, and its "SET dp0=%~dp0" and "%*" are unquoted, so an '&' in the
  shim's folder or in an argument ends the command there: eslint either
  never starts ("is not recognized", "Cannot find module C:\eslint\...") or
  loads its config from 'C:\ThornswoodTemps' and dies with
  ERR_UNSUPPORTED_DIR_IMPORT.

  This lifts the eslint lines out of build.yml as they are, makes a tiny
  repository with the real .github\lint\eslint.config.mjs and one file with a
  known no-unreachable finding, and runs those lines with RUNNER_TEMP and the
  working folder both under a '&' folder, then again under a plain folder.
  Each run must report the finding and must not crash. Offline: npm is
  replaced by a function that copies an already-installed eslint 9.39.5 from
  -EslintCache (default %TEMP%\herald-lint). Without that cache it says SKIP
  and exits 2.
#>
[CmdletBinding()]
param([string]$EslintCache = (Join-Path $env:TEMP 'herald-lint'))

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
$root = Split-Path -Parent $Here
$pass = 0; $fail = 0
function Check([bool]$ok, [string]$what) {
    if ($ok) { $script:pass++; Write-Host "PASS  $what" } else { $script:fail++; Write-Host "FAIL  $what" }
}

if (-not (Test-Path -LiteralPath (Join-Path $EslintCache 'node_modules\eslint\bin\eslint.js'))) {
    Write-Host "SKIP  no eslint in $EslintCache\node_modules (npm i eslint@9.39.5 there once)"
    exit 2
}

# The eslint lines of the step: from the "# eslint:" comment up to the
# "# PSScriptAnalyzer:" comment.
$yml = Get-Content -LiteralPath (Join-Path $root '.github\workflows\build.yml')
$a = ($yml | Select-String -SimpleMatch '# eslint: pinned' | Select-Object -First 1).LineNumber
$b = ($yml | Select-String -SimpleMatch '# PSScriptAnalyzer: pinned' | Select-Object -First 1).LineNumber
Check ([bool]($a -and $b -and $b -gt $a)) 'build.yml has the eslint lines of the lint step'
$block = ($yml[($a - 1)..($b - 2)] | ForEach-Object { $_ -replace '^ {10}', '' }) -join "`n"

$npmFn = @"
function npm {
    `$i = [array]::IndexOf(`$args, '--prefix')
    `$to = `$args[`$i + 1]
    New-Item -ItemType Directory -Force -Path `$to | Out-Null
    Copy-Item -LiteralPath (Join-Path `$env:HARNESS_ESLINT_CACHE 'node_modules') -Destination `$to -Recurse -Force
}
"@

function RunFrom([string]$base, [string]$label) {
    $repo = Join-Path $base 'repo'
    $tmp = Join-Path $base 'runner-temp'
    New-Item -ItemType Directory -Force -Path (Join-Path $repo '.github\lint'), $tmp | Out-Null
    Copy-Item -LiteralPath (Join-Path $root '.github\lint\eslint.config.mjs') -Destination (Join-Path $repo '.github\lint')
    Set-Content -LiteralPath (Join-Path $repo 'bad.js') -Value "function f() {`n  return 1;`n  f();`n}`nf();"
    $script = Join-Path $base 'step.ps1'
    Set-Content -LiteralPath $script -Value ($npmFn + "`n" + $block)
    $env:RUNNER_TEMP = $tmp
    $env:HARNESS_ESLINT_CACHE = $EslintCache
    Push-Location -LiteralPath $repo
    try { $out = (& pwsh -NoProfile -File $script 2>&1 | Out-String) } finally { Pop-Location }
    Check ($out -match 'no-unreachable') "$label : eslint reports the no-unreachable finding"
    Check ($out -notmatch 'Oops!|ERR_UNSUPPORTED_DIR_IMPORT|is not recognized|Cannot find module') "$label : eslint did not crash"
    if ($out -notmatch 'no-unreachable') { Write-Host (($out.Trim() -split "`n" | Select-Object -First 6) -join "`n") }
}

$work = Join-Path $env:TEMP ('eslint-amp-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
try {
    RunFrom (Join-Path $work 'Temps&Worktrees') "'&' path"
    RunFrom (Join-Path $work 'plain') 'plain path'
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ("{0} passed, {1} failed" -f $pass, $fail)
if ($fail) { exit 1 } else { exit 0 }
