# test-2243-installer-throw.ps1
#
# #2243: on 11 October a check inside Package-Thornswood.ps1 threw during
# Ship's 'Rebuilding the installer' step, and the throw went straight out of
# Ship, so the remirror, the dev marks, the news, the Discord post, the
# restart and the tag never ran. The step is meant to never stop a release.
#
# Lifts that step and the Done section's installer lines out of the real
# scripts\release\Ship.ps1 and runs them under Stop and strict mode, as Ship
# does, with a stand-in Package-Thornswood.ps1 in a scratch folder:
#   a packager that throws, one that Write-Errors under Stop, one that exits
#   non-zero, one that works, and one that works after an earlier native
#   command left a non-zero exit code behind.
# Each time it checks the step records the failure (or not), says it in red,
# and that the code AFTER the step still runs. Ship itself is never run.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Repo = Split-Path -Parent $PSScriptRoot
$pass = 0; $fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" } else { $script:fail++; Write-Host "FAIL  $what" }
}
$ship = (Get-Content -Raw (Join-Path $Repo 'scripts\release\Ship.ps1')) -replace "`r", ''
$a = $ship.IndexOf('    $pkgArgs = @{ Root = $Root; OutDir = $DistDir; NoPause = $true; OneFile = $true }')
$b = $ship.IndexOf("`n}`nelse {`n    Show-Installer", $a)
$step = if ($a -gt 0 -and $b -gt $a) { $ship.Substring($a, $b - $a) } else { '' }
Yes 'the installer step is in Ship.ps1' ($step.Length -gt 0)
$d0 = $ship.IndexOf('if ($script:InstallerFailed) {', $b)
$d1 = if ($d0 -gt 0) { $ship.IndexOf("`n}`n", $d0) } else { -1 }
$done = if ($d0 -gt 0 -and $d1 -gt $d0) { $ship.Substring($d0, $d1 - $d0 + 2) } else { '' }
Yes 'and so are the Done section''s installer lines' ($done.Length -gt 0)
Yes 'the step catches a throw from the packager' ($step -match 'try \{ & \(Join-Path \$Here ''Package-Thornswood\.ps1''\) @pkgArgs \}' -and $step -match 'catch \{ \$pkgThrew = \$_ \}')
Yes 'Ship declares InstallerWhy for strict mode' ($ship -match "(?m)^\`$script:InstallerWhy = ''")

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('ts-2243-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory $tmp | Out-Null
$code = [scriptblock]::Create($step + "`n`$script:after = `$true`n" + $done)

function Run([string]$packager, [int]$before = 0) {
    Set-Content -LiteralPath (Join-Path $tmp 'Package-Thornswood.ps1') -Value $packager
    $script:said = New-Object System.Collections.Generic.List[string]
    $script:InstallerFailed = 0; $script:InstallerWhy = ''; $script:after = $false
    $Here = $tmp; $Root = $tmp; $DistDir = $tmp; $ciStub = $null
    function Say([string]$t, [string]$c = 'Gray') { $script:said.Add("$c|$t") }
    $global:LASTEXITCODE = $before
    $threw = $null
    try { & $code } catch { $threw = $_ }
    return [pscustomobject]@{ Threw = $threw; Failed = $script:InstallerFailed; Why = $script:InstallerWhy; After = $script:after; Said = @($script:said) }
}

try {
    $r = Run "throw 'Generated files are stale: a file Pandora reads changed in Vortex'"
    Yes 'T1 a packager that throws does not throw out of the step (the bug in #2243)' ($null -eq $r.Threw)
    Yes 'T2 the code after the step still runs, so the rest of the release does' ($r.After)
    Yes "T3 it is recorded as an installer failure (exit $($r.Failed))" ($r.Failed -ne 0)
    Yes 'T4 with what it threw' ($r.Why -match 'Generated files are stale')
    Yes 'T5 said in red where it happened, with the reason' (@($r.Said | Where-Object { $_ -like 'Red|  THE INSTALLER DID NOT BUILD. Package-Thornswood.ps1 stopped: Generated files are stale*' }).Count -eq 1)
    Yes 'T6 and again on the Done screen, with the reason' (@($r.Said | Where-Object { $_ -like 'Red|The installer did NOT rebuild*' }).Count -eq 1 -and @($r.Said | Where-Object { $_ -like 'Red|  It stopped with: Generated files are stale*' }).Count -eq 1)
    Yes 'T7 with the command to put it right' (@($r.Said | Where-Object { $_ -like 'Yellow|*Package-Thornswood.ps1 -OneFile*' }).Count -ge 1)

    $r = Run "Write-Error 'winget is not on this machine'"
    Yes 'W1 a Write-Error under Stop is caught the same way' ($null -eq $r.Threw -and $r.After -and $r.Failed -ne 0 -and $r.Why -match 'winget')

    $r = Run 'exit 3'
    Yes 'E1 a packager that exits 3 is recorded as exit 3, as before' ($null -eq $r.Threw -and $r.After -and $r.Failed -eq 3 -and $r.Why -eq '')
    Yes 'E2 and says the exit code' (@($r.Said | Where-Object { $_ -like 'Red|  THE INSTALLER DID NOT BUILD. Package-Thornswood.ps1 exited with 3.*' }).Count -eq 1)

    $r = Run 'exit 0'
    Yes 'S1 a packager that works is not a failure and says nothing red' ($null -eq $r.Threw -and $r.After -and $r.Failed -eq 0 -and @($r.Said | Where-Object { $_ -like 'Red|*' }).Count -eq 0)

    $r = Run 'exit 0' 5
    Yes 'S2 a working packager after an earlier native exit code of 5 is still not a failure' ($r.Failed -eq 0 -and $r.After)
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "$pass passed, $fail failed"
if ($fail) { exit 1 }
