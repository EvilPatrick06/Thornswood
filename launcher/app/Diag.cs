using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Text;

namespace Thornswood
{
    class Reading
    {
        public string Title, Detail;
        public int Level;              // 0 fine, 1 worth a look, 2 wrong
        public Reading(int level, string title, string detail) { Level = level; Title = title; Detail = detail; }
    }

    /// <summary>
    /// Everything the launcher can work out about this machine without being
    /// asked a question, and a way to put it in one file.
    ///
    /// The point is the file. Half of every support conversation is spent
    /// getting someone to find four logs in three folders, and most people
    /// give up before the end of it.
    /// </summary>
    static class Diag
    {
        public static string ReportDir { get { return Path.Combine(Paths.ProfileDir, "Reports"); } }

        static string Size(long b)
        {
            if (b < 1024) return b + " B";
            if (b < 1024 * 1024) return (b / 1024) + " KB";
            if (b < 1024L * 1024 * 1024) return (b / (1024.0 * 1024.0)).ToString("F1") + " MB";
            return (b / (1024.0 * 1024.0 * 1024.0)).ToString("F1") + " GB";
        }

        /// <summary>The first line of the newest crash log that names a plugin, if there is one.</summary>
        public static string CrashCulprit()
        {
            try
            {
                Entry e = Files.NewestCrash();
                if (e == null) return "";
                foreach (string line in File.ReadLines(e.FullPath))
                {
                    // Crash Logger prints the faulting module on a line of its own.
                    int at = line.IndexOf("Probable callstack", StringComparison.OrdinalIgnoreCase);
                    if (at >= 0) continue;
                    string t = line.Trim();
                    if (t.EndsWith(".dll", StringComparison.OrdinalIgnoreCase) ||
                        t.EndsWith(".esp", StringComparison.OrdinalIgnoreCase) ||
                        t.EndsWith(".esm", StringComparison.OrdinalIgnoreCase))
                        return t;
                }
            }
            catch (Exception ex) { Swallow.Note("Diag.CrashCulprit", ex); }
            return "";
        }

