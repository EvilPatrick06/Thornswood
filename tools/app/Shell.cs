using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net.NetworkInformation;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Ellipse = System.Windows.Shapes.Ellipse;   // not the namespace: System.Windows.Shapes.Path would collide with System.IO.Path
using System.Windows.Threading;

namespace Thornswood
{
    /// <summary>
    /// The launcher itself: Main, the window, every button, and the Play
    /// sequence. There is no compiled window class. Run parses tools\ui.xaml,
    /// which Build-Launcher.ps1 embeds in the exe, into a live Window at run
    /// time; Bind finds the named controls in it and Wire attaches every
    /// handler. So this is one static class, not a Window subclass, split
    /// across Shell.cs and every other file that declares partial class Shell.
    ///
    /// tools\app\ARCHITECTURE.md walks through it: the startup order, what
    /// each of the other classes owns on disk, and every step between the
    /// Play button and the game starting, with the file and line of each.
    /// Whoever changes one of those steps changes that page in the same pull
    /// request; tools\test-architecture.js fails when the page names a step
    /// that is gone or out of order.
    /// </summary>
    static partial class Shell
    {
        static Window win;
        static Config cfg;
        static VersionDoc pendingDoc;
        static List<Pack> pendingPacks = new List<Pack>();
        static bool playing, selfUpdateOffered;
        // An update waiting means this build no longer matches what the
        // server expects. Playing anyway is how someone gets turned away at
        // the door, or worse, gets in with a different mod list.
        /*
          Play starts blocked, not allowed.

          This was a plain false, which meant the launcher opened with Play
          live and only took it away once a background check had come back and
          said there was something waiting. Anybody quick enough got into the
          game on an old build in the gap, and the same gap opened whenever the
          check failed or the version document could not be read: no answer,
          no block, straight in. That is how somebody ends up playing a release
          behind and reporting bugs that were fixed hours ago.

          So the question is no longer "has an update been found" but "has
          anything told us it is safe to play yet", and the answer starts as no.
          updateAnswered is what turns CHECKING into either PLAY or UPDATE
          FIRST.

          Decided by Patrick on 20 September: nobody plays on a build that is
          not known to be current, on main or on dev. A check that cannot reach
          the source used to say so and let the game start, on the argument
          that a launcher that bricks itself when GitHub hiccups is worse than
          one a release behind. It is the other way round for a playtest: a
          release behind reports bugs fixed hours ago and desyncs everybody,
          so the button stays shut with the reason on it and the check runs
          again every thirty seconds until the source answers. Automatic
          updates being off no longer skips the check either; it only means
          the pack waits for the Install button instead of going in on its own.
          The one case that still frees Play without an answer is a launcher
          with no update source configured at all, which is a developer's own
          build and never a tester's.
        */
        static bool updatePending = true;
        static bool updateAnswered;
        static bool checkFailed;
        static bool retryQueued;
        static DateTime playStartedAt;

        // An update published while the game runs. The check that runs every
        // thirty seconds during play notices it; four and a half minutes after it is first
        // seen the game is closed so the launcher can install it, which is
        // what the server's own five minute warning has been counting down
        // to. The server's kick by itself did nothing: the client reconnects
        // in three seconds and carries on running files the rest of the room
        // has moved past, which is what happened to everybody on 1.1.40.
        static DateTime updateSeenAt = DateTime.MinValue;
        static bool checkingInPlay = false;
        static bool closedForUpdate = false;
        static bool installWhenSeen = false;
        static int inPlayTicks = 0;
        static int modTab;   // 0 server plugins, 1 script extender, 2 your own, 3 add-ons
        static Border addonsCard;
        // Ids being installed or removed right now, so a second click on the
        // same row does not start the same download twice.
        static readonly List<string> packBusy = new List<string>();
        static DispatcherTimer timer;

        // The character bar (charBar, charRow, txtCharNote, charPickerOpen)
        // went on 20 September; the person picks at the game's main menu.
        // This is who they picked, read out of the plugin's choice file while
        // the game runs, and 0 until they have.
        static int chosenId;

        static TextBlock txtServer, txtPing, txtStatus, txtStatusRight, txtVersion, txtBuildLine,
                         txtUpdateTitle, txtUpdateNote, txtModCount, txtUpdateSource,
                         txtPageTitle, txtHeroLine, txtVerifyTitle, txtVerifyNote,
                         txtSaveNote, txtSaveCount, txtLogCount, txtDisplayNote;
        static Ellipse dotServer, dotVerify;
        static StackPanel statusList, modList, themeRow, pathRows, helpList,
                          newsList, saveList, logList, statRow, displayModeRow,
                          firstRunCard, quickKeysCard, quickKeys;
        static TextBox boxSearch, boxAddress, boxPort, boxResolution, boxFrameLimit, boxFov;
        static CheckBox chkAutoUpdate, chkVSync, chkKeepOpen, chkLockRes;
        static CheckBox chkMusic; static Slider sldMusic; static TextBlock txtMusic;
        static StackPanel chatFadeRow; static TextBlock txtChatFadeNote; static CheckBox chkNeedsBars;
        static CheckBox chkKeepSaves;
        static CheckBox chkDeleteMods;
        static Button btnVoiceTest;
        static TextBlock txtVoiceState;
        static Button btnUninstall, btnServerStart, btnServerStop;
        static Button btnDevInstall, btnDevRemove;
        static TextBlock txtBrandSmall, txtBrandBig, txtDevState;
        static StackPanel pnlDev;
        static TextBlock txtServerState;
        static Border updateBar, mineCard;
        static Border downgradeBar;
        static TextBlock txtDowngradeNote, txtDowngradeTitle;
        static Button btnDowngrade;
        // The feed's word to everybody and whether it holds Play (entry 262).
        // Empty until a document has actually been read, so nothing here can
        // hold Play on a check that failed. See FeedNotice.cs.
        static Border noticeBar;
        static TextBlock txtNoticeTitle, txtNoticeNote;
        static FeedNotice feedNotice = new FeedNotice();
        static Grid titleBar;
        static Button buttonDiscord, buttonDiscordForget;
        static TextBlock labelDiscord, noteDiscord;
        static Button btnPlay, btnRecheck, btnCopy, btnUpdate, btnMin, btnMax, btnClose,
                      btnSaveServer, btnCheckNow, btnFolder, btnOpenLog, btnOpenSaves,
                      btnRepair, btnRestore, btnIcons, tabPlugins, tabSkse, tabMine, tabAddons,
                      btnRefreshAddons,
                      btnScan, btnFix, btnOpenMine, btnRefreshMine, btnInstallNow,
                      btnBackupSaves, btnOpenSaveFolder, btnCopyCrash, btnOpenLogFolder, btnSaveDisplay, btnShowServer,
                      btnAllControls, btnQuitGame;
        static Button[] navButtons;
        static UIElement[] pages;

        const string SearchHint = "Search";

        [STAThread]
        static void Main(string[] args)
        {
            bool fresh;
            using (var mutex = new Mutex(true, MutexName(args), out fresh))
            {
                // A second copy used to return here in silence, which from the
                // outside is indistinguishable from the launcher being broken:
                // you double click it, nothing happens, forever. Usually it is
                // a copy that crashed without releasing the mutex, or one
                // sitting behind another window.
                if (!fresh)
                {
                    try
                    {
                        var mine = System.Diagnostics.Process.GetCurrentProcess();
                        foreach (var p in System.Diagnostics.Process.GetProcessesByName(mine.ProcessName))
                        {
                            if (p.Id == mine.Id) continue;
                            if (p.MainWindowHandle != IntPtr.Zero)
                            {
                                // There is a real window somewhere. Say so
                                // rather than doing nothing at all.
                                MessageBox.Show(
                                    "Thornswood is already open.\n\nLook for it in the taskbar. " +
                                    "If you cannot find it, end Thornswood.exe in Task Manager and try again.",
                                    "Thornswood", MessageBoxButton.OK, MessageBoxImage.Information);
                                return;
                            }
                        }
                        MessageBox.Show(
                            "Another copy of Thornswood is running but has no window, which means " +
                            "it did not shut down properly last time.\n\nOpen Task Manager, end " +
                            "every Thornswood.exe, then start it again.",
                            "Thornswood", MessageBoxButton.OK, MessageBoxImage.Warning);
                    }
                    catch { }
                    return;
                }

                try { Run(args); }
                catch (Exception ex)
                {
                    // Into the log as well as onto the screen. A message box
                    // gets closed and then nobody can say what it said, and
                    // "it will not open" is not something anybody can act on.
                    try
                    {
                        Paths.Init(null);
                        File.AppendAllText(Paths.LogFile,
                            DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") +
                            "  COULD NOT START: " + ex.ToString() + Environment.NewLine);
                    }
                    catch { }
                    MessageBox.Show(ex.ToString(), "Thornswood could not start",
                                    MessageBoxButton.OK, MessageBoxImage.Error);
                }
            }
        }

        /// <summary>
        /// The single-instance lock, one per install. It used to be one name
        /// for every copy on the machine, which was right when there was one
        /// copy. The dev build lives in its own folder beside the main one and
        /// both may be open at once, so the folder is part of the name.
        /// </summary>
        static string MutexName(string[] args)
        {
            string root = null;
            try
            {
                for (int i = 0; i < args.Length - 1; i++)
                    if (args[i].Equals("-root", StringComparison.OrdinalIgnoreCase)) root = args[i + 1];
                if (string.IsNullOrEmpty(root))
                    root = Path.GetDirectoryName(Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location));
                root = Path.GetFullPath(root).TrimEnd('\\').ToLowerInvariant();
            }
            catch { root = ""; }
            uint h = 2166136261;
            foreach (char c in root) { h ^= c; h *= 16777619; }
            return "ThornswoodLauncher-" + h.ToString("x8");
        }

        /// <summary>
        /// Windows sent us here from Installed apps, so open on the page that
        /// does it. The entry in Settings points at this rather than deleting
        /// anything itself, because the uninstall asks two questions that
        /// matter and puts the Windows Skyrim folders back first.
        /// </summary>
        static bool askedToUninstall;

        static void Run(string[] args)
        {
            string root = null;
            for (int i = 0; i < args.Length - 1; i++)
                if (args[i].Equals("-root", StringComparison.OrdinalIgnoreCase)) root = args[i + 1];
            for (int i = 0; i < args.Length; i++)
                if (args[i].Equals("-uninstall", StringComparison.OrdinalIgnoreCase)) askedToUninstall = true;

            Paths.Init(root);
            cfg = Config.Load(Paths.CfgFile);
            Stats.Load();
            Keep.BuildName = cfg.BuildName;
            Icons.BuildName = cfg.BuildName;
            Discord.Channel = cfg.Channel;

            string xaml;
            using (var s = Assembly.GetExecutingAssembly().GetManifestResourceStream("ui.xaml"))
            using (var r = new StreamReader(s))
                xaml = r.ReadToEnd();
            win = (Window)XamlReader.Parse(xaml);

            Bind();
            Themes.Apply(win, cfg.Theme);
            Wire();
            BuildThemeRow();
            BuildDisplay();
            BuildChat();
            BuildStatRow();
            BuildPathRows();
            BuildHelp();

            // Windows Settings sends people here with -uninstall. The window
            // and the Settings page above are what the uninstall is made of;
            // everything below is a launcher starting up to play, and none of
            // it belongs on the way out. ShellUninstall.cs says what still runs.
            if (askedToUninstall) { OpenForUninstall(); return; }

            BuildModList();
            RefreshDiscord();
            ShowPage(PagePlay);

            // And put Thornswood in Installed apps, or bring the entry up to
            // date. Done here rather than in the installer so that every
            // install that already exists gets one on its next launch.
            try { Register.Ensure(cfg); } catch { }

            // So the session report can run the readiness checks against the
            // same config this launcher is using, without reaching in here.
            try { Discord.UseConfig(cfg); } catch { }

            // Logs from a session that ended without sending them, sent now.
            // On a pool thread so nothing waits on the site, and BEFORE Play
            // can be pressed, because the game truncates its own logs under
            // Data\Platform at every game start and after that there is
            // nothing left to send. A crash that took the launcher down with
            // it is exactly the session somebody wants to read afterwards,
            // and it was the one that was always lost.
            try { ThreadPool.QueueUserWorkItem(delegate { try { Discord.SendPendingLogs(); } catch { } }); } catch { }

            // The client settings file, made here if this install has none.
            // Nothing ships it, the client does not create it, and without it
            // a character cannot be chosen. From startup, so the log says so
            // before Play or a character choice can trip over its absence.
            try { AutoJoin.Ensure(Log); } catch { }

            // A launcher killed mid-session and opened again finds the game
            // still up. Taking the redirect off now would send the rest of
            // that session's settings and saves into the real Windows folders,
            // and putting other servers' plugins back would hand them to
            // SkyrimPlatform while it is loading them. So the session is picked
            // up where it was, and the two second tick does all of it properly
            // once the game has actually closed.
            playing = Checks.GameRunning();
            if (playing)
            {
                // Only the part of the session this launcher can see is
                // counted. Stats.StartedPlaying already ran in the instance
                // that started the game, so it is not run again here.
                playStartedAt = DateTime.Now;
                btnPlay.Content = "RUNNING";
                Log("Skyrim is still running, so this session is taken over rather than pulled apart under it. Your Windows folders stay pointed at this build until the game closes.");
                int holding = 0;
                try { holding = Hold.Take(PresenceLog); } catch { }
                if (holding > 0) Log("Holding " + holding + " of " + cfg.BuildName + "'s game files again, so nothing else can change them under the running game.");
            }
            else
            {
                if (Swap.Restore()) Log("Cleaned up a redirect left behind by a crash.");
                Keep.TakeNote();
            }
            try { string leak = Leaks.Clean(cfg); if (leak != null) Log(leak); } catch { }
            try { string ini = ThornIni.Ensure(); if (ini != null) Log(ini); } catch { }
            try { string fov = ThornIni.UndoShippedFov(); if (fov != null) Log(fov); } catch { }
            // Steam's Updates setting for the Skyrim the downgrade looks after, read only (SteamUpdates).
            try { if (!Downgrade.Needed(cfg) && !Downgrade.SourceNeeded(cfg)) { string upd = SteamUpdates.Report(Downgrade.Target(cfg)); if (upd != null) Log(upd); } } catch (Exception ex) { Swallow.Note("Shell.Run, reading Steam's Updates setting", ex); }
            {
                int parked = playing ? 0 : Keep.Unpark();
                if (parked > 0) Log("Put back " + parked + " parked " + (parked == 1 ? "plugin" : "plugins") + " from another server or build left behind by the last session.");
                // Packs go in before the launcher updates itself, so the first
                // launcher with Keep finds files it never saw arrive.
                int seeded = Keep.Seed();
                if (seeded > 0) Log("Kept " + seeded + " of " + cfg.BuildName + "'s own game files from earlier updates, to put back if another server or build changes them.");
            }

            // Same check the Play button does, run on the way in as well, so
            // somebody who changed monitor sees it corrected before they get
            // as far as pressing anything.
            if (!cfg.LockResolution)
            {
                string res = Display.MatchScreen();
                if (res != null) Log("Set the game to " + res + " to match your screen.");

                // Same idea, one layer up: the menus themselves are sized in
                // pixels, so a tall screen makes the inventory small and the
                // category icons squeeze together.
                string menus = Display.ScaleMenus();
                if (menus != null && menus != "1") Log("Sized the menus up " + menus + "x for this screen.");

            }

            // The shortcut points at whatever icon file the last build wrote,
            // and an update brings a new one. Quiet unless it actually had to
            // move something.
            ThreadPool.QueueUserWorkItem(delegate
            {
                int moved = 0;
                try { moved = Icons.Ensure(); } catch { }
                if (moved > 0)
                    win.Dispatcher.BeginInvoke((Action)delegate { Log("Shortcut icon brought up to date."); });
            });

            // Chars.Adopt and Chars.Sync ran here until 20 September. Adopt
            // made the two slot folders on every start; Sync asked the voice
            // service which characters this Steam account owned, off the UI
            // thread, and always came back with nothing, because that route
            // wants the server secret and the launcher never sent one. The
            // list lives in Profile\Characters\profiles.txt and the person
            // picks at the game's main menu now.
            try
            {
                int named = Files.FixPresetNames();
                if (named > 0) Log("Put " + named + " class name" + (named == 1 ? "" : "s") + " back to the right spelling.");
            }
            catch { }
            // Off the window's thread. Ending a stuck game waits on it, and at
            // this point the window has not even been shown yet.
            ThreadPool.QueueUserWorkItem(delegate
            {
                string said = null;
                try { said = ClearLeftovers(); } catch { }
                if (string.IsNullOrEmpty(said)) return;
                try { win.Dispatcher.BeginInvoke((Action)delegate { Log(said); DrawStatus(); }); } catch { }
            });

            // The installer unpacks into Thornswood-setup at the root of the
            // drive and nothing has ever deleted it, so a folder of leftovers
            // has been sitting on every machine that installed this, somewhere
            // nobody would think to look. Clearing it here means the space
            // comes back on the next start rather than only if somebody
            // uninstalls. Off the UI thread, because it is a recursive delete.
            ThreadPool.QueueUserWorkItem(delegate
            {
                long freed = 0;
                try { freed = Uninstall.DropScratch(null); } catch { }
                if (freed <= 0) return;
                try
                {
                    win.Dispatcher.BeginInvoke((Action)delegate
                    {
                        Log("Cleared " + (freed / (1024 * 1024)) +
                            " MB the installer left behind on your drive.");
                    });
                }
                catch { }
            });

            // Scan asks the server for its plugin list. The server having a bad
            // night is not a reason for the launcher to stop halfway through
            // starting, with the window built and nothing on it.
            try { RunScan(); }
            catch (Exception ex) { Log("Could not check the mod list on the way in: " + ex.Message); }
            if (DrawStatus()) Log("Ready."); else Log("Something needs attention before you can play.");
            // Nobody should have to press anything to get a client file back.
            // This does nothing at all when the six are the recorded build,
            // which is every start but the one that needed it.
            HealClientBackground();
            AutoDisplayOnce();
            StartPing();
            if (Updater.Enabled(cfg))
                ThreadPool.QueueUserWorkItem(delegate { CheckUpdatesBackground(false); });
            else
                Unblock("there is no update source configured");

            /*
              Voice comes up with the launcher, not with the game.

              Prepare installs the assembly resolver that hands WebView2 back
              to the CLR out of this exe's own resources, and it has to happen
              before any method touching a WebView2 type is compiled, which is
              why it is here and not inside Start.

              Start itself is queued on the dispatcher rather than called: it
              creates a Window, and a Window needs a running message loop.
              ApplicationIdle means it happens once the launcher is actually on
              screen, so a slow WebView2 runtime cannot delay the window
              appearing.
            */
            Voice.Prepare();
            win.Dispatcher.BeginInvoke(
                new Action(delegate { Voice.Start(delegate (string m) { Log(m); }, cfg); }),
                System.Windows.Threading.DispatcherPriority.ApplicationIdle);

            // The self update's way back. A launcher that got as far as drawing
            // its window started cleanly, so the copy of the one before it can
            // go, and not before: the update script watches for that copy to
            // disappear and puts it back if this one closes first. SelfSwap.cs.
            win.ContentRendered += delegate
            {
                string self = Assembly.GetExecutingAssembly().Location;
                ThreadPool.QueueUserWorkItem(delegate
                {
                    string said = null;
                    try { said = SelfSwap.Settle(self); } catch (Exception ex) { Swallow.Note("Shell.Run, clearing the copy the self update kept", ex); }
                    if (string.IsNullOrEmpty(said)) return;
                    try { win.Dispatcher.BeginInvoke((Action)delegate { Log(said); }); } catch (Exception ex) { Swallow.Note("Shell.Run, saying what the self update left", ex); }
                });
            };

            CentreOnMainScreen();

            /*
              ShutdownMode, and why it is not the default.

              WPF closes the application when the LAST window closes. The voice
              host is a real Window that is deliberately never shown, so with
              the default the launcher window closing left Application.Run
              still running against an invisible window: no UI, process alive,
              and the ThornswoodLauncher mutex still held. Every later launch
              then hit "if (!fresh) return" and vanished without a word, which
              reads as the launcher simply refusing to open.

              OnMainWindowClose ties the app's life to this window, which is
              what anyone closing it means.
            */
            var app = new Application();
            app.ShutdownMode = ShutdownMode.OnMainWindowClose;
            app.Exit += delegate { Voice.Stop(); try { Presence.Stop(); } catch { } try { Hold.Release(); } catch { } };

            // A fault on the launcher's own thread used to take the window
            // down with no line in the log, or leave it standing and deaf.
            // Now the fault is written down, stack and all, and the launcher
            // stays up. A button that failed once is better than no launcher,
            // and the log line is the only evidence anyone will have.
            app.DispatcherUnhandledException += delegate (object faultSender,
                System.Windows.Threading.DispatcherUnhandledExceptionEventArgs fault)
            {
                try { Log("Fault on the launcher's own thread: " + fault.Exception.GetType().Name + ": " + fault.Exception.Message); } catch { }
                try { File.AppendAllText(Paths.LogFile, fault.Exception.ToString() + Environment.NewLine); } catch { }
                fault.Handled = true;
            };
            StartStallWatch();
            app.Run(win);
        }

        /// <summary>
        /// WPF's CenterScreen centres on the whole desktop, so on a two monitor
        /// setup the window lands in the gap between them. The primary monitor's
        /// work area is what people mean by the middle of their screen, and it
        /// already excludes the taskbar.
        /// </summary>
        static void CentreOnMainScreen()
        {
            try
            {
                Rect work = SystemParameters.WorkArea;
                double w = win.Width, h = win.Height;
                if (double.IsNaN(w) || w <= 0) w = win.ActualWidth;
                if (double.IsNaN(h) || h <= 0) h = win.ActualHeight;

                win.Left = work.Left + Math.Max(0, (work.Width - w) / 2);
                win.Top = work.Top + Math.Max(0, (work.Height - h) / 2);
            }
            catch { }   // a bad monitor layout is not worth refusing to start over
        }

        static T F<T>(string name) where T : class { return win.FindName(name) as T; }

