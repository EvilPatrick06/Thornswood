<#
  test-crash-snapshot.ps1

      pwsh -NoProfile -File .\tests\test-crash-snapshot.ps1

  Issue #2626, which replaces #1191's rule. A full crash snapshot was turned
  on by itself for the dev build and staff PCs and described as about 1 GB.
  The one written on Djinn's PC on 17 October was 9.2 GB, and nobody had told
  him. Djinn: off unless the person turns it on, in the launcher, with the
  size said and a folder they choose; after a crash, show it and ask whether
  to keep it.

  The launcher does it with Crash Logger's own switch (Crash Log Write
  Minidump in the install's CrashLogger.ini, launcher\app\CrashDump.cs),
  written before every Play to match Settings, Crash snapshots:

    1. off for everybody until ticked (Config.CrashSnapshots is false);
    2. turning it off stops new snapshots and deletes none already saved;
    3. on: Max Minidumps = 1, and the launcher deletes all but the newest,
       in Crash Logger's folder and the chosen one;
    4. written into that install's file only: a CrashLogger.ini that is a
       hard link to another copy is split first, and nothing goes in the
       registry or asks for administrator;
    5. as the game closes after a crash with it on, the snapshot is moved to
       the chosen folder, the line names it and its size, and the launcher
       asks whether to keep it;
    6. nothing sends a snapshot anywhere (session logs, the report zip).

  HOW. Compiles the shipped CrashDump.cs and Enforce.cs with the build's own
  compiler (Launcher-Csc.ps1), with small stand-ins for Paths, Files,
  Swallow and Config, and drives it against pretend installs in a temp folder
  under C:\ThornswoodTemps&Worktrees\temp (or %TEMP% on another machine).
  Reads Config.cs, Shell.cs, ui.xaml, Diag.cs and Discord.cs as text. Changes
  nothing outside its temp folder.
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Launcher-Csc.ps1')   # the build's compiler and C# version (#498)
$root = Split-Path -Parent $PSScriptRoot
$app = Join-Path $root 'launcher\app'

$script:pass = 0; $script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" -ForegroundColor Red }
}
function Done {
    Write-Host ''
    Write-Host "$script:pass passed, $script:fail failed"
    if ($script:fail -gt 0) { exit 1 } else { exit 0 }
}
function Read([string]$rel) { Get-Content -LiteralPath (Join-Path $root $rel) -Raw }

