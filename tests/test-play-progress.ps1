<#
  test-play-progress.ps1

      pwsh -NoProfile -File .\tests\test-play-progress.ps1

  The Play button as a progress bar, issue #1145.

  Patrick, 29 Sep: "when the launcher is preparing the own game folder or
  doing an update I want a progress bar on the Play button and not just
  updating or preparing the game folder". Done when: the button fills as a
  progress bar with a percentage and what it is doing in plain words, driven
  by real byte or file counts, never goes backwards, shows a steady state
  when the size is unknown, and returns to Play when done.

  What this drives:

    1. launcher\app\Progress.cs (PlayBar, PlayProgress, ProgressStep) with
       Swallow.cs, compiled with the .NET Framework csc as C# 5, the way
       Build-Launcher.ps1 compiles the launcher, into a small program that
       feeds it the reports each piece of work makes, in the order they make
       them: an update synced to its release record (checking files, then the
       download), several packs, a self-update, the client download, the own
       game folder (preparing, then checking), a download whose size nobody
       said, and a failure. At every step it checks the button's words, the
       fill, that nothing goes backwards, the moving state, that a burst of
       reports is one redraw, and that the button says Play (or the error it
       said before) once the work ends.
    2. The wiring, read from the real files: the fill in the Primary style's
       template in ui.xaml, the timer and the fill in ShellProgress.cs,
       DrawStatus putting the words first and keeping the button off, and
       every caller (Updater.Download, Sync, RunUpdate, the client repair,
       OwnGame.Make and Refresh, StartOwnGame, Verify.Bytes) reporting and
       closing what it opens.

  Read only apart from its own temp folder, which it removes.
#>
[CmdletBinding()]
param([string]$AppDir, [string]$Xaml)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here
if (-not $AppDir) { $AppDir = Join-Path $Repo 'launcher\app' }
if (-not $Xaml) { $Xaml = Join-Path $Repo 'launcher\ui.xaml' }

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

# Everything between the first line matching $start and the brace that closes it.
function Body([string]$src, [string]$start) {
    $at = $src.IndexOf($start)
    if ($at -lt 0) { return '' }
    $open = $src.IndexOf('{', $at)
    $depth = 0
    for ($i = $open; $i -lt $src.Length; $i++) {
        if ($src[$i] -eq '{') { $depth++ }
        elseif ($src[$i] -eq '}') { $depth--; if ($depth -eq 0) { return $src.Substring($at, $i - $at + 1) } }
    }
    return ''
}

$progressPath = Join-Path $AppDir 'Progress.cs'
Yes 'Progress.cs is in the launcher source' (Test-Path -LiteralPath $progressPath)
if (-not (Test-Path -LiteralPath $progressPath)) { Done }

# ---- 1. compile the real model and drive it ------------------------------------
$csc = @("$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe", "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe") |
    Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