        static void Bind()
        {
            txtServer = F<TextBlock>("TxtServer"); txtPing = F<TextBlock>("TxtPing");
            txtStatus = F<TextBlock>("TxtStatus"); txtStatusRight = F<TextBlock>("TxtStatusRight");
            txtVersion = F<TextBlock>("TxtVersion"); txtBuildLine = F<TextBlock>("TxtBuildLine");
            txtUpdateTitle = F<TextBlock>("TxtUpdateTitle"); txtUpdateNote = F<TextBlock>("TxtUpdateNote");
            txtModCount = F<TextBlock>("TxtModCount"); txtUpdateSource = F<TextBlock>("TxtUpdateSource");
            txtPageTitle = F<TextBlock>("TxtPageTitle"); txtHeroLine = F<TextBlock>("TxtHeroLine");
            txtVerifyTitle = F<TextBlock>("TxtVerifyTitle"); txtVerifyNote = F<TextBlock>("TxtVerifyNote");
            txtSaveNote = F<TextBlock>("TxtSaveNote"); txtSaveCount = F<TextBlock>("TxtSaveCount");
            txtLogCount = F<TextBlock>("TxtLogCount"); txtDisplayNote = F<TextBlock>("TxtDisplayNote");
            newsList = F<StackPanel>("NewsList"); saveList = F<StackPanel>("SaveList");
            logList = F<StackPanel>("LogList"); statRow = F<StackPanel>("StatRow");
            displayModeRow = F<StackPanel>("DisplayModeRow");
            boxResolution = F<TextBox>("BoxResolution"); boxFrameLimit = F<TextBox>("BoxFrameLimit");
            boxFov = F<TextBox>("BoxFov");
            chatFadeRow = F<StackPanel>("ChatFadeRow"); txtChatFadeNote = F<TextBlock>("TxtChatFadeNote");
            chkNeedsBars = F<CheckBox>("ChkNeedsBars");
            chkVSync = F<CheckBox>("ChkVSync"); chkKeepOpen = F<CheckBox>("ChkKeepOpen");
            btnBackupSaves = F<Button>("BtnBackupSaves"); btnOpenSaveFolder = F<Button>("BtnOpenSaveFolder");
            btnCopyCrash = F<Button>("BtnCopyCrash"); btnOpenLogFolder = F<Button>("BtnOpenLogFolder");
            btnSaveDisplay = F<Button>("BtnSaveDisplay");
            btnQuitGame = F<Button>("BtnQuitGame");
            chkLockRes = F<CheckBox>("ChkLockRes");
            chkMusic = F<CheckBox>("ChkMusic"); sldMusic = F<Slider>("SldMusic"); txtMusic = F<TextBlock>("TxtMusic");
            dotServer = F<Ellipse>("DotServer"); dotVerify = F<Ellipse>("DotVerify");
            mineCard = F<Border>("MineCard");
            statusList = F<StackPanel>("StatusList"); modList = F<StackPanel>("ModList");
            themeRow = F<StackPanel>("ThemeRow"); pathRows = F<StackPanel>("PathRows");
            helpList = F<StackPanel>("HelpList");
            boxSearch = F<TextBox>("BoxSearch"); boxAddress = F<TextBox>("BoxAddress"); boxPort = F<TextBox>("BoxPort");
            btnShowServer = F<Button>("BtnShowServer");
            chkAutoUpdate = F<CheckBox>("ChkAutoUpdate");
            updateBar = F<Border>("UpdateBar"); titleBar = F<Grid>("TitleBar");
            downgradeBar = F<Border>("DowngradeBar"); txtDowngradeNote = F<TextBlock>("TxtDowngradeNote"); btnDowngrade = F<Button>("BtnDowngrade");
            txtDowngradeTitle = F<TextBlock>("TxtDowngradeTitle");
            noticeBar = F<Border>("NoticeBar"); txtNoticeTitle = F<TextBlock>("TxtNoticeTitle"); txtNoticeNote = F<TextBlock>("TxtNoticeNote");

            btnPlay = F<Button>("BtnPlay"); btnRecheck = F<Button>("BtnRecheck"); btnCopy = F<Button>("BtnCopy");
            btnUpdate = F<Button>("BtnUpdate"); btnMin = F<Button>("BtnMin"); btnMax = F<Button>("BtnMax");
            btnClose = F<Button>("BtnClose"); btnSaveServer = F<Button>("BtnSaveServer");
            btnCheckNow = F<Button>("BtnCheckNow"); btnInstallNow = F<Button>("BtnInstallNow");
            btnFolder = F<Button>("BtnFolder");
            btnOpenLog = F<Button>("BtnOpenLog"); btnOpenSaves = F<Button>("BtnOpenSaves");
            btnRepair = F<Button>("BtnRepair"); btnRestore = F<Button>("BtnRestore");
            btnIcons = F<Button>("BtnIcons");
            btnDevInstall = F<Button>("BtnDevInstall"); btnDevRemove = F<Button>("BtnDevRemove");
            txtDevState = F<TextBlock>("TxtDevState"); pnlDev = F<StackPanel>("PnlDev");
            txtBrandSmall = F<TextBlock>("TxtBrandSmall"); txtBrandBig = F<TextBlock>("TxtBrandBig");
            btnUninstall = F<Button>("BtnUninstall"); chkKeepSaves = F<CheckBox>("ChkKeepSaves");
            chkDeleteMods = F<CheckBox>("ChkDeleteMods");
            btnServerStart = F<Button>("BtnServerStart"); btnServerStop = F<Button>("BtnServerStop");
            txtServerState = F<TextBlock>("TxtServerState");
            btnVoiceTest = F<Button>("BtnVoiceTest");
            txtVoiceState = F<TextBlock>("TxtVoiceState");
            tabPlugins = F<Button>("TabPlugins"); tabSkse = F<Button>("TabSkse"); tabMine = F<Button>("TabMine");
            tabAddons = F<Button>("TabAddons"); btnRefreshAddons = F<Button>("BtnRefreshAddons");
            addonsCard = F<Border>("AddonsCard");
            btnScan = F<Button>("BtnScan"); btnFix = F<Button>("BtnFix");
            btnOpenMine = F<Button>("BtnOpenMine"); btnRefreshMine = F<Button>("BtnRefreshMine");

            firstRunCard = F<StackPanel>("FirstRunCard");
            quickKeysCard = F<StackPanel>("QuickKeysCard");
            quickKeys = F<StackPanel>("QuickKeys");
            btnAllControls = F<Button>("BtnAllControls");

            // Same order as the PageXxx constants above, and as PageTitles.
            navButtons = new Button[] {
                F<Button>("NavPlay"), F<Button>("NavNews"), F<Button>("NavServer"),
                F<Button>("NavMods"), F<Button>("NavBuild"), F<Button>("NavSaves"),
                F<Button>("NavControls"), F<Button>("NavLogs"), F<Button>("NavDiag"),
                F<Button>("NavHelp"), F<Button>("NavSettings") };
            pages = new UIElement[] {
                F<Grid>("PagePlay"), F<Grid>("PageNews"), F<Grid>("PageServer"),
                F<Grid>("PageMods"), F<Grid>("PageBuild"), F<Grid>("PageSaves"),
                F<Grid>("PageControls"), F<Grid>("PageLogs"), F<Grid>("PageDiag"),
                F<Grid>("PageHelp"), F<Grid>("PageSettings") };

            /*
              Saves is gone.

              Characters live on the server now, so a page for browsing and
              backing up local save files is showing people something that is
              no longer where their character is, which is worse than showing
              them nothing.

              Collapsed rather than cut out of the arrays. These three arrays
              and the PageXxx constants are parallel and indexed by number, and
              the comment on those constants records that a bare number in the
              middle of Play() once sent people to the wrong page for weeks.
              Renumbering eleven entries to save one unreachable Grid is how
              that happens again. The page cannot be reached, which is what was
              asked for; the dead Grid costs nothing and can be cut properly
              whenever the xaml is next opened.
            */
            if (navButtons[PageSaves] != null)
                navButtons[PageSaves].Visibility = Visibility.Collapsed;

            buttonDiscord       = F<Button>("ButtonDiscord");
            buttonDiscordForget = F<Button>("ButtonDiscordForget");
            labelDiscord        = F<TextBlock>("LabelDiscord");
            noteDiscord         = F<TextBlock>("NoteDiscord");

            // Discord.cs keeps the ticket beside launcher.log rather than in
            // config.json, so a config that gets copied between machines does
            // not carry somebody else's account with it.
            Discord.Folder = Paths.ProfileDir;

            BindPages();
        }

        /// <summary>
        /// Linking Discord, from either button that offers it.
        ///
        /// Discord.Connect runs on a pool thread and used to be called bare. If
        /// anything in it threw after the listener was up, saving the ticket
        /// for instance, the exception killed that thread with the callback
        /// never fired, and the button it had just disabled stayed grey for the
        /// rest of the session. The only way back to it was restarting the
        /// launcher, which is not something anybody guesses.
        ///
        /// So the button is put back on every path out of here, including the
        /// ones nobody thought of.
        /// </summary>
        static void ConnectDiscord()
        {
            if (linkingDiscord) return;
            linkingDiscord = true;
            SetLinkButtons(false);
            labelDiscord.Text = "Discord: waiting for your browser";
            Log("Waiting for your browser. Sign in to Discord and it closes itself.");

            ThreadPool.QueueUserWorkItem(delegate
            {
                bool answered = false;
                try
                {
                    Discord.Connect(delegate (bool ok, string who)
                    {
                        answered = true;
                        win.Dispatcher.BeginInvoke(new Action(delegate
                        {
                            linkingDiscord = false;
                            SetLinkButtons(true);
                            Door.Forget();          // re-ask with the new ticket
                            if (!ok)
                            {
                                labelDiscord.Text = "Discord: " + who;
                                Log("Discord: " + who);
                                DrawStatus();       // so the collection card offers it again
                            }
                            else
                            {
                                RefreshDiscord();
                                DrawStatus();
                                Log("Linked as " + (who.Length > 0 ? who : "your Discord account") + ".");
                            }
                        }));
                    });
                }
                catch (Exception ex)
                {
                    string why = ex.Message;
                    win.Dispatcher.BeginInvoke(new Action(delegate
                    {
                        linkingDiscord = false;
                        SetLinkButtons(true);
                        RefreshDiscord();
                        DrawStatus();
                        Log("Connecting Discord failed: " + why + "  Press it again.");
                    }));
                    return;
                }

                // Belt to the braces above: a Connect that returns without ever
                // calling back is still not allowed to leave the button dead.
                if (!answered)
                {
                    win.Dispatcher.BeginInvoke(new Action(delegate
                    {
                        linkingDiscord = false;
                        SetLinkButtons(true);
                        RefreshDiscord();
                        DrawStatus();
                    }));
                }
            });
        }

        static bool linkingDiscord = false;

        /// <summary>Both buttons that can start a link, moved together.</summary>
        static void SetLinkButtons(bool on)
        {
            if (buttonDiscord != null) buttonDiscord.IsEnabled = on;
            if (btnInstallNow != null && collectionBarUp && !Discord.Linked)
                btnInstallNow.IsEnabled = on;
        }

        /// <summary>The Discord card on the Play page. Called whenever it changes.</summary>
        static void RefreshDiscord()
        {
            if (labelDiscord == null) return;
            // This function is what says the card is now correct, so it is also
            // what puts the button back. Nothing else gets to leave it grey.
            if (buttonDiscord != null) buttonDiscord.IsEnabled = !linkingDiscord;
            if (Discord.Linked)
            {
                string who = Discord.Name;
                labelDiscord.Text = "Discord: " + (who != null && who.Length > 0 ? who : "linked");
                buttonDiscord.Content = "Reconnect";
                if (noteDiscord != null)
                    noteDiscord.Text = "Every launch asks whether this account is still allowed in. " +
                                       "Nothing else to do.";
                if (buttonDiscordForget != null)
                    buttonDiscordForget.Visibility = Visibility.Visible;
            }
            else
            {
                labelDiscord.Text = "Discord: not linked";
                buttonDiscord.Content = "Connect Discord";
                if (noteDiscord != null)
                    noteDiscord.Text = "Thornswood asks Discord who you are. One click, your browser " +
                                       "opens, and it closes itself.";
                if (buttonDiscordForget != null)
                    buttonDiscordForget.Visibility = Visibility.Collapsed;
            }
        }

        static Brush Res(string key) { return (Brush)win.Resources[key]; }

        static void Log(string m)
        {
            lastLogged = m;
            txtStatus.Text = m;
            try { File.AppendAllText(Paths.LogFile, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + m + Environment.NewLine); }
            catch { }
        }

        // ------------------------------------------------------------- pages
        // Named, because these are the index into three parallel arrays and a
        // bare number in the middle of Play() sent people to the wrong page for
        // weeks without anyone noticing.
        const int PagePlay = 0, PageNews = 1, PageServer = 2, PageMods = 3, PageBuild = 4,
                  PageSaves = 5, PageControls = 6, PageLogs = 7, PageDiag = 8,
                  PageHelp = 9, PageSettings = 10;

        static readonly string[] PageTitles = {
            "Play", "News", "Server", "Mods", "What is installed",
            "Saves", "Controls", "Logs", "Diagnostics", "Help", "Settings" };

        static void ShowPage(int i)
        {
            for (int k = 0; k < pages.Length; k++)
            {
                pages[k].Visibility = (k == i) ? Visibility.Visible : Visibility.Collapsed;
                navButtons[k].Tag = (k == i) ? "on" : "off";
            }
            txtPageTitle.Text = PageTitles[i];

            // Each page is rebuilt as it is opened rather than kept up to date
            // in the background. The folders behind them change while the
            // launcher sits there, so anything cached goes stale.
            if (i == PagePlay) DrawStatus();
            else if (i == PageNews) BuildNews();
            else if (i == PageServer) BuildServer();
            else if (i == PageMods) BuildModList();
            else if (i == PageBuild) BuildInstalled();
            else if (i == PageControls) BuildControls();
            else if (i == PageLogs) BuildLogs();
            else if (i == PageDiag) BuildDiag();
        }

        /// <summary>
        /// Puts the moving strip over the still one on the Play page.
        ///
        /// A MediaPlayer painted through a brush rather than a MediaElement. The
        /// band takes its height from the title beside it, and a MediaElement
        /// asks for room at the video's own shape: it took the band from 135 to
        /// 195 high. A brush asks for no room at all and crops exactly as the
        /// picture's brush does, so the two line up.
        ///
        /// The clip is made to loop, and a timeline that repeats forever joins
        /// the end to the start more smoothly than going back to the start when
        /// it ends: the band held one picture for 61 to 78 ms at the join that
        /// way, against 94 to 111 ms, where any two ordinary frames are 33 ms
        /// apart. While playing, the two cost the same as far as measuring could
        /// tell: 3 to 14% of one core, varying from run to run.
        ///
        /// It plays only while somebody can see it: stopped while the window is
        /// minimised or another page is open, and carried on from the same point
        /// when the Play page is back. Stopped, not paused, because a paused
        /// timeline went on costing up to 6.9% of one core with nothing on
        /// screen, and a stopped one next to nothing. If it will not play (Windows
        /// N without the Media Feature Pack, a file that will not open) it is
        /// hidden and the still picture shows exactly as before.
        ///
        /// Stopped while the game runs as well, the way the music is. With Keep
        /// Launcher Open ticked the window is never minimised, so until 24
        /// September the video went on decoding behind the game for the whole
        /// session, 3 to 14% of one core that the game could have had. The one
        /// time it failed on Patrick's machine, in 42 game starts since 19
        /// September, came one second after a start: "Starting the game" at
        /// 20:47:59 on 21 September, then "Title band: the video did not play
        /// (MILAVERR_UNEXPECTEDWMPFAILURE ...)" at 20:48:00, and a failure keeps
        /// the still picture until the launcher is restarted. Every place that
        /// changes playing calls headerVideoDecide straight after, except the
        /// check at startup, which runs before the window is shown; showing it
        /// decides then.
        /// </summary>
        static Action headerVideoDecide = delegate { };
        static void StartHeaderVideo()
        {
            string file = Art.HeaderVideo();
            var layer = F<Border>("HeaderArtVideo");
            var page = F<Grid>("PagePlay");
            if (file == null || layer == null || page == null) return;

            MediaPlayer player = null;
            MediaClock clock = null;
            bool gone = false;
            // Where it was when it was put away. Null while it plays.
            TimeSpan? heldAt = null;
            Action<string> drop = delegate(string why)
            {
                if (gone) return;
                gone = true;
                layer.Visibility = Visibility.Collapsed;
                layer.Background = null;
                try { if (player != null) { player.Clock = null; player.Close(); } } catch { }
                Stamp("Title band: the video did not play (" + why + "), the still picture stays");
            };
            Action decide = delegate
            {
                if (gone || clock == null) return;
                bool seen = page.IsVisible && win.WindowState != WindowState.Minimized && !playing;
                if (seen && heldAt != null)
                {
                    TimeSpan at = heldAt.Value;
                    heldAt = null;
                    clock.Controller.Begin();
                    clock.Controller.Seek(at, System.Windows.Media.Animation.TimeSeekOrigin.BeginTime);
                }
                else if (!seen && heldAt == null)
                {
                    heldAt = clock.CurrentTime ?? TimeSpan.Zero;
                    clock.Controller.Stop();
                }
            };

            try
            {
                player = new MediaPlayer();
                player.IsMuted = true;
                player.Volume = 0;
                var frame = new VideoDrawing();
                frame.Player = player;
                var brush = new DrawingBrush(frame);
                brush.Stretch = Stretch.UniformToFill;
                brush.AlignmentX = AlignmentX.Center;
                brush.AlignmentY = AlignmentY.Center;

                player.MediaOpened += delegate
                {
                    if (player.NaturalVideoWidth <= 0 || player.NaturalVideoHeight <= 0) { drop("no picture in it"); return; }
                    frame.Rect = new Rect(0, 0, player.NaturalVideoWidth, player.NaturalVideoHeight);
                    layer.Background = brush;
                    layer.Visibility = Visibility.Visible;
                    decide();
                };
                player.MediaFailed += delegate(object s, ExceptionEventArgs e)
                {
                    drop(e.ErrorException == null ? "no reason given" : e.ErrorException.Message);
                };

                var timeline = new MediaTimeline(new Uri(file));
                timeline.RepeatBehavior = System.Windows.Media.Animation.RepeatBehavior.Forever;
                clock = timeline.CreateClock();
                player.Clock = clock;
            }
            catch (Exception ex) { drop(ex.Message); return; }

            decide();
            win.StateChanged += delegate { decide(); };
            page.IsVisibleChanged += delegate { decide(); };
            headerVideoDecide = decide;
        }

        /// <summary>
        /// The theme, for the launcher, the game's main menu and the loading
        /// screen. Asked for by Patrick on 20 September, and held to the dev
        /// build until 22 September out of respect for the artist, because the
        /// track was not the final one. He supplied the final version that day
        /// and said it goes to main, so the dev-only rule is gone: the file is
        /// Data\Platform\UI\thornswood-theme.mp3, every pack and the installer
        /// carry it, and it plays on every build.
        ///
        /// It plays from the same file the game's menu plays, so there is one
        /// track on disk and not two.
        ///
        /// On a loop while the launcher is open and the game is not running:
        /// the game's own menu takes over the moment Play is pressed, and the
        /// launcher picks it up again when the game closes. Paused while the
        /// window is minimised, because music from a window nobody can see is
        /// a puzzle rather than a mood. Off entirely when the person has turned
        /// it off in Settings, which is what MusicDecide reads.
        /// </summary>
        static MediaPlayer music;
        static void StartMenuMusic()
        {
            // Not for somebody who opened this from Windows Settings to
            // uninstall. The theme playing is the loudest way to say the
            // launcher has started up to play when that is not why it opened.
            if (cfg == null || askedToUninstall) return;
            string src = Path.Combine(Paths.Game, "Data\\Platform\\UI\\thornswood-theme.mp3");
            if (!File.Exists(src)) return;

            // Played from a copy under Profile, never from the game folder. A
            // MediaPlayer holds its file open, and the first dev pack that
            // carried this track could not be installed over the copy the
            // launcher was playing: "being used by another process", 20
            // September 14:27, four times in a row, Play switched off. The copy
            // is refreshed from the game folder on every start, so an updated
            // track is heard the next time the launcher opens.
            string file;
            try
            {
                string dir = Path.Combine(Paths.ProfileDir, "Music");
                Directory.CreateDirectory(dir);
                file = Path.Combine(dir, "thornswood-theme.mp3");
                var a = new FileInfo(src);
                var b = new FileInfo(file);
                if (!b.Exists || b.Length != a.Length || b.LastWriteTimeUtc != a.LastWriteTimeUtc)
                    File.Copy(src, file, true);
            }
            catch (Exception ex)
            {
                Stamp("Menu music: could not copy the track out of the game folder (" + ex.Message + ")");
                return;
            }
            try
            {
                music = new MediaPlayer();
                music.Volume = Math.Max(0, Math.Min(100, cfg.MusicVolume)) / 100.0;
                music.MediaEnded += delegate
                {
                    try { music.Position = TimeSpan.Zero; music.Play(); } catch { }
                };
                music.MediaFailed += delegate(object s, ExceptionEventArgs e)
                {
                    Stamp("Menu music: did not play (" + (e.ErrorException == null ? "no reason given" : e.ErrorException.Message) + ")");
                    music = null;
                };
                music.Open(new Uri(file));
                MusicDecide();
                win.StateChanged += delegate { MusicDecide(); };
                Stamp("Menu music: the theme is on, from " + file);
            }
            catch (Exception ex)
            {
                Stamp("Menu music: " + ex.Message);
                music = null;
            }
        }

        /// <summary>
        /// Plays or pauses the track for the moment: not when it is switched off
        /// in Settings, not while the game runs, not while minimised. The volume
        /// is the Settings slider, 0 to 100.
        /// </summary>
        static void MusicDecide()
        {
            if (music == null) return;
            bool want = cfg.MusicOn && cfg.MusicVolume > 0 && !playing && win.WindowState != WindowState.Minimized;
            try
            {
                music.Volume = Math.Max(0, Math.Min(100, cfg.MusicVolume)) / 100.0;
                if (want) music.Play(); else music.Pause();
            }
            catch { }
        }

        static void MusicLabel()
        {
            if (txtMusic == null) return;
            int v = Math.Max(0, Math.Min(100, cfg.MusicVolume));
            txtMusic.Text = v == 0 ? "silent" : v + "%";
        }

