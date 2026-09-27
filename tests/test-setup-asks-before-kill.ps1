<#
  test-setup-asks-before-kill.ps1

      pwsh -NoProfile -File .\tests\test-setup-asks-before-kill.ps1

  The setup program does not end anybody's game without asking.

  WHY THIS EXISTS. 27 September: the live download, hash
  c1d2065f...0120f258b, came back 5 of 71 on VirusTotal, every one of the five
  a machine learning or hash intelligence verdict rather than a signature for
  anything known. Signing is the lasting fix and it is issue #390, deferred.
  Of what the file actually does, the one thing that was worth changing on its
  own is StopSkyrim: it enumerated Skyrim's processes, asked the windows to
  close, waited six seconds and then called Kill on whatever was left, with
  nothing said to the person sitting in front of it. Killing a process without
  consent is behaviour a model can see, and it is also plainly rude to somebody
  who had not saved. So the Kill is behind a Yes or No box now, and No stops
  the install having changed nothing.

  What this holds Bootstrap.cs to:
    - the enumeration stays. A leftover Skyrim holds the game files open and
      the install genuinely cannot carry on, so this is not the part to drop;
    - CloseMainWindow and the wait still come first, because a game that
      closes itself needs no box at all;
    - every Kill in the file sits after the ask, and the ask is a Yes or No;
    - a No throws instead, with a message that says nothing was installed;
    - the box names what is still running, says the install cannot continue
      while it is there, and says what each answer does;
    - no anti-debug call went in with it. Those read as evasion to the very
      engines this is trying to satisfy, which would trade one flag for a
      worse one.

  Read only. Reads installer\setup\Bootstrap.cs as text and runs nothing.
#>
[CmdletBinding()]
param([string]$BootstrapPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# This test lives in tests\; repo root is one level up.
$repoRoot = Split-Path -Parent $Here
if (-not $BootstrapPath) { $BootstrapPath = Join-Path $repoRoot 'installer\setup\Bootstrap.cs' }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

Yes 'Bootstrap.cs is where this expects it' (Test-Path -LiteralPath $BootstrapPath)
if (-not (Test-Path -LiteralPath $BootstrapPath)) {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    exit 1
}
$bs = [IO.File]::ReadAllText($BootstrapPath)

# ---- 1. what it still does ------------------------------------------------
Yes 'StopSkyrim is still there' ($bs.Contains('static int StopSkyrim()'))
Yes 'it still enumerates the processes, which is how a leftover one is found' (
    $bs.Contains('Process.GetProcessesByName'))
Yes 'it still asks the window to close first' ($bs.Contains('p.CloseMainWindow();'))
Yes 'and still waits for it to go' ($bs -match '(?s)CloseMainWindow.{0,900}?Thread\.Sleep\(250\)')

# ---- 2. the ask comes before the kill -------------------------------------
$iAsk = $bs.IndexOf('AskToClose(')
$iKill = $bs.IndexOf('p.Kill()')
Yes 'there is an AskToClose' ($iAsk -ge 0)
Yes 'the file still kills something, since Yes has to mean something' ($iKill -ge 0)
Yes 'the ask is written before the kill' ($iAsk -ge 0 -and $iKill -gt $iAsk)
# One Kill in the whole file, and it is the one inside the branch the ask
# guards. A second one anywhere would be a way round the box.
$kills = @([regex]::Matches($bs, '\.Kill\(\)'))
Yes ('there is exactly one Kill in the file, ' + $kills.Count + ' found') ($kills.Count -eq 1)
Yes 'the kill is inside the branch a Yes opens' (
    $bs -match '(?s)if \(!AskToClose\(left\)\).{0,700}?p\.Kill\(\)')

# ---- 3. a No stops the install and changes nothing ------------------------
Yes 'a No throws rather than killing' (
    $bs -match '(?s)if \(!AskToClose\(left\)\)\s*\{.{0,400}?throw new Exception')
Yes 'and says nothing was installed' ($bs -match 'nothing was installed')
Yes 'and tells the person what to do instead' ($bs -match 'Close it yourself')

# ---- 4. what the box says -------------------------------------------------
$ask = ''
$iFn = $bs.IndexOf('static bool AskToClose')
if ($iFn -ge 0) { $ask = $bs.Substring($iFn) }
Yes 'the box is a Yes or No, not a warning that carries on anyway' (
    $ask.Contains('MessageBoxButton.YesNo'))
Yes 'it names what is still running' ($ask -match 'Skyrim is still running')
Yes 'it says a helper left behind by a crash is the other thing this can be' (
    $ask -match '(?i)helper of it left behind by a crash')
Yes 'it says why the install cannot carry on' (
    $ask -match 'install cannot carry on while it is there')
Yes 'it says what Yes costs' ($ask -match 'Yes ends it, and anything not saved in the game is lost')
Yes 'and that No changes nothing' ($ask -match 'No stops the install and changes nothing')
# The box is put up from the unpack thread, so it goes through the window's
# dispatcher. Called straight it would throw on a WPF window from that thread.
Yes 'it is asked on the window thread' ($ask -match 'win\.Dispatcher\.Invoke')
Yes 'and anything that goes wrong asking counts as No' ($ask -match 'catch \{ return false; \}')

# ---- 5. nothing that reads as evasion went in with it ---------------------
foreach ($api in @('IsDebuggerPresent', 'CheckRemoteDebuggerPresent',
                   'NtQueryInformationProcess', 'Debugger.IsAttached',
                   'NtSetInformationThread')) {
    Yes ('no anti-debug call: ' + $api) (-not $bs.Contains($api))
}

# ---- 6. the page that explains all of this --------------------------------
$page = Join-Path $repoRoot 'docs\VIRUSTOTAL-FALSE-POSITIVE.md'
Yes 'docs\VIRUSTOTAL-FALSE-POSITIVE.md is there' (Test-Path -LiteralPath $page)
Yes 'and Bootstrap points at it' ($bs.Contains('VIRUSTOTAL-FALSE-POSITIVE.md'))
if (Test-Path -LiteralPath $page) {
    $doc = [IO.File]::ReadAllText($page)
    Yes 'the page says signing is the lasting fix and names the issue' ($doc -match '#390')
    Yes 'it gives the report address shape' (
        $doc.Contains('https://www.virustotal.com/gui/file/'))
    Yes 'it carries the identity strings the setup program uses' (
        $doc.Contains('Thornswood Setup') -and $doc.Contains('thornswood.net'))
    Yes 'it says the McAfeeD verdict is hash intelligence off VirusTotal itself' (
        $doc -match 'ti!' -and $doc -match '(?i)feed')
    Yes 'it says each new build is a new hash and has to be done again' (
        $doc -match '(?i)new build is a new hash')
    Yes 'it names the vendors that take a report' (
        $doc -match 'CrowdStrike' -and $doc -match 'McAfee' -and
        $doc -match 'Microsoft' -and $doc -match '(?i)smartscreen')
    Yes 'and it has no em dash in it' (-not $doc.Contains([string][char]0x2014))
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
