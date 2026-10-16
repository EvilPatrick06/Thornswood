<#
  test-crash-snapshot.ps1

      pwsh -NoProfile -File .\tests\test-crash-snapshot.ps1

  Issue #1191. A game crash left only Crash Logger's text log, on every
  install, so the rare crashes (#407, #408) could not be traced. Patrick,
  29 Sep: keep a full crash snapshot on the dev build and on staff PCs only,
  about 1 GB, only the newest kept.

  The launcher does it with Crash Logger's own switch (Crash Log Write
  Minidump in the install's CrashLogger.ini, launcher\app\CrashDump.cs),
  written before every Play:

    1. on for the dev build, and for a linked Discord account the site says
       holds a staff role (the dev flag of /api/play/join, dev-allowed.txt);
    2. off for everybody else, and off again with every snapshot deleted
       at the first Play after an install stops being either;
    3. Max Minidumps = 1, and the launcher deletes all but the newest;
    4. written into that install's file only: a CrashLogger.ini that is a
       hard link to another copy is split first, and nothing goes in the
       registry or asks for administrator;
    5. as the game closes after a crash, the log line names the crash log
       and the snapshot beside it, says it holds what was in memory and
       that it stays on the PC;
    6. nothing sends a snapshot anywhere (session logs, the report zip).

  HOW. Compiles the shipped CrashDump.cs and Enforce.cs with the same
  .NET Framework 4 csc the launcher is built with (so it is a C# 5 check
  too), with small stand-ins for Paths, Files, Swallow, Config and Discord,
  and drives it against pretend installs in a temp folder under
  C:\ThornswoodTemps&Worktrees\temp (or %TEMP% on another machine). Reads
  Shell.cs, Diag.cs, Discord.cs and the site as text. Changes nothing outside
  its temp folder.
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
    class Config
    {
        public string Channel = "";
        public bool IsDev { get { return string.Equals(Channel, "dev", StringComparison.OrdinalIgnoreCase); } }
    }
    static class Discord { public static bool Linked; public static bool DevAllowed; }

    static class CrashSnapshotTest
    {
        static string Flat(string s) { return s == null ? "(none)" : s.Replace("\r", " ").Replace("\n", " "); }

        // apply   <game> <mygames> <channel> <linked 0|1> <staff 0|1>
        // after   <game> <mygames> <since, local ticks> <want 0|1>
        public static int Main(string[] a)
        {
            Paths.Game = a[1];
            Paths.LiveMyGames = a[2];
            if (a[0] == "apply")
            {
                var cfg = new Config();
                cfg.Channel = a[3] == "-" ? "" : a[3];
                Discord.Linked = a[4] == "1";
                Discord.DevAllowed = a[5] == "1";
                Console.WriteLine("WANTED=" + CrashDump.Wanted(cfg));
                Console.WriteLine("SAID=" + Flat(CrashDump.Apply(cfg)));
                Console.WriteLine("ENFORCE=" + Flat(string.Join(" | ", Enforce.Said.ToArray())));
                return 0;
            }
            if (a[0] == "after")
            {
                DateTime since = new DateTime(long.Parse(a[3]), DateTimeKind.Local);
                Console.WriteLine("SAID=" + Flat(CrashDump.AfterSession(since, a[4] == "1")));
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
    function Apply($inst, [string]$channel, [bool]$linked, [bool]$staff) {
        Run @('apply', $inst.Game, $inst.My, $(if ($channel) { $channel } else { '-' }), $(if ($linked) { '1' } else { '0' }), $(if ($staff) { '1' } else { '0' }))
    }
    function IniText($inst) { if (Test-Path -LiteralPath $inst.Ini) { Get-Content -LiteralPath $inst.Ini -Raw } else { '' } }
    function Live([string]$text, [string]$key) {
        $m = [regex]::Matches($text, '(?m)^\s*' + [regex]::Escape($key) + '\s*=\s*(.*?)\s*$')
        return ,@($m | ForEach-Object { $_.Groups[1].Value })
    }
    function Dump($inst, [string]$name, [int]$minutesAgo) {
        $p = Join-Path $inst.Skse $name
        [IO.File]::WriteAllBytes($p, [byte[]](0x4D, 0x44, 0x4D, 0x50))
        (Get-Item -LiteralPath $p).LastWriteTime = (Get-Date).AddMinutes(-$minutesAgo)
        return $p
    }

    # The lines of Crash Logger 1.24's own CrashLogger.ini that matter, as
    # C:\Thornswood\Game and C:\Thornswood-DevBuild\Game had them on 29 Sep
    # (#1191), with a BOM as it ships.
    $script:shippedIni = "; Crash Log Settings`r`n`r`n[Debug]`r`n`r`n; Crashlog output directory. If blank, defaults to `"Documents\my games\Skyrim Special Edition\SKSE\`"`r`nCrashlog Directory = `r`n`r`n;Maximum number of crash logs to keep. Default: 20`r`nMax Crash Logs = 20`r`n`r`n;Maximum number of minidump files to keep. Minidumps are very large, so a low limit is recommended. Default: 1`r`n;Set to 0 to disable minidump cleanup.`r`nMax Minidumps = 1`r`n`r`nAuto Open Crash Log = true`r`n`r`n;Also create minidump file (.dmp) for crash log WinDbg analysis. Default: false`r`nCrash Log Write Minidump = false`r`n`r`n;Also create minidump file (.dmp) for thread dump WinDbg analysis. Default: false`r`nThread Dump Write Minidump = false`r`n`r`nLog Level = 2`r`n"

    # ------------------------------------------- 1. who gets one, who does not
    $cases = @(
        @{ Name = 'main build, no Discord linked';                Ch = '';    L = $false; S = $false; Want = $false },
        @{ Name = 'main build, linked, no staff role';            Ch = '';    L = $true;  S = $false; Want = $false },
        @{ Name = 'main build, a stale staff note, not linked';   Ch = '';    L = $false; S = $true;  Want = $false },
        @{ Name = 'main build, linked, staff role';               Ch = '';    L = $true;  S = $true;  Want = $true },
        @{ Name = 'dev build, not staff';                          Ch = 'dev'; L = $true;  S = $false; Want = $true },
        @{ Name = 'dev build, not linked';                         Ch = 'dev'; L = $false; S = $false; Want = $true }
    )
    $n = 0
    foreach ($c in $cases) {
        $n++
        $inst = NewInstall ('who' + $n)
        $r = Apply $inst $c.Ch $c.L $c.S
        $t = IniText $inst
        $w = Live $t 'Crash Log Write Minidump'
        $expect = $(if ($c.Want) { 'true' } else { 'false' })
        Yes "$($c.Name): Crash Log Write Minidump = $expect" ($w.Count -eq 1 -and $w[0] -eq $expect -and $r['WANTED'] -eq [string]$c.Want)
        if (-not $c.Want) {
            Yes "$($c.Name): the launcher says nothing, the file is at Crash Logger's default" ($r['SAID'] -eq '(none)')
        }
        else {
            $k = Live $t 'Max Minidumps'
            Yes "$($c.Name): only the newest kept (Max Minidumps = 1)" ($k.Count -eq 1 -and $k[0] -eq '1')
            $why = $(if ($c.Ch -eq 'dev') { 'it is the dev build' } else { 'your Discord account holds a staff role' })
            Yes "$($c.Name): the log line says why ($why), where, and that it stays on this PC" ($r['SAID'] -match [regex]::Escape($why) -and $r['SAID'] -match [regex]::Escape($inst.Skse) -and $r['SAID'] -match "what was in the game's memory" -and $r['SAID'] -match 'stays on this PC and nothing sends it anywhere')
            $again = Apply $inst $c.Ch $c.L $c.S
            Yes "$($c.Name): a second Play changes nothing and says nothing" ($again['SAID'] -eq '(none)' -and (IniText $inst) -eq $t)
            Yes "$($c.Name): the rest of Crash Logger's file is left alone" ((Live $t 'Max Crash Logs')[0] -eq '20' -and (Live $t 'Auto Open Crash Log')[0] -eq 'true' -and (Live $t 'Thread Dump Write Minidump')[0] -eq 'false' -and (Live $t 'Log Level')[0] -eq '2' -and $t -match ';Also create minidump file \(\.dmp\) for crash log WinDbg analysis')
        }
    }

    # ------------------------------------------- 2. only the newest kept
    $inst = NewInstall 'newest'
    $old = Dump $inst 'crash-2026-09-20-10-00-00.dmp' 600
    $mid = Dump $inst 'crash-2026-09-25-10-00-00.dmp' 300
    $new = Dump $inst 'crash-2026-09-29-10-00-00.dmp' 10
    [IO.File]::WriteAllText((Join-Path $inst.Skse 'crash-2026-09-20-10-00-00.log'), 'log')
    $r = Apply $inst '' $true $true
    Yes 'staff: the two older snapshots are deleted before Play, the newest is kept' (-not (Test-Path -LiteralPath $old) -and -not (Test-Path -LiteralPath $mid) -and (Test-Path -LiteralPath $new))
    Yes 'staff: and the log says so' ($r['SAID'] -match 'Deleted 2 older crash snapshots\. Only the newest is kept\.')
    Yes 'staff: crash logs are never touched' (Test-Path -LiteralPath (Join-Path $inst.Skse 'crash-2026-09-20-10-00-00.log'))

    # ------------------------------------------- 3. staff role taken away
    $thread = Dump $inst 'threaddump-2026-09-28-10-00-00.dmp' 60
    $t0 = (IniText $inst) -replace '(?m)^Thread Dump Write Minidump = false', 'Thread Dump Write Minidump = true'
    [IO.File]::WriteAllText($inst.Ini, $t0)
    $r = Apply $inst '' $true $false
    $t = IniText $inst
    Yes 'no longer staff: Crash Log Write Minidump back to false at the next Play' ((Live $t 'Crash Log Write Minidump')[0] -eq 'false')
    Yes 'no longer staff: the hang snapshot switch is held off too' ((Live $t 'Thread Dump Write Minidump')[0] -eq 'false')
    Yes 'no longer staff: every snapshot it left is deleted, the hang one included' (@(Get-ChildItem -LiteralPath $inst.Skse -Filter '*.dmp').Count -eq 0)
    Yes 'no longer staff: the log says it is off and what was deleted' ($r['SAID'] -match 'no longer keeps a crash snapshot' -and $r['SAID'] -match 'Deleted 2 crash snapshots from')
    Yes 'no longer staff: crash logs are never touched' (Test-Path -LiteralPath (Join-Path $inst.Skse 'crash-2026-09-20-10-00-00.log'))
    $r = Apply $inst '' $false $true
    Yes 'unlinked with a staff note left on disk: still off' ((Live (IniText $inst) 'Crash Log Write Minidump')[0] -eq 'false' -and $r['WANTED'] -eq 'False')

    # Somebody turned it on by hand on an ordinary install.
    $inst = NewInstall 'byhand'
    [IO.File]::WriteAllText($inst.Ini, ($script:shippedIni -replace 'Crash Log Write Minidump = false', 'Crash Log Write Minidump = true'))
    $d = Dump $inst 'crash-2026-09-29-11-00-00.dmp' 5
    $r = Apply $inst '' $true $false
    Yes 'an ordinary install that turned it on by hand: off again, and its snapshot deleted' ((Live (IniText $inst) 'Crash Log Write Minidump')[0] -eq 'false' -and -not (Test-Path -LiteralPath $d))

    # ------------------------------------------- 4. only that install's file
    $a = NewInstall 'devinstall'
    $b = NewInstall 'maininstall'
    $null = Apply $a 'dev' $true $false
    $null = Apply $b '' $true $false
    Yes 'dev install and main install on one PC: on in the dev install''s file, off in the main one' ((Live (IniText $a) 'Crash Log Write Minidump')[0] -eq 'true' -and (Live (IniText $b) 'Crash Log Write Minidump')[0] -eq 'false')

    $vortex = Join-Path $tmp 'VortexCopy.ini'
    [IO.File]::WriteAllText($vortex, $script:shippedIni)
    $h = NewInstall 'linked' $false $true
    New-Item -ItemType HardLink -Path $h.Ini -Target $vortex | Out-Null
    $r = Apply $h '' $true $true
    Yes 'a CrashLogger.ini that is a hard link to another copy: the other copy is not written' ((Get-Content -LiteralPath $vortex -Raw) -eq $script:shippedIni)
    Yes 'and this install''s own file is' ((Live (IniText $h) 'Crash Log Write Minidump')[0] -eq 'true')
    Yes 'and the log says the file was split' ($r['ENFORCE'] -match 'It has its own copy now')

    $m = NewInstall 'noini' $false $true
    $null = Apply $m 'dev' $false $false
    $t = IniText $m
    Yes 'Crash Logger there but its ini missing: made with both lines under [Debug]' ($t -match '(?s)\[Debug\].*Crash Log Write Minidump = true' -and (Live $t 'Max Minidumps')[0] -eq '1')
    $m = NewInstall 'nocrashlogger' $false $false
    $null = Apply $m 'dev' $false $false
    Yes 'no Crash Logger at all: nothing is made' (-not (Test-Path -LiteralPath $m.Ini))
    $m = NewInstall 'noini-main' $false $true
    $null = Apply $m '' $true $false
    Yes 'not kept and no ini: none is made (Crash Logger''s default is off)' (-not (Test-Path -LiteralPath $m.Ini))

    $src = Read 'launcher\app\CrashDump.cs'
    $code = [regex]::Replace($src, '(?m)^\s*///?.*$', '')
    Yes 'nothing in the registry and nothing that asks for administrator (no LocalDumps, no runas)' ($code -notmatch 'Registry|LocalDumps|runas|HKEY|HKLM|HKCU')

    # ------------------------------------------- 5. the line as the game closes
    $s = NewInstall 'session'
    $since = (Get-Date).AddMinutes(-30)
    $older = Dump $s 'crash-2026-09-28-09-00-00.dmp' 1500
    [IO.File]::WriteAllText((Join-Path $s.Skse 'crash-2026-09-28-09-00-00.log'), 'yesterday')
    (Get-Item -LiteralPath (Join-Path $s.Skse 'crash-2026-09-28-09-00-00.log')).LastWriteTime = (Get-Date).AddMinutes(-1500)
    $r = Run @('after', $s.Game, $s.My, [string]$since.Ticks, '1')
    Yes 'a session that did not crash: no crash line (yesterday''s log does not count)' ($r['SAID'] -eq '(none)')
    $log = Join-Path $s.Skse 'crash-2026-09-29-12-00-00.log'
    [IO.File]::WriteAllText($log, 'today')
    $dmp = Dump $s 'crash-2026-09-29-12-00-00.dmp' 1
    $r = Run @('after', $s.Game, $s.My, [string]$since.Ticks, '1')
    Yes 'crashed: the line names the crash log and where it is' ($r['SAID'] -match 'The game crashed\. Its crash log is crash-2026-09-29-12-00-00\.log in ' -and $r['SAID'] -match [regex]::Escape($s.Skse))
    Yes 'crashed: and points to the snapshot beside it' ($r['SAID'] -match 'The full crash snapshot is beside it: crash-2026-09-29-12-00-00\.dmp')
    Yes 'crashed: and says it holds what was in memory and stays on this PC' ($r['SAID'] -match "It holds what was in the game's memory, so it stays on this PC and nothing sends it anywhere")
    Yes 'crashed: the older snapshot is deleted as the game closes, the new one kept' (-not (Test-Path -LiteralPath $older) -and (Test-Path -LiteralPath $dmp))
    Remove-Item -LiteralPath $dmp
    $r = Run @('after', $s.Game, $s.My, [string]$since.Ticks, '0')
    Yes 'crashed on an ordinary install: the crash log line, and no snapshot named' ($r['SAID'] -match 'The game crashed\.' -and $r['SAID'] -notmatch 'full crash snapshot' -and $r['SAID'] -notmatch '\.dmp')

    # ------------------------------------------- 6. the launcher around it
    $shell = (Get-ChildItem -LiteralPath $app -Filter 'Shell*.cs' | Sort-Object Name | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
    $play = [regex]::Match($shell, '(?s)static void Play\(\)\s*\{(.*?)\n        \}\r?\n')
    $body = $play.Groups[1].Value
    $iEnf = $body.IndexOf('Enforce.Apply()'); $iDump = $body.IndexOf('CrashDump.Apply(cfg)'); $iSaid = $body.IndexOf('foreach (string note in Enforce.Said)'); $iNote = $body.IndexOf('Keep.LeaveNote')
    Yes 'Play writes it every time, after the other held settings and before the game starts' ($play.Success -and $iEnf -ge 0 -and $iDump -gt $iEnf -and $iSaid -gt $iDump -and $iNote -gt $iDump)
    Yes 'the game closing logs the crash line, with the snapshot for kept installs' ($shell -match 'CrashDump\.AfterSession\(playStartedAt, CrashDump\.Wanted\(cfg\)\)')
    Yes 'Wanted(cfg) is the dev build, or a linked account the site said is staff' ($src -match 'return Wanted\(cfg != null && cfg\.IsDev, Discord\.Linked, Discord\.DevAllowed\);' -and $src -match 'return devBuild \|\| \(linked && staff\);')
    $files = Read 'launcher\app\Files.cs'
    Yes 'the snapshot folder is the crash log folder (the stand-in above says what Files.cs says)' ($files -match 'public static string SkseLogDir \{ get \{ return Path\.Combine\(Paths\.LiveMyGames, "SKSE"\); \} \}' -and $src -match 'return Files\.SkseLogDir;')
    $discord = Read 'launcher\app\Discord.cs'
    Yes 'staff is the site''s dev answer, written down at every check in' ($discord -match 'st\.Dev\s*= Field\(reply, "dev"\) == "true";' -and $discord -match 'NoteDev\(st\.Dev\)' -and $discord -match '"dev-allowed\.txt"')
    $site = Read 'site\server.js'
    Yes 'and the site''s dev answer is the staff roles' ($site -match "cfg\.access\.dev = \['Owner', 'Dev', 'Gamemaster', 'Moderator', 'Loremaster'\];")
    Yes 'the session logs never carry a snapshot (only crash-*.log)' ($discord -notmatch '\.dmp' -and $discord -match 'Directory\.GetFiles\(dir, "crash-\*\.log"\)')
    $diag = Read 'launcher\app\Diag.cs'
    $report = [regex]::Match($diag, '(?s)Entry crash = Files\.NewestCrash\(\);\s*if \(crash != null\) Grab\(work, crash\.FullPath\);')
    Yes 'the report zip takes the crash log, not the snapshot' ($report.Success -and $diag -notmatch '\.dmp' -and $files -match '"crash-\*\.log"')
    Yes 'Diagnostics names the snapshot beside the newest crash and says the report leaves it out' ($diag -match 'CrashDump\.Beside\(crash\.FullPath\)' -and $diag -match 'The report leaves it out')
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
Done