        static void Wire()
        {
            // The Play page names the server rather than addressing it. See the
            // note on BtnSrvCopy in Pages.cs.
            txtServer.Text = "Thornswood";
            PaintServerBoxes();
            chkAutoUpdate.IsChecked = cfg.AutoUpdate;
            txtVersion.Text = "launcher " + Updater.Version;
            // The dev build says so everywhere a person looks, so nobody
            // reports a dev break against the main build or the other way.
            if (cfg.IsDev)
            {
                txtServer.Text = "Thornswood Dev";
                txtVersion.Text = "launcher " + Updater.Version + "  \u00b7  dev build";
                if (txtBrandSmall != null) txtBrandSmall.Text = "ThornsWood Dev";
                if (txtBrandBig != null) txtBrandBig.Text = "ThornsWood Dev";
                try { win.Title = "Thornswood Dev"; } catch { }
            }
            DrawDevBuild();
            boxSearch.Text = SearchHint;
            boxSearch.Foreground = Res("Faint");

            DrawBuildLine();
            txtStatusRight.Text = Paths.Root;
            chkKeepOpen.IsChecked = cfg.KeepLauncherOpen;
            if (chkMusic != null) chkMusic.IsChecked = cfg.MusicOn;
            if (sldMusic != null) sldMusic.Value = Math.Max(0, Math.Min(100, cfg.MusicVolume));
            MusicLabel();
            // The address, the port, the update source and the voice port are
            // not on this page any more. They are not settings: they are facts
            // about the server everybody connects to, they arrive in the update
            // and the launcher applies them. A box that lets somebody change
            // where the server is can only ever be wrong.
            //
            // Auto join is forced rather than offered for the same reason.
            // Unticking it left the person at a main menu with no way in and
            // nothing on screen saying why.
            if (!cfg.AutoJoin) { cfg.AutoJoin = true; cfg.Save(Paths.CfgFile); }
            // A request to the voice service. Somebody who came to uninstall
            // is not waiting on its answer, and the Server page asks again.
            if (!askedToUninstall) DrawVoiceState();

            // The emblem travels inside the exe rather than beside it, so the
            // update that replaces the launcher carries its artwork with it and
            // there is no second file to lose.
            BitmapImage emblem = Art.Emblem();
            if (emblem != null)
            {
                win.Icon = emblem;
                var big = F<Image>("Emblem");
                if (big != null) { big.Source = emblem; big.Visibility = Visibility.Visible; }
                var small = F<Image>("EmblemSmall");
                if (small != null) { small.Source = emblem; small.Visibility = Visibility.Visible; }
            }
            else
            {
                try
                {
                    var ico = System.Drawing.Icon.ExtractAssociatedIcon(
                        File.Exists(Paths.Exe) ? Paths.Exe : Assembly.GetExecutingAssembly().Location);
                    win.Icon = System.Windows.Interop.Imaging.CreateBitmapSourceFromHIcon(
                        ico.Handle, Int32Rect.Empty,
                        System.Windows.Media.Imaging.BitmapSizeOptions.FromEmptyOptions());
                }
                catch { }
            }

            // The landscape behind the title travels the same way. Without it
            // the band stays collapsed and keeps its pattern.
            ImageBrush headerArt = Art.Header();
            if (headerArt != null)
            {
                var band = F<Grid>("HeaderArt");
                var picture = F<Border>("HeaderArtPicture");
                if (band != null && picture != null) { picture.Background = headerArt; band.Visibility = Visibility.Visible; }
                StartHeaderVideo();
            }
            StartMenuMusic();

            titleBar.MouseLeftButtonDown += delegate(object s, MouseButtonEventArgs e)
            {
                if (e.ClickCount == 2)
                {
                    win.WindowState = win.WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;
                    return;
                }
                try { win.DragMove(); } catch { }
            };

            btnMin.Click += delegate { win.WindowState = WindowState.Minimized; };
            btnMax.Click += delegate { win.WindowState = win.WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized; };
            btnClose.Click += delegate { win.Close(); };

            for (int i = 0; i < navButtons.Length; i++)
            {
                int k = i;
                navButtons[i].Click += delegate { ShowPage(k); };
            }

            btnCopy.Visibility = Visibility.Collapsed;

            btnRecheck.Click += delegate
            {
                Log(DrawStatus() ? "Everything checks out." : "Something is still off, see the red rows.");
                StartPing();
                // Recheck is the button somebody presses when a row is red, so
                // it is the button that has to do something about it.
                HealClientBackground();
                if (Updater.Enabled(cfg))
                {
                    Log("Checking for updates...");
                    ThreadPool.QueueUserWorkItem(delegate { CheckUpdatesBackground(true); });
                }
                else Log("Updates are off: " + Updater.WhyDisabled(cfg));
            };
            btnPlay.Click += delegate
            {
                // Play means Play. Until 20 September this opened a bar of two
                // character slots and the slot's own button started the game;
                // the person picks at the game's main menu now.
                if (playing) { Play(); return; }
                StartPlay();
            };
            if (buttonDiscord != null) buttonDiscord.Click += delegate { ConnectDiscord(); };
            if (buttonDiscordForget != null)
            {
                buttonDiscordForget.Click += delegate
                {
                    Discord.Forget();
                    Door.Forget();
                    RefreshDiscord();
                    Log("Unlinked. Connect Discord again before you can play.");
                };
            }

            btnUpdate.Click += delegate { RunUpdate(); };
            if (btnDowngrade != null) btnDowngrade.Click += delegate { RunDowngrade(); };
            btnInstallNow.Click += delegate
            {
                if (collectionBarUp)
                {
                    if (!Discord.Linked) { ConnectDiscord(); return; }
                    try { Process.Start(new ProcessStartInfo(cfg.CollectionUrl) { UseShellExecute = true }); }
                    catch (Exception ex) { Log("Could not open the collection: " + ex.Message); }
                    return;
                }
                RunUpdate();
            };

            if (chkMusic != null) chkMusic.Click += delegate
            {
                cfg.MusicOn = chkMusic.IsChecked == true;
                cfg.Save(Paths.CfgFile);
                MusicDecide();
            };
            if (sldMusic != null) sldMusic.ValueChanged += delegate
            {
                cfg.MusicVolume = (int)Math.Round(sldMusic.Value);
                MusicLabel();
                MusicDecide();
                cfg.Save(Paths.CfgFile);
            };
            chkKeepOpen.Click += delegate
            {
                cfg.KeepLauncherOpen = chkKeepOpen.IsChecked == true;
                cfg.Save(Paths.CfgFile);
            };

            btnVoiceTest.Click += delegate { DrawVoiceState(); };

            // The dev build's uninstall is its own removal, never the main
            // uninstaller: that one deletes Thornswood's files out of the
            // shared game folder, which would take the main build down too.
            if (cfg.IsDev)
            {
                btnUninstall.Content = "Remove the dev build";
                if (chkDeleteMods != null) chkDeleteMods.Visibility = Visibility.Collapsed;
                if (chkKeepSaves != null) chkKeepSaves.Visibility = Visibility.Collapsed;
                btnUninstall.Click += delegate
                {
                    var r = MessageBox.Show(
                        "Remove the dev build?\n\nThis launcher and its folder go. The main build, the game and your characters on the dev server are not touched.",
                        "Thornswood Dev", MessageBoxButton.YesNo, MessageBoxImage.Question);
                    if (r != MessageBoxResult.Yes) return;
                    try { Log(DevBuild.RemoveSelf()); }
                    catch (Exception ex) { Log("Could not remove the dev build: " + ex.Message); return; }
                    try { Voice.Stop(); } catch { }
                    Application.Current.Shutdown();
                };
            }
            else
            {
                btnUninstall.Click += delegate { DoUninstall(); };
            }
            btnDevInstall.Click += delegate
            {
                if (DevBuild.Installed)
                {
                    try
                    {
                        Process.Start(new ProcessStartInfo(DevBuild.Exe) { UseShellExecute = true, WorkingDirectory = Path.GetDirectoryName(DevBuild.Exe) });
                        Log("Opened the dev build.");
                    }
                    catch (Exception ex) { Log("Could not open the dev build: " + ex.Message); }
                }
                else
                {
                    try { Log(DevBuild.Install(cfg)); }
                    catch (Exception ex) { Log("Could not install the dev build: " + ex.Message); }
                }
                DrawDevBuild();
            };
            btnDevRemove.Click += delegate
            {
                var r = MessageBox.Show(
                    "Remove the dev build?\n\nThe second launcher and its folder go. Characters on the dev server stay on the server, and this build is not touched.",
                    "Thornswood", MessageBoxButton.YesNo, MessageBoxImage.Question);
                if (r != MessageBoxResult.Yes) return;
                try { Log(DevBuild.Remove()); }
                catch (Exception ex) { Log("Could not remove the dev build: " + ex.Message); }
                DrawDevBuild();
            };

            btnOpenSaveFolder.Click += delegate { Open(Files.SaveDir); };
            btnOpenLogFolder.Click += delegate { Open(Files.SkseLogDir); };
            btnBackupSaves.Click += delegate
            {
                try
                {
                    string zip = Files.BackupSaves();
                    Log("Saves backed up to " + System.IO.Path.GetFileName(zip));
                    BuildSaves();
                }
                catch (Exception ex) { Log("Backup failed: " + ex.Message); }
            };
            btnCopyCrash.Click += delegate
            {
                Entry e = Files.NewestCrash();
                if (e == null) { Log("No crash logs, which is the good outcome."); return; }
                try
                {
                    string text = File.ReadAllText(e.FullPath);
                    if (text.Length > 60000) text = text.Substring(0, 60000) + "\n... truncated ...";
                    Clipboard.SetText(text);
                    Log("Copied " + e.Name + ". Paste it into Discord.");
                }
                catch (Exception ex) { Log("Could not read it: " + ex.Message); }
            };
            btnSaveDisplay.Click += delegate { SaveDisplay(); };
            btnQuitGame.Click += delegate
            {
                if (!Checks.GameRunning()) { Log("Skyrim is not running."); DrawStatus(); return; }
                var r = MessageBox.Show(
                    "Close Skyrim now?\n\nAnything since your last save in that session is lost, and on a shared world "
                    + "the others will see you vanish.",
                    "Thornswood", MessageBoxButton.YesNo, MessageBoxImage.Warning);
                if (r != MessageBoxResult.Yes) return;

                Log("Closing Skyrim...");
                int n;
                string still = CloseGameWaiting(out n);
                if (still.Length > 0)
                {
                    Log("Skyrim would not close. " + still);
                    MessageBox.Show("Skyrim would not close.\n\n" + still, "Thornswood", MessageBoxButton.OK, MessageBoxImage.Warning);
                    DrawStatus();
                    return;
                }
                Log(n > 0 ? "Closed Skyrim." : "Skyrim was already gone.");
                // The two second tick does the rest: puts the Windows folders
                // back, records the session and turns Play on again.
                DrawStatus();
            };
            chkLockRes.Click += delegate
            {
                cfg.LockResolution = chkLockRes.IsChecked == true;
                try { cfg.Save(Paths.CfgFile); } catch { }
                Log(cfg.LockResolution
                    ? "Resolution locked. Play will leave it exactly as you set it."
                    : "Resolution unlocked. Play will match it to your screen.");
            };
            chkNeedsBars.Click += delegate
            {
                bool shown = chkNeedsBars.IsChecked == true;
                if (!NeedsBars.Set(shown))
                {
                    Log("Could not save the needs bars setting to Thornswood.ini.");
                    BuildChat();
                    return;
                }
                Log(shown
                    ? "The needs bars are shown. It applies next time the game starts."
                    : "The needs bars are hidden. Type /needs in chat to see them. It applies next time the game starts.");
            };

            tabPlugins.Click += delegate { modTab = 0; BuildModList(); };
            tabSkse.Click += delegate { modTab = 1; BuildModList(); };
            tabMine.Click += delegate { modTab = 2; BuildModList(); };
            tabAddons.Click += delegate { modTab = 3; BuildModList(); };
            btnRefreshAddons.Click += delegate
            {
                Log("Checking for add-ons...");
                ThreadPool.QueueUserWorkItem(delegate { CheckUpdatesBackground(false); });
            };
            btnScan.Click += delegate { RunScan(); };
            btnFix.Click += delegate
            {
                if (Checks.GameRunning())
                {
                    Log("Close Skyrim first. It writes the plugin list back when it exits, which would undo the fix.");
                    return;
                }

                // Off the window's thread: a plugin fetched from the server is a
                // few megabytes, and the window has to keep answering meanwhile.
                var said = new List<string>();
                int n = 0;
                Waiting(delegate
                {
                    n = Verify.Fix(cfg, delegate(string m) { lock (said) said.Add(m); });
                });
                foreach (string m in said) Log(m);
                Log("Fix put " + n + " thing" + (n == 1 ? "" : "s") + " right. Restart the game for it to take effect.");
                RunScan(); BuildModList(); DrawStatus();
                // Fix pointed the launcher at the folder Vortex really deploys
                // into. Making Thornswood's own folder from it goes the way
                // Make it in Settings does. See ShellOwnGame.cs.
                if (Verify.OwnFolderNext) AskOwnGame(false);
            };
            btnOpenMine.Click += delegate
            {
                try { System.IO.Directory.CreateDirectory(Paths.Personal); } catch { }
                Open(Paths.Personal);
            };
            btnRefreshMine.Click += delegate { BuildModList(); };
            boxSearch.TextChanged += delegate { if (boxSearch.Text != SearchHint) BuildModList(); };
            boxSearch.GotKeyboardFocus += delegate
            {
                if (boxSearch.Text == SearchHint) { boxSearch.Text = ""; boxSearch.Foreground = Res("Ink"); }
            };
            boxSearch.LostKeyboardFocus += delegate
            {
                if (boxSearch.Text.Length == 0) { boxSearch.Text = SearchHint; boxSearch.Foreground = Res("Faint"); }
            };


            chkAutoUpdate.Click += delegate
            {
                cfg.AutoUpdate = chkAutoUpdate.IsChecked == true;
                cfg.Save(Paths.CfgFile);
            };
            btnCheckNow.Click += delegate
            {
                if (!Updater.Enabled(cfg)) { Log("No update source is configured in config.json."); return; }
                Log("Checking for updates...");
                ThreadPool.QueueUserWorkItem(delegate { CheckUpdatesBackground(true); });
            };

            btnAllControls.Click += delegate { ShowPage(PageControls); };

            WirePages();
            WireOwnGame();
            btnFolder.Click += delegate { Open(Paths.Root); };
            btnOpenLog.Click += delegate
            {
                if (File.Exists(Paths.LogFile)) Open(Paths.LogFile); else Log("Nothing has been logged yet.");
            };
            btnOpenSaves.Click += delegate { Open(Path.Combine(Paths.LiveMyGames, "Saves")); };
            btnRepair.Click += delegate
            {
                // Everything a Play does to put this build's files back, on
                // demand, because the one time somebody needs it is the time
                // they cannot press Play.
                //
                // It used to be one line: restore the settings files. That left
                // it useless for the thing people actually reach for it over,
                // which is Thornswood's own files in Data\Platform having been
                // replaced, parked or never written. Another server's launcher
                // rewrites the page the front plugin loads and drops its own
                // plugin in beside ours; an install that came from the
                // installer rather than from an update has no kept copy of
                // anything until something makes one. Both are what this is
                // for now.
                //
                // Every step is one Play already does on the way in, so none of
                // it is new behaviour, and all of it is safe to run twice.
                if (Checks.GameRunning())
                {
                    Log("Close Skyrim first. Repair writes into the game folder, and Skyrim writes its own files back when it exits.");
                    return;
                }

                btnRepair.IsEnabled = false;
                try
                {
                    var did = new List<string>();

                    int cfgs = Swap.RepairConfigs();
                    if (cfgs > 0) did.Add(cfgs + " settings file" + (cfgs == 1 ? "" : "s"));

                    // A machine that installed rather than updated has nothing
                    // kept, so there is nothing to put back until this runs.
                    int seeded = 0;
                    try { seeded = Keep.Seed(); } catch { }
                    if (seeded > 0) did.Add("kept a copy of " + seeded + " of this build's file" + (seeded == 1 ? "" : "s"));

                    // The one that matters: our Data\Platform files back from
                    // the kept copies, and another server's plugins aside.
                    try
                    {
                        string kept = Keep.Restore();
                        if (!string.IsNullOrEmpty(kept)) Log(kept);
                    }
                    catch (Exception ex) { Log("Could not put this build's files back: " + ex.Message); }

                    try
                    {
                        string ini = ThornIni.Ensure();
                        if (!string.IsNullOrEmpty(ini)) Log(ini);
                    }
                    catch { }

                    try
                    {
                        int rules = Enforce.Apply();
                        if (rules > 0) did.Add(rules + " mod setting" + (rules == 1 ? "" : "s"));
                    }
                    catch { }

                    try
                    {
                        int names = Files.FixPresetNames();
                        if (names > 0) did.Add(names + " class preset name" + (names == 1 ? "" : "s"));
                    }
                    catch { }

                    Log(did.Count > 0
                        ? "Repair put right: " + string.Join(", ", did.ToArray()) + "."
                        : "Repair found nothing to put right.");

                    // The Client row reads the bundle, so it has to be asked
                    // again rather than trusting what it answered a moment ago.
                    DrawStatus();
                    BuildModList();
                }
                finally { btnRepair.IsEnabled = true; }
            };
            btnRestore.Click += delegate
            {
                Log(Swap.Restore() ? "Windows Skyrim folders put back." : "Nothing was redirected.");
            };
            btnIcons.Click += delegate
            {
                // Explorer goes away for a second, so this one says so first
                // rather than leaving somebody watching their taskbar vanish.
                var r = MessageBox.Show(
                    "This throws away the pictures Windows has remembered for the shortcut and redraws them.\n\n" +
                    "The desktop and taskbar will blink once while Explorer restarts. Nothing is lost.\n\nGo ahead?",
                    "Thornswood", MessageBoxButton.YesNo, MessageBoxImage.Question);
                if (r != MessageBoxResult.Yes) return;

                btnIcons.IsEnabled = false;
                Log("Refreshing the shortcut icon...");
                ThreadPool.QueueUserWorkItem(delegate
                {
                    string said;
                    try { said = Icons.Repair(); }
                    catch { said = "Could not refresh the icon."; }
                    win.Dispatcher.BeginInvoke((Action)delegate
                    {
                        btnIcons.IsEnabled = true;
                        Log(said);
                    });
                });
            };

            win.Closing += delegate(object s, System.ComponentModel.CancelEventArgs e)
            {
                // Not while Skyrim is being closed. Play or the update that
                // asked for it carries on once it is gone, window or no window.
                if (waitDepth > 0) { e.Cancel = true; Log("Wait for Skyrim to finish closing."); return; }
                if (playing)
                {
                    var r = MessageBox.Show(
                        "Skyrim is still running. Quit the game first, otherwise this session's saves end up in the wrong folder.\n\nClose the launcher anyway?",
                        "Thornswood", MessageBoxButton.YesNo, MessageBoxImage.Warning);
                    if (r != MessageBoxResult.Yes) { e.Cancel = true; return; }
                }
                if (timer != null) timer.Stop();
                Swap.Restore();
                try { Hold.Release(); } catch { }
                if (!playing) { try { Keep.Unpark(); } catch { } }
                if (cfg.StopServerOnExit && SkyMp.Stop()) Log("Stopped the server.");
            };

            timer = new DispatcherTimer();
            timer.Interval = TimeSpan.FromSeconds(2);
            timer.Tick += delegate
            {
                // Every fifteenth two second tick, so the Server page has a
                // history to draw rather than one lonely bar.
                if (++pingTicks >= 15) { pingTicks = 0; StartPing(); }

                if (!playing) return;
                if (Checks.GameRunning())
                {
                    // Who was picked at the game's menu, every tick. One file
                    // read, and nothing when the file says what it said last.
                    PollChoice();
                    // Every fifteenth two second tick, so every thirty
                    // seconds: a pack is seen within half a minute of going
                    // out, and the close below lands on the server's own
                    // countdown rather than minutes after it.
                    if (++inPlayTicks >= 15) { inPlayTicks = 0; CheckUpdatesInPlay(); }
                    return;
                }
                playing = false;
                inPlayTicks = 0;
                MusicDecide();
                headerVideoDecide();
                // An update was seen during the session and they quit before
                // the five minutes were up. The clock goes, the fact does not:
                // it is fetched now, the same as it would have been had the
                // launcher closed the game itself. Otherwise quitting early was
                // a way to stay on a build the rest of the room had moved past,
                // with nothing on screen to say so.
                if (updateSeenAt != DateTime.MinValue) closedForUpdate = true;
                updateSeenAt = DateTime.MinValue;
                try { Presence.Stop(); } catch { }
                try { Hold.Release(); } catch { }
                Keep.TakeNote();
                Swap.Restore();
                {
                    int parked = Keep.Unpark();
                    if (parked > 0) Log("Put back " + parked + " parked " + (parked == 1 ? "plugin" : "plugins") + " from another server or build now that " + cfg.BuildName + " has closed.");
                }
                Stats.StoppedPlaying(playStartedAt);
                // The other end of the session for the site's log: how long it
                // ran, who was played, and why it stopped. closedForUpdate is
                // read here because it is cleared further down this same tick.
                // Off this thread and wrapped: the game has already closed and
                // nothing here is worth a wait on a network.
                double ranFor = (DateTime.Now - playStartedAt).TotalMinutes;
                int playedAs = chosenId;
                bool endedForUpdate = closedForUpdate;
                ThreadPool.QueueUserWorkItem(delegate
                {
                    try { Discord.SessionEnd(playedAs, ranFor, endedForUpdate ? "update" : "quit"); } catch { }
                    // Then the logs, on the same thread so they go after the
                    // row they attach to exists. This is the only moment they
                    // can be collected: the game truncates its own logs under
                    // Data\Platform at every game start, so anything not taken
                    // now is gone. Until 22 September every report began by
                    // asking the person to go and find four files themselves.
                    try { Discord.SessionLogs(); } catch { }
                });
                // Against the character, not just the install. Skyrim keeps its
                // own play time inside the save, and under SkyMP the character
                // is a change form on the server with often no save here at all,
                // so the launcher is the only thing in a position to count.
                // The character is whoever the menu's choice file named this
                // session; 0 when it never did, and then nothing is counted.
                try { Chars.AddPlaytime(chosenId, DateTime.Now - playStartedAt); } catch { }
                BuildStatRow();
                btnPlay.Content = "PLAY";
                btnQuitGame.Visibility = Visibility.Collapsed;
                Log("Game closed after " + (int)(DateTime.Now - playStartedAt).TotalMinutes + " minutes. Your Windows Skyrim folders are back to normal.");

                // The one failure that looks like everything else: a session
                // that ran the wrong Skyrim. Nothing else in here can be trusted
                // if this is wrong, so it is checked first and said plainly.
                string ranFrom = Checks.LastRunFrom();
                if (ranFrom.Length > 0 && !Checks.RanFromBuild())
                    Log("That session ran Skyrim from " + ranFrom + ", not this build, so none of the mod list was in play.");

                // Skyrim rewrites the plugin list every time it runs, and it has
                // been known to drop entries. Better to say so the moment it
                // happens than to let it turn up as a refused connect later.
                // Off the window's thread, because Run now asks the server for
                // its manifest and the server is often mid restart at exactly
                // this moment, after an update.
                ThreadPool.QueueUserWorkItem(delegate
                {
                    int broke = 0;
                    try { foreach (Issue i in Verify.Run(cfg)) if (i.Blocking) broke++; } catch { }
                    if (broke == 0) return;
                    try
                    {
                        win.Dispatcher.BeginInvoke(new Action(delegate
                        {
                            Log("Skyrim changed your plugin list on the way out, " + broke +
                                (broke == 1 ? " problem" : " problems") + ". Mods, then Fix.");
                        }));
                    }
                    catch { }
                });

                // Shut Play before the window comes back, not after. Nothing
                // in the in-play check sets updatePending, so the status drawn
                // here said PLAY while the pack the game was just closed for
                // was still being fetched, and a press in that gap started
                // Skyrim on half a pack. updateAnswered goes back to false so
                // the button reads CHECKING, and so Unblock can free Play again
                // if the check never reaches the source.
                if (closedForUpdate)
                {
                    updatePending = true;
                    updateAnswered = false;
                }

                DrawStatus();
                win.WindowState = WindowState.Normal;
                win.Activate();

                if (closedForUpdate)
                {
                    closedForUpdate = false;
                    installWhenSeen = true;
                    Log("Fetching the update the game was closed for...");
                    ThreadPool.QueueUserWorkItem(delegate { CheckUpdatesBackground(true); });
                }
            };
            timer.Start();
        }

        /// <summary>
        /// Clears a Skyrim that is still holding on. A crash, an Alt-F4, or one
        /// of the multiplayer client's browser helpers leaves a process behind
        /// with no window on screen: invisible to the person sitting there, and
        /// in the way of everything that comes next. Those are closed without
        /// asking, because there is nothing to lose and nothing to look at. A
        /// game that is actually on screen is somebody's session, so that one
        /// is asked about first. Returns false when the way is still blocked.
        /// </summary>
        static bool ClearStuckGame(bool askIfVisible)
        {
            if (!Checks.GameRunning())
            {
                // Somebody else's Skyrim, from another folder. Not ours to
                // close, and Steam will not run two at once, so the only
                // useful thing is to say which one is in the way.
                if (Checks.OtherSkyrimRunning())
                {
                    if (!askIfVisible) return true;
                    var other = MessageBox.Show(
                        "A different Skyrim is already running, from another folder on this PC.\n\n" +
                        "Steam will not run two at once. Close that one first.\n\nTry to start this one anyway?",
                        "Thornswood", MessageBoxButton.YesNo, MessageBoxImage.Warning);
                    if (other != MessageBoxResult.Yes) { Log("Left the other Skyrim alone."); return false; }
                }
                return true;
            }

            if (Checks.GameVisible())
            {
                if (!askIfVisible) return false;
                var r = MessageBox.Show(
                    "Skyrim is already open.\n\n" +
                    "Close it and carry on? Anything not saved in that session is lost.",
                    "Thornswood", MessageBoxButton.YesNo, MessageBoxImage.Warning);
                if (r != MessageBoxResult.Yes) { Log("Left the game where it was."); return false; }
            }

            Log("Closing what is left of Skyrim...");
            int n;
            string still = CloseGameWaiting(out n);
            if (still.Length > 0)
            {
                Log("Skyrim would not close. " + still);
                if (askIfVisible)
                    MessageBox.Show("Skyrim would not close, so this has to wait.\n\n" + still,
                                    "Thornswood", MessageBoxButton.OK, MessageBoxImage.Warning);
                return false;
            }
            if (n > 0) Log("Closed " + n + " Skyrim process" + (n == 1 ? "" : "es") + " that was still open.");
            return true;
        }

        /// <summary>
        /// Ends the game and whatever it left behind, with the window still
        /// drawing while it waits (Waiting). Returns what is still running
        /// afterwards, as a sentence, or "" when everything went.
        /// </summary>
        static string CloseGameWaiting(out int closed)
        {
            int n = 0;
            string still = "";
            stallDoing = "closing Skyrim";
            try
            {
                Waiting(delegate
                {
                    n = Checks.CloseGame();
                    still = Checks.StuckReport();
                });
            }
            finally { stallDoing = null; }
            closed = n;
            return still ?? "";
        }

        /// <summary>
        /// At startup, from a pool thread: a game with no window left over from a
        /// crash is ended quietly, because there is nothing on screen to lose. A
        /// game somebody is looking at is left alone. Returns a line for the log,
        /// or null when there was nothing to do.
        /// </summary>
        static string ClearLeftovers()
        {
            if (!Checks.GameRunning() || Checks.GameVisible()) return null;
            // A game that is still starting has no window yet either. With this
            // mod list Skyrim takes the better part of a minute to put one up
            // and skse64_loader hands over well before that, so a launcher
            // opened in those seconds reads a session that is loading in as the
            // leftovers of a crashed one and kills it. Anything younger than
            // three minutes is left alone; a crash worth clearing is older than
            // that by the time somebody has opened the launcher again, and
            // Clear is there for the rest.
            if (JustStarted(180)) return null;
            int n = Checks.CloseGame();
            string still = Checks.StuckReport();
            if (still.Length > 0) return "Something Skyrim left behind would not close. " + still;
            return n > 0 ? "Closed " + n + " Skyrim process" + (n == 1 ? "" : "es") + " left over from the last session." : null;
        }

        /// <summary>
        /// True when one of the game's processes started fewer than this many
        /// seconds ago. A start time that cannot be read counts as old, the same
        /// call Checks.GameProcesses makes about a path it cannot read: a
        /// process that has already fallen over is the one that hides its own
        /// details, and those are the ones worth closing.
        /// </summary>
        static bool JustStarted(int seconds)
        {
            List<Process> ps = Checks.GameProcesses();
            bool young = false;
            foreach (Process p in ps)
            {
                DateTime started;
                try { started = p.StartTime; }
                catch { continue; }
                if ((DateTime.Now - started).TotalSeconds < seconds) { young = true; break; }
            }
            foreach (Process p in ps) { try { p.Dispose(); } catch { } }
            return young;
        }