Yes 'the .NET Framework 4 compiler is here' ($null -ne $csc)
if (-not $csc) { Done }

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('ts-play-progress-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null

$driver = @'
using System;
using System.Collections.Generic;
namespace Thornswood
{
    static class Paths { public static string LogFile; }
    static class Drive
    {
        static int pass, fail;
        static PlayBar bar = new PlayBar();
        static List<string> said = new List<string>();
        const long MB = 1048576;

        static void Yes(string what, bool ok)
        {
            if (ok) { pass++; Console.WriteLine("PASS  " + what); }
            else { fail++; Console.WriteLine("FAIL  " + what + "   (text: \"" + bar.Text + "\", fill " + bar.Fill.ToString("0.000") + ", active " + bar.Active + ")"); }
        }
        static void Is(string what, string want)
        {
            Yes(what + ": \"" + want + "\"", bar.Text == want);
        }

        // What ShellProgress.cs does with every report.
        static void Sink(ProgressStep s)
        {
            if (s == null) bar.Stop(); else bar.Offer(s);
            if (bar.Active) said.Add(bar.Text);
        }

        static int Main()
        {
            PlayProgress.Sink = Sink;

            // ---- idle ------------------------------------------------------
            Yes("idle: the button is not working", !bar.Active);
            Yes("idle: the button says what it would anyway", bar.Caption("PLAY") == "PLAY");
            Yes("idle: nothing to redraw", !bar.TakeDirty());
            PlayProgress.Files("Checking files", 5, 10);
            PlayProgress.Part(10, 100);
            Yes("a report with no work open (Fix, Scan, the check before Play) does not touch the button", !bar.Active && !bar.Dirty);

            // ---- an update synced to its release record --------------------
            PlayProgress.Begin("Updating", 1);
            Yes("Begin: the button is working", bar.Active);
            Is("Begin: before anything is counted", "Updating ...");
            Yes("Begin: the fill is the moving state", bar.Fill < 0);
            Yes("Begin: a redraw is due", bar.TakeDirty());
            Yes("Begin: the caption replaces Play", bar.Caption("PLAY") == "Updating ...");

            PlayProgress.Files("Checking files", 1200, 2580);
            Is("checking the install", "Checking files 46%, 1,200 of 2,580 files");
            Yes("checking: fill is 1,200 of 2,580", Math.Abs(bar.Fill - 1200.0 / 2580) < 1e-9);
            PlayProgress.Files("Checking files", 1100, 2580);
            Is("a lower count in the same phase is dropped", "Checking files 46%, 1,200 of 2,580 files");
            Yes("  and the fill stays", Math.Abs(bar.Fill - 1200.0 / 2580) < 1e-9);
            PlayProgress.Report("Checking files", 0, 0, 0, 0, "files");
            Yes("a known total never turns back into an unknown one", bar.Fill > 0.4);
            PlayProgress.Files("Checking files", 2580, 2580);
            Is("checking finished", "Checking files 100%, 2,580 of 2,580 files");

            PlayProgress.Bytes("Updating", 0, 740 * MB);
            Is("a new phase starts from its own beginning", "Updating 0%, 0 of 740 MB");
            Yes("  its fill is empty, not the last phase's", bar.Fill == 0);
            bar.TakeDirty();
            int redraws = 0;
            for (long b = 1; b <= 310 * MB; b += 81920)
            {
                PlayProgress.Bytes("Updating", b, 740 * MB);
                if (b % (50 * 81920) == 1) { if (bar.TakeDirty()) redraws++; }
            }
            PlayProgress.Bytes("Updating", 310 * MB, 740 * MB);
            Is("downloading", "Updating 41%, 310 of 740 MB");
            Yes("downloading: fill is 310 of 740", Math.Abs(bar.Fill - 310.0 / 740) < 1e-9);
            Yes("3,968 reports make one redraw per timer tick, not one each (" + redraws + " ticks asked)", redraws <= 80 && redraws >= 1);
            Yes("  and the last one is still waiting for the next tick", bar.TakeDirty());
            Yes("  and only once", !bar.TakeDirty());
            PlayProgress.Bytes("Updating", 300 * MB, 740 * MB);
            Is("a download that restarts lower does not move the bar back", "Updating 41%, 310 of 740 MB");
            Yes("  nothing to redraw", !bar.TakeDirty());
            PlayProgress.Bytes("Updating", 740 * MB - 1, 740 * MB);
            Yes("one byte short is 99%, not 100%", bar.Text.StartsWith("Updating 99%"));
            PlayProgress.Bytes("Updating", 740 * MB, 740 * MB);
            Is("download finished", "Updating 100%, 740 of 740 MB");
            Yes("  fill is full", bar.Fill == 1);

            // ---- then the launcher itself -----------------------------------
            PlayProgress.Plan("Updating the launcher", 1, "updates");
            Is("the self-update is its own phase", "Updating the launcher ...");
            PlayProgress.Part(0, 3743496);
            PlayProgress.Part(1871748, 3743496);
            Is("the launcher download", "Updating the launcher 50%, 1.7 of 3.5 MB");
            PlayProgress.PartDone();
            PlayProgress.Part(10, 100);
            Is("a second download the plan did not count leaves it alone", "Updating the launcher 50%, 1.7 of 3.5 MB");

            PlayProgress.End();
            Yes("End: the button is not working", !bar.Active);
            Yes("End: the button says Play again", bar.Caption("PLAY") == "PLAY");
            Yes("End: a redraw is due, so it gets back to Play at once", bar.TakeDirty());
            Yes("End: the fill is empty", bar.Fill == 0);
            PlayProgress.End();
            Yes("a second End changes nothing", !bar.Active && !bar.Dirty);

            // ---- several packs: which one, and the bytes of the one under way
            PlayProgress.Begin("Updating", 3);
            PlayProgress.Part(0, 2825);
            PlayProgress.Part(1400, 2825);
            Is("pack one of three, half down", "Updating 16%, 0 of 3 updates");
            PlayProgress.Part(2825, 2825);
            PlayProgress.PartDone();
            Is("pack one in", "Updating 33%, 1 of 3 updates");
            PlayProgress.Part(0, 5000000);
            Is("the next pack starting does not move the bar back", "Updating 33%, 1 of 3 updates");
            PlayProgress.Part(2500000, 5000000);
            Is("pack two half down", "Updating 50%, 1 of 3 updates");
            PlayProgress.PartDone();
            PlayProgress.Part(0, -1);
            PlayProgress.Part(700000, -1);
            Is("pack three with no size said", "Updating 66%, 2 of 3 updates");
            PlayProgress.PartDone();
            Is("all three", "Updating 100%, 3 of 3 updates");
            PlayProgress.End();

            // ---- one small pack, in KB ---------------------------------------
            PlayProgress.Begin("Updating", 1);
            PlayProgress.Part(1400, 2825);
            Is("a small pack", "Updating 49%, 2 of 3 KB");
            PlayProgress.End();

            // ---- a size nobody said ------------------------------------------
            PlayProgress.Begin("Updating", 1);
            PlayProgress.Part(0, -1);
            Is("no size: the steady moving state", "Updating ...");
            Yes("  fill is the moving state", bar.Fill < 0);
            PlayProgress.Part(5 * MB + MB / 2, -1);
            Is("no size: how much so far", "Updating, 5.5 MB so far");
            Yes("  still moving", bar.Fill < 0);
            PlayProgress.Part(12 * MB, -1);
            Is("no size: more so far", "Updating, 12 MB so far");
            PlayProgress.Part(3 * MB, -1);
            Is("no size: less than before is dropped", "Updating, 12 MB so far");
            PlayProgress.End();

            // ---- the client repair -------------------------------------------
            PlayProgress.Begin("Updating", 1);
            PlayProgress.Part(0, 6573503);
            PlayProgress.Part(3286752, 6573503);
            Is("the client download", "Updating 50%, 3.1 of 6.2 MB");
            PlayProgress.End();

            // ---- the own game folder -----------------------------------------
            PlayProgress.Begin("Preparing the game folder", 0);
            Is("preparing, before the folder is walked", "Preparing the game folder ...");
            PlayProgress.Files("Preparing the game folder", 0, 2580);
            PlayProgress.Files("Preparing the game folder", 1200, 2580);
            Is("preparing", "Preparing the game folder 46%, 1,200 of 2,580 files");
            PlayProgress.Files("Preparing the game folder", 2580, 2580);
            PlayProgress.Files("Checking files", 1, 1);
            Is("one file is a file", "Checking files 100%, 1 of 1 file");
            PlayProgress.Files("Checking files", 40, 238);
            Is("a count that would move a finished phase back is dropped", "Checking files 100%, 1 of 1 file");

            // Two pieces of work at once: the button waits for both.
            PlayProgress.Begin("Updating", 1);
            PlayProgress.End();
            Yes("the first of two to finish leaves the button working", bar.Active);
            PlayProgress.End();
            Yes("the second puts it back", !bar.Active);

            // ---- a failure ---------------------------------------------------
            PlayProgress.Begin("Updating", 1);
            PlayProgress.Part(10 * MB, 20 * MB);
            PlayProgress.End();
            Yes("a failed update gives the button back its own error", bar.Caption("NO ANSWER FROM THE UPDATE SOURCE") == "NO ANSWER FROM THE UPDATE SOURCE");

            // ---- a sink that throws is noted, never thrown -------------------
            PlayProgress.Sink = delegate(ProgressStep s) { throw new Exception("broken sink"); };
            bool threw = false;
            try { PlayProgress.Begin("Updating", 1); PlayProgress.Part(1, 2); PlayProgress.End(); }
            catch (Exception) { threw = true; }
            Yes("a sink that throws never stops the work", !threw);
            PlayProgress.Sink = Sink;

            // ---- the words ---------------------------------------------------
            bool clean = said.Count > 20;
            foreach (string t in said)
                if (t.IndexOf((char)0x2014) >= 0 || t.IndexOf("player", StringComparison.OrdinalIgnoreCase) >= 0) clean = false;
            Yes("none of the " + said.Count + " captions has an em dash or the word player", clean);

            Console.WriteLine("RESULT " + pass + " " + fail);
            return fail == 0 ? 0 : 1;
        }
    }
}
'@
$driverPath = Join-Path $tmp 'Drive.cs'
[IO.File]::WriteAllText($driverPath, $driver, (New-Object Text.UTF8Encoding($false)))
$exe = Join-Path $tmp 'drive.exe'
$cscArgs = @('/noconfig', '/nologo', '/target:exe', '/platform:anycpu', '/langversion:5', "/out:$exe",
             '/reference:System.dll', $progressPath, (Join-Path $AppDir 'Swallow.cs'), $driverPath)
$old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
$said = & $csc @cscArgs 2>&1
$ErrorActionPreference = $old
Yes 'Progress.cs compiles with the .NET Framework csc, as C# 5' ((Test-Path -LiteralPath $exe) -and $LASTEXITCODE -eq 0)
if (-not (Test-Path -LiteralPath $exe)) {
    $said | ForEach-Object { Write-Host "      $_" }
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Done
}
$out = & $exe 2>&1
$code = $LASTEXITCODE
foreach ($line in $out) {
    $l = [string]$line
    if ($l.StartsWith('PASS  ')) { $script:pass++; Write-Host $l }
    elseif ($l.StartsWith('FAIL  ')) { $script:fail++; Write-Host $l }
}
Yes 'the driver ran to the end' (($out | Where-Object { ([string]$_).StartsWith('RESULT ') }).Count -eq 1)
Yes 'the driver exits 0 only when every step passed' (($code -eq 0) -eq (($out | Where-Object { ([string]$_).StartsWith('FAIL  ') }).Count -eq 0))
Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue

# ---- 2. the wiring -----------------------------------------------------------------
$xamlText = Read-Text $Xaml
$pAt = $xamlText.IndexOf('<Style x:Key="Primary"')
$primary = if ($pAt -ge 0) { $xamlText.Substring($pAt, $xamlText.IndexOf('</Style>', $pAt) - $pAt) } else { '' }
Yes 'ui.xaml: the Primary style is there' ($primary.Length -gt 0)
$fillAt = $primary.IndexOf('x:Name="fill"')
Yes 'ui.xaml: the Primary template has the fill' ($fillAt -ge 0)
Yes 'ui.xaml: the fill sits over the face and under the words' ($fillAt -gt $primary.IndexOf('x:Name="b"') -and $fillAt -lt $primary.IndexOf('<ContentPresenter'))
$fillTag = if ($fillAt -ge 0) { $primary.Substring($primary.LastIndexOf('<', $fillAt), $primary.IndexOf('>', $fillAt) - $primary.LastIndexOf('<', $fillAt)) } else { '' }
Yes 'ui.xaml: the fill starts hidden, empty, from the left, and takes no clicks' ($fillTag -match 'Visibility="Collapsed"' -and $fillTag -match 'Width="0"' -and $fillTag -match 'HorizontalAlignment="Left"' -and $fillTag -match 'IsHitTestVisible="False"')
Yes 'ui.xaml: the fill is the launcher''s accent colour, so every theme keeps its look' (([regex]::Matches($primary, 'Background="\{DynamicResource Accent\}"')).Count -ge 3)
Yes 'ui.xaml: the button keeps its height' ($primary -match '<Setter Property="Height" Value="56"/>')
try {
    $doc = New-Object Xml.XmlDocument
    $doc.LoadXml($xamlText)
    Yes 'ui.xaml still reads as XML' $true
} catch { Yes ('ui.xaml still reads as XML: ' + $_.Exception.Message) $false }

$sp = Read-Text (Join-Path $AppDir 'ShellProgress.cs')
Yes 'ShellProgress.cs: the sink feeds the PlayBar and Stop on the end' ($sp -match 'PlayProgress\.Sink\s*=' -and $sp -match 'playBar\.Stop\(\)' -and $sp -match 'playBar\.Offer\(s\)')
Yes 'ShellProgress.cs: redraws on a timer every PlayBar.DrawEveryMs, only when something changed' ($sp -match 'FromMilliseconds\(PlayBar\.DrawEveryMs\)' -and $sp -match 'if \(playBar\.TakeDirty\(\)\) DrawPlayBar\(\)')
Yes 'ShellProgress.cs: one wake per run, not a BeginInvoke per report' ($sp -match 'Interlocked\.CompareExchange\(ref playBarTicking, 1, 0\)')
Yes 'ShellProgress.cs: finds the fill in the button''s template' ($sp -match 'Template\.FindName\("fill", btnPlay\)')
Yes 'ShellProgress.cs: an unknown total slides a band steadily, for ever' ($sp -match 'RepeatBehavior\.Forever' -and $sp -match 'AutoReverse = true')
Yes 'ShellProgress.cs: a known total sets the width from the fill' ($sp -match 'playFill\.Width = Math\.Max\(0, Math\.Min\(1\.0, f\)\) \* w')
Yes 'ShellProgress.cs: when the work ends the fill goes and DrawStatus puts Play or the reason back' ((Body $sp 'static void DrawPlayBar()') -match 'HidePlayFill\(\);\s*(//[^\n]*\n\s*)*DrawStatus\(\);')
Yes 'ShellProgress.cs: the words read on the fill and on the face (Ink)' ($sp -match 'SetResourceReference\(Control\.ForegroundProperty, "Ink"\)' -and $sp -match 'ClearValue\(Control\.ForegroundProperty\)')
Yes 'ShellProgress.cs: redrawn when the window is resized' ($sp -match 'btnPlay\.SizeChanged')

$shell = Read-Text (Join-Path $AppDir 'Shell.cs')
$draw = Body $shell 'static bool DrawStatus()'
Yes 'Shell.cs: WireProgress is called' ($shell -match 'WireProgress\(\);')
Yes 'DrawStatus: the button is off while work runs' ($draw -match '!working &&')
$wAt = $draw.IndexOf('if (working && !playing)')
Yes 'DrawStatus: the progress words come before every other reason' ($wAt -ge 0 -and $wAt -lt $draw.IndexOf('else if (ownGameBusy && !playing)') -and $wAt -lt $draw.IndexOf('else if (updatePending && !playing)'))
Yes 'DrawStatus: with no work, the fill goes' ($draw -match 'if \(!working\) HidePlayFill\(\);')
Yes 'DrawStatus: PLAY is still the last word' ($draw -match 'btnPlay\.Content = "PLAY";')
$heal = Body $shell 'static void HealClientBackground()'
Yes 'the client repair opens the button before it starts and closes it in its finally' ($heal -match 'PlayProgress\.Begin\("Updating", 1\)' -and $heal -match 'finally\s*\{[^}]*PlayProgress\.End\(\);')

$upd = Read-Text (Join-Path $AppDir 'Updater.cs')
$dl = Body $upd 'static string Download(Config cfg'
Yes 'Updater.Download reports each piece it reads' ($dl -match 'PlayProgress\.Part\(had, length\)' -and $dl -match 'PlayProgress\.PartDone\(\)')
Yes 'Updater.Download reads the size the server gives' ($dl -match 'Content-Length')
Yes 'Updater.Download no longer uses DownloadFile, and throws a half file away' ($dl -notmatch '\.DownloadFile\(' -and $dl -match 'File\.Delete\(tmp\)')
Yes 'Updater.Download still checks the url and the checksum' ($dl -match 'CheckUrl\(url\)' -and $dl -match 'Checksum did not match')

$sync = Read-Text (Join-Path $AppDir 'Sync.cs')
Yes 'Sync: checking the install counts every file' ($sync -match 'PlayProgress\.Files\("Checking files", \+\+looked, items\.Count\)')
Yes 'Sync: the downloads report their bytes against the total' ($sync -match 'PlayProgress\.Bytes\("Updating", before \+ Math\.Min\(had, f\.Value\), total\)')
Yes 'Sync: Transfer reports as it writes' ((Body $sync 'static void Transfer(') -match 'onBytes\(had\)')
Yes 'Sync: packs after a record without its files are planned as downloads' ($sync -match 'PlayProgress\.Plan\("Updating", count, "updates"\)')

$su = Read-Text (Join-Path $AppDir 'ShellUpdate.cs')
$run = Body $su 'static void RunUpdate()'
Yes 'RunUpdate opens the button with one download per pack' ($run -match 'PlayProgress\.Begin\("Updating", downloads\)')
Yes 'RunUpdate: the self-update is its own phase' ($run -match 'PlayProgress\.Plan\("Updating the launcher", 1, "updates"\)')
Yes 'RunUpdate closes it when it finishes and when it fails, before DrawStatus' (([regex]::Matches($run, 'PlayProgress\.End\(\);\s*(updatePending = false;\s*)?DrawStatus\(\)')).Count -eq 2)

$sog = Read-Text (Join-Path $AppDir 'ShellOwnGame.cs')
# The overload that does the work. Since #1584 StartOwnGame(make, loud) only
# hands on to StartOwnGame(make, loud, then), which runs a step once the
# bring-up-to-date Play asked for has finished.
$start = Body $sog 'static void StartOwnGame(bool make, bool loud, Action then)'
Yes 'StartOwnGame opens the button' ($start -match 'PlayProgress\.Begin\(OwnGame\.Phase, 0\)')
Yes 'StartOwnGame closes it as soon as the work is over' ($start -match 'ownGameBusy = false;\s*PlayProgress\.End\(\);')

$og = Read-Text (Join-Path $AppDir 'OwnGame.cs')
Yes 'OwnGame: the phase is "Preparing the game folder"' ($og -match 'public const string Phase = "Preparing the game folder";')
Yes 'OwnGame.Make counts every file it brings over' ((Body $og 'static string MakeNow(') -match 'PlayProgress\.Files\(Phase, looked\+\+, all\.Count\)')
Yes 'OwnGame.Refresh counts every file it compares' ((Body $og 'static string RefreshNow(') -match 'PlayProgress\.Files\(Phase, looked\+\+, all\.Count\)')

$ver = Read-Text (Join-Path $AppDir 'Verify.cs')
# Full and light (#1715): the light plugins a server publishes are checked
# after its full ones, and counted with them.
$bytesBody = Body $ver 'public static List<Issue> Bytes('
Yes 'Verify.Bytes counts the plugins it checks, full and light' (
    $bytesBody -match 'int all = mods\.Length \+ light\.Length;' -and $bytesBody -match 'PlayProgress\.Files\("Checking files", idx \+ 1, all\)')

# C# 5 and the words, in the two new files.
foreach ($n in @('Progress.cs', 'ShellProgress.cs')) {
    $t = Read-Text (Join-Path $AppDir $n)
    Yes "$n is C# 5: no interpolation, ?., nameof or =>" (-not ($t -match '\$"' -or $t -match '\?\.' -or $t -match 'nameof\(' -or $t -match '\)\s*=>'))
    Yes "$n has no em dash and never says player" (-not ($t.Contains([string][char]0x2014) -or $t -match '(?i)player'))
}

Done
