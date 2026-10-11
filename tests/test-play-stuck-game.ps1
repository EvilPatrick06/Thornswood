<#
  test-play-stuck-game.ps1

      pwsh -NoProfile -File .\tests\test-play-stuck-game.ps1

  The Play path's guards that no harness ran: ClearStuckGame,
  CloseGameWaiting, ClearLeftovers and EnsureServer in launcher\app\Shell.cs.

  Each method is lifted out of the real Shell.cs (the brace-matched body, the
  way test-play-progress.ps1 reads its wiring) and compiled with the .NET
  Framework csc as C# 5, the way Build-Launcher.ps1 compiles the launcher,
  beside stand-ins for Checks, SkyMp, MessageBox, Waiting and Log. The
  stand-ins script every answer the real ones can give, so this fails if a
  guard starts closing somebody's other Skyrim, closes a visible game without
  asking, carries on when the game would not close, kills a session that is
  still loading, or lets the game start against a local server that never came
  up. Then the order of the steps in Play is read from the file: the busy
  guards, ClearStuckGame, Verify, EnsureServer, Keep/Hold, and only then
  Process.Start.

  No process is started or ended. Read only apart from its own temp folder.
#>
[CmdletBinding()]
param([string]$AppDir)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here
if (-not $AppDir) { $AppDir = Join-Path $Repo 'launcher\app' }

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

$shellPath = Join-Path $AppDir 'Shell.cs'
Yes 'Shell.cs is in the launcher source' (Test-Path -LiteralPath $shellPath)
if (-not (Test-Path -LiteralPath $shellPath)) { Done }
$shell = [IO.File]::ReadAllText($shellPath, [Text.Encoding]::UTF8)

$sigs = @('static bool ClearStuckGame(bool askIfVisible)', 'static string CloseGameWaiting(out int closed)',
          'static string ClearLeftovers()', 'static bool EnsureServer()')
$bodies = @()
foreach ($sig in $sigs) {
    $b = Body $shell $sig
    Yes "lifted $sig" ($b.Length -gt 0)
    $bodies += $b
}
if ($script:fail) { Done }

$csc = @("$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe", "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe") |
    Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