        static void Open(string path)
        {
            try { Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); }
            catch (Exception ex) { Log("Could not open it: " + ex.Message); }
        }

        // ------------------------------------------------------------- checks
        static bool DrawStatus()
        {
            statusList.Children.Clear();
            bool all = true;
            foreach (Check c in Checks.All(cfg))
            {
                // An advisory row that fails is drawn amber and leaves Play
                // alone. See Check.Advisory.
                if (c.Blocks) all = false;
                var row = new Grid();
                row.Margin = new Thickness(0, 0, 0, 1);
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

                var back = new Border();
                back.Background = Res("Card");
                back.BorderBrush = Res("Line");
                back.BorderThickness = new Thickness(1);
                back.Padding = new Thickness(15, 11, 15, 11);
                back.Margin = new Thickness(0, 0, 0, 7);

                var dot = new Ellipse();
                dot.Width = 7; dot.Height = 7;
                dot.Margin = new Thickness(0, 0, 12, 0);
                dot.VerticalAlignment = VerticalAlignment.Center;
                dot.Fill = Res(c.Ok ? "Ok" : c.Advisory ? "Warn" : "Bad");
                Grid.SetColumn(dot, 0); row.Children.Add(dot);

                var t1 = new TextBlock();
                t1.Text = c.Name; t1.FontSize = 13; t1.Foreground = Res("Ink");
                t1.VerticalAlignment = VerticalAlignment.Center;
                Grid.SetColumn(t1, 1); row.Children.Add(t1);

                var t2 = new TextBlock();
                t2.Text = c.Detail; t2.FontSize = 11.5;
                t2.VerticalAlignment = VerticalAlignment.Center;
                t2.Foreground = Res(c.Ok ? "Muted" : c.Advisory ? "Warn" : "Bad");
                Grid.SetColumn(t2, 2); row.Children.Add(t2);

                back.Child = row;
                statusList.Children.Add(back);
            }

            // No card here. It said the same thing as the bar above Play, which
            // lives in its own grid row below the scroller, so the two stacked
            // and the bar sat on top of the card. One message, in the louder
            // of the two places.

            // Connect Discord is put back here as well as in RefreshDiscord.
            //
            // Being refused for a role greyed it out and left it that way, so
            // somebody who was given the role a minute later had no way to
            // reconnect without closing the whole launcher and opening it
            // again. DrawStatus runs on every page change, every scan and every
            // recheck, so pinning the button's state to whether a link is
            // actually in flight means it comes back on its own.
            if (buttonDiscord != null) buttonDiscord.IsEnabled = !linkingDiscord;

            // Whether the mods are on this machine is a fact about this
            // machine, so it decides this, not the timing of a web request.
            // The collection bar went up only inside the update check, which
            // meant anybody whose check had not landed yet, or who could not
            // reach the site at all, got a red "Mods  32 plugins" row on this
            // page and nothing whatsoever to press. A link to the collection
            // is the single thing somebody in that state needs.
            // Guarded, because DrawStatus has always been safe to call before
            // the update card's own controls are resolved and this is the
            // first thing in it that touches them.
            //
            // The wrong Skyrim build comes before the mods. The downgrade needs
            // nothing from the collection, and Vortex deploying onto files the
            // downgrade then copies over is the same work twice, so while the
            // exe is wrong the collection card stays down and the downgrade
            // card is the one thing on this page to press. The collection card
            // comes up by itself once the build is right. A real update still
            // outranks both, below, because an update can carry a new expected
            // build and settle the question by itself.
            bool wrongBuild = Downgrade.Needed(cfg);
            // With Thornswood's own folder the card also comes up when only the
            // Steam copy it is made from has moved on: Thornswood still plays,
            // so Play is not held back, but the folder cannot follow Vortex until
            // the Steam copy is back on the right build. The mods card waits for
            // that one as well: Vortex deploys into the Steam copy, and the
            // downgrade rewrites the Steam copy, so the order is the same.
            bool steamCopyWrong = !wrongBuild && Downgrade.SourceNeeded(cfg);
            if (updateBar != null && btnInstallNow != null && ModsMissing() && !wrongBuild && !steamCopyWrong)
            {
                ShowCollectionBar();
            }
            else if (collectionBarUp && updateBar != null && btnInstallNow != null)
            {
                collectionBarUp = false;
                btnInstallNow.Content = "Install now";
                updateBar.Visibility = Visibility.Collapsed;
                btnInstallNow.Visibility = Visibility.Collapsed;
            }

            // Wrong Skyrim build: the one thing on this page with a button that
            // fixes it. Below the update bar in priority, because an update can
            // carry a new expected build and settle the question by itself.
            if (downgradeBar != null)
            {
                bool updateUp = updateBar != null && updateBar.Visibility == Visibility.Visible;
                downgradeBar.Visibility = ((wrongBuild || steamCopyWrong) && !updateUp && !playing) ? Visibility.Visible : Visibility.Collapsed;
                if (btnDowngrade != null) btnDowngrade.IsEnabled = !Downgrade.Busy && !ownGameBusy;
                if (txtDowngradeTitle != null)
                    txtDowngradeTitle.Text = steamCopyWrong ? "The Steam copy of Skyrim is on the wrong build" : "Skyrim is on the wrong build";
            }

            btnPlay.IsEnabled = all && !playing && !updatePending && !collectionBarUp && !ownGameBusy && feedNotice.Hold == null;
            // Only worth offering while there is something to quit, and it is
            // the one control on this page that stays live during a session.
            if (btnQuitGame != null)
                btnQuitGame.Visibility = Checks.GameRunning() ? Visibility.Visible : Visibility.Collapsed;

            // Missing mods outrank everything else here. The collection path
            // sets updatePending false, so the old order fell through to the
            // last branch and put PLAY back on a button that could not play:
            // the bar said install the mods and the button said go.
            // The game folder itself is being made or brought up to date, so
            // there is nothing complete to start yet.
            if (ownGameBusy && !playing)
            {
                btnPlay.Content = "PREPARING THE GAME FOLDER";
                btnPlay.ToolTip = "Thornswood's own Skyrim folder is being brought up to date from Vortex. Play comes back when it is done.";
            }
            else if (collectionBarUp && !playing)
            {
                btnPlay.Content = "INSTALL THE MODS FIRST";
                btnPlay.ToolTip = "Open the collection from the card above, then come back.";
            }
            else if (updatePending && !playing)
            {
                btnPlay.Content = checkFailed ? "NO ANSWER FROM THE UPDATE SOURCE"
                                : updateAnswered ? "UPDATE FIRST" : "CHECKING...";
                btnPlay.ToolTip = checkFailed
                    ? "The update source did not answer, so it is not known whether this build is current. Play stays shut until it answers; the check runs again every 30 seconds."
                    : updateAnswered
                    ? "There is an update waiting. Install it and Play comes back."
                    : "Checking for updates before letting anybody in. A moment.";
            }
            // The feed holds Play (entry 262). Below the three above because
            // each of those is something to do or already under way, and the
            // bar above Play says why it is held either way. Above the two
            // below because they label a button that stays live, and this one
            // is not.
            else if (feedNotice.Hold != null && !playing)
            {
                btnPlay.Content = feedNotice.Button;
                btnPlay.ToolTip = feedNotice.Hold;
            }
            else if (wrongBuild && !playing && !collectionBarUp)
            {
                btnPlay.Content = Downgrade.Busy ? "DOWNGRADING..." : "DOWNGRADE FIRST";
                btnPlay.ToolTip = ModsMissing()
                    ? "This Skyrim is not build 1.6.1170. The card above puts it right; the mods come after that."
                    : "This Skyrim is not build 1.6.1170. The card above puts it right.";
            }
            // A shared Skyrim is not an install this supports, so the button
            // says the thing that fixes it rather than saying PLAY and then
            // refusing. Pressing it goes to OwnGameRequired in ShellOwnGame.cs,
            // which offers the folder when it can be made and names the one
            // thing in the way when it cannot.
            //
            // Ranked BELOW the four above on purpose. Every one of them is also
            // a reason OwnGame.WhyNot gives for the folder not being makeable
            // yet: the mods have to be deployed, the build has to be right.
            // Putting this first would tell somebody to make a folder that
            // cannot be made, and hide the step that actually unblocks them.
            else if (Paths.Collection && !playing)
            {
                btnPlay.Content = "MAKE THORNSWOOD'S OWN FOLDER";
                btnPlay.ToolTip =
                    "Thornswood is sharing one Skyrim with every other server on this machine, in " +
                    Paths.Game + ". They all write the same client settings file and the game " +
                    "believes whichever wrote last, which is how their menus and logins get into " +
                    "Thornswood and Thornswood's get into theirs. This gives Thornswood a folder " +
                    "of its own. It takes a few minutes and the launcher restarts when it is done.";
            }
            else if (!playing)
            {
                btnPlay.ToolTip = null;
                btnPlay.Content = "PLAY";
            }
            return all;
        }

        /// <summary>
        /// "game 1.6.1170" in the corner and in the hero line, or what the exe
        /// actually is when it is not that. Redrawn after a downgrade.
        /// </summary>
        static void DrawBuildLine()
        {
            string build = Downgrade.Needed(cfg) ? Downgrade.Describe(cfg) : "1.6.1170";
            if (txtBuildLine != null) txtBuildLine.Text = "game " + build;
            if (txtHeroLine != null) txtHeroLine.Text = Checks.EnabledPlugins() + " plugins  ·  game " + build + "  ·  launcher " + Updater.Version;
        }

        /// <summary>
        /// The Downgrade button. Everything happens on Downgrade's own thread;
        /// its words come back here through the dispatcher, into the log and
        /// the line under the button, and the page is redrawn. With
        /// Thornswood's own folder the downgrade is done to the Steam copy the
        /// folder is made from, and the folder is brought up to date from it
        /// once that has worked.
        /// </summary>
        static void RunDowngrade()
        {
            if (Downgrade.Busy) return;
            if (ownGameBusy) { Log("Thornswood's own Skyrim folder is being prepared. Press Downgrade when that is done."); return; }
            if (Checks.GameRunning()) { Log("Close Skyrim first, then press Downgrade."); return; }
            // Asked first because the downgrade takes over Steam's window, the mouse and the keyboard, and nobody should find that happening without having said yes to it.
            var r = MessageBox.Show(
                "Downgrade Skyrim to 1.6.1170?\n\n" +
                "Steam only hands over an older build through its own console, so the launcher works that console for you. " +
                "Steam's window comes to the front, the launcher clicks the console's command line and types these three lines into it, one at a time, each after the one before has finished downloading:\n\n" +
                string.Join("\n", Downgrade.Commands()) + "\n\n" +
                "Steam downloads about 11 GB under your own account, and the launcher then copies the files over the Steam copy of Skyrim. " +
                "Do not type or click while Steam's window is in front, or the keys go to the wrong place.",
                "Thornswood", MessageBoxButton.YesNo, MessageBoxImage.Question);
            if (r != MessageBoxResult.Yes) { Log("Left Skyrim on the build it is on."); return; }
            btnDowngrade.IsEnabled = false;
            btnDowngrade.Content = "Working...";
            Downgrade.Start(cfg,
                PresenceLog,
                delegate (string s) { try { win.Dispatcher.BeginInvoke(new Action(delegate { txtDowngradeNote.Text = s; })); } catch { } },
                delegate (bool ok)
                {
                    try
                    {
                        win.Dispatcher.BeginInvoke(new Action(delegate
                        {
                            btnDowngrade.Content = ok ? "Done" : "Try again";
                            btnDowngrade.IsEnabled = !ok;
                            if (ok && OwnGame.Active) StartOwnGame(false, true);
                            DrawStatus();
                            DrawBuildLine();
                            if (ok) AskToHoldSteamUpdates();
                        }));
                    }
                    catch { }
                });
        }

        // ------------------------------------------------------------- mods
        static void RunScan()
        {
            List<Issue> issues = null;
            Waiting(delegate { issues = Verify.Run(cfg); });
            int blocking = 0;
            foreach (Issue i in issues) if (i.Blocking) blocking++;
            // Vortex deploys somewhere else, and Fix makes the own folder from
            // there: the missing mods are in that folder, so Fix does help.
            bool elsewhere = false;
            foreach (Issue i in issues) if (i.VortexFolder != null) elsewhere = true;

            if (issues.Count == 0)
            {
                dotVerify.Fill = Res("Ok");
                txtVerifyTitle.Text = "Everything matches";
                txtVerifyNote.Text = "Your plugin list is identical to the one the server expects" +
                                     (Verify.BytesChecked
                                        ? ", and every plugin in it is byte for byte the server's."
                                        : ". The server could not be asked about the plugin bytes just now, so only the names were compared.") +
                                     "\n\nRead from " + Verify.LiveFile;
                btnFix.IsEnabled = false;
            }
            else
            {
                dotVerify.Fill = Res(blocking > 0 ? "Bad" : "Warn");
                txtVerifyTitle.Text = blocking > 0
                    ? (blocking == 1 ? "1 problem will stop you connecting" : blocking + " problems will stop you connecting")
                    : "Worth a look";
                var sb = new System.Text.StringBuilder();
                int shown = 0;
                foreach (Issue i in issues)
                {
                    if (shown >= 4) { sb.Append("and " + (issues.Count - shown) + " more."); break; }
                    if (shown > 0) sb.Append("\n");
                    sb.Append(i.Text);
                    shown++;
                }
                // Fix repairs the plugin list. It cannot install a mod, so when
                // the problem is files that are not there, the button is the
                // wrong answer and offering it is worse than not offering it.
                int absent = 0;
                foreach (Issue i in issues) if (i.Absent) absent++;
                if (absent > 0 && !elsewhere)
                {
                    sb.Append("\n\nThese are not installed at all. Fix cannot help. In Vortex, " +
                              "Profiles, press Enable under Thornswood.");
                }
                // Which file it judged. An hour went into a mismatch nobody
                // could place, because the page reported problems without ever
                // saying where it had read the list from, and under the
                // collection that is Vortex's file rather than one of ours.
                sb.Append("\n\nRead from ").Append(Verify.LiveFile);
                if (Paths.Collection)
                    sb.Append("\nThat file is Vortex's. Fix writes the server's order into it, " +
                              "and Vortex writes its own again the next time it deploys.");

                txtVerifyNote.Text = sb.ToString();
                btnFix.IsEnabled = blocking > 0 && (absent == 0 || elsewhere);
            }
            // The count alone read the same after every press: 182, 182, 182.
            // When most of them are mods that are simply not in the game folder,
            // pressing Scan again or Fix changes nothing, and that is the line
            // worth reading.
            int missing = 0;
            foreach (Issue i in issues) if (i.Absent) missing++;
            Log("Scan finished. " + issues.Count + " issue" + (issues.Count == 1 ? "" : "s") + " found." +
                (missing > 0 && !elsewhere
                    ? " " + missing + " of them are mods that are not in the game folder at all, which Scan and Fix cannot change." +
                      (Paths.Collection ? " Vortex most likely has another profile deployed." : "")
                    : ""));

            /*
              AND WHICH ONES, because the count on its own is not a record of
              anything.

              FOUND 22 SEPTEMBER while working out why nobody could join the
              dev server. The log said "Scan finished. 4 issues found" and
              "Something needs attention before you can play", and that was the
              entire record. It never said which four. Every one of those
              issues already carries a written sentence naming the plugin and
              what is wrong with it, because Verify.cs builds them that way for
              the card on screen; this line threw all of it away and kept the
              number.

              Working out what those four were meant reading Verify.cs,
              reimplementing its comparison by hand, fetching the server's
              manifest and diffing it against the game folder. Twenty minutes
              for somebody who knows the code and an impossibility for anybody
              else.

              IT MATTERS MOST FOR THE PEOPLE THE LOG IS COLLECTED FROM. Each
              session's log goes up to the site, so a tester who cannot press
              Play produced a line with a number in it, while the answer to
              "why can't I play" was sitting in memory at that exact moment and
              was deliberately not written down.

              BLOCKING FIRST, because those are the ones that refuse Play, and
              capped so a mod list that is 182 wrong does not bury the rest of
              the log. The count above already says how many there were, so the
              cap loses nothing that is not already recorded.
            */
            if (issues.Count > 0)
            {
                var named = new List<Issue>();
                foreach (Issue i in issues) if (i.Blocking) named.Add(i);
                foreach (Issue i in issues) if (!i.Blocking) named.Add(i);

                const int LogAtMost = 25;
                int shown = 0;
                foreach (Issue i in named)
                {
                    if (shown >= LogAtMost) break;
                    if (string.IsNullOrEmpty(i.Text)) continue;
                    // One line each, flattened: a wrapped sentence in a log
                    // file is a sentence somebody has to reassemble by eye.
                    string one = i.Text.Replace("\r", " ").Replace("\n", " ").Trim();
                    Log("  " + (i.Blocking ? "blocks Play: " : "worth knowing: ") + one);
                    shown++;
                }
                if (named.Count > shown)
                    Log("  and " + (named.Count - shown) + " more, not written out to keep the log readable.");
            }
        }

        static void BuildModList()
        {
            if (modList == null) return;
            modList.Children.Clear();
            tabPlugins.Background = Res(modTab == 0 ? "CardHover" : "Card");
            tabSkse.Background    = Res(modTab == 1 ? "CardHover" : "Card");
            tabMine.Background    = Res(modTab == 2 ? "CardHover" : "Card");
            tabAddons.Background  = Res(modTab == 3 ? "CardHover" : "Card");
            mineCard.Visibility   = modTab == 2 ? Visibility.Visible : Visibility.Collapsed;
            if (addonsCard != null)
                addonsCard.Visibility = modTab == 3 ? Visibility.Visible : Visibility.Collapsed;
            // Scan and Fix compare against the server's list, which covers the
            // first two tabs. Your own folder and the add-ons are both outside
            // what the server looks at, so the card has nothing to say there.
            verifyCardVisible(modTab == 0 || modTab == 1);

            // Above every sub tab, not just Add-ons. It lived in BuildPackRows,
            // which only runs when somebody has already clicked Add-ons, so the
            // one thing in the launcher that says where the mods come from was
            // behind a chip nobody had a reason to press.
            if (!string.IsNullOrEmpty(cfg.CollectionUrl))
                modList.Children.Add(CollectionCard());

            if (modTab == 3) { BuildPackRows(); return; }

            string filter = (boxSearch.Text == SearchHint) ? "" : boxSearch.Text.Trim().ToLowerInvariant();
            int shown = 0, total = 0, enabled = 0;

            if (modTab == 0)
            {
                string plug = Path.Combine(Paths.Live, "plugins.txt");
                if (!File.Exists(plug)) { txtModCount.Text = "No plugin list found in this build's profile."; return; }
                // Only the enabled plugins are what the server compares against.
                // Everything switched off is not part of this build and is left out.
                int index = 0;
                foreach (string raw in File.ReadAllLines(plug))
                {
                    string line = raw.Trim();
                    if (line.Length == 0 || line.StartsWith("#")) continue;
                    bool on = line.StartsWith("*");
                    string name = on ? line.Substring(1) : line;
                    total++;
                    if (!on) continue;
                    enabled++; index++;
                    if (filter.Length > 0 && name.ToLowerInvariant().IndexOf(filter) < 0) continue;
                    modList.Children.Add(LinkedRow(index, name, true,
                        Path.GetExtension(name).TrimStart('.').ToUpperInvariant()));
                    shown++;
                }
                int off = total - enabled;
                txtModCount.Text = enabled + " plugins, in the order the server expects them." +
                                   (off > 0 ? "   ·   " + off + " switched off and not shown" : "") +
                                   (filter.Length > 0 ? "   ·   showing " + shown : "") +
                                   "   ·   click one to open its mod page";
            }
            else if (modTab == 1)
            {
                string dir = Path.Combine(Paths.Game, "Data\\SKSE\\Plugins");
                if (!Directory.Exists(dir)) { txtModCount.Text = "No script extender folder in this build."; return; }
                var files = Directory.GetFiles(dir, "*.dll");
                Array.Sort(files);
                int index = 0;
                foreach (string f in files)
                {
                    string name = Path.GetFileNameWithoutExtension(f);
                    total++; index++;
                    if (filter.Length > 0 && name.ToLowerInvariant().IndexOf(filter) < 0) continue;
                    long kb = 0;
                    try { kb = new FileInfo(f).Length / 1024; } catch { }
                    // C# 4 captures the loop variable itself, so the path has to
                    // be copied before a handler can be trusted with it.
                    string dll = f;
                    string dllName = name;
                    modList.Children.Add(ModRow(index, name, true, kb + " KB",
                        delegate { Open(Links.Target(dllName) ?? dir); }, "Open the mod page",
                        delegate
                        {
                            DeleteFromBuild(dll, dllName + ".dll",
                                "The server never looks at script extender plugins, so this will not stop you " +
                                "connecting. Whatever mod relies on it will stop working until it is back.");
                        }));
                    shown++;
                }
                txtModCount.Text = total + " script extender plugins. The server never sees these." +
                                   (filter.Length > 0 ? "   ·   showing " + shown : "") +
                                   "   ·   click one to open its mod page";
            }
            else
            {
                string[] files = Verify.PersonalFiles();
                int index = 0;
                foreach (string f in files)
                {
                    string rel = f.Substring(Paths.Personal.Length).TrimStart('\\');
                    string ext = Path.GetExtension(f).ToLowerInvariant();
                    bool bad = (ext == ".esp" || ext == ".esm" || ext == ".esl");
                    total++; index++;
                    if (filter.Length > 0 && rel.ToLowerInvariant().IndexOf(filter) < 0) continue;
                    long kb = 0;
                    try { kb = new FileInfo(f).Length / 1024; } catch { }
                    string full = f;
                    string relName = rel;
                    modList.Children.Add(ModRow(index, rel, !bad,
                        bad ? "PLUGIN, NOT ALLOWED" : kb + " KB",
                        delegate { Reveal(full); }, "Show this file in Explorer",
                        delegate
                        {
                            DeleteFromBuild(full, relName,
                                "This is one of your own files. Nothing else uses it and the server " +
                                "never sees it.");
                        }));
                    shown++;
                }
                txtModCount.Text = total == 0
                    ? "Nothing here yet."
                    : total + " file" + (total == 1 ? "" : "s") + " of your own, copied in every time you press Play." +
                      (filter.Length > 0 ? "   ·   showing " + shown : "");
            }

            if (shown == 0 && filter.Length > 0)
            {
                var none = new TextBlock();
                none.Text = "Nothing matches \"" + filter + "\".";
                none.Foreground = Res("Faint"); none.FontSize = 12.5;
                none.Margin = new Thickness(2, 10, 0, 0);
                modList.Children.Add(none);
            }
        }

        /// <summary>
        /// The add-ons tab. One row per optional pack, with a button that says
        /// what it will do.
        ///
        /// The list comes from the same version.json the update check already
        /// reads, so there is nothing extra to fetch and no second source that
        /// can disagree with the first.
        /// </summary>
        static void BuildPackRows()
        {
            // The mods do not come with the installer any more, so this is the
            // only thing in the launcher that tells anybody where they do come
            // from. It goes above the add-on list and shows whether or not the
            // add-ons have loaded, because somebody whose world looks like
            // plain Skyrim needs to read it before anything else.
            // BuildModList puts the card above every sub tab now, so adding it
            // here again would show it twice on this one.
            var have = pendingDoc == null ? null : pendingDoc.optional;

            if (have == null)
            {
                txtModCount.Text = "Add-ons load with the update check. Press " +
                                   "Check for add-ons above.";
                return;
            }

            string filter = (boxSearch.Text == SearchHint) ? "" : boxSearch.Text.Trim().ToLowerInvariant();
            int total = 0, shown = 0, on = 0;
            long free = 0;

            foreach (var p in have)
            {
                if (p == null || string.IsNullOrEmpty(p.id)) continue;
                total++;
                bool installed = Updater.IsInstalled(p.id);
                if (installed) on++; else free += p.bytes;
                if (filter.Length > 0 && p.Title.ToLowerInvariant().IndexOf(filter) < 0) continue;
                modList.Children.Add(PackRow(p, installed));
                shown++;
            }

            if (total == 0)
            {
                txtModCount.Text = "No add-ons published yet.";
                return;
            }

            txtModCount.Text = total + " add-on" + (total == 1 ? "" : "s") + "   ·   " +
                               on + " installed" +
                               (free > 0 ? "   ·   " + Bytes(free) + " more available" : "") +
                               (filter.Length > 0 ? "   ·   showing " + shown : "");

            if (shown == 0 && filter.Length > 0)
            {
                var none = new TextBlock();
                none.Text = "Nothing matches \"" + filter + "\".";
                none.Foreground = Res("Faint"); none.FontSize = 12.5;
                none.Margin = new Thickness(2, 10, 0, 0);
                modList.Children.Add(none);
            }
        }

        static string Bytes(long n)
        {
            if (n >= 1073741824L) return (n / 1073741824.0).ToString("0.0") + " GB";
            if (n >= 1048576L) return (n / 1048576.0).ToString("0") + " MB";
            return (n / 1024.0).ToString("0") + " KB";
        }

        static UIElement PackRow(Pack p, bool installed)
        {
            var g = new Grid();
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            var left = new StackPanel();
            Grid.SetColumn(left, 0); g.Children.Add(left);

            var name = new TextBlock();
            name.Text = p.Title;
            name.FontSize = 13.5;
            name.Foreground = Res("Ink");
            name.TextTrimming = TextTrimming.CharacterEllipsis;
            left.Children.Add(name);

            var note = new TextBlock();
            string size = p.Size;
            string body = p.notes == null ? "" : p.notes.Trim();
            note.Text = (size.Length > 0 ? size : "") +
                        (size.Length > 0 && body.Length > 0 ? "   ·   " : "") + body;
            note.FontSize = 11.5;
            note.Foreground = Res(installed ? "Muted" : "Faint");
            note.TextWrapping = TextWrapping.Wrap;
            note.Margin = new Thickness(0, 3, 12, 0);
            if (note.Text.Length > 0) left.Children.Add(note);

            var b = new Button();
            bool busy = packBusy.Contains(p.id);
            b.Content = busy ? "Working..." : (installed ? "Remove" : "Install");
            b.Style = (Style)win.Resources[installed ? "Ghost" : "Solid"];
            b.IsEnabled = !busy;
            b.VerticalAlignment = VerticalAlignment.Center;
            b.MinWidth = 96;
            Grid.SetColumn(b, 1); g.Children.Add(b);

            // C# 4 closures capture the loop variable itself, so the pack has
            // to be copied to a local before the handler can be trusted.
            Pack mine = p;
            bool wasOn = installed;
            b.Click += delegate { PackAction(mine, wasOn); };

            var card = new Border();
            card.Padding = new Thickness(14, 12, 14, 12);
            card.Background = Res("Panel");
            card.Margin = new Thickness(0, 0, 8, 4);
            card.Child = g;
            return card;
        }

        /// <summary>
        /// Where the mods come from, and a way to get there.
        ///
        /// Built here rather than in ui.xaml on purpose: a named control the
        /// C# looks up and the xaml does not have comes back null and takes
        /// the whole page with it, and this is the one row that must not be
        /// the thing that breaks.
        /// </summary>
        static UIElement CollectionCard()
        {
            return CollectionCard("The mods",
                "Thornswood's mods are installed by Vortex from the collection, " +
                "not by this launcher. If the world looks like plain Skyrim, or " +
                "the server turns you away when you press Play, the collection is " +
                "what is missing.");
        }

        static UIElement CollectionCard(string title, string body)
        {
            var g = new Grid();
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            var left = new StackPanel();
            Grid.SetColumn(left, 0); g.Children.Add(left);

            var name = new TextBlock();
            name.Text = title;
            name.FontSize = 13.5;
            name.Foreground = Res("Ink");
            left.Children.Add(name);

            var note = new TextBlock();
            note.Text = body;
            note.FontSize = 11.5;
            note.Foreground = Res("Faint");
            note.TextWrapping = TextWrapping.Wrap;
            note.Margin = new Thickness(0, 3, 12, 0);
            left.Children.Add(note);

            var b = new Button();
            b.Content = "Open the collection";
            b.Style = (Style)win.Resources["Solid"];
            b.VerticalAlignment = VerticalAlignment.Center;
            b.MinWidth = 96;
            Grid.SetColumn(b, 1); g.Children.Add(b);

            string url = cfg.CollectionUrl;
            b.Click += delegate
            {
                try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); }
                catch (Exception ex) { Log("Could not open the collection: " + ex.Message); }
            };

            // Connecting Discord only succeeds for an account the site has
            // already accepted, so a linked launcher is an accepted one and
            // this is the whole test. Anybody who has not been through the
            // application can see what is coming and cannot start on it.
            if (!Discord.Linked)
            {
                b.IsEnabled = false;
                b.Content = "Apply first";
                b.ToolTip = "The collection opens once your application is accepted and you have " +
                            "connected Discord below.";
                var gate = new TextBlock();
                gate.Text = "Connect Discord first. The collection opens once you have been accepted.";
                gate.FontSize = 11.5;
                gate.Foreground = Res("Bad");
                gate.TextWrapping = TextWrapping.Wrap;
                gate.Margin = new Thickness(0, 7, 12, 0);
                left.Children.Add(gate);
            }

            var card = new Border();
            card.Padding = new Thickness(14, 12, 14, 12);
            card.Background = Res("Panel");
            card.Margin = new Thickness(0, 0, 8, 10);
            card.Child = g;
            return card;
        }

        static void PackAction(Pack p, bool installed)
        {
            if (p == null || packBusy.Contains(p.id)) return;

            if (Checks.GameRunning())
            {
                Log("Close Skyrim first. Files it has open cannot be changed.");
                return;
            }

            packBusy.Add(p.id);
            BuildModList();

            ThreadPool.QueueUserWorkItem(delegate
            {
                try
                {
                    if (installed) Updater.RemovePack(cfg, p, SafeLog);
                    else Updater.ApplyPack(cfg, p, SafeLog);
                }
                catch (Exception ex)
                {
                    SafeLog((installed ? "Could not remove " : "Could not install ") +
                            p.Title + ": " + ex.Message);
                }
                finally
                {
                    win.Dispatcher.BeginInvoke(new Action(delegate
                    {
                        packBusy.Remove(p.id);
                        BuildModList();
                        DrawStatus();
                    }));
                }
            });
        }

        /// <summary>Log from a background thread. Log itself touches the UI.</summary>
        static void SafeLog(string m)
        {
            try
            {
                if (win.Dispatcher.CheckAccess()) Log(m);
                else win.Dispatcher.BeginInvoke(new Action(delegate { Log(m); }));
            }
            catch { }
        }

        static void verifyCardVisible(bool on)
        {
            var c = win.FindName("VerifyCard") as UIElement;
            if (c != null) c.Visibility = on ? Visibility.Visible : Visibility.Collapsed;
        }

        // Plugin and DLL rows go to the mod's own page. Anything the catalogue
        // does not have a confirmed address for falls back to a Nexus search
        // for the name, which is honest about not knowing and still lands the
        // reader one click away. The Bethesda masters and the two another server
        // plugins have nowhere to go, so those rows stay plain.
        static UIElement LinkedRow(int index, string name, bool on, string tag)
        {
            string url = Links.Target(name);
            if (url == null) return ModRow(index, name, on, tag, null, null);
            string hint = Links.Exact(name)
                ? "Open the mod page" + Environment.NewLine + url
                : "No page recorded for this one. Opens a Nexus search instead."
                  + Environment.NewLine + url;
            string target = url;
            return ModRow(index, name, on, tag, delegate { Open(target); }, hint);
        }

        /// <summary>
        /// Deletes one file out of the build, on purpose, with the person told
        /// what it costs first.
        ///
        /// This exists so somebody leaving Thornswood can keep what they still
        /// want rather than throwing the lot away and downloading it again for
        /// the next server. It refuses anything outside the build, because a
        /// delete button that can be pointed at the wrong folder is not a
        /// feature.
        /// </summary>
        static void DeleteFromBuild(string full, string shown, string consequence)
        {
            string root;
            try { root = Path.GetFullPath(Paths.Root); }
            catch { Log("Could not work out the install folder, so nothing was deleted."); return; }

            string fence = root.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
                         + Path.DirectorySeparatorChar;
            string target;
            try { target = Path.GetFullPath(full); }
            catch { Log("That path could not be read, so nothing was deleted."); return; }

            if (!target.StartsWith(fence, StringComparison.OrdinalIgnoreCase))
            {
                MessageBox.Show("That file is not inside the Thornswood folder, so this will not delete it.\n\n    " + target,
                                "Thornswood", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }

            var r = MessageBox.Show(
                "Delete this?\n\n    " + shown + "\n\n" + consequence +
                "\n\nThere is no undo in the launcher.",
                "Thornswood", MessageBoxButton.YesNo, MessageBoxImage.Warning);
            if (r != MessageBoxResult.Yes) return;

            try
            {
                if (File.Exists(target)) File.Delete(target);
                Log("Deleted " + shown);
            }
            catch (Exception ex)
            {
                Log("Could not delete " + shown + ": " + ex.Message);
                MessageBox.Show(ex.Message + "\n\nNothing was deleted. Close Skyrim if it is running.",
                                "Thornswood", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }
            BuildModList();
        }

        // A row in the mod list. When there is somewhere to send the reader,
        // the whole row becomes the link: hand cursor, a lift on hover, and an
        // arrow at the end so it reads as clickable before anyone hovers it.
        static UIElement ModRow(int index, string name, bool on, string tag, Action onClick, string hint)
        {
            return ModRow(index, name, on, tag, onClick, hint, null);
        }

        static UIElement ModRow(int index, string name, bool on, string tag, Action onClick, string hint, Action onDelete)
        {
            var g = new Grid();
            g.Margin = new Thickness(0, 0, 0, 1);
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(42) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(18) });

            var idx = new TextBlock();
            idx.Text = index.ToString();
            idx.FontFamily = new FontFamily("Cascadia Mono, Consolas");
            idx.FontSize = 11; idx.Foreground = Res("Faint");
            idx.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(idx, 0); g.Children.Add(idx);

            var t = new TextBlock();
            t.Text = name; t.FontSize = 12.5;
            t.Foreground = Res(on ? "Ink" : "Faint");
            t.TextTrimming = TextTrimming.CharacterEllipsis;
            t.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(t, 1); g.Children.Add(t);

            var tg = new TextBlock();
            tg.Text = on ? tag : tag + "  off";
            tg.FontFamily = new FontFamily("Cascadia Mono, Consolas");
            tg.FontSize = 10.5;
            tg.Foreground = Res(on ? "Muted" : "Bad");
            tg.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(tg, 2); g.Children.Add(tg);

            var arrow = new TextBlock();
            arrow.Text = "\u2197";                       // north east arrow
            arrow.FontSize = 11;
            arrow.Margin = new Thickness(7, 0, 0, 0);
            arrow.Foreground = Res("Faint");
            arrow.VerticalAlignment = VerticalAlignment.Center;
            arrow.HorizontalAlignment = HorizontalAlignment.Right;
            arrow.Visibility = onClick == null ? Visibility.Hidden : Visibility.Visible;
            Grid.SetColumn(arrow, 4); g.Children.Add(arrow);

            // Only where deleting is a real choice. The server plugins tab does
            // not get one: a row there is a plugin, not a mod, so deleting it
            // takes the esp and leaves that mod's textures and archives behind,
            // and the person cannot connect until it is back.
            if (onDelete != null)
            {
                var del = new Button();
                del.Content = "Delete";
                del.Style = (Style)win.Resources["Ghost"];
                del.FontSize = 11;
                del.Padding = new Thickness(9, 2, 9, 2);
                del.Margin = new Thickness(10, 0, 0, 0);
                del.VerticalAlignment = VerticalAlignment.Center;
                del.ToolTip = "Delete this file from the build";
                Action mine = onDelete;
                del.Click += delegate { mine(); };
                Grid.SetColumn(del, 3); g.Children.Add(del);
            }

            var b = new Border();
            b.Padding = new Thickness(10, 8, 12, 8);
            b.Background = Res("Panel");
            b.Margin = new Thickness(0, 0, 8, 3);
            b.Child = g;

            if (onClick != null)
            {
                b.Cursor = Cursors.Hand;
                b.ToolTip = hint;
                b.MouseEnter += delegate
                {
                    b.Background = Res("CardHover");
                    arrow.Foreground = Res("Accent");
                    t.Foreground = Res("Accent");
                };
                b.MouseLeave += delegate
                {
                    b.Background = Res("Panel");
                    arrow.Foreground = Res("Faint");
                    t.Foreground = Res(on ? "Ink" : "Faint");
                };
                b.MouseLeftButtonUp += delegate { onClick(); };
            }
            return b;
        }

        // Explorer, with the file already picked out. Used by the Your own tab,
        // where the thing worth reaching is the file itself, not a mod page.
        static void Reveal(string path)
        {
            try
            {
                var psi = new ProcessStartInfo("explorer.exe", "/select,\"" + path + "\"");
                psi.UseShellExecute = true;
                Process.Start(psi);
            }
            catch (Exception ex) { Log("Could not open the folder: " + ex.Message); }
        }

        // ------------------------------------------------------------- settings
        // Ten of them now, so they wrap instead of running off the side, and
        // each one says what it is rather than making you click to find out.
        static void BuildThemeRow()
        {
            themeRow.Children.Clear();

            var wrap = new WrapPanel();
            themeRow.Children.Add(wrap);

            foreach (Theme t in Themes.All)
            {
                Theme captured = t;
                bool on = string.Equals(t.Name, cfg.Theme, StringComparison.OrdinalIgnoreCase);

                var sw = new Border();
                sw.Width = 15; sw.Height = 15;
                sw.CornerRadius = new CornerRadius(2);
                sw.Background = new SolidColorBrush((Color)ColorConverter.ConvertFromString(t.Swatch));
                sw.Margin = new Thickness(0, 0, 10, 0);
                sw.VerticalAlignment = VerticalAlignment.Center;

                var label = new TextBlock();
                label.Text = t.Name;
                label.VerticalAlignment = VerticalAlignment.Center;
                label.FontWeight = on ? FontWeights.SemiBold : FontWeights.Normal;

                var sp = new StackPanel();
                sp.Orientation = Orientation.Horizontal;
                sp.Children.Add(sw);
                sp.Children.Add(label);

                var b = new Button();
                b.Content = sp;
                b.Style = (Style)win.Resources["Ghost"];
                b.Margin = new Thickness(0, 0, 9, 9);
                b.Padding = new Thickness(12, 9, 16, 9);
                b.MinWidth = 148;
                b.HorizontalContentAlignment = HorizontalAlignment.Left;
                if (on) b.Background = Res("CardHover");
                b.Click += delegate
                {
                    cfg.Theme = captured.Name;
                    cfg.Save(Paths.CfgFile);
                    Themes.Apply(win, captured.Name);
                    Redraw();
                    Log("Theme set to " + captured.Name + ".");
                };
                wrap.Children.Add(b);
            }

            Theme cur = Themes.Find(cfg.Theme);
            txtThemeNote.Text = cur.Name + ". " + cur.Note;
        }

        // Everything that paints itself from the theme brushes rather than
        // binding to them. Called after a theme change, and nowhere else.
        static void Redraw()
        {
            BuildThemeRow(); BuildModList(); DrawStatus(); BuildPathRows(); BuildHelp();
            BuildStatRow(); BuildNews(); BuildLogs(); BuildDisplay(); BuildChat();
            BuildServer(); BuildInstalled(); BuildControls(); BuildDiag(); RefreshDiscord();
            boxSearch.Foreground = Res(boxSearch.Text == SearchHint ? "Faint" : "Ink");
        }

        static void BuildPathRows()
        {
            pathRows.Children.Clear();
            AddPathRow("Install", Paths.Root);
            AddPathRow("Game", Paths.Game);
            AddPathRow("Saves", Path.Combine(Paths.LiveMyGames, "Saves"));
            AddPathRow("Settings", Paths.LiveMyGames);
        }

        static void AddPathRow(string label, string value)
        {
            var g = new Grid();
            g.Margin = new Thickness(0, 0, 0, 7);
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(78) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

            var l = new TextBlock();
            l.Text = label; l.FontSize = 12; l.Foreground = Res("Faint");
            Grid.SetColumn(l, 0); g.Children.Add(l);

            var v = new TextBlock();
            v.Text = value; v.FontSize = 11.5; v.FontFamily = new FontFamily("Cascadia Mono, Consolas");
            v.Foreground = Res("Muted"); v.TextTrimming = TextTrimming.CharacterEllipsis;
            Grid.SetColumn(v, 1); g.Children.Add(v);

            pathRows.Children.Add(g);
        }

        // ------------------------------------------------------------- help
        static void BuildHelp()
        {
            helpList.Children.Clear();
            string section = null;
            foreach (HelpItem h in Help.Items)
            {
                if (h.Section != section)
                {
                    section = h.Section;
                    var eyebrow = new TextBlock();
                    eyebrow.Text = section.ToUpperInvariant();
                    eyebrow.Foreground = Res("Accent");
                    eyebrow.FontSize = 10.5;
                    eyebrow.FontWeight = FontWeights.SemiBold;
                    eyebrow.Margin = new Thickness(0, helpList.Children.Count == 0 ? 0 : 22, 0, 14);
                    helpList.Children.Add(eyebrow);
                }

                var g = new Grid();
                g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(190) });
                g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

                var t = new TextBlock();
                t.Text = h.Title; t.FontSize = 13; t.FontWeight = FontWeights.SemiBold;
                t.Foreground = Res("Ink"); t.TextWrapping = TextWrapping.Wrap;
                t.Margin = new Thickness(0, 0, 20, 0);
                Grid.SetColumn(t, 0); g.Children.Add(t);

                var a = new TextBlock();
                a.Text = h.Body; a.FontSize = 12.5; a.Foreground = Res("Muted");
                a.TextWrapping = TextWrapping.Wrap; a.LineHeight = 20;
                Grid.SetColumn(a, 1); g.Children.Add(a);

                var b = new Border();
                b.BorderBrush = Res("Line");
                b.BorderThickness = new Thickness(0, 0, 0, 1);
                b.Padding = new Thickness(0, 0, 0, 14);
                b.Margin = new Thickness(0, 0, 0, 14);
                b.Child = g;
                helpList.Children.Add(b);
            }
        }


        // ------------------------------------------------------------- stat strip
        static void BuildStatRow()
        {
            statRow.Children.Clear();
            AddStat("Played", Stats.PlayedText);
            AddStat("Sessions", Stats.Sessions.ToString());
            AddStat("Last played", Stats.LastPlayedText);
            AddStat("Updated", string.IsNullOrEmpty(Stats.LastUpdate) ? "never" : Stats.LastUpdate);
            BuildSideCard();
        }

        // The first-time notes are read once and then become wallpaper, so the
        // side column hands itself over to something still worth glancing at.
        static void BuildSideCard()
        {
            bool played = Stats.Sessions > 0 || File.Exists(Paths.PlayedFile);
            firstRunCard.Visibility = played ? Visibility.Collapsed : Visibility.Visible;
            quickKeysCard.Visibility = played ? Visibility.Visible : Visibility.Collapsed;
            if (!played) return;

            quickKeys.Children.Clear();

            // Read out of the real files rather than typed here. The old list
            // was five hardcoded lines and it went stale the moment the build
            // moved off Skyrim Together: it was still offering an F2 party menu
            // that no longer exists and a trade key belonging to a mod that had
            // been removed. A row now appears only if its binding is really
            // there, and it shows the key it is really bound to.
            List<Keys.Binding> keys;
            try { keys = Keys.All(); } catch { keys = new List<Keys.Binding>(); }

            AddKeyFor(keys, "emotewheel", "The emote wheel");
            AddKeyFor(keys, "emotestop",  "Stand up out of an idle");
            AddKeyFor(keys, "menu",       "Mod settings");
            AddKeyFor(keys, "lock",       "Lock on to what you are aiming at");
            AddKeyFor(keys, "search",     "Search your inventory");

            // Not from a file: Skyrim's own, and the same on every install.
            AddKey("E / R", "Take one item, or the lot, at a container");
        }

        static void AddKeyFor(List<Keys.Binding> all, string id, string what)
        {
            foreach (Keys.Binding b in all)
            {
                if (!string.Equals(b.Id, id, StringComparison.Ordinal)) continue;
                if (string.IsNullOrEmpty(b.Value)) return;
                AddKey(b.Value, what);
                return;
            }
        }

        static void AddKey(string key, string what)
        {
            var g = new Grid();
            g.Margin = new Thickness(0, 0, 0, 9);
            // Auto rather than a fixed 58, with a minimum so the short ones
            // still line up. A fixed width was fine until a key was called
            // "Middle mouse", which then ran straight into its own description.
            var c0 = new ColumnDefinition(); c0.Width = GridLength.Auto;
            var c1 = new ColumnDefinition(); c1.Width = new GridLength(1, GridUnitType.Star);
            g.ColumnDefinitions.Add(c0);
            g.ColumnDefinitions.Add(c1);

            var k = new TextBlock();
            k.Text = key; k.FontSize = 11.5; k.FontWeight = FontWeights.SemiBold;
            k.FontFamily = new FontFamily("Cascadia Mono, Consolas");
            k.Foreground = Res("Accent");
            k.MinWidth = 52;
            k.Margin = new Thickness(0, 0, 14, 0);
            k.VerticalAlignment = VerticalAlignment.Top;
            Grid.SetColumn(k, 0);
            g.Children.Add(k);

            var v = new TextBlock();
            v.Text = what; v.FontSize = 12; v.Foreground = Res("Muted");
            v.TextWrapping = TextWrapping.Wrap; v.LineHeight = 17;
            Grid.SetColumn(v, 1);
            g.Children.Add(v);

            quickKeys.Children.Add(g);
        }

        static void AddStat(string label, string value)
        {
            var sp = new StackPanel();
            sp.Margin = new Thickness(0, 0, 30, 0);

            var l = new TextBlock();
            l.Text = label; l.FontSize = 11.5;
            l.FontFamily = new FontFamily("Constantia, Georgia");
            l.Foreground = Res("Faint");
            sp.Children.Add(l);

            var v = new TextBlock();
            v.Text = value; v.FontSize = 16; v.Foreground = Res("Ink");
            v.FontFamily = new FontFamily("Constantia, Georgia");
            v.Margin = new Thickness(0, 3, 0, 0);
            sp.Children.Add(v);

            statRow.Children.Add(sp);
        }

        // ------------------------------------------------------------- news
        static void BuildNews()
        {
            newsList.Children.Clear();
            NewsItem[] items = (pendingDoc != null && pendingDoc.news != null) ? pendingDoc.news : new NewsItem[0];

            if (items.Length == 0)
            {
                var empty = new TextBlock();
                empty.Text = Updater.Enabled(cfg)
                    ? "Nothing posted yet. Anything Patrick writes to the update feed turns up here."
                    : "Updates are not set up on this copy, so there is no news feed to read.";
                empty.Foreground = Res("Faint"); empty.FontSize = 12.5;
                empty.TextWrapping = TextWrapping.Wrap;
                newsList.Children.Add(empty);
                return;
            }

            // What this build has that main does not.
            //
            // The dev feed is main's whole history with the dev notes on top,
            // so the tab used to read as one long list with no seam in it. The
            // seam is the useful part: it is the difference between the build
            // in front of you and the build everybody plays, which is the list
            // of what wants testing before this one becomes that one.
            int ahead = 0;
            for (int i = 0; i < items.Length; i++) { if (items[i].IsDev) ahead++; }

            if (cfg.IsDev)
            {
                string mine = (pendingDoc != null) ? pendingDoc.launcherVersion : "";
                string theirs = (pendingDoc != null) ? pendingDoc.mainVersion : "";

                var head = new StackPanel();

                var ht = new TextBlock();
                ht.Text = string.IsNullOrEmpty(theirs)
                    ? "This is the dev build."
                    : "This is the dev build, on " + mine + ". Main is on " + theirs + ".";
                ht.FontSize = 13.5; ht.FontWeight = FontWeights.SemiBold;
                ht.Foreground = Res("Ink"); ht.TextWrapping = TextWrapping.Wrap;
                head.Children.Add(ht);

                var hb = new TextBlock();
                if (ahead == 0)
                {
                    hb.Text = "Nothing below is dev only. Everything here has gone out on main as well, so there is nothing waiting to be tested.";
                }
                else
                {
                    hb.Text = (ahead == 1 ? "One note below is marked DEV. It is" : ahead + " notes below are marked DEV. They are")
                            + " on this build and not on main yet, so that is what wants testing before dev goes over.";
                }
                hb.FontSize = 12; hb.Foreground = Res("Muted");
                hb.TextWrapping = TextWrapping.Wrap; hb.LineHeight = 18;
                hb.Margin = new Thickness(0, 6, 0, 0);
                head.Children.Add(hb);

                var hc = new Border();
                hc.Background = Res("Card");
                hc.BorderBrush = Res("Accent");
                hc.BorderThickness = new Thickness(2, 0, 0, 0);
                hc.Padding = new Thickness(16, 14, 16, 14);
                hc.Margin = new Thickness(0, 0, 0, 24);
                hc.Child = head;
                newsList.Children.Add(hc);
            }

            foreach (NewsItem n in items)
            {
                var sp = new StackPanel();

                if (!string.IsNullOrEmpty(n.DateText) || n.IsDev)
                {
                    var stamp = new StackPanel();
                    stamp.Orientation = Orientation.Horizontal;
                    stamp.Margin = new Thickness(0, 0, 0, 6);

                    if (!string.IsNullOrEmpty(n.DateText))
                    {
                        var d = new TextBlock();
                        d.Text = n.DateText.ToUpperInvariant();
                        d.FontSize = 9.5; d.FontWeight = FontWeights.SemiBold;
                        d.Foreground = Res("Accent");
                        d.VerticalAlignment = VerticalAlignment.Center;
                        stamp.Children.Add(d);
                    }

                    // Only a dev feed ever carries one of these, and inside a
                    // dev feed only the notes main has not had yet.
                    if (n.IsDev)
                    {
                        var ct = new TextBlock();
                        ct.Text = "DEV";
                        ct.FontSize = 8.5; ct.FontWeight = FontWeights.Bold;
                        ct.Foreground = Res("Warn");

                        var chip = new Border();
                        chip.BorderBrush = Res("Warn");
                        chip.BorderThickness = new Thickness(1);
                        chip.CornerRadius = new CornerRadius(3);
                        chip.Padding = new Thickness(5, 1, 5, 1);
                        chip.Margin = new Thickness(string.IsNullOrEmpty(n.DateText) ? 0 : 8, 0, 0, 0);
                        chip.VerticalAlignment = VerticalAlignment.Center;
                        chip.Child = ct;
                        stamp.Children.Add(chip);
                    }

                    sp.Children.Add(stamp);
                }

                var t = new TextBlock();
                t.Text = n.title; t.FontSize = 15; t.FontWeight = FontWeights.SemiBold;
                t.Foreground = Res("Ink"); t.TextWrapping = TextWrapping.Wrap;
                sp.Children.Add(t);

                if (!string.IsNullOrEmpty(n.body))
                {
                    var bd = new TextBlock();
                    bd.Text = n.body; bd.FontSize = 12.5; bd.Foreground = Res("Muted");
                    bd.TextWrapping = TextWrapping.Wrap; bd.LineHeight = 20;
                    bd.Margin = new Thickness(0, 7, 0, 0);
                    sp.Children.Add(bd);
                }

                if (n.details != null && n.details.Length > 0)
                {
                    var box = new StackPanel();
                    box.Margin = new Thickness(0, 12, 0, 0);
                    for (int i = 0; i < n.details.Length; i++)
                    {
                        string line = n.details[i];
                        if (string.IsNullOrEmpty(line)) continue;

                        var row = new StackPanel();
                        row.Orientation = Orientation.Horizontal;
                        row.Margin = new Thickness(0, 0, 0, 4);

                        var dot = new TextBlock();
                        dot.Text = "\u2022";
                        dot.FontSize = 12;
                        dot.Foreground = Res("Accent");
                        dot.Margin = new Thickness(0, 0, 8, 0);
                        row.Children.Add(dot);

                        var dt = new TextBlock();
                        dt.Text = line;
                        dt.FontSize = 11.5;
                        dt.Foreground = Res("Faint");
                        dt.TextWrapping = TextWrapping.Wrap;
                        dt.MaxWidth = 520;
                        row.Children.Add(dt);

                        box.Children.Add(row);
                    }
                    if (box.Children.Count > 0) sp.Children.Add(box);
                }

                if (n.files != null && n.files.Length > 0)
                {
                    var toggle = new Button();
                    toggle.Style = (Style)win.Resources["Ghost"];
                    toggle.Content = "Show the " + n.files.Length + " file" + (n.files.Length == 1 ? "" : "s");
                    toggle.HorizontalAlignment = HorizontalAlignment.Left;
                    toggle.Margin = new Thickness(0, 12, 0, 0);

                    var filesBox = new StackPanel();
                    filesBox.Visibility = Visibility.Collapsed;
                    filesBox.Margin = new Thickness(0, 10, 0, 0);
                    for (int i = 0; i < n.files.Length; i++)
                    {
                        var ft = new TextBlock();
                        ft.Text = n.files[i];
                        ft.FontSize = 10.5;
                        ft.FontFamily = new FontFamily("Cascadia Mono, Consolas");
                        ft.Foreground = Res(n.files[i].StartsWith("- ") ? "Warn" : "Faint");
                        ft.TextWrapping = TextWrapping.Wrap;
                        ft.Margin = new Thickness(0, 0, 0, 2);
                        filesBox.Children.Add(ft);
                    }

                    StackPanel captured = filesBox;
                    Button capturedButton = toggle;
                    string[] capturedFiles = n.files;
                    toggle.Click += delegate
                    {
                        bool open = captured.Visibility == Visibility.Visible;
                        captured.Visibility = open ? Visibility.Collapsed : Visibility.Visible;
                        capturedButton.Content = (open ? "Show the " : "Hide the ") + capturedFiles.Length
                                               + " file" + (capturedFiles.Length == 1 ? "" : "s");
                    };

                    sp.Children.Add(toggle);
                    sp.Children.Add(filesBox);
                }

                var b = new Border();
                b.BorderBrush = Res("Line");
                b.BorderThickness = new Thickness(0, 0, 0, 1);
                b.Padding = new Thickness(0, 0, 0, 20);
                b.Margin = new Thickness(0, 0, 0, 20);
                b.Child = sp;
                newsList.Children.Add(b);
            }
        }

        // ------------------------------------------------------------- saves and logs
        static void BuildSaves()
        {
            saveList.Children.Clear();
            var saves = Files.Saves();
            var backups = Files.Backups();

            txtSaveNote.Text = Files.SaveDir;
            txtSaveCount.Text = saves.Count == 0
                ? "No saves yet."
                : saves.Count + (saves.Count == 1 ? " save" : " saves") +
                  (backups.Count > 0 ? "   ·   " + backups.Count + " backup" + (backups.Count == 1 ? "" : "s") : "");

            int i = 0;
            foreach (Entry e in saves) { i++; saveList.Children.Add(FileRow(i, e.Name, e.Detail, false)); }
            foreach (Entry e in backups) { i++; saveList.Children.Add(FileRow(i, e.Name, e.Detail, true)); }
        }

        static void BuildLogs()
        {
            logList.Children.Clear();
            var logs = Files.Logs();
            int crashes = 0;
            foreach (Entry e in logs) if (e.Name.StartsWith("crash-")) crashes++;

            txtLogCount.Text = crashes == 0
                ? "No crash logs. " + Files.SkseLogDir
                : crashes + (crashes == 1 ? " crash log" : " crash logs") + ", newest first.   ·   " + Files.SkseLogDir;

            int i = 0;
            foreach (Entry e in logs) { i++; logList.Children.Add(FileRow(i, e.Name, e.Detail, !e.Name.StartsWith("crash-"))); }
        }

        static UIElement FileRow(int index, string name, string detail, bool dim)
        {
            var g = new Grid();
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(42) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            var idx = new TextBlock();
            idx.Text = index.ToString();
            idx.FontFamily = new FontFamily("Cascadia Mono, Consolas"); idx.FontSize = 11;
            idx.Foreground = Res("Faint"); idx.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(idx, 0); g.Children.Add(idx);

            var t = new TextBlock();
            t.Text = name; t.FontSize = 12.5;
            t.Foreground = Res(dim ? "Muted" : "Ink");
            t.TextTrimming = TextTrimming.CharacterEllipsis;
            t.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(t, 1); g.Children.Add(t);

            var d = new TextBlock();
            d.Text = detail; d.FontFamily = new FontFamily("Cascadia Mono, Consolas"); d.FontSize = 10.5;
            d.Foreground = Res("Faint"); d.VerticalAlignment = VerticalAlignment.Center;
            d.Margin = new Thickness(16, 0, 0, 0);
            Grid.SetColumn(d, 2); g.Children.Add(d);

            var b = new Border();
            b.Padding = new Thickness(10, 9, 12, 9);
            b.Background = Res("Panel");
            b.Margin = new Thickness(0, 0, 8, 3);
            b.Child = g;
            return b;
        }

        // ------------------------------------------------------------- display
        /// <summary>
        /// Matches the game to this screen, once, on a machine that has never
        /// played it.
        ///
        /// The build ships with whatever resolution it was packaged on, which
        /// is one particular ultrawide, and on anyone else's monitor that is
        /// the wrong shape. Setting it on the first run gets everybody a
        /// correct picture without ever touching it again, so a choice made in
        /// Settings afterwards is the last word.
        /// </summary>
        static void AutoDisplayOnce()
        {
            if (cfg.DisplaySet) return;

            // Written before anything else is attempted, so a failure below
            // cannot turn this into something that runs on every start.
            cfg.DisplaySet = true;
            try { cfg.Save(Paths.CfgFile); } catch { }

            // Somebody who has already played has settings of their own by now,
            // whether they chose them or not, and this is not the moment to
            // start moving them around.
            if (File.Exists(Paths.PlayedFile) || Stats.Sessions > 0) return;
            if (!Display.Available) return;

            Display.ScreenMode m = Display.Detect();
            if (m == null) return;

            string want = m.ToString();
            if (string.Equals(Display.Get("Resolution"), want, StringComparison.OrdinalIgnoreCase)) return;
            if (!Display.Set("Resolution", want)) return;

            BuildDisplay();
            Log("Display set to " + want + " to match your screen"
                + (m.Hz > 0 ? ", " + m.Hz + " Hz" : "")
                + ". Change it in Settings if you want something else.");
        }

        static void BuildDisplay()
        {
            displayModeRow.Children.Clear();

            // Field of view first, and outside the check below. It lives in
            // Thornswood.ini and is applied by the game plugin, so it works
            // whether or not SSE Display Tweaks is in the build, and greying
            // it out with the rest of the page would be wrong.
            boxFov.Text = Fov.Get().ToString();

            if (!Display.Available)
            {
                txtDisplayNote.Text = "SSE Display Tweaks is not in this build, so only the field of view can be set here.";
                boxResolution.IsEnabled = false; boxFrameLimit.IsEnabled = false;
                chkVSync.IsEnabled = false;
                return;
            }

            string current = Display.Mode;
            foreach (string mode in new string[] { "Borderless", "Fullscreen", "Windowed" })
            {
                string captured = mode;
                var b = new Button();
                b.Content = mode;
                b.Style = (Style)win.Resources["Ghost"];
                b.Margin = new Thickness(0, 0, 8, 0);
                if (mode == current) b.Background = Res("CardHover");
                b.Click += delegate
                {
                    Display.SetMode(captured);
                    BuildDisplay();
                    Log("Display mode set to " + captured.ToLowerInvariant() + ". It applies next time the game starts.");
                };
                displayModeRow.Children.Add(b);
            }

            string res = Display.Get("Resolution");
            Display.ScreenMode screen = Display.Detect();

            // Blank is auto detect, so the box stays blank. Filling it with the
            // screen we found would look helpful and would be a value somebody
            // could then lock by accident.
            //
            // What was wrong was the wording. A blank box under a line opening
            // "Resolution as 1920x1080" reads as a field that failed to load,
            // and the old note said blank "leaves it to the game", which is not
            // what happens: unless Lock resolution is ticked, pressing Play
            // sets the game to whatever the screen is running at. Lock is what
            // pins a resolution, not typing one.
            boxResolution.Text = res == null ? "" : res;

            string scr = screen == null ? null
                       : screen + (screen.Hz > 0 ? " at " + screen.Hz + " Hz" : "");
            string note;

            if (cfg.LockResolution)
            {
                note = string.IsNullOrEmpty(res)
                     ? "Locked, but nothing is set, so the game keeps whatever it had. Type a resolution like 1920x1080."
                     : "Locked to " + res + ", and it stays there whatever screen you are on.";
                if (scr != null && !string.IsNullOrEmpty(res) &&
                    !string.Equals(res, screen.ToString(), StringComparison.OrdinalIgnoreCase))
                    note += "  This screen is " + scr + ", which is fine if you meant it.";
            }
            else
            {
                note = "This follows your screen. Pressing Play sets the game to whatever it is "
                     + "running at, so moving to another monitor sorts itself out.";
                if (scr != null) note += "  Right now that is " + scr + ".";
                note += "  Tick Lock resolution below to keep one of your own instead.";
            }
            note += "  Frame limit is in frames per second.";
            txtDisplayNote.Text = note;
            boxFrameLimit.Text = Display.GetInt("FramerateLimit", 0).ToString();
            chkVSync.IsChecked = Display.GetBool("EnableVSync", true);
            chkLockRes.IsChecked = cfg.LockResolution;
        }

        /// <summary>
        /// How long the chat stays up after a line, and whether the needs bars
        /// are drawn. Both live in Thornswood.ini beside the field of view and
        /// are read by the game plugin when the game starts. See ChatFade and
        /// NeedsBars in Display.cs.
        /// </summary>
        static void BuildChat()
        {
            chatFadeRow.Children.Clear();
            int current = ChatFade.Get();
            foreach (int seconds in ChatFade.Choices)
            {
                int captured = seconds;
                var b = new Button();
                b.Content = seconds == 0 ? "Never" : seconds + " s";
                b.Style = (Style)win.Resources["Ghost"];
                b.Margin = new Thickness(0, 0, 8, 0);
                if (seconds == current) b.Background = Res("CardHover");
                b.Click += delegate
                {
                    if (!ChatFade.Set(captured))
                    {
                        Log("Could not save the chat setting to Thornswood.ini.");
                        return;
                    }
                    BuildChat();
                    Log(captured == 0
                        ? "The chat stays on screen all the time. It applies next time the game starts."
                        : "The chat hides " + captured + " seconds after its last line and comes back with a new line or Enter. It applies next time the game starts.");
                };
                chatFadeRow.Children.Add(b);
            }
            txtChatFadeNote.Text = current == 0
                ? "Never: the chat stays on screen all the time, as it used to."
                : "The chat hides " + current + " seconds after its last line, whoever sent it. A new line brings it back, and so does Enter.";
            chkNeedsBars.IsChecked = NeedsBars.Shown();
        }

        static void SaveDisplay()
        {
            // Field of view first, for the same reason it is read first.
            string rawFov = boxFov.Text.Trim();
            if (rawFov.Length == 0)
            {
                Fov.Set(Fov.Default);
            }
            else
            {
                int fov;
                if (!int.TryParse(rawFov, out fov) || fov < Fov.Min || fov > Fov.Max)
                {
                    Log("Field of view has to be a number between " + Fov.Min + " and " +
                        Fov.Max + ". Skyrim's own is " + Fov.Default + ".");
                    return;
                }
                Fov.Set(fov);
            }

            if (!Display.Available)
            {
                BuildDisplay();
                Log("Field of view saved. It applies next time the game starts.");
                return;
            }

            string res = boxResolution.Text.Trim();
            if (res.Length > 0 && !System.Text.RegularExpressions.Regex.IsMatch(res, @"^\d{3,5}x\d{3,5}$"))
            {
                Log("Resolution has to look like 1920x1080, or be left blank.");
                return;
            }
            if (res.Length > 0) Display.Set("Resolution", res);

            int fps;
            if (int.TryParse(boxFrameLimit.Text.Trim(), out fps) && fps > 0)
            {
                Display.Set("FramerateLimit", fps.ToString());
                Display.Set("MaximumRefreshRate", fps.ToString());
            }
            Display.Set("EnableVSync", chkVSync.IsChecked == true ? "true" : "false");
            BuildDisplay();
            Log("Display settings written. They apply next time the game starts.");
        }

        // ------------------------------------------------------------- ping
        /// <summary>
        /// Is the server there, and how far away is it.
        ///
        /// These are two different questions and this used to answer only the
        /// first one, badly. It pinged, and reported the server down whenever
        /// the ping got no reply. ICMP echo is the first thing a host drops
        /// under load or on principle, so the page sat there saying "no answer"
        /// about a server that was up and serving, with a chart of green bars
        /// directly underneath contradicting it.
        ///
        /// What actually settles it is a TCP connect to the resources port. The
        /// game traffic itself is UDP with nothing to connect to, but the server
        /// serves its resources folder over TCP on 3000 and that is only open
        /// when the server is running. So: TCP decides whether it is up, and
        /// the ping is just the nicer latency number when it comes back.
        /// </summary>
        static void StartPing()
        {
            txtPing.Text = "checking";
            dotServer.Fill = Res("Faint");

            string host = cfg.ServerAddress;
            if (string.IsNullOrEmpty(host)) { txtPing.Text = "no address"; return; }

            ThreadPool.QueueUserWorkItem(delegate
            {
                long icmp = -1;
                try
                {
                    using (var p = new Ping())
                    {
                        PingReply r = p.Send(host, 2000);
                        if (r != null && r.Status == IPStatus.Success) icmp = r.RoundtripTime;
                    }
                }
                catch { }

                long tcp = -1;
                try
                {
                    var sw = System.Diagnostics.Stopwatch.StartNew();
                    using (var c = new System.Net.Sockets.TcpClient())
                    {
                        IAsyncResult ar = c.BeginConnect(host, SkyMp.ResourcePortFor(cfg), null, null);
                        if (ar.AsyncWaitHandle.WaitOne(2000) && c.Connected)
                        {
                            c.EndConnect(ar);
                            tcp = sw.ElapsedMilliseconds;
                        }
                    }
                }
                catch { }

                bool up = tcp >= 0 || icmp >= 0;
                long ms = icmp >= 0 ? icmp : tcp;
                bool serving = tcp >= 0;

                win.Dispatcher.BeginInvoke(new Action(delegate
                {
                    if (up)
                    {
                        txtPing.Text = ms + " ms";
                        dotServer.Fill = Res(serving ? "Ok" : "Warn");
                    }
                    else
                    {
                        txtPing.Text = "no reply";
                        dotServer.Fill = Res("Warn");
                    }
                    RecordPing(up ? ms : -1, serving);
                    AskOnline();
                }));
            });
        }

        // ------------------------------------------------------------- play
        /// <summary>
        /// <summary>
        /// What the Server page says about voice.
        ///
        /// This launcher no longer opens anything. Voice used to run in a
        /// Chromium window beside the game, which was wrong twice over: it was
        /// a second window to alt-tab to, and it could not have worked anyway.
        /// It was served from http://&lt;address&gt;:7778, and Chromium exposes
        /// the microphone only on https or on localhost, so on a plain http
        /// remote address navigator.mediaDevices is not blocked, it is absent.
        /// No command line flag changes that: it is an origin rule.
        ///
        /// So voice runs in the game's own browser, the one already drawing the
        /// chat and the names, loaded from file://, which Chromium does treat as
        /// trustworthy. The plugin forwards the push to talk key, because the
        /// game's browser never holds focus while you play. Nothing to open,
        /// nothing to allow, no window.
        ///
        /// All that is left here is whether the service answers, which is worth
        /// showing because it is the one part that lives on the server.
        /// </summary>


        static void DrawVoiceState()
        {
            if (txtVoiceState == null) return;
            Config c = cfg;
            txtVoiceState.Text = "checking";
            ThreadPool.QueueUserWorkItem(delegate
            {
                // Asked at the address voice really uses, not by knocking on the
                // raw port. Since 1.1.49 the service sits behind the site's
                // certificate and listens only on the VPS's own loopback, so the
                // raw port no longer answers from outside, and the knock said
                // nobody would hear anybody while voice was working. VoiceBase is
                // the feed's voiceUrl, or host and port on a config that has
                // none, which asks the same place the knock did.
                string where = c.VoiceBase();
                bool up = false;
                try
                {
                    try { System.Net.ServicePointManager.SecurityProtocol |= (System.Net.SecurityProtocolType)3072; } catch { }
                    var req = (System.Net.HttpWebRequest)System.Net.WebRequest.Create(where + "/health");
                    req.Method = "GET";
                    req.Timeout = 4000;
                    req.ReadWriteTimeout = 4000;
                    using (var resp = (System.Net.HttpWebResponse)req.GetResponse())
                        up = resp.StatusCode == System.Net.HttpStatusCode.OK;
                }
                catch { }

                bool fUp = up;
                win.Dispatcher.BeginInvoke(new Action(delegate
                {
                    try
                    {
                        string keys = "";
                        try
                        {
                            foreach (Keys.Binding b in Keys.All())
                            {
                                if (b.Id == "ptt") keys = "  Hold " + b.Value + " to talk.";
                            }
                        }
                        catch { }

                        txtVoiceState.Text = fUp
                            ? ("Running at " + where +
                               ". It starts inside the game on its own." + keys)
                            : ("Not answering at " + where +
                               ", so nobody will hear anybody. It is not installed on the server, or not running.");
                    }
                    catch { }
                }));
            });
        }

        // The probe waits on a socket, so it does not run on the thread that
        // draws. A settings page that freezes for most of a second every time
        // it is opened is worse than one that fills in a moment later.
        /// <summary>The dev build card on Settings: what is installed and what the buttons do.</summary>
        static void DrawDevBuild()
        {
            if (btnDevInstall == null || btnDevRemove == null || txtDevState == null) return;
            // The card is for the roles the dev build is for. It shows once
            // the site has said yes at a check in, or when a dev build is
            // already installed here, and on the dev build itself.
            bool allowed = cfg.IsDev || Discord.DevAllowed || DevBuild.Installed;
            if (pnlDev != null) pnlDev.Visibility = allowed ? Visibility.Visible : Visibility.Collapsed;
            if (!allowed) return;
            if (cfg.IsDev)
            {
                txtDevState.Text = "This is the dev build. It follows the dev branch and joins the dev server on port " + cfg.ServerPort + ". The main build is the one you installed first, and it is not touched from here.";
                btnDevInstall.Visibility = Visibility.Collapsed;
                btnDevRemove.Visibility = Visibility.Collapsed;
                return;
            }
            bool have = DevBuild.Installed;
            btnDevInstall.Content = have ? "Open the dev build" : "Install the dev build";
            btnDevRemove.Visibility = have ? Visibility.Visible : Visibility.Collapsed;
            txtDevState.Text = have
                ? "Installed at " + DevBuild.Root + ". It has its own Start menu entry, Thornswood Dev, and updates itself from the dev branch."
                : "Not installed. Installing copies this launcher into " + DevBuild.Root + " and opens it. Nothing about this build changes.";
        }

        static void DoUninstall()
        {
            string why = Uninstall.WhyNot();
            if (why != null)
            {
                MessageBox.Show(why, "Thornswood", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }

            bool keep = chkKeepSaves.IsChecked == true;
            // Ticked by default, which is what this always did. Unticking it is
            // the new part: the mods stay and a reinstall reuses them.
            bool dropMods = chkDeleteMods == null || chkDeleteMods.IsChecked == true;

            var goes = new StringBuilder();
            var stays = new StringBuilder();

            if (Paths.Collection)
            {
                // Paths.Game is the Skyrim they own on Steam here. Measuring
                // that and calling it "the mods" told somebody at the uninstall
                // screen that thirty gigabytes of their own game was about to
                // go. It never was: Begin refuses to delete it whatever the box
                // says. But the dialog said it, which is the worst possible
                // sentence to read at that exact moment.
                long ourBytes = 0; int ourCount = 0;
                try { Uninstall.OurGameFiles(cfg, out ourBytes, out ourCount); }
                catch { ourBytes = 0; ourCount = 0; }
                string ours = ourCount > 0
                    ? ourCount.ToString("n0") + " files, " +
                      (ourBytes / 1024.0 / 1024.0).ToString("0") + " MB"
                    : "nothing on record";

                if (dropMods) goes.AppendLine("    Thornswood's own files inside your Skyrim   (" + ours + ")");
                else          stays.AppendLine("    Thornswood's own files inside your Skyrim   (" + ours + ")");
                stays.AppendLine("    Your Skyrim on Steam. None of it is touched");
                stays.AppendLine("    The collection's mods. Purge Mods in Vortex is what removes those");
            }
            else if (OwnGame.Active)
            {
                // Made of links to Vortex's copies, so deleting it frees the
                // copied part and not the collection; the collection's files
                // stay Vortex's under their other names.
                if (dropMods) goes.AppendLine("    " + Paths.Game + "   (Thornswood's own game folder; the linked mods stay Vortex's)");
                else          stays.AppendLine("    " + Paths.Game + "   (Thornswood's own game folder)");

                // What the installer wrote into the Steam copy before the folder
                // existed comes out with it, from the installer's own list.
                long ourBytes = 0; int ourCount = 0;
                try { Uninstall.OurGameFiles(cfg, out ourBytes, out ourCount); }
                catch { ourBytes = 0; ourCount = 0; }
                string ours = ourCount > 0
                    ? ourCount.ToString("n0") + " files, " +
                      (ourBytes / 1024.0 / 1024.0).ToString("0") + " MB"
                    : "nothing on record";
                if (dropMods) goes.AppendLine("    Thornswood's own files inside your Skyrim on Steam   (" + ours + ")");
                else          stays.AppendLine("    Thornswood's own files inside your Skyrim on Steam   (" + ours + ")");
                stays.AppendLine("    Your Skyrim on Steam. None of the rest of it is touched");
                stays.AppendLine("    The collection's mods. Purge Mods in Vortex is what removes those");
            }
            else
            {
                int files = 0;
                long bytes = Uninstall.Measure(Paths.Game, ref files);
                string size = bytes > 0
                    ? (bytes / 1024.0 / 1024.0 / 1024.0).ToString("0.0") + " GB" : "some space";
                if (dropMods) goes.AppendLine("    " + Paths.Game + "   (" + size + ", the mods)");
                else          stays.AppendLine("    " + Paths.Game + "   (" + size + ", the mods)");
                stays.AppendLine("    Your own Skyrim on Steam");
            }

            goes.AppendLine("    " + Paths.LauncherDir);
            goes.AppendLine("    " + Paths.Personal);
            if (!keep)
            {
                goes.AppendLine("    " + Paths.ProfileDir + "   (your characters and settings)");
                goes.AppendLine("    " + Paths.CfgFile);
            }
            else
            {
                stays.AppendLine("    " + Paths.ProfileDir + "   (your characters and settings)");
                stays.AppendLine("    " + Paths.CfgFile);
            }

            // Named rather than removed quietly, because it is not where
            // anybody would look for it and it is usually the biggest thing on
            // the list.
            try
            {
                foreach (string sc in Uninstall.Scratch())
                    goes.AppendLine("    " + sc + "   (what the installer left behind)");
            }
            catch { }

            // The dev build is a second install in a folder of its own, beside
            // this one, with its own launcher and its own game folder. Nothing
            // here removes it and nothing here can: every path this uninstall
            // deletes has to sit under Root, and that fence is the reason a
            // wrong entry in a list can never become rmdir pointed at somebody's
            // game. So it is named instead of quietly left, because somebody who
            // has just uninstalled Thornswood and still has a Thornswood
            // launcher on their machine is owed the reason.
            try
            {
                if (Directory.Exists(DevBuild.Root))
                    stays.AppendLine("    the dev build at " + DevBuild.Root +
                                     "   (its own launcher uninstalls it)");
            }
            catch { }

            stays.AppendLine("    Windows' own Skyrim settings and saves");

            var r1 = MessageBox.Show(
                "This removes:\n\n" + goes +
                "\nThis is left alone:\n\n" + stays +
                "\nWindows\u2019 Skyrim settings and saves folders are pointed back at your own copy " +
                "first. If that fails, nothing is deleted.\n\nContinue?",
                "Uninstall Thornswood", MessageBoxButton.YesNo, MessageBoxImage.Warning);
            if (r1 != MessageBoxResult.Yes) return;

            // Built from what is actually about to happen rather than from
            // four hand written sentences, which is how one of them came to
            // talk about deleting mods on an install where it deletes none.
            string mods = Paths.Collection
                ? (dropMods ? "Thornswood's files come out of your Skyrim"
                            : "Thornswood's files stay in your Skyrim")
                : (dropMods ? "The mods go" : "The mods stay where they are");
            string chars = keep ? "your characters stay" : "your characters go";
            string warn = keep ? "" : "  None of that can be got back.";

            var r2 = MessageBox.Show(
                "Last check. " + mods + ", and " + chars + "." + warn +
                (Paths.Collection
                   ? "\n\nThe collection itself is Vortex's. Purge Mods there when you want it gone."
                   : "") +
                "\n\nThe launcher closes as it finishes.",
                "Uninstall Thornswood", MessageBoxButton.YesNo, MessageBoxImage.Warning);
            if (r2 != MessageBoxResult.Yes) return;

            btnUninstall.IsEnabled = false;
            try
            {
                string[] rest = Uninstall.Begin(cfg, keep, dropMods, Log);
                Log("Handing the rest to Windows and closing...");
                Uninstall.Finish(rest, keep, dropMods);
            }
            catch (Exception ex)
            {
                btnUninstall.IsEnabled = true;
                Log("Uninstall stopped: " + ex.Message);
                MessageBox.Show(ex.Message + "\n\nNothing was removed.",
                                "Thornswood", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }

            Application.Current.Shutdown();
        }

        static void DrawServerState()
        {
            if (txtServerState == null) return;
            Config c = cfg;
            ThreadPool.QueueUserWorkItem(delegate
            {
                bool local = false, up = false, ours = false, node = true;
                string dir = null;
                try
                {
                    local = SkyMp.IsLocal(c);
                    up = SkyMp.Up(c);
                    dir = SkyMp.ServerDir(c);
                    ours = SkyMp.Ours() != null;
                    if (local && dir != null) node = SkyMp.NodeExe() != null;
                }
                catch { }

                bool fLocal = local, fUp = up, fOurs = ours, fNode = node;
                string fDir = dir;
                win.Dispatcher.BeginInvoke(new Action(delegate
                {
                    try
                    {
                        var sb = new StringBuilder();
                        sb.Append(fUp ? "UP" : "not answering").Append("   ")
                          .Append(fLocal ? "this machine" : c.ServerAddress)
                          .Append(":").Append(c.ServerPort);
                        if (fUp && fOurs) sb.Append("   started by this launcher");
                        if (fLocal)
                        {
                            sb.Append(Environment.NewLine);
                            sb.Append(fDir != null ? fDir : "no server folder found on this machine");
                            if (fDir != null && !fNode)
                                sb.Append(Environment.NewLine).Append("Node is not installed, so it cannot be started from here.");
                        }
                        txtServerState.Text = sb.ToString();
                        btnServerStart.IsEnabled = fLocal && !fUp;
                        btnServerStop.IsEnabled = fOurs;
                    }
                    catch { }
                }));
            });
        }

        /// <summary>
        /// Makes sure something is actually listening before the game starts.
        ///
        /// This is the failure everyone hits and nobody recognises. Without a
        /// server, SkyMP never sends the message that creates your character,
        /// so the client never loads a world: you get a long wait, a black
        /// screen, and then single player with no creation menus and no
        /// character on the server. It reads as the game being broken. It is
        /// one window nobody opened.
        /// </summary>
        static bool EnsureServer()
        {
            try
            {
                if (SkyMp.Up(cfg)) return true;

                if (!SkyMp.IsLocal(cfg))
                {
                    var r = MessageBox.Show(
                        "The server at " + cfg.ServerAddress + " is not answering.\n\n" +
                        "Starting anyway gives you a long wait, a black screen and then single player: " +
                        "no character creation, and nothing anyone else can see.\n\nStart the game anyway?",
                        "Thornswood", MessageBoxButton.YesNo, MessageBoxImage.Warning);
                    if (r != MessageBoxResult.Yes) { Log("Not starting. The server is not answering."); return false; }
                    Log("Starting anyway. The server is not answering.");
                    return true;
                }

                // Up to forty eight seconds of waiting on the server to answer,
                // and the window has to keep drawing through it or Windows
                // offers to close the launcher instead. SafeLog, because what
                // Start says now comes from another thread.
                string why = null;
                Waiting(delegate { why = SkyMp.Start(cfg, SafeLog); });
                if (why == null) { Log("The server is up."); return true; }

                Log(why);
                MessageBox.Show(why, "Thornswood", MessageBoxButton.OK, MessageBoxImage.Warning);
                return false;
            }
            catch (Exception ex)
            {
                Log("Could not check the server: " + ex.Message);
                return true;
            }
        }

        static void Play()
        {
            try
            {
                // The button is not the only way in here. StartPlay, after the
                // Discord check, and a session coming back call this too, and
                // greying out btnPlay does nothing for those, so the three
                // things the button is disabled for are checked again on the
                // way in. The
                // one that bites is updatePending: the game closes for an
                // update, the pack is being fetched, and a press in that gap
                // starts Skyrim on a half extracted build.
                if (updatePending) { Log("An update is going in. Play comes back when it is done."); return; }
                if (collectionBarUp) { Log("The collection is not installed yet. Open it from the card above Play, then come back."); return; }
                if (ownGameBusy) { Log("Thornswood's own Skyrim folder is being prepared. Play comes back when it is done."); return; }
                if (feedNotice.Hold != null) { Log(feedNotice.Hold); return; }

                if (!File.Exists(Paths.Loader)) { Log("skse64_loader.exe is missing from this build."); return; }
                if (!File.Exists(Paths.MpClient)) { Log("MpClientPlugin.dll is missing, so this build has no multiplayer in it."); return; }

                // Starting a second one on top of a copy that never exited is
                // how people end up staring at a launcher that says the game is
                // running while their screen says otherwise.
                if (!ClearStuckGame(true)) return;

                // Checked again here, not just at startup, because the player's
                // own mods folder and the plugin list can both change in between.
                int blockers = 0, absent = 0;
                List<Issue> found = null;
                Waiting(delegate { found = Verify.Run(cfg); });
                foreach (Issue i in found)
                {
                    if (!i.Blocking) continue;
                    blockers++;
                    if (i.Absent) absent++;
                }
                if (blockers > 0)
                {
                    Log("Not launching. " + blockers + " problem" + (blockers == 1 ? "" : "s") + " with your mod list would desync everyone.");
                    RunScan();
                    DrawStatus();
                    ShowPage(PageMods);

                    // Two different problems wearing the same coat. A list in
                    // the wrong order is Fix's job. Plugins whose files are not
                    // on disk at all is not: nothing in this launcher can put a
                    // mod back, and telling somebody to press Fix when that is
                    // what happened sends them round in circles.
                    if (absent > 0)
                    {
                        MessageBox.Show(
                            (absent == 1 ? "A mod the server needs is not installed." : absent + " mods the server needs are not installed.") +
                            "\n\nThe usual reason is that a different profile is active in Vortex. Open Vortex, go to " +
                            "Profiles, and press Enable under Thornswood. Close Skyrim first if it is open.\n\n" +
                            "If you have never installed the collection, the Add-ons page has a button that opens it.\n\n" +
                            "Pressing Fix will not help with this one. Fix repairs the plugin list, it cannot install a mod.",
                            "Thornswood", MessageBoxButton.OK, MessageBoxImage.Warning);
                    }
                    else
                    {
                        MessageBox.Show(
                            "Your mod list does not match the one this build shipped with.\n\n" +
                            "Joining like this desyncs the whole server, so the launcher will not start the game until it is sorted.\n\n" +
                            "Press Fix on the Mods page, then try again.",
                            "Thornswood", MessageBoxButton.OK, MessageBoxImage.Warning);
                    }
                    return;
                }

                // Every file in the personal folder, copied over the top on
                // every Play with nothing comparing them first, so a big one is
                // a visible stall on the window's own thread.
                int mine = 0;
                Waiting(delegate { mine = Verify.DeployPersonal(); });
                if (mine > 0) Log("Copied in " + mine + " of your own files.");

                // Several of these mods rewrite their own ini when Skyrim
                // exits, so a fix written once does not survive the next quit.
                // Putting them back here, every launch, is what makes them
                // stick.
                // Skyrim's window size and Display Tweaks' resolution are two
                // separate settings and either one left on an old monitor's
                // numbers is what leaves the game not reaching the bottom of
                // the screen. Checked every launch, because people change
                // monitors and nobody thinks to come back here.
                if (!cfg.LockResolution)
                {
                    string moved = Display.MatchScreen();
                    if (moved != null) Log("Set the game to " + moved + " to match your screen. Tick Lock resolution in Settings to stop that.");
                    Display.ScaleMenus();
                }

                int held = Enforce.Apply();
                if (held > 0) Log("Put back " + held + " setting" + (held == 1 ? "" : "s") + " the last session overwrote.");
                foreach (string note in Enforce.Said) Log(note);

                // Written fresh every launch so the address and port the client
                // reads are whatever the launcher is showing. SkyMP has no join
                // screen: this file is the whole of joining.
                string join = AutoJoin.Apply(cfg);
                if (join != null) Log(join);

                // Same idea, for the microphone. The game's browser opens the
                // capture device and asking it for nothing gets Chromium's
                // default, which is not the one in Windows' sound settings. It
                // has to be told a name, and the name cannot ship with the
                // build because everybody owns a different microphone, so it
                // is read off this machine and written into this machine's ini.
                try { string ini = ThornIni.Ensure(); if (ini != null) Log(ini); } catch { }
                try
                {
                    string mic = Mics.Apply(cfg);
                    if (!string.IsNullOrEmpty(mic)) Log("Microphone: " + mic);
                }
                catch { }

                if (!EnsureServer()) return;

                // Another SkyMP server's launcher may have rewritten the page
                // the front plugin loads, or the client, or dropped its own
                // plugin in beside ours. Ours go back and theirs step aside
                // until the game closes. See Keep. Last thing before the game
                // starts, so nothing that can still say no leaves them parked.
                string kept = Keep.Restore();
                if (kept != null) Log(kept);
                Keep.LeaveNote();

                // And held, read only, until the game closes. Another server's
                // launcher opened mid-session rewrote them under the game once
                // (16 Sep, 19:08); it cannot now. See Hold.
                int holding = 0;
                try { holding = Hold.Take(PresenceLog); } catch { }
                if (holding > 0) Log("Holding " + holding + " of " + cfg.BuildName + "'s game files while the game runs, so nothing else can change them under it.");

                Log("Pointing Skyrim settings and saves at this build.");
                Swap.Apply();
                playing = true;
                MusicDecide();
                headerVideoDecide();
                btnPlay.IsEnabled = false;
                btnPlay.Content = "RUNNING";
                btnQuitGame.Visibility = Visibility.Visible;

                // Working directory must be the game root. Address Library
                // resolves Data/SKSE/Plugins/versionlib-*.bin relative to it,
                // and EngineFixes refuses to load with "failed to locate an
                // appropriate address library" when it is wrong, even though
                // the file is sitting right there.
                //
                // No --exePath any more. That existed because Skyrim Together's
                // own client looked Skyrim up through Steam's registry key and
                // would start the wrong copy. skse64_loader starts the exe
                // beside it, so the build it is sitting in is the one that runs.
                var psi = new ProcessStartInfo(Paths.Loader);
                psi.WorkingDirectory = Paths.Game;

                // No command line switches, and there is no arguing with this
                // one: skse64_loader parses its own arguments and refuses
                // anything it does not recognise. Handing it
                // --enable-media-stream got a message box saying "Couldn't
                // read arguments." and no game at all. It does not forward an
                // unknown switch to SkyrimSE.exe; it stops.
                //
                // Which is fine, because the thing that switch was for is now
                // compiled in. The browser is CEF 108 on the Alloy runtime and
                // SkyrimPlatform registered no permission handler, so every
                // getUserMedia call was denied before Windows saw it, with no
                // prompt to accept because there was nothing there to raise
                // one. MyChromiumApp::OnBeforeCommandLineProcessing appends
                // the switch itself now, inside the process where CEF reads
                // it, which is both the correct place and the only one that
                // was ever reachable.
                //
                // So the microphone travels in SkyrimPlatformImpl.dll, as a
                // mod file, to everybody. Nothing here has to know about it.
                psi.UseShellExecute = true;
                Process.Start(psi);
                // Which pack this game runs on, in the line everybody pastes.
                // Play is shut while a pack waits, but a feed that cannot be
                // reached frees it (Unblock), so "on the right update" was a
                // question until now and this makes it a line in the log.
                string onPack = "no pack";
                try
                {
                    var ids = new List<string>(Updater.Applied());
                    ids.Sort(StringComparer.Ordinal);
                    if (ids.Count > 0) onPack = "pack " + ids[ids.Count - 1];
                }
                catch { }
                // The display mode rides along because Skyrim itself is known to
                // go down on alt tab in exclusive fullscreen, and a crash report
                // with no crash log needs this line to say which mode it was.
                string mode = "";
                try { mode = ", " + Display.Mode.ToLowerInvariant(); } catch { }
                Log("Starting the game on launcher " + Updater.Version + ", " + onPack + mode + ".");

                // The site keeps a log of who played, when, and on which
                // build, so the staff console has a sheet to fill in rather
                // than a last played stamp. One id for this session, the start
                // now and the end when the game closes. Off this thread, and
                // wrapped, so a site that is down changes nothing about
                // playing. No character is picked yet: the menu does that, and
                // the end carries whoever was chosen.
                try { Discord.NewSession(); } catch { }
                int startedAs = chosenId;
                ThreadPool.QueueUserWorkItem(delegate
                {
                    try { Discord.SessionStart(startedAs); } catch { }
                });

                // "Playing Thornswood" in Discord, with the headcount and the
                // Download and Discord buttons, for as long as the game runs.
                // Off this thread entirely; a Discord that is not running is
                // simply nothing said.
                try { Presence.Start(cfg, PresenceLog); } catch { }

                try { File.WriteAllText(Paths.PlayedFile, DateTime.Now.ToString("o")); } catch { }
                playStartedAt = DateTime.Now;
                Stats.StartedPlaying();
                BuildStatRow();
                Thread.Sleep(1200);
                if (!cfg.KeepLauncherOpen) win.WindowState = WindowState.Minimized;
            }
            catch (Exception ex)
            {
                string reason = ex.Message == null ? "" : ex.Message;

                // The whole thing still goes to the log file, because Log
                // writes there before the bar trims anything, and the log is
                // how a report from a tester becomes something to act on.
                Log("Failed to start: " + reason);

                Swap.Restore();
                try { Hold.Release(); } catch { }
                try { Keep.Unpark(); } catch { }
                try { Presence.Stop(); } catch { }
                Keep.TakeNote();
                playing = false;
                headerVideoDecide();
                btnPlay.Content = "PLAY";
                DrawStatus();

                // A start that failed has one job left, which is to say why in
                // a way the person can act on, and the status bar cannot do it.
                //
                // WHAT A TESTER SAW, 21 September: Swap.MoveAside could not
                // move a folder, so it threw the message it was written to
                // throw, which names the folder and then the two causes worth
                // acting on: a Skyrim or multiplayer client left over from a
                // crash, which a restart clears, and the folder sitting in
                // OneDrive, which needs moving out for good. Three lines.
                // TxtStatus is one line with TextTrimming CharacterEllipsis,
                // so they read "Failed to start: Windows would not let go of"
                // and nothing after it, and reported that it cuts off. It did.
                // Every line past the first was written for exactly the person
                // who was not shown it.
                //
                // Last, and not before the cleanup above, because this blocks
                // until it is dismissed and the folders should be back by then.
                if (reason.IndexOf('\n') >= 0)
                {
                    try
                    {
                        MessageBox.Show(win, reason, "Thornswood could not start",
                                        MessageBoxButton.OK, MessageBoxImage.Warning);
                    }
                    catch { }
                }
            }
        }

        // ------------------------------------------------------------- updates
        // ------------------------------------------------------------- who is on
        static string pingText = "";

        /// <summary>Presence speaks from its own thread; the log lives on this one.</summary>
        static void PresenceLog(string m)
        {
            try { win.Dispatcher.BeginInvoke(new Action(delegate { Log(m); })); } catch { }
        }

        static void AskOnline()
        {
            pingText = txtPing.Text;
            ThreadPool.QueueUserWorkItem(delegate
            {
                Online.Count c = null;
                try { c = Online.Ask(cfg); } catch { }
                Online.Count got = c;
                win.Dispatcher.BeginInvoke(new Action(delegate
                {
                    string extra = Online.Line(got);
                    if (extra.Length > 0) txtPing.Text = pingText + "   \u00b7   " + extra;
                    if (playing && got != null)
                    {
                        try { Presence.Update(got.Known ? got.Now : -1, got.Max); } catch { }
                    }
                }));
            });
        }

        // ------------------------------------------------------------- characters
        //
        // Until 20 September this was the character picker: NameOf, SlotName,
        // StartAs(slot, fresh), ForgetChar, DescribeChar, RefreshRoster and
        // BuildChars drew two slot cards under Play, each with its own Play or
        // Make a character button and a Delete. The person picks at the game's
        // own main menu now, from a list Chars.Prepare writes into
        // Data\Platform, and the plugin writes the answer to a file the two
        // second tick reads. Nothing here draws a character any more.

        // A Discord check is out and the game starts on its answer. Only
        // btnPlay was ever switched off while it was, and the slot cards sat
        // on their own bar: two presses on a slot's Play sent two checks, both
        // came back allowed, and the second start found the first Skyrim
        // already up, closed it as a stuck one, and started again. The cards
        // are gone; the flag stays, because a press that lands while the site
        // is still thinking is the same race.
        static bool doorCheckOut = false;

        /// <summary>
        /// Play, from the button. Door.Check first, exactly as StartAs did,
        /// then Chars.Prepare, then a check in with the site for every id this
        /// install could pick, then Play().
        /// </summary>
        static void StartPlay()
        {
            // Before anything else, including Discord: a shared Skyrim is not
            // an install this supports any more. OwnGameRequired says why and
            // offers the folder when it can be made. See ShellOwnGame.cs.
            if (!OwnGameRequired()) return;

            // Discord decides who gets in, and it is asked here rather than
            // inside Play() because Play() is also the path a game already
            // running comes back through. Asked off the UI thread: the site can
            // take up to fifteen seconds to answer on a bad connection and a
            // frozen launcher looks like a crash.
            if (!Door.RecentlyCleared)
            {
                if (doorCheckOut) { Log("Still asking Discord. One moment."); return; }
                doorCheckOut = true;
                btnPlay.IsEnabled = false;
                Door.Check(win, Log,
                    delegate (Standing st)
                    {
                        // Whatever it said, do not hold on to it. A refusal for
                        // a missing role is the one answer most likely to be
                        // wrong thirty seconds later, because somebody is
                        // usually giving them the role while they read it.
                        Door.Forget();
                        Door.Explain(win, st, delegate { ShowPage(PagePlay); });
                    },
                    // Cleared before the start, because this goes straight back
                    // into StartPlay and the whole launch runs inside that call.
                    // Door holds the yes for a few minutes, so the second pass
                    // takes the path below rather than sending another check.
                    delegate { doorCheckOut = false; StartPlay(); },
                    delegate
                    {
                        doorCheckOut = false;
                        btnPlay.IsEnabled = true;
                        RefreshDiscord();
                        DrawStatus();
                        DrawDevBuild();
                    });
                return;
            }

            // A Skyrim somebody started by hand after the launcher opened is
            // not 'playing' to this window, and Prepare below rewrites the
            // client settings, which SkyrimPlatform answers with a reload of
            // every plugin in the running game. So a running game goes the
            // way a running game always went, through Play() and its own
            // checks, and nothing under Data is touched first.
            if (Checks.GameRunning()) { Play(); return; }

            // The save folder, the client settings, the menu's character list
            // and voice. Off the window's thread under the wait cursor, because
            // it asks the server for the roster on the way and that is up to
            // two and a half seconds of nothing drawing otherwise. A throw
            // here is the settings file or the list refusing to be written,
            // and the game is not started on either.
            string saveNote = null;
            try
            {
                Waiting(delegate { saveNote = Chars.Prepare(cfg); });
            }
            catch (Exception ex) { Log(ex.Message); return; }
            if (saveNote != null) Log(saveNote);

            // The Discord check above went out carrying the id the settings
            // file held, which is one of several now. Check in again for every
            // id this install could pick at the menu, characters and spare,
            // so the site's allowed list carries them all before anybody logs
            // in: the site keeps the ids against the account and the game
            // server's door reads that list. In the background, and a failure
            // is a line in the log and nothing more; the game still starts.
            List<int> ids = Chars.KnownIds();
            ThreadPool.QueueUserWorkItem(delegate
            {
                // Stop at the first id the site could not be reached for.
                // It is reachable for all of them or for none, so carrying on
                // only repeats one sentence once per character.
                foreach (int id in ids) { if (!CheckIn(id)) break; }
            });

            chosenId = 0;
            Log("Starting. You pick your character at the game's main menu.");
            Play();
        }

        /// <summary>
        /// One check in with the site for one id, from a pool thread. What
        /// went wrong goes to the log; nothing here stops anything.
        ///
        /// False means the site could not be reached at all, which is true of
        /// every id or none of them, so a caller working through a list stops
        /// rather than saying the same thing once per character.
        /// </summary>
        static bool CheckIn(int id)
        {
            try
            {
                Standing st = Discord.Join(id);
                // PresenceLog and not Log, and the difference is the whole bug.
                //
                // This runs on a pool thread. Log writes txtStatus.Text
                // straight, which is a WPF object, so off the window's thread
                // it throws "The calling thread cannot access this object
                // because a different thread owns it". PresenceLog is the same
                // line put through win.Dispatcher, which is why the other two
                // calls below use it.
                //
                // WHAT A PLAYTESTER SAW, 21 September: the throw landed in the
                // catch below, and the catch reports with PresenceLog, which
                // works. So the status bar read "Could not check profile
                // 1893288986 in with thornswood.net: The calling thread cannot
                // access this object because a different thread owns it" on a
                // check in that had SUCCEEDED. st.Ok was true and the site had
                // said yes. The launcher was telling somebody it had failed to
                // do the thing it had just done.
                if (st.Ok) { PresenceLog("checked character " + id + " in with thornswood.net"); return true; }

                // The site not answering is not the site saying no, and it
                // used to be reported as though it were.
                //
                // Discord.Join returns why "offline" when PostJson gets
                // nothing back at all. Run through the prefix below that came
                // out as "Could not check profile 1893288986 in with
                // thornswood.net: Could not reach thornswood.net to check you
                // in.", which names the site twice, reads like a refusal, and
                // was read as one by a tester on 21 September. It is neither:
                // checking in is done off the window's thread precisely so a
                // site that is down changes nothing, and the game starts
                // either way. Say that, once, and let the caller stop.
                if (st.Why == "offline")
                {
                    PresenceLog("thornswood.net is not answering, so your characters were not " +
                                "checked in. The game still starts.");
                    return false;
                }

                string why = st.Message != null && st.Message.Length > 0 ? st.Message : st.Why;
                PresenceLog("Could not check profile " + id + " in with thornswood.net: " + why);
            }
            catch (Exception ex)
            {
                PresenceLog("Could not check profile " + id + " in with thornswood.net: " + ex.Message);
            }
            return true;
        }

        /// <summary>
        /// Who the person picked at the game's menu, while the game runs.
        ///
        /// The plugin writes Data\Platform\thornswood-choice.txt when they
        /// pick, and the two second tick reads it. Each new id is written down
        /// (Chars.Chose), voice and the site are told, and the id is kept for
        /// the play time count at close. The settings file is never touched
        /// here: a write to it hot reloads every plugin under the running game.
        /// </summary>
        static readonly HashSet<int> forgotten = new HashSet<int>();

        static void PollChoice()
        {
            // The delete icon at the menu. Each id once, whatever the file says
            // on later ticks; the file itself goes at the next Prepare.
            List<int> gone = null;
            try { gone = Chars.ReadForgets(); } catch { gone = null; }
            if (gone != null)
            {
                foreach (int g in gone)
                {
                    if (!forgotten.Add(g)) continue;
                    try { Chars.Forget(g); Log("forgot character " + g + " at the menu"); }
                    catch (Exception ex) { Log("Could not forget character " + g + ": " + ex.Message); }
                }
            }

            int id = 0;
            try { id = Chars.ReadChoice(); } catch { id = 0; }
            if (id <= 0 || id == chosenId) return;
            chosenId = id;
            try { Chars.Chose(id); }
            catch (Exception ex) { Log("Could not write that choice down: " + ex.Message); }
            Log("chose character " + id);
            ThreadPool.QueueUserWorkItem(delegate
            {
                try { Voice.Reconfigure(id); } catch { }
                CheckIn(id);
            });
        }

        // The address, port and password sit behind one toggle. Hidden is the
        // resting state because these boxes are the only place the address is
        // still written down, and a launcher is a thing people screen share.
        // Hidden also means read only, so nothing can be edited blind.
        static bool serverShown = false;

        static string Dots(string s)
        {
            if (string.IsNullOrEmpty(s)) return "";
            return new string('\u2022', Math.Min(s.Length, 18));
        }

        static void PaintServerBoxes()
        {
            if (boxAddress == null) return;
            boxAddress.Text  = serverShown ? cfg.ServerAddress  : Dots(cfg.ServerAddress);
            boxPort.Text     = serverShown ? cfg.ServerPort     : Dots(cfg.ServerPort);

            boxAddress.IsReadOnly  = !serverShown;
            boxPort.IsReadOnly     = !serverShown;

            if (btnShowServer != null) btnShowServer.Content = serverShown ? "Hide" : "Show";
            if (btnSaveServer != null) btnSaveServer.IsEnabled = serverShown;
        }

        /// <summary>
        /// Put the client runtime back, if it is not the recorded build.
        ///
        /// THE ROW PROMISED THIS AND NOTHING DID IT. 1.1.82 shipped the check
        /// and the repair and never called the repair from anywhere, so the
        /// Client row said "the launcher will fetch it" and the launcher did
        /// not. Patrick, 22 September: "clicking scan and fix shows green and
        /// than recheck does nothing". Recheck did exactly nothing, because
        /// nothing was wired to it.
        ///
        /// Off the UI thread on purpose: this hashes six files, one of which
        /// is 15 MB, and may download a pack. Every line it produces goes to
        /// the log through the dispatcher, and the rows are redrawn at the end
        /// only when something actually changed.
        /// </summary>
        static bool healing;
        static void HealClientBackground()
        {
            if (healing) return;
            if (ClientRuntime.Recorded().Count == 0) return;
            if (ClientRuntime.Good()) return;
            healing = true;
            ThreadPool.QueueUserWorkItem(delegate
            {
                int n = 0;
                try
                {
                    n = ClientRuntime.Heal(cfg, delegate(string m)
                    {
                        string line = m;
                        win.Dispatcher.BeginInvoke(new Action(delegate { Log(line); }));
                    });
                }
                catch (Exception ex)
                {
                    string why = ex.Message;
                    win.Dispatcher.BeginInvoke(new Action(delegate
                    {
                        Log("Could not put the client runtime back: " + why);
                    }));
                }
                finally
                {
                    healing = false;
                    if (n > 0) win.Dispatcher.BeginInvoke(new Action(delegate { DrawStatus(); }));
                }
            });
        }

        static void CheckUpdatesBackground(bool loud)
        {
            try
            {
                VersionDoc v = Updater.Check(cfg);
                if (v == null) { win.Dispatcher.BeginInvoke(new Action(delegate { CheckFailed("the update source had nothing to say"); })); return; }
                win.Dispatcher.BeginInvoke(new Action(delegate { OnVersionDoc(v, loud); }));
            }
            catch (Exception ex)
            {
                string why = ex.Message;
                win.Dispatcher.BeginInvoke(new Action(delegate { CheckFailed(why); }));
            }
        }

        /// <summary>
        /// The source did not answer, so it is not known whether this build is
        /// current, and Play stays shut with the reason on the button. One
        /// retry is queued at a time, thirty seconds out.
        /// </summary>
        static void CheckFailed(string why)
        {
            checkFailed = true;
            updatePending = true;
            updateAnswered = true;
            Log("Could not check for updates: " + why + ". Play stays shut until the update source answers; trying again in 30 seconds.");
            DrawStatus();
            if (retryQueued) return;
            retryQueued = true;
            ThreadPool.QueueUserWorkItem(delegate
            {
                Thread.Sleep(30000);
                retryQueued = false;
                CheckUpdatesBackground(false);
            });
        }

        /// <summary>
        /// Let Play through when nothing is able to say whether it should.
        /// Never called on a check that answered; only when there was no
        /// answer to be had.
        /// </summary>
        static void Unblock(string why)
        {
            if (updateAnswered) return;
            updateAnswered = true;
            updatePending = false;
            Log("Playing on launcher " + Updater.Version + ", " + why + ".");
            DrawStatus();
        }

        /// <summary>
        /// The feed's message in the bar above Play, and the hold on Play when
        /// the feed asks for one. Entry 262: until this the message was one
        /// Log line that scrolled away, so there was no way to say anything to
        /// everybody when something outside the build broke.
        ///
        /// Only ever called with a document that was read, which is what keeps
        /// the hold from coming out of a failed check. Every call replaces the
        /// last answer, so a feed that drops the message or the maintenance
        /// flag takes the bar and the hold away with it. DrawStatus, which
        /// every path through OnVersionDoc reaches, puts the button right.
        /// </summary>
        static void ShowNotice(VersionDoc v)
        {
            FeedNotice was = feedNotice;
            feedNotice = FeedNotice.From(v, Updater.Version);
            if (noticeBar != null)
            {
                noticeBar.Visibility = feedNotice.Title == null ? Visibility.Collapsed : Visibility.Visible;
                noticeBar.BorderBrush = Res(feedNotice.Hold != null ? "Bad" : "Accent");
            }
            if (txtNoticeTitle != null) txtNoticeTitle.Text = feedNotice.Title == null ? "" : feedNotice.Title;
            if (txtNoticeNote != null) txtNoticeNote.Text = feedNotice.Text;

            // Once in the log when it changes, so a report still shows what the
            // bar said, without a line on every check.
            if (feedNotice.Title != null && (feedNotice.Title != was.Title || feedNotice.Text != was.Text))
                Log(feedNotice.Title + ". " + feedNotice.Text);
            if (was.Hold != null && feedNotice.Hold == null)
                Log("The update feed no longer holds Play.");
        }

        static void OnVersionDoc(VersionDoc v, bool loud)
        {
            checkFailed = false;
            pendingDoc = v;
            bool install = installWhenSeen;
            installWhenSeen = false;

            bool moved = false;
            if (!string.IsNullOrEmpty(v.serverAddress) && v.serverAddress != cfg.ServerAddress) { cfg.ServerAddress = v.serverAddress; moved = true; }
            if (!string.IsNullOrEmpty(v.collectionUrl) && v.collectionUrl != cfg.CollectionUrl) { cfg.CollectionUrl = v.collectionUrl; moved = true; }
            if (!string.IsNullOrEmpty(v.serverPort) && v.serverPort != cfg.ServerPort) { cfg.ServerPort = v.serverPort; moved = true; }
            if (v.maxOnline > 0 && v.maxOnline != cfg.MaxOnline) { cfg.MaxOnline = v.maxOnline; moved = true; }
            if (moved)
            {
                cfg.Save(Paths.CfgFile);
                PaintServerBoxes();
                Log("The server moved. The launcher already has the new address.");
                StartPing();
            }

            // Which collection revision this release agrees with. Not a
            // setting and never written to config.json: it is a fact about the
            // server that belongs to the feed it came from, and a stale copy
            // outliving its release is exactly the failure this replaced.
            Updater.FeedCollectionRevision = v.collectionRevision;

            // Quietly, and without a line in the log. Nobody set these and
            // nobody needs telling they changed.
            bool quiet = false;
            if (!string.IsNullOrEmpty(v.voicePort) && v.voicePort != cfg.VoicePort)
            {
                cfg.VoicePort = v.voicePort; quiet = true;
            }
            if (!string.IsNullOrEmpty(v.updateRepo) && v.updateRepo != cfg.UpdateRepo)
            {
                cfg.UpdateRepo = v.updateRepo; quiet = true;
            }
            // The Discord presence card's application, the site its buttons
            // point at, and the picture on it.
            if (!string.IsNullOrEmpty(v.discordAppId) && v.discordAppId != cfg.DiscordAppId) { cfg.DiscordAppId = v.discordAppId; quiet = true; }
            if (!string.IsNullOrEmpty(v.siteUrl) && v.siteUrl != cfg.SiteUrl) { cfg.SiteUrl = v.siteUrl; quiet = true; }
            // Not IsNullOrEmpty, deliberately. An empty voiceUrl in the feed is
            // an instruction to stop using the proxy and go back to the raw
            // port, and that is the only way back once everybody has been
            // pointed at Caddy. Null means the feed did not mention it.
            if (v.voiceUrl != null && v.voiceUrl != cfg.VoiceUrl) { cfg.VoiceUrl = v.voiceUrl; quiet = true; }
            if (!string.IsNullOrEmpty(v.presenceImage) && v.presenceImage != cfg.PresenceImage) { cfg.PresenceImage = v.presenceImage; quiet = true; }
            if (quiet)
            {
                cfg.Save(Paths.CfgFile);
                if (txtUpdateSource != null) txtUpdateSource.Text = Updater.WhyDisabled(cfg);
                DrawVoiceState();
            }
            ShowNotice(v);
            BuildNews();

            // The add-ons tab is drawn straight from this document, so redraw
            // it if somebody is sitting on that tab while the check lands.
            if (modTab == 3) BuildModList();

            // Packs a launcher before 1.1.32 marked as applied on a collection
            // install without writing a single game file. Back into the queue
            // they go, and this time they land. See Updater.Requeue.
            int again = Updater.Requeue();
            if (again > 0)
                Log(again + (again == 1 ? " earlier update" : " earlier updates") +
                    " never reached the game folder on this install, a launcher fault fixed in " +
                    Updater.Version + ". " + (again == 1 ? "It goes" : "They go") +
                    " in again with this update.");
            pendingPacks = Updater.Pending(v);
            bool newLauncher = Updater.IsNewer(v.launcherVersion, Updater.Version)
                               && !string.IsNullOrEmpty(v.launcherUrl);

            // Before a word is said about updates. An update into a build with
            // no mods in it cannot work, and reporting that it failed when the
            // cause is an uninstalled collection sends somebody looking for a
            // problem that is not there.
            if (ModsMissing())
            {
                if (!newLauncher)
                {
                    updatePending = false;
                    updateAnswered = true;
                    if (Downgrade.Needed(cfg))
                    {
                        DrawStatus();
                        Log("The collection is not installed yet and Skyrim is on the wrong build. The downgrade comes first; the collection card follows it. Updates wait until both are done.");
                        return;
                    }
                    ShowCollectionBar();
                    DrawStatus();
                    Log("The collection is not installed yet. Updates wait until it is.");
                    return;
                }
                // The launcher itself needs no mods to update. Holding it back
                // with the packs left a machine whose Vortex was on another
                // server's profile stuck on an old launcher for good, and the
                // fix for that (this line) could never reach it. The packs
                // still wait; the exe goes ahead.
                pendingPacks = new List<Pack>();
                collectionBarUp = false;
                Log("The collection is not installed yet. The mod updates wait until it is; the launcher update goes ahead.");
            }
            else
            {
                collectionBarUp = false;
            }
            btnInstallNow.Content = "Install now";

            if (pendingPacks.Count == 0 && !newLauncher)
            {
                updateBar.Visibility = Visibility.Collapsed;
                btnInstallNow.Visibility = Visibility.Collapsed;
                updatePending = false;
                updateAnswered = true;
                DrawStatus();
                if (loud || !moved) Log("Up to date.");
                return;
            }
            updatePending = true;
            updateAnswered = true;
            DrawStatus();

            selfUpdateOffered = newLauncher;
            var parts = new List<string>();
            if (newLauncher) parts.Add("launcher " + v.launcherVersion);
            if (pendingPacks.Count > 0) parts.Add(pendingPacks.Count + (pendingPacks.Count == 1 ? " mod update" : " mod updates"));
            txtUpdateTitle.Text = "Update available";
            string note = string.Join(", ", parts.ToArray());
            if (pendingPacks.Count > 0 && !string.IsNullOrEmpty(pendingPacks[0].notes))
                note += "  ·  " + pendingPacks[0].notes;
            txtUpdateNote.Text = note;
            updateBar.Visibility = Visibility.Visible;
            btnInstallNow.Visibility = Visibility.Visible;
            Log("Update available. Install it from the card above the Play button, or in Settings.");

            // The game was just closed for this. With automatic updates on it
            // goes in now, so the person is back in the world in a minute
            // rather than looking at a card.
            if (install && cfg.AutoUpdate)
            {
                Log("Installing it now.");
                RunUpdate();
            }
        }

        /// <summary>
        /// The update check that runs while the game is up. It only decides
        /// whether an update exists; the cards, the addresses and the rest of
        /// what a version document brings wait for OnVersionDoc, after the
        /// game is gone. First sight starts a five minute clock and says so in
        /// the log; when it runs out the game is closed and the tick's closed
        /// path takes it from there.
        /// </summary>
        static void CheckUpdatesInPlay()
        {
            if (checkingInPlay || !Updater.Enabled(cfg)) return;
            checkingInPlay = true;
            ThreadPool.QueueUserWorkItem(delegate
            {
                bool due = false;
                // A check that could not be made is not a check that said no.
                // GitHub answers 403 once the hour's requests are spent, and a
                // thrown check landed below looking exactly like "no update",
                // so it wiped the five minute clock every two minutes and the
                // countdown the server was already running never ran out on
                // this machine. True until a document actually comes back.
                bool failed = true;
                string what = "";
                try
                {
                    VersionDoc v = Updater.Check(cfg);
                    if (v != null)
                    {
                        failed = false;
                        List<Pack> packs = Updater.Pending(v);
                        bool newLauncher = Updater.IsNewer(v.launcherVersion, Updater.Version)
                                           && !string.IsNullOrEmpty(v.launcherUrl);
                        due = packs.Count > 0 || newLauncher;
                        var parts = new List<string>();
                        if (newLauncher) parts.Add("launcher " + v.launcherVersion);
                        if (packs.Count > 0) parts.Add(packs.Count + (packs.Count == 1 ? " mod update" : " mod updates"));
                        what = string.Join(", ", parts.ToArray());
                    }
                }
                catch { }
                try
                {
                    win.Dispatcher.BeginInvoke(new Action(delegate
                    {
                        checkingInPlay = false;
                        // Leave the clock alone when there was no answer. Only
                        // a check that came back and found nothing clears it.
                        if (failed) return;
                        if (!playing || !due) { updateSeenAt = DateTime.MinValue; return; }
                        if (updateSeenAt == DateTime.MinValue)
                        {
                            updateSeenAt = DateTime.Now;
                            Log("An update went out while you were playing (" + what + "). The server is telling everybody the same. When its countdown ends, in about four and a half minutes, the game closes so the launcher can install it.");
                            return;
                        }
                        // Ship tells the server five minutes right after the
                        // pack goes out, and the pack is seen within thirty
                        // seconds of that, so four and a half minutes from
                        // first sight is the server's zero, give or take the
                        // poll. Nobody is left in a world the room has moved
                        // past: the server says out, and the game goes.
                        if ((DateTime.Now - updateSeenAt).TotalMinutes < 4.5) return;
                        if (!Checks.GameRunning()) return;
                        closedForUpdate = true;
                        Log("Closing the game for the update (" + what + ").");
                        bool still = false;
                        Waiting(delegate { Checks.CloseGame(); still = Checks.GameRunning(); });
                        if (still)
                        {
                            closedForUpdate = false;
                            Log("Skyrim would not close. Quit it yourself and the update goes in.");
                        }
                    }));
                }
                catch { checkingInPlay = false; }
            });
        }

        /// <summary>
        /// Whether the card above Play should be the collection card, and if
        /// so which thing is wrong.
        ///
        /// Returns "none" for never installed, which is no more than
        /// Checks.MostPluginsWithoutCollection plugins enabled; "stale" when
        /// the revision Vortex installed is behind the one the server was
        /// built against; "ahead" when it is in front of it. Otherwise "",
        /// which includes having no collection address and either revision
        /// reading as 0.
        ///
        /// Two tests because a plugin count alone only catches somebody who
        /// has never installed the collection. An older revision still
        /// deploys a full list of plugins and looks perfect by that measure,
        /// so behind and ahead come from the revision numbers.
        ///
        /// ModsMissing is this answering anything but "", and while it does
        /// the mod updates wait. An update cannot succeed against a build
        /// with no mods in it, and the bar above Play used to say "Update
        /// failed" over the top of the one message somebody in that state
        /// actually needs.
        /// </summary>
        static string CollectionProblem()
        {
            if (string.IsNullOrEmpty(cfg.CollectionUrl)) return "";
            try
            {
                if (Checks.EnabledPlugins() <= Checks.MostPluginsWithoutCollection) return "none";

                // THE REVISION, NOT A NAMED FILE.
                //
                // This used to ask whether po3_StartOnSave.dll was present and
                // call the collection stale when it was not. That was wrong in
                // both directions, and on 22 September it was wrong on
                // Patrick's own machine in the quietest possible way.
                //
                // The file is not in the collection and never has been:
                // Add-Characters.ps1 puts it into a build by hand. So anybody
                // who installed the collection correctly and never ran that
                // script read as behind, and Patrick, who had run it, read as
                // fine while sitting two revisions behind the collection he
                // publishes. Nothing on screen said a word.
                //
                // Vortex names the collection's own mod folder with the
                // revision, so there is a number to compare, and the feed
                // carries the revision the SERVER was built against. Behind
                // and ahead are different problems and get different words:
                // behind means update, ahead means the server has not caught
                // up with you yet and Play will refuse you on the load order.
                int mine = Checks.CollectionRevision(cfg);
                int wants = Updater.FeedCollectionRevision;
                if (mine > 0 && wants > 0)
                {
                    if (mine < wants) return "stale";
                    if (mine > wants) return "ahead";
                }
            }
            catch { return ""; }
            return "";
        }

        static bool ModsMissing()
        {
            return CollectionProblem().Length > 0;
        }

        static bool collectionBarUp = false;

        /// <summary>
        /// Turns the bar above Play into the one thing worth doing first. Same
        /// bar, same button, different job, because a second card underneath a
        /// louder one is a card nobody reads.
        /// </summary>
        static void ShowCollectionBar()
        {
            string problem = CollectionProblem();
            bool stale = problem == "stale";

            if (stale)
            {
                int mine = Checks.CollectionRevision(cfg);
                int wants = Updater.FeedCollectionRevision;
                txtUpdateTitle.Text = "Your mods need updating";
                txtUpdateNote.Text =
                    "The collection is on revision " + wants + " and this copy is on " + mine +
                    ", so part of what the server expects is not installed. Open it and let " +
                    "Vortex bring it up to date. It is one button there and it takes the lot " +
                    "in one go.";
            }
            else if (problem == "ahead")
            {
                // The other direction, which nothing used to say at all. The
                // person has done everything right and is further forward than
                // the server; Play will still refuse them, on the load order,
                // and without this that reads as their fault.
                int mine = Checks.CollectionRevision(cfg);
                int wants = Updater.FeedCollectionRevision;
                txtUpdateTitle.Text = "The server has not caught up with you";
                txtUpdateNote.Text =
                    "You are on collection revision " + mine + " and the server was built " +
                    "against revision " + wants + ". Nothing is wrong with your install. Play " +
                    "will refuse you over the load order until the server is rebuilt, which is " +
                    "ours to do, so say so in the Discord if nobody has.";
            }
            else
            {
                txtUpdateTitle.Text = "Your mods are not installed yet";
                txtUpdateNote.Text =
                    "Thornswood's mods are a collection on Nexus, and Vortex installs them into a " +
                    "profile of its own, so the Skyrim you already play is left alone. Nothing else " +
                    "here comes right until that is done, updates included.";
            }
            updateBar.Visibility = Visibility.Visible;
            btnInstallNow.Visibility = Visibility.Visible;
            collectionBarUp = true;

            if (Discord.Linked)
            {
                btnInstallNow.Content = "Open the collection";
                btnInstallNow.IsEnabled = true;
            }
            else
            {
                // It used to read "Apply first" and be dead. That is a card
                // telling somebody to do a thing, with the button that does the
                // thing switched off, and the only other way to it greyed out
                // underneath by a bug. Somebody who has been accepted and has
                // simply not linked yet had nowhere to go from this screen.
                //
                // The gate has not moved: the collection still only opens once
                // Discord is linked and the site says yes. The button is just
                // the next step now instead of a wall.
                btnInstallNow.Content = "Connect Discord";
                btnInstallNow.IsEnabled = !linkingDiscord;
                txtUpdateNote.Text = txtUpdateNote.Text +
                    "  Connect Discord first and this opens the collection.";
            }
        }

        static void RunUpdate()
        {
            if (playing) { Log("Quit the game first."); return; }
            if (ownGameBusy) { Log("Thornswood's own Skyrim folder is still being prepared. The update can go in when that is done."); return; }
            // An update writes into the build. A game still holding files open
            // down there turns that into a half written install.
            if (!ClearStuckGame(true)) return;
            btnUpdate.IsEnabled = false;
            btnInstallNow.IsEnabled = false;
            btnPlay.IsEnabled = false;
            txtUpdateTitle.Text = "Updating";
            var doc = pendingDoc;
            var packs = pendingPacks;

            ThreadPool.QueueUserWorkItem(delegate
            {
                Action<string> log = delegate(string m)
                {
                    win.Dispatcher.BeginInvoke(new Action(delegate { Log(m); }));
                };
                try
                {
                    // A pack published with no url is unusable and always will
                    // be: there is nothing at the other end to download. It is
                    // not a network problem and retrying never clears it, so
                    // stopping the whole update on it means the Play button
                    // stays off forever, for everyone, including whoever would
                    // have to publish the fix. Skip it, say so, and let the
                    // packs that do have somewhere to download from go in.
                    int dead = 0;
                    foreach (Pack p in packs)
                    {
                        if (p == null) continue;
                        if (string.IsNullOrEmpty(p.url) || p.url.Trim().Length == 0)
                        {
                            dead++;
                            log("Skipping " + p.id + ": it was published without a download link, so there is nothing to fetch. It will not be offered again.");
                            Updater.Skip(p.id);
                            continue;
                        }
                        Updater.ApplyPack(cfg, p, log);
                    }
                    if (dead > 0)
                        log(dead + " update" + (dead == 1 ? " was" : "s were") + " published without a download link and had to be skipped. Whatever was in " + (dead == 1 ? "it" : "them") + " comes back in the next one.");

                    if (selfUpdateOffered)
                    {
                        log("Updating the launcher. It will restart.");
                        Updater.SelfUpdate(cfg, doc, log);
                        win.Dispatcher.BeginInvoke(new Action(delegate { win.Close(); }));
                        return;
                    }

                    win.Dispatcher.BeginInvoke(new Action(delegate
                    {
                        updateBar.Visibility = Visibility.Collapsed;
                        btnInstallNow.Visibility = Visibility.Collapsed;
                        Stats.LastUpdate = DateTime.Now.ToString("d MMM HH:mm");
                        Stats.Save();
                        BuildStatRow();
                        btnUpdate.IsEnabled = true;
                        updatePending = false;
                        DrawStatus(); BuildModList();
                        Log("Update finished.");
                    }));
                }
                catch (Exception ex)
                {
                    win.Dispatcher.BeginInvoke(new Action(delegate
                    {
                        Log("Update failed: " + ex.Message);
                        // Everything before the pack that broke is in. Without
                        // this the card still counts them and pressing Update
                        // again unpacks them a second time, which rewrites each
                        // one's file list with every path marked as one the pack
                        // wrote over, so a later Remove leaves its own files.
                        pendingPacks = Updater.Pending(doc);
                        txtUpdateTitle.Text = "Update failed";
                        btnUpdate.IsEnabled = true;
                        btnInstallNow.IsEnabled = true;
                        DrawStatus();
                        Log("Play stays off until the update goes through, because the server is expecting the newer mod list.");
                    }));
                }
            });
        }

    }
}
