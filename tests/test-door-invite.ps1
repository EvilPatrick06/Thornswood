<#
  test-door-invite.ps1

      powershell -NoProfile -File .\tests\test-door-invite.ps1

  "Not accepted yet" offers the Discord invite (#999).

  /api/play/join answers a Discord account that has no role that lets it in
  with why 'role', the message telling them to apply in the Discord, and the
  invite. Door.Explain offered to open the invite only for why 'guild', so for
  'role' it put up the message in an OK box and stopped, and somebody told to
  apply in the Discord had to find the Discord themselves.

  This compiles the real Door.cs, with the real Standing class lifted out of
  Discord.cs by brace match, with the compiler the build runs
  (tests\Launcher-Csc.ps1), and asks Door.InviteQuestion
  about every answer the site gives. Then it reads Explain and holds it to
  asking that question with Yes and No and opening the invite on Yes.
  site\server.js is read for the other half: 'role' is sent with the invite.

  Read only apart from files under its own temp folder.
#>
[CmdletBinding()]
param([string]$DoorPath, [string]$DiscordPath)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Launcher-Csc.ps1')   # the build's compiler and C# version (#498)
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, the repository is one folder up.
$Here = Split-Path -Parent $Here
if (-not $DoorPath) { $DoorPath = Join-Path $Here 'launcher\app\Door.cs' }
if (-not $DiscordPath) { $DiscordPath = Join-Path $Here 'launcher\app\Discord.cs' }

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

$doorSrc = [IO.File]::ReadAllText($DoorPath)

# ---- Explain asks the question and opens the invite on Yes -------------------
$at = $doorSrc.IndexOf('public static void Explain(')
Yes 'Door.cs has Explain' ($at -ge 0)
if ($at -lt 0) { Done }
$explain = $doorSrc.Substring($at, $doorSrc.IndexOf('public static string InviteQuestion(') - $at)
Yes 'Explain asks InviteQuestion whether it can offer the Discord' ($explain -match 'string ask = InviteQuestion\(st\);\s*if \(ask != null\)')
Yes 'the question goes on the end of the site''s message' ($explain.Contains('body += "\n\n" + ask;'))
Yes 'as a Yes and No box' ($explain -match '(?s)if \(ask != null\).{0,200}MessageBoxButton\.YesNo')
Yes 'and Yes opens the invite the site sent' ($explain -match '(?s)MessageBoxResult\.Yes\).{0,300}ProcessStartInfo\(st\.Invite\).{0,200}Process\.Start\(psi\)')
Yes 'Explain no longer offers the invite for guild alone' (-not $explain.Contains('st.Why == "guild" && st.Invite'))

# ---- the site sends the invite with 'role' -----------------------------------
$server = [IO.File]::ReadAllText((Join-Path $Here 'site\server.js'))
Yes 'site\server.js sends why role with the invite on /api/play/join' (
    $server -match "(?s)why:'role', message:\s*notAcceptedYet\(\),\s*invite: cfg\.discord\.invite")

# ---- the compiler the launcher is built with --------------------------------
if (-not $OnWindows) { Write-Host 'SKIP  the launcher''s code, compiled and run: its compiler is the Roslyn csc that comes with Visual Studio''s Build Tools, which only Windows has'; Done }
Yes 'the compiler the build runs is on this machine (the Roslyn csc beside MSBuild)' (Test-Path -LiteralPath $LauncherCsc)
if (-not (Test-Path -LiteralPath $LauncherCsc)) { Done }
$refs = @('System.dll', 'System.Core.dll', 'System.Xaml.dll', 'WindowsBase.dll', 'PresentationCore.dll', 'PresentationFramework.dll') |
    ForEach-Object { Join-Path $LauncherRefDir $_ }
foreach ($r in $refs) { Yes "$([IO.Path]::GetFileName($r)) is there to compile against" (Test-Path -LiteralPath $r) }
if (@($refs | Where-Object { -not (Test-Path -LiteralPath $_) }).Count) { Done }

# ---- the real Standing, out of Discord.cs -----------------------------------
$discordSrc = [IO.File]::ReadAllText($DiscordPath)
$at = $discordSrc.IndexOf('public class Standing')
Yes 'Discord.cs still has the Standing class' ($at -ge 0)
if ($at -lt 0) { Done }
$b = $discordSrc.IndexOf('{', $at)
$depth = 0; $end = -1
for ($i = $b; $i -lt $discordSrc.Length; $i++) {
    $c = $discordSrc[$i]
    if ($c -eq '{') { $depth++ }
    elseif ($c -eq '}') { $depth--; if ($depth -eq 0) { $end = $i; break } }
}
$standing = $discordSrc.Substring($at, $end - $at + 1)

# The driver prints InviteQuestion's answer for a why and an invite, "null"
# when there is none. "-" for the invite is no invite at all, "empty" an empty one.
$driver = @'
using System;

namespace Thornswood
{
    STANDING_GOES_HERE

    public static class Swallow { public static void Note(string where, Exception e) { } }

    public static class Discord
    {
        public static string Folder = "";
        public static Standing Join() { throw new Exception("not in this test"); }
    }

    public static class DoorInviteTest
    {
        public static int Main(string[] args)
        {
            for (int i = 0; i + 1 < args.Length; i += 2)
            {
                Standing st = new Standing();
                st.Ok = false;
                st.Why = args[i];
                st.Invite = args[i + 1] == "-" ? null : (args[i + 1] == "empty" ? "" : args[i + 1]);
                string q = Door.InviteQuestion(st);
                Console.WriteLine(args[i] + "|" + args[i + 1] + "=" + (q == null ? "null" : q));
            }
            Console.WriteLine("nullstanding=" + (Door.InviteQuestion(null) == null ? "null" : "asked"));
            return 0;
        }
    }
}
'@
$driver = $driver.Replace('STANDING_GOES_HERE', $standing)

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-door-invite-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    $driverFile = Join-Path $tmp 'DoorInviteTest.cs'
    [IO.File]::WriteAllText($driverFile, $driver, (New-Object System.Text.UTF8Encoding($false)))
    $exe = Join-Path $tmp 'door-invite-test.exe'
    # /noconfig, as the build does: csc.rsp adds its own copies of the
    # framework, and beside the reference assemblies that stops on CS1703.
    $cscArgs = @('/noconfig', '/nologo', '/target:exe', '/warn:0', "/out:$exe")
    foreach ($r in $refs) { $cscArgs += "/reference:$r" }
    $cscArgs += (Resolve-Path -LiteralPath $DoorPath).Path
    $cscArgs += $driverFile
    $compiled = & $LauncherCsc @cscArgs
    $built = ($LASTEXITCODE -eq 0) -and (Test-Path -LiteralPath $exe)
    Yes 'Door.cs compiles with the compiler the build runs' $built
    if (-not $built) {
        foreach ($l in @($compiled)) { Write-Host "      $l" }
        Done
    }

    $inv = 'https://discord.gg/example'
    $lines = & $exe 'role' $inv 'guild' $inv 'banned' $inv 'role' '-' 'role' 'empty' 'guild' '-' `
                    'link' $inv 'could not ask Discord' $inv 'offline' $inv 'role' 'file:///C:/Windows/notepad.exe' `
                    'role' 'C:\Windows\notepad.exe' 'role' 'HTTPS://discord.gg/example'
    $got = @{}
    foreach ($l in @($lines)) { $s = [string]$l; $cut = $s.IndexOf('='); if ($cut -gt 0) { $got[$s.Substring(0, $cut)] = $s.Substring($cut + 1) } }

    Yes 'not accepted yet, with an invite: the box offers to open the Discord' ($got["role|$inv"] -eq 'Open the Discord to apply?')
    Yes 'not in the Discord, with an invite: it still offers to join it' ($got["guild|$inv"] -eq 'Open the Discord and join it?')
    Yes 'banned never gets the invite' ($got["banned|$inv"] -eq 'null')
    Yes 'not accepted yet with no invite sent: no offer, the OK box as before' ($got['role|-'] -eq 'null')
    Yes 'not accepted yet with an empty invite: no offer' ($got['role|empty'] -eq 'null')
    Yes 'not in the Discord with no invite: no offer' ($got['guild|-'] -eq 'null')
    Yes 'not linked yet: no invite, Connect Discord is its answer' ($got["link|$inv"] -eq 'null')
    Yes 'Discord could not be asked: no invite' ($got["could not ask Discord|$inv"] -eq 'null')
    Yes 'the site did not answer: no invite' ($got["offline|$inv"] -eq 'null')
    Yes 'an invite that is not a web address is never opened' (
        $got['role|file:///C:/Windows/notepad.exe'] -eq 'null' -and $got['role|C:\Windows\notepad.exe'] -eq 'null')
    Yes 'a web address in capitals is still one' ($got['role|HTTPS://discord.gg/example'] -eq 'Open the Discord to apply?')
    Yes 'no answer at all asks nothing' ($got['nullstanding'] -eq 'null')

    $said = @($got.Values | Where-Object { $_ -ne 'null' }) -join ' '
    Yes 'no em dash and never the word the project does not use' (-not ($said -match [char]0x2014) -and -not ($said -match 'player'))
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Done
