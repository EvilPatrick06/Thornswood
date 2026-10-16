<#
  test-self-update.ps1

  The launcher's self update keeps the old exe until the new one has started,
  and puts it back when the new one does not.

  WHY THIS EXISTS. On the To Do List as "The launcher's self update destroys
  the old exe and has no way back". The swap script moved the new exe straight
  over the old one, so a new build that Defender flagged, or that fell over on
  its first start, left somebody with no launcher at all. The entry: "An
  unsigned exe that Defender flags is exactly when a fallback is needed".

  WHAT IT DOES. Compiles launcher\app\SelfSwap.cs on its own with the .NET
  Framework 4 csc, the compiler the launcher is built with, which also proves
  it is still C# 5. Compiles stub launchers around it:

      old         the launcher asking for the update, and the one put back
      new-good    starts, calls the real SelfSwap.Settle, stays up
      new-broken  exits 1 the moment it starts
      new-late    stays up three seconds and exits 1 without drawing, like
                  the "could not start" box somebody reads and closes
      new-hang    stays up past the script's watch without drawing

  Each writes what it did, with its pid, into events.txt beside itself. Then,
  in a scratch folder laid out like an install (<case>\Launcher\Thornswood.exe),
  it does what Updater.SelfUpdate does once the new exe is at Thornswood.exe.new:
  writes the script for the exe, the .new and the pid of the launcher asking,
  and starts it hidden through the shell. The launcher asking is an old stub
  that takes two seconds to close, as the real one does. Then it reads what is
  where, who started, in what order, and who is still running.

  MEASURED 24 SEPTEMBER, and the reason the script looks the way it does:
      a running exe renames without complaint (move exited 0 under a live stub)
      it cannot be opened for writing while it runs, and can once it has exited
      start on a missing file puts up a "Windows cannot find" box and waits
      start leaves errorlevel as it found it when it works

  Issue #497, 29 Sep: the launcher's name from before the rename is gone from
  the update path too, so the new build always goes in at the running
  launcher's own path and nothing renames or repoints anything.
  tests\test-old-name-gone.js checks that no tracked file names it at all.

  Not driven: start failing on a file that is there (Defender blocking it, a
  file that is not a program). Windows puts up a box for those too, on the
  desktop of whoever runs this. The watch covers the same case without start's
  word for it, because a launcher that never started is not holding its file,
  and new-broken is that case as far as the script can tell.

  Writes only under its own folder in %TEMP%, and ends every stub it started.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Launcher-Csc.ps1')   # the build's compiler and C# version (#498)
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here
$App = Join-Path $Repo 'launcher\app'

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Finish {
    Write-Host ''
    Write-Host "$($script:pass) passed, $($script:fail) failed"
    if ($script:fail) { exit 1 }
    exit 0
}

# ---- the sources say what they should ---------------------------------------
$swapCs = Join-Path $App 'SelfSwap.cs'
$haveSwap = Test-Path -LiteralPath $swapCs
Yes 'launcher\app\SelfSwap.cs exists' $haveSwap

$upd = Get-Content -LiteralPath (Join-Path $App 'Updater.cs') -Raw
# Since #2210 SelfUpdate is FetchLauncher then SwapIn, so an update can
# download while the game folder is prepared; SwapIn is what writes the script.
Yes 'Updater.SelfUpdate is FetchLauncher then SwapIn' ($upd -match 'public static void SelfUpdate\(Config cfg, VersionDoc v, Action<string> log\)\s*\{\s*SwapIn\(FetchLauncher\(cfg, v, log\), log\);\s*\}')
$at = $upd.IndexOf('public static void SwapIn(')
Yes 'Updater.SwapIn is there' ($at -ge 0)
$body = ''
if ($at -ge 0) {
    # To the brace that closes the method, at its own indentation.
    $m = [regex]::Match($upd.Substring($at), '(?s)^.*?\n        \}\r?\n')
    if ($m.Success) { $body = $m.Value } else { $body = $upd.Substring($at) }
}
Yes 'SelfUpdate writes the script SelfSwap builds' ($body -match 'File\.WriteAllText\(bat, SelfSwap\.Script\(exe, neu, me\)\)')
Yes 'SelfUpdate still starts it hidden' (($body -match 'WindowStyle = System\.Diagnostics\.ProcessWindowStyle\.Hidden') -and ($body -match 'CreateNoWindow = true') -and ($body -match 'UseShellExecute = true'))
Yes 'SelfUpdate no longer moves the new exe over the old one itself' ($upd -notmatch 'move /y')

