<#
  test-2019-ship-roots.ps1

      pwsh -NoProfile -File .\tests\test-2019-ship-roots.ps1

  Issue #2019. A Ship never packs a folder that can be stale.

  WHAT WAS WRONG, measured on One on 15 Oct. The dev ship root
  (local\release-devbuild) was a launcher install whose launcher is never
  started, so its Game folder was still the one made on 3 Oct: OwnGame rules
  14 against the code's 16, made from C:\Thornswood-DevBuild\Game rather than
  Vortex's deployment, the collection's old 3BBB.esp in it, and the 12 Oct
  client. Ship read the client from the worktree's own engine\skymp\build,
  also 12 Oct, and refused twice. Main had no ship root of its own, so a main
  Ship packed C:\Thornswood, Patrick's own install.

  WHAT IT HOLDS.
    1. The ship root tool (scripts\release\ShipRoot), compiled from the real
       OwnGame sources with its own two files, on a pretend Steam, Vortex and
       root in a scratch folder:
       a. a new main root is made the way an install that chose its own
          folder is: config.json for main, Thornswood's own files synced from
          the channel's release into Payload (the sync stood in for), Make,
          Payload gone, and the folder current;
       b. the same root made at older rules from another folder, after Vortex
          deployed a new copy of a plugin (One's dev root on 15 Oct): -Check
          says it was made from another folder and changes nothing; a run
          brings it up to date, the plugin is Vortex's new bytes, made.txt
          names the folder Vortex deploys into at the current rules, and
          Thornswood's own file is still there;
       c. Vortex deploying again is seen by -Check and taken in by a run;
       d. refusals, each with nothing changed: the other channel's root, a
          folder Vortex deploys into, a Game folder OwnGame did not make,
          -Check on a root that is not there.
    2. Where.ps1 and where.js: with no record ClientDist and ServerDist are
       under the checkout's engine\skymp; with Setup-ShipMachine's record they
       are under the recorded fork's build, for every clone; a record naming
       a folder with no build stops with a sentence and never falls back.
    3. Update-ShipRoot.ps1, the real script with a stand-in tool: a tool that
       refuses stops it, naming why; a client build that is not the record
       stops it; the recorded build goes in, through a file that had a second
       name without writing through it, and it ends current.
    4. Setup-ShipMachine.ps1's Save-EngineBuild writes the record and refuses
       a folder with no build in it; Ship.ps1 runs Update-ShipRoot.ps1 for
       the channel's root before the version moves and before anything is
       built, and stops when it refuses (tests\test-ship-dry-run.ps1 runs that
       Ship, N).

  Nothing outside its own scratch folder is written. Needs the Build Tools'
  csc (tests\Launcher-Csc.ps1) and node.
#>
[CmdletBinding()]
param([string]$Scratch)
# Scripts this runs whole go to a stand-in box, so the freshness guard lets them be (#2118).
$env:THORNSWOOD_HARNESS = '1'

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Launcher-Csc.ps1')   # the build's compiler and C# version (#498)
$Here = Split-Path -Parent $PSScriptRoot
$App = Join-Path $Here 'launcher\app'
$Tool = Join-Path $Here 'scripts\release\ShipRoot'
$Release = Join-Path $Here 'scripts\release'
if (-not $Scratch) { $Scratch = [IO.Path]::GetTempPath() }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Done {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail -gt 0) { exit 1 }
    exit 0
}

