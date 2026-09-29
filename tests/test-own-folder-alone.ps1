<#
  test-own-folder-alone.ps1

      pwsh -NoProfile -File .\tests\test-own-folder-alone.ps1

  Thornswood's own game folder stands on its own once it is made, and the
  Steam copy of Skyrim is never written. Issues #1218 and #1217.

  WHAT WAS WRONG, 29 September. Once C:\Thornswood\Game held a whole 1.6.1170
  game, a Steam update of the Steam copy still stopped every refresh from
  Vortex ("most likely because Steam updated it. Press Downgrade on the Play
  page first"), and the Downgrade then copied 1.6.1170 over the Steam copy
  (#1218). And 18 of Skyrim's archives, 13.2 GB, were in the folder as copies
  of their own, the same bytes as the Steam copy's (#1217). Patrick, 29 Sep:
  "it shouldn't be using Steam's now anyway, but this way people can play
  vanilla at whatever version and their own mods".

  WHAT THIS HOLDS THE LAUNCHER TO.
    1. A folder made from a Steam copy on 1.6.1170: the game's own files are
       the folder's own copies, Vortex's files are links, and Skyrim's archives
       are one file with the Steam copy's and on record with their SHA-256.
    2. The Steam copy then updated to a newer build (by moving new files in,
       the way Steam does), a mod put into it by hand, and Vortex deploying
       another file: no Downgrade is asked for, the refresh works, takes only
       Vortex's new file, and the folder keeps its 1.6.1170 exe, master and
       archives. The check before Play passes.
    3. A first setup from a Steam copy on a newer build: the folder cannot be
       made and the sentence says the Steam copy stays as it is and the
       Downgrade gets 1.6.1170's own files; once they are downloaded the folder
       is made from them, an archive the Steam copy has the same bytes of is
       shared, one it does not is a copy, and the download is cleared away.
    4. An archive shared with the Steam copy and written over there (a file
       copied over it, which writes through a hard link): the check before
       Play finds it, Play stays shut, the Downgrade card comes up, and the
       Downgrade's files put 1.6.1170's bytes back as a copy of the folder's
       own. With no folder of its own the Downgrade refuses to write anywhere.
    5. The Steam copy's files are byte for byte and time for time what they
       were around every one of those: Make, Refresh, Share, the check, and
       the Downgrade's files. And the launcher's source keeps it that way.

  HOW. It compiles the shipped launcher\app\OwnGame.cs, OwnGameShare.cs,
  Downgrade.cs, Steam.cs, Paths.cs and Config.cs with the .NET Framework csc
  Build-Launcher.ps1 uses (C# 5), with stand-ins for the few calls that touch
  the machine (Checks, Keep, Junction). A driver builds a pretend Steam, Steam
  copy and Vortex in a scratch folder, points Steam.cs at it through
  Steam.RootForTest, and runs the real code. Steam's console is never driven:
  the Downgrade's download is laid down as Steam leaves it.

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

$csc = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
Yes 'the .NET Framework csc the launcher builds with is on this machine' ([bool]$csc)
if (-not $csc) { Done }
$fw = Split-Path -Parent $csc
$refs = @('System.dll', 'System.Core.dll', 'System.Runtime.Serialization.dll', 'System.Xml.dll', 'System.Security.dll') |
    ForEach-Object { Join-Path $fw $_ }
# Downgrade.cs puts a line on the clipboard through WPF. Found the way
# Build-Launcher.ps1 finds it: the reference assemblies first, then the
# framework's own WPF folder, then the GAC.
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
foreach ($r in $refs) { Yes "$([IO.Path]::GetFileName($r)) is there to compile against" (Test-Path -LiteralPath $r) }

$real = @('OwnGame.cs', 'OwnGameShare.cs', 'Downgrade.cs', 'Steam.cs', 'Paths.cs', 'Config.cs', 'Secrets.cs', 'LoadOrder.cs', 'Swallow.cs', 'Progress.cs') |
    ForEach-Object { Join-Path $AppPath $_ }
foreach ($f in $real) {
    Yes "launcher\app\$([IO.Path]::GetFileName($f)) is there" (Test-Path -LiteralPath $f)
    if (-not (Test-Path -LiteralPath $f)) { Done }
}

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
    static class Keep { public static List<string> Held() { return new List<string>(); } }
    static class Junction { public static bool IsLink(string p) { return false; } }
}
'@

$driver = @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace Thornswood
{
    static class OwnFolderAloneTest
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

        static string Id(string path)
        {
            if (!File.Exists(path)) return "none:" + path;
            using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            {
                Info i;
                if (!GetFileInformationByHandle(fs.SafeFileHandle, out i)) return "?";
                return i.Volume + ":" + i.IndexHigh + ":" + i.IndexLow;
            }
        }

        const int ExeBytes = 4096, NewerExeBytes = 5000;
        static string T;

        static void Put(string path, string text)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            File.WriteAllText(path, text, new UTF8Encoding(false));
        }

        // An archive: its mark, a zero where Text stops reading, then padding,
        // so two builds can be the same size.
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

        static string Text(string path)
        {
            try
            {
                byte[] b = File.ReadAllBytes(path);
                int n = Array.IndexOf(b, (byte)0);
                return Encoding.ASCII.GetString(b, 0, n < 0 ? b.Length : n);
            }
            catch { return null; }
        }

        static string J(string s) { return s.Replace("\\", "\\\\").Replace("\"", "\\\""); }

        static void Record(string path, string staging, string target, string[][] files, DateTime when)
        {
            var sb = new StringBuilder();
            sb.Append("{\n  \"instance\": \"test\",\n  \"version\": 1,\n  \"deploymentMethod\": \"hardlink_activator\",\n  \"gameId\": \"skyrimse\",\n");
            sb.Append("  \"stagingPath\": \"" + J(staging) + "\",\n  \"targetPath\": \"" + J(target) + "\",\n  \"files\": [\n");
            for (int i = 0; i < files.Length; i++)
                sb.Append("    { \"relPath\": \"" + J(files[i][0]) + "\", \"source\": \"" + J(files[i][1]) + "\", \"target\": \"\", \"time\": 1 }" + (i + 1 < files.Length ? "," : "") + "\n");
            sb.Append("  ]\n}\n");
            Put(path, sb.ToString());
            File.SetLastWriteTimeUtc(path, when);
        }

        // Every file under a folder with its bytes and its write time.
        static Dictionary<string, string> Snap(string dir)
        {
            var d = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            if (!Directory.Exists(dir)) return d;
            using (var sha = SHA256.Create())
            {
                foreach (string f in Directory.GetFiles(dir, "*", SearchOption.AllDirectories))
                {
                    var fi = new FileInfo(f);
                    d[f.Substring(dir.Length)] = fi.Length + ":" + Convert.ToBase64String(sha.ComputeHash(File.ReadAllBytes(f))) + ":" + fi.LastWriteTimeUtc.Ticks + ":" + fi.Attributes;
                }
            }
            return d;
        }

        static bool Same(Dictionary<string, string> a, Dictionary<string, string> b)
        {
            if (a.Count != b.Count) return false;
            foreach (KeyValuePair<string, string> kv in a)
            {
                string v;
                if (!b.TryGetValue(kv.Key, out v) || v != kv.Value) return false;
            }
            return true;
        }

        static bool Clean(string said)
        {
            return said != null && said.IndexOf('\u2014') < 0 && said.IndexOf("player", StringComparison.OrdinalIgnoreCase) < 0;
        }

        // Steam puts an update in by building the new file under
        // steamapps\downloading and moving it over the old name (measured,
        // OwnGameShare.cs). The old file stays as it was for any other name.
        static void SteamUpdates(Scene s, string rel, Action<string> write)
        {
            string staged = Path.Combine(s.Steam, "steamapps\\downloading\\489830\\" + rel);
            write(staged);
            string at = Path.Combine(s.Game, rel);
            if (File.Exists(at)) File.Delete(at);
            Directory.CreateDirectory(Path.GetDirectoryName(at));
            File.Move(staged, at);
        }

        class Scene
        {
            public string Dir, Steam, Game, Staging, Ts;
            public Config Cfg;
        }

        static readonly string Tex = "Data\\Skyrim - Textures0.bsa", Mesh = "Data\\Skyrim - Meshes0.bsa";
        // A loose file of the game's own, as every Steam copy has it. It was a
        // script source until #1227 kept those out of the folder altogether.
        static readonly string Master = "Data\\Skyrim.esm", Loose = "Data\\Video\\BGS_Logo.bik";

        static Scene NewScene(string name, bool newer)
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

            // The Steam copy's game, on 1.6.1170 or on a newer build.
            if (newer)
            {
                Exe(Path.Combine(s.Game, "SkyrimSE.exe"), "NEW-EXE", NewerExeBytes);
                Put(Path.Combine(s.Game, Master), "NEW-MASTER");
                Archive(Path.Combine(s.Game, Tex), "PIN-TEX0");          // unchanged between builds
                Archive(Path.Combine(s.Game, Mesh), "NEW-MESH0");        // changed, the same size
            }
            else
            {
                Exe(Path.Combine(s.Game, "SkyrimSE.exe"), "PIN-EXE", ExeBytes);
                Put(Path.Combine(s.Game, Master), "PIN-MASTER");
                Archive(Path.Combine(s.Game, Tex), "PIN-TEX0");
                Archive(Path.Combine(s.Game, Mesh), "PIN-MESH0");
            }
            Put(Path.Combine(s.Game, Loose), "GAME-LOOSE");
            Put(Path.Combine(s.Game, "bink2w64.dll"), "GAME-BINK");

            // Vortex: two files in staging, deployed into the Steam copy as hard links.
            Deploy(s, new string[][] { new string[] { "TsOne.esp", "ModA", "VORTEX-TSONE" },
                                       new string[] { "textures\\ts\\wood.dds", "ModA", "VORTEX-DDS" } }, DateTime.UtcNow.AddMinutes(-10));
            return s;
        }

        static void Deploy(Scene s, string[][] files, DateTime when)
        {
            var rec = new List<string[]>();
            foreach (string[] f in files)
            {
                string staged = Path.Combine(s.Staging, f[1] + "\\" + f[0]);
                if (!File.Exists(staged)) Put(staged, f[2]);
                string at = Path.Combine(s.Game, "Data\\" + f[0]);
                if (!File.Exists(at)) { Directory.CreateDirectory(Path.GetDirectoryName(at)); CreateHardLink(at, staged, IntPtr.Zero); }
                rec.Add(new string[] { f[0], f[1] });
            }
            Record(Path.Combine(s.Game, "Data\\vortex.deployment.json"), s.Staging, Path.Combine(s.Game, "Data"), rec.ToArray(), when);
        }

        // Steam's download of 1.6.1170's own files, as Steam leaves it and
        // the Downgrade marks it: three depot folders under steamapps\content.
        static List<string> Download(Scene s)
        {
            var folders = new List<string>();
            string content = Path.Combine(s.Steam, "steamapps\\content\\app_489830");
            string[] cmds = Downgrade.Commands(s.Cfg);
            for (int i = 0; i < cmds.Length; i++)
            {
                string[] p = cmds[i].Split(' ');
                string folder = Path.Combine(content, "depot_" + p[2]);
                if (i == 0) Exe(Path.Combine(folder, "SkyrimSE.exe"), "PIN-EXE", ExeBytes);
                if (i == 1) { Archive(Path.Combine(folder, Tex), "PIN-TEX0"); Archive(Path.Combine(folder, Mesh), "PIN-MESH0"); }
                if (i == 2) Put(Path.Combine(folder, Master), "PIN-MASTER");
                Put(Path.Combine(folder, ".thornswood-complete"), p[3] + "\n1");
                folders.Add(folder);
            }
            return folders;
        }

        static void MadeNowRuns(Scene s)
        {
            // What the restart after Make does: the launcher runs from the folder.
            Paths.Collection = false;
            Paths.Game = OwnGame.Folder;
            Paths.Live = Paths.LocalAD;
            Paths.LiveMyGames = Paths.MyGames;
        }

        static string Shares() { string f = Path.Combine(OwnGame.Dir, "shared.txt"); return File.Exists(f) ? File.ReadAllText(f) : ""; }

        static int Main(string[] args)
        {
            T = args[0];
            try
            {
                SteamMovesOn();
                FirstFromNewer();
                WrittenThrough();
            }
            catch (Exception ex)
            {
                Yes("the driver ran to the end (" + ex.GetType().Name + ": " + ex.Message + ")", false);
                Console.WriteLine(ex.StackTrace);
            }
            Console.WriteLine("driver: " + pass + " passed, " + fail + " failed");
            return fail > 0 ? 1 : 0;
        }

        // ---- 1 and 2: made from 1.6.1170, then Steam moves on -----------------
        static void SteamMovesOn()
        {
            Scene s = NewScene("moves-on", false);
            var before = Snap(s.Game);
            string made = null;
            try { made = OwnGame.Make(s.Cfg, null); } catch (Exception ex) { Console.WriteLine("      Make said: " + ex.Message); }
            string own = OwnGame.Folder;
            Yes("made from a Steam copy on 1.6.1170", made != null && Clean(made));
            Yes("Make wrote nothing into the Steam copy", Same(before, Snap(s.Game)));
            Yes("the exe is the folder's own copy", Text(Path.Combine(own, "SkyrimSE.exe")) == "PIN-EXE" && Id(Path.Combine(own, "SkyrimSE.exe")) != Id(Path.Combine(s.Game, "SkyrimSE.exe")));
            Yes("a loose game file is the folder's own copy, not a link to the Steam copy's",
                Text(Path.Combine(own, Loose)) == "GAME-LOOSE" && Id(Path.Combine(own, Loose)) != Id(Path.Combine(s.Game, Loose)));
            Yes("Vortex's files are links to Vortex's own copies",
                Id(Path.Combine(own, "Data\\TsOne.esp")) == Id(Path.Combine(s.Staging, "ModA\\TsOne.esp")));
            Yes("Skyrim's archives are one file with the Steam copy's, so they are on the disk once",
                Id(Path.Combine(own, Tex)) == Id(Path.Combine(s.Game, Tex)) && Id(Path.Combine(own, Mesh)) == Id(Path.Combine(s.Game, Mesh)));
            string shares = Shares();
            Yes("and both are on record with their SHA-256 for the check before Play",
                shares.Contains("|" + Tex) && shares.Contains("|" + Mesh));
            MadeNowRuns(s);
            Yes("the check before Play passes on a folder just made", OwnGame.CheckShared(OwnGame.Source(s.Cfg), null) == null);

            // Steam updates its copy to a newer build, and the person mods it by hand.
            SteamUpdates(s, "SkyrimSE.exe", delegate (string p) { Exe(p, "NEW-EXE", NewerExeBytes); });
            SteamUpdates(s, Master, delegate (string p) { Put(p, "NEW-MASTER"); });
            SteamUpdates(s, Tex, delegate (string p) { Archive(p, "NEW-TEX0"); });
            Put(Path.Combine(s.Game, "Data\\PersonsOwn.esp"), "PERSON-MOD");
            Archive(Path.Combine(s.Game, "Data\\NewBuild.bsa"), "NEW-ARCHIVE");
            // And Vortex deploys another file of the collection.
            Deploy(s, new string[][] { new string[] { "TsOne.esp", "ModA", "VORTEX-TSONE" },
                                       new string[] { "textures\\ts\\wood.dds", "ModA", "VORTEX-DDS" },
                                       new string[] { "meshes\\ts\\bench.nif", "ModB", "VORTEX-BENCH" } }, DateTime.UtcNow);

            string src = OwnGame.DeploysInto(s.Cfg);
            string why = OwnGame.WhyNot(s.Cfg, src);
            Yes("with the Steam copy on a newer build, a made folder can still follow Vortex (WhyNot says nothing)", why == null);
            if (why != null) Console.WriteLine("      WhyNot said: " + why);
            Yes("and no Downgrade is asked for", !Downgrade.Needed(s.Cfg));
            Yes("the check before Play passes: the archive the Steam update replaced kept its bytes here",
                OwnGame.CheckShared(OwnGame.Source(s.Cfg), null) == null && Text(Path.Combine(own, Tex)) == "PIN-TEX0");
            Yes("the folder asks to follow Vortex", OwnGame.NeedsRefresh(s.Cfg));

            var steamNow = Snap(s.Game);
            string again = null;
            try { again = OwnGame.Refresh(s.Cfg, null); } catch (Exception ex) { Console.WriteLine("      Refresh said: " + ex.Message); }
            Yes("the refresh works", again != null && Clean(again));
            Yes("and wrote nothing into the Steam copy", Same(steamNow, Snap(s.Game)));
            Yes("Vortex's new file came in, as a link", Id(Path.Combine(own, "Data\\meshes\\ts\\bench.nif")) == Id(Path.Combine(s.Staging, "ModB\\meshes\\ts\\bench.nif")));
            Yes("the folder kept its 1.6.1170 exe, master and archives",
                Text(Path.Combine(own, "SkyrimSE.exe")) == "PIN-EXE" && new FileInfo(Path.Combine(own, "SkyrimSE.exe")).Length == ExeBytes &&
                Text(Path.Combine(own, Master)) == "PIN-MASTER" && Text(Path.Combine(own, Tex)) == "PIN-TEX0" && Text(Path.Combine(own, Mesh)) == "PIN-MESH0");
            Yes("nothing of the newer build or of the person's own mods came in",
                !File.Exists(Path.Combine(own, "Data\\PersonsOwn.esp")) && !File.Exists(Path.Combine(own, "Data\\NewBuild.bsa")));
            string files = File.ReadAllText(Path.Combine(OwnGame.Dir, "files.txt"));
            Yes("the game's own files are still on record after the refresh", files.Contains("|O|") && files.Contains("|" + Master) && files.Contains("|" + Loose));
            Yes("the check before Play still passes", OwnGame.CheckShared(OwnGame.Source(s.Cfg), null) == null);
        }

        // ---- 3: first setup from a Steam copy on a newer build ---------------
        static void FirstFromNewer()
        {
            Scene s = NewScene("first-newer", true);
            var before = Snap(s.Game);
            string src = OwnGame.DeploysInto(s.Cfg);
            string why = OwnGame.WhyNot(s.Cfg, src);
            Yes("first setup, Steam copy newer: the folder cannot be made yet", why != null);
            Yes("and the sentence says the Steam copy stays as it is and the Downgrade gets 1.6.1170's own files",
                why != null && why.Contains("never changes that copy") && why.Contains("press Downgrade") && why.Contains("stays on the build it is on") && Clean(why));
            Yes("the Downgrade card is up (Downgrade.Needed)", Downgrade.Needed(s.Cfg));
            bool threw = false;
            try { OwnGame.Make(s.Cfg, null); } catch { threw = true; }
            Yes("Make refuses", threw && !Directory.Exists(OwnGame.Folder));

            List<string> depots = Download(s);
            Yes("once 1.6.1170's files are downloaded, Downgrade.Downloaded finds all three", Downgrade.Downloaded(s.Cfg) != null && Downgrade.Downloaded(s.Cfg).Count == 3);
            Yes("the Downgrade card goes, and the folder can be made", !Downgrade.Needed(s.Cfg) && OwnGame.WhyNot(s.Cfg, src) == null);
            string made = null;
            try { made = OwnGame.Make(s.Cfg, null); } catch (Exception ex) { Console.WriteLine("      Make said: " + ex.Message); }
            string own = OwnGame.Folder;
            Yes("Make works from the download", made != null && Clean(made));
            Yes("and wrote nothing into the Steam copy", Same(before, Snap(s.Game)));
            Yes("the folder has 1.6.1170's exe and master, not the Steam copy's",
                Text(Path.Combine(own, "SkyrimSE.exe")) == "PIN-EXE" && new FileInfo(Path.Combine(own, "SkyrimSE.exe")).Length == ExeBytes &&
                Text(Path.Combine(own, Master)) == "PIN-MASTER");
            Yes("an archive the newer build changed is 1.6.1170's, as a copy of the folder's own",
                Text(Path.Combine(own, Mesh)) == "PIN-MESH0" && Id(Path.Combine(own, Mesh)) != Id(Path.Combine(s.Game, Mesh)));
            Yes("an archive with the same bytes in both builds is shared with the Steam copy",
                Text(Path.Combine(own, Tex)) == "PIN-TEX0" && Id(Path.Combine(own, Tex)) == Id(Path.Combine(s.Game, Tex)) && Shares().Contains("|" + Tex));
            Yes("Vortex's files are in", Id(Path.Combine(own, "Data\\TsOne.esp")) == Id(Path.Combine(s.Staging, "ModA\\TsOne.esp")));
            bool gone = true;
            foreach (string d in depots) if (Directory.Exists(d)) gone = false;
            Yes("the download is cleared away once the folder has the files", gone);
            Yes("the folder's line says the Steam copy was not changed", made != null && made.Contains("was not changed"));
        }

        // ---- 4: a shared archive written over through the Steam copy ---------
        static void WrittenThrough()
        {
            Scene s = NewScene("written-through", false);
            string made = null;
            try { made = OwnGame.Make(s.Cfg, null); } catch (Exception ex) { Console.WriteLine("      Make said: " + ex.Message); }
            string own = OwnGame.Folder;
            MadeNowRuns(s);
            Yes("(made, with the meshes archive shared)", made != null && Id(Path.Combine(own, Mesh)) == Id(Path.Combine(s.Game, Mesh)));

            // The person copies another build's archive over the Steam copy's,
            // the way a manual mod or another launcher's downgrade puts one in.
            string other = Path.Combine(s.Dir, "other.bsa");
            Archive(other, "MODDED-MESH");
            File.Copy(other, Path.Combine(s.Game, Mesh), true);
            Yes("(copying over the Steam copy's archive changed the one in Thornswood's folder too)", Text(Path.Combine(own, Mesh)) == "MODDED-MESH");

            var steamNow = Snap(s.Game);
            string said = OwnGame.CheckShared(OwnGame.Source(s.Cfg), null);
            Yes("the check before Play finds it and names it", said != null && said.Contains("Skyrim - Meshes0.bsa") && Clean(said));
            Yes("and says the Downgrade puts it right", said != null && said.Contains("Press Downgrade"));
            Yes("it goes on record as changed, so Play stays shut", OwnGame.Changed().Contains(Mesh));
            Yes("and the Downgrade card comes up", Downgrade.Needed(s.Cfg));
            Yes("the check wrote nothing into the Steam copy", Same(steamNow, Snap(s.Game)));
            Yes("an untouched shared archive is not called changed", !OwnGame.Changed().Contains(Tex));

            List<string> depots = Download(s);
            steamNow = Snap(s.Game);
            string took = null;
            try { took = OwnGame.TakePinned(s.Cfg, depots, null, null); } catch (Exception ex) { Console.WriteLine("      TakePinned said: " + ex.Message); }
            Yes("the Downgrade's files go into the folder", took != null && Clean(took));
            Yes("and 1.6.1170's bytes are back, as the folder's own copy",
                Text(Path.Combine(own, Mesh)) == "PIN-MESH0" && Id(Path.Combine(own, Mesh)) != Id(Path.Combine(s.Game, Mesh)));
            Yes("nothing is on record as changed any more, the check passes and the card goes",
                OwnGame.Changed().Count == 0 && OwnGame.CheckShared(OwnGame.Source(s.Cfg), null) == null && !Downgrade.Needed(s.Cfg));
            Yes("the Steam copy still has what the person put there, untouched", Same(steamNow, Snap(s.Game)) && Text(Path.Combine(s.Game, Mesh)) == "MODDED-MESH");
            Yes("Vortex's files were left as they are", Id(Path.Combine(own, "Data\\TsOne.esp")) == Id(Path.Combine(s.Staging, "ModA\\TsOne.esp")));
            string files = File.ReadAllText(Path.Combine(OwnGame.Dir, "files.txt"));
            Yes("the record lists the archive as the folder's own copy", files.Contains("C|O|" + new FileInfo(Path.Combine(own, Mesh)).Length));

            // With no folder of its own the Downgrade writes nowhere.
            Paths.Collection = true;
            Paths.Game = s.Game;
            steamNow = Snap(s.Game);
            bool refused = false;
            try { OwnGame.TakePinned(s.Cfg, depots, null, null); } catch (Exception ex) { refused = ex.Message.Contains("never written"); }
            Yes("before a folder of its own exists, the Downgrade's files are never put into the Steam copy", refused && Same(steamNow, Snap(s.Game)));
        }
    }
}
'@