# ------------------------------------------------------------------ compile
$csc = @(
    "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
    "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $csc) { Write-Host 'SKIP  no .NET Framework 4 csc on this machine, so CrashDump.cs cannot be compiled here'; Done }
$fw = Split-Path -Parent $csc

$driver = @'
using System;
using System.IO;

namespace Thornswood
{
    static class Paths { public static string Game = ""; public static string LiveMyGames = ""; }
    // The same line as Files.cs; the text check below holds the two together.
    static class Files { public static string SkseLogDir { get { return Path.Combine(Paths.LiveMyGames, "SKSE"); } } }
    static class Swallow { public static void Note(string where, Exception e) { Console.WriteLine("SWALLOW=" + where + ": " + e.Message); } }
    class Config { public bool CrashSnapshots; public string CrashSnapshotFolder = ""; }

    static class CrashSnapshotTest
    {
        static string Flat(string s) { return s == null ? "(none)" : s.Replace("\r", " ").Replace("\n", " "); }

        // apply   <game> <mygames> <on 0|1> <folder or ->
        // after   <game> <mygames> <on 0|1> <folder or -> <since, local ticks>
        public static int Main(string[] a)
        {
            Paths.Game = a[1];
            Paths.LiveMyGames = a[2];
            var cfg = new Config();
            cfg.CrashSnapshots = a[3] == "1";
            cfg.CrashSnapshotFolder = a[4] == "-" ? "" : a[4];
            if (a[0] == "apply")
            {
                Console.WriteLine("WANTED=" + CrashDump.Wanted(cfg));
                Console.WriteLine("SAID=" + Flat(CrashDump.Apply(cfg)));
                Console.WriteLine("ENFORCE=" + Flat(string.Join(" | ", Enforce.Said.ToArray())));
                return 0;
            }
            if (a[0] == "after")
            {
                DateTime since = new DateTime(long.Parse(a[5]), DateTimeKind.Local);
                string snapshot;
                Console.WriteLine("SAID=" + Flat(CrashDump.AfterSession(since, CrashDump.Wanted(cfg), CrashDump.KeptIn(cfg), out snapshot)));
                Console.WriteLine("SNAP=" + (snapshot ?? "(none)"));
                return 0;
            }
            return 2;
        }
    }
}
'@

$tempBase = 'C:\ThornswoodTemps&Worktrees\temp'
if (-not (Test-Path -LiteralPath $tempBase)) { $tempBase = [IO.Path]::GetTempPath() }
$tmp = Join-Path $tempBase ('test-crash-snapshot-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

try {
    $driverFile = Join-Path $tmp 'CrashSnapshotTest.cs'
    [IO.File]::WriteAllText($driverFile, $driver, (New-Object Text.UTF8Encoding($false)))
    $exe = Join-Path $tmp 'crash-snapshot-test.exe'
    # /noconfig, as Build-Launcher.ps1 does: csc.rsp adds its own framework
    # copies and a machine with the reference assemblies stops on CS1703.
    $cscArgs = @('/noconfig', '/nologo', '/target:exe', '/warn:4', "/out:$exe",
                 "/reference:$(Join-Path $fw 'System.dll')", "/reference:$(Join-Path $fw 'System.Core.dll')",
                 (Join-Path $app 'CrashDump.cs'), (Join-Path $app 'Enforce.cs'), $driverFile)
    $out = & $LauncherCsc @cscArgs 2>&1
    $built = ($LASTEXITCODE -eq 0) -and (Test-Path -LiteralPath $exe)
    if (-not $built) { $out | ForEach-Object { Write-Host "      $_" } }
    Yes 'CrashDump.cs and Enforce.cs compile with the launcher''s .NET Framework 4 csc (C# 5)' $built
    if (-not $built) { Done }

    function Run([string[]]$argv) {
        $lines = & $exe @argv
        $r = @{}
        foreach ($l in $lines) { $i = $l.IndexOf('='); if ($i -gt 0) { $r[$l.Substring(0, $i)] = $l.Substring($i + 1) } }
        return $r
    }
    # A pretend install: Game\Data\SKSE\Plugins with Crash Logger in it, and
    # Profile\MyGames\SKSE for the logs, as C:\Thornswood lays them out.
    function NewInstall([string]$name, [bool]$withIni = $true, [bool]$withDll = $true) {
        $r = Join-Path $tmp $name
        $game = Join-Path $r 'Game'
        $my = Join-Path $r 'Profile\MyGames'
        $plugins = Join-Path $game 'Data\SKSE\Plugins'
        New-Item -ItemType Directory -Force -Path $plugins, (Join-Path $my 'SKSE') | Out-Null
        if ($withDll) { [IO.File]::WriteAllBytes((Join-Path $plugins 'CrashLogger.dll'), [byte[]](1, 2, 3)) }
        if ($withIni) { [IO.File]::WriteAllText((Join-Path $plugins 'CrashLogger.ini'), $script:shippedIni, (New-Object Text.UTF8Encoding($true))) }
        return @{ Game = $game; My = $my; Ini = (Join-Path $plugins 'CrashLogger.ini'); Skse = (Join-Path $my 'SKSE') }
    }

    # The lines of Crash Logger 1.24's own CrashLogger.ini that matter, as
    # C:\Thornswood\Game and C:\Thornswood-DevBuild\Game had them on 29 Sep
    # (#1191), with a BOM as it ships.
    $script:shippedIni = "; Crash Log Settings`r`n`r`n[Debug]`r`n`r`n; Crashlog output directory. If blank, defaults to `"Documents\my games\Skyrim Special Edition\SKSE\`"`r`nCrashlog Directory = `r`n`r`n;Maximum number of crash logs to keep. Default: 20`r`nMax Crash Logs = 20`r`n`r`n;Maximum number of minidump files to keep. Minidumps are very large, so a low limit is recommended. Default: 1`r`n;Set to 0 to disable minidump cleanup.`r`nMax Minidumps = 1`r`n`r`nAuto Open Crash Log = true`r`n`r`n;Also create minidump file (.dmp) for crash log WinDbg analysis. Default: false`r`nCrash Log Write Minidump = false`r`n`r`n;Also create minidump file (.dmp) for thread dump WinDbg analysis. Default: false`r`nThread Dump Write Minidump = false`r`n`r`nLog Level = 2`r`n"


    function Apply($inst, [bool]$on, [string]$folder = '-') {
        Run @('apply', $inst.Game, $inst.My, $(if ($on) { '1' } else { '0' }), $folder)
    }
    function After($inst, [bool]$on, [string]$folder, [datetime]$since) {
        Run @('after', $inst.Game, $inst.My, $(if ($on) { '1' } else { '0' }), $folder, [string]$since.Ticks)
    }
    function IniText($inst) { if (Test-Path -LiteralPath $inst.Ini) { Get-Content -LiteralPath $inst.Ini -Raw } else { '' } }
    function Live([string]$text, [string]$key) {
        $m = [regex]::Matches($text, '(?m)^\s*' + [regex]::Escape($key) + '\s*=\s*(.*?)\s*$')
        return ,@($m | ForEach-Object { $_.Groups[1].Value })
    }
    function Dump([string]$dir, [string]$name, [int]$minutesAgo) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $p = Join-Path $dir $name
        [IO.File]::WriteAllBytes($p, [byte[]](0x4D, 0x44, 0x4D, 0x50))
        (Get-Item -LiteralPath $p).LastWriteTime = (Get-Date).AddMinutes(-$minutesAgo)
        return $p
    }

    # ------------------------------------------- 1. off until ticked
    $cfgText = Read 'launcher\app\Config.cs'
    Yes 'the setting is off for everybody until ticked (Config.CrashSnapshots = false)' ($cfgText -match '\[DataMember\] public bool CrashSnapshots = false;')
    $inst = NewInstall 'off'
    $r = Apply $inst $false
    Yes 'off: Crash Log Write Minidump = false, and the launcher says nothing (already Crash Logger''s default)' ((Live (IniText $inst) 'Crash Log Write Minidump')[0] -eq 'false' -and $r['WANTED'] -eq 'False' -and $r['SAID'] -eq '(none)')
    $m = NewInstall 'noini-off' $false $true
    $null = Apply $m $false
    Yes 'off and no ini: none is made (Crash Logger''s default is off)' (-not (Test-Path -LiteralPath $m.Ini))

    # ------------------------------------------- 2. turning it off deletes nothing
    $inst = NewInstall 'turnedoff'
    [IO.File]::WriteAllText($inst.Ini, ($script:shippedIni -replace 'Crash Log Write Minidump = false', 'Crash Log Write Minidump = true' -replace 'Thread Dump Write Minidump = false', 'Thread Dump Write Minidump = true'))
    $d = Dump $inst.Skse 'crash-2026-10-17-13-13-14.dmp' 5
    $r = Apply $inst $false
    $t = IniText $inst
    Yes 'turned off: Crash Log Write Minidump back to false' ((Live $t 'Crash Log Write Minidump')[0] -eq 'false')
    Yes 'turned off: the hang snapshot switch is held off too' ((Live $t 'Thread Dump Write Minidump')[0] -eq 'false')
    Yes 'turned off: a snapshot already saved is left where it is' (Test-Path -LiteralPath $d)
    Yes 'turned off: the log says so, and where they are' ($r['SAID'] -match 'Crash snapshots are off\. Any already saved are left where they are' -and $r['SAID'] -match [regex]::Escape($inst.Skse))

    # ------------------------------------------- 3. on: only the newest kept
    $inst = NewInstall 'on'
    $chosen = Join-Path $tmp 'chosen-on'
    $r = Apply $inst $true $chosen
    $t = IniText $inst
    Yes 'on: Crash Log Write Minidump = true and Max Minidumps = 1' ((Live $t 'Crash Log Write Minidump')[0] -eq 'true' -and (Live $t 'Max Minidumps')[0] -eq '1' -and $r['WANTED'] -eq 'True')
    Yes 'on: the log says where they go, how big they get, and that they stay on this PC' ($r['SAID'] -match [regex]::Escape($chosen) -and $r['SAID'] -match '9 GB or more' -and $r['SAID'] -match 'stays on this PC')
    $again = Apply $inst $true $chosen
    Yes 'on: a second Play changes nothing and says nothing' ($again['SAID'] -eq '(none)' -and (IniText $inst) -eq $t)
    Yes 'on: the rest of Crash Logger''s file is left alone' ((Live $t 'Max Crash Logs')[0] -eq '20' -and (Live $t 'Auto Open Crash Log')[0] -eq 'true' -and (Live $t 'Thread Dump Write Minidump')[0] -eq 'false' -and (Live $t 'Log Level')[0] -eq '2')
    $old = Dump $inst.Skse 'crash-2026-09-20-10-00-00.dmp' 600
    $mid = Dump $chosen 'crash-2026-09-25-10-00-00.dmp' 300
    $new = Dump $chosen 'crash-2026-09-29-10-00-00.dmp' 10
    [IO.File]::WriteAllText((Join-Path $inst.Skse 'crash-2026-09-20-10-00-00.log'), 'log')
    $r = Apply $inst $true $chosen
    Yes 'on: the older snapshots are deleted in both folders, the newest kept' (-not (Test-Path -LiteralPath $old) -and -not (Test-Path -LiteralPath $mid) -and (Test-Path -LiteralPath $new))
    Yes 'on: and the log says so' ($r['SAID'] -match 'Deleted 2 older crash snapshots\. Only the newest is kept\.')
    Yes 'crash logs are never touched' (Test-Path -LiteralPath (Join-Path $inst.Skse 'crash-2026-09-20-10-00-00.log'))

    # ------------------------------------------- 4. only that install's file
    $vortex = Join-Path $tmp 'VortexCopy.ini'
    [IO.File]::WriteAllText($vortex, $script:shippedIni)
    $h = NewInstall 'linked' $false $true
    New-Item -ItemType HardLink -Path $h.Ini -Target $vortex | Out-Null
    $r = Apply $h $true
    Yes 'a CrashLogger.ini that is a hard link to another copy: the other copy is not written' ((Get-Content -LiteralPath $vortex -Raw) -eq $script:shippedIni)
    Yes 'and this install''s own file is' ((Live (IniText $h) 'Crash Log Write Minidump')[0] -eq 'true')
    Yes 'and the log says the file was split' ($r['ENFORCE'] -match 'It has its own copy now')
    $m = NewInstall 'noini' $false $true
    $null = Apply $m $true
    $t = IniText $m
    Yes 'on, Crash Logger there but its ini missing: made with both lines under [Debug]' ($t -match '(?s)\[Debug\].*Crash Log Write Minidump = true' -and (Live $t 'Max Minidumps')[0] -eq '1')
    $m = NewInstall 'nocrashlogger' $false $false
    $null = Apply $m $true
    Yes 'no Crash Logger at all: nothing is made' (-not (Test-Path -LiteralPath $m.Ini))

    $src = Read 'launcher\app\CrashDump.cs'
    $code = [regex]::Replace($src, '(?m)^\s*///?.*$', '')
    Yes 'nothing in the registry and nothing that asks for administrator (no LocalDumps, no runas)' ($code -notmatch 'Registry|LocalDumps|runas|HKEY|HKLM|HKCU')

    # ------------------------------------------- 5. as the game closes
    $s = NewInstall 'session'
    $chosen = Join-Path $tmp 'chosen-session'
    $since = (Get-Date).AddMinutes(-30)
    [IO.File]::WriteAllText((Join-Path $s.Skse 'crash-2026-09-28-09-00-00.log'), 'yesterday')
    (Get-Item -LiteralPath (Join-Path $s.Skse 'crash-2026-09-28-09-00-00.log')).LastWriteTime = (Get-Date).AddMinutes(-1500)
    $r = After $s $true $chosen $since
    Yes 'a session that did not crash: no crash line (yesterday''s log does not count)' ($r['SAID'] -eq '(none)' -and $r['SNAP'] -eq '(none)')
    $older = Dump $chosen 'crash-2026-09-28-09-00-00.dmp' 1500
    [IO.File]::WriteAllText((Join-Path $s.Skse 'crash-2026-10-17-13-13-14.log'), 'today')
    $dmp = Dump $s.Skse 'crash-2026-10-17-13-13-14.dmp' 1
    $r = After $s $true $chosen $since
    $moved = Join-Path $chosen 'crash-2026-10-17-13-13-14.dmp'
    Yes 'crashed, on: the line names the crash log and where it is' ($r['SAID'] -match 'The game crashed\. Its crash log is crash-2026-10-17-13-13-14\.log in ' -and $r['SAID'] -match [regex]::Escape($s.Skse))
    Yes 'crashed, on: the snapshot is moved to the chosen folder and named with its size' ((Test-Path -LiteralPath $moved) -and -not (Test-Path -LiteralPath $dmp) -and $r['SNAP'] -eq $moved -and $r['SAID'] -match [regex]::Escape($moved) -and $r['SAID'] -match ', \d+ (MB|GB)\.')
    Yes 'crashed, on: and the line says it holds what was in memory and stays on this PC' ($r['SAID'] -match "It holds what was in the game's memory, so it stays on this PC and nothing sends it anywhere")
    Yes 'crashed, on: the older snapshot in the chosen folder is deleted, the new one kept' (-not (Test-Path -LiteralPath $older) -and (Test-Path -LiteralPath $moved))
    $s2 = NewInstall 'session-off'
    [IO.File]::WriteAllText((Join-Path $s2.Skse 'crash-2026-10-17-14-00-00.log'), 'today')
    $stray = Dump $s2.Skse 'crash-2026-10-17-14-00-00.dmp' 1
    $r = After $s2 $false '-' $since
    Yes 'crashed, off: the crash log line, no snapshot named, and nothing moved or deleted' ($r['SAID'] -match 'The game crashed\.' -and $r['SAID'] -notmatch 'crash snapshot' -and $r['SNAP'] -eq '(none)' -and (Test-Path -LiteralPath $stray))

    # ------------------------------------------- 6. the launcher around it
    $shell = (Get-ChildItem -LiteralPath $app -Filter 'Shell*.cs' | Sort-Object Name | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
    $play = [regex]::Match($shell, '(?s)static void Play\(\)\s*\{(.*?)\n        \}\r?\n')
    $body = $play.Groups[1].Value
    $iEnf = $body.IndexOf('Enforce.Apply()'); $iDump = $body.IndexOf('CrashDump.Apply(cfg)'); $iSaid = $body.IndexOf('foreach (string note in Enforce.Said)'); $iNote = $body.IndexOf('Keep.LeaveNote')
    Yes 'Play writes it every time, after the other held settings and before the game starts' ($play.Success -and $iEnf -ge 0 -and $iDump -gt $iEnf -and $iSaid -gt $iDump -and $iNote -gt $iDump)
    Yes 'the game closing logs the crash line and asks about a saved snapshot' ($shell -match 'CrashDump\.AfterSession\(playStartedAt, CrashDump\.Wanted\(cfg\), CrashDump\.KeptIn\(cfg\), out snapshot\)' -and $shell -match 'if \(snapshot != null\) AskKeepSnapshot\(snapshot\);')
    Yes 'asking: Yes keeps it, No deletes it' ($shell -match 'MessageBoxButton\.YesNo' -and $shell -match 'static void AskKeepSnapshot' -and $shell -match 'File\.Delete\(snapshot\);')
    Yes 'Wanted(cfg) is the person''s own setting and nothing else' ($src -match 'return cfg != null && cfg\.CrashSnapshots;' -and $src -notmatch 'Discord\.' -and $src -notmatch 'IsDev')
    $ui = Read 'launcher\ui.xaml'
    Yes 'Settings has the box, the size said beside it, and a folder button' ($ui -match 'x:Name="ChkCrashSnapshots"' -and $ui -match 'One can be 9 GB or more' -and $ui -match 'x:Name="BtnCrashFolder"' -and $ui -match 'x:Name="TxtCrashFolder"')
    Yes 'the box and the folder are saved to the config when changed' ($shell -match 'cfg\.CrashSnapshots = chkCrashSnapshots\.IsChecked == true;' -and $shell -match 'cfg\.CrashSnapshotFolder = chosen;')
    $files = Read 'launcher\app\Files.cs'
    Yes 'Crash Logger''s folder is the crash log folder (the stand-in above says what Files.cs says)' ($files -match 'public static string SkseLogDir \{ get \{ return Path\.Combine\(Paths\.LiveMyGames, "SKSE"\); \} \}' -and $src -match 'return Files\.SkseLogDir;')
    $discord = Read 'launcher\app\Discord.cs'
    Yes 'the session logs never carry a snapshot (only crash-*.log)' ($discord -notmatch '\.dmp' -and $discord -match 'Directory\.GetFiles\(dir, "crash-\*\.log"\)')
    $diag = Read 'launcher\app\Diag.cs'
    $report = [regex]::Match($diag, '(?s)Entry crash = Files\.NewestCrash\(\);\s*if \(crash != null\) Grab\(work, crash\.FullPath\);')
    Yes 'the report zip takes the crash log, not the snapshot' ($report.Success -and $diag -notmatch '\.dmp' -and $files -match '"crash-\*\.log"')
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
Done