        public static List<Reading> Readings(Config cfg, bool serverUp, string pingText)
        {
            var l = new List<Reading>();

            // ---- which Skyrim actually ran
            string ran = Checks.LastRunFrom();
            if (ran.Length == 0)
                l.Add(new Reading(1, "The game has not run from here yet",
                    "Nothing to read. This fills in the first time you press Play and quit."));
            else if (Checks.RanFromBuild())
                l.Add(new Reading(0, "The last session ran this build",
                    ran + ". That is the folder this launcher manages, which is what you want."));
            else
                l.Add(new Reading(2, "The last session ran a different Skyrim",
                    "It ran from " + ran + ", so none of this build's mods were loaded and none of its settings applied. " +
                    "Start the game from this launcher rather than from Steam or a desktop shortcut."));

            // ---- mod list
            int blocking = 0, total = 0;
            try { foreach (Issue i in Verify.Run()) { total++; if (i.Blocking) blocking++; } } catch (Exception ex) { Swallow.Note("Diag.Readings, Verify.Run", ex); }
            if (blocking > 0)
                l.Add(new Reading(2, blocking == 1 ? "1 problem with your mod list" : blocking + " problems with your mod list",
                    "The server compares your plugin list against the one this build shipped with and will refuse the connection. Mods, then Fix."));
            else if (total > 0)
                l.Add(new Reading(1, total == 1 ? "1 note about your mod list" : total + " notes about your mod list",
                    "Nothing that stops you connecting. Mods, then Scan, to read them."));
            else
                l.Add(new Reading(0, "Your mod list matches the server", Checks.EnabledPlugins() + " plugins, in the order it expects."));

            // ---- crash
            Entry crash = null;
            try { crash = Files.NewestCrash(); } catch (Exception ex) { Swallow.Note("Diag.Readings, NewestCrash", ex); }
            if (crash == null)
                l.Add(new Reading(0, "No crash logs", "Nothing has fallen over on this machine."));
            else
            {
                string who = CrashCulprit();
                string dmp = CrashDump.Beside(crash.FullPath);
                l.Add(new Reading(1, "Newest crash: " + crash.Name,
                    (who.Length > 0 ? "The log points at " + who + ". " : "") +
                    "Send the report below rather than reading it yourself." +
                    (dmp != null ? " Its full crash snapshot is " + dmp + ". The report leaves it out: it holds what was in the game's memory, so it stays on this PC." : "")));
            }

            // ---- server
            l.Add(serverUp
                ? new Reading(0, "The server answers", "round trip " + pingText + ".")
                : new Reading(1, "The server did not answer",
                    "That is not always a problem. Plenty of hosts drop the kind of packet this test uses, so try connecting before assuming it is down."));

            // ---- steam
            l.Add(Checks.SteamRunning()
                ? new Reading(0, "Steam is running", "Skyrim still checks ownership through it, even though this build sits outside your Steam folder.")
                : new Reading(2, "Steam is not running", "Start Steam and sign in. The game will not launch without it."));

            // ---- disk
            try
            {
                var d = new DriveInfo(Path.GetPathRoot(Paths.Root));
                long free = d.AvailableFreeSpace;
                l.Add(free < 3L * 1024 * 1024 * 1024
                    ? new Reading(2, "Almost no disk space left", Size(free) + " free on " + d.Name + ". Saves and updates both need room.")
                    : new Reading(0, "Disk space is fine", Size(free) + " free on " + d.Name + "."));
            }
            catch (Exception ex) { Swallow.Note("Diag.Readings, disk space", ex); }

            // ---- leftovers
            if (Checks.GameRunning())
                l.Add(new Reading(2, "Skyrim is running right now",
                    Checks.GameVisible()
                        ? "There is a window for it somewhere."
                        : "With no window anywhere. It is left over from a crash. Press Play and the launcher will clear it."));

            return l;
        }

        /// <summary>
        /// Writes a zip of every log worth having plus a summary, and returns
        /// the path. Slow enough to want a background thread.
        /// </summary>
        public static string Report(Config cfg, string launcherVersion)
        {
            Directory.CreateDirectory(ReportDir);
            string stamp = DateTime.Now.ToString("yyyyMMdd-HHmm");
            string work = Path.Combine(ReportDir, "build-" + stamp);
            if (Directory.Exists(work)) Directory.Delete(work, true);
            Directory.CreateDirectory(work);

            try
            {
                Grab(work, Path.Combine(Paths.LiveMyGames, "SKSE\\skse64.log"));
                Grab(work, Path.Combine(Paths.LiveMyGames, "SKSE\\SSEDisplayTweaks.log"));
                Grab(work, Path.Combine(Paths.Live, "plugins.txt"));
                Grab(work, Path.Combine(Paths.Golden, "plugins.txt"), "plugins-expected.txt");
                Grab(work, Paths.LogFile);
                Grab(work, Path.Combine(Paths.LiveMyGames, "SkyrimPrefs.ini"));

                Entry crash = Files.NewestCrash();
                if (crash != null) Grab(work, crash.FullPath);

                File.WriteAllText(Path.Combine(work, "summary.txt"), Summary(cfg, launcherVersion));

                string zip = Path.Combine(ReportDir, "thornswood-" + stamp + ".zip");
                if (File.Exists(zip)) File.Delete(zip);
                ZipFile.CreateFromDirectory(work, zip, CompressionLevel.Optimal, false);
                return zip;
            }
            finally
            {
                try { Directory.Delete(work, true); } catch (Exception ex) { Swallow.Note("Diag.Report, clearing work folder", ex); }
            }
        }

        static void Grab(string into, string file) { Grab(into, file, null); }