$work = Join-Path $Scratch ('thornswood-2019-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Force -Path $work
$utf8 = New-Object System.Text.UTF8Encoding($false)
$oldLocal = $env:LOCALAPPDATA

try {
# ============================================================ 1. the tool ====
$stubs = @'
using System;
using System.Collections.Generic;
using System.IO;

namespace Thornswood
{
    static class Checks
    {
        public const string OffSuffix = ".thornswood-off";
        public static string VortexProfileDir(string name) { return null; }
        public static bool GameRunning() { return false; }
    }
    static class Keep
    {
        public static List<string> Held() { return new List<string>(); }
        public static string Dir { get { return Path.Combine(Paths.ProfileDir, "Keep"); } }
    }
    static class Junction { public static bool IsLink(string p) { return false; } }
    static class Icons { public static List<string> ShortcutPaths(string buildName) { return new List<string>(); } }
    // The launcher's sync, stood in for: what Updater.Resync leaves in an
    // install that chose its own folder, which is the release's game files in
    // Paths.Game (Profile\Payload until the folder is made) and its plugin
    // list in Profile\Default. tests\test-record-sync.ps1 holds the real one.
    static partial class Updater
    {
        public static int Synced;
        public static string SyncedInto;
        public static bool ReleaseFilesKnown() { return true; }
        public static List<string> ReleaseFiles() { return new List<string>(); }
        public static VersionDoc Check(Config cfg) { return new VersionDoc(); }
        public static bool Resync(Config cfg, VersionDoc v, Action<string> log)
        {
            Synced++;
            SyncedInto = Paths.Game;
            string ours = Path.Combine(Paths.Game, "Data\\Platform\\Plugins\\thornswood-front.js");
            Directory.CreateDirectory(Path.GetDirectoryName(ours));
            File.WriteAllText(ours, "// thornswood's own, from the release");
            Directory.CreateDirectory(Paths.Golden);
            File.WriteAllText(Path.Combine(Paths.Golden, "plugins.txt"), "# Automatically generated by Vortex\r\n*TsOne.esp\r\n");
            log("Release stand-in: 1 file put right.");
            return true;
        }
    }
}
'@

$driver = @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;

namespace Thornswood
{
    static class ShipRootTest
    {
        static int pass, fail;
        static void Yes(string what, bool cond)
        {
            Console.WriteLine((cond ? "PASS  " : "FAIL  ") + what);
            if (cond) pass++; else fail++;
        }
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool CreateHardLink(string newName, string existing, IntPtr security);

        static string T, SteamDir, Game, Staging;
        static void Put(string path, string text)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            File.WriteAllText(path, text, new UTF8Encoding(false));
        }
        static string J(string s) { return s.Replace("\\", "\\\\").Replace("\"", "\\\""); }

        // A Steam copy on the pinned build by the exe's size, which is all the
        // list below pins (its sha1s are "0"), so the config's own default
        // ExpectedExeBytes is the one Make holds it to.
        static void Steam()
        {
            SteamDir = Path.Combine(T, "steam");
            Game = Path.Combine(SteamDir, "steamapps\\common\\Skyrim Special Edition");
            Staging = Path.Combine(T, "vortex\\mods");
            Put(Path.Combine(SteamDir, "config\\libraryfolders.vdf"),
                "\"libraryfolders\"\n{\n\t\"0\"\n\t{\n\t\t\"path\"\t\t\"" + J(SteamDir) + "\"\n\t}\n}\n");
            Thornswood.Steam.RootForTest = SteamDir;
            Directory.CreateDirectory(Game);
            using (var fs = new FileStream(Path.Combine(Game, "SkyrimSE.exe"), FileMode.Create)) fs.SetLength(new Config().ExpectedExeBytes);
            Put(Path.Combine(Game, "Data\\Skyrim.esm"), "PIN-MASTER");
            Deploy("VORTEX-TSONE-1", DateTime.UtcNow.AddMinutes(-30));
        }

        // Vortex's deployment: one plugin, linked from its staging copy, and
        // its record. A new text is a new copy in staging and a new link.
        static void Deploy(string plugin, DateTime when)
        {
            string staged = Path.Combine(Staging, "ModA\\TsOne.esp");
            string at = Path.Combine(Game, "Data\\TsOne.esp");
            if (File.Exists(at)) File.Delete(at);
            if (File.Exists(staged)) File.Delete(staged);
            Put(staged, plugin);
            CreateHardLink(at, staged, IntPtr.Zero);
            string rec = Path.Combine(Game, "Data\\vortex.deployment.json");
            // The time Vortex's record gives a file is its staging copy's write
            // time in milliseconds (measured on One, 16 Oct: 400 of 400), which
            // a refresh compares with the last record's (#2210).
            long time = (long)(File.GetLastWriteTimeUtc(staged) - new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc)).TotalMilliseconds;
            Put(rec, "{\n  \"instance\": \"test\",\n  \"version\": 1,\n  \"deploymentMethod\": \"hardlink_activator\",\n  \"gameId\": \"skyrimse\",\n" +
                     "  \"stagingPath\": \"" + J(Staging) + "\",\n  \"targetPath\": \"" + J(Path.Combine(Game, "Data")) + "\",\n" +
                     "  \"files\": [ { \"relPath\": \"TsOne.esp\", \"source\": \"ModA\", \"target\": \"\", \"time\": " + time + " } ]\n}\n");
            File.SetLastWriteTimeUtc(rec, when);
        }

        static string Made(string root, string key)
        {
            string f = Path.Combine(root, "Profile\\OwnGame\\made.txt");
            if (!File.Exists(f)) return null;
            foreach (string l in File.ReadAllLines(f)) if (l.StartsWith(key + "=")) return l.Substring(key.Length + 1);
            return null;
        }
        static void SetMade(string root, string key, string value)
        {
            string f = Path.Combine(root, "Profile\\OwnGame\\made.txt");
            var lines = new List<string>();
            foreach (string l in File.ReadAllLines(f)) lines.Add(l.StartsWith(key + "=") ? key + "=" + value : l);
            File.WriteAllLines(f, lines.ToArray());
        }
        static string RulesNow()
        {
            return Convert.ToString(typeof(OwnGame).GetField("Rules", BindingFlags.NonPublic | BindingFlags.Static).GetValue(null));
        }
        static bool Same(string a, string b)
        {
            return a != null && b != null && string.Equals(Path.GetFullPath(a).TrimEnd('\\'), Path.GetFullPath(b).TrimEnd('\\'), StringComparison.OrdinalIgnoreCase);
        }

        static string Run(string root, string channel, bool check, List<string> said)
        {
            try { return ShipRootTool.Run(root, channel, check, delegate(string m) { said.Add(m); }); }
            catch (Exception ex) { return "THREW " + ex.Message; }
        }

        static int Main(string[] args)
        {
            T = args[0];
            try
            {
                Steam();
                string root = Path.Combine(T, "repo\\local\\release-main");
                var said = new List<string>();

                // ---- a. a new main root ------------------------------------
                string why = Run(root, "main", true, said);
                Yes("a. -Check on a root that is not there says so and makes nothing", why != null && why.Contains("no ship root") && !Directory.Exists(root));
                why = Run(root, "main", false, said);
                Yes("a. a new main root is made (" + (why ?? "current") + ")", why == null);
                Config cfg = Config.Load(Path.Combine(root, "config.json"));
                Yes("a.   with a config.json for main", File.Exists(Path.Combine(root, "config.json")) && !cfg.IsDev && cfg.ServerPort == "7777");
                Yes("a.   Thornswood's own files synced from the channel's release once, into Profile\\Payload",
                    Updater.Synced == 1 && Same(Updater.SyncedInto, Path.Combine(root, "Profile\\Payload")));
                Yes("a.   taken into the game folder by Make, and Payload gone",
                    File.Exists(Path.Combine(root, "Game\\Data\\Platform\\Plugins\\thornswood-front.js")) && !Directory.Exists(Path.Combine(root, "Profile\\Payload")));
                Yes("a.   with Vortex's plugin in it", File.ReadAllText(Path.Combine(root, "Game\\Data\\TsOne.esp")) == "VORTEX-TSONE-1");
                Yes("a.   made.txt names the folder Vortex deploys into, at the current rules",
                    Same(Made(root, "source"), Game) && Made(root, "rules") == RulesNow() && Made(root, "kinds") == "1");
                said.Clear();
                Yes("a.   and -Check calls it current", Run(root, "main", true, said) == null && string.Join(" ", said.ToArray()).Contains("is current"));

                // ---- b. made at older rules, from another folder -----------
                SetMade(root, "rules", "14");
                SetMade(root, "source", Path.Combine(T, "Thornswood-DevBuild\\Game"));
                Deploy("VORTEX-TSONE-2-REINSTALLED", DateTime.UtcNow.AddMinutes(-5));
                why = Run(root, "main", true, said);
                Yes("b. -Check on a root made from another folder says so", why != null && why.Contains("was made from") && why.Contains("Thornswood-DevBuild"));
                Yes("b.   and changes nothing", File.ReadAllText(Path.Combine(root, "Game\\Data\\TsOne.esp")) == "VORTEX-TSONE-1" && Made(root, "rules") == "14");
                SetMade(root, "source", Game);
                why = Run(root, "main", true, said);
                Yes("b. one at older rules is named too", why != null && why.Contains("rules 14"));
                SetMade(root, "source", Path.Combine(T, "Thornswood-DevBuild\\Game"));
                said.Clear();
                why = Run(root, "main", false, said);
                Yes("b. a run brings it up to date (" + (why ?? "current") + ")", why == null);
                Yes("b.   the plugin is Vortex's new copy", File.ReadAllText(Path.Combine(root, "Game\\Data\\TsOne.esp")) == "VORTEX-TSONE-2-REINSTALLED");
                Yes("b.   made.txt names the folder Vortex deploys into, at the current rules",
                    Same(Made(root, "source"), Game) && Made(root, "rules") == RulesNow());
                Yes("b.   Thornswood's own file is still there", File.Exists(Path.Combine(root, "Game\\Data\\Platform\\Plugins\\thornswood-front.js")));
                Yes("b.   and no second sync: a made root's own files are the Ship's", Updater.Synced == 1);

                // ---- c. Vortex deploys again ------------------------------
                Deploy("VORTEX-TSONE-3", DateTime.UtcNow);
                why = Run(root, "main", true, said);
                Yes("c. -Check sees Vortex has deployed since", why != null && why.Contains("has deployed"));
                Yes("c.   a run takes it in", Run(root, "main", false, said) == null && File.ReadAllText(Path.Combine(root, "Game\\Data\\TsOne.esp")) == "VORTEX-TSONE-3");

                // ---- d. refusals -------------------------------------------
                why = Run(root, "dev", false, said);
                Yes("d. the main root asked for as dev is refused", why != null && why.Contains("main build's") && Made(root, "rules") == RulesNow());
                string vortexRoot = Path.Combine(T, "vortex-root");
                Put(Path.Combine(vortexRoot, "Game\\Data\\vortex.deployment.json"), "{}");
                why = Run(vortexRoot, "dev", false, said);
                Yes("d. a folder Vortex deploys into is refused", why != null && why.Contains("Vortex deploys into") && !File.Exists(Path.Combine(vortexRoot, "config.json")));
                string handRoot = Path.Combine(T, "hand-root");
                Put(Path.Combine(handRoot, "Game\\Data\\Skyrim.esm"), "A COPY BY HAND");
                why = Run(handRoot, "dev", false, said);
                Yes("d. a Game folder OwnGame did not make is refused, saying what to do", why != null && why.Contains("OwnGame did not make it") && why.Contains("Move that Game folder"));
                Yes("d.   and left as it was", File.ReadAllText(Path.Combine(handRoot, "Game\\Data\\Skyrim.esm")) == "A COPY BY HAND");
                Config dev = Config.Load(Path.Combine(handRoot, "config.json"));
                Yes("d.   its config.json was written for dev, as DevBuild.Install writes one", dev.IsDev && dev.ServerPort == DevBuild.DevPort && dev.UpdateFeedUrl.Contains("/feed-dev/"));
            }
            catch (Exception ex)
            {
                Yes("the driver ran to the end (" + ex.GetType().Name + ": " + ex.Message + ")", false);
                Console.WriteLine(ex.StackTrace);
            }
            Console.WriteLine("driver: " + pass + " passed, " + fail + " failed");
            return fail > 0 ? 1 : 0;
        }
    }
}
'@

