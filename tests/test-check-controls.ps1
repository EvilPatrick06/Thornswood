<#
  test-check-controls.ps1

  Check-Controls.ps1 has to fail when the launcher's window has drifted or
  broken, or the build check that runs it proves nothing.

  WHY. Shell.cs builds the whole window at startup from ui.xaml with
  XamlReader.Parse, then finds every control by name with FindName. There is
  no compiler anywhere in that. A control renamed in ui.xaml is null at
  runtime, and a ui.xaml that does not parse stops the launcher before anybody
  sees a window. Either one was found by the person using the launcher, not by
  the build.

  MEASURED 24 SEPTEMBER. Check-Controls.ps1 already compared the names, but it
  had no exit statement anywhere: its last line was the Read-Host behind
  -NoPause, so it returned 0 whatever it printed, and nothing ran it. With
  TxtPing renamed in ui.xaml it printed "NEW   TxtPing ... this will be null at
  runtime" and exited 0. It never parsed the file at all, so a window WPF
  refuses passed it clean.

  This runs the shipped script against copies of ui.xaml and launcher\app with one
  thing wrong in each, and reads the exit code a build step would read.

  Read only apart from files under its own temp folder.
#>
[CmdletBinding()]
param([string]$CheckPath)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, the repository is one folder up.
$Here = Split-Path -Parent $Here
. (Join-Path $PSScriptRoot 'Windows.ps1')
if (-not $CheckPath) { $CheckPath = Join-Path $Here 'scripts\dev\Check-Controls.ps1' }
$RealXaml = Join-Path $Here 'launcher\ui.xaml'
$RealApp  = Join-Path $Here 'launcher\app'

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

# The same PowerShell this harness runs under, so the build check's pwsh runs
# pwsh and a person's Windows PowerShell runs Windows PowerShell.
$Exe = (Get-Process -Id $PID).Path

# Runs the check the way a build step does, in its own process with -NoPause,
# and hands back what it printed and the exit code it left.
function Run-Check([string]$xaml, [string]$app) {
    $out = & $Exe -NoProfile -File $CheckPath -Xaml $xaml -AppDir $app -NoPause | Out-String
    return @{ Out = $out; Code = $LASTEXITCODE }
}

