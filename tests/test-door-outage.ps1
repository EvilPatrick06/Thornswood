<#
  test-door-outage.ps1

      powershell -NoProfile -File .\tests\test-door-outage.ps1

  The launcher's half of "Discord did not answer is not a no".

  The site's door, /api/play/join, used to answer a rate limit from Discord
  with 403 why 'guild', "That Discord account is not in the Thornswood
  Discord". Door.cs writes a 'guild' down as a remembered no, so the same
  answer also erased the 72 hour grace the launcher keeps for a site that
  cannot vouch for anybody. The restart wave after every release is when
  Discord rate limits the site. The site now answers 503 with why
  "could not ask Discord", which is what /api/play/owns already said, and
  Door.cs has to treat that the way it treats a site that did not answer: a
  recent yes still opens the door, and nothing is written down as a no.

  This compiles the real Door.cs, with the real Standing class lifted out of
  Discord.cs by brace match, against a stand-in Discord.Join that returns the
  answer each case names. It compiles with the compiler the build runs
  (tests\Launcher-Csc.ps1). Then it
  drives Door.Check through a real WPF dispatcher, the way Shell does, and
  reads back whether Play went ahead, whether the box went up, what it said
  and what door.txt says afterwards. test-join-outage.js is the site's half.

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

# ---- the compiler the launcher is built with (tests\Launcher-Csc.ps1) -------
if (-not $OnWindows) { Write-Host 'SKIP  the launcher''s code, compiled and run: its compiler is the Roslyn csc that comes with Visual Studio''s Build Tools, which only Windows has'; Done }
Yes 'the compiler the build runs is on this machine (the Roslyn csc beside MSBuild)' (Test-Path -LiteralPath $LauncherCsc)
if (-not (Test-Path -LiteralPath $LauncherCsc)) { Done }
$refs = @('System.dll', 'System.Core.dll', 'System.Xaml.dll', 'WindowsBase.dll', 'PresentationCore.dll', 'PresentationFramework.dll') |
    ForEach-Object { Join-Path $LauncherRefDir $_ }
foreach ($r in $refs) { Yes "$([IO.Path]::GetFileName($r)) is there to compile against" (Test-Path -LiteralPath $r) }
if (@($refs | Where-Object { -not (Test-Path -LiteralPath $_) }).Count) { Done }

# ---- the real Standing, out of Discord.cs -----------------------------------
$discordSrc = Get-Content -LiteralPath $DiscordPath -Raw
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

# ---- a stand-in Discord.Join, and a driver that runs Door.Check once --------
#
# The driver takes three arguments: the folder door.txt lives in, the why the
# site answers with ("ok" for a yes, "throw" for Discord.Join throwing, "-"
# for a reply with no why in it), and what door.txt says beforehand ("yes" an
# hour ago, "old" a yes a hundred hours ago, "no" an hour ago, or "none").
$driver = @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Windows;
using System.Windows.Threading;

namespace Thornswood
{
    STANDING_GOES_HERE

    // Stands in for launcher\app\Swallow.cs, which Door.cs calls from its
    // catch blocks since the silent catches were given a log line (#461).
    // The real one writes to Paths.LogFile, which this driver has no use for.
    public static class Swallow
    {
        public static void Note(string where, Exception e) { }
    }

    public static class Discord
    {
        public static string Folder = "";
        public static Standing Next;
        public static Standing Join()
        {
            if (Next == null) throw new Exception("the network is unplugged");
            return Next;
        }
    }

