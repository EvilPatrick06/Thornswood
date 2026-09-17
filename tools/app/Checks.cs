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
                string p = Path.Combine(Paths.Live, "plugins.txt");
                if (!File.Exists(p)) return 0;
                int n = 0;
                foreach (string line in File.ReadAllLines(p))
                    if (line.StartsWith("*")) n++;
                return n;
            }
            catch { return 0; }
        }

        /// <summary>
        /// Another server's client, sitting in the Steam game's SKSE folder.
        ///
        /// These are not plugins and not mods, so nothing about the plugin list
        /// notices them. Every check on the Play page can be green while Daedric
        /// Online's client draws the main menu and asks somebody to log in to a
        /// server that is not this one, and Skyrim then will not close, so the
        /// launcher cannot update either.
        ///
        /// Vortex does not take them out. It only tracks what it deployed, and
        /// these were dropped in by somebody else's installer, so Purge Mods
        /// leaves them exactly where they are.
        /// </summary>
        ///
        /// NirnLabUIPlugin.dll WAS on this list and must never go back on it.
        /// It is not another server's file. It is the browser backend this
        /// build runs on: Data\SKSE\Plugins\SkyrimPlatform.ini says
        /// BackendName = nirnlab, and thornswood-front.js reads the backend
        /// name at startup and logs it. Listing it here meant every press of
        /// Fix deleted the plugin that draws the whole in game interface, so
        /// the overlay never booted and nothing put anybody into the creation
        /// hall. Its runtime folder, Data\NirnLabUIPlatform, is the same
        /// thing and is not foreign either.
        public static readonly string[] ForeignNames = {
            "DaedricItemUseProbe.dll",
            "DaedricItemUseProbe.json",
            "DaedricItemUseProbe.NOTICES.txt",
        };

        /// <summary>
        /// The rest of another server's client, as exact paths under the game
        /// folder. The two swf files are the other server's main menu, which
        /// is what shows their logo and their sign in box in place of
        /// Skyrim's.
        ///
        /// Data\\NirnLabUIPlatform is deliberately NOT here. See the note on
        /// ForeignNames above: that folder is this build's own browser.
        ///
        /// Exact paths only. Never a pattern, and never the bare word daedric,
        /// which is a vanilla Skyrim material that names thousands of ordinary
        /// armour, weapon and texture files.
        /// </summary>
        //
        // Data\Interface\startmenu.swf and loadwaitspinner.swf are NOT here any
        // more. From 2026-09-16 Thornswood ships its own copies of both, a main
        // menu with no Bethesda logo and no button list so the backdrop stands
        // alone, and an empty spinner. The pack overwrites another server's copy
        // on the way in, so nothing has to be moved aside, and listing them here
        // would make Fix quarantine our own files on every scan.
        public static readonly string[] ForeignPaths = {
            "Data\\Video\\Interface\\startmenu.swf",
            "Data\\Video\\Interface\\loadwaitspinner.swf",
        };

        /// <summary>What is left behind after something is moved aside, so the
        /// checks do not keep reporting a file that is already disabled.</summary>
        public const string OffSuffix = ".thornswood-off";

        public static string[] ForeignClients()
        {
            var found = new List<string>();
            try
            {
                string dir = Path.Combine(Paths.Game, "Data\\SKSE\\Plugins");
                foreach (string n in ForeignNames)
                {
                    string f = Path.Combine(dir, n);
                    if (File.Exists(f)) found.Add(f);
                }
                foreach (string rel in ForeignPaths)
                {
                    string f = Path.Combine(Paths.Game, rel);
                    if (File.Exists(f) || Directory.Exists(f)) found.Add(f);
                }
            }
            catch { }
            return found.ToArray();
        }

        /// <summary>
        /// Plugins that have to carry the ESL flag for the load order to line up
        /// with the server's.
        ///
        /// SkyMP resolves a form as fileIdx * 0x01000000 + shortFormId, with
        /// fileIdx the plugin's position in the server's list, and the client
        /// counts its own with Game.GetModCount, which skips every light plugin.
        /// The server leaves light plugins out for the same reason, and it also
        /// has to leave out anything that masters to one, because libespm will
        /// not load a plugin whose master is absent.
        ///
        /// MCMHelper.esp masters to SkyUI_SE.esp, which is light, so the server
        /// drops it. MCM Helper ships two copies of that plugin in its archive,
        /// identical to the byte apart from this one flag, and the collection
        /// installs the one without it. The game hands that one an index, the
        /// server has no such entry, and from that position on every plugin on
        /// the client is one place away from the server's copy. On 2026-09-16
        /// that was the whole of "connects, then sits on the main menu".
        ///
        /// The file is 100 bytes and holds no records, so flagging it costs
        /// nothing and the mod keeps working. This is what the author's own ESL
        /// variant is.
        /// </summary>
        public static readonly string[] MustBeLight = {
            "MCMHelper.esp",
        };

        const uint LightFlag = 0x200;

        /// <summary>True when the TES4 header carries the ESL flag. A file that
        /// cannot be read answers true, so nothing is reported for it.</summary>
        static bool IsLight(string path)
        {
            try
            {
                using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                {
                    var b = new byte[12];
                    if (fs.Read(b, 0, 12) < 12) return true;
                    if (b[0] != (byte)'T' || b[1] != (byte)'E' || b[2] != (byte)'S' || b[3] != (byte)'4') return true;
                    uint flags = BitConverter.ToUInt32(b, 8);
                    return (flags & LightFlag) != 0;
                }
            }
            catch { return true; }
        }

        /// <summary>The plugins in MustBeLight that are present and not yet light.</summary>
        public static List<string> NotLight()
        {
            var l = new List<string>();
            string data = Path.Combine(Paths.Game, "Data");
            foreach (string n in MustBeLight)
            {
                string p = Path.Combine(data, n);
                try { if (File.Exists(p) && !IsLight(p)) l.Add(n); } catch { }
            }
            return l;
        }

        /// <summary>
        /// Sets the ESL flag on each plugin in MustBeLight that lacks it. One
        /// byte, in place, so a Vortex hard link stays a hard link and the
        /// staging copy is corrected with it. Returns how many were changed.
        /// </summary>
        public static int FlagLight(Action<string> say)
        {
            int n = 0;
            string data = Path.Combine(Paths.Game, "Data");
            foreach (string name in NotLight())
            {
                string p = Path.Combine(data, name);
                try
                {
                    try { File.SetAttributes(p, FileAttributes.Normal); } catch { }
                    using (var fs = new FileStream(p, FileMode.Open, FileAccess.ReadWrite, FileShare.ReadWrite))
                    {
                        var b = new byte[4];
                        fs.Seek(8, SeekOrigin.Begin);
                        if (fs.Read(b, 0, 4) < 4) continue;
                        uint flags = BitConverter.ToUInt32(b, 0) | LightFlag;
                        fs.Seek(8, SeekOrigin.Begin);
                        fs.Write(BitConverter.GetBytes(flags), 0, 4);
                    }
                    n++;
                    if (say != null) say(name + " is now flagged light, so your load order counts the same way the server's does.");
                }
                catch (Exception ex)
                {
                    if (say != null) say("Could not flag " + name + " light: " + ex.Message + "  Close Skyrim and Vortex and try again.");
                }
            }
            return n;
        }

        /// <summary>
        /// Moves another server's files aside. It never deletes anything.
        ///
        /// Somebody who plays Thornswood may also play Keizaal Online or
        /// Daedric Online, and their install is theirs. Two steps, because the
        /// game can sit on a different drive from the launcher:
        ///
        ///   1. Rename in place with .thornswood-off. Always on the same
        ///      volume, so it always works, and a renamed dll is not loaded by
        ///      the script extender and a renamed swf is not read by Skyrim.
        ///   2. Move the renamed item into Profile\Isolated, best effort. If
        ///      that fails it stays renamed where it is, still disabled.
        ///
        /// Either way restore.txt in the Isolated folder records where each
        /// item came from and where it went, so it can be put back by hand.
        ///
        /// Named files and exact paths only, nothing matched by pattern.
        /// </summary>
        public static int IsolateForeign(Action<string> say)
        {
            int n = 0;
            string stamp = DateTime.Now.ToString("yyyyMMdd-HHmm");
            string bin = Path.Combine(Paths.Isolated, stamp);

            foreach (string f in ForeignClients())
            {
                string name = Path.GetFileName(f);
                try
                {
                    bool isDir = Directory.Exists(f);
                    string off = f + OffSuffix;
                    if (File.Exists(off) || Directory.Exists(off)) off = off + "-" + stamp;

                    if (isDir)
                    {
                        Directory.Move(f, off);
                    }
                    else
                    {
                        try { File.SetAttributes(f, FileAttributes.Normal); } catch { }
                        File.Move(f, off);
                    }

                    string landed = off;
                    try
                    {
                        Directory.CreateDirectory(bin);
                        string dest = Path.Combine(bin, Path.GetFileName(off));
                        if (isDir) Directory.Move(off, dest); else File.Move(off, dest);
                        landed = dest;
                    }
                    catch { }

                    NoteIsolated(bin, f, landed);
                    n++;
                    if (say != null)
                        say(name + " belongs to another server. Moved aside to " + landed +
                            ". Nothing was deleted, and it can be put back.");
                }
                catch (Exception ex)
                {
                    if (say != null)
                        say("Could not move " + name + " aside: " + ex.Message +
                            "  Close Skyrim and try again.");
                }
            }
            return n;
        }

        static void NoteIsolated(string bin, string from, string to)
        {
            try
            {
                Directory.CreateDirectory(bin);
                File.AppendAllText(Path.Combine(bin, "restore.txt"),
                    DateTime.Now.ToString("s") + "  was: " + from + Environment.NewLine +
                    "                     now: " + to + Environment.NewLine);
            }
            catch { }
        }

        /// <summary>Old name. Kept so nothing that still calls it deletes
        /// anything, because it never did anything else after this change.</summary>
        public static int RemoveForeign(Action<string> say) { return IsolateForeign(say); }

        public static List<Check> All(Config cfg)
        {
            long bytes = 0;
            try { if (File.Exists(Paths.Exe)) bytes = new FileInfo(Paths.Exe).Length; } catch { }
            int plugins = EnabledPlugins();

            var l = new List<Check>();
            l.Add(new Check("Game build", bytes == cfg.ExpectedExeBytes, Downgrade.Describe(cfg)));
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

            string[] foreign = ForeignClients();
            l.Add(new Check("Other servers",
                            foreign.Length == 0,
                            foreign.Length == 0
                                ? "none"
                                : (foreign.Length == 1 ? "1 client file, open Mods"
                                                       : foreign.Length + " client files, open Mods")));

            // The plugin that walks past the main menu.
            //
            // This helper has existed the whole time and nothing ever showed
            // its answer, so the launcher said everything checks out while the
            // one thing that actually puts somebody into the world was missing.
            // The symptom is not an error: the game opens on NEW, LOAD, QUIT
            // and waits, which reads as the server ignoring you.
            //
            // It is worth its own row rather than folding into Mods, because
            // neither the installer nor the collection delivers it. The
            // launcher writes po3_StartOnSave.ini on every Play, so the config
            // for it is always present and proves nothing about the dll.
            l.Add(new Check("Auto load",
                            StartOnSaveInstalled(),
                            StartOnSaveInstalled()
                                ? "walks past the main menu"
                                : "Start On Save is missing, install it in Vortex"));

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
                string log = Path.Combine(Paths.LiveMyGames, "SKSE\\skse64.log");
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
        // Asking a hung process for its own path is allowed to take forever,
        // and this is read from the UI thread on every redraw, so one wedged
        // Skyrim froze the entire launcher. It gets one bounded attempt per
        // process and the answer is kept, so a stuck game costs a second and
        // a half once instead of the window every time it is drawn.
        static readonly Dictionary<int, string> pathCache = new Dictionary<int, string>();

        static string PathOf(Process p)
        {
            int id;
            try { id = p.Id; } catch { return null; }
            lock (pathCache)
            {
                string had;
                if (pathCache.TryGetValue(id, out had)) return had;
            }

            string got = null;
            try
            {
                var t = new Thread(delegate() { try { got = p.MainModule.FileName; } catch { } });
                t.IsBackground = true;
                t.Start();
                if (!t.Join(1500)) got = null;
            }
            catch { got = null; }

            lock (pathCache)
            {
                if (pathCache.Count > 256) pathCache.Clear();
                pathCache[id] = got;
            }
            return got;
        }

        static bool? Where(Process p)
        {
            string path = PathOf(p);
            if (string.IsNullOrEmpty(path)) return null;
            try
            {
                string full = Path.GetFullPath(path);

                // Two roots, not one. This tested Paths.Root alone, which is
                // right for an install that built its own copy of the game
                // underneath it, and wrong for every collection install: the
                // game runs out of the Steam folder, which is nowhere near
                // Root, so the running Skyrim was judged to be somebody else's.
                //
                // Everything downstream then went wrong at once. GameRunning
                // said no while the game was plainly on screen, Close Skyrim
                // closed nothing and reported nothing to close, the update
                // refused to start because it could not clear a game it could
                // not see, and the only thing that did fire was the warning
                // about a different Skyrim running from another folder.
                //
                // The launcher lives under Root. The game lives under
                // Paths.Game, which is Root\Game in an old install and the
                // Steam copy in a collection one. Either counts as ours.
                foreach (string r in new string[] { Paths.Root, Paths.Game })
                {
                    if (string.IsNullOrEmpty(r)) continue;
                    string root = Path.GetFullPath(r).TrimEnd('\\') + "\\";
                    if (root.Length < 4) continue;
                    if (full.StartsWith(root, StringComparison.OrdinalIgnoreCase)) return true;
                }
                return false;
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