Yes 'the Build Tools csc the launcher builds with is on this machine' (Test-Path -LiteralPath $LauncherCsc)
if (-not (Test-Path -LiteralPath $LauncherCsc)) { Done }
$fw = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
$refDir = Join-Path ${env:ProgramFiles(x86)} 'Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8.1'
$refs = @()
foreach ($n in $LauncherNeeded) {
    $hit = @((Join-Path $refDir $n), (Join-Path $fw $n), (Join-Path $fw ('WPF\' + $n))) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($hit) { $refs += $hit }
}
$real = @('OwnGame.cs', 'OwnGameShare.cs', 'OwnGameKinds.cs', 'Downgrade.cs', 'Steam.cs', 'Paths.cs', 'Config.cs', 'Secrets.cs', 'LoadOrder.cs', 'Swallow.cs', 'Progress.cs', 'DevBuild.cs') |
    ForEach-Object { Join-Path $App $_ }
$real += @((Join-Path $Tool 'ShipRoot.cs'), (Join-Path $Tool 'OwnGameShipRoot.cs'))
foreach ($f in $real) { Yes ("$([IO.Path]::GetFileName($f)) is there") (Test-Path -LiteralPath $f) }
$stubFile = Join-Path $work 'Stubs.cs'
$driverFile = Join-Path $work 'Driver.cs'
[IO.File]::WriteAllText($stubFile, $stubs, $utf8)
[IO.File]::WriteAllText($driverFile, $driver, $utf8)
$skyrimList = Join-Path $work 'skyrim-files.json'
[IO.File]::WriteAllText($skyrimList, ("{`n  ""build"": ""1.6.1170"",`n  ""files"": {`n" +
    '    "SkyrimSE.exe": { "bytes": 37157144, "sha1": "0", "depot": "1" },' + "`n" +
    '    "Data\\Skyrim.esm": { "bytes": 10, "sha1": "0", "depot": "1" }' + "`n  }`n}`n"), $utf8)
$exe = Join-Path $work 'ship-root-test.exe'
$cscArgs = @('/noconfig', '/nologo', '/target:exe', '/warn:0', "/langversion:$LauncherLangVersion", '/main:Thornswood.ShipRootTest', "/out:$exe",
             "/resource:$skyrimList,skyrim-files.json", ("/resource:" + (Join-Path $Here 'records\ui-gone.json') + ",ui-gone.json"))
foreach ($r in $refs) { $cscArgs += "/reference:$r" }
foreach ($f in $real) { $cscArgs += (Resolve-Path -LiteralPath $f).Path }
$cscArgs += $stubFile, $driverFile
$old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
$compiled = & $LauncherCsc @cscArgs 2>&1
$ErrorActionPreference = $old
$built = ($LASTEXITCODE -eq 0) -and (Test-Path -LiteralPath $exe)
Yes 'the ship root tool compiles with the real OwnGame and the driver' $built
if ($built) {
    $scene = Join-Path $work 'machine'
    $null = New-Item -ItemType Directory -Force -Path $scene
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $out = & $exe $scene 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $old
    foreach ($l in @($out)) {
        $s = [string]$l
        if ($s.StartsWith('PASS  ')) { $script:pass++; Write-Host $s }
        elseif ($s.StartsWith('FAIL  ')) { $script:fail++; Write-Host $s }
        else { Write-Host $s }
    }
    Yes 'the driver finished and agrees' ($code -eq 0)
} else { foreach ($l in @($compiled)) { Write-Host "      $l" } }

# ============================================== 2. Where.ps1 and where.js ====
$repo = Join-Path $work 'repo'
New-Item -ItemType Directory -Force -Path (Join-Path $repo 'scripts\release'), (Join-Path $repo 'records') | Out-Null
foreach ($n in 'Where.ps1', 'where.js', 'Update-ShipRoot.ps1', 'Sync-Client.ps1', 'RecordShape.ps1', 'Read-JsonFile.ps1', 'Get-ScratchDir.ps1', 'Find-MSBuild.ps1') {
    Copy-Item -LiteralPath (Join-Path $Release $n) -Destination (Join-Path $repo 'scripts\release')
}
Copy-Item -LiteralPath (Join-Path $Here 'layout.json') -Destination $repo
$env:LOCALAPPDATA = Join-Path $work 'localappdata'
New-Item -ItemType Directory -Force -Path $env:LOCALAPPDATA | Out-Null
$w = Join-Path $repo 'scripts\release\Where.ps1'
$wj = Join-Path $repo 'scripts\release\where.js'
function Same([string]$a, [string]$b) { return $a -and $b -and ([IO.Path]::GetFullPath($a).TrimEnd('\') -eq [IO.Path]::GetFullPath($b).TrimEnd('\')) }
function AskJs([string]$what) { $o = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; try { return [string](& node $wj $what 2>&1) } finally { $ErrorActionPreference = $o } }
$engine = Join-Path $repo 'engine\skymp'
Yes '2. with no record, ClientDist is the checkout''s engine\skymp build' (Same (& $w ClientDist) (Join-Path $engine 'build\dist\client'))
Yes '2.   and ServerDist too' (Same (& $w ServerDist) (Join-Path $engine 'build\dist\server'))
Yes '2.   and EngineBuild is Engine' (Same (& $w EngineBuild) $engine)
Yes '2.   EngineBuilds is this machine''s own data, beside ship-roots.json' (Same (& $w EngineBuilds) (Join-Path $env:LOCALAPPDATA 'Thornswood\engine-build.json'))
$fork = Join-Path $work 'worktrees\skymp-built'
New-Item -ItemType Directory -Force -Path (Join-Path $fork 'build\dist\client'), (Join-Path $fork 'build\dist\server') | Out-Null
$setup = Join-Path $Release 'Setup-ShipMachine.ps1'
$ast = [System.Management.Automation.Language.Parser]::ParseFile($setup, [ref]$null, [ref]$null)
$fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Save-EngineBuild' }, $true)
Yes '4. Setup-ShipMachine.ps1 has Save-EngineBuild' ([bool]$fn)
if ($fn) { . ([scriptblock]::Create($fn.Extent.Text)) }
$recFile = Join-Path $env:LOCALAPPDATA 'Thornswood\engine-build.json'
$noBuild = Join-Path $work 'worktrees\skymp-never-built'
New-Item -ItemType Directory -Force -Path $noBuild | Out-Null
$why = Save-EngineBuild $recFile $noBuild
Yes '4. Save-EngineBuild refuses a fork folder with no build in it, and writes nothing' ($why -match 'no build\\dist' -and -not (Test-Path -LiteralPath $recFile))
$why = Save-EngineBuild $recFile $fork
Yes '4. and records one that has a build' (-not $why -and (Test-Path -LiteralPath $recFile))
Yes '2. with the record, ClientDist is the recorded fork''s build, not the checkout''s' (Same (& $w ClientDist) (Join-Path $fork 'build\dist\client'))
Yes '2.   and ServerDist, ServerSettings and ChangeForms are under it too' (
    (Same (& $w ServerDist) (Join-Path $fork 'build\dist\server')) -and (Same (& $w ServerSettings) (Join-Path $fork 'build\dist\server\server-settings.json')) -and
    (Same (& $w ChangeForms) (Join-Path $fork 'build\dist\server\world\changeForms')))
Yes '2.   and where.js says the same' ((Same (AskJs ClientDist).Trim() (& $w ClientDist)) -and (Same (AskJs ServerDist).Trim() (& $w ServerDist)))
[IO.File]::WriteAllText($recFile, (ConvertTo-Json -InputObject ([ordered]@{ fork = $noBuild })), $utf8)
$threw = ''
try { & $w ClientDist | Out-Null } catch { $threw = $_.Exception.Message }
Yes '2. a record naming a fork with no build stops with a sentence, and does not fall back' ($threw -match 'no build\\dist in it' -and $threw -match 'Setup-ShipMachine\.ps1 -EngineBuild')
Yes '2.   and where.js stops too' ((AskJs ClientDist) -match 'no build\\dist')
[IO.File]::WriteAllText($recFile, (ConvertTo-Json -InputObject ([ordered]@{ fork = $fork })), $utf8)

# ===================================================== 3. Update-ShipRoot ====
# A record of two client files, the recorded build in the fork, and a ship
# root whose game folder holds an old copy of one of them under a second name.
$cA = 'Data\SKSE\Plugins\MpClientPlugin.dll'; $cB = 'Data\Platform\Plugins\skymp5-client.js'
function Sha([string]$t) { return ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($utf8.GetBytes($t))) -replace '-', '').ToLowerInvariant() }
$record = [ordered]@{ recordedUtc = '2026-10-16T02:29:34Z'; fork = 'x'; forkBranch = 'thornswood/engine-changes'; forkCommit = '3bdf3d3c'; files = [ordered]@{
    $cA = [ordered]@{ sha256 = (Sha 'CLIENT-A-NEW'); bytes = 12 }; $cB = [ordered]@{ sha256 = (Sha 'CLIENT-B-NEW'); bytes = 12 } } }
[IO.File]::WriteAllText((Join-Path $repo 'records\client-build.json'), (ConvertTo-Json -InputObject $record -Depth 5), $utf8)
$shipRoot = Join-Path $work 'repo\local\release-devbuild'
$elsewhere = Join-Path $work 'other-install\Game'
foreach ($p in @((Join-Path $fork ('build\dist\client\' + $cA)), (Join-Path $elsewhere $cA))) { New-Item -ItemType Directory -Force -Path (Split-Path -Parent $p) | Out-Null }
[IO.File]::WriteAllText((Join-Path $elsewhere $cA), 'CLIENT-A-OLD', $utf8)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent (Join-Path $shipRoot ('Game\' + $cA))) | Out-Null
$null = New-Item -ItemType HardLink -Path (Join-Path $shipRoot ('Game\' + $cA)) -Target (Join-Path $elsewhere $cA)
$standIn = Join-Path $work 'stand-in-tool.ps1'
[IO.File]::WriteAllText($standIn, @'
param([string]$Root, [string]$Channel, [switch]$Check)
[IO.File]::AppendAllText($env:TS_TOOL_CALLS, "tool -Root $Root -Channel $Channel" + $(if ($Check) { ' -Check' } else { '' }) + "`r`n")
if ($env:TS_TOOL_EXIT -eq '1') { Write-Output 'STOP. stand-in: the game folder was made from another folder.'; exit 1 }
Write-Output '  stand-in: current.'
exit 0
'@, $utf8)
$env:TS_TOOL_CALLS = Join-Path $work 'tool-calls.txt'
$up = Join-Path $repo 'scripts\release\Update-ShipRoot.ps1'
$ps = (Get-Process -Id $PID).Path
function Up([string[]]$more) {
    $o = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $t = & $ps -NoProfile -ExecutionPolicy Bypass -File $up -Channel dev -Root $shipRoot -Tool $standIn -NoPause @more 2>&1 | Out-String; return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $t } }
    finally { $ErrorActionPreference = $o }
}
$env:TS_TOOL_EXIT = '1'
$r = Up @()
Yes ("3. a tool that refuses stops Update-ShipRoot.ps1 (exit {0}), naming why" -f $r.Code) ($r.Code -eq 1 -and $r.Out -match 'not current with Vortex''s deployment, so nothing is packed from it: stand-in: the game folder was made from another folder')
Yes '3.   before any client file is touched' ([IO.File]::ReadAllText((Join-Path $shipRoot ('Game\' + $cA))) -eq 'CLIENT-A-OLD')
Yes '3.   and the tool was asked about the channel''s root' (([IO.File]::ReadAllText($env:TS_TOOL_CALLS)) -match [regex]::Escape("tool -Root $shipRoot -Channel dev"))
$env:TS_TOOL_EXIT = '0'
[IO.File]::WriteAllText((Join-Path $fork ('build\dist\client\' + $cA)), 'CLIENT-A-NEW', $utf8)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent (Join-Path $fork ('build\dist\client\' + $cB))) | Out-Null
[IO.File]::WriteAllText((Join-Path $fork ('build\dist\client\' + $cB)), 'CLIENT-B-STALE', $utf8)
$r = Up @()
Yes ("3. an engine build that is not the record stops it (exit {0})" -f $r.Code) ($r.Code -eq 1 -and $r.Out -match 'could not be put into' -and $r.Out -match 'not the recorded one')
Yes '3.   and nothing was copied' ([IO.File]::ReadAllText((Join-Path $shipRoot ('Game\' + $cA))) -eq 'CLIENT-A-OLD')
[IO.File]::WriteAllText((Join-Path $fork ('build\dist\client\' + $cB)), 'CLIENT-B-NEW', $utf8)
$r = Up @()
Yes ("3. with the recorded build in the recorded fork, it ends current (exit {0})" -f $r.Code) ($r.Code -eq 0 -and $r.Out -match 'is current, with the recorded client in it')
Yes '3.   the root holds the recorded client' (
    [IO.File]::ReadAllText((Join-Path $shipRoot ('Game\' + $cA))) -eq 'CLIENT-A-NEW' -and [IO.File]::ReadAllText((Join-Path $shipRoot ('Game\' + $cB))) -eq 'CLIENT-B-NEW')
Yes '3.   and the file it replaced kept its other name''s bytes: nothing was written through the hard link' ([IO.File]::ReadAllText((Join-Path $elsewhere $cA)) -eq 'CLIENT-A-OLD')
$r = Up @('-Check')
Yes '3. -Check asks the tool with -Check and changes nothing' ($r.Code -eq 0 -and ([IO.File]::ReadAllText($env:TS_TOOL_CALLS)) -match '-Channel dev -Check')

# ============================================================= 4. Ship.ps1 ====
$shipText = [IO.File]::ReadAllText((Join-Path $Release 'Ship.ps1'))
$callAt = $shipText.IndexOf("& (Join-Path `$Here 'Update-ShipRoot.ps1') -Channel `$Channel -Root `$Root -NoPause")
Yes '4. Ship.ps1 runs Update-ShipRoot.ps1 for the channel''s root' ($callAt -ge 0)
$rootAt = $shipText.IndexOf("Where.ps1') `$(if (`$Dev) { 'ShipRootDev' } else { 'ShipRoot' })")
$vortexAt = $shipText.IndexOf("is a folder Vortex deploys into (Game\Data\vortex.deployment.json is there), so a release is never built from it")
$versionAt = $shipText.IndexOf('# ------------------------------------------------------------ version')
$genAt = $shipText.IndexOf("Head 'Generated files'")
$buildAt = $shipText.IndexOf("Head 'Building the launcher'")
Yes '4.   after it knows the root and has refused a folder Vortex deploys into' ($rootAt -ge 0 -and $vortexAt -ge 0 -and $callAt -gt $rootAt -and $callAt -gt $vortexAt)
Yes '4.   and before the version moves, the generated files are read or the launcher is built' ($callAt -lt $versionAt -and $callAt -lt $genAt -and $callAt -lt $buildAt)
Yes '4.   and it stops when the root is not current' ($shipText -match "(?s)Update-ShipRoot\.ps1'\) -Channel \`$Channel -Root \`$Root -NoPause\s*if \(\`$LASTEXITCODE -ne 0\) \{\s*Die \(")
}
finally {
    $env:LOCALAPPDATA = $oldLocal
    Remove-Item Env:TS_TOOL_CALLS, Env:TS_TOOL_EXIT -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
Done
