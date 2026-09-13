using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Threading;

namespace Thornswood
{
    class Check
    {
        public string Name, Detail;
        public bool Ok;
        public Check(string n, bool ok, string d) { Name = n; Ok = ok; Detail = d; }
    }

    static class Checks
    {
        /// <summary>
        /// Whether the plugin that walks past the main menu is present. Without
        /// it the character picker still decides which saves exist, the game
        /// just asks one more question on the way in.
        /// </summary>
        public static bool StartOnSaveInstalled()
        {
            try
            {
                string dll = System.IO.Path.Combine(Paths.Game, "Data\\SKSE\\Plugins\\po3_StartOnSave.dll");
                return System.IO.File.Exists(dll);
            }
            catch { return false; }
        }

        public static int EnabledPlugins()
        {
            try
            {
                string p = Path.Combine(Paths.LocalAD, "plugins.txt");
                if (!File.Exists(p)) return 0;
                int n = 0;
                foreach (string line in File.ReadAllLines(p))
                    if (line.StartsWith("*")) n++;
                return n;
            }
            catch { return 0; }
        }

        public static List<Check> All(Config cfg)
        {
            long bytes = 0;
            try { if (File.Exists(Paths.Exe)) bytes = new FileInfo(Paths.Exe).Length; } catch { }
            int plugins = EnabledPlugins();

            var l = new List<Check>();
            l.Add(new Check("Game build", bytes == cfg.ExpectedExeBytes, bytes == 0 ? "missing" : "1.6.1170"));
            l.Add(new Check("Script Extender", File.Exists(Path.Combine(Paths.Game, "skse64_1_6_1170.dll")), "skse64 2.2.6"));
            l.Add(new Check("Multiplayer", File.Exists(Paths.MpClient), "SkyMP client"));
            l.Add(new Check("Mods", plugins > 40, plugins + " plugins"));

            // The server does not police plugin lists, so this does. A list that
            // does not match the one this build shipped with desyncs everyone,
            // which is worse than a blocked button with a one click fix.
            int blocking = 0;
            try { foreach (Issue i in Verify.Run()) if (i.Blocking) blocking++; } catch { }
            l.Add(new Check("Mod list",
                            blocking == 0,
                            blocking == 0 ? "matches the server"
                                          : (blocking == 1 ? "1 problem, open Mods" : blocking + " problems, open Mods")));

            l.Add(new Check("Steam", SteamRunning(), "running"));
            return l;
        }

        public static bool SteamRunning()
        {
            try { return Process.GetProcessesByName("steam").Length > 0; }
            catch { return false; }
        }

        /// <summary>
        /// Which Skyrim last ran, read back from the script extender's own log.
        /// Empty until the game has been started at least once.
        ///
        /// Worth knowing because the multiplayer client will happily start a
        /// different copy of Skyrim than the one it is sitting in, and when it
        /// does, nothing about this build applies and nothing says so.
        /// </summary>
        public static string LastRunFrom()
        {
            const string key = "plugin directory =";
            const string tail = "\\Data\\SKSE\\Plugins";
            try
            {
                string log = Path.Combine(Paths.MyGames, "SKSE\\skse64.log");
                if (!File.Exists(log)) return "";
                foreach (string line in File.ReadAllLines(log))
                {
                    int at = line.IndexOf(key, StringComparison.OrdinalIgnoreCase);
                    if (at < 0) continue;
                    string p = line.Substring(at + key.Length).Trim();
                    int cut = p.IndexOf(tail, StringComparison.OrdinalIgnoreCase);
                    return (cut > 0 ? p.Substring(0, cut) : p).TrimEnd('\\');
                }
            }
            catch { }
            return "";
        }

        /// <summary>False only when we know for certain it ran somewhere else.</summary>
        public static bool RanFromBuild()
        {
            string from = LastRunFrom();
            if (from.Length == 0) return true;
            return string.Equals(from, Paths.Game.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase);
        }

        /// <summary>
        /// True only while Skyrim itself is up. The launcher's own exe has
        /// carried the same name as the multiplayer client at times, so a bare
        /// name match makes it find itself and never let go of the session.
        /// </summary>
        public static bool GameRunning()
        {
            List<Process> ps = GameProcesses();
            int n = ps.Count;
            Release(ps);
            return n > 0;
        }

        /// <summary>
        /// Everything currently running that counts as the game. The caller owns
        /// what comes back and should pass it to Release when finished.
        /// </summary>
        public static List<Process> GameProcesses()
        {
            var l = new List<Process>();
            int mine = Process.GetCurrentProcess().Id;
            string self = "";
            try { self = System.Reflection.Assembly.GetExecutingAssembly().Location; } catch { }

            // Thornswood and SkyrimTogether are both this launcher: installs
            // made before the rename keep the old file name, because the
            // launcher replaces itself in place rather than being reinstalled.
            string[] names = { "SkyrimSE", "Thornswood", "SkyrimTogether", "skse64_loader" };
            foreach (string n in names)
            {
                Process[] found;
                try { found = Process.GetProcessesByName(n); } catch { continue; }
                foreach (Process p in found)
                {
                    bool ours = p.Id == mine ||
                                ((n == "Thornswood" || n == "SkyrimTogether") && IsThisLauncher(p, self));
                    // SkyrimSE.exe is what every Skyrim install on the machine
                    // is called. Matching the name alone meant another modlist's
                    // game counted as this one: Play stayed blocked while it was
                    // up, and Clear would try to kill somebody else's session
                    // and then tell them to restart the PC when it could not.
                    //
                    // Only skip it when the path says, in as many words, that it
                    // lives somewhere else. A path we cannot read is the state a
                    // game that has already fallen over is usually in, and those
                    // are exactly the ones that need closing: one of them left
                    // holding the profile folder is what makes the next launch
                    // fail with access denied.
                    if (!ours && Where(p) == false) ours = true;
                    if (ours) { try { p.Dispose(); } catch { } }
                    else l.Add(p);
                }
            }
            return l;
        }