        static void Grab(string into, string file, string rename)
        {
            try
            {
                if (!File.Exists(file)) return;
                string name = rename != null ? rename : Path.GetFileName(file);
                File.Copy(file, Path.Combine(into, name), true);
            }
            catch (Exception ex) { Swallow.Note("Diag.Grab, " + file, ex); }
        }

        static string Summary(Config cfg, string launcherVersion)
        {
            var s = new StringBuilder();
            // A local function would read better, but this is compiled by the
            // .NET Framework csc that ships with Windows, which predates them.
            Action<string, string> Add = delegate(string k, string v) { s.AppendLine(k.PadRight(22) + v); };

            s.AppendLine("ThornsWood - report");
            s.AppendLine("===================");
            s.AppendLine(DateTime.Now.ToString("dddd d MMMM yyyy, HH:mm"));
            s.AppendLine();

            Add("launcher", launcherVersion);
            Add("install", Paths.Root);
            Add("server", cfg.ServerAddress + ":" + cfg.ServerPort);
            Add("auto join", cfg.AutoJoin ? "on" : "off");
            Add("auto update", cfg.AutoUpdate ? "on" : "off");
            Add("theme", cfg.Theme);
            s.AppendLine();

            // The game's facts from Paths.Skyrim: the Steam copy while the own
            // folder is chosen and not made, when Paths.Game is Profile\Payload
            // and has no game in it (#1235). The client is Game's either way.
            if (Paths.OwnFirst) Add("game read from", Paths.Skyrim + " (the own folder is not made yet)");
            try { Add("game exe", new FileInfo(Paths.SkyrimExe).Length.ToString("n0") + " bytes"); } catch (Exception ex) { Swallow.Note("Diag.Summary, game exe size", ex); }
            Add("expected exe", cfg.ExpectedExeBytes.ToString("n0") + " bytes");
            Add("multiplayer client", File.Exists(Paths.MpClient) ? "present" : "MISSING");
            Add("plugins enabled", Checks.EnabledPlugins().ToString());
            Add("ran last from", Checks.LastRunFrom());
            s.AppendLine();

            Add("windows", Environment.OSVersion.VersionString);
            Add("64 bit", Environment.Is64BitOperatingSystem ? "yes" : "no");
            Add("processors", Environment.ProcessorCount.ToString());
            Add("user", Environment.UserName);
            Add("machine", Environment.MachineName);
            try
            {
                var d = new DriveInfo(Path.GetPathRoot(Paths.Root));
                Add("disk free", Size(d.AvailableFreeSpace) + " on " + d.Name);
            }
            catch (Exception ex) { Swallow.Note("Diag.Summary, disk free", ex); }
            s.AppendLine();

            s.AppendLine("mod list problems");
            s.AppendLine("-----------------");
            try
            {
                var issues = Verify.Run();
                if (issues.Count == 0) s.AppendLine("none");
                foreach (Issue i in issues) s.AppendLine((i.Blocking ? "[blocking] " : "[note]     ") + i.Text);
            }
            catch (Exception ex) { s.AppendLine("could not check: " + ex.Message); }
            s.AppendLine();

            s.AppendLine("script extender plugins");
            s.AppendLine("-----------------------");
            try
            {
                // Two folders while the own folder is chosen and not made: the
                // Steam copy's, what Vortex deployed, and Payload's,
                // Thornswood's own. Each is named so a report says which.
                string[] dirs = Paths.SksePluginDirs;
                foreach (string dir in dirs)
                {
                    if (dirs.Length > 1) s.AppendLine("in " + dir);
                    if (!Directory.Exists(dir)) continue;
                    var files = Directory.GetFiles(dir, "*.dll");
                    Array.Sort(files);
                    foreach (string f in files) s.AppendLine(Path.GetFileName(f));
                }
            }
            catch (Exception ex) { Swallow.Note("Diag.Summary, SKSE plugins", ex); }

            return s.ToString();
        }
    }
}