Yes 'the .NET Framework 4 compiler is here' ($null -ne $csc)
if (-not $csc) { Done }

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('ts-play-stuck-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null

$driver = @'
using System;
using System.Collections.Generic;
namespace Thornswood
{
    enum MessageBoxButton { OK, YesNo }
    enum MessageBoxImage { Warning }
    enum MessageBoxResult { None, OK, Yes, No }
    class Config { }
    static class MessageBox
    {
        public static MessageBoxResult Answer = MessageBoxResult.No;
        public static List<string> Asked = new List<string>();
        public static MessageBoxResult Show(string text, string title, MessageBoxButton b, MessageBoxImage i)
        { Asked.Add(text); return b == MessageBoxButton.OK ? MessageBoxResult.OK : Answer; }
    }
    static class Checks
    {
        public static bool Running, Other, Visible;
        public static int Closes, CloseCalls;
        public static string Stuck = "";
        public static bool GameRunning() { return Running; }
        public static bool OtherSkyrimRunning() { return Other; }
        public static bool GameVisible() { return Visible; }
        public static int CloseGame() { CloseCalls++; return Closes; }
        public static string StuckReport() { return Stuck; }
    }
    static class SkyMp
    {
        public static bool IsUp, Local, Throw;
        public static string StartSays;
        public static int Starts;
        public static bool Up(Config c) { if (Throw) throw new InvalidOperationException("boom"); return IsUp; }
        public static bool IsLocal(Config c) { return Local; }
        public static string Start(Config c, Action<string> say) { Starts++; return StartSays; }
    }
    static partial class Shell
    {
        static Config cfg = new Config();
        static string stallDoing;
        static bool young;
        static int waits;
        static string stallSeenInside;
        static List<string> logged = new List<string>();
        static void Log(string m) { logged.Add(m); }
        static void SafeLog(string m) { logged.Add(m); }
        static void Waiting(Action a) { waits++; stallSeenInside = stallDoing; a(); }
        static bool JustStarted(int seconds) { return young; }

__METHODS__

        static int pass, fail;
        static void Yes(string what, bool ok)
        {
            if (ok) { pass++; Console.WriteLine("PASS  " + what); }
            else { fail++; Console.WriteLine("FAIL  " + what); }
        }
        static void Reset()
        {
            Checks.Running = Checks.Other = Checks.Visible = false;
            Checks.Closes = 0; Checks.CloseCalls = 0; Checks.Stuck = "";
            SkyMp.IsUp = SkyMp.Local = SkyMp.Throw = false; SkyMp.StartSays = null; SkyMp.Starts = 0;
            MessageBox.Answer = MessageBoxResult.No; MessageBox.Asked.Clear();
            logged.Clear(); young = false; waits = 0; stallSeenInside = null; stallDoing = null;
        }
        static bool LoggedHas(string s) { foreach (string l in logged) if (l.Contains(s)) return true; return false; }

        static int Main()
        {
            // ---- ClearStuckGame -------------------------------------------
            Reset();
            Yes("nothing running: Play goes on, nothing asked or closed", ClearStuckGame(true) && MessageBox.Asked.Count == 0 && Checks.CloseCalls == 0);

            Reset(); Checks.Other = true;
            Yes("another folder's Skyrim, asked and refused: stop, it is not closed", !ClearStuckGame(true) && MessageBox.Asked.Count == 1 && Checks.CloseCalls == 0);
            Reset(); Checks.Other = true; MessageBox.Answer = MessageBoxResult.Yes;
            Yes("another folder's Skyrim, asked and accepted: go on, still not closed", ClearStuckGame(true) && Checks.CloseCalls == 0);
            Reset(); Checks.Other = true;
            Yes("another folder's Skyrim with no asking: go on, never closed", ClearStuckGame(false) && MessageBox.Asked.Count == 0 && Checks.CloseCalls == 0);

            Reset(); Checks.Running = true; Checks.Visible = true;
            Yes("our game on screen, refused: stop and close nothing", !ClearStuckGame(true) && Checks.CloseCalls == 0 && LoggedHas("Left the game"));
            Reset(); Checks.Running = true; Checks.Visible = true;
            Yes("our game on screen with no asking: never closed silently", !ClearStuckGame(false) && Checks.CloseCalls == 0 && MessageBox.Asked.Count == 0);
            Reset(); Checks.Running = true; Checks.Visible = true; MessageBox.Answer = MessageBoxResult.Yes; Checks.Closes = 2;
            Yes("our game on screen, accepted: closed and Play goes on", ClearStuckGame(true) && Checks.CloseCalls == 1 && LoggedHas("Closed 2 Skyrim processes"));

            Reset(); Checks.Running = true; Checks.Closes = 1;
            Yes("windowless leftover: closed without asking", ClearStuckGame(true) && MessageBox.Asked.Count == 0 && LoggedHas("Closed 1 Skyrim process that"));
            Reset(); Checks.Running = true; Checks.Stuck = "Still running: SkyrimSE.exe (process 9).";
            Yes("leftover that will not close: stop, and say what is still running", !ClearStuckGame(true) && MessageBox.Asked.Count == 1 && MessageBox.Asked[0].Contains("SkyrimSE.exe"));
            Reset(); Checks.Running = true; Checks.Stuck = "Still running: x.";
            Yes("leftover that will not close, no asking: stop with no box", !ClearStuckGame(false) && MessageBox.Asked.Count == 0);

            // ---- CloseGameWaiting -----------------------------------------
            Reset(); Checks.Closes = 3; Checks.Stuck = null; int n;
            string still = CloseGameWaiting(out n);
            Yes("CloseGameWaiting closes inside Waiting with the stall label set", waits == 1 && stallSeenInside == "closing Skyrim");
            Yes("CloseGameWaiting clears the stall label and counts what closed", stallDoing == null && n == 3);
            Yes("a null StuckReport comes back as empty, not null", still == "");

            // ---- ClearLeftovers -------------------------------------------
            Reset();
            Yes("startup: nothing running, nothing to say", ClearLeftovers() == null && Checks.CloseCalls == 0);
            Reset(); Checks.Running = true; Checks.Visible = true;
            Yes("startup: a visible game is left alone", ClearLeftovers() == null && Checks.CloseCalls == 0);
            Reset(); Checks.Running = true; young = true;
            Yes("startup: a windowless game still loading in is left alone", ClearLeftovers() == null && Checks.CloseCalls == 0);
            Reset(); Checks.Running = true; Checks.Closes = 2;
            string s = ClearLeftovers();
            Yes("startup: an old windowless leftover is closed and counted", s != null && s.Contains("Closed 2 Skyrim processes") && Checks.CloseCalls == 1);
            Reset(); Checks.Running = true; Checks.Stuck = "Still running: y.";
            s = ClearLeftovers();
            Yes("startup: one that would not close is reported", s != null && s.Contains("would not close") && s.Contains("Still running: y."));

            // ---- EnsureServer ---------------------------------------------
            Reset(); SkyMp.IsUp = true;
            Yes("server answering: go, nothing started or asked", EnsureServer() && SkyMp.Starts == 0 && MessageBox.Asked.Count == 0);
            Reset();
            Yes("remote server silent, refused: do not start", !EnsureServer() && MessageBox.Asked.Count == 1 && SkyMp.Starts == 0);
            Reset(); MessageBox.Answer = MessageBoxResult.Yes;
            Yes("remote server silent, accepted: start anyway, never start a server", EnsureServer() && SkyMp.Starts == 0);
            Reset(); SkyMp.Local = true;
            Yes("local server down and comes up: started inside Waiting, go", EnsureServer() && SkyMp.Starts == 1 && waits == 1 && LoggedHas("The server is up."));
            Reset(); SkyMp.Local = true; SkyMp.StartSays = "Node is missing.";
            Yes("local server will not start: stop and show why", !EnsureServer() && MessageBox.Asked.Count == 1 && MessageBox.Asked[0] == "Node is missing.");
            Reset(); SkyMp.Throw = true;
            Yes("a check that throws is logged and lets Play go on (as written)", EnsureServer() && LoggedHas("Could not check the server: boom"));

            Console.WriteLine();
            Console.WriteLine(pass + " passed, " + fail + " failed");
            return fail == 0 ? 0 : 1;
        }
    }
}
'@
$driver = $driver.Replace('__METHODS__', ($bodies -join "`r`n`r`n"))

$src = Join-Path $tmp 'drive.cs'
$exe = Join-Path $tmp 'drive.exe'
[IO.File]::WriteAllText($src, $driver, (New-Object Text.UTF8Encoding($false)))
try {
    $out = & $csc /nologo /langversion:5 /target:exe "/out:$exe" $src 2>&1
    Yes 'the lifted guards compile as C# 5' ($LASTEXITCODE -eq 0)
    if ($LASTEXITCODE -ne 0) { $out | Write-Host; Done }
    $lines = & $exe
    $code = $LASTEXITCODE
    foreach ($l in $lines) {
        if ($l -like 'PASS  *') { $script:pass++; Write-Host $l }
        elseif ($l -like 'FAIL  *') { $script:fail++; Write-Host $l }
    }
    Yes 'the driver exits 0' ($code -eq 0)
}
finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }

