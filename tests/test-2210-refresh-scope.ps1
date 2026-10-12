<#
  test-2210-refresh-scope.ps1

      pwsh -NoProfile -File .\tests\test-2210-refresh-scope.ps1

  Issue #2210. "Preparing the game folder" walked every file in the folder
  whatever had moved. A launcher update that raised OwnGame.Rules made every
  install walk all thirty thousand files once, though rules 14, 15 and 16 are
  each about one plugin or the client's page folder. And for every file it did
  not change, the walk asked Windows how many names the file has up to three
  times.

  WHAT IT HOLDS THE LAUNCHER TO.
    1. RulesScope: a folder behind only on rules that name their paths in
       RuleTouches looks at those paths; one older than 14, or on the current
       rules, has no scope, so it is walked whole.
    2. A refresh when Vortex has not deployed since and only the rules moved
       (15 to 16): a file under Data\Platform\UI that the new rules leave out
       is taken out; every file outside that path keeps its line of the
       record exactly, and is not touched, even one whose record is out of
       date or that has a second name; what was left out before outside the
       path stays on left-out.txt; made.txt is on the current rules after it;
       and the log line says what it looked at and how long it took.
    3. The same folder on rules 12 (before the three kinds), or one Vortex has
       deployed into since: the whole folder is walked. A file the folder
       keeps as its own copy that has a second name is its own copy again, a
       Distribution redistributable the folder held as a copy is a hard link
       again, and the line says every file was looked at and why the copies
       had another name.
    4. Every number from 14 to the current Rules has a line in RuleTouches, so
       raising Rules without saying what the rule is about fails here.

  HOW. As test-own-folder-alone.ps1: the shipped OwnGame.cs and the files it
  needs, compiled with the .NET Framework csc the launcher builds with (C# 5),
  stand-ins for Checks, Keep, Updater and Junction, and a driver that builds a
  pretend Steam, Steam copy and Vortex in a scratch folder.

  Nothing outside its own scratch folder is read or written.
#>
[CmdletBinding()]
param([string]$AppPath, [string]$Scratch)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Here = Split-Path -Parent $Here
if (-not $AppPath) { $AppPath = Join-Path $Here 'launcher\app' }
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

# ---- 4: every rule from 14 on says what it is about --------------------------
$og = [IO.File]::ReadAllText((Join-Path $AppPath 'OwnGame.cs'))
$rulesNum = [regex]::Match($og, '(?m)^\s*const int Rules = (\d+);')
Yes 'OwnGame.Rules is there' $rulesNum.Success
if (-not $rulesNum.Success) { Done }
$touches = [regex]::Match($og, '(?s)static readonly Dictionary<int, string\[\]> RuleTouches = new Dictionary<int, string\[\]>\s*\{(.*?)\};')
Yes 'RuleTouches is there' $touches.Success
$missing = @()
for ($n = 14; $n -le [int]$rulesNum.Groups[1].Value; $n++) {
    if (-not $touches.Success -or $touches.Groups[1].Value -notmatch ('\{\s*' + $n + '\s*,')) { $missing += $n }
}
Yes ("every rule from 14 to " + $rulesNum.Groups[1].Value + " has a line in RuleTouches (null walks everything)" + $(if ($missing) { '; missing: ' + ($missing -join ', ') } else { '' })) ($missing.Count -eq 0)

$csc = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
Yes 'the .NET Framework csc the launcher builds with is on this machine' ([bool]$csc)
if (-not $csc) { Done }
$fw = Split-Path -Parent $csc
$refs = @('System.dll', 'System.Core.dll', 'System.Runtime.Serialization.dll', 'System.Xml.dll', 'System.Security.dll') |
    ForEach-Object { Join-Path $fw $_ }
# Downgrade.cs puts a line on the clipboard through WPF, found the way
# Build-Launcher.ps1 and test-own-folder-alone.ps1 find it.
$refDirs = @(Get-ChildItem -Path "${env:ProgramFiles(x86)}\Reference Assemblies\Microsoft\Framework\.NETFramework" -Directory -Filter 'v4.*' -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | ForEach-Object { $_.FullName }) + @((Join-Path $fw 'WPF'), $fw)
foreach ($n in 'PresentationCore.dll', 'WindowsBase.dll', 'PresentationFramework.dll', 'System.Xaml.dll') {
    $hit = $refDirs | ForEach-Object { Join-Path $_ $n } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $hit) {
        $hit = Get-ChildItem (Join-Path $env:WINDIR 'Microsoft.NET\assembly') -Filter $n -Recurse -File -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending | Select-Object -First 1 | ForEach-Object { $_.FullName }
    }
    $refs += $(if ($hit) { $hit } else { Join-Path $fw $n })
}

