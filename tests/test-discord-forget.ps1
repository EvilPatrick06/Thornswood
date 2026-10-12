<#
  test-discord-forget.ps1

      powershell -NoProfile -File .\tests\test-discord-forget.ps1

  Unlinking drops the last account's staff answer. Discord.Forget used to
  delete the ticket, the name and the avatar, and leave dev-allowed.txt,
  so Discord.DevAllowed stayed true until the next account's first check-in
  (#1208). door.txt is the last yes or no the site gave for that ticket, so
  it goes too.

  Compiles the real Discord.cs with the real Secrets.cs and Swallow.cs, and
  a stand-in Paths that only supplies the two fields those files read.
  The .NET Framework 4 csc is the one the launcher builds with.

  Read only apart from files under its own temp folder.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Done {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail) { exit 1 } else { exit 0 }
}

$csc = @(
    "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
    "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $csc) {
    Write-Host 'SKIP  no .NET Framework 4 csc on this machine, so Discord.cs cannot be compiled here'
    Done
}
$fw = Split-Path -Parent $csc
$core = Join-Path $fw 'System.Core.dll'
Yes 'System.Core.dll is there to compile against' (Test-Path -LiteralPath $core)
if (-not (Test-Path -LiteralPath $core)) { Done }

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('discord-forget-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$driver = Join-Path $tmp 'driver.cs'
$exe = Join-Path $tmp 'forget.exe'
$cs = @(
'using System;',
'using System.IO;',
'',
'namespace Thornswood',
'{',
'    static class Paths',
'    {',
'        public static string Game = "";',
'        public static string LogFile = "";',
'    }',
'',
'    public class Config { }',
'    public class Check',
'    {',
'        public bool Ok;',
'        public string Name = "";',
'        public string Detail = "";',
'    }',
'    static class Checks',
'    {',
'        public static Check[] All(Config c) { return new Check[0]; }',
'    }',
'',
'    static class AutoJoin { public static int GetProfileId() { return 0; } }',
'    static class Updater { public static string Version = ""; }',
'    static class Files { public static string SkseLogDir = ""; }',
'    // Since #2380 the crash log line finds its snapshot by CrashDump.Beside.',
'    // CrashDump.cs needs Enforce and a full Config, so its rule is stood in',
'    // for here, as test-log-upload.ps1 does (test-crash-snapshot.ps1 holds the real one).',
'    static class CrashDump { public static string Beside(string l) { string d = Path.ChangeExtension(l, ".dmp"); return File.Exists(d) ? d : null; } }',
'    public class Issue',
'    {',
'        public string Text = "";',
'        public bool Blocking;',
'        public bool Absent;',
'        public string Plugin = "";',
'        public long WantSize;',
'        public uint WantCrc;',
'        public int WantIndex;',
'    }',
'    static class Verify { public static Issue[] Run() { return new Issue[0]; } }',
'',
'    static class Driver',
'    {',
'        static int fail;',
'        static void Yes(string what, bool cond)',
'        {',
'            if (cond) { Console.WriteLine("PASS  " + what); }',
'            else { Console.WriteLine("FAIL  " + what); fail++; }',
'        }',
'',
'        static int Main(string[] args)',
'        {',
'            string dir = args[0];',
'            Discord.Folder = dir;',
'            Yes("DevAllowed is true while the last account staff answer is on disk", Discord.DevAllowed);',
'            Discord.Forget();',
'            Yes("DevAllowed is false after unlink", !Discord.DevAllowed);',
'            Yes("dev-allowed.txt is gone", !File.Exists(Path.Combine(dir, "dev-allowed.txt")));',
'            Yes("door.txt is gone", !File.Exists(Path.Combine(dir, "door.txt")));',
'            Yes("discord.txt is gone", !File.Exists(Path.Combine(dir, "discord.txt")));',
'            Yes("discord-name.txt is gone", !File.Exists(Path.Combine(dir, "discord-name.txt")));',
'            Yes("discord-avatar.txt is gone", !File.Exists(Path.Combine(dir, "discord-avatar.txt")));',
'            return fail == 0 ? 0 : 1;',
'        }',
'    }',
'}'
)
[IO.File]::WriteAllText($driver, ($cs -join "`r`n") + "`r`n")

$sources = @(
    (Join-Path $Repo 'launcher\app\Discord.cs'),
    (Join-Path $Repo 'launcher\app\Secrets.cs'),
    (Join-Path $Repo 'launcher\app\Swallow.cs'),
    $driver
)
& $csc /nologo /t:exe /out:$exe /r:$core $sources
Yes 'Discord.cs compiles with Forget under the C# 5 compiler' ($LASTEXITCODE -eq 0)
if ($LASTEXITCODE -ne 0) { Done }

$profile = Join-Path $tmp 'Profile'
New-Item -ItemType Directory -Force -Path $profile | Out-Null
$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $profile 'dev-allowed.txt'), 'yes', $utf8)
[IO.File]::WriteAllText((Join-Path $profile 'door.txt'), ('yes|' + [DateTime]::UtcNow.Ticks), $utf8)
[IO.File]::WriteAllText((Join-Path $profile 'discord.txt'), 'tk1.e30.sig', $utf8)
[IO.File]::WriteAllText((Join-Path $profile 'discord-name.txt'), 'Ada', $utf8)
[IO.File]::WriteAllText((Join-Path $profile 'discord-avatar.txt'), 'abc', $utf8)

& $exe $profile
if ($LASTEXITCODE -ne 0) { $script:fail++ }
Yes 'the driver finished and agrees' ($LASTEXITCODE -eq 0)

try { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction Stop } catch { }
Done