        static void Release(List<Process> ps)
        {
            foreach (Process p in ps) { try { p.Dispose(); } catch { } }
        }

        /// <summary>
        /// True when at least one of them has a window on screen, which is the
        /// difference between a game somebody is playing and the leftovers of
        /// one that crashed. Skyrim does not always exit cleanly, and the
        /// multiplayer client's browser helpers outlive it more often than not,
        /// so a process with no window is the common case, not the odd one.
        /// </summary>
        public static bool GameVisible()
        {
            List<Process> ps = GameProcesses();
            bool seen = false;
            foreach (Process p in ps)
            {
                try { if (p.MainWindowHandle != IntPtr.Zero) { seen = true; break; } }
                catch { }
            }
            Release(ps);
            return seen;
        }

        /// <summary>
        /// Closes everything GameProcesses found and waits for it to actually
        /// go. Anything with a window is asked first and given six seconds;
        /// anything without one never had a window to ask, so it is ended
        /// straight away. Returns how many were closed.
        /// </summary>
        public static int CloseGame()
        {
            List<Process> ps = GameProcesses();
            if (ps.Count == 0) return 0;
            int count = ps.Count;

            bool asked = false;
            foreach (Process p in ps)
            {
                try
                {
                    if (p.MainWindowHandle == IntPtr.Zero) continue;
                    p.CloseMainWindow();
                    asked = true;
                }
                catch { }
            }

            if (asked)
            {
                for (int i = 0; i < 24; i++)
                {
                    Thread.Sleep(250);
                    bool any = false;
                    foreach (Process p in ps) { try { if (!p.HasExited) any = true; } catch { } }
                    if (!any) break;
                }
            }

            foreach (Process p in ps) { try { if (!p.HasExited) p.Kill(); } catch { } }
            Release(ps);

            // A process that has been ended can sit in the table for a moment
            // afterwards, so this waits for it to leave rather than reporting a
            // failure on the first look.
            for (int i = 0; i < 12; i++)
            {
                Thread.Sleep(250);
                if (!GameRunning()) break;
            }
            return count;
        }

        /// <summary>
        /// True when the process is running out of this build's folder, false
        /// when it is positively somewhere else, and null when the path cannot
        /// be read at all. The three answers are not the same and the caller
        /// has to tell them apart: treating "cannot read" as "somebody else's"
        /// leaves a crashed game running, and a crashed game still holding the
        /// profile folder is what breaks the next launch.
        /// </summary>
        static bool? Where(Process p)
        {
            string path = null;
            try { path = p.MainModule.FileName; } catch { }
            if (string.IsNullOrEmpty(path)) return null;
            try
            {
                string root = Path.GetFullPath(Paths.Root).TrimEnd('\\') + "\\";
                return Path.GetFullPath(path).StartsWith(root, StringComparison.OrdinalIgnoreCase);
            }
            catch { return null; }
        }

        /// <summary>
        /// A Skyrim that is not this one. Two at once is a losing fight with
        /// Steam whoever started them, so it is worth saying, but it is not
        /// ours to close.
        /// </summary>
        public static bool OtherSkyrimRunning()
        {
            string[] names = { "SkyrimSE", "skse64_loader" };
            foreach (string n in names)
            {
                Process[] found;
                try { found = Process.GetProcessesByName(n); } catch { continue; }
                foreach (Process p in found)
                {
                    // Only a path we could actually read counts as somebody
                    // else's game. Anything else stays our problem.
                    bool foreign = Where(p) == false;
                    try { p.Dispose(); } catch { }
                    if (foreign) return true;
                }
            }
            return false;
        }

        static bool IsThisLauncher(Process p, string self)
        {
            string path = null;
            try { path = p.MainModule.FileName; } catch { }

            // A path we cannot read belongs to a process running at a higher
            // level than us, which the game never is. Another copy of this
            // launcher is the likelier answer, and the game shows up as
            // SkyrimSE regardless, so nothing is missed by skipping it.
            if (string.IsNullOrEmpty(path)) return true;

            if (!string.IsNullOrEmpty(self) && string.Equals(path, self, StringComparison.OrdinalIgnoreCase)) return true;
            // Matched by folder rather than by file name. The launcher has been
            // called SkyrimTogether.exe and is called Thornswood.exe now, and an
            // install made before the rename still carries the old name, so a
            // literal here would quietly stop recognising somebody's launcher.
            try
            {
                string dir = Path.GetDirectoryName(path);
                if (!string.IsNullOrEmpty(dir) &&
                    string.Equals(dir.TrimEnd('\\'), Paths.LauncherDir.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase))
                    return true;
            }
            catch { }
            return false;
        }
    }
}
