<#
  test-5202-gh-log-flags.ps1

      pwsh -NoProfile -File .\tests\test-5202-gh-log-flags.ps1

  Issue #5202. A runner's log carries terminal escape sequences (its
  colours), and gh 2.92 and newer refuse to hand over an answer that holds
  any unless told --allow-escape-sequences. On 31 Oct 2026 engine-pin.yml
  stopped reading engine.yml's log for that and made no pin.

  WHAT IT HOLDS, with stand-in gh scripts, nothing sent anywhere:
    1. Get-GhLogFlags (LogHandBack.ps1) gives the flag when gh's help names
       it, and nothing for an older gh, or one that cannot be run.
    2. Every job log read in scripts\ and .github\workflows\ passes what gh
       needs told, from Get-GhLogFlags, and each file that calls it loads
       LogHandBack.ps1. Read-Board.ps1 kept its own copy of the flag (#3192)
       until it moved onto Get-GhLogFlags too, so there is one.
    Get-EngineRecords.ps1 run whole against a gh that refuses is in
    test-3399-engine-records.ps1.

  Writes only in its own scratch folder, which it removes.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$env:THORNSWOOD_HARNESS = '1'
$Here = Split-Path -Parent $PSScriptRoot
$utf8 = New-Object Text.UTF8Encoding($false)
$script:pass = 0; $script:fail = 0
function Yes([string]$what, [bool]$ok) {
    if ($ok) { $script:pass++; Write-Host "PASS  $what" -ForegroundColor Green }
    else { $script:fail++; Write-Host "FAIL  $what" -ForegroundColor Red }
}
function Read([string]$rel) { return [IO.File]::ReadAllText((Join-Path $Here $rel)).Replace("`r`n", "`n") }

. (Join-Path $Here 'scripts/release/LogHandBack.ps1')

$T = Join-Path ([IO.Path]::GetTempPath()) ('ts-5202-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Force -Path $T
try {
    # ===================================================== 1. Get-GhLogFlags ==
    Write-Host '1. Get-GhLogFlags'
    $new = Join-Path $T 'gh-new.ps1'
    [IO.File]::WriteAllText($new, "if (`$args[0] -eq 'api' -and `$args[1] -eq '--help') { 'FLAGS'; '  --allow-escape-sequences   Allow terminal escape sequences in the output'; exit 0 }`nexit 1`n", $utf8)
    $old = Join-Path $T 'gh-old.ps1'
    [IO.File]::WriteAllText($old, "if (`$args[0] -eq 'api' -and `$args[1] -eq '--help') { 'FLAGS'; '  --paginate   Make additional HTTP requests'; exit 0 }`nexit 1`n", $utf8)
    $f = @(Get-GhLogFlags $new)
    Yes ('1. a gh whose help names --allow-escape-sequences is given it (' + ($f -join ' ') + ')') ($f.Count -eq 1 -and $f[0] -eq '--allow-escape-sequences')
    $f = @(Get-GhLogFlags $old)
    Yes '1. an older gh, which has no such flag and refuses no log, is given nothing' ($f.Count -eq 0)
    $f = @(Get-GhLogFlags (Join-Path $T 'no-such-gh.ps1'))
    Yes '1. a gh that cannot be run is given nothing, and nothing throws' ($f.Count -eq 0)

    # ========================================== 2. every job log read passes it ==
    Write-Host ''; Write-Host '2. every job log read'
    $files = @(Get-ChildItem -LiteralPath (Join-Path $Here 'scripts') -Recurse -File -Include '*.ps1', '*.psm1') +
             @(Get-ChildItem -LiteralPath (Join-Path $Here '.github/workflows') -File -Include '*.yml', '*.yaml')
    $reads = 0
    foreach ($file in $files) {
        $rel = $file.FullName.Substring($Here.Length + 1).Replace('\', '/')
        $text = [IO.File]::ReadAllText($file.FullName).Replace("`r`n", "`n")
        $lines = $text -split "`n"
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $l = $lines[$i]
            if ($l -notmatch 'gh api "[^"]*/actions/jobs/[^"]+/logs"' -and $l -notmatch 'Get-Gh "[^"]*/actions/jobs/[^"]+/logs"') { continue }
            $reads++
            $ok = $l -match '/logs" @flags\b' -or $l -match '/logs" \(Get-GhLogFlags'
            Yes ("2. {0}:{1} passes what gh needs told" -f $rel, ($i + 1)) $ok
            if ($l -match 'Get-GhLogFlags' -or $text -match '\$flags = (@\()?Get-GhLogFlags') {
                $loads = $text -match "LogHandBack\.ps1" -or $rel -eq 'scripts/release/LogHandBack.ps1'
                if ($rel -eq 'scripts/release/Get-EngineRecords.ps1') { $loads = (Read 'scripts/release/EngineRecords.ps1') -match "\. \(Join-Path \`$PSScriptRoot 'LogHandBack\.ps1'\)" }
                Yes ("2.   and {0} loads LogHandBack.ps1, where Get-GhLogFlags is" -f $rel) $loads
            }
        }
    }
    Yes ("2. the reads are all found ({0}: Get-EngineRecords, engine-pin.yml, Read-Board, Sealed, Report-Clone)" -f $reads) ($reads -ge 5)
}
finally {
    if (Test-Path -LiteralPath $T) { Remove-Item -LiteralPath $T -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
