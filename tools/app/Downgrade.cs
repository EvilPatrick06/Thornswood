using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace Thornswood
{
    /// <summary>
    /// Puts a Steam copy of Skyrim that is on a newer build back on 1.6.1170,
    /// the build the server runs, from one button and with nothing to paste.
    ///
    /// Steam will hand over any build's files to somebody who owns the game,
    /// through the console command "download_depot", but only from its own
    /// console: there is no URL or command line for it. So this opens that
    /// console (steam://open/console), makes sure Steam's window is the one
    /// in front, types the command into it the way a person would, and then
    /// watches Steam's own content_log.txt for "Depot download complete".
    /// Three depots make up the game; they go one at a time, as Steam wants.
    /// When all three are down, the files are copied over the Steam copy,
    /// the exe is checked against the size 1.6.1170 has, and the downloaded
    /// copies are removed so eleven gigabytes do not stay behind.
    ///
    /// Nothing is typed unless Steam's window is confirmed to be the one in
    /// the foreground. If it cannot be brought there, the command goes on the
    /// clipboard and the log says where to paste it, and the watching carries
    /// on all the same.
    ///
    /// The earlier install shape did this from Setup-Thornswood.ps1 with the
    /// person pasting the three lines. The site tells people to pick the build
    /// in Steam's Betas list; a tester asked for a button instead, for people
    /// who are not at home in Steam's settings. This is that button.
    /// </summary>
    static class Downgrade
    {
        const int AppId = 489830;

        // How long nothing may happen before this stops waiting. Measured from
        // the last time the download folder grew, not from the start, so a slow
        // line is never cut off: any progress at all resets it. See the loop
        // below for why a deadline is needed at all.
        const int GiveUpMinutes = 25;
        // Depot id -> the manifest of that depot at 1.6.1170. Same three as
        // Setup-Thornswood.ps1. (Build-Thornswood.ps1 was deleted on 23
        // September: it could not produce a working build any more.)
        static readonly string[][] Depots = {
            new[] { "489831", "8442952117333549665" },
            new[] { "489832", "8042843504692938467" },
            new[] { "489833", "1914580699073641964" },
        };
        /// <summary>SkyrimSE.exe at 1.7.104, the Steam build we never want.</summary>
        public const long NewerExeBytes = 37910440;

        // The processes whose windows are Steam's. Only "steam" was looked for
        // until 24 September, and a tester on 1.1.91 got every part on the
        // clipboard with Steam's console open behind the launcher: "its not
        // going into the console by itself its going to your clipboard"
        // (Patrick). Measured on Patrick's machine that day, with Steam in the
        // tray: Steam's main window (class SDL_app, titled "Steam", 2308 x 927)
        // belongs to steamwebhelper.exe, and steam.exe owns three small popups,
        // none bigger than 149 x 77, so a window that is really Steam's never
        // counted as Steam in front.
        // steamwebhelper is Steam's own and nothing else ships one.
        static readonly string[] SteamNames = { "steam", "steamwebhelper" };

        // The last window the log named as Steam's, so it is said once a run
        // and again only if a different one is found.
        static string saidWindow;

        static Thread worker;
        // Cleared before done is called, not when the thread ends, so what done
        // starts (Thornswood's own folder brought up to date) does not find the
        // downgrade still busy.
        static volatile bool running;
        public static bool Busy { get { return running; } }

        /// <summary>The game is there and its exe is not the build the server runs.</summary>
        public static bool Needed(Config cfg) { return Wrong(cfg, Paths.Exe); }

        /// <summary>
        /// Thornswood runs from its own folder (OwnGame) and the Steam copy that
        /// folder is made from is on another build, which is what Steam does by
        /// itself when it updates the game. Thornswood still plays, but the next
        /// refresh from Vortex would bring that build in, so OwnGame refuses to
        /// refresh until this is put right.
        /// </summary>
        public static bool SourceNeeded(Config cfg)
        {
            if (!OwnGame.Active) return false;
            string src = OwnGame.Source(cfg);
            return src.Length > 0 && Wrong(cfg, Path.Combine(src, "SkyrimSE.exe"));
        }

        /// <summary>
        /// The Skyrim folder the downgrade writes into. With Thornswood's own
        /// folder that is the Steam copy the folder is made from, never the own
        /// folder: its files are brought over from the Steam copy afterwards, the
        /// same way a Vortex deployment is, so the two cannot end up on different
        /// builds. Otherwise the folder the game runs from.
        /// </summary>
        public static string Target(Config cfg)
        {
            if (OwnGame.Active)
            {
                string src = OwnGame.Source(cfg);
                if (src.Length > 0) return src;
            }
            return Paths.Game;
        }

        static bool SameFolder(string a, string b)
        {
            try { return string.Equals(Path.GetFullPath(a).TrimEnd('\\'), Path.GetFullPath(b).TrimEnd('\\'), StringComparison.OrdinalIgnoreCase); }
            catch { return false; }
        }

        static bool Wrong(Config cfg, string exe)
        {
            try
            {
                if (!File.Exists(exe)) return false;
                return new FileInfo(exe).Length != cfg.ExpectedExeBytes;
            }
            catch { return false; }
        }

        /// <summary>What the check row should say about the build.</summary>
        public static string Describe(Config cfg) { return Describe(cfg, Paths.Exe); }

        public static string Describe(Config cfg, string exe)
        {
            try
            {
                if (!File.Exists(exe)) return "missing";
                long n = new FileInfo(exe).Length;
                if (n == cfg.ExpectedExeBytes) return "1.6.1170";
                if (n == NewerExeBytes) return "1.7.104, the server runs 1.6.1170";
                return "not 1.6.1170";
            }
            catch { return "unknown"; }
        }

        /// <summary>
        /// The three lines typed into Steam's console, in the order they are
        /// typed. The Downgrade button shows these before anything starts, and
        /// Run types the same strings, so the question cannot name one command
        /// and the keyboard send another.
        /// </summary>
        public static string[] Commands()
        {
            var all = new string[Depots.Length];
            for (int i = 0; i < Depots.Length; i++) all[i] = Command(Depots[i]);
            return all;
        }

        static string Command(string[] depot)
        {
            return "download_depot " + AppId + " " + depot[0] + " " + depot[1];
        }

        /// <summary>
        /// Runs the whole thing on its own thread. <paramref name="log"/> goes
        /// to the launcher log, <paramref name="status"/> to the one line under
        /// the button, <paramref name="done"/> fires at the end either way with
        /// true when the exe is now 1.6.1170. All three may be called from the
        /// worker thread.
        /// </summary>
        public static void Start(Config cfg, Action<string> log, Action<string> status, Action<bool> done)
        {
            if (Busy) return;
            running = true;
            worker = new Thread(delegate ()
            {
                bool ok = false;
                try { ok = Run(cfg, log, status); }
                catch (Exception ex) { log("Downgrade stopped: " + ex.Message); }
                finally { running = false; }
                try { done(ok); } catch { }
            });
            worker.IsBackground = true;
            worker.SetApartmentState(ApartmentState.STA);   // the clipboard fallback needs it
            try { worker.Start(); }
            catch { running = false; throw; }
        }

        static bool Run(Config cfg, Action<string> log, Action<string> status)
        {
            string steam = Steam.Path_();
            if (string.IsNullOrEmpty(steam) || !Directory.Exists(steam))
            {
                log("Could not find where Steam is installed, so Steam cannot be asked for the files.");
                return false;
            }
            string content = Path.Combine(steam, "steamapps\\content\\app_" + AppId);
            string logFile = Path.Combine(steam, "logs\\content_log.txt");

            if (Checks.GameRunning())
            {
                log("Skyrim is running. Close it, then press the button again.");
                return false;
            }

            string target = Target(cfg);
            string targetExe = Path.Combine(target, "SkyrimSE.exe");
            bool ownFolder = !SameFolder(target, Paths.Game);
            if (ownFolder)
            {
                // Another server's session plays out of the Steam copy, and its
                // files cannot be replaced while that runs.
                if (Checks.OtherSkyrimRunning())
                {
                    log("A Skyrim from another folder is running, most likely another server's session in the Steam copy. Close it, then press the button again.");
                    return false;
                }
                if (File.Exists(targetExe) && !Wrong(cfg, targetExe))
                {
                    log("The Steam copy in " + target + " is already on 1.6.1170, so nothing needs downloading. Thornswood's own folder is brought up to date from it next.");
                    status("The Steam copy is already on 1.6.1170.");
                    return true;
                }
                log("Thornswood runs from its own folder, which is made from the Steam copy in " + target + ". The Steam copy is downgraded, then the folder is brought up to date from it.");
            }

            log("Downgrading Skyrim to 1.6.1170. Steam downloads the build's files under your own account; nothing is touched until all three parts are down.");
            saidWindow = null;
            status("Opening Steam...");
            if (!WaitForSteam(log, status)) return false;

            for (int i = 0; i < Depots.Length; i++)
            {
                string depot = Depots[i][0], manifest = Depots[i][1];
                string folder = Path.Combine(content, "depot_" + depot);
                string cmd = Command(Depots[i]);

                // The marker holds the manifest it was written for, and only
                // that manifest counts as this build being down. A folder left
                // by an attempt at another build is full of the wrong files,
                // and skipping the depot on one of those copies them over the
                // Steam copy as if they were 1.6.1170.
                if (Directory.Exists(folder) && MarkerIs(folder, manifest))
                {
                    log("Part " + (i + 1) + " of 3 (depot " + depot + ") is already downloaded.");
                    continue;
                }

                long logStart = 0;
                try { if (File.Exists(logFile)) logStart = new FileInfo(logFile).Length; } catch { }

                status("Part " + (i + 1) + " of 3: asking Steam for depot " + depot + "...");
                log("Part " + (i + 1) + " of 3, depot " + depot + ": " + cmd);
                bool typed = TypeIntoConsole(cmd, log);
                bool pasted = !typed;
                if (!typed)
                    OnClipboard(cmd, i + 1, "Steam's window would not come to the front, so nothing was typed. ", log, status);

                // Steam makes the depot folder within seconds of taking the
                // command. No folder after a while means it did not take.
                //
                // The folder and the log are kept apart from here on. A folder
                // an aborted attempt left behind is there before Steam has been
                // asked anything, which is enough to carry on watching but is
                // no proof that this run's download ever started. Only the log
                // is that proof, and the fallback below needs it.
                DateTime askedAt = DateTime.Now;
                bool started = false;
                bool sawStart = false;
                while ((DateTime.Now - askedAt).TotalSeconds < 45)
                {
                    if (LogSays(logFile, logStart, "depot_" + depot)) sawStart = true;
                    if (Directory.Exists(folder) || sawStart) { started = true; break; }
                    Thread.Sleep(1000);
                }
                if (!started && typed)
                {
                    // Typed into the wrong place, most likely a console whose
                    // command line did not have the focus. Click it and try once
                    // more, then fall back to the clipboard.
                    log("Steam has not started the download. Trying the console's command line once more.");
                    FocusConsole();
                    Thread.Sleep(400);
                    typed = TypeIntoConsole(cmd, log);
                    askedAt = DateTime.Now;
                    while ((DateTime.Now - askedAt).TotalSeconds < 30)
                    {
                        if (LogSays(logFile, logStart, "depot_" + depot)) sawStart = true;
                        if (Directory.Exists(folder) || sawStart) { started = true; break; }
                        Thread.Sleep(1000);
                    }
                    if (!started)
                    {
                        // Whatever Steam put in its own content log since the
                        // command. A real refusal ("No connection", a manifest
                        // error) shows here; nothing here means the command
                        // never reached the console's command line at all.
                        string tail = NewLog(logFile, logStart);
                        if (tail.Length > 0) log("Steam's content log since the command:" + Environment.NewLine + tail);
                        else log("Steam wrote nothing to its content log, so the command did not reach the console's command line. Steam's console has to be the window in front with its command line clicked.");
                        OnClipboard(cmd, i + 1, "", log, status);
                        pasted = true;
                    }
                }

                // Wait for "Depot download complete" for this depot. Progress
                // is the size of the folder Steam is filling.
                long lastSize = -1;
                DateTime lastGrowth = DateTime.Now;
                bool warned = false;
                string downloading = Path.Combine(steam, "steamapps\\downloading\\" + AppId);
                while (true)
                {
                    if (LogHasCompletion(logFile, logStart, depot)) break;
                    long size = FolderSize(folder);
                    if (size != lastSize) { lastSize = size; lastGrowth = DateTime.Now; warned = false; }
                    status(ProgressLine(i + 1, Depots.Length, size, pasted));
                    double quiet = (DateTime.Now - lastGrowth).TotalMinutes;
                    if (!warned && quiet > 10)
                    {
                        warned = true;
                        log("Steam has not written anything for ten minutes. Check that Steam is still open and signed in; the download carries on where it left off.");
                    }
                    // Steam's log has always said "Depot download complete" so
                    // far. If a Steam build stops saying it, a full folder that
                    // has been still for a long while with nothing left in
                    // Steam's downloading folder is the next best proof.
                    //
                    // Only for a download this run started, though. A folder an
                    // aborted run left half written is also full and still, and
                    // taking that as done writes the marker and copies truncated
                    // files over the Steam copy, after which every later attempt
                    // skips the depot as already downloaded.
                    if (size > 0 && quiet > 20 && !Directory.Exists(downloading))
                    {
                        if (!sawStart && LogSays(logFile, logStart, "depot_" + depot)) sawStart = true;
                        if (sawStart)
                        {
                            log("Steam's log never said the download finished, but the folder has been complete and still for twenty minutes, so it is taken as done.");
                            break;
                        }
                        log("Steam never started this download, and " + folder + " is left over from an earlier attempt, so what is in it cannot be trusted. Delete that folder, then press the button again.");
                        return false;
                    }

                    /*
                      AND A DEADLINE, BECAUSE THIS USED TO BE while(true) WITH
                      NO WAY OUT.

                      Every exit above needs something to have happened: the
                      log saying the download finished, or the folder being
                      non-empty and still. Steam refusing outright satisfies
                      neither. It writes its refusal to its own console, this
                      folder never appears, size stays at zero, and the loop
                      carries on at two seconds a turn for ever behind a
                      progress line that will never move. There is nothing on
                      screen that says so, and nothing a person watching it
                      could do but guess.

                      So: nothing has changed for GiveUpMinutes, stop and say
                      which outside thing did not answer, and leave the manual
                      path on screen. Measured against progress rather than
                      against the clock from the start, so a genuinely slow
                      download on a slow line is never cut off: the folder
                      growing at all resets it.
                    */
                    if (quiet > GiveUpMinutes)
                    {
                        log("Steam has done nothing for " + GiveUpMinutes + " minutes and this part is still " + (size / 1048576).ToString("n0") + " MB, so it is being given up on rather than waited on for ever.");
                        if (size == 0)
                            log("Nothing was downloaded at all, which usually means Steam refused the command. Its console window says why: look for a line about a manifest, a licence or no connection.");
                        log("To do it by hand: open Steam, press Ctrl+Shift+D or start it with -console, click the console's command line, and paste " + cmd);
                        status("Steam did not answer. See the log for what to do by hand.");
                        return false;
                    }
                    Thread.Sleep(2000);
                }
                try { File.WriteAllText(Path.Combine(folder, ".thornswood-complete"), manifest); } catch { }
                log("Part " + (i + 1) + " of 3 is down (depot " + depot + ", " + (FolderSize(folder) / 1048576).ToString("n0") + " MB).");
            }

            // ---- apply ------------------------------------------------------
            if (Checks.GameRunning())
            {
                log("Skyrim started while the files were coming down. Close it and press the button again; the downloads are kept.");
                return false;
            }
            status("Putting the 1.6.1170 files in place...");
            // A file a mod replaces is the collection's, and in the Steam copy it
            // is a hard link to Vortex's own copy: writing the vanilla file over
            // it would change the mod inside Vortex. Those are left as they are.
            HashSet<string> modded = OwnGame.DeployedIn(target);
            long copied = 0; int files = 0, leftForMods = 0;
            foreach (string[] d in Depots)
            {
                string folder = Path.Combine(content, "depot_" + d[0]);
                if (!Directory.Exists(folder)) continue;
                string prefix = folder.TrimEnd('\\') + "\\";
                foreach (string f in Directory.GetFiles(folder, "*", SearchOption.AllDirectories))
                {
                    string rel = f.Substring(prefix.Length);
                    if (rel.StartsWith(".thornswood", StringComparison.OrdinalIgnoreCase)) continue;
                    if (modded.Contains(rel)) { leftForMods++; continue; }
                    string dest = Path.Combine(target, rel);
                    try
                    {
                        Directory.CreateDirectory(Path.GetDirectoryName(dest));
                        // The name comes off before the copy, so the new file is
                        // this folder's alone. Copying over the name would write
                        // through any hard link to it, including the links in
                        // Thornswood's own folder, which are brought up to date
                        // from here afterwards.
                        if (File.Exists(dest)) OwnGame.DropName(dest);
                        File.Copy(f, dest, false);
                        copied += new FileInfo(f).Length; files++;
                        if (files % 25 == 0) status("Putting the 1.6.1170 files in place: " + (copied / 1048576).ToString("n0") + " MB");
                    }
                    catch (Exception ex)
                    {
                        log("Could not replace " + rel + ": " + ex.Message);
                        return false;
                    }
                }
            }
            log("Copied " + files + " files, " + (copied / 1048576).ToString("n0") + " MB, into " + target + "." +
                (leftForMods > 0 ? " " + leftForMods + " that a mod replaces were left as the mod has them." : ""));

            bool right = File.Exists(targetExe) && !Wrong(cfg, targetExe);
            if (!right)
            {
                log("SkyrimSE.exe is still not the 1.6.1170 build after the copy (" + Describe(cfg, targetExe) + "). Send your launcher log to the Discord.");
                return false;
            }

            status("Cleaning up the downloaded copies...");
            long freed = 0;
            foreach (string[] d in Depots)
            {
                string folder = Path.Combine(content, "depot_" + d[0]);
                try { freed += FolderSize(folder); Directory.Delete(folder, true); } catch { }
            }
            try { if (Directory.Exists(content) && Directory.GetFileSystemEntries(content).Length == 0) Directory.Delete(content); } catch { }
            log("Skyrim is on 1.6.1170. " + (freed / 1048576).ToString("n0") + " MB of downloaded copies removed from Steam's folder.");
            log("Do not start Skyrim through Steam from here on: Steam would update it back, and you would be here again. Play from this launcher.");
            status("Done. Skyrim is on 1.6.1170.");
            return true;
        }

        // ------------------------------------------------------------ steam

        static Process SteamProcess()
        {
            try
            {
                foreach (Process p in Process.GetProcessesByName("steam")) return p;
            }
            catch { }
            return null;
        }

        static bool WaitForSteam(Action<string> log, Action<string> status)
        {
            if (SteamProcess() == null)
            {
                log("Steam is not running. Starting it; sign in if it asks.");
                try { Process.Start(new ProcessStartInfo("steam://open/main") { UseShellExecute = true }); } catch { }
                DateTime t = DateTime.Now;
                while (SteamProcess() == null && (DateTime.Now - t).TotalSeconds < 90) Thread.Sleep(1000);
                if (SteamProcess() == null) { log("Steam did not start."); return false; }
                // Give it time to sign in and draw its window.
                status("Waiting for Steam to sign in...");
                DateTime t2 = DateTime.Now;
                while (MainWindow() == IntPtr.Zero && (DateTime.Now - t2).TotalSeconds < 120) Thread.Sleep(1000);
            }
            return true;
        }

        /// <summary>
        /// Opens Steam's console, brings Steam in front, confirms Steam's window
        /// is the foreground one, and types the command with Enter. False when
        /// the window never came to the front; nothing is typed then.
        /// </summary>
        static bool TypeIntoConsole(string cmd, Action<string> log)
        {
            try { Process.Start(new ProcessStartInfo("steam://open/console") { UseShellExecute = true }); } catch { }

            // Steam's window can take a while to come up, longer still when the
            // client was sitting in the tray, and the first request for the
            // console is sometimes swallowed while it is busy. So: up to twenty
            // seconds, and the console is asked for again halfway.
            bool front = false;
            bool reopened = false;
            IntPtr h = IntPtr.Zero;
            DateTime start = DateTime.Now;
            while (!front && (DateTime.Now - start).TotalSeconds < 20)
            {
                Thread.Sleep(500);
                h = MainWindow();
                if (h == IntPtr.Zero) continue;
                SayWindow(h, log);
                BringToFront(h);
                Thread.Sleep(400);
                front = SteamInFront(h);
                if (!front && !reopened && (DateTime.Now - start).TotalSeconds > 8)
                {
                    reopened = true;
                    try { Process.Start(new ProcessStartInfo("steam://open/console") { UseShellExecute = true }); } catch { }
                }
            }
            if (!front) return false;

            // A moment for the console page to finish drawing.
            Thread.Sleep(1200);
            if (!SteamInFront(h)) return false;

            // Then a click on the command line. Opening the console puts the
            // keyboard there when the page is new, and not when the tab was
            // already open: on 17 Sep the button brought Steam up, said it had
            // typed, and the console showed the old line untouched, because
            // select all, delete and the command had all gone to the page and
            // not to its input. The command line sits along the bottom of the
            // console page, above the status bar, and that is where this
            // clicks, scaled for the monitor Steam is on.
            ClickCommandLine(h);
            Thread.Sleep(150);
            if (!SteamInFront(h)) return false;

            // Whatever is on the command line goes first. The retry used to
            // type the command a second time onto the first one, and Steam ran
            // "download_depot ... 8442952117333549665download_depot ..." (Djinn,
            // 17 Sep). Select all, delete, then type.
            Chord(VK_CONTROL, VK_A);
            Thread.Sleep(80);
            Key(VK_BACK);
            Thread.Sleep(120);
            Type(cmd);
            Thread.Sleep(250);
            // Twice. Steam's console suggests commands as you type, and while a
            // suggestion is up the first Enter takes the suggestion instead of
            // running the line; that is how the command sat there typed and not
            // run. With no suggestion up, the second Enter runs an empty line,
            // which Steam ignores.
            Key(VK_RETURN);
            Thread.Sleep(350);
            Key(VK_RETURN);
            return true;
        }

        /// <summary>
        /// Puts Steam's window in front and makes sure it took.
        ///
        /// Windows only lets the foreground process hand the foreground on, and
        /// this runs on a worker thread of a launcher that stopped being the
        /// foreground process the moment Steam's window appeared. A plain
        /// SetForegroundWindow is refused then, quietly. Attaching to Steam's
        /// input thread for the call is the documented way through; a tap of
        /// Alt is the other, because a key press from us counts as the person's
        /// and the system lets the next SetForegroundWindow through after one.
        /// </summary>
        static void BringToFront(IntPtr h)
        {
            try
            {
                // Restored only when it is minimised. Restoring a maximised
                // window un-maximises it, which every attempt did to Steam once
                // its real window was the one found (review, 24 September).
                if (IsIconic(h)) ShowWindow(h, SW_RESTORE);
                uint pid;
                uint steamThread = GetWindowThreadProcessId(h, out pid);
                uint me = GetCurrentThreadId();
                bool attached = steamThread != 0 && steamThread != me && AttachThreadInput(me, steamThread, true);
                try
                {
                    BringWindowToTop(h);
                    SetForegroundWindow(h);
                }
                finally
                {
                    if (attached) AttachThreadInput(me, steamThread, false);
                }
                if (SteamInFront(h)) return;
                Key(VK_MENU);
                Thread.Sleep(50);
                SetForegroundWindow(h);
            }
            catch { }
        }

        /// <summary>
        /// Puts the keyboard back on the console's command line for a retry.
        /// This used to click 28 pixels up from the bottom edge of Steam's
        /// window, where the command line was in the old client. In the
        /// current client that is the status bar, Downloads and Friends and
        /// Chat, so the click opened another page instead of focusing
        /// anything. Opening the console again focuses its command line, and
        /// nothing is clicked.
        /// </summary>
        static void FocusConsole()
        {
            try { Process.Start(new ProcessStartInfo("steam://open/console") { UseShellExecute = true }); } catch { }
            Thread.Sleep(1500);
            IntPtr h = MainWindow();
            if (h == IntPtr.Zero) return;
            BringToFront(h);
            Thread.Sleep(300);
            if (SteamInFront(h)) ClickCommandLine(h);
        }

        /// <summary>
        /// One click on the console's command line.
        ///
        /// Measured on the current Steam client at 100 percent scaling: the
        /// input's centre is 72 pixels above the bottom edge of the window,
        /// with the status bar (Downloads, Friends and Chat) below it. Steam
        /// draws itself at its monitor's scale, and this process sees window
        /// coordinates at the system's, so the offset is scaled by the ratio
        /// of the two. A Windows without GetDpiForWindow (before 10.0.1607)
        /// gets the ratio 1, which is right whenever the two scales agree.
        /// </summary>
        static void ClickCommandLine(IntPtr h)
        {
            if (h == IntPtr.Zero) return;
            RECT r;
            if (!GetWindowRect(h, out r)) return;
            double scale = 1.0;
            try
            {
                uint steam = GetDpiForWindow(h);
                uint system = GetDpiForSystem();
                if (steam > 0 && system > 0) scale = steam / (double)system;
            }
            catch { }
            int x = (r.Left + r.Right) / 2;
            int y = r.Bottom - (int)Math.Round(72 * scale);
            SetCursorPos(x, y);
            Thread.Sleep(80);
            Mouse(MOUSEEVENTF_LEFTDOWN);
            Thread.Sleep(60);
            Mouse(MOUSEEVENTF_LEFTUP);
        }

        static bool ForegroundIsSteam()
        {
            try
            {
                IntPtr fg = GetForegroundWindow();
                if (fg == IntPtr.Zero) return false;
                uint pid;
                GetWindowThreadProcessId(fg, out pid);
                if (pid == 0) return false;
                return IsSteam(Process.GetProcessById((int)pid).ProcessName);
            }
            catch { return false; }
        }

        /// <summary>
        /// Steam is in front, and it is the window this brought forward or a
        /// window inside it. Any Steam window was not enough once windows drawn
        /// by steamwebhelper counted as Steam's: the Friends list, a chat window
        /// or the sign-in box can be the one in front, and a download_depot line
        /// and two Enters typed into a chat would go to a friend as a message.
        /// Found in review, 24 September.
        /// </summary>
        static bool SteamInFront(IntPtr h)
        {
            if (h == IntPtr.Zero || !ForegroundIsSteam()) return false;
            try
            {
                IntPtr fg = GetForegroundWindow();
                return fg == h || GetAncestor(fg, GA_ROOT) == h;
            }
            catch { return false; }
        }

        /// <summary>A process named steam or steamwebhelper, in any case.</summary>
        static bool IsSteam(string processName)
        {
            foreach (string name in SteamNames)
                if (string.Equals(processName, name, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }

        /// <summary>Steam's biggest visible top level window, drawn by steam or by steamwebhelper.</summary>
        static IntPtr MainWindow()
        {
            IntPtr best = IntPtr.Zero;
            long bestArea = 0;
            var pids = new HashSet<uint>();
            try { foreach (string name in SteamNames) foreach (Process p in Process.GetProcessesByName(name)) pids.Add((uint)p.Id); } catch { }
            if (pids.Count == 0) return IntPtr.Zero;
            EnumWindows(delegate (IntPtr h, IntPtr l)
            {
                try
                {
                    if (!IsWindowVisible(h)) return true;
                    uint pid;
                    GetWindowThreadProcessId(h, out pid);
                    if (!pids.Contains(pid)) return true;
                    RECT r;
                    if (!GetWindowRect(h, out r)) return true;
                    long area = (long)Math.Max(0, r.Right - r.Left) * Math.Max(0, r.Bottom - r.Top);
                    if (area > bestArea) { bestArea = area; best = h; }
                }
                catch { }
                return true;
            }, IntPtr.Zero);
            return best;
        }

        /// <summary>
        /// Names the window taken for Steam's, the process that drew it, its
        /// title and its size, the first time it is found in a run and again
        /// only if another one is found. When the clipboard fallback comes up
        /// on somebody's machine, this line says whether Steam's window was
        /// found at all and which one it was.
        /// </summary>
        static void SayWindow(IntPtr h, Action<string> log)
        {
            string key = h.ToString();
            if (key == saidWindow) return;
            saidWindow = key;
            log("Found Steam's window: " + WindowWords(h) + ".");
        }

        static string WindowWords(IntPtr h)
        {
            uint pid;
            GetWindowThreadProcessId(h, out pid);
            string owner = "process " + pid;
            try { owner = Process.GetProcessById((int)pid).ProcessName + ", process " + pid; }
            catch { /* The process has gone; its number is still worth saying. */ }
            var title = new StringBuilder(256);
            try { GetWindowText(h, title, title.Capacity); }
            catch { /* No title is said as an empty one. */ }
            RECT r;
            string size = GetWindowRect(h, out r) ? (r.Right - r.Left) + " x " + (r.Bottom - r.Top) : "size unknown";
            return owner + ", titled \"" + title + "\", " + size;
        }

        /// <summary>
        /// A part's command goes on the clipboard, and the log, the line on the
        /// card and the launcher's taskbar button all say so.
        ///
        /// The parts go one at a time, so each command is put on the clipboard
        /// only when the part before it is down, in place of whatever was there.
        /// Until 24 September nothing said so, and a tester believed only the
        /// first command was ever given: "it only give you the fiurst one to
        /// yuor clipboards and not all of them" (Patrick). So the line names the
        /// part of three and says the rest follow here.
        ///
        /// The launcher is flashed rather than brought forward: a later part
        /// lands while the person is looking at Steam, and putting the launcher
        /// over Steam's console would cover the place they have to paste into.
        /// </summary>
        static void OnClipboard(string cmd, int part, string why, Action<string> log, Action<string> status)
        {
            TryClipboard(cmd);
            string line = ClipboardLine(part, Depots.Length);
            log(why + line + " This keeps watching for it.");
            status(line);
            FlashLauncher();
        }

        /// <summary>What the log and the card say when part <paramref name="part"/> of <paramref name="of"/> is on the clipboard.</summary>
        static string ClipboardLine(int part, int of)
        {
            string before = part > 1 ? Parts(1, part - 1, "is down.", "are down.") + " " : "";
            return before + "Part " + part + " of " + of + " is on your clipboard" + (part > 1 ? " now" : "") +
                ": click in Steam's console command line, press Ctrl+V and Enter. " + Next(part, of);
        }

        /// <summary>
        /// The line on the card while a part downloads. It stays there for the
        /// whole part, so a part that went on the clipboard keeps saying so:
        /// the paste itself while nothing has come down, and after that what
        /// follows.
        /// </summary>
        static string ProgressLine(int part, int of, long bytes, bool pasted)
        {
            if (pasted && bytes <= 0) return ClipboardLine(part, of);
            string line = "Part " + part + " of " + of + ": " + (bytes / 1048576).ToString("n0") + " MB down so far (Steam shows the rest in its console)";
            return pasted ? line + ". " + Next(part, of) : line;
        }

        static string Next(int part, int of)
        {
            if (part >= of) return "It is the last one.";
            return Parts(part + 1, of, "follows here when it is down.", "follow here when it is down.");
        }

        /// <summary>"Part 2 follows", "Parts 2 and 3 follow", "Parts 2 to 5 follow".</summary>
        static string Parts(int from, int to, string one, string many)
        {
            if (from >= to) return "Part " + from + " " + one;
            return "Parts " + from + (to == from + 1 ? " and " : " to ") + to + " " + many;
        }

        /// <summary>
        /// Flashes the launcher's taskbar button until the person comes back to
        /// it. FlashWindowEx only draws attention: it takes nothing from Steam's
        /// window and sends no input anywhere.
        /// </summary>
        static void FlashLauncher()
        {
            try
            {
                IntPtr me = Process.GetCurrentProcess().MainWindowHandle;
                if (me == IntPtr.Zero) return;
                var f = new FLASHWINFO();
                f.cbSize = (uint)Marshal.SizeOf(typeof(FLASHWINFO));
                f.hwnd = me;
                f.dwFlags = FLASHW_ALL | FLASHW_TIMERNOFG;
                f.uCount = uint.MaxValue;
                f.dwTimeout = 0;
                FlashWindowEx(ref f);
            }
            catch (Exception ex) { Swallow.Note("Downgrade.FlashLauncher", ex); }
        }

        static void TryClipboard(string text)
        {
            try { System.Windows.Clipboard.SetText(text); } catch { }
        }

        // ---------------------------------------------------------- watching

        /// <summary>The last few lines Steam wrote to its content log since <paramref name="from"/>, for the launcher log when a depot will not start.</summary>
        static string NewLog(string logFile, long from)
        {
            try
            {
                if (!File.Exists(logFile)) return "";
                using (var fs = new FileStream(logFile, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                {
                    if (fs.Length <= from) return "";
                    fs.Seek(from, SeekOrigin.Begin);
                    var buf = new byte[fs.Length - from];
                    int n = fs.Read(buf, 0, buf.Length);
                    string[] lines = Encoding.UTF8.GetString(buf, 0, n).Replace("\r", "").Trim().Split('\n');
                    int take = Math.Min(lines.Length, 12);
                    return string.Join(Environment.NewLine, lines, lines.Length - take, take).Trim();
                }
            }
            catch { return ""; }
        }

        static bool LogSays(string logFile, long from, string needle)
        {
            try
            {
                if (!File.Exists(logFile)) return false;
                using (var fs = new FileStream(logFile, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                {
                    if (fs.Length <= from) return false;
                    fs.Seek(from, SeekOrigin.Begin);
                    var buf = new byte[fs.Length - from];
                    int n = fs.Read(buf, 0, buf.Length);
                    string s = Encoding.UTF8.GetString(buf, 0, n);
                    return s.IndexOf(needle, StringComparison.OrdinalIgnoreCase) >= 0;
                }
            }
            catch { return false; }
        }

        /// <summary>
        /// True once Steam has logged this depot's download as complete, after
        /// the point in the log where the command was given. The line Steam
        /// writes names the folder, so both the words and the depot have to be
        /// on the same line.
        /// </summary>
        static bool LogHasCompletion(string logFile, long from, string depot)
        {
            try
            {
                if (!File.Exists(logFile)) return false;
                using (var fs = new FileStream(logFile, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                {
                    if (fs.Length <= from) return false;
                    fs.Seek(from, SeekOrigin.Begin);
                    var buf = new byte[fs.Length - from];
                    int n = fs.Read(buf, 0, buf.Length);
                    string s = Encoding.UTF8.GetString(buf, 0, n);
                    foreach (string line in s.Split('\n'))
                    {
                        if (line.IndexOf("Depot download complete", StringComparison.OrdinalIgnoreCase) < 0) continue;
                        if (line.IndexOf("depot_" + depot, StringComparison.OrdinalIgnoreCase) >= 0) return true;
                        if (line.IndexOf(depot, StringComparison.OrdinalIgnoreCase) >= 0) return true;
                    }
                }
            }
            catch { }
            return false;
        }

        /// <summary>
        /// True when this depot folder's completion marker was written for the
        /// manifest being asked for now. The marker holds the manifest id, so a
        /// folder from an attempt at another build reads as not downloaded and
        /// is fetched again. An empty or unreadable marker is the same answer:
        /// nothing in it says these are the files being asked for.
        /// </summary>
        static bool MarkerIs(string folder, string manifest)
        {
            try
            {
                string mark = Path.Combine(folder, ".thornswood-complete");
                if (!File.Exists(mark)) return false;
                return string.Equals(File.ReadAllText(mark).Trim(), manifest, StringComparison.Ordinal);
            }
            catch { return false; }
        }

        static long FolderSize(string folder)
        {
            long n = 0;
            try
            {
                if (!Directory.Exists(folder)) return 0;
                foreach (string f in Directory.GetFiles(folder, "*", SearchOption.AllDirectories))
                {
                    try { n += new FileInfo(f).Length; } catch { }
                }
            }
            catch { }
            return n;
        }

        // ------------------------------------------------------------ win32

        const int SW_RESTORE = 9;
        const uint GA_ROOT = 2;
        const ushort VK_RETURN = 0x0D;
        const ushort VK_MENU = 0x12;
        const ushort VK_CONTROL = 0x11;
        const ushort VK_BACK = 0x08;
        const ushort VK_A = 0x41;
        const uint INPUT_MOUSE = 0, INPUT_KEYBOARD = 1;
        const uint KEYEVENTF_KEYUP = 0x0002, KEYEVENTF_UNICODE = 0x0004;
        const uint MOUSEEVENTF_LEFTDOWN = 0x0002, MOUSEEVENTF_LEFTUP = 0x0004;

        [StructLayout(LayoutKind.Sequential)]
        public struct RECT { public int Left, Top, Right, Bottom; }

        [StructLayout(LayoutKind.Sequential)]
        struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr dwExtraInfo; }
        [StructLayout(LayoutKind.Sequential)]
        struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr dwExtraInfo; }
        [StructLayout(LayoutKind.Sequential)]
        struct HARDWAREINPUT { public uint uMsg; public ushort wParamL, wParamH; }
        [StructLayout(LayoutKind.Explicit)]
        struct INPUTUNION
        {
            [FieldOffset(0)] public MOUSEINPUT mi;
            [FieldOffset(0)] public KEYBDINPUT ki;
            [FieldOffset(0)] public HARDWAREINPUT hi;
        }
        [StructLayout(LayoutKind.Sequential)]
        struct INPUT { public uint type; public INPUTUNION u; }
        [StructLayout(LayoutKind.Sequential)]
        struct FLASHWINFO { public uint cbSize; public IntPtr hwnd; public uint dwFlags, uCount, dwTimeout; }
        const uint FLASHW_ALL = 3, FLASHW_TIMERNOFG = 12;

        delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

        [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
        [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
        [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
        [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr hWnd, uint gaFlags);
        [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hWnd);
        [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hWnd);
        [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr hWnd);
        [DllImport("user32.dll")] static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
        [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
        [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hWnd, int cmd);
        [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
        [DllImport("user32.dll")] static extern uint GetDpiForWindow(IntPtr hWnd);
        [DllImport("user32.dll")] static extern uint GetDpiForSystem();
        [DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint n, INPUT[] inputs, int size);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int max);
        [DllImport("user32.dll")] static extern bool FlashWindowEx(ref FLASHWINFO info);

        static void Type(string text)
        {
            foreach (char c in text)
            {
                var down = new INPUT(); down.type = INPUT_KEYBOARD;
                down.u.ki.wScan = c; down.u.ki.dwFlags = KEYEVENTF_UNICODE;
                var up = new INPUT(); up.type = INPUT_KEYBOARD;
                up.u.ki.wScan = c; up.u.ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP;
                SendInput(2, new[] { down, up }, Marshal.SizeOf(typeof(INPUT)));
                Thread.Sleep(12);
            }
        }

        static void Key(ushort vk)
        {
            var down = new INPUT(); down.type = INPUT_KEYBOARD; down.u.ki.wVk = vk;
            var up = new INPUT(); up.type = INPUT_KEYBOARD; up.u.ki.wVk = vk; up.u.ki.dwFlags = KEYEVENTF_KEYUP;
            SendInput(2, new[] { down, up }, Marshal.SizeOf(typeof(INPUT)));
        }

        /// <summary>A modifier held while another key is pressed, Ctrl+A for one.</summary>
        static void Chord(ushort modifier, ushort vk)
        {
            var mDown = new INPUT(); mDown.type = INPUT_KEYBOARD; mDown.u.ki.wVk = modifier;
            var kDown = new INPUT(); kDown.type = INPUT_KEYBOARD; kDown.u.ki.wVk = vk;
            var kUp = new INPUT(); kUp.type = INPUT_KEYBOARD; kUp.u.ki.wVk = vk; kUp.u.ki.dwFlags = KEYEVENTF_KEYUP;
            var mUp = new INPUT(); mUp.type = INPUT_KEYBOARD; mUp.u.ki.wVk = modifier; mUp.u.ki.dwFlags = KEYEVENTF_KEYUP;
            SendInput(4, new[] { mDown, kDown, kUp, mUp }, Marshal.SizeOf(typeof(INPUT)));
        }

        static void Mouse(uint flag)
        {
            var e = new INPUT(); e.type = INPUT_MOUSE; e.u.mi.dwFlags = flag;
            SendInput(1, new[] { e }, Marshal.SizeOf(typeof(INPUT)));
        }
    }
}
