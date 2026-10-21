<#
  test-feed-notice.ps1

  What the update feed says to everybody, and when it may hold Play.

  To Do List entry 262: "There is no way to say anything to everybody when an
  outside thing breaks". version.json has carried a message field from the
  start, and the launcher's whole treatment of it was one line in OnVersionDoc:

      if (!string.IsNullOrEmpty(v.message)) Log(v.message);

  a log line that scrolled away. Now the message is a bar above Play, and two
  new fields, maintenance and minLauncher, can hold Play with the reason in
  that bar. That makes it a kill switch, and a kill switch is only safe if
  every doubt comes out open. So this asks the launcher's own code, compiled
  from the files that ship, every case that could shut Play by accident:

    - a notice on its own never holds Play
    - a feed older than the new fields, or with them null, still reads, and
      holds nothing
    - a document that was never read holds nothing
    - a minimum that is not a version number holds nothing, and since #1329
      Updater.IsNewer by itself no longer calls "latest" newer either
    - a maintenance value that is not plainly on holds nothing, and a value
      that would have thrown as a bool reads without a word

  The C# is compiled with the compiler the build runs, at the C# version the
  project names (Add-LauncherType, tests\Launcher-Csc.ps1, #2821), and run
  under Windows PowerShell on the same serializer the launcher reads the feed
  with. Measured on 24
  September: that serializer turns "maintenance": null or "yes" on a bool field
  into an exception, and an exception there is the whole document unread and
  Play shut for everybody. Under pwsh this hands itself to powershell.exe for
  that reason; the harness step on GitHub runs pwsh.

  It also reads every file of the Shell class and ui.xaml for the wiring: the bar is found by name,
  the log line is gone, the hold is on the button and in Play(), it can only be
  set from a document that was read, and the bar has a grid row of its own.

  Read only. The compiler writes its dll under the temp folder, and it is
  removed once loaded.
#>
[CmdletBinding()]
param(
    [string]$AppDir,
    [string]$Xaml
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, the repository is one folder up.
$Here = Split-Path -Parent $Here
if (-not $AppDir) { $AppDir = Join-Path $Here 'launcher\app' }
if (-not $Xaml) { $Xaml = Join-Path $Here 'launcher\ui.xaml' }

. (Join-Path $PSScriptRoot 'Windows.ps1')
if (-not $OnWindows) { Write-Host 'NOT RUN  this runs the launcher''s code on the .NET Framework the launcher runs on, which only Windows has'; exit 0 }
# The launcher's serializer is the .NET Framework's, so the answer has to come
# from there and not from .NET under pwsh.
if ($PSVersionTable.PSEdition -eq 'Core') {
    $wp = Get-WindowsPowerShell
    & $wp -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -AppDir $AppDir -Xaml $Xaml
    exit $LASTEXITCODE
}
. (Join-Path $PSScriptRoot 'Launcher-Csc.ps1')   # the build's compiler and C# version (#2821)

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Done {
    Write-Host ''
    Write-Host "$script:pass passed, $script:fail failed"
    exit $(if ($script:fail) { 1 } else { 0 })
}
function Read-Text([string]$p) { return [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8) }

$configPath = Join-Path $AppDir 'Config.cs'
$updaterPath = Join-Path $AppDir 'Updater.cs'
$noticePath = Join-Path $AppDir 'FeedNotice.cs'
$shellPath = Join-Path $AppDir 'Shell.cs'

Yes 'FeedNotice.cs is in the launcher source' (Test-Path -LiteralPath $noticePath)
if (-not (Test-Path -LiteralPath $noticePath)) { Done }

$configSrc = Read-Text $configPath
# Config.Load and Save call Secrets, so it comes along. Nothing here calls it.
$secretsSrc = Read-Text (Join-Path $AppDir 'Secrets.cs')
# Config.Save logs what it swallows through Swallow.Note (entry 239), so
# Swallow.cs comes along too, with a stand-in for the one field of Paths it
# reads. Left null, a note writes nothing, which keeps this read only.
$swallowSrc = Read-Text (Join-Path $AppDir 'Swallow.cs')
$pathsStub = "namespace Thornswood`r`n{`r`n    static class Paths { public static string LogFile; }`r`n}`r`n"
$updaterSrc = Read-Text $updaterPath
$noticeSrc = Read-Text $noticePath
# The Shell class is split across files (#500): ShowNotice, OnVersionDoc and
# CheckFailed moved to ShellUpdate.cs. Every file of the class is read, so the
# counts below cover the whole class whichever file the code is in next.
$shellSrc = Read-Text $shellPath
foreach ($f in (Get-ChildItem -LiteralPath $AppDir -Filter '*.cs' | Sort-Object Name)) {
    if ($f.Name -eq 'Shell.cs') { continue }
    $t = Read-Text $f.FullName
    if ($t -match '\bpartial class Shell\b') { $shellSrc += "`r`n" + $t }
}

# ---- lift Updater.IsNewer and Parts out of the shipped Updater.cs -----------
# Updater.cs as a whole needs half the launcher to compile. The comparison is
# two methods that need nothing, so they are cut out by brace matching and
# compiled into a class of the same name. The answer is the shipped code's.
function Lift([string]$src, [string]$signature) {
    $at = $src.IndexOf($signature)
    if ($at -lt 0) { return $null }
    $lineStart = $src.LastIndexOf("`n", $at) + 1
    $open = $src.IndexOf('{', $at)
    $depth = 0
    for ($i = $open; $i -lt $src.Length; $i++) {
        $c = $src[$i]
        if ($c -eq '{') { $depth++ }
        elseif ($c -eq '}') { $depth--; if ($depth -eq 0) { return $src.Substring($lineStart, $i - $lineStart + 1) } }
    }
    return $null
}
$isNewer = Lift $updaterSrc 'public static bool IsNewer('
$parts = Lift $updaterSrc 'static int[] Parts('
Yes 'Updater.IsNewer is in Updater.cs' ($null -ne $isNewer)
Yes 'Updater.Parts is in Updater.cs' ($null -ne $parts)
if ($null -eq $isNewer -or $null -eq $parts) { Done }
$updaterStub = "using System;`r`nnamespace Thornswood`r`n{`r`n    static class Updater`r`n    {`r`n" +
               $isNewer + "`r`n" + $parts + "`r`n    }`r`n}`r`n"

# ---- compile Config.cs, FeedNotice.cs and the comparison --------------------
$asm = $null
try { $asm = Add-LauncherType -Source $configSrc, $secretsSrc, $swallowSrc, $pathsStub, $noticeSrc, $updaterStub }
catch { Write-Host ('      ' + $_.Exception.Message) }
Yes 'Config.cs and FeedNotice.cs compile with the compiler the build runs' ($null -ne $asm)
if ($null -eq $asm) { Done }

$DocT = $asm.GetType('Thornswood.VersionDoc')
$NoticeT = $asm.GetType('Thornswood.FeedNotice')
$UpdaterT = $asm.GetType('Thornswood.Updater')

$Running = '1.1.92'

# One feed, as the launcher reads it: bytes through VersionDoc.Parse, then
# FeedNotice.From. A throw anywhere is reported, not swallowed.
function Ask([string]$json, [string]$running = $Running) {
    $r = @{ Threw = $null; Notice = $null }
    try {
        $doc = $DocT::Parse([Text.Encoding]::UTF8.GetBytes($json))
        $r.Notice = $NoticeT::From($doc, $running)
    }
    catch { $r.Threw = $_.Exception.GetBaseException().Message }
    return $r
}
# The case that must never hold: no bar and no hold, and it read.
function Quiet([string]$what, [string]$json) {
    $a = Ask $json
    Yes "$what reads without a throw" ($null -eq $a.Threw)
    if ($a.Threw) { Write-Host "      $($a.Threw)"; return }
    Yes "$what shows no bar" ($null -eq $a.Notice.Title)
    Yes "$what leaves Play open" ($null -eq $a.Notice.Hold)
}
# A notice that shows but must not hold.
function Says([string]$what, [string]$json) {
    $a = Ask $json
    Yes "$what reads without a throw" ($null -eq $a.Threw)
    if ($a.Threw) { Write-Host "      $($a.Threw)"; return $null }
    Yes "$what shows the bar" ($null -ne $a.Notice.Title)
    Yes "$what leaves Play open" ($null -eq $a.Notice.Hold)
    return $a.Notice
}
# A hold, with everything the button and the bar need to say why.
function Holds([string]$what, [string]$json, [string]$running = $Running) {
    $a = Ask $json $running
    Yes "$what reads without a throw" ($null -eq $a.Threw)
    if ($a.Threw) { Write-Host "      $($a.Threw)"; return $null }
    $n = $a.Notice
    Yes "$what holds Play" ($null -ne $n.Hold)
    Yes "$what says why in the bar and on the button" ($n.Title -and $n.Text -and $n.Button -and $n.Hold)
    return $n
}

# ---- S1: nothing to say. None of these may show anything or hold anything ---
Quiet 'S1 the feed as it is today, message ""' '{"launcherVersion":"1.1.92","message":""}'
Quiet 'S1 a feed from before the message field' '{"launcherVersion":"1.0.1","packs":[]}'
Quiet 'S1 an empty document' '{}'
Quiet 'S1 a message of spaces' '{"message":"   "}'
Quiet 'S1 every new field null' '{"message":null,"maintenance":null,"minLauncher":null}'
$none = $NoticeT::From($null, $Running)
Yes 'S1 a check that got no document shows no bar' ($null -eq $none.Title)
Yes 'S1 and leaves Play open' ($null -eq $none.Hold)

# ---- S2: a notice on its own never holds Play --------------------------------
$msg = 'Steam updated Skyrim tonight. Do not let it update again; the fix is on its way.'
$n = Says 'S2 a message on its own' ('{"message":"' + $msg + '"}')
if ($n) {
    Yes 'S2 the bar carries the message word for word' ($n.Text -eq $msg)
    Yes 'S2 and the button is left alone' ($null -eq $n.Button)
}
$n = Says 'S2 a message with maintenance false' ('{"message":"' + $msg + '","maintenance":false}')
$n = Says 'S2 a message with a minimum this launcher meets' ('{"message":"' + $msg + '","minLauncher":"1.1.92"}')

# ---- S3: maintenance ---------------------------------------------------------
$n = Holds 'S3 maintenance true with a message' ('{"maintenance":true,"message":"' + $msg + '"}')
if ($n) {
    Yes 'S3 the bar gives the message as the reason' ($n.Text.Contains($msg))
    Yes 'S3 the log line gives it too' ($n.Hold.Contains($msg))
    Yes "S3 the button says $($n.Button)" ($n.Button -eq 'CLOSED FOR MAINTENANCE')
}
$n = Holds 'S3 maintenance true and no message' '{"maintenance":true}'
if ($n) { Yes 'S3 the bar still says something' ($n.Text.Length -gt 20) }
$n = Holds 'S3 maintenance with a message that has no full stop' '{"maintenance":true,"message":"Steam broke SKSE"}'
if ($n) { Yes 'S3 the reason still reads as a sentence' ($n.Text.StartsWith('Steam broke SKSE. Open Diagnostics')) }
$n = Says 'S3 the same message with no maintenance' '{"message":"Steam broke SKSE"}'
if ($n) { Yes 'S3 is shown exactly as it was written' ($n.Text -eq 'Steam broke SKSE') }
$n = Holds 'S3 maintenance "true" as a string' '{"maintenance":"true"}'
$n = Holds 'S3 maintenance 1' '{"maintenance":1}'
$n = Holds 'S3 maintenance "yes"' '{"maintenance":"yes"}'
Quiet 'S3 maintenance false' '{"maintenance":false}'
Quiet 'S3 maintenance "false"' '{"maintenance":"false"}'
Quiet 'S3 maintenance 0' '{"maintenance":0}'
Quiet 'S3 maintenance ""' '{"maintenance":""}'
Quiet 'S3 maintenance "maybe", a typo' '{"maintenance":"maybe"}'

# ---- S4: the minimum launcher version ----------------------------------------
$n = Holds 'S4 a minimum above this launcher' '{"minLauncher":"1.1.93"}'
if ($n) {
    Yes "S4 the button says $($n.Button)" ($n.Button -eq 'UPDATE THE LAUNCHER')
    Yes 'S4 the bar names both versions' ($n.Text.Contains('1.1.93') -and $n.Text.Contains($Running))
}
Quiet 'S4 a minimum equal to this launcher' '{"minLauncher":"1.1.92"}'
Quiet 'S4 a minimum below this launcher' '{"minLauncher":"1.1.40"}'
Quiet 'S4 an empty minimum' '{"minLauncher":""}'
$n = Holds 'S4 a minimum with a leading v' '{"minLauncher":"v1.1.93"}'
$n = Holds 'S4 a minimum written as a JSON number' '{"minLauncher":1.2}'
# #1329: a version on either side that does not read as dotted numbers is not
# an update. It used to be, which is why the notice reads the minimum itself.
Yes ('S4 Updater.IsNewer on its own no longer calls "latest" newer than ' + $Running) (-not $UpdaterT::IsNewer('latest', $Running))
Quiet 'S4 so a minimum of "latest" is not a version and holds nothing' '{"minLauncher":"latest"}'
Quiet 'S4 a minimum of "1.1."' '{"minLauncher":"1.1."}'
Quiet 'S4 a minimum with a part too long for an int' '{"minLauncher":"1.1.9999999999"}'
$a = Ask '{"minLauncher":"1.1.92"}' '1.1.92.1'
Yes 'S4 a dev build 1.1.92.1 meets a minimum of 1.1.92' ($null -eq $a.Threw -and $null -eq $a.Notice.Hold)
$n = Holds 'S4 a dev build 1.1.92.1 below a minimum of 1.1.93' '{"minLauncher":"1.1.93"}' '1.1.92.1'
$a = Ask '{"minLauncher":"1.1.93"}' 'dev'
Yes 'S4 a running version that is not a number is never held' ($null -eq $a.Threw -and $null -eq $a.Notice.Hold)

# ---- S5: both at once --------------------------------------------------------
$n = Holds 'S5 maintenance and a minimum above' '{"maintenance":true,"minLauncher":"1.1.93"}'
if ($n) { Yes 'S5 maintenance is what it says' ($n.Button -eq 'CLOSED FOR MAINTENANCE') }
$n = Holds 'S5 a minimum above with a message' ('{"minLauncher":"1.1.93","message":"' + $msg + '"}')
if ($n) { Yes 'S5 the message still reaches the bar' ($n.Text.Contains($msg)) }

# ---- S6: the words people read -----------------------------------------------
$strings = [regex]::Matches($noticeSrc, '"((?:[^"\\]|\\.)*)"') | ForEach-Object { $_.Groups[1].Value }
$said = ($strings -join ' ')
# Built from two halves so a search of the repository for the word finds real
# uses and not this check.
$banned = 'play' + 'er'
Yes 'S6 no text in FeedNotice.cs uses the word CLAUDE.md rules out for people' (-not ($said -match ('(?i)' + $banned)))
Yes 'S6 no text in FeedNotice.cs carries an em dash' (-not $said.Contains([string][char]0x2014))

# ---- S7: the wiring in the Shell class ---------------------------------------
Yes 'S7 the message no longer goes only to the log' (-not $shellSrc.Contains('Log(v.message)'))
Yes 'S7 the bar is found by name' ($shellSrc.Contains('F<Border>("NoticeBar")'))
Yes 'S7 its heading is found by name' ($shellSrc.Contains('F<TextBlock>("TxtNoticeTitle")'))
Yes 'S7 its sentence is found by name' ($shellSrc.Contains('F<TextBlock>("TxtNoticeNote")'))
$gate = [regex]::Match($shellSrc, 'btnPlay\.IsEnabled = all [^;]*;').Value
Yes 'S7 the Play button is shut while the feed holds it' ($gate.Contains('feedNotice.Hold == null'))
Yes 'S7 Play() refuses too, for the ways in that are not the button' ($shellSrc.Contains('if (feedNotice.Hold != null) { Log(feedNotice.Hold); return; }'))
$sets = @([regex]::Matches($shellSrc, '\bfeedNotice\s*=[^=]') | ForEach-Object { $_.Value })
Yes "S7 feedNotice is set in two places, its declaration and ShowNotice ($($sets.Count) found)" ($sets.Count -eq 2)
Yes 'S7 it starts empty, so nothing is held before a document is read' ($shellSrc.Contains('static FeedNotice feedNotice = new FeedNotice();'))
Yes 'S7 ShowNotice sets it from the document' ($shellSrc.Contains('feedNotice = FeedNotice.From(v, Updater.Version);'))
$calls = @([regex]::Matches($shellSrc, '\bShowNotice\(') ).Count
Yes "S7 ShowNotice is defined once and called once ($calls found)" ($calls -eq 2)
$ovd = Lift $shellSrc 'static void OnVersionDoc(VersionDoc v, bool loud)'
Yes 'S7 and the one call is in OnVersionDoc, which only ever has a document that was read' ($null -ne $ovd -and $ovd.Contains('ShowNotice(v);'))
$failed = Lift $shellSrc 'static void CheckFailed(string why)'
Yes 'S7 a failed check does not touch the notice' ($null -ne $failed -and -not $failed.Contains('feedNotice') -and -not $failed.Contains('ShowNotice'))

# ---- S8: the bar in ui.xaml --------------------------------------------------
$xns = 'http://schemas.microsoft.com/winfx/2006/xaml'
[xml]$ui = Read-Text $Xaml
$page = $null
foreach ($g in $ui.GetElementsByTagName('Grid')) { if ($g.GetAttribute('Name', $xns) -eq 'PagePlay') { $page = $g; break } }
Yes 'S8 the Play page is in ui.xaml' ($null -ne $page)
if ($page) {
    $rows = 0
    $kids = @()
    foreach ($k in $page.ChildNodes) {
        if ($k.NodeType -ne 'Element') { continue }
        if ($k.LocalName -eq 'Grid.RowDefinitions') { $rows = @($k.ChildNodes | Where-Object { $_.NodeType -eq 'Element' }).Count; continue }
        $kids += $k
    }
    $bar = $null; $playRow = -1; $maxRow = 0
    foreach ($k in $kids) {
        $r = 0; if ($k.GetAttribute('Grid.Row')) { $r = [int]$k.GetAttribute('Grid.Row') }
        if ($r -gt $maxRow) { $maxRow = $r }
        if ($k.GetAttribute('Name', $xns) -eq 'NoticeBar') { $bar = $k }
        if ($k.OuterXml.Contains('x:Name="BtnPlay"') -or $k.OuterXml.Contains('Name="BtnPlay"')) { $playRow = $r }
    }
    Yes 'S8 NoticeBar sits on the Play page' ($null -ne $bar)
    if ($bar) {
        $barRow = [int]$bar.GetAttribute('Grid.Row')
        $shared = @($kids | Where-Object { $_ -ne $bar -and ([int]$_.GetAttribute('Grid.Row')) -eq $barRow })
        Yes "S8 it has row $barRow to itself, so it cannot cover an update card" ($shared.Count -eq 0)
        Yes 'S8 it sits above the Play button' ($playRow -gt $barRow)
        Yes 'S8 it is hidden until a feed says something' ($bar.GetAttribute('Visibility') -eq 'Collapsed')
        Yes 'S8 it holds the heading and the sentence' ($bar.OuterXml.Contains('Name="TxtNoticeTitle"') -and $bar.OuterXml.Contains('Name="TxtNoticeNote"'))
    }
    Yes "S8 every row the page uses is defined ($rows rows, highest used $maxRow)" ($maxRow -lt $rows)
}

Done