# ---- 2. the order of Play's steps, read from the file ----------------------
$play = Body $shell 'static void Play()'
Yes 'Play() is in Shell.cs' ($play.Length -gt 0)
$steps = @('if (updatePending)', 'if (collectionBarUp)', 'if (ownGameBusy)', 'File.Exists(Paths.Loader)',
           'ClearStuckGame(true)', 'Verify.Run(cfg)', 'EnsureServer()', 'Keep.Restore()', 'Hold.Take(', 'Swap.Apply()', 'Process.Start(psi)')
$prev = -1; $prevName = 'the top'
foreach ($st in $steps) {
    $i = $play.IndexOf($st)
    Yes "Play has $st after $prevName" ($i -gt $prev)
    if ($i -ge 0) { $prev = $i; $prevName = $st }
}
Yes 'a refused ClearStuckGame returns before the game starts' ($play.Contains('if (!ClearStuckGame(true)) return;'))
Yes 'a refused EnsureServer returns before the game starts' ($play.Contains('if (!EnsureServer()) return;'))
$upd = [IO.File]::ReadAllText((Join-Path $AppDir 'ShellUpdate.cs'), [Text.Encoding]::UTF8)
Yes 'the update path also stops on a refused ClearStuckGame' ($upd.Contains('if (!ClearStuckGame(true)) return;'))

Done