$work = Join-Path $Scratch ('thornswood-own-alone-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Force -Path $work
try {
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $stubFile = Join-Path $work 'Stubs.cs'
    $driverFile = Join-Path $work 'Driver.cs'
    [IO.File]::WriteAllText($stubFile, $stubs, $utf8)
    [IO.File]::WriteAllText($driverFile, $driver, $utf8)
    $exe = Join-Path $work 'own-alone-test.exe'
    $cscArgs = @('/noconfig', '/nologo', '/target:exe', '/warn:0', "/out:$exe")
    foreach ($r in $refs) { $cscArgs += "/reference:$r" }
    foreach ($f in $real) { $cscArgs += (Resolve-Path -LiteralPath $f).Path }
    $cscArgs += $stubFile
    $cscArgs += $driverFile
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $compiled = & $csc @cscArgs 2>&1
    $ErrorActionPreference = $old
    $built = ($LASTEXITCODE -eq 0) -and (Test-Path -LiteralPath $exe)
    Yes 'the real OwnGame.cs, OwnGameShare.cs and Downgrade.cs compile with the driver under the C# 5 compiler' $built
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

# ---- 5: the launcher's source keeps the Steam copy unwritten ------------------
$read = { param($n) [IO.File]::ReadAllText((Join-Path $AppPath $n)) }
$own = & $read 'OwnGame.cs'
$share = & $read 'OwnGameShare.cs'
$down = & $read 'Downgrade.cs'
$shell = & $read 'Shell.cs'
$upd = & $read 'Updater.cs'
$all = (Get-ChildItem -LiteralPath $AppPath -Filter '*.cs' | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n"

Yes 'nothing asks for the Steam copy to be downgraded any more (SourceNeeded and Downgrade.Target are gone)' `
    (($all -notmatch 'SourceNeeded\(') -and ($all -notmatch 'Downgrade\.Target\('))
Yes 'WhyNot no longer refuses a made folder over the Steam copy''s build' ($own -notmatch 'most likely because Steam updated it')
Yes 'a refresh takes only Vortex''s files (Refresh calls Vortex, not Gather)' `
    (($own -match 'List<Found> all = Vortex\(src, left\);') -and ($own -notmatch 'List<Found> all = Gather\(src, left\);'))
Yes 'the Downgrade puts its files only through OwnGame.TakePinned, and never names the Steam copy (OwnGame.Source)' `
    (($down -match 'OwnGame\.TakePinned\(') -and ($down -notmatch 'OwnGame\.Source') -and ($down -notmatch 'File\.Copy\('))
$run = $down.Substring($down.IndexOf('static bool Run(Config cfg'))
Yes 'with no folder of its own the Downgrade returns before any file is put anywhere' `
    (($run.IndexOf('if (first)', $run.IndexOf('DownloadedExe(content)')) -ge 0) -and
     ($run.IndexOf('if (first)', $run.IndexOf('DownloadedExe(content)')) -lt $run.IndexOf('OwnGame.TakePinned(')))
Yes 'TakePinned refuses outright before a folder of its own exists' `
    ($share -match 'if \(Paths\.Collection\)\s*throw new Exception\("Thornswood has no folder of its own yet, and the Steam copy is never written')
Yes 'SkyrimSE.exe goes in last (#369 F3)' `
    (($share -match 'if \(string\.Equals\(f\.Rel, "SkyrimSE\.exe", StringComparison\.OrdinalIgnoreCase\)\) exe = f;') -and ($share -match 'if \(exe != null\) take\.Add\(exe\);'))
Yes 'removing a pack no longer deletes anything from the Steam copy' `
    ($upd -notmatch 'also went from the Skyrim on Steam')
$play = $shell.Substring($shell.IndexOf('static void Play()'))
Yes 'Play checks the shared archives before anything else is read, and stops when one changed' `
    (($play.IndexOf('OwnGame.CheckShared(') -ge 0) -and ($play.IndexOf('OwnGame.CheckShared(') -lt $play.IndexOf('Verify.Run(cfg)')))
Yes 'after the Downgrade, the folder is made from the download, and Steam''s updates are not asked about' `
    (($shell -match 'if \(ok && Paths\.Collection && Downgrade\.Downloaded\(cfg\) != null\) StartOwnGame\(true, true\);') -and
     ($shell -notmatch 'if \(ok\) AskToHoldSteamUpdates\(\);'))
Yes 'the Downgrade question says the Steam copy is not changed' ($shell -match 'Your Steam copy of Skyrim is not changed and can stay on any build')
Yes 'OwnGame.cs and OwnGameShare.cs are C# 5: no interpolated strings, no ?., no nameof' `
    ((($own + $share) -notmatch '(?<![\w\)\]])\$"') -and (($own + $share) -notmatch '\?\.[A-Za-z]') -and (($own + $share) -notmatch '\bnameof\s*\('))

Done