    public static class DoorOutageTest
    {
        [STAThread]
        public static int Main(string[] args)
        {
            Discord.Folder = args[0];
            string why = args[1];
            string note = args[2];
            Directory.CreateDirectory(Discord.Folder);
            string file = Path.Combine(Discord.Folder, "door.txt");
            if (File.Exists(file)) File.Delete(file);
            if (note != "none")
            {
                long ticks = DateTime.UtcNow.AddHours(note == "old" ? -100 : -1).Ticks;
                File.WriteAllText(file, (note == "no" ? "no" : "yes") + "|" + ticks);
            }

            if (why == "throw") Discord.Next = null;
            else
            {
                Standing st = new Standing();
                st.Ok = why == "ok";
                st.Why = (why == "ok" || why == "-") ? "" : why;
                st.Message = st.Ok ? "" : "the site's own words";
                Discord.Next = st;
            }

            bool allowed = false, shouted = false, done = false;
            string told = "";
            List<string> logged = new List<string>();
            Window win = new Window();
            DispatcherFrame frame = new DispatcherFrame();
            DispatcherTimer timer = new DispatcherTimer();
            timer.Interval = TimeSpan.FromSeconds(10);
            timer.Tick += delegate { timer.Stop(); frame.Continue = false; };
            timer.Start();

            Door.Forget();
            Door.Check(win,
                delegate (string line) { logged.Add(line); },
                delegate (Standing s) { shouted = true; told = s.Message ?? ""; },
                delegate { allowed = true; },
                delegate { done = true; frame.Continue = false; });
            Dispatcher.PushFrame(frame);
            timer.Stop();

            string after = "none";
            if (File.Exists(file)) after = File.ReadAllText(file).Split('|')[0];
            Console.WriteLine("done=" + done);
            Console.WriteLine("allowed=" + allowed);
            Console.WriteLine("shouted=" + shouted);
            Console.WriteLine("note=" + after);
            Console.WriteLine("message=" + told.Replace("\r", " ").Replace("\n", " "));
            Console.WriteLine("log=" + string.Join(" / ", logged.ToArray()).Replace("\r", " ").Replace("\n", " "));
            return 0;
        }
    }
}
'@
$driver = $driver.Replace('STANDING_GOES_HERE', $standing)

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-door-outage-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    $driverFile = Join-Path $tmp 'DoorOutageTest.cs'
    [IO.File]::WriteAllText($driverFile, $driver, (New-Object System.Text.UTF8Encoding($false)))
    $exe = Join-Path $tmp 'door-outage-test.exe'
    $work = Join-Path $tmp 'profile'

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

    function Knock([string]$why, [string]$note) {
        $lines = & $exe $work $why $note
        $r = @{ ran = ($LASTEXITCODE -eq 0) }
        foreach ($l in @($lines)) {
            $s = [string]$l
            $cut = $s.IndexOf('=')
            if ($cut -gt 0) { $r[$s.Substring(0, $cut)] = $s.Substring($cut + 1) }
        }
        $r
    }
    function Finished($r) { return $r.ran -and $r.done -eq 'True' }

    $outage = 'could not ask Discord'

    # ---- the fault this exists for ----------------------------------------------
    $r = Knock $outage 'yes'
    Yes 'Door.Check finishes on the outage answer' (Finished $r)
    Yes 'a yes from an hour ago opens the door when the site could not ask Discord' ($r.allowed -eq 'True')
    Yes 'and no box goes up telling them anything' ($r.shouted -eq 'False')
    Yes 'and the remembered yes is still a yes afterwards' ($r.note -eq 'yes')
    Yes 'the log says it was Discord that did not answer' ("$($r.log)".Contains('could not ask Discord'))

    $r = Knock $outage 'none'
    Yes 'with nothing remembered, the outage answer does not open the door' ((Finished $r) -and $r.allowed -eq 'False' -and $r.shouted -eq 'True')
    Yes 'the box says Discord could not be asked' ("$($r.message)".Contains('could not ask Discord'))
    Yes 'the box does not say they are not in the Discord' (-not "$($r.message)".Contains('not in the Thornswood Discord'))
    Yes 'the box does not tell them to check an internet connection that is working' (-not "$($r.message)".Contains('internet'))
    Yes 'and nothing is written down as a no' ($r.note -eq 'none')

    $r = Knock $outage 'old'
    Yes 'a yes older than the grace does not open the door on an outage' ((Finished $r) -and $r.allowed -eq 'False')
    Yes 'and it is not overwritten with a no either' ($r.note -eq 'yes')

    $r = Knock $outage 'no'
    Yes 'a remembered no is not overturned by an outage' ((Finished $r) -and $r.allowed -eq 'False' -and $r.note -eq 'no')

    # ---- what was already right stays right --------------------------------------
    $r = Knock 'offline' 'yes'
    Yes 'the site not answering at all still stands on a recent yes' ((Finished $r) -and $r.allowed -eq 'True' -and $r.note -eq 'yes')

    $r = Knock 'offline' 'none'
    Yes 'and with nothing remembered it still says to check the connection' ((Finished $r) -and $r.allowed -eq 'False' -and "$($r.message)".Contains('Could not reach thornswood.net'))

    $r = Knock 'throw' 'yes'
    Yes 'Discord.Join throwing is the same as the site not answering' ((Finished $r) -and $r.allowed -eq 'True')

    $r = Knock 'guild' 'yes'
    Yes 'a real not in the Discord still refuses' ((Finished $r) -and $r.allowed -eq 'False' -and $r.shouted -eq 'True')
    Yes 'and is still written down as a no' ($r.note -eq 'no')

    $r = Knock 'banned' 'yes'
    Yes 'banned still refuses and is written down as a no' ((Finished $r) -and $r.allowed -eq 'False' -and $r.note -eq 'no')

    $r = Knock 'role' 'yes'
    Yes 'no role still refuses and is written down as a no' ((Finished $r) -and $r.allowed -eq 'False' -and $r.note -eq 'no')

    # A reply the launcher cannot read, a bad gateway page, is neither a yes nor
    # a no. It refuses this once and leaves the note alone.
    $r = Knock '-' 'yes'
    Yes 'a reply with no why in it refuses once and leaves the remembered yes alone' ((Finished $r) -and $r.allowed -eq 'False' -and $r.note -eq 'yes')

    $r = Knock 'ok' 'none'
    Yes 'a yes from the site opens the door and is written down' ((Finished $r) -and $r.allowed -eq 'True' -and $r.note -eq 'yes')
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Done