$shell = Get-Content -LiteralPath (Join-Path $App 'Shell.cs') -Raw
Yes 'the launcher clears the kept copy once its window has drawn' ($shell -match '(?s)ContentRendered\s*\+=\s*delegate\s*\{.{0,800}?SelfSwap\.Settle\(')

# ---- issue #497: the update path renames nothing -----------------------------
# Release 1 (#901) taught the update to rename an install still under the
# launcher's name from before the rename, and Icons to repoint its shortcuts.
# Patrick, 29 Sep: nobody has those old files any more, so both went. The
# update puts the new build at the running exe's own path, as before #901.
$icons = Get-Content -LiteralPath (Join-Path $App 'Icons.cs') -Raw
$swapAll = ''
if ($haveSwap) { $swapAll = Get-Content -LiteralPath $swapCs -Raw }
Yes '#497: SelfSwap has no Target, AimsAtOld, OldName or NewName' ($swapAll -cnotmatch '\b(Target|AimsAtOld|OldName|NewName)\b')
Yes '#497: SelfSwap names no exe file at all' ($swapAll -notmatch '"[^"]*\.exe"')
Yes '#497: the updater asks SelfSwap for no other destination' ($upd -cnotmatch 'SelfSwap\.(Target|NewName)')
Yes '#497: Icons repoints no shortcut aimed at another exe' ($icons -cnotmatch 'AimsAtOld|SelfSwap\.(OldName|NewName)')

if (-not $haveSwap) { Finish }
$swapSrc = Get-Content -LiteralPath $swapCs -Raw
# The compile below is the real proof, since this csc stops at C# 5. This is
# the same search the entry gives, so a failure names what it found.
Yes 'SelfSwap.cs has no C# 6: no $", no ?., no nameof' (-not ($swapSrc -match '\$"|\?\.|nameof\('))