$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('ts-check-controls-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $Tmp | Out-Null

try {
    $xamlText = [System.IO.File]::ReadAllText($RealXaml)

    # A copy of ui.xaml with one change, written into the temp folder.
    function Xaml-With([string]$name, [string]$from, [string]$to) {
        $p = Join-Path $Tmp $name
        [System.IO.File]::WriteAllText($p, $xamlText.Replace($from, $to))
        return $p
    }

    # ---- as things stand ------------------------------------------------------
    $r = Run-Check $RealXaml $RealApp
    Yes 'the real ui.xaml and launcher\app exit 0' ($r.Code -eq 0)
    Yes 'nothing is NEW' ($r.Out -notmatch '\bNEW\b')
    # The baseline is empty since #3146 took out the last guarded lookups.
    Yes 'nothing is missing, so nothing leans on the baseline' ($r.Out -match '(?ms)Looked up but not in ui\.xaml.*?^\s*none\s*$' -and $r.Out -notmatch '(?m)^\s*known\s')
    if ($OnWindows) { Yes 'it says ui.xaml parses' ($r.Out -match '(?ms)Does ui\.xaml parse.*?^\s*yes\s*$') }
    else { Yes 'off Windows it says the parse was not checked, and why' ($r.Out -match '(?ms)Does ui\.xaml parse.*?^\s*not checked: WPF, which reads it, is only on Windows\s*$') }

    # ---- a looked up control renamed in ui.xaml -------------------------------
    #
    # TxtPing is the ping readout on the top bar. Shell.cs looks it up by name,
    # and nothing inside ui.xaml refers to it, so renaming it leaves a window
    # that still parses and a field that is null at runtime.
    Yes 'ui.xaml names TxtPing, so the rename below changes something' ($xamlText.Contains('x:Name="TxtPing"'))
    $renamed = Xaml-With 'renamed.xaml' 'x:Name="TxtPing"' 'x:Name="TxtPingRenamed"'
    $r = Run-Check $renamed $RealApp
    Yes 'a renamed control is reported as NEW' ($r.Out -match 'NEW\s+TxtPing\b')
    Yes 'a renamed control exits 1' ($r.Code -eq 1)
    if ($OnWindows) { Yes 'the renamed window still parses, so the 1 is the name alone' ($r.Out -match '(?ms)Does ui\.xaml parse.*?^\s*yes\s*$') }

    # ---- a window WPF refuses -------------------------------------------------
    #
    # Well formed XML and every name intact, so only a real parse sees it.
    if ($OnWindows) {
        Yes 'ui.xaml sets Width="1220" on the window' ($xamlText.Contains('Width="1220"'))
        $badValue = Xaml-With 'bad-value.xaml' 'Width="1220"' 'Width="wide"'
        $r = Run-Check $badValue $RealApp
        Yes 'a property value WPF refuses is reported as not parsing' ($r.Out -match 'does not parse')
        Yes 'a property value WPF refuses exits 1' ($r.Code -eq 1)
        Yes 'the report carries the line it failed on' ($r.Out -match '(?i)line\D{0,20}3\b')
        Yes 'and the names alone were fine' ($r.Out -notmatch '\bNEW\b')

        $badXml = Xaml-With 'bad-xml.xaml' '</Window>' ''
        $r = Run-Check $badXml $RealApp
        Yes 'a window with no closing tag exits 1' (($r.Out -match 'does not parse') -and $r.Code -eq 1)
    } else {
        Write-Host 'SKIP  a window WPF refuses: XamlReader, which reads it, is in WPF, which only Windows has'
    }

    # ---- the baseline, seeded -------------------------------------------------
    #
    # The real control-baseline.txt names nothing since #3146, so a copy of the
    # script runs beside a seeded one that names BoxGone. A copy of
    # launcher\app that still looks BoxGone up reads it as known; the real
    # launcher\app, which does not, leaves the line stale, which is
    # information and not a failure.
    $dev = Join-Path $Tmp 'dev'
    New-Item -ItemType Directory -Force -Path $dev | Out-Null
    Copy-Item -LiteralPath $CheckPath -Destination (Join-Path $dev 'Check-Controls.ps1')
    [System.IO.File]::WriteAllText((Join-Path $dev 'control-baseline.txt'), "# seeded`r`nBoxGone`r`n")
    $app = Join-Path $Tmp 'app'
    New-Item -ItemType Directory -Force -Path $app | Out-Null
    foreach ($f in (Get-ChildItem -LiteralPath $RealApp -Filter '*.cs' -File)) { Copy-Item -LiteralPath $f.FullName -Destination $app }
    [System.IO.File]::WriteAllText((Join-Path $app 'Gone.cs'), 'class Gone { static void G() { var b = F<TextBox>("BoxGone"); if (b != null) b.Text = ""; } }')
    $real = $CheckPath
    $CheckPath = Join-Path $dev 'Check-Controls.ps1'
    $r = Run-Check $RealXaml $app
    Yes 'a missing name on the baseline is reported as known, not NEW' ($r.Out -match '(?m)^\s*known\s+BoxGone\b' -and $r.Out -notmatch '\bNEW\b')
    Yes 'a known name does not fail the check' ($r.Code -eq 0)
    $r = Run-Check $RealXaml $RealApp
    Yes 'a baseline name nothing looks up is reported as stale' ($r.Out -match 'stale\s+BoxGone\b')
    Yes 'a stale baseline line does not fail the check' ($r.Code -eq 0)
    $CheckPath = $real

    # ---- the exit code a person reads in the same session ---------------------
    #
    # Run in process, the way ".\scripts\dev\Check-Controls.ps1 -NoPause; $LASTEXITCODE"
    # runs it. A script that simply ends leaves the session's last exit code
    # alone, so without an explicit exit 0 the clean run after a failing one
    # would still read 1.
    & $CheckPath -Xaml $renamed -AppDir $RealApp -NoPause 6>$null | Out-Null
    $first = $LASTEXITCODE
    & $CheckPath -Xaml $RealXaml -AppDir $RealApp -NoPause 6>$null | Out-Null
    $second = $LASTEXITCODE
    Yes ("in one session, a failing run then a clean one read 1 then 0 (read {0} then {1})" -f $first, $second) ($first -eq 1 -and $second -eq 0)

    # ---- the build check runs it ----------------------------------------------
    $yml = Join-Path $Here '.github\workflows\build.yml'
    if (Test-Path -LiteralPath $yml) {
        $y = [System.IO.File]::ReadAllText($yml)
        Yes 'build.yml runs Check-Controls.ps1 with -NoPause' ($y -match 'Check-Controls\.ps1[^\r\n]*-NoPause')
    } else {
        Write-Host 'SKIP  no .github\workflows\build.yml next to tools, so there is no build check to read'
    }
}
finally {
    Remove-Item -LiteralPath $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