$real = @('OwnGame.cs', 'OwnGameShare.cs', 'OwnGameKinds.cs', 'Downgrade.cs', 'Steam.cs', 'Paths.cs', 'Config.cs', 'Secrets.cs', 'LoadOrder.cs', 'Swallow.cs', 'Progress.cs') |
    ForEach-Object { Join-Path $AppPath $_ }
foreach ($f in $real) { if (-not (Test-Path -LiteralPath $f)) { Yes "launcher\app\$([IO.Path]::GetFileName($f)) is there" $false; Done } }

$stubs = @'
using System;
using System.Collections.Generic;

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
        public static string Dir { get { return System.IO.Path.Combine(Paths.ProfileDir, "Keep"); } }
    }
    static class Updater
    {
        public static bool ReleaseFilesKnown() { return true; }
        public static List<string> ReleaseFiles() { return new List<string>(); }
    }
    static class Junction { public static bool IsLink(string p) { return false; } }
}
'@

$driver = @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace Thornswood
{
    static class RefreshScopeTest
    {
        static int pass, fail;
        static void Yes(string what, bool cond)
        {
            Console.WriteLine((cond ? "PASS  " : "FAIL  ") + what);
            if (cond) pass++; else fail++;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct Info
        {
            public uint Attributes;
            public System.Runtime.InteropServices.ComTypes.FILETIME C, A, W;
            public uint Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
        }
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool GetFileInformationByHandle(SafeFileHandle h, out Info info);
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool CreateHardLink(string newName, string existing, IntPtr security);

        static Info Of(string path)
        {
            using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            {
                Info i;
                GetFileInformationByHandle(fs.SafeFileHandle, out i);
                return i;
            }
        }
        static int Names(string path) { return (int)Of(path).Links; }
        static string Id(string path) { Info i = Of(path); return i.Volume + ":" + i.IndexHigh + ":" + i.IndexLow; }

        const int ExeBytes = 4096, NewerExeBytes = 5000;
        static string T;

        static void Put(string path, string text)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            File.WriteAllText(path, text, new UTF8Encoding(false));
        }

        static void Archive(string path, string mark)
        {
            var b = new byte[64 * 1024];
            byte[] m = Encoding.ASCII.GetBytes(mark);
            Array.Copy(m, b, m.Length);
            for (int i = m.Length + 1; i < b.Length; i++) b[i] = (byte)(1 + i % 250);
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            File.WriteAllBytes(path, b);
        }

        static void Exe(string path, string mark, int size)
        {
            var b = new byte[size];
            byte[] m = Encoding.ASCII.GetBytes(mark);
            Array.Copy(m, b, m.Length);
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            File.WriteAllBytes(path, b);
        }

        static string J(string s) { return s.Replace("\\", "\\\\").Replace("\"", "\\\""); }

        class Scene
        {
            public string Dir, Steam, Game, Staging, Ts;
            public Config Cfg;
        }

        static readonly string Tex = "Data\\Skyrim - Textures0.bsa", Mesh = "Data\\Skyrim - Meshes0.bsa";
        static readonly string Master = "Data\\Skyrim.esm", Loose = "Data\\Video\\BGS_Logo.bik";

        // Vortex's files: a plugin and a texture (linked), a Nemesis patch
        // (.txt, kept as the folder's own copy), a redistributable under
        // Data\Platform\Distribution (linked though it is a .dll), and a file
        // of another menu under Data\Platform\UI that the rules leave out.
        static readonly string[][] Files = {
            new string[] { "TsOne.esp", "ModA", "VORTEX-TSONE" },
            new string[] { "textures\\ts\\wood.dds", "ModA", "VORTEX-DDS" },
            new string[] { "Nemesis_Engine\\mod\\tdm\\patch.txt", "ModN", "NEMESIS-PATCH" },
            new string[] { "Platform\\Distribution\\libcef.dll", "ModD", "VORTEX-CEF" },
            new string[] { "Platform\\UI\\app.js", "ModU", "OTHER-MENU" },
        };

        static Scene NewScene(string name)
        {
            var s = new Scene();
            s.Dir = Path.Combine(T, name);
            s.Steam = Path.Combine(s.Dir, "steam");
            s.Staging = Path.Combine(s.Dir, "vortex\\mods");
            s.Ts = Path.Combine(s.Dir, "Thornswood");
            s.Game = Path.Combine(s.Steam, "steamapps\\common\\Skyrim Special Edition");
            Put(Path.Combine(s.Steam, "config\\libraryfolders.vdf"),
                "\"libraryfolders\"\n{\n\t\"0\"\n\t{\n\t\t\"path\"\t\t\"" + J(s.Steam) + "\"\n\t}\n}\n");
            Steam.RootForTest = s.Steam;

            Paths.Root = s.Ts;
            Paths.LauncherDir = Path.Combine(s.Ts, "Launcher");
            Paths.ProfileDir = Path.Combine(s.Ts, "Profile");
            Paths.MyGames = Path.Combine(Paths.ProfileDir, "MyGames");
            Paths.LocalAD = Path.Combine(Paths.ProfileDir, "LocalAppData");
            Paths.Golden = Path.Combine(Paths.ProfileDir, "Default");
            Paths.Personal = Path.Combine(s.Ts, "Your Mods");
            Paths.Isolated = Path.Combine(Paths.ProfileDir, "Isolated");
            Paths.Replaced = Path.Combine(Paths.ProfileDir, "Replaced");
            Paths.StateFile = Path.Combine(Paths.ProfileDir, "swap.json");
            Paths.PlayedFile = Path.Combine(Paths.ProfileDir, "played.flag");
            Paths.AppliedFile = Path.Combine(Paths.ProfileDir, "applied.txt");
            Paths.PacksDir = Path.Combine(Paths.ProfileDir, "Packs");
            Paths.LogFile = Path.Combine(Paths.ProfileDir, "launcher.log");
            Paths.CfgFile = Path.Combine(s.Ts, "config.json");
            Paths.WinMyGames = Path.Combine(s.Dir, "windows\\My Games\\Skyrim Special Edition");
            Paths.WinLocalAD = Path.Combine(s.Dir, "windows\\LocalAppData\\Skyrim Special Edition");
            Paths.Collection = true;
            Paths.Game = s.Game;
            Paths.SteamCopy = s.Game;
            Paths.Payload = Path.Combine(Paths.ProfileDir, "Payload");
            Paths.OwnFirst = false;
            Paths.Live = Paths.WinLocalAD;
            Paths.LiveMyGames = Paths.WinMyGames;
            Directory.CreateDirectory(Paths.ProfileDir);
            string list = "# Automatically generated by Vortex\r\n*TsOne.esp\r\n";
            Put(Path.Combine(Paths.Golden, "plugins.txt"), list);
            Put(Path.Combine(Paths.WinLocalAD, "plugins.txt"), list);

            s.Cfg = new Config();
            s.Cfg.ServerAddress = "";
            s.Cfg.ExpectedExeBytes = ExeBytes;
            s.Cfg.NewerExeBytes = NewerExeBytes;
            s.Cfg.VortexGame = "";

            Exe(Path.Combine(s.Game, "SkyrimSE.exe"), "PIN-EXE", ExeBytes);
            Put(Path.Combine(s.Game, Master), "PIN-MASTER");
            Archive(Path.Combine(s.Game, Tex), "PIN-TEX0");
            Archive(Path.Combine(s.Game, Mesh), "PIN-MESH0");
            Put(Path.Combine(s.Game, Loose), "GAME-LOOSE");
            Put(Path.Combine(s.Game, "bink2w64.dll"), "GAME-BINK");
            Deploy(s, DateTime.UtcNow.AddMinutes(-10));
            return s;
        }

        static void Deploy(Scene s, DateTime when)
        {
            var sb = new StringBuilder();
            sb.Append("{\n  \"instance\": \"test\",\n  \"version\": 1,\n  \"deploymentMethod\": \"hardlink_activator\",\n  \"gameId\": \"skyrimse\",\n");
            sb.Append("  \"stagingPath\": \"" + J(s.Staging) + "\",\n  \"targetPath\": \"" + J(Path.Combine(s.Game, "Data")) + "\",\n  \"files\": [\n");
            for (int i = 0; i < Files.Length; i++)
            {
                string staged = Path.Combine(s.Staging, Files[i][1] + "\\" + Files[i][0]);
                if (!File.Exists(staged)) Put(staged, Files[i][2]);
                string at = Path.Combine(s.Game, "Data\\" + Files[i][0]);
                if (!File.Exists(at)) { Directory.CreateDirectory(Path.GetDirectoryName(at)); CreateHardLink(at, staged, IntPtr.Zero); }
                sb.Append("    { \"relPath\": \"" + J(Files[i][0]) + "\", \"source\": \"" + J(Files[i][1]) + "\", \"target\": \"\", \"time\": 1 }" + (i + 1 < Files.Length ? "," : "") + "\n");
            }
            sb.Append("  ]\n}\n");
            string rec = Path.Combine(s.Game, "Data\\vortex.deployment.json");
            Put(rec, sb.ToString());
            File.SetLastWriteTimeUtc(rec, when);
        }

        static void MadeNowRuns()
        {
            Paths.Collection = false;
            Paths.Game = OwnGame.Folder;
            Paths.Live = Paths.LocalAD;
            Paths.LiveMyGames = Paths.MyGames;
        }

        static string FilesTxt { get { return Path.Combine(OwnGame.Dir, "files.txt"); } }
        static string LeftOutTxt { get { return Path.Combine(OwnGame.Dir, "left-out.txt"); } }
        static string MadeTxt { get { return Path.Combine(OwnGame.Dir, "made.txt"); } }

        static Dictionary<string, string> Record()
        {
            var d = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (string l in File.ReadAllLines(FilesTxt))
            {
                string[] p = l.Split(new char[] { '|' }, 5);
                if (p.Length == 5) d[p[4]] = l;
            }
            return d;
        }

        static void SetRecorded(string key, string value)
        {
            var lines = new List<string>();
            foreach (string l in File.ReadAllLines(MadeTxt)) lines.Add(l.StartsWith(key + "=") ? key + "=" + value : l);
            File.WriteAllLines(MadeTxt, lines.ToArray());
        }

        static string Recorded(string key)
        {
            foreach (string l in File.ReadAllLines(MadeTxt)) if (l.StartsWith(key + "=")) return l.Substring(key.Length + 1);
            return null;
        }

        static readonly string Patch = "Data\\Nemesis_Engine\\mod\\tdm\\patch.txt", Wood = "Data\\textures\\ts\\wood.dds",
                               Cef = "Data\\Platform\\Distribution\\libcef.dll", Menu = "Data\\Platform\\UI\\app.js";

        // A folder made, then put in the shape one made under older rules
        // would be in: the other menu's file in it and on record, the Nemesis
        // patch with a second name in another folder (a release folder made by
        // hard linking this one), the redistributable as a copy of its own, a
        // record line out of date, and a line on left-out.txt outside UI.
        static Scene Prepared(string name, string rules)
        {
            Scene s = NewScene(name);
            string made = null;
            try { made = OwnGame.Make(s.Cfg, null); } catch (Exception ex) { Console.WriteLine("      Make said: " + ex.Message); }
            MadeNowRuns();
            string own = OwnGame.Folder;
            Yes("(" + name + ": made)", made != null && Directory.Exists(own));
            Yes("(" + name + ": the rules leave the other menu's file out at Make)", !File.Exists(Path.Combine(own, Menu)));

            var fi = new FileInfo(Path.Combine(s.Staging, "ModU\\Platform\\UI\\app.js"));
            Put(Path.Combine(own, Menu), "OTHER-MENU");
            var rec = new List<string>(File.ReadAllLines(FilesTxt));
            rec.Add("C|V|" + fi.Length + "|" + fi.LastWriteTimeUtc.Ticks + "|" + Menu);
            for (int i = 0; i < rec.Count; i++)
                if (rec[i].EndsWith("|" + Wood)) { string[] p = rec[i].Split('|'); rec[i] = p[0] + "|" + p[1] + "|" + p[2] + "|1|" + Wood; }
            File.WriteAllLines(FilesTxt, rec.ToArray());

            string clone = Path.Combine(s.Dir, "release\\Game\\" + Patch);
            Directory.CreateDirectory(Path.GetDirectoryName(clone));
            CreateHardLink(clone, Path.Combine(own, Patch), IntPtr.Zero);

            string cef = Path.Combine(own, Cef);
            DateTime t = File.GetLastWriteTimeUtc(cef);
            byte[] b = File.ReadAllBytes(cef);
            File.Delete(cef);
            File.WriteAllBytes(cef, b);
            File.SetLastWriteTimeUtc(cef, t);

            File.AppendAllText(LeftOutTxt, "Data\\Elsewhere\\old.esp  (an old reason)\r\n");
            SetRecorded("rules", rules);
            Yes("(" + name + ": the patch has a second name, the redistributable is a copy)", Names(Path.Combine(own, Patch)) == 2 && Names(cef) == 1);
            return s;
        }

        static void Scoped()
        {
            Scene s = Prepared("scoped", "15");
            string own = OwnGame.Folder;
            Dictionary<string, string> before = Record();
            Yes("a folder on rules 15 that Vortex has not deployed into since asks for a refresh", OwnGame.NeedsRefresh(s.Cfg));
            string said = null;
            try { said = OwnGame.Refresh(s.Cfg, null); } catch (Exception ex) { Console.WriteLine("      Refresh said: " + ex.Message); }
            if (said != null) Console.WriteLine("      Refresh said: " + said);
            Yes("the refresh works", said != null);
            Yes("the other menu's file under Data\\Platform\\UI, which the new rules leave out, is taken out", !File.Exists(Path.Combine(own, Menu)) && !Record().ContainsKey(Menu));
            Yes("and left-out.txt says why", File.ReadAllText(LeftOutTxt).Contains(Menu + "  ("));
            Dictionary<string, string> after = Record();
            bool same = true;
            foreach (KeyValuePair<string, string> kv in before)
            {
                if (kv.Key.Equals(Menu, StringComparison.OrdinalIgnoreCase)) continue;
                string now;
                if (!after.TryGetValue(kv.Key, out now) || now != kv.Value) { same = false; Console.WriteLine("      moved: " + kv.Value + " -> " + now); }
            }
            Yes("every other line of the record is carried forward exactly, the out of date one included", same && after.Count == before.Count - 1);
            Yes("the Nemesis patch outside the path was not touched: it still has its second name", Names(Path.Combine(own, Patch)) == 2);
            Yes("the redistributable outside the path was not touched: still a copy", Names(Path.Combine(own, Cef)) == 1);
            Yes("what was left out before outside the path is still on left-out.txt", File.ReadAllText(LeftOutTxt).Contains("Data\\Elsewhere\\old.esp  (an old reason)"));
            Yes("made.txt is on the current rules, so it does not ask again", Recorded("rules") == RulesNow() && !OwnGame.NeedsRefresh(s.Cfg));
            Yes("the line says what it looked at, why, and how long it took",
                said != null && said.Contains("looking only at Data\\Platform\\UI\\") && said.Contains("only the rules about those changed") && said.Contains("It took "));
        }

        static void Whole(string name, string rules, bool deploy)
        {
            Scene s = Prepared(name, rules);
            string own = OwnGame.Folder;
            if (deploy) Deploy(s, DateTime.UtcNow);
            string said = null;
            try { said = OwnGame.Refresh(s.Cfg, null); } catch (Exception ex) { Console.WriteLine("      Refresh said: " + ex.Message); }
            if (said != null) Console.WriteLine("      Refresh said: " + said);
            string why = deploy ? "Vortex deployed since" : "rules " + rules;
            Yes(name + " (" + why + "): the whole folder is walked", said != null && said.Contains("looking at every file"));
            Yes(name + ": the other menu's file is taken out", !File.Exists(Path.Combine(own, Menu)));
            Yes(name + ": the Nemesis patch is the folder's own copy again, and the other folder keeps its own", Names(Path.Combine(own, Patch)) == 1 &&
                File.ReadAllText(Path.Combine(own, Patch)) == "NEMESIS-PATCH");
            Yes(name + ": the line says the copies had another name", said != null && said.Contains("had another name") && !said.Contains("animation file"));
            Yes(name + ": the redistributable is a hard link to Vortex's again",
                Id(Path.Combine(own, Cef)) == Id(Path.Combine(s.Staging, "ModD\\Platform\\Distribution\\libcef.dll")));
            string woodLine;
            Yes(name + ": the out of date record line is read again from Vortex's file", Record().TryGetValue(Wood, out woodLine) && !woodLine.Contains("|1|" + Wood));
            Yes(name + ": the record says L or C as the disk holds it",
                Record()[Patch].StartsWith("C|") && Record()[Cef].StartsWith("L|") && Record()["Data\\TsOne.esp"].StartsWith("L|"));
            Yes(name + ": made.txt is on the current rules", Recorded("rules") == RulesNow() && !OwnGame.NeedsRefresh(s.Cfg));
        }

        static string RulesNow()
        {
            return Convert.ToString(typeof(OwnGame).GetField("Rules", BindingFlags.NonPublic | BindingFlags.Static).GetValue(null));
        }

        static void Scope()
        {
            MethodInfo m = typeof(OwnGame).GetMethod("RulesScope", BindingFlags.NonPublic | BindingFlags.Static);
            Func<long, string[]> scope = delegate(long r) { return (string[])m.Invoke(null, new object[] { r }); };
            int now = int.Parse(RulesNow());
            Yes("on the current rules there is no scope", scope(now) == null);
            Yes("before rule 14 (rules 12) the whole folder is walked", scope(12) == null && scope(-1) == null);
            string[] from15 = scope(15);
            Yes("from 15 to 16 only Data\\Platform\\UI\\ is looked at", now != 16 || (from15 != null && from15.Length == 1 && from15[0] == "Data\\Platform\\UI\\"));
            string[] from13 = scope(13);
            Yes("from 13, Elysium Estate's old plugin and Data\\Platform\\UI\\, once each",
                now != 16 || (from13 != null && from13.Length == 2 && Array.IndexOf(from13, "Data\\ElysiumEstateSSE.esp") >= 0 && Array.IndexOf(from13, "Data\\Platform\\UI\\") >= 0));
        }

        static int Main(string[] args)
        {
            T = args[0];
            try
            {
                Scope();
                Scoped();
                Whole("rules-12", "12", false);
                Whole("deployed", "15", true);
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

$work = Join-Path $Scratch ('thornswood-2210-scope-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Force -Path $work
try {
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $stubFile = Join-Path $work 'Stubs.cs'
    $driverFile = Join-Path $work 'Driver.cs'
    [IO.File]::WriteAllText($stubFile, $stubs, $utf8)
    [IO.File]::WriteAllText($driverFile, $driver, $utf8)
    $exe = Join-Path $work 'refresh-scope-test.exe'
    # The pretend build's list, as in test-own-folder-alone.ps1: the bytes and
    # SHA-1 of what NewScene writes for 1.6.1170.
    $skyrimList = Join-Path $work 'skyrim-files.json'
    $listed = @(
        '    "SkyrimSE.exe": { "bytes": 4096, "sha1": "c6b7bc36797a26fa409a0f7fb3333c7cfc990e36", "depot": "1" }',
        '    "bink2w64.dll": { "bytes": 9, "sha1": "f9dcb7c51635e79d3438edc88a3848a2f25a85dd", "depot": "1" }',
        '    "Data\\Skyrim.esm": { "bytes": 10, "sha1": "f02c4781bceef74eed7a337c528c1599d9edd739", "depot": "1" }',
        '    "Data\\Skyrim - Textures0.bsa": { "bytes": 65536, "sha1": "8cf0fb06e3e8887913e498c016e1eed034a2a2a8", "depot": "1" }',
        '    "Data\\Skyrim - Meshes0.bsa": { "bytes": 65536, "sha1": "5536cf0719bc8c69629f9add1a961b58807ce022", "depot": "1" }',
        '    "Data\\Video\\BGS_Logo.bik": { "bytes": 10, "sha1": "b5c2432d19146126a033d65dcb4e3ce01d88cfff", "depot": "1" }'
    )
    [IO.File]::WriteAllText($skyrimList, "{`n  ""build"": ""1.6.1170"",`n  ""files"": {`n" + ($listed -join ",`n") + "`n  }`n}`n", $utf8)
    $uiGoneList = Join-Path $Here 'records\ui-gone.json'
    $cscArgs = @('/noconfig', '/nologo', '/target:exe', '/warn:0', "/out:$exe", "/resource:$skyrimList,skyrim-files.json", "/resource:$uiGoneList,ui-gone.json")
    foreach ($r in $refs) { $cscArgs += "/reference:$r" }
    foreach ($f in $real) { $cscArgs += (Resolve-Path -LiteralPath $f).Path }
    $cscArgs += $stubFile
    $cscArgs += $driverFile
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $compiled = & $csc @cscArgs 2>&1
    $ErrorActionPreference = $old
    $built = ($LASTEXITCODE -eq 0) -and (Test-Path -LiteralPath $exe)
    Yes 'the real OwnGame.cs compiles with the driver under the C# 5 compiler' $built
    if (-not $built) { foreach ($l in @($compiled)) { Write-Host "      $l" }; Done }

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
}
finally {
    try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction Stop } catch { }
}

Done