$csc = @(
    "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
    "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
Yes 'the .NET Framework 4 csc is on this machine' ([bool]$csc)
if (-not $csc) { Finish }

# `find` in the script has to be Windows' own. A PATH with Git's usr\bin ahead
# of System32 would hand it GNU find, and the wait would end at once.
$env:PATH = (Join-Path $env:SystemRoot 'System32') + ';' + $env:PATH

$root = Join-Path ([IO.Path]::GetTempPath()) ('tsself-' + [Guid]::NewGuid().ToString('N'))
$bin = Join-Path $root 'bin'
New-Item -ItemType Directory -Force -Path $bin | Out-Null

$stubSrc = @'
using System;
using System.IO;
using System.Reflection;
using System.Threading;

[assembly: AssemblyInformationalVersion(Stub.Version)]
[assembly: AssemblyFileVersion(Stub.Version)]

class Stub
{
#if NEW
    public const string Version = "2.0.0";
#else
    public const string Version = "1.0.0";
#endif
#if GOOD
    const string Who = "new-good";
#elif BROKEN
    const string Who = "new-broken";
#elif LATE
    const string Who = "new-late";
#elif HANG
    const string Who = "new-hang";
#else
    const string Who = "old";
#endif

    static void Say(string dir, string line)
    {
        for (int i = 0; i < 100; i++)
        {
            try { File.AppendAllText(Path.Combine(dir, "events.txt"), line + "\r\n"); return; }
            catch (IOException) { Thread.Sleep(20); }
        }
    }

    static int Main(string[] args)
    {
        string exe = Assembly.GetExecutingAssembly().Location;
        string dir = Path.GetDirectoryName(exe);
        int me = System.Diagnostics.Process.GetCurrentProcess().Id;
        if (args.Length > 1 && args[0] == "--closing")
        {
            Thread.Sleep(int.Parse(args[1]));
            Say(dir, Who + " closed " + me);
            return 0;
        }
        Say(dir, Who + " started " + me);
#if BROKEN
        return 1;
#elif LATE
        Thread.Sleep(3000);
        Say(dir, Who + " gave up " + me);
        return 1;
#elif HANG
        Thread.Sleep(30000);
        return 0;
#else
        Thread.Sleep(300);
        string said = Thornswood.SelfSwap.Settle(exe);
        Say(dir, Who + " settled " + me + (said == null ? "" : ": " + said));
        Thread.Sleep(20000);
        return 0;
#endif
    }
}
'@

$driverSrc = @'
using System;
using System.Diagnostics;
using System.IO;

class Driver
{
    // What Updater.SelfUpdate does once the new exe is at exe.new: write the
    // script, start it hidden through the shell.
    // Arguments: bat exe neu pid checks|- [--write-only]
    static int Main(string[] a)
    {
        string bat = a[0], exe = a[1], neu = a[2];
        int pid = int.Parse(a[3]);
        string text = a[4] == "-"
            ? Thornswood.SelfSwap.Script(exe, neu, pid)
            : Thornswood.SelfSwap.Script(exe, neu, pid, int.Parse(a[4]));
        File.WriteAllText(bat, text);
        if (a.Length > 5 && a[5] == "--write-only") return 0;
        var psi = new ProcessStartInfo(bat);
        psi.WindowStyle = ProcessWindowStyle.Hidden;
        psi.CreateNoWindow = true;
        psi.UseShellExecute = true;
        Process.Start(psi);
        return 0;
    }
}
'@

[IO.File]::WriteAllText((Join-Path $bin 'Stub.cs'), $stubSrc)
[IO.File]::WriteAllText((Join-Path $bin 'Driver.cs'), $driverSrc)

# /noconfig and the one reference by name, the way Build-Launcher.ps1 compiles:
# csc.rsp on a machine with the reference assemblies installed (the GitHub
# runner) is what stopped the launcher build with CS1703.
function Build([string]$out, [string]$target, [string]$define, [string[]]$src) {
    $a = @('/noconfig', '/nologo', "/target:$target", "/out:$out", '/reference:System.dll')
    if ($define) { $a += "/define:$define" }
    $a += $src
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $o = & $LauncherCsc @a 2>&1
    $rc = $LASTEXITCODE
    $ErrorActionPreference = $old
    if ($rc -ne 0) { $o | Where-Object { $_ -match 'error' } | ForEach-Object { Write-Host "      $_" } }
    return ($rc -eq 0 -and (Test-Path -LiteralPath $out))
}

$stubCs = Join-Path $bin 'Stub.cs'
$driver = Join-Path $bin 'driver.exe'
$built = Build $driver 'exe' '' @((Join-Path $bin 'Driver.cs'), $swapCs)
Yes 'SelfSwap.cs compiles with the Framework csc, alone, into a driver' $built
$kinds = [ordered]@{ 'old' = ''; 'new-good' = 'NEW;GOOD'; 'new-broken' = 'NEW;BROKEN'; 'new-late' = 'NEW;LATE'; 'new-hang' = 'NEW;HANG' }
foreach ($k in $kinds.Keys) {
    $ok = Build (Join-Path $bin "$k.exe") 'winexe' $kinds[$k] @($stubCs, $swapCs)
    Yes "the $k stub compiles around SelfSwap.cs" $ok
    $built = $built -and $ok
}
if (-not $built) {
    try { Remove-Item -LiteralPath $root -Recurse -Force } catch { }
    Finish
}

$hash = @{}
foreach ($k in $kinds.Keys) { $hash[$k] = (Get-FileHash -LiteralPath (Join-Path $bin "$k.exe") -Algorithm SHA256).Hash }
function HashOf([string]$p) {
    if (-not (Test-Path -LiteralPath $p)) { return '' }
    return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
}

# Read while a stub may be writing, so shared both ways.
function Events([string]$dir) {
    $f = Join-Path $dir 'events.txt'
    for ($i = 0; $i -lt 20; $i++) {
        if (-not (Test-Path -LiteralPath $f)) { return @() }
        try {
            $fs = New-Object IO.FileStream($f, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
            try { $t = (New-Object IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() }
            return @($t -split "`r`n" | Where-Object { $_ -ne '' })
        } catch { Start-Sleep -Milliseconds 50 }
    }
    return @()
}
# @() because a function returning one line hands back a string, not an array.
function At($ev, [string]$pattern) {
    $ev = @($ev)
    for ($i = 0; $i -lt $ev.Count; $i++) { if ($ev[$i] -match $pattern) { return $i } }
    return -1
}
function PidOf($ev, [string]$pattern) {
    foreach ($l in $ev) { if ($l -match $pattern) { return [int]$Matches[1] } }
    return 0
}
function Alive([int]$id) {
    if ($id -le 0) { return $false }
    $p = Get-Process -Id $id -ErrorAction SilentlyContinue
    return ($null -ne $p) -and (-not $p.HasExited) -and ($p.ProcessName -eq 'Thornswood')
}
# The condition is run from here, so it sees the caller's variables by
# PowerShell's dynamic scoping. GetNewClosure would cut it off from the
# functions in this file when it runs under -File.
function Wait-For([scriptblock]$cond, [int]$ms) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $ms) {
        if (& $cond) { return $true }
        Start-Sleep -Milliseconds 200
    }
    return [bool](& $cond)
}
$script:started = New-Object System.Collections.Generic.List[int]
function Stop-Stubs {
    $ids = @($script:started)
    foreach ($d in @(Get-ChildItem -LiteralPath $root -Directory -Recurse -ErrorAction SilentlyContinue)) {
        foreach ($l in (Events $d.FullName)) { if ($l -match ' (\d+)(:|$)') { $ids += [int]$Matches[1] } }
    }
    foreach ($id in $ids) {
        if (Alive $id) { try { $p = Get-Process -Id $id; $p.Kill(); [void]$p.WaitForExit(5000) } catch { } }
    }
}

<#
  One update. $kind is the stub waiting at Thornswood.exe.new, or '' for none.
  $before runs once the folder is laid out and before anything starts.
  $during runs once the script is started; whatever it returns is disposed
  once the script has finished, so a lock can be held for the whole run.
#>
function Update-Case {
    param([string]$name, [string]$kind, [int]$checks = 0, [scriptblock]$before = $null,
          [scriptblock]$during = $null, [int]$timeoutMs = 120000)
    $dir = Join-Path (Join-Path $root $name) 'Launcher'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $exe = Join-Path $dir 'Thornswood.exe'
    $neu = $exe + '.new'
    Copy-Item -LiteralPath (Join-Path $bin 'old.exe') -Destination $exe
    if ($kind) { Copy-Item -LiteralPath (Join-Path $bin ($kind + '.exe')) -Destination $neu }
    if ($before) { & $before $dir $exe }
    $closing = Start-Process -FilePath $exe -ArgumentList '--closing', '2000' -PassThru
    $script:started.Add($closing.Id)
    $bat = Join-Path $dir 'thornswood-update-test.cmd'
    $c = '-'
    if ($checks -gt 0) { $c = [string]$checks }
    & $driver $bat $exe $neu $closing.Id $c | Out-Null
    $drove = ($LASTEXITCODE -eq 0)
    $held = $null
    if ($during) { $held = & $during $dir $exe $neu }
    $gone = Wait-For { -not (Test-Path -LiteralPath $bat) } $timeoutMs
    if ($held -is [IDisposable]) { $held.Dispose() }
    return [pscustomobject]@{
        Dir = $dir; Exe = $exe; Neu = $neu; Old = $exe + '.old'; Bad = $exe + '.bad'
        Drove = $drove; Gone = $gone; Closing = $closing.Id
    }
}

try {
    # ---- the script itself --------------------------------------------------
    $tdir = Join-Path $root 'text'
    New-Item -ItemType Directory -Force -Path $tdir | Out-Null
    $texe = Join-Path $tdir 'Thornswood.exe'
    $tbat = Join-Path $tdir 'thornswood-update-4242.cmd'
    & $driver $tbat $texe ($texe + '.new') 4242 '-' '--write-only' | Out-Null
    $text = [IO.File]::ReadAllText($tbat)
    $lines = $text -split "`r`n"
    Yes 'the script starts @echo off, then chcp 65001 so cmd reads the paths as UTF-8' (($lines[0] -eq '@echo off') -and ($lines[1] -eq 'chcp 65001 >nul'))
    Yes 'it still waits on tasklist for the launcher that asked' ($text.Contains('tasklist /fi "PID eq 4242" | find "4242" >nul 2>&1'))
    Yes 'it still pauses with ping, not timeout, because it runs hidden' ($text.Contains('if not errorlevel 1 ( ping 127.0.0.1 -n 2 >nul & goto wait )'))
    Yes 'it still tries the swap for about a minute' ($text.Contains('if %tries% lss 30 ( ping 127.0.0.1 -n 2 >nul & goto swap )'))
    Yes 'it still deletes itself, last' ((($lines | Where-Object { $_ -ne '' }) | Select-Object -Last 1) -eq 'del "%~f0"')
    Yes 'it watches for five minutes by default' ($text.Contains('if %looked% lss 300 goto watch'))
    Yes 'every line ends CRLF' (-not ($text -match "[^`r]`n"))
    $bare = 0; $i = $text.IndexOf($tdir)
    while ($i -ge 0) { if ($i -eq 0 -or $text[$i - 1] -ne '"') { $bare++ }; $i = $text.IndexOf($tdir, $i + 1) }
    Yes 'every path in it is quoted' ($bare -eq 0)
    Yes 'it renames the old exe to .old before the new one goes in' ($text.IndexOf('move /y "' + $texe + '" "' + $texe + '.old"') -ge 0 -and $text.IndexOf('move /y "' + $texe + '" "' + $texe + '.old"') -lt $text.IndexOf('move /y "' + $texe + '.new" "' + $texe + '"'))
    # Issue #497: the new build goes in at the running launcher's own path and
    # nowhere else, so every move and start in the script names that exe, its
    # .new, .old or .bad, and no other file.
    $named = @([regex]::Matches($text, '"([^"]*\.exe[^"]*)"') | ForEach-Object { $_.Groups[1].Value } |
        Where-Object { $_ -ne $texe -and $_ -ne ($texe + '.new') -and $_ -ne ($texe + '.old') -and $_ -ne ($texe + '.bad') })
    Yes ('#497: the script names no exe but the running one and its .new, .old and .bad' + $(if ($named.Count) { ': ' + ($named -join ', ') } else { '' })) ($named.Count -eq 0)
    Yes '#497: and has no second branch for starting another name' (-not $text.Contains(':runnew'))

    # ---- a good new launcher ------------------------------------------------
    $r = Update-Case 'good' 'new-good'
    Yes 'good: the driver wrote and started the script' $r.Drove
    Yes 'good: the script finished and deleted itself' $r.Gone
    $ok = Wait-For { (At (Events $r.Dir) '^new-good settled') -ge 0 } 30000
    $ev = Events $r.Dir
    Yes 'good: the new launcher started and settled' $ok
    Yes 'good: the swap waited until the launcher asking had closed' (((At $ev '^old closed') -ge 0) -and ((At $ev '^old closed') -lt (At $ev '^new-good started')))
    Yes 'good: the new exe is in place' ((HashOf $r.Exe) -eq $hash['new-good'])
    Yes 'good: the kept .old is gone, cleared by the new launcher' (-not (Test-Path -LiteralPath $r.Old))
    Yes 'good: no .bad and no .new left' ((-not (Test-Path -LiteralPath $r.Bad)) -and (-not (Test-Path -LiteralPath $r.Neu)))
    Yes 'good: the old launcher was not started again' ((At $ev '^old started') -lt 0)
    Yes 'good: the new launcher is running afterwards' (Alive (PidOf $ev '^new-good started (\d+)'))
    Yes 'good: it said nothing, because there was nothing to say' ((At $ev '^new-good settled \d+$') -ge 0)

    # ---- a new launcher that exits 1 the moment it starts --------------------
    $r = Update-Case 'broken' 'new-broken'
    Yes 'broken: the script finished and deleted itself' $r.Gone
    $ok = Wait-For { (At (Events $r.Dir) '^old settled') -ge 0 } 30000
    $ev = Events $r.Dir
    Yes 'broken: the new launcher ran and failed' ((At $ev '^new-broken started') -ge 0)
    Yes 'broken: then the old launcher was started again' ($ok -and ((At $ev '^old started') -gt (At $ev '^new-broken started')))
    Yes 'broken: the old exe is back in place' ((HashOf $r.Exe) -eq $hash['old'])
    Yes 'broken: the old launcher is running afterwards' (Alive (PidOf $ev '^old started (\d+)'))
    Yes 'broken: the .old went back to being the exe' (-not (Test-Path -LiteralPath $r.Old))
    Yes 'broken: the launcher that came back named the build that failed' ((At $ev '^old settled \d+: Launcher 2\.0\.0 did not start on this machine, so the launcher you had before was put back\.') -ge 0)
    Yes 'broken: and cleared the .bad it was kept in' (-not (Test-Path -LiteralPath $r.Bad))

    # ---- a new launcher that is up a while and never draws ------------------
    $r = Update-Case 'late' 'new-late'
    Yes 'late: the script finished and deleted itself' $r.Gone
    $ok = Wait-For { (At (Events $r.Dir) '^old settled') -ge 0 } 30000
    $ev = Events $r.Dir
    Yes 'late: nothing was put back while the new launcher was still up' (((At $ev '^new-late gave up') -ge 0) -and ((At $ev '^old started') -gt (At $ev '^new-late gave up')))
    Yes 'late: once it had gone, the old exe is back and running' (((HashOf $r.Exe) -eq $hash['old']) -and (Alive (PidOf $ev '^old started (\d+)')))
    Yes 'late: no .old and no .bad left' ((-not (Test-Path -LiteralPath $r.Old)) -and (-not (Test-Path -LiteralPath $r.Bad)))

    # ---- a new launcher still up when the watch ends -------------------------
    # Three checks instead of three hundred, so this takes seconds.
    $r = Update-Case 'hang' 'new-hang' 3
    $null = Wait-For { (At (Events $r.Dir) '^new-hang started') -ge 0 } 30000
    $ev = Events $r.Dir
    Yes 'hang: the script stopped watching and deleted itself' $r.Gone
    Yes 'hang: the new exe that is still running was left in place' (((HashOf $r.Exe) -eq $hash['new-hang']) -and (Alive (PidOf $ev '^new-hang started (\d+)')))
    Yes 'hang: the old one is kept as .old for that launcher to clear' ((HashOf $r.Old) -eq $hash['old'])
    Yes 'hang: nothing was put back and nothing was started again' (((At $ev '^old started') -lt 0) -and (-not (Test-Path -LiteralPath $r.Bad)))

    # ---- no .new: somebody else finished the job -----------------------------
    $r = Update-Case 'no-new' ''
    Yes 'no new: the script finished and deleted itself' $r.Gone
    $ok = Wait-For { (At (Events $r.Dir) '^old settled') -ge 0 } 30000
    $ev = Events $r.Dir
    Yes 'no new: it started what was there, as it always did' ($ok -and ((HashOf $r.Exe) -eq $hash['old']))
    Yes 'no new: and kept nothing' ((-not (Test-Path -LiteralPath $r.Old)) -and (-not (Test-Path -LiteralPath $r.Bad)))

    # ---- a read-only .old a launcher could not clear -------------------------
    $stale = {
        param($dir, $exe)
        Copy-Item -LiteralPath (Join-Path $bin 'new-broken.exe') -Destination ($exe + '.old')
        Set-ItemProperty -LiteralPath ($exe + '.old') -Name IsReadOnly -Value $true
    }
    $r = Update-Case 'stale' 'new-good' 0 $stale
    Yes 'stale: the script finished and deleted itself' $r.Gone
    $ok = Wait-For { (At (Events $r.Dir) '^new-good settled') -ge 0 } 30000
    Yes 'stale: the update still went in over a read-only leftover .old' ($ok -and ((HashOf $r.Exe) -eq $hash['new-good']))
    Yes 'stale: and the .old is gone' (-not (Test-Path -LiteralPath $r.Old))

    # ---- the new exe held open for a few seconds -----------------------------
    $brief = {
        param($dir, $exe, $neu)
        $fs = [IO.File]::Open($neu, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
        Start-Sleep -Milliseconds 4500
        $fs.Dispose()
        return $null
    }
    $r = Update-Case 'held-briefly' 'new-good' 0 $null $brief
    Yes 'held briefly: the script finished and deleted itself' $r.Gone
    $ok = Wait-For { (At (Events $r.Dir) '^new-good settled') -ge 0 } 30000
    $ev = Events $r.Dir
    Yes 'held briefly: the swap kept trying and the new exe went in' ($ok -and ((HashOf $r.Exe) -eq $hash['new-good']))
    Yes 'held briefly: the .old is gone and the old one never restarted' ((-not (Test-Path -LiteralPath $r.Old)) -and ((At $ev '^old started') -lt 0))

    # ---- the new exe held open for the whole minute of tries -----------------
    $always = {
        param($dir, $exe, $neu)
        return [IO.File]::Open($neu, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
    }
    # About forty seconds on a quiet machine. The ceiling is for a busy one.
    $r = Update-Case 'held' 'new-good' 0 $null $always 240000
    Yes 'held: the script gave up on the swap and deleted itself' $r.Gone
    $ok = Wait-For { (At (Events $r.Dir) '^old settled') -ge 0 } 30000
    $ev = Events $r.Dir
    Yes 'held: the old exe was put back after every try and is in place' ((HashOf $r.Exe) -eq $hash['old'])
    Yes 'held: and it was started, so nobody is left with no launcher' ($ok -and (Alive (PidOf $ev '^old started (\d+)')))
    Yes 'held: the new one is still waiting as .new, nothing kept, nothing bad' (((HashOf $r.Neu) -eq $hash['new-good']) -and (-not (Test-Path -LiteralPath $r.Old)) -and (-not (Test-Path -LiteralPath $r.Bad)))
    Yes 'held: the new one never ran' ((At $ev '^new-good started') -lt 0)

    # ---- a folder name outside ASCII, with spaces ----------------------------
    # Built from char codes so this file stays ASCII: an o with an acute, and a
    # Cyrillic letter, which no Western OEM code page has.
    $odd = 'Th' + [char]0x00F3 + 'rnswood ' + [char]0x0416 + ' test'
    $r = Update-Case ($odd + ' good') 'new-good'
    Yes 'outside ASCII, good: the script finished and deleted itself' $r.Gone
    $ok = Wait-For { (At (Events $r.Dir) '^new-good settled') -ge 0 } 30000
    Yes 'outside ASCII, good: the new exe went in and cleared the .old' ($ok -and ((HashOf $r.Exe) -eq $hash['new-good']) -and (-not (Test-Path -LiteralPath $r.Old)))
    $r = Update-Case ($odd + ' broken') 'new-broken'
    Yes 'outside ASCII, broken: the script finished and deleted itself' $r.Gone
    $ok = Wait-For { (At (Events $r.Dir) '^old settled') -ge 0 } 30000
    $ev = Events $r.Dir
    Yes 'outside ASCII, broken: the old exe is back and running' ($ok -and ((HashOf $r.Exe) -eq $hash['old']) -and (Alive (PidOf $ev '^old started (\d+)')))
    Yes 'outside ASCII, broken: no .old and no .bad left' ((-not (Test-Path -LiteralPath $r.Old)) -and (-not (Test-Path -LiteralPath $r.Bad)))
}
finally {
    Stop-Stubs
    for ($i = 0; $i -lt 10 -and (Test-Path -LiteralPath $root); $i++) {
        try { Remove-Item -LiteralPath $root -Recurse -Force } catch { Start-Sleep -Milliseconds 500 }
    }
}

Finish
