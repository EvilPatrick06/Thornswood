using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.NetworkInformation;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
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
    /// launcher\app\ARCHITECTURE.md walks through it: the startup order, what
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
        static bool playing;
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
        static DateTime playStartedAt;
        // When the last session's game closed, for PlayPressedBy (#2215).
        static DateTime gameClosedAt;
        // The last key that went down on this window, for PlayPressedBy.
        static Key lastKeyDown = Key.None;
        static DateTime lastKeyDownAt;

        // An update published while the game runs. The check that runs every
        // thirty seconds during play notices it; four and a half minutes after it is first
        // seen the game is closed so the launcher can install it, which is
        // what the server's own five minute warning has been counting down
        // to. The server's kick by itself did nothing: the client reconnects
        // in three seconds and carries on running files the rest of the room
        // has moved past, which is what happened to everybody on 1.1.40.
        static DateTime updateSeenAt = DateTime.MinValue;
        static bool closedForUpdate = false;
        static bool installWhenSeen = false;
        static int inPlayTicks = 0;
        static int modTab;   // 0 server plugins, 1 script extender, 2 your own, 3 add-ons
        static Border addonsCard;
        static DispatcherTimer timer;

        // The character bar (charBar, charRow, txtCharNote, charPickerOpen)
        // went on 20 September; the person picks at the game's main menu.
        // This is who they picked, read out of the plugin's choice file while
        // the game runs, and 0 until they have.
        static int chosenId;

        static TextBlock txtServer, txtPing, txtStatus, txtStatusRight, txtVersion, txtBuildLine,
                         txtUpdateTitle, txtUpdateNote, txtModCount, txtUpdateSource,
                         txtPageTitle, txtHeroLine, txtVerifyTitle, txtVerifyNote,
                         txtSaveNote, txtSaveCount, txtLogCount, txtDisplayNote,
                         txtReadyTitle, txtReadyNote;
        static Ellipse dotServer, dotVerify, dotReady;
        static StackPanel statusList, modList, themeRow, themeEditor, pathRows, helpList,
                          saveList, logList, displayModeRow,
                          firstRunCard, quickKeysCard, quickKeys;
        // Play hero stats strip: three equal columns (Played / Sessions / Last played).
        static UniformGrid statRow;
        // GalleryCard is a Grid that fills the Play centre; only Visibility is touched.
        static FrameworkElement galleryCard;
        static Image galleryImage; static TextBlock galleryBy;
        // The pictures /api/public is showing and where the card is in turning
        // through them. Null until the feed has answered with at least one.
        static List<Gallery.Shot> galleryShots;
        static int galleryAt = -1;
        static DispatcherTimer galleryTimer;
        // Gallery page tools (#731). Play keeps the rotating spotlight only.
        // galleryWho is what /api/gallery/who answered at start up, null until
        // it has; galleryReporting is the picture an open report on the Gallery
        // page is about.
        static Gallery.Who galleryWho;
        static Gallery.Shot galleryReporting;
        static List<string> galleryChosenPaths = new List<string>();
        static Button btnGalleryChoose, btnGallerySend, btnGalleryRefresh,
                      btnGalleryReportSend, btnGalleryReportCancel;
        static TextBox boxGalleryBy, boxGalleryNote, boxGalleryWhy;
        static TextBlock txtGalleryChosen, txtGalleryPageSaid, txtGalleryDropLead,
                         txtGalleryApprovedEmpty;
        static FrameworkElement galleryPageReportRow;
        static Border galleryDrop;
        static StackPanel galleryChosenList;
        static WrapPanel galleryApprovedList;
        static List<Gallery.Pending> galleryPending;
        static TextBox boxSearch, boxAddress, boxPort, boxResolution, boxFrameLimit, boxFov;
        static CheckBox chkAutoUpdate, chkVSync, chkKeepOpen, chkLockRes;
        static CheckBox chkCrashSnapshots; static TextBlock txtCrashFolder; static Button btnCrashFolder;
        static CheckBox chkMusic; static Slider sldMusic; static TextBlock txtMusic;
        static StackPanel chatFadeRow; static TextBlock txtChatFadeNote; static CheckBox chkNeedsBars;
        static CheckBox chkKeepSaves;
        static CheckBox chkDeleteMods;
        static Button btnVoiceTest;
        static TextBlock txtVoiceState;
        static Button btnUninstall, btnServerStart, btnServerStop;
        static Button btnServerMain, btnServerDev, btnServerPick, btnCheckDiagnostics;
        static Popup serverPickPopup;
        static Border serverPickPanel;
        static TextBlock txtBrandSmall, txtBrandBig, txtServerPick, txtServerPickMeta;
        static TextBlock txtServerMainMeta, txtServerDevMeta;
        static Ellipse dotServerPick, dotServerMain, dotServerDev;
        static TextBlock txtServerState;
        static string pingMsText = "";
        static string awakeMineText = "";
        static string awakeOtherText = "";
        // Per-server chip lines for the dropdown (Main and Dev each once).
        static string pingMainText = "";
        static string pingDevText = "";
        static string awakeMainText = "";
        static string awakeDevText = "";
        static string dotMainKey = "Faint";
        static string dotDevKey = "Faint";
        static Border updateBar, mineCard;
        static Border downgradeBar;
        static TextBlock txtDowngradeNote, txtDowngradeTitle;
        static Button btnDowngrade;
        static ProgressBar prgDowngrade;
        // The feed's word to everybody and whether it holds Play (entry 262).
        // Empty until a document has actually been read, so nothing here can
        // hold Play on a check that failed. See FeedNotice.cs.
        static Border noticeBar;
        static TextBlock txtNoticeTitle, txtNoticeNote;
        static FeedNotice feedNotice = new FeedNotice();
        static Grid titleBar;
        static Button buttonDiscord;
        static TextBlock labelDiscord;
        static Ellipse discordAvatar;
        static Button btnPlay, btnCopy, btnUpdate, btnMin, btnMax, btnClose,
                      btnSaveServer, btnCheckNow, btnFolder, btnOpenLog,
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
            // PerMonitorV2 is in the application manifest (#463). Framework WPF
            // only rescales on WM_DPICHANGED when this switch is false; its
            // default depends on a TargetFrameworkAttribute we do not emit.
            // WPF reads it once and keeps the answer, so it is set here, before
            // any window, message box or XAML exists.
            AppContext.SetSwitch("Switch.System.Windows.DoNotScaleForDpiChanges", false);

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
                    catch (Exception ex) { Swallow.Note("Shell.Main", ex); }
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
                    catch (Exception logEx) { Swallow.Note("Shell.Main, append", logEx); }
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
            // Profile\accepted.json is the setup program's record of the terms,
            // the privacy policy and the rules (issue #1009). An install made
            // before that has no file, and silence is not a yes. Ask before
            // anything else is opened. Uninstall must still be reachable.
            bool termsOnFile = !Acceptance.NeedsAsk(Acceptance.Read(Paths.ProfileDir), null);
            if (!askedToUninstall && !termsOnFile && !Acceptance.Ensure(Paths.ProfileDir)) return;
            cfg = Config.Load(Paths.CfgFile);
            Stats.Load();
            Keep.BuildName = cfg.BuildName;
            Icons.BuildName = cfg.BuildName;
            Art.Dev = cfg.IsDev;
            Discord.Channel = cfg.Channel;

            string xaml;
            using (var s = Assembly.GetExecutingAssembly().GetManifestResourceStream("ui.xaml"))
            using (var r = new StreamReader(s))
                xaml = r.ReadToEnd();
            win = (Window)XamlReader.Parse(xaml);

            Bind();
            Themes.Apply(win, Themes.Resolve(cfg));
            Wire();
            BuildThemeRow();
            BuildThemeEditor();
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
            // Linked tickets from before the site sent avatar still need a hash.
            // Join answers with it; paint once it lands so the sidebar is not stuck on Clyde.
            PullDiscordAvatarIfNeeded();
            ShowPage(PagePlay);

            // And put Thornswood in Installed apps, or bring the entry up to
            // date. Done here rather than in the installer so that every
            // install that already exists gets one on its next launch.
            try { Register.Ensure(cfg); } catch (Exception ex) { Swallow.Note("Shell.Run", ex); }

            // So the session report can run the readiness checks against the
            // same config this launcher is using, without reaching in here.
            try { Discord.UseConfig(cfg); } catch (Exception ex) { Swallow.Note("Shell.Run", ex); }

            // Logs from a session that ended without sending them, sent now.
            // On a pool thread so nothing waits on the site, and BEFORE Play
            // can be pressed, because the game truncates its own logs under
            // Data\Platform at every game start and after that there is
            // nothing left to send. A crash that took the launcher down with
            // it is exactly the session somebody wants to read afterwards,
            // and it was the one that was always lost.
            try { ThreadPool.QueueUserWorkItem(delegate { try { Discord.SendPendingLogs(); } catch (Exception ex) { Swallow.Note("Shell.Run", ex); } }); } catch (Exception ex) { Swallow.Note("Shell.Run", ex); }

            // The client settings file, made here if this install has none.
            // Nothing ships it, the client does not create it, and without it
            // a character cannot be chosen. From startup, so the log says so
            // before Play or a character choice can trip over its absence.
            try { AutoJoin.Ensure(Log); } catch (Exception ex) { Swallow.Note("Shell.Run", ex); }

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
                try { holding = Hold.Take(PresenceLog); } catch (Exception ex) { Swallow.Note("Shell.Run, dispose", ex); }
                if (holding > 0) Log("Holding " + holding + " of " + cfg.BuildName + "'s game files again, so nothing else can change them under the running game.");
            }
            else
            {
                if (Swap.Restore()) Log("Cleaned up a redirect left behind by a crash.");
                Keep.TakeNote();
            }
            try { string leak = Leaks.Clean(cfg); if (leak != null) Log(leak); } catch (Exception ex) { Swallow.Note("Shell.Run", ex); }
            // Once the own folder is made, Thornswood's files come out of the Steam copy, once (OwnGameClean.cs, #1226). Off the window's thread: it deletes.
            ThreadPool.QueueUserWorkItem(delegate
            {
                string cleaned = null;
                try { cleaned = OwnGame.CleanSteamCopy(cfg); } catch (Exception ex) { Swallow.Note("Shell.Run, taking Thornswood's files out of the Steam copy", ex); }
                if (cleaned == null) return;
                try { win.Dispatcher.BeginInvoke((Action)delegate { Log(cleaned); }); } catch (Exception ex) { Swallow.Note("Shell.Run, saying what came out of the Steam copy", ex); }
            });
            try { string ini = ThornIni.Ensure(); if (ini != null) Log(ini); } catch (Exception ex) { Swallow.Note("Shell.Run", ex); }
            try { string fov = ThornIni.UndoShippedFov(); if (fov != null) Log(fov); } catch (Exception ex) { Swallow.Note("Shell.Run", ex); }
            // Steam's Updates setting for the Steam copy of Skyrim: logged, and set when it does not hold the version (ShellSteamUpdates.cs, #493), only until the own folder is made (#1226).
            try { if (SteamUpdates.LooksAtStart(!Paths.Collection, Downgrade.Needed(cfg))) HoldSteamUpdatesOnStart(); } catch (Exception ex) { Swallow.Note("Shell.Run, Steam's Updates setting", ex); }
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
            // move something. After a self-update the previous exe is still
            // sitting as .old; Ensure sees that and rewrites icons even when
            // the path string did not change, so blank desktop icons do not
            // stick until someone opens Settings.
            ThreadPool.QueueUserWorkItem(delegate
            {
                int moved = 0;
                try { moved = Icons.Ensure(); } catch (Exception ex) { Swallow.Note("Shell.Run", ex); }
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
            // Off the window's thread. Ending a stuck game waits on it, and at
            // this point the window has not even been shown yet.
            ThreadPool.QueueUserWorkItem(delegate
            {
                string said = null;
                try { said = ClearLeftovers(); } catch (Exception ex) { Swallow.Note("Shell.Run", ex); }
                if (string.IsNullOrEmpty(said)) return;
                try { win.Dispatcher.BeginInvoke((Action)delegate { Log(said); DrawStatus(); }); } catch (Exception ex) { Swallow.Note("Shell.Run", ex); }
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
                try { freed = Uninstall.DropScratch(null); } catch (Exception ex) { Swallow.Note("Shell.Run", ex); }
                if (freed <= 0) return;
                try
                {
                    win.Dispatcher.BeginInvoke((Action)delegate
                    {
                        Log("Cleared " + (freed / (1024 * 1024)) +
                            " MB the installer left behind on your drive.");
                    });
                }
                catch (Exception ex) { Swallow.Note("Shell.Run", ex); }
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
            StartGallery();
            // Always: config.json cannot switch the check off (#937), and Play
            // stays shut until it has answered (Updater.FeedUrl).
            ThreadPool.QueueUserWorkItem(delegate { CheckUpdatesBackground(false); });
            StartFeedWatch();

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
                new Action(delegate
                {
                    // PlaceLoader runs inside Voice.Start before CreateAsync.
                    // Menu music must not CreateAsync until that file exists;
                    // a separate ApplicationIdle item used to run first and
                    // fail with "Unable to load DLL WebView2Loader.dll".
                    Voice.Start(delegate (string m) { Log(m); }, cfg);
                    StartMenuMusic();
                }),
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
                    // Capture before Settle deletes .old. The early Icons.Ensure
                    // usually runs while .old is still there; if it raced after
                    // Settle, this second pass still forces the shortcut redraw.
                    bool afterUpdate = false;
                    try { afterUpdate = File.Exists(SelfSwap.OldOf(self)); } catch { /* path unreadable: skip the second icon pass */ }
                    string said = null;
                    try { said = SelfSwap.Settle(self); } catch (Exception ex) { Swallow.Note("Shell.Run, clearing the copy the self update kept", ex); }
                    if (afterUpdate)
                    {
                        int moved = 0;
                        try { moved = Icons.Ensure(true); } catch (Exception ex) { Swallow.Note("Shell.Run, refreshing shortcut icons after self update", ex); }
                        if (moved > 0)
                            try { win.Dispatcher.BeginInvoke((Action)delegate { Log("Shortcut icon brought up to date after the update."); }); } catch (Exception ex) { Swallow.Note("Shell.Run, saying shortcut icons were refreshed", ex); }
                    }
                    if (string.IsNullOrEmpty(said)) return;
                    try { win.Dispatcher.BeginInvoke((Action)delegate { Log(said); }); } catch (Exception ex) { Swallow.Note("Shell.Run, saying what the self update left", ex); }
                });
            };

            // Inside the screen at any display scale, before it is centred (#463).
            try { WindowFit.Keep(win); } catch (Exception ex) { Swallow.Note("Shell.Run, fitting the window to the screen", ex); }
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
            app.Exit += delegate { StopFeedWatch(); Voice.Stop(); try { Presence.Stop(); } catch (Exception ex) { Swallow.Note("Shell.Run, dispose", ex); } try { Hold.Release(); } catch (Exception ex) { Swallow.Note("Shell.Run, dispose", ex); } };

            // A fault on the launcher's own thread used to take the window
            // down with no line in the log, or leave it standing and deaf.
            // Now the fault is written down, stack and all, and the launcher
            // stays up. A button that failed once is better than no launcher,
            // and the log line is the only evidence anyone will have.
            app.DispatcherUnhandledException += delegate (object faultSender,
                System.Windows.Threading.DispatcherUnhandledExceptionEventArgs fault)
            {
                try { Log("Fault on the launcher's own thread: " + fault.Exception.GetType().Name + ": " + fault.Exception.Message); } catch (Exception ex) { Swallow.Note("Shell.Run", ex); }
                try { File.AppendAllText(Paths.LogFile, fault.Exception.ToString() + Environment.NewLine); } catch (Exception ex) { Swallow.Note("Shell.Run, append", ex); }
                // IL offsets let a pdb kept on the shipping machine map a
                // customer's report to a source line without shipping symbols
                // (issue #462). StackTrace(..., false) skips file/line lookup
                // so a missing pdb on the customer machine does not cost.
                try
                {
                    StackTrace st = new StackTrace(fault.Exception, false);
                    StringBuilder il = new StringBuilder();
                    il.AppendLine("IL offsets:");
                    for (int fi = 0; fi < st.FrameCount; fi++)
                    {
                        StackFrame fr = st.GetFrame(fi);
                        if (fr == null) continue;
                        MethodBase mb = fr.GetMethod();
                        string name = "?";
                        if (mb != null)
                        {
                            if (mb.DeclaringType != null)
                                name = mb.DeclaringType.FullName + "." + mb.Name;
                            else
                                name = mb.Name;
                        }
                        il.Append("  ");
                        il.Append(name);
                        il.Append(" IL_");
                        il.Append(fr.GetILOffset().ToString("x4"));
                        il.AppendLine();
                    }
                    File.AppendAllText(Paths.LogFile, il.ToString());
                }
                catch (Exception ilEx) { Swallow.Note("Shell.DispatcherUnhandledException, IL offsets", ilEx); }
                fault.Handled = true;
            };
            StartStallWatch();
            if (!askedToUninstall && termsOnFile)
            {
                // The record is already there (the setup program's, or the
                // first start's above). A page is asked again only when its
                // text has changed since it was accepted, and then only that
                // page: Patrick, 16 Oct 2026 (#2616), asked once at install,
                // and again "if any changes and only ask about the one that
                // does change". Off this thread so startup does not wait on
                // the site. Declining closes the launcher.
                ThreadPool.QueueUserWorkItem(delegate
                {
                    try
                    {
                        bool ok = Acceptance.Recheck(Paths.ProfileDir, delegate(bool[] which)
                        {
                            bool ticked = false;
                            win.Dispatcher.Invoke((Action)delegate { ticked = Acceptance.Ask(which); });
                            return ticked;
                        });
                        if (!ok)
                        {
                            try { win.Dispatcher.Invoke((Action)delegate { if (Application.Current != null) Application.Current.Shutdown(); }); }
                            catch (Exception ex) { Swallow.Note("Shell.Run, closing after a changed page was declined", ex); }
                        }
                    }
                    catch (Exception ex) { Swallow.Note("Shell.Run, terms recheck", ex); }
                });
            }
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
            catch (Exception ex) { Swallow.Note("Shell.CentreOnMainScreen", ex); }   // a bad monitor layout is not worth refusing to start over
        }

        static T F<T>(string name) where T : class { return win.FindName(name) as T; }

        /// <summary>How far a maximized window hangs past the screen: the sizing frame plus its padding, in WPF units.</summary>
        static Thickness MaximizedInset()
        {
            double scale = 1;
            try
            {
                PresentationSource src = PresentationSource.FromVisual(win);
                if (src != null && src.CompositionTarget != null) scale = src.CompositionTarget.TransformToDevice.M11;
            }
            catch (Exception ex) { Swallow.Note("Shell.MaximizedInset, reading the screen scale", ex); }
            if (scale <= 0) scale = 1;
            // At the scale of the monitor the window is on, not the one
            // Windows started with: they differ on a second monitor (#463).
            double px = 0;
            try { px = WindowFit.FramePixels(scale); }   // SM_CXSIZEFRAME + SM_CXPADDEDBORDER
            catch (Exception ex) { Swallow.Note("Shell.MaximizedInset, asking Windows for the frame size", ex); }
            if (px <= 0) px = 8;
            return new Thickness(px / scale);
        }

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
            logList = F<StackPanel>("LogList"); statRow = F<UniformGrid>("StatRow");
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
            chkCrashSnapshots = F<CheckBox>("ChkCrashSnapshots"); txtCrashFolder = F<TextBlock>("TxtCrashFolder");
            btnCrashFolder = F<Button>("BtnCrashFolder");
            chkMusic = F<CheckBox>("ChkMusic"); sldMusic = F<Slider>("SldMusic"); txtMusic = F<TextBlock>("TxtMusic");
            dotServer = F<Ellipse>("DotServer"); dotVerify = F<Ellipse>("DotVerify");
            dotReady = F<Ellipse>("DotReady");
            txtReadyTitle = F<TextBlock>("TxtReadyTitle"); txtReadyNote = F<TextBlock>("TxtReadyNote");
            mineCard = F<Border>("MineCard");
            statusList = F<StackPanel>("StatusList"); modList = F<StackPanel>("ModList");
            themeRow = F<StackPanel>("ThemeRow"); themeEditor = F<StackPanel>("ThemeEditor");
            pathRows = F<StackPanel>("PathRows");
            helpList = F<StackPanel>("HelpList");
            boxSearch = F<TextBox>("BoxSearch"); boxAddress = F<TextBox>("BoxAddress"); boxPort = F<TextBox>("BoxPort");
            btnShowServer = F<Button>("BtnShowServer");
            chkAutoUpdate = F<CheckBox>("ChkAutoUpdate");
            updateBar = F<Border>("UpdateBar"); titleBar = F<Grid>("TitleBar");
            downgradeBar = F<Border>("DowngradeBar"); txtDowngradeNote = F<TextBlock>("TxtDowngradeNote"); btnDowngrade = F<Button>("BtnDowngrade");
            prgDowngrade = F<ProgressBar>("PrgDowngrade");
            txtDowngradeTitle = F<TextBlock>("TxtDowngradeTitle");
            noticeBar = F<Border>("NoticeBar"); txtNoticeTitle = F<TextBlock>("TxtNoticeTitle"); txtNoticeNote = F<TextBlock>("TxtNoticeNote");

            btnPlay = F<Button>("BtnPlay"); btnCopy = F<Button>("BtnCopy");
            btnUpdate = F<Button>("BtnUpdate"); btnMin = F<Button>("BtnMin"); btnMax = F<Button>("BtnMax");
            btnClose = F<Button>("BtnClose"); btnSaveServer = F<Button>("BtnSaveServer");
            btnCheckNow = F<Button>("BtnCheckNow"); btnInstallNow = F<Button>("BtnInstallNow");
            btnFolder = F<Button>("BtnFolder");
            btnOpenLog = F<Button>("BtnOpenLog");
            btnRepair = F<Button>("BtnRepair"); btnRestore = F<Button>("BtnRestore");
            btnIcons = F<Button>("BtnIcons");
            btnServerMain = F<Button>("BtnServerMain"); btnServerDev = F<Button>("BtnServerDev");
            btnServerPick = F<Button>("BtnServerPick"); serverPickPopup = F<Popup>("ServerPickPopup");
            serverPickPanel = F<Border>("ServerPickPanel");
            txtServerPick = F<TextBlock>("TxtServerPick");
            txtServerPickMeta = F<TextBlock>("TxtServerPickMeta");
            txtServerMainMeta = F<TextBlock>("TxtServerMainMeta");
            txtServerDevMeta = F<TextBlock>("TxtServerDevMeta");
            dotServerPick = F<Ellipse>("DotServerPick");
            dotServerMain = F<Ellipse>("DotServerMain");
            dotServerDev = F<Ellipse>("DotServerDev");
            btnCheckDiagnostics = F<Button>("BtnCheckDiagnostics");
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
            galleryCard = F<FrameworkElement>("GalleryCard");
            galleryImage = F<Image>("GalleryImage");
            galleryBy = F<TextBlock>("GalleryBy");
            btnGalleryChoose = F<Button>("BtnGalleryChoose");
            btnGallerySend = F<Button>("BtnGallerySend");
            btnGalleryRefresh = F<Button>("BtnGalleryRefresh");
            btnGalleryReportSend = F<Button>("BtnGalleryReportSend");
            btnGalleryReportCancel = F<Button>("BtnGalleryReportCancel");
            boxGalleryBy = F<TextBox>("BoxGalleryBy");
            boxGalleryNote = F<TextBox>("BoxGalleryNote");
            boxGalleryWhy = F<TextBox>("BoxGalleryWhy");
            txtGalleryChosen = F<TextBlock>("TxtGalleryChosen");
            txtGalleryDropLead = F<TextBlock>("TxtGalleryDropLead");
            txtGalleryPageSaid = F<TextBlock>("TxtGalleryPageSaid");
            txtGalleryApprovedEmpty = F<TextBlock>("TxtGalleryApprovedEmpty");
            galleryPageReportRow = F<FrameworkElement>("GalleryPageReportRow");
            galleryDrop = F<Border>("GalleryDrop");
            galleryChosenList = F<StackPanel>("GalleryChosenList");
            galleryApprovedList = F<WrapPanel>("GalleryApprovedList");

            // Same order as the PageXxx constants above, and as PageTitles.
            // Gallery is appended at the end on purpose: renumbering the middle
            // once sent people to the wrong page for weeks.
            navButtons = new Button[] {
                F<Button>("NavPlay"), F<Button>("NavNews"), F<Button>("NavServer"),
                F<Button>("NavMods"), F<Button>("NavBuild"), F<Button>("NavSaves"),
                F<Button>("NavControls"), F<Button>("NavLogs"), F<Button>("NavDiag"),
                F<Button>("NavHelp"), F<Button>("NavSettings"), F<Button>("NavGallery") };
            pages = new UIElement[] {
                F<Grid>("PagePlay"), F<Grid>("PageNews"), F<Grid>("PageServer"),
                F<Grid>("PageMods"), F<Grid>("PageBuild"), F<Grid>("PageSaves"),
                F<Grid>("PageControls"), F<Grid>("PageLogs"), F<Grid>("PageDiag"),
                F<Grid>("PageHelp"), F<Grid>("PageSettings"), F<Grid>("PageGallery") };

            /*
              Saves is gone, and with it Server, Mods, What is installed and
              Logs (issue #599).

              Characters live on the server now, so a page for browsing and
              backing up local save files is showing people something that is
              no longer where their character is, which is worse than showing
              them nothing. The other four are the read-and-diagnose pages the
              team no longer wants in the everyday rail: Play, News, Controls,
              Diagnostics, Help and Settings are what is left.

              Collapsed rather than cut out of the arrays. The three arrays
              (navButtons, pages, PageTitles) and the PageXxx constants are
              parallel and indexed by number, and the comment on those
              constants records that a bare number in the middle of Play() once
              sent people to the wrong page for weeks. Renumbering eleven
              entries to save a few unreachable Grids is how that happens again.
              The pages cannot be reached from the rail, which is what was
              asked for; the dead Grids cost nothing and can be cut properly
              whenever the xaml is next opened on a machine with the compiler.

              A blocked Play sends people to Diagnostics (ShowPage(PageDiag)),
              where Scan and Fix are since #607 and which the rail shows. Until
              #982 it sent them to Mods, which by then had no Fix on it
              and no rail button to come back to.
            */
            int[] hiddenNav = { PageSaves, PageServer, PageMods, PageBuild, PageLogs };
            foreach (int p in hiddenNav)
                if (navButtons[p] != null)
                    navButtons[p].Visibility = Visibility.Collapsed;

            buttonDiscord  = F<Button>("ButtonDiscord");
            labelDiscord   = F<TextBlock>("LabelDiscord");
            discordAvatar  = F<Ellipse>("DiscordAvatar");

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
            if (labelDiscord != null) labelDiscord.Text = "Waiting…";
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
                                if (labelDiscord != null) labelDiscord.Text = who;
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

        /// <summary>The button that starts a link. The collection bar used to be
        /// a second one; since #428 it only ever opens the collection.</summary>
        static void SetLinkButtons(bool on)
        {
            if (buttonDiscord != null) buttonDiscord.IsEnabled = on;
        }

        /// <summary>The Discord account block above Settings. Called whenever it changes.</summary>
        static void RefreshDiscord()
        {
            if (labelDiscord == null) return;
            // This function is what says the card is now correct, so it is also
            // what puts the button back. Nothing else gets to leave it grey.
            if (buttonDiscord != null) buttonDiscord.IsEnabled = !linkingDiscord;
            if (Discord.Linked)
            {
                string who = Discord.Name;
                labelDiscord.Text = (who != null && who.Length > 0) ? who : "Linked";
                if (buttonDiscord != null) buttonDiscord.Content = "Reconnect";
                LoadDiscordAvatar();
            }
            else
            {
                labelDiscord.Text = "Not linked";
                if (buttonDiscord != null) buttonDiscord.Content = "Connect Discord";
                ClearDiscordAvatar();
            }
            // Linking or unlinking is what decides whether the gallery card can
            // offer Report, and whether the site's last word made this account
            // staff. A report half written under the account that has just gone
            // is closed rather than sent under the new one.
            if (GalleryReportOpen && !Discord.Linked) CloseGalleryReport();
            PaintGalleryPage();
        }

        /// <summary>Empty circle while unlinked, or while a picture is still loading.</summary>
        static void ClearDiscordAvatar()
        {
            if (discordAvatar == null) return;
            discordAvatar.Fill = Res("Line");
        }

        /// <summary>
        /// When linked but no avatar hash is on disk yet, ask /api/play/join once
        /// so the site can hand back Discord's avatar field, then paint it.
        /// </summary>
        static void PullDiscordAvatarIfNeeded()
        {
            if (!Discord.Linked) return;
            string have = "";
            try { have = Discord.Avatar; } catch (Exception ex) { Swallow.Note("Shell.PullDiscordAvatar", ex); }
            if (have != null && have.Length > 0) return;
            ThreadPool.QueueUserWorkItem(delegate
            {
                try { Discord.Join(); }
                catch (Exception ex) { Swallow.Note("Shell.PullDiscordAvatar", ex); }
                try
                {
                    win.Dispatcher.BeginInvoke(new Action(delegate
                    {
                        try { LoadDiscordAvatar(); }
                        catch (Exception ex) { Swallow.Note("Shell.PullDiscordAvatar", ex); }
                    }));
                }
                catch (Exception ex) { Swallow.Note("Shell.PullDiscordAvatar", ex); }
            });
        }

        /// <summary>
        /// Discord profile picture into the sidebar circle. Fetched off the UI
        /// thread so a slow CDN does not freeze the window; a miss leaves the
        /// empty circle.
        /// </summary>
        static void LoadDiscordAvatar()
        {
            if (discordAvatar == null) return;
            string url = "";
            try { url = Discord.AvatarUrl; }
            catch (Exception ex) { Swallow.Note("Shell.LoadDiscordAvatar", ex); url = ""; }
            if (string.IsNullOrEmpty(url)) { ClearDiscordAvatar(); return; }
            string want = url;
            ThreadPool.QueueUserWorkItem(delegate
            {
                BitmapImage bi = null;
                try
                {
                    byte[] raw = null;
                    try
                    {
                        ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12; // added, never replaced (#1360)
                        using (var wc = new System.Net.WebClient())
                        {
                            wc.Headers["User-Agent"] = "ThornswoodLauncher/" + Updater.Version;
                            raw = wc.DownloadData(want);
                        }
                    }
                    catch (Exception ex) { Swallow.Note("Shell.LoadDiscordAvatar", ex); raw = null; }
                    if (raw == null || raw.Length == 0) return;
                    bi = new BitmapImage();
                    bi.BeginInit();
                    bi.CacheOption = BitmapCacheOption.OnLoad;
                    bi.StreamSource = new MemoryStream(raw);
                    bi.EndInit();
                    bi.Freeze();
                }
                catch (Exception ex) { Swallow.Note("Shell.LoadDiscordAvatar", ex); bi = null; }
                if (bi == null) return;
                BitmapImage pic = bi;
                try
                {
                    win.Dispatcher.BeginInvoke(new Action(delegate
                    {
                        if (discordAvatar == null || !Discord.Linked) return;
                        // Stale answer: Reconnect or Forget may have changed the account.
                        string now = "";
                        try { now = Discord.AvatarUrl; } catch (Exception ex) { Swallow.Note("Shell.LoadDiscordAvatar", ex); }
                        if (now != want) return;
                        var brush = new ImageBrush(pic);
                        brush.Stretch = Stretch.UniformToFill;
                        brush.AlignmentX = AlignmentX.Center;
                        brush.AlignmentY = AlignmentY.Center;
                        discordAvatar.Fill = brush;
                    }));
                }
                catch (Exception ex) { Swallow.Note("Shell.LoadDiscordAvatar", ex); }
            });
        }

        static Brush Res(string key) { return (Brush)win.Resources[key]; }

        static void Log(string m)
        {
            lastLogged = m;
            txtStatus.Text = m;
            try { File.AppendAllText(Paths.LogFile, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + m + Environment.NewLine); }
            catch (Exception ex) { Swallow.Note("Shell.Log, append", ex); }
        }

        /// <summary>
        /// One line in launcher.log and nothing on the status line, for
        /// something whoever reads a report needs and whoever is playing does
        /// not. Safe from any thread, which Log is not: Log writes to a control.
        /// </summary>
        static void LogOnly(string m)
        {
            try { File.AppendAllText(Paths.LogFile, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + m + Environment.NewLine); }
            catch { /* the log is the only place this line could have gone */ }
        }

        /// <summary>
        /// One line saying what pressed Play (#2215): the mouse (and whether its
        /// left button is still down), the keyboard (and the last key down on
        /// this window, and how long ago), or neither, which is UI Automation or
        /// a program; whether the window was the active one; and how long after
        /// the last game closed.
        /// </summary>
        static string PlayPressedBy()
        {
            try
            {
                InputDevice dev = InputManager.Current.MostRecentInputDevice;
                string by;
                if (dev is MouseDevice)
                    by = "the mouse (left button " + (Mouse.LeftButton == MouseButtonState.Pressed ? "still down" : "up") + ")";
                else if (dev is KeyboardDevice)
                    by = "the keyboard (last key " + lastKeyDown + ", " +
                         (lastKeyDownAt == DateTime.MinValue ? "never" : (int)(DateTime.Now - lastKeyDownAt).TotalMilliseconds + " ms ago") +
                         (Keyboard.Modifiers != ModifierKeys.None ? ", " + Keyboard.Modifiers + " held" : "") + ")";
                else
                    by = dev == null ? "no input device (UI Automation or a program)" : dev.GetType().Name;
                string when = gameClosedAt == DateTime.MinValue ? "no game closed yet this run"
                    : (DateTime.Now - gameClosedAt).TotalSeconds.ToString("0.0") + " s after the last game closed";
                return "Play pressed by " + by + ", window " + (win != null && win.IsActive ? "active" : "not active") + ", " + when + ".";
            }
            catch (Exception ex) { return "Play pressed (what pressed it could not be read: " + ex.Message + ")."; }
        }

        // ------------------------------------------------------------- pages
        // Named, because these are the index into three parallel arrays and a
        // bare number in the middle of Play() sent people to the wrong page for
        // weeks without anyone noticing.
        const int PagePlay = 0, PageNews = 1, PageServer = 2, PageMods = 3, PageBuild = 4,
                  PageSaves = 5, PageControls = 6, PageLogs = 7, PageDiag = 8,
                  PageHelp = 9, PageSettings = 10, PageGallery = 11;

        static readonly string[] PageTitles = {
            "Play", "News", "Server", "Mods", "What is installed",
            "Saves", "Controls", "Logs", "Diagnostics", "Help", "Settings", "Gallery" };

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
            else if (i == PageGallery) BuildGalleryPage();

            // The Play spotlight turns only on the Play page, so a page
            // change starts or stops it, the way the title video follows
            // what is on screen.
            GalleryDecide();
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
                try { if (player != null) { player.Clock = null; player.Close(); } } catch (Exception ex) { Swallow.Note("Shell.StartHeaderVideo, dispose", ex); }
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
                // One crop for the band, the still picture's and this one, so
                // the two line up and the overlook sits where the approved
                // picture has it (Art.HeaderCrop says why that is not the
                // middle of the picture). The video is painted at its own size
                // and its own timing: no scale, no drift, no speed-up.
                brush.Stretch = Stretch.UniformToFill;
                brush.AlignmentX = AlignmentX.Center;
                brush.AlignmentY = AlignmentY.Center;
                brush.ViewboxUnits = BrushMappingMode.RelativeToBoundingBox;
                brush.Viewbox = Art.HeaderCrop;

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
        // Menu theme plays through MenuMusic (WebView2 HTML5). WPF MediaPlayer
        // failed on the ship PC with "Windows Media Player version 10 or later
        // is required" while Voice's WebView2 still carried audio.
        static void StartMenuMusic()
        {
            // Not for somebody who opened this from Windows Settings to
            // uninstall. The theme playing is the loudest way to say the
            // launcher has started up to play when that is not why it opened.
            if (cfg == null || askedToUninstall) return;
            string src = Path.Combine(Paths.Game, "Data\\Platform\\UI\\thornswood-theme.mp3");
            if (!File.Exists(src))
            {
                string alt = Path.Combine(Paths.Game, "Data\\Platform\\UI\\thornswood-dev-theme.mp3");
                if (File.Exists(alt)) src = alt;
                else return;
            }

            // Played from a copy under Profile, never from the game folder. The
            // copy is refreshed from the game folder on every start, so an
            // updated track is heard the next time the launcher opens, and a
            // pack install is not blocked by a held file handle.
            string file;
            try
            {
                string dir = Path.Combine(Paths.ProfileDir, "Music");
                Directory.CreateDirectory(dir);
                file = Path.Combine(dir, Path.GetFileName(src));
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
                double vol = Math.Max(0, Math.Min(100, cfg.MusicVolume)) / 100.0;
                MenuMusic.Start(file, vol, Stamp);
                MusicDecide();
                win.StateChanged += delegate { MusicDecide(); };
            }
            catch (Exception ex)
            {
                Stamp("Menu music: " + ex.Message);
            }
        }

        /// <summary>
        /// Plays or pauses the track for the moment: not when it is switched off
        /// in Settings, not while the game runs, not while minimised. The volume
        /// is the Settings slider, 0 to 100.
        /// </summary>
        static void MusicDecide()
        {
            // While the game runs the browser behind the theme is closed, not
            // paused (#963). The first call after the game closes makes it again.
            if (playing) { try { MenuMusic.Close(); } catch (Exception ex) { Swallow.Note("Shell.MusicDecide, close", ex); } return; }
            bool want = cfg != null && cfg.MusicOn && cfg.MusicVolume > 0 && !playing
                && win != null && win.WindowState != WindowState.Minimized;
            double vol = cfg == null ? 0 : Math.Max(0, Math.Min(100, cfg.MusicVolume)) / 100.0;
            try { MenuMusic.Decide(want, vol); } catch (Exception ex) { Swallow.Note("Shell.MusicDecide", ex); }
        }

        static void MusicLabel()
        {
            if (txtMusic == null) return;
            int v = Math.Max(0, Math.Min(100, cfg.MusicVolume));
            txtMusic.Text = v == 0 ? "silent" : v + "%";
        }

        /// <summary>
        /// The pictures the site is showing, turned through on the Play page
        /// as a spotlight of approved pictures only. Upload, Report, Accept
        /// and Delete live on the Gallery page (#731).
        ///
        /// Gallery.Load asks /api/public. The list is fetched once on a pool
        /// thread at start up with /api/gallery/who, so the Gallery page knows
        /// whether the site has the doors at all.
        ///
        /// The Play card stays hidden until the first picture has loaded.
        /// </summary>
        static void StartGallery()
        {
            if (galleryCard == null) return;
            ThreadPool.QueueUserWorkItem(delegate
            {
                List<Gallery.Shot> shots = Gallery.Load();
                Gallery.Who who = Gallery.AskWho();
                win.Dispatcher.BeginInvoke(new Action(delegate
                {
                    galleryWho = who;
                    galleryShots = (shots != null && shots.Count > 0) ? shots : null;
                    galleryAt = -1;
                    PaintGalleryPage();
                    if (galleryShots == null) return;

                    if (galleryTimer == null)
                    {
                        galleryTimer = new DispatcherTimer();
                        galleryTimer.Interval = TimeSpan.FromSeconds(7);
                        galleryTimer.Tick += delegate { ShowNextShot(); };
                        win.StateChanged += delegate { GalleryDecide(); };
                    }
                    ShowNextShot();
                    GalleryDecide();
                }));
            });
        }

        /// <summary>
        /// True when the site's last word on this Discord account was that it
        /// is staff: the access.dev roles, which is the same set the site calls
        /// staff at /api/gallery/who.
        ///
        /// Read from the door rather than from who, because who only knows
        /// browser sessions and the launcher has none. Door.Last is this
        /// session's answer when Play has been pressed; Discord.DevAllowed is
        /// the last answer written down, which is what there is before the
        /// first check in of a session.
        /// </summary>
        static bool GalleryStaff()
        {
            if (!Discord.Linked) return false;
            if (Door.Last != null && Door.Last.Dev) return true;
            return Discord.DevAllowed;
        }

        static bool GalleryReportOpen
        {
            get { return galleryPageReportRow != null && galleryPageReportRow.Visibility == Visibility.Visible; }
        }

        /// <summary>
        /// One line on the Gallery page, or nothing when there is nothing to say.
        /// </summary>
        static void SayGallery(string line)
        {
            if (txtGalleryPageSaid == null) return;
            if (string.IsNullOrEmpty(line))
            {
                txtGalleryPageSaid.Text = "";
                txtGalleryPageSaid.Visibility = Visibility.Collapsed;
                return;
            }
            txtGalleryPageSaid.Text = line;
            txtGalleryPageSaid.Visibility = Visibility.Visible;
        }

        /// <summary>
        /// Staff block visibility and whether upload is offered, from who and
        /// Discord link state. Called when the Gallery page is built and when
        /// Discord link state changes.
        /// </summary>
        static void PaintGalleryPage()
        {
            bool doors = galleryWho != null && galleryWho.Answered;
            if (btnGallerySend != null)
                btnGallerySend.IsEnabled = doors && Discord.Linked &&
                    galleryChosenPaths != null && galleryChosenPaths.Count > 0;
            if (btnGalleryChoose != null)
                btnGalleryChoose.IsEnabled = doors;
            if (galleryDrop != null)
                galleryDrop.IsEnabled = doors;
        }

        /// <summary>
        /// Rebuilds the Gallery page lists from the public feed and, for staff,
        /// the pending queue. Call on the UI thread after a pool trip, or from
        /// ShowPage which kicks the trip itself.
        /// </summary>
        static void BuildGalleryPage()
        {
            PaintGalleryPage();
            ThreadPool.QueueUserWorkItem(delegate
            {
                List<Gallery.Shot> shots = Gallery.Load();
                Gallery.Who who = Gallery.AskWho();
                string pendingBad = "";
                List<Gallery.Pending> pending = null;
                // Staff queue is Door / DevAllowed, not who.Answered.
                bool staff = Discord.Linked && ((Door.Last != null && Door.Last.Dev) || Discord.DevAllowed);
                if (staff) pending = Gallery.Queue(out pendingBad);
                win.Dispatcher.BeginInvoke(new Action(delegate
                {
                    galleryWho = who;
                    // Keep Play's rotation in step with what the Gallery page
                    // just learnt, without forcing a turn mid-page.
                    if (shots != null && shots.Count > 0)
                    {
                        galleryShots = shots;
                        if (galleryAt < 0 || galleryAt >= galleryShots.Count) galleryAt = -1;
                        if (galleryTimer == null)
                        {
                            galleryTimer = new DispatcherTimer();
                            galleryTimer.Interval = TimeSpan.FromSeconds(7);
                            galleryTimer.Tick += delegate { ShowNextShot(); };
                            win.StateChanged += delegate { GalleryDecide(); };
                        }
                        if (galleryAt < 0) ShowNextShot();
                        GalleryDecide();
                    }
                    else
                    {
                        galleryShots = null;
                        galleryAt = -1;
                        if (galleryCard != null) galleryCard.Visibility = Visibility.Collapsed;
                    }

                    galleryPending = pending;
                    PaintGalleryPage();
                    FillGalleryGrid(shots, pending, pendingBad);
                }));
            });
        }

﻿
        /// <summary>
        /// One Gallery grid: approved cards for everyone, plus pending cards for
        /// staff (Door / DevAllowed) in the same WrapPanel. No separate waiting
        /// section. Accept and Delete are staff-only; Reject is gone; Report
        /// stays on approved cards for linked people.
        /// </summary>
        static void FillGalleryGrid(List<Gallery.Shot> shots, List<Gallery.Pending> pending, string pendingBad)
        {
            if (galleryApprovedList == null) return;
            galleryApprovedList.Children.Clear();

            bool doors = galleryWho != null && galleryWho.Answered;
            bool staff = GalleryStaff();
            bool anyApproved = shots != null && shots.Count > 0;
            bool anyPending = staff && pending != null && pending.Count > 0;
            bool any = anyApproved || anyPending;

            if (!string.IsNullOrEmpty(pendingBad) && staff)
                SayGallery(pendingBad);

            if (txtGalleryApprovedEmpty != null)
            {
                txtGalleryApprovedEmpty.Text = any
                    ? ""
                    : "Nothing is on the gallery yet.";
                txtGalleryApprovedEmpty.Visibility = any ? Visibility.Collapsed : Visibility.Visible;
            }

            if (anyApproved)
            {
                for (int i = 0; i < shots.Count; i++)
                {
                    Gallery.Shot shot = shots[i];
                    if (shot == null) continue;
                    galleryApprovedList.Children.Add(BuildApprovedCard(shot, doors, staff));
                }
            }

            // Pending only for staff, same grid as approved. Play never sees these.
            if (anyPending)
            {
                for (int i = 0; i < pending.Count; i++)
                {
                    Gallery.Pending item = pending[i];
                    if (item == null || item.Name == null || item.Name.Length == 0) continue;
                    galleryApprovedList.Children.Add(BuildPendingCard(item));
                }
            }
        }

        static Border BuildApprovedCard(Gallery.Shot shot, bool doors, bool staff)
        {
            var card = new Border();
            card.Style = (Style)win.FindResource("Slab");
            card.Padding = new Thickness(0);
            card.Margin = new Thickness(0, 0, 14, 14);
            card.Width = 280;
            card.ClipToBounds = true;

            var stack = new StackPanel();

            var frame = new Border();
            frame.Height = 200;
            frame.Background = (Brush)win.FindResource("Line");
            frame.ClipToBounds = true;

            var img = new Image();
            img.Stretch = Stretch.UniformToFill;
            img.HorizontalAlignment = HorizontalAlignment.Stretch;
            img.VerticalAlignment = VerticalAlignment.Stretch;
            RenderOptions.SetBitmapScalingMode(img, BitmapScalingMode.HighQuality);
            if (shot.Image != null) img.Source = shot.Image;
            frame.Child = img;
            stack.Children.Add(frame);

            if (shot.Image == null && shot.ImageUrl != null && shot.ImageUrl.Length > 0)
            {
                Gallery.Shot hold = shot;
                Image holdImg = img;
                ThreadPool.QueueUserWorkItem(delegate
                {
                    BitmapImage bi = Gallery.Fetch(hold);
                    if (bi == null) return;
                    win.Dispatcher.BeginInvoke(new Action(delegate
                    {
                        if (holdImg != null) holdImg.Source = bi;
                    }));
                });
            }

            var meta = new StackPanel();
            meta.Margin = new Thickness(12, 10, 12, 12);

            var label = new TextBlock();
            label.Style = (Style)win.FindResource("Body");
            label.TextWrapping = TextWrapping.Wrap;
            string by = (shot.By != null && shot.By.Length > 0) ? shot.By : "";
            label.Text = by.Length > 0 ? ("By " + by) : "On the gallery";
            meta.Children.Add(label);

            if (doors && Discord.Linked && shot.Name != null && shot.Name.Length > 0)
            {
                var acts = new StackPanel();
                acts.Orientation = Orientation.Horizontal;
                acts.Margin = new Thickness(0, 8, 0, 0);

                var report = new Button();
                report.Style = (Style)win.FindResource("Ghost");
                report.Content = "Report";
                report.Padding = new Thickness(10, 4, 10, 4);
                Gallery.Shot holdShot = shot;
                report.Click += delegate { OpenGalleryReport(holdShot); };
                acts.Children.Add(report);

                if (staff)
                {
                    var del = new Button();
                    del.Style = (Style)win.FindResource("Ghost");
                    del.Content = "Delete";
                    del.Padding = new Thickness(10, 4, 10, 4);
                    del.Margin = new Thickness(8, 0, 0, 0);
                    string name = shot.Name;
                    del.Click += delegate { GalleryTakeDown(name); };
                    acts.Children.Add(del);
                }
                meta.Children.Add(acts);
            }

            stack.Children.Add(meta);
            card.Child = stack;
            return card;
        }

        static Border BuildPendingCard(Gallery.Pending item)
        {
            var card = new Border();
            card.Style = (Style)win.FindResource("Slab");
            card.Padding = new Thickness(0);
            card.Margin = new Thickness(0, 0, 14, 14);
            card.Width = 280;
            card.ClipToBounds = true;

            var stack = new StackPanel();

            var frame = new Border();
            frame.Height = 200;
            frame.Background = (Brush)win.FindResource("Line");
            frame.ClipToBounds = true;

            var img = new Image();
            img.Stretch = Stretch.UniformToFill;
            RenderOptions.SetBitmapScalingMode(img, BitmapScalingMode.HighQuality);
            if (item.Image != null) img.Source = item.Image;
            frame.Child = img;
            stack.Children.Add(frame);

            Gallery.Pending holdItem = item;
            Image holdImg = img;
            ThreadPool.QueueUserWorkItem(delegate
            {
                BitmapImage bi = Gallery.FetchPending(holdItem);
                if (bi == null) return;
                win.Dispatcher.BeginInvoke(new Action(delegate
                {
                    if (holdImg != null) holdImg.Source = bi;
                }));
            });

            var meta = new StackPanel();
            meta.Margin = new Thickness(12, 10, 12, 12);

            var label = new TextBlock();
            label.Style = (Style)win.FindResource("Body");
            label.TextWrapping = TextWrapping.Wrap;
            string by = (item.By != null && item.By.Length > 0) ? item.By : "somebody";
            label.Text = "By " + by + " (waiting)";
            meta.Children.Add(label);

            if (item.Note != null && item.Note.Length > 0)
            {
                var note = new TextBlock();
                note.Style = (Style)win.FindResource("Small");
                note.TextWrapping = TextWrapping.Wrap;
                note.Margin = new Thickness(0, 4, 0, 0);
                note.Text = item.Note;
                meta.Children.Add(note);
            }

            // Staff-only: this card is only built when GalleryStaff is true.
            var buttons = new StackPanel();
            buttons.Orientation = Orientation.Horizontal;
            buttons.Margin = new Thickness(0, 10, 0, 0);

            var accept = new Button();
            accept.Style = (Style)win.FindResource("Solid");
            accept.Content = "Accept";
            accept.Padding = new Thickness(14, 6, 14, 6);
            string name = item.Name;
            accept.Click += delegate { GalleryAccept(name); };
            buttons.Children.Add(accept);

            var del = new Button();
            del.Style = (Style)win.FindResource("Ghost");
            del.Content = "Delete";
            del.Padding = new Thickness(12, 6, 12, 6);
            del.Margin = new Thickness(8, 0, 0, 0);
            del.Click += delegate { GalleryDeletePending(name); };
            buttons.Children.Add(del);

            meta.Children.Add(buttons);
            stack.Children.Add(meta);
            card.Child = stack;
            return card;
        }

        static void OpenGalleryReport(Gallery.Shot shot)
        {
            if (shot == null || shot.Name == null || shot.Name.Length == 0) return;
            if (!Discord.Linked)
            {
                SayGallery("Connect Discord first, so the site knows who is reporting this.");
                return;
            }

            galleryReporting = shot;
            SayGallery("Say what is wrong with " + shot.Name + ". Staff read it; nothing comes off the gallery until one of them takes it off.");
            if (boxGalleryWhy != null) boxGalleryWhy.Text = "";
            if (galleryPageReportRow != null) galleryPageReportRow.Visibility = Visibility.Visible;
            if (boxGalleryWhy != null) boxGalleryWhy.Focus();
        }

        static void CloseGalleryReport()
        {
            galleryReporting = null;
            if (galleryPageReportRow != null) galleryPageReportRow.Visibility = Visibility.Collapsed;
            if (boxGalleryWhy != null) boxGalleryWhy.Text = "";
            if (btnGalleryReportSend != null) btnGalleryReportSend.IsEnabled = true;
        }

        static void SendGalleryReport()
        {
            Gallery.Shot shot = galleryReporting;
            if (shot == null) { CloseGalleryReport(); return; }

            string name = shot.Name;
            string why = boxGalleryWhy == null ? "" : boxGalleryWhy.Text;
            if (btnGalleryReportSend != null) btnGalleryReportSend.IsEnabled = false;
            SayGallery("Sending that to staff...");

            ThreadPool.QueueUserWorkItem(delegate
            {
                string bad = Gallery.Report(name, why);
                win.Dispatcher.BeginInvoke(new Action(delegate
                {
                    if (bad.Length == 0)
                    {
                        CloseGalleryReport();
                        SayGallery("Sent. Staff will look at it; the picture stays up until one of them takes it down.");
                    }
                    else
                    {
                        if (btnGalleryReportSend != null) btnGalleryReportSend.IsEnabled = true;
                        SayGallery(bad);
                    }
                }));
            });
        }

﻿        static void GalleryChooseFile()
        {
            var dlg = new Microsoft.Win32.OpenFileDialog();
            dlg.Title = "Choose pictures for the gallery";
            dlg.Filter = "Pictures|*.png;*.jpg;*.jpeg;*.webp;*.gif|All files|*.*";
            dlg.CheckFileExists = true;
            dlg.Multiselect = true;
            bool? ok = dlg.ShowDialog(win);
            if (ok != true || dlg.FileNames == null || dlg.FileNames.Length == 0) return;
            GalleryAddChosen(dlg.FileNames);
        }

        static bool GalleryAllowedPath(string path)
        {
            if (path == null || path.Length == 0) return false;
            string ext = Path.GetExtension(path).ToLowerInvariant();
            return ext == ".png" || ext == ".jpg" || ext == ".jpeg" ||
                   ext == ".webp" || ext == ".gif";
        }

        static void GalleryAddChosen(System.Collections.IEnumerable paths)
        {
            if (galleryChosenPaths == null) galleryChosenPaths = new List<string>();
            foreach (string path in paths)
            {
                if (!GalleryAllowedPath(path)) continue;
                if (!File.Exists(path)) continue;
                bool have = false;
                for (int i = 0; i < galleryChosenPaths.Count; i++)
                    if (string.Equals(galleryChosenPaths[i], path, StringComparison.OrdinalIgnoreCase))
                    { have = true; break; }
                if (!have) galleryChosenPaths.Add(path);
            }
            PaintGalleryChosen();
            PaintGalleryPage();
            SayGallery("");
        }

        static void GalleryRemoveChosen(string path)
        {
            if (galleryChosenPaths == null) return;
            for (int i = galleryChosenPaths.Count - 1; i >= 0; i--)
                if (string.Equals(galleryChosenPaths[i], path, StringComparison.OrdinalIgnoreCase))
                    galleryChosenPaths.RemoveAt(i);
            PaintGalleryChosen();
            PaintGalleryPage();
        }

        static void PaintGalleryChosen()
        {
            if (galleryChosenList == null) return;
            galleryChosenList.Children.Clear();
            int n = galleryChosenPaths == null ? 0 : galleryChosenPaths.Count;
            if (txtGalleryChosen != null)
                txtGalleryChosen.Text = n == 0 ? "No file chosen"
                    : (n == 1 ? Path.GetFileName(galleryChosenPaths[0])
                              : (n + " pictures chosen"));
            if (n == 0) return;

            for (int i = 0; i < galleryChosenPaths.Count; i++)
            {
                string path = galleryChosenPaths[i];
                var row = new Border();
                row.Style = (Style)win.FindResource("Slab");
                row.Padding = new Thickness(8, 8, 8, 8);
                if (i > 0) row.Margin = new Thickness(0, 8, 0, 0);

                var grid = new Grid();
                grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                grid.ColumnDefinitions.Add(new ColumnDefinition());
                grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

                var thumb = new Border();
                thumb.Width = 56; thumb.Height = 56;
                thumb.ClipToBounds = true;
                thumb.Background = (Brush)win.FindResource("Line");
                var img = new Image();
                img.Stretch = Stretch.UniformToFill;
                try
                {
                    var bi = new BitmapImage();
                    bi.BeginInit();
                    bi.CacheOption = BitmapCacheOption.OnLoad;
                    bi.UriSource = new Uri(path);
                    bi.DecodePixelWidth = 112;
                    bi.EndInit();
                    bi.Freeze();
                    img.Source = bi;
                }
                catch (Exception ex) { Swallow.Note("Shell.PaintGalleryChosen thumb", ex); }
                thumb.Child = img;
                Grid.SetColumn(thumb, 0);
                grid.Children.Add(thumb);

                var meta = new StackPanel();
                meta.Margin = new Thickness(12, 0, 0, 0);
                meta.VerticalAlignment = VerticalAlignment.Center;
                var name = new TextBlock();
                name.Style = (Style)win.FindResource("Body");
                name.Text = Path.GetFileName(path);
                name.TextTrimming = TextTrimming.CharacterEllipsis;
                meta.Children.Add(name);
                try
                {
                    long len = new FileInfo(path).Length;
                    var size = new TextBlock();
                    size.Style = (Style)win.FindResource("Small");
                    size.Margin = new Thickness(0, 2, 0, 0);
                    if (len < 1024) size.Text = len + " B";
                    else if (len < 1024 * 1024) size.Text = (len / 1024) + " KB";
                    else size.Text = (len / (1024.0 * 1024.0)).ToString("0.0") + " MB";
                    meta.Children.Add(size);
                }
                catch (Exception ex) { Swallow.Note("Shell.PaintGalleryChosen size", ex); }
                Grid.SetColumn(meta, 1);
                grid.Children.Add(meta);

                var rem = new Button();
                rem.Style = (Style)win.FindResource("Ghost");
                rem.Content = "Remove";
                rem.Padding = new Thickness(10, 4, 10, 4);
                rem.VerticalAlignment = VerticalAlignment.Center;
                string hold = path;
                rem.Click += delegate { GalleryRemoveChosen(hold); };
                Grid.SetColumn(rem, 2);
                grid.Children.Add(rem);

                row.Child = grid;
                galleryChosenList.Children.Add(row);
            }
        }

        static void WireGalleryDrop()
        {
            if (galleryDrop == null) return;
            galleryDrop.DragEnter += GalleryDropOver;
            galleryDrop.DragOver += GalleryDropOver;
            galleryDrop.DragLeave += delegate
            {
                galleryDrop.BorderBrush = (Brush)win.FindResource("Edge");
                galleryDrop.Background = new SolidColorBrush(Color.FromArgb(0x8C, 0x0B, 0x0E, 0x0A));
            };
            galleryDrop.Drop += delegate (object s, DragEventArgs e)
            {
                galleryDrop.BorderBrush = (Brush)win.FindResource("Edge");
                galleryDrop.Background = new SolidColorBrush(Color.FromArgb(0x8C, 0x0B, 0x0E, 0x0A));
                if (e.Data == null || !e.Data.GetDataPresent(DataFormats.FileDrop)) return;
                string[] files = e.Data.GetData(DataFormats.FileDrop) as string[];
                if (files == null || files.Length == 0) return;
                GalleryAddChosen(files);
            };
            galleryDrop.MouseLeftButtonUp += delegate (object s, MouseButtonEventArgs e)
            {
                if (e.OriginalSource is Button) return;
                GalleryChooseFile();
            };
        }

        static void GalleryDropOver(object s, DragEventArgs e)
        {
            if (e.Data != null && e.Data.GetDataPresent(DataFormats.FileDrop))
            {
                e.Effects = DragDropEffects.Copy;
                galleryDrop.BorderBrush = (Brush)win.FindResource("Accent");
                galleryDrop.Background = new SolidColorBrush(Color.FromArgb(0x28, 0xC9, 0xA2, 0x4B));
            }
            else e.Effects = DragDropEffects.None;
            e.Handled = true;
        }

        static void GallerySendChosen()
        {
            if (!Discord.Linked)
            {
                SayGallery("Connect Discord first, so the site knows who is sending this.");
                return;
            }
            if (galleryChosenPaths == null || galleryChosenPaths.Count == 0)
            {
                SayGallery("Choose a picture to send first.");
                return;
            }
            string[] paths = galleryChosenPaths.ToArray();
            string by = boxGalleryBy == null ? "" : boxGalleryBy.Text;
            string note = boxGalleryNote == null ? "" : boxGalleryNote.Text;
            if (btnGallerySend != null) btnGallerySend.IsEnabled = false;
            SayGallery(paths.Length == 1
                ? "Sending that to thornswood.net..."
                : ("Sending " + paths.Length + " pictures to thornswood.net..."));

            ThreadPool.QueueUserWorkItem(delegate
            {
                int ok = 0;
                string firstBad = "";
                for (int i = 0; i < paths.Length; i++)
                {
                    string bad = Gallery.Submit(paths[i], by, note);
                    if (bad.Length == 0) ok++;
                    else if (firstBad.Length == 0) firstBad = bad;
                }
                win.Dispatcher.BeginInvoke(new Action(delegate
                {
                    if (ok == paths.Length)
                    {
                        galleryChosenPaths.Clear();
                        PaintGalleryChosen();
                        if (boxGalleryNote != null) boxGalleryNote.Text = "";
                        SayGallery(ok == 1
                            ? "Sent. It is waiting for staff to Accept it onto the gallery."
                            : ("Sent " + ok + " pictures. They are waiting for staff to Accept."));
                        BuildGalleryPage();
                    }
                    else if (ok > 0)
                    {
                        galleryChosenPaths.Clear();
                        PaintGalleryChosen();
                        SayGallery("Sent " + ok + " of " + paths.Length + ". " + firstBad);
                        BuildGalleryPage();
                    }
                    else
                    {
                        SayGallery(firstBad.Length > 0 ? firstBad : "Nothing was sent.");
                        PaintGalleryPage();
                    }
                }));
            });
        }

        static void GalleryAccept(string name)
        {
            SayGallery("Accepting " + name + "...");
            ThreadPool.QueueUserWorkItem(delegate
            {
                string bad = Gallery.Approve(name);
                win.Dispatcher.BeginInvoke(new Action(delegate
                {
                    if (bad.Length == 0)
                    {
                        SayGallery("Accepted. It is on the gallery and will show on Play.");
                        BuildGalleryPage();
                    }
                    else SayGallery(bad);
                }));
            });
        }

        static void GalleryDeletePending(string name)
        {
            SayGallery("Deleting " + name + "...");
            ThreadPool.QueueUserWorkItem(delegate
            {
                // Same staff queue door as the old Reject; UI no longer says Reject.
                string bad = Gallery.Reject(name);
                win.Dispatcher.BeginInvoke(new Action(delegate
                {
                    if (bad.Length == 0)
                    {
                        SayGallery("Deleted. It is off the gallery queue.");
                        BuildGalleryPage();
                    }
                    else SayGallery(bad);
                }));
            });
        }

        static void GalleryTakeDown(string name)
        {
            SayGallery("Taking " + name + " down...");
            ThreadPool.QueueUserWorkItem(delegate
            {
                string bad = Gallery.TakeDown(name);
                win.Dispatcher.BeginInvoke(new Action(delegate
                {
                    if (bad.Length == 0)
                    {
                        SayGallery("Taken down. It is no longer on the gallery or on Play.");
                        BuildGalleryPage();
                    }
                    else SayGallery(bad);
                }));
            });
        }

        /// <summary>
        /// Turns to the next picture on the Play spotlight. Its image is
        /// fetched on a pool thread the first time it is shown and kept after
        /// that; a picture that will not load leaves the one before it up and
        /// the next tick turns past it.
        /// </summary>
        static void ShowNextShot()
        {
            if (galleryShots == null || galleryShots.Count == 0) return;
            galleryAt = (galleryAt + 1) % galleryShots.Count;
            Gallery.Shot shot = galleryShots[galleryAt];

            if (shot.Image != null) { ShowShot(shot); return; }

            ThreadPool.QueueUserWorkItem(delegate
            {
                BitmapImage bi = Gallery.Fetch(shot);
                if (bi == null) return;
                win.Dispatcher.BeginInvoke(new Action(delegate { ShowShot(shot); }));
            });
        }

        static void ShowShot(Gallery.Shot shot)
        {
            if (shot == null || shot.Image == null) return;
            if (galleryImage != null)
            {
                galleryImage.Stretch = Stretch.UniformToFill;
                galleryImage.HorizontalAlignment = HorizontalAlignment.Stretch;
                galleryImage.VerticalAlignment = VerticalAlignment.Stretch;
                galleryImage.Source = shot.Image;
            }
            if (galleryBy != null)
                galleryBy.Text = (shot.By != null && shot.By.Length > 0)
                    ? "By " + shot.By
                    : "";
            if (galleryCard != null && galleryCard.Visibility != Visibility.Visible)
                galleryCard.Visibility = Visibility.Visible;
        }

        /// <summary>
        /// Runs the Play spotlight rotation only when the Play page is up, the
        /// window is not minimised and no game is running.
        /// </summary>
        static void GalleryDecide()
        {
            if (galleryTimer == null || galleryShots == null) return;
            bool seen = pages != null && pages[PagePlay] != null &&
                        pages[PagePlay].IsVisible &&
                        win.WindowState != WindowState.Minimized && !playing;
            if (seen) { if (!galleryTimer.IsEnabled) galleryTimer.Start(); }
            else { if (galleryTimer.IsEnabled) galleryTimer.Stop(); }
        }

        static void Wire()
        {
            // The Play page names the server rather than addressing it. See the
            // note on BtnSrvCopy in Pages.cs.
            txtServer.Text = "Thornswood";
            PaintServerBoxes();
            chkAutoUpdate.IsChecked = cfg.AutoUpdate;
            txtVersion.Text = "launcher " + Updater.Version;
            // Channel is already on the sidebar brand (Thornswood over Dev).
            // Do not also tag the version line; that leftover truncated as
            // "dev bu". The one-line "Thornswood Dev" ran past the emblem in
            // the 208 column; two lines keep the name and Dev both visible.
            if (cfg.IsDev)
            {
                txtServer.Text = "Thornswood Dev";
                if (txtBrandSmall != null) txtBrandSmall.Text = "Thornswood\nDev";
                if (txtBrandBig != null) txtBrandBig.Text = "Thornswood Dev";
                try { win.Title = "Thornswood Dev"; } catch (Exception ex) { Swallow.Note("Shell.ApplyConfig", ex); }
            }
            DrawServerPick();
            boxSearch.Text = SearchHint;
            boxSearch.Foreground = Res("Faint");

            DrawBuildLine();
            txtStatusRight.Text = Paths.Root;
            chkKeepOpen.IsChecked = cfg.KeepLauncherOpen;
            chkCrashSnapshots.IsChecked = cfg.CrashSnapshots;
            DrawCrashFolder();
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
                catch (Exception ex) { Swallow.Note("Shell.Wire", ex); }
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
            // Menu music starts from the Voice ApplicationIdle callback after
            // WebView2Loader.dll is placed (see Voice.Start above).

            titleBar.MouseLeftButtonDown += delegate(object s, MouseButtonEventArgs e)
            {
                if (e.ClickCount == 2)
                {
                    win.WindowState = win.WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;
                    return;
                }
                try { win.DragMove(); } catch (Exception ex) { Swallow.Note("Shell.Wire", ex); }
            };

            // With WindowChrome a maximized window hangs past the screen by its
            // resize frame, so the frame is pulled in by that much while maximized.
            var frame = F<Border>("WindowFrame");
            if (frame != null)
            {
                Action fit = delegate { frame.Margin = win.WindowState == WindowState.Maximized ? MaximizedInset() : new Thickness(0); };
                win.StateChanged += delegate { fit(); };
                // Maximized onto a monitor with another scale: that monitor's frame.
                win.DpiChanged += delegate { fit(); };
                fit();
            }

            btnMin.Click += delegate { win.WindowState = WindowState.Minimized; };
            btnMax.Click += delegate { win.WindowState = win.WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized; };
            btnClose.Click += delegate { win.Close(); };

            for (int i = 0; i < navButtons.Length; i++)
            {
                int k = i;
                navButtons[i].Click += delegate { ShowPage(k); };
            }

            btnCopy.Visibility = Visibility.Collapsed;

            // For PlayPressedBy: the last key that went down on this window.
            win.PreviewKeyDown += delegate (object s, KeyEventArgs e)
            {
                lastKeyDown = e.Key == Key.System ? e.SystemKey : e.Key;
                lastKeyDownAt = DateTime.Now;
            };
            btnPlay.Click += delegate
            {
                // What pressed it, into the log (#2215). Since 20 September the
                // game has started again within three seconds of closing 17
                // times on One, the person saying they quit with the mouse
                // through Steam's overlay, and only this button reaches
                // StartPlay from outside. Nothing said which input pressed it,
                // so the cause could not be measured; this line is that
                // measurement.
                LogOnly(PlayPressedBy());
                // Play means Play. Until 20 September this opened a bar of two
                // character slots and the slot's own button started the game;
                // the person picks at the game's main menu now.
                if (playing) { Play(); return; }
                StartPlay();
            };
            if (buttonDiscord != null) buttonDiscord.Click += delegate { ConnectDiscord(); };

            btnUpdate.Click += delegate { RunUpdate(); };
            if (btnDowngrade != null) btnDowngrade.Click += delegate { RunDowngrade(); };
            btnInstallNow.Click += delegate
            {
                if (collectionBarUp || (collectionNoteUp && !updatePending))
                {
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
                    try { Voice.Stop(); } catch (Exception ex) { Swallow.Note("Shell.Wire", ex); }
                    Application.Current.Shutdown();
                };
            }
            else
            {
                btnUninstall.Click += delegate { DoUninstall(); };
            }
            if (btnServerPick != null) btnServerPick.Click += delegate { ToggleServerPick(); };
            if (btnServerDev != null) btnServerDev.Click += delegate { CloseServerPick(); SwitchToDev(); };
            if (btnServerMain != null) btnServerMain.Click += delegate { CloseServerPick(); SwitchToMain(); };
            if (btnCheckDiagnostics != null) btnCheckDiagnostics.Click += delegate { ShowPage(PageDiag); };

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
            chkCrashSnapshots.Click += delegate
            {
                // #2626: off unless the person turns it on. Crash Logger's own
                // switch follows at the next Play (CrashDump.Apply).
                cfg.CrashSnapshots = chkCrashSnapshots.IsChecked == true;
                try { cfg.Save(Paths.CfgFile); } catch (Exception ex) { Swallow.Note("Shell.Wire, cfg save", ex); }
                Log(cfg.CrashSnapshots
                    ? "Crash snapshots on. From the next Play, a crash saves one in " + CrashDump.KeptIn(cfg) + ". One can be 9 GB or more; only the newest is kept."
                    : "Crash snapshots off. From the next Play none are written. Any already saved are left where they are.");
            };
            btnCrashFolder.Click += delegate { PickCrashFolder(); };
            chkLockRes.Click += delegate
            {
                cfg.LockResolution = chkLockRes.IsChecked == true;
                try { cfg.Save(Paths.CfgFile); } catch (Exception ex) { Swallow.Note("Shell.Wire, cfg save", ex); }
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
                    : "The needs bars are hidden. The Body page on K shows the numbers. It applies next time the game starts.");
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
                try { System.IO.Directory.CreateDirectory(Paths.Personal); } catch (Exception ex) { Swallow.Note("Shell.Wire, mkdir", ex); }
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
                Log("Checking for updates...");
                ThreadPool.QueueUserWorkItem(delegate { CheckUpdatesBackground(true); });
            };

            btnAllControls.Click += delegate { ShowPage(PageControls); };

            // Gallery page (#731): upload, refresh, report send/cancel.
            WireGalleryDrop();
            if (btnGalleryChoose != null) btnGalleryChoose.Click += delegate { GalleryChooseFile(); };
            if (btnGallerySend != null) btnGallerySend.Click += delegate { GallerySendChosen(); };
            if (btnGalleryRefresh != null) btnGalleryRefresh.Click += delegate { BuildGalleryPage(); };
            if (btnGalleryReportCancel != null) btnGalleryReportCancel.Click += delegate { CloseGalleryReport(); };
            if (btnGalleryReportSend != null) btnGalleryReportSend.Click += delegate { SendGalleryReport(); };
            if (boxGalleryWhy != null)
                boxGalleryWhy.KeyDown += delegate (object s, KeyEventArgs e)
                {
                    if (e.Key == Key.Enter) { e.Handled = true; SendGalleryReport(); }
                    else if (e.Key == Key.Escape) { e.Handled = true; CloseGalleryReport(); }
                };

            WirePages();
            WireProgress();
            WireOwnGame();
            btnFolder.Click += delegate { Open(Paths.Root); };
            btnOpenLog.Click += delegate
            {
                if (File.Exists(Paths.LogFile)) Open(Paths.LogFile); else Log("Nothing has been logged yet.");
            };
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
                    try { seeded = Keep.Seed(); } catch (Exception ex) { Swallow.Note("Shell.Wire", ex); }
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
                    catch (Exception ex) { Swallow.Note("Shell.Wire", ex); }

                    try
                    {
                        int rules = Enforce.Apply();
                        if (rules > 0) did.Add(rules + " mod setting" + (rules == 1 ? "" : "s"));
                    }
                    catch (Exception ex) { Swallow.Note("Shell.Wire", ex); }

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
                try { Hold.Release(); } catch (Exception ex) { Swallow.Note("Shell.Wire, dispose", ex); }
                if (!playing) { try { Keep.Unpark(); } catch (Exception ex) { Swallow.Note("Shell.Wire", ex); } }
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
                // Asks the game processes the last look found whether they are
                // still up, and lists the machine's processes only when none is
                // (#978). Same answer as GameRunning, on the same tick.
                if (Checks.GameStillRunning())
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
                GalleryDecide();
                // An update was seen during the session and they quit before
                // the five minutes were up. The clock goes, the fact does not:
                // it is fetched now, the same as it would have been had the
                // launcher closed the game itself. Otherwise quitting early was
                // a way to stay on a build the rest of the room had moved past,
                // with nothing on screen to say so.
                if (updateSeenAt != DateTime.MinValue) closedForUpdate = true;
                updateSeenAt = DateTime.MinValue;
                try { Presence.Stop(); } catch (Exception ex) { Swallow.Note("Shell.Wire, dispose", ex); }
                try { Hold.Release(); } catch (Exception ex) { Swallow.Note("Shell.Wire, dispose", ex); }
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
                    try { Discord.SessionEnd(playedAs, ranFor, endedForUpdate ? "update" : "quit"); } catch (Exception ex) { Swallow.Note("Shell.Wire, dispose", ex); }
                    // Then the logs, on the same thread so they go after the
                    // row they attach to exists. This is the only moment they
                    // can be collected: the game truncates its own logs under
                    // Data\Platform at every game start, so anything not taken
                    // now is gone. Until 22 September every report began by
                    // asking the person to go and find four files themselves.
                    try { Discord.SessionLogs(); } catch (Exception ex) { Swallow.Note("Shell.Wire", ex); }
                });
                // Against the character, not just the install. Skyrim keeps its
                // own play time inside the save, and under SkyMP the character
                // is a change form on the server with often no save here at all,
                // so the launcher is the only thing in a position to count.
                // The character is whoever the menu's choice file named this
                // session; 0 when it never did, and then nothing is counted.
                try { Chars.AddPlaytime(chosenId, DateTime.Now - playStartedAt); } catch (Exception ex) { Swallow.Note("Shell.Wire", ex); }
                BuildStatRow();
                btnPlay.Content = "PLAY";
                btnQuitGame.Visibility = Visibility.Collapsed;
                gameClosedAt = DateTime.Now;
                Log("Game closed after " + (int)(DateTime.Now - playStartedAt).TotalMinutes + " minutes. Your Windows Skyrim folders are back to normal.");
                {
                    // Where the crash log is, and the snapshot when the
                    // person turned snapshots on (#2626). A snapshot is shown
                    // with its size and they are asked whether to keep it,
                    // since it can be 9 GB or more.
                    // What Crash Logger was told at Play, not the box as it is
                    // now, and off the window's thread: moving a 9 GB
                    // snapshot to a folder on another drive is a copy that
                    // takes minutes.
                    bool keptAtPlay = CrashDump.AppliedAtPlay;
                    string keptIn = CrashDump.KeptIn(cfg);
                    DateTime crashSince = playStartedAt;
                    ThreadPool.QueueUserWorkItem(delegate
                    {
                        string snapshot = null, crashed = null;
                        try { crashed = CrashDump.AfterSession(crashSince, keptAtPlay, keptIn, out snapshot); }
                        catch (Exception ex) { Swallow.Note("Shell.Wire, crash snapshot", ex); }
                        try
                        {
                            win.Dispatcher.BeginInvoke(new Action(delegate
                            {
                                if (crashed != null) Log(crashed);
                                if (snapshot != null) AskKeepSnapshot(snapshot, keptIn);
                            }));
                        }
                        catch (Exception ex) { Swallow.Note("Shell.Wire, crash snapshot", ex); }
                    });
                }

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
                    try { foreach (Issue i in Verify.Run(cfg)) if (i.Blocking) broke++; } catch (Exception ex) { Swallow.Note("Shell.Wire", ex); }
                    if (broke == 0) return;
                    try
                    {
                        win.Dispatcher.BeginInvoke(new Action(delegate
                        {
                            Log("Skyrim changed your plugin list on the way out, " + broke +
                                (broke == 1 ? " problem" : " problems") + ". Mods, then Fix.");
                        }));
                    }
                    catch (Exception ex) { Swallow.Note("Shell.Wire", ex); }
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
            foreach (Process p in ps) { try { p.Dispose(); } catch (Exception ex) { Swallow.Note("Shell.JustStarted, dispose", ex); } }
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
            // The checklist now lives on the Diagnostics page and Play shows a
            // one line summary of it (UpdateReadySummary). See #607.
            //
            // The rows are updated in place rather than cleared and rebuilt
            // every time. Rebuilding them on every scan, recheck and update
            // check made the list flash and re-say itself even when nothing had
            // changed, which #607 asked to stop: "it shouldn't say checking
            // every time it checks, it should just update in place if numbers
            // change". Only a row whose text or colour actually differs is
            // touched now, so an unchanged pass moves nothing on screen.
            List<Check> checks = Checks.All(cfg);
            bool all = true;
            int problems = 0;
            foreach (Check c in checks)
            {
                // An advisory row that fails is drawn amber and leaves Play
                // alone. See Check.Advisory.
                if (c.Blocks) { all = false; problems++; }
            }

            if (statusList != null)
            {
                // Positional: Checks.All is the one thing that decides how many
                // rows there are, so a change in their number, not just their
                // values, is the only thing that rebuilds.
                if (statusList.Children.Count != checks.Count)
                {
                    statusList.Children.Clear();
                    for (int i = 0; i < checks.Count; i++) statusList.Children.Add(StatusRow());
                }
                for (int i = 0; i < checks.Count; i++)
                    FillStatusRow(statusList.Children[i] as Border, checks[i]);
            }

            UpdateReadySummary(all, problems);

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
            //
            // Only the game Thornswood runs counts (#1218). A Steam copy that
            // moved on after Thornswood's own folder was made no longer brings
            // the card up: the folder holds 1.6.1170 itself and follows Vortex
            // whatever build the Steam copy is on.
            bool wrongBuild = Downgrade.Needed(cfg);
            // One current observation per draw, with no stale cache between draws.
            int collectionRevision = updateBar != null && btnInstallNow != null && !wrongBuild ? Checks.CollectionRevision(cfg) : 0;
            if (updateBar != null && btnInstallNow != null && ModsMissing(collectionRevision) && !wrongBuild)
            {
                ShowCollectionBar(collectionRevision);
            }
            else if (collectionBarUp && updateBar != null && btnInstallNow != null)
            {
                collectionBarUp = false;
                btnInstallNow.Content = "Install now";
                updateBar.Visibility = Visibility.Collapsed;
                btnInstallNow.Visibility = Visibility.Collapsed;
            }

            // Mods that could not be confirmed (Djinn, 2 Oct). CollectionProblem
            // answers "" when it cannot read the revision Vortex installed, which
            // left no card and no way to the collection on this page at all.
            // This is a note, not a hold: Play is not shut for it, because a
            // revision that cannot be read is not proof the mods are wrong.
            if (updateBar != null && btnInstallNow != null && !collectionBarUp && !updatePending &&
                !wrongBuild && !playing && !playBar.Active)
            {
                bool unsure = CollectionUnconfirmed(collectionRevision);
                if (unsure && (collectionNoteUp || updateBar.Visibility != Visibility.Visible))
                {
                    txtUpdateTitle.Text = "Your mods could not be confirmed";
                    txtUpdateNote.Text =
                        "The launcher could not read which revision of the Thornswood collection " +
                        "Vortex has installed. If you have not installed it, or are not sure, open " +
                        "the collection and let Vortex install or update it. Play is not held for this.";
                    btnInstallNow.Content = "Open the collection";
                    btnInstallNow.IsEnabled = true;
                    updateBar.Visibility = Visibility.Visible;
                    btnInstallNow.Visibility = Visibility.Visible;
                    collectionNoteUp = true;
                }
                else if (!unsure && collectionNoteUp)
                {
                    collectionNoteUp = false;
                    btnInstallNow.Content = "Install now";
                    updateBar.Visibility = Visibility.Collapsed;
                    btnInstallNow.Visibility = Visibility.Collapsed;
                }
            }
            else if (collectionNoteUp)
            {
                // An update or the collection card took the bar, or the game is
                // running: the note steps aside and leaves the bar to them.
                collectionNoteUp = false;
                if (!collectionBarUp && !updatePending && updateBar != null && btnInstallNow != null)
                {
                    btnInstallNow.Content = "Install now";
                    updateBar.Visibility = Visibility.Collapsed;
                    btnInstallNow.Visibility = Visibility.Collapsed;
                }
            }

            // Wrong Skyrim build: the one thing on this page with a button that
            // fixes it. Below the update bar in priority, because an update can
            // carry a new expected build and settle the question by itself.
            if (downgradeBar != null)
            {
                bool updateUp = updateBar != null && updateBar.Visibility == Visibility.Visible;
                downgradeBar.Visibility = (wrongBuild && !updateUp && !playing) ? Visibility.Visible : Visibility.Collapsed;
                if (btnDowngrade != null) btnDowngrade.IsEnabled = !Downgrade.Busy && !ownGameBusy;
                if (txtDowngradeTitle != null)
                    txtDowngradeTitle.Text = Paths.Collection ? "Skyrim on Steam is not on the server's build"
                        : OwnGame.Active && OwnGame.Changed().Count > 0 ? "Some of Skyrim's own files in Thornswood's folder changed"
                        : "Skyrim is on the wrong build";
            }

            bool working = playBar.Active;
            btnPlay.IsEnabled = all && !playing && !updatePending && !collectionBarUp && !ownGameBusy && !working && feedNotice.Hold == null;
            if (!working) HidePlayFill();
            // Only worth offering while there is something to quit, and it is
            // the one control on this page that stays live during a session.
            if (btnQuitGame != null)
                btnQuitGame.Visibility = Checks.GameRunning() ? Visibility.Visible : Visibility.Collapsed;

            // Missing mods outrank everything else here. The collection path
            // sets updatePending false, so the old order fell through to the
            // last branch and put PLAY back on a button that could not play:
            // the bar said install the mods and the button said go.
            // Work that reports how far it has got (#1145): the button is the
            // progress bar, and says what is going on and how much is left.
            // ShellProgress.cs paints the fill; this keeps the words when
            // anything else redraws the button in the meantime.
            if (working && !playing)
            {
                btnPlay.Content = PlayBarCaption(playBar.Text);
                btnPlay.ToolTip = "Play comes back when this is done.";
            }
            // The game folder itself is being made or brought up to date, so
            // there is nothing complete to start yet.
            else if (ownGameBusy && !playing)
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
                btnPlay.ToolTip = NoOwnFolderYet() + " This gives Thornswood a folder " +
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
        /// One empty checklist row for the Ready to launch list on Diagnostics.
        /// Built once and then filled by FillStatusRow, so the list is not torn
        /// down and rebuilt on every pass (#607). The shape is a Border holding
        /// a three column Grid: a dot, the name, and the detail.
        /// </summary>
        static Border StatusRow()
        {
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
            Grid.SetColumn(dot, 0); row.Children.Add(dot);

            var t1 = new TextBlock();
            t1.FontSize = 13; t1.Foreground = Res("Ink");
            t1.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(t1, 1); row.Children.Add(t1);

            var t2 = new TextBlock();
            t2.FontSize = 11.5;
            t2.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(t2, 2); row.Children.Add(t2);

            back.Child = row;
            return back;
        }

        /// <summary>
        /// Fills one row from a check, touching only what has actually changed
        /// so an unchanged pass moves nothing on screen. Res returns the one
        /// cached brush per key, so a reference match means the colour is the
        /// same and does not need setting again.
        /// </summary>
        static void FillStatusRow(Border back, Check c)
        {
            if (back == null) return;
            var row = back.Child as Grid;
            if (row == null || row.Children.Count < 3) return;
            var dot = row.Children[0] as Ellipse;
            var t1 = row.Children[1] as TextBlock;
            var t2 = row.Children[2] as TextBlock;

            Brush wantDot = Res(c.Ok ? "Ok" : c.Advisory ? "Warn" : "Bad");
            if (dot != null && !ReferenceEquals(dot.Fill, wantDot)) dot.Fill = wantDot;

            if (t1 != null && t1.Text != c.Name) t1.Text = c.Name;

            if (t2 != null)
            {
                if (t2.Text != c.Detail) t2.Text = c.Detail;
                Brush wantT2 = Res(c.Ok ? "Muted" : c.Advisory ? "Warn" : "Bad");
                if (!ReferenceEquals(t2.Foreground, wantT2)) t2.Foreground = wantT2;
            }
        }

        /// <summary>
        /// The one line summary of the checklist that sits on the Play page
        /// (#607). Updated in place: it does not flash or re-say itself when the
        /// count has not changed. The button's own words say why Play is held
        /// for anything that is not a failing row (an update, a downgrade, the
        /// feed), so this stays about the checks themselves.
        /// </summary>
        static void UpdateReadySummary(bool all, int problems)
        {
            if (dotReady != null)
            {
                Brush want = Res(all ? "Ok" : "Bad");
                if (!ReferenceEquals(dotReady.Fill, want)) dotReady.Fill = want;
            }
            if (txtReadyTitle != null)
            {
                // Pass: "Everything checks out". Fail: red "Check Diagnostics"
                // (capital C) and a button that opens the Diagnostics page.
                string title = all ? "Everything checks out" : "Check Diagnostics";
                if (txtReadyTitle.Text != title) txtReadyTitle.Text = title;
                Brush ink = Res(all ? "Ink" : "Bad");
                if (!ReferenceEquals(txtReadyTitle.Foreground, ink)) txtReadyTitle.Foreground = ink;
            }
            if (btnCheckDiagnostics != null)
                btnCheckDiagnostics.Visibility = all ? Visibility.Collapsed : Visibility.Visible;
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
        /// the line under the button, and the page is redrawn. The files go
        /// into Thornswood's own folder, or, before it has one, the folder is
        /// made from them. The Steam copy of Skyrim is never written (#1218).
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
                string.Join("\n", Downgrade.Commands(cfg)) + "\n\n" +
                "Steam downloads about 11 GB under your own account, and the launcher then " +
                (Paths.Collection ? "makes Thornswood's own game folder from those files. " : "puts the files into Thornswood's own game folder. ") +
                "Your Steam copy of Skyrim is not changed and can stay on any build.\n\n" +
                "Do not type or click while Steam's window is in front, or the keys go to the wrong place.",
                "Thornswood", MessageBoxButton.YesNo, MessageBoxImage.Question);
            if (r != MessageBoxResult.Yes) { Log("Left Skyrim on the build it is on."); return; }
            btnDowngrade.IsEnabled = false;
            btnDowngrade.Content = "Working...";
            // The bar under the note: a share while Steam downloads a part
            // whose size it has given, moving without a number while it has
            // not, and gone when the run ends. Downgrade.Progress in Downgrade.cs.
            Downgrade.OnProgress = delegate (int p)
            {
                try
                {
                    win.Dispatcher.BeginInvoke(new Action(delegate
                    {
                        if (prgDowngrade == null) return;
                        if (p == -1) { prgDowngrade.Visibility = Visibility.Collapsed; return; }
                        prgDowngrade.Visibility = Visibility.Visible;
                        prgDowngrade.IsIndeterminate = p < 0;
                        if (p >= 0) prgDowngrade.Value = Math.Min(100, p);
                    }));
                }
                catch (Exception ex) { Swallow.Note("RunDowngrade, the progress bar", ex); }
            };
            Downgrade.Start(cfg,
                PresenceLog,
                delegate (string s) { try { win.Dispatcher.BeginInvoke(new Action(delegate { txtDowngradeNote.Text = s; })); } catch (Exception ex) { Swallow.Note("Shell.RunDowngrade", ex); } },
                delegate (bool ok)
                {
                    try
                    {
                        win.Dispatcher.BeginInvoke(new Action(delegate
                        {
                            btnDowngrade.Content = ok ? "Done" : "Try again";
                            btnDowngrade.IsEnabled = !ok;
                            if (prgDowngrade != null) { prgDowngrade.IsIndeterminate = false; prgDowngrade.Visibility = Visibility.Collapsed; }
                            // Before Thornswood has a folder of its own the
                            // download is what the folder is made from, and
                            // the person already said yes to that above. With
                            // a folder, the files went straight into it, and
                            // there is nothing for Vortex to bring in. The
                            // Steam copy was not touched either way, so there
                            // is no question about Steam's updates to ask here.
                            if (ok && Paths.Collection && Downgrade.Downloaded(cfg) != null) StartOwnGame(true, true);
                            DrawStatus();
                            DrawBuildLine();
                        }));
                    }
                    catch (Exception ex) { Swallow.Note("Shell.RunDowngrade, own game source", ex); }
                });
        }

        // ------------------------------------------------------------- mods
        static void RunScan()
        {
            List<Issue> issues = null;
            Waiting(delegate { issues = Verify.Run(cfg); });
            ShowVerify(issues, true);
        }

        /// <summary>
        /// Paints the Scan and Fix card from an Issue list and redraws Ready
        /// to launch from the same list. <paramref name="logDetail"/> is true
        /// for a fresh Scan (writes the issue lines to the log); false when
        /// Diagnostics opens onto an already shared LastIssues and should not
        /// re-say the scan.
        /// </summary>
        static void ShowVerify(List<Issue> issues, bool logDetail)
        {
            if (issues == null) issues = new List<Issue>();
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
            else if (CollectionNotDeployed(issues, elsewhere))
            {
                // Vortex has not deployed the collection into the folder the
                // launcher reads, so most of the plugins the server expects are
                // simply not there. One line per missing plugin is a screenful
                // of noise with the one fact that matters left out, so say that
                // fact once and point at Vortex and the collection. The gate is
                // untouched: Play still counts the blocking issues and refuses
                // (Shell Play, Verify.Run). When this install already has its
                // own Game folder, Fix refreshes it from Vortex and can put the
                // missing plugins back; otherwise Fix cannot invent a collection
                // Vortex never deployed, so the button stays grey.
                dotVerify.Fill = Res("Bad");
                txtVerifyTitle.Text = "The collection is not deployed";
                string dataFolder = Path.Combine(Paths.Game, "Data");
                bool canRefresh = false;
                try { canRefresh = OwnGame.Active; }
                catch (Exception ex) { Swallow.Note("Shell.RunScan, asking whether OwnGame is active for collection-not-deployed Fix", ex); }
                if (canRefresh)
                {
                    txtVerifyNote.Text =
                        "Thornswood's mods are not in " + dataFolder + ", so almost none of the " +
                        "collection the server expects is installed where the launcher looks. Fix " +
                        "refreshes Thornswood's own folder from what Vortex has deployed. Open " +
                        "Vortex and press Deploy first if the collection is not on yet, then Fix.";
                    btnFix.IsEnabled = true;
                }
                else
                {
                    txtVerifyNote.Text =
                        "Thornswood's mods are not in " + dataFolder + ", so almost none of the " +
                        "collection the server expects is installed where the launcher looks. Open " +
                        "Vortex and press Deploy, and install the collection first if you have not. " +
                        "The collection card above opens it. Then press Scan again.";
                    btnFix.IsEnabled = false;
                }
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
                // Absent ("is not installed") means Vortex never put the mod on
                // this machine. FileMissing means the list still names it and
                // Data does not have the file: Fix restores those from Vortex
                // (and from the server when it serves them). Greying Fix for
                // one absent plugin also greyed the light flags, another
                // server's menu files and the plugins that are simply extra,
                // which Fix does put right. 1 October that was a clean
                // collection install with one plugin the collection does not
                // ship. Fix stays off only when every blocking issue is a mod
                // that is not installed at all.
                int absent = 0;
                int fileMissing = 0;
                int fixable = 0;
                foreach (Issue i in issues) if (i.Absent) absent++;
                foreach (Issue i in issues) if (i.FileMissing) fileMissing++;
                foreach (Issue i in issues) if (i.Blocking && !i.Absent) fixable++;
                bool onlyAbsent = absent > 0 && fixable == 0;
                if (onlyAbsent && !elsewhere)
                {
                    sb.Append("\n\nThese are not installed at all. Fix cannot help. In Vortex, " +
                              "Profiles, press Enable under Thornswood.");
                }
                else if (absent > 0 && !elsewhere)
                {
                    sb.Append("\n\nFix cannot install a mod Vortex does not have. It still puts right the rest of this list.");
                }
                else if (fileMissing > 0 && !elsewhere)
                {
                    sb.Append("\n\nFix puts the missing plugin files back into Data from Vortex " +
                              "(and from the server when it has a copy). It does not remove them from the list.");
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
                btnFix.IsEnabled = blocking > 0 && (!onlyAbsent || elsewhere);
            }
            // The count alone read the same after every press: 182, 182, 182.
            // When most of them are mods that are simply not in the game folder,
            // pressing Scan again or Fix changes nothing, and that is the line
            // worth reading.
            if (logDetail)
            {
            int missing = 0;
            foreach (Issue i in issues) if (i.Absent) missing++;
            Log("Scan finished. " + issues.Count + " issue" + (issues.Count == 1 ? "" : "s") + " found." +
                (missing > 0 && !elsewhere
                    ? " " + missing + (missing == 1
                        ? " of them is a mod that is not in the game folder at all, which Scan and Fix cannot change."
                        : " of them are mods that are not in the game folder at all, which Scan and Fix cannot change.") +
                      (Paths.Collection && OwnGame.NotThisCollection(missing, Verify.Expected)
                        ? " Vortex most likely has another profile deployed." : "")
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

            // Same Issue list the card just painted (Verify.LastIssues). Without
            // this, Scan could go green while Ready to launch Mods / Mod list
            // still showed the previous Run, or the reverse after Fix.
            DrawStatus();
        }

        /// <summary>
        /// True when Vortex has not deployed the collection into the folder the
        /// launcher reads: most of the plugins the server expects are simply not
        /// in Data, so the card should say that once rather than list every one.
        /// Not when Vortex deploys somewhere else (that has its own line and Fix
        /// helps), and only past a floor so a couple of missing files is still
        /// read plugin by plugin. This decides only what the card shows; the Play
        /// gate is unchanged and still counts the blocking issues.
        /// </summary>
        static bool CollectionNotDeployed(List<Issue> issues, bool elsewhere)
        {
            if (elsewhere) return false;
            if (Verify.Expected <= 0) return false;
            int missing = 0;
            foreach (Issue i in issues) if (i.FileMissing) missing++;
            // A handful of missing files is a mod or two, not the whole
            // collection. Half of what the server expects, and at least ten,
            // is the collection not being there at all.
            return missing >= 10 && missing * 2 >= Verify.Expected;
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
            // Scan and Fix moved to the Diagnostics page (#607), so this page no
            // longer shows or hides that card per tab.

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
                    try { kb = new FileInfo(f).Length / 1024; } catch (Exception ex) { Swallow.Note("Shell.BuildModList, leaf", ex); }
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
                    try { kb = new FileInfo(f).Length / 1024; } catch (Exception ex) { Swallow.Note("Shell.BuildModList", ex); }
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

        /// <summary>Log from a background thread. Log itself touches the UI.</summary>
        static void SafeLog(string m)
        {
            try
            {
                if (win.Dispatcher.CheckAccess()) Log(m);
                else win.Dispatcher.BeginInvoke(new Action(delegate { Log(m); }));
            }
            catch (Exception ex) { Swallow.Note("Shell.SafeLog", ex); }
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
        // Nine of them now, so they wrap instead of running off the side, and
        // each one says what it is rather than making you click to find out.
        // DIY is a card in the same strip as the presets; its editor panel
        // shows only while that card is selected (#601 follow-up).
        static bool diyPanelOpen;
        static bool diyPanelStateReady;

        static void SyncDiyPanelOpenFromConfig()
        {
            if (diyPanelStateReady) return;
            diyPanelStateReady = true;
            diyPanelOpen = string.Equals(cfg.Theme, Themes.CustomName, StringComparison.OrdinalIgnoreCase)
                && Themes.HasCustom(cfg.CustomColors);
        }

        static void BuildThemeRow()
        {
            SyncDiyPanelOpenFromConfig();
            themeRow.Children.Clear();

            var wrap = new WrapPanel();
            themeRow.Children.Add(wrap);

            foreach (Theme t in Themes.All)
                AddThemeButton(wrap, t);

            // DIY sits after the built-ins in the same strip. Clicking it shows
            // the make-your-own panel; clicking a preset hides that panel again.
            AddDiyButton(wrap);

            if (diyPanelOpen)
                txtThemeNote.Text = "DIY. Make your own colours below.";
            else
            {
                Theme cur = Themes.Resolve(cfg);
                txtThemeNote.Text = cur.Name + ". " + cur.Note;
            }
        }

        static void AddThemeButton(WrapPanel wrap, Theme t)
        {
            Theme captured = t;
            // A preset is not lit while the DIY card is selected, even if the
            // saved theme name still matches that preset (editing before save).
            bool on = !diyPanelOpen
                && string.Equals(t.Name, cfg.Theme, StringComparison.OrdinalIgnoreCase);

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
                diyPanelOpen = false;
                cfg.Theme = captured.Name;
                cfg.Save(Paths.CfgFile);
                Themes.Apply(win, Themes.Resolve(cfg));
                Redraw();
                Log("Theme set to " + captured.Name + ".");
            };
            wrap.Children.Add(b);
        }

        static void AddDiyButton(WrapPanel wrap)
        {
            bool on = diyPanelOpen;

            string swatchHex;
            if (Themes.HasCustom(cfg.CustomColors))
                swatchHex = Themes.Custom(cfg.CustomColors, cfg.CustomLight).Swatch;
            else
                // No saved DIY yet: show the DIY starter accent, not the live
                // preset, so the card does not twin Dwemer (or Forge) at a glance.
                swatchHex = Themes.Custom(null, false).Swatch;

            var sw = new Border();
            sw.Width = 15; sw.Height = 15;
            sw.CornerRadius = new CornerRadius(2);
            sw.Background = new SolidColorBrush((Color)ColorConverter.ConvertFromString(swatchHex));
            sw.Margin = new Thickness(0, 0, 10, 0);
            sw.VerticalAlignment = VerticalAlignment.Center;

            var label = new TextBlock();
            label.Text = "DIY";
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
                diyPanelOpen = true;
                if (Themes.HasCustom(cfg.CustomColors))
                {
                    cfg.Theme = Themes.CustomName;
                    cfg.Save(Paths.CfgFile);
                    Themes.Apply(win, Themes.Resolve(cfg));
                    Redraw();
                    Log("Theme set to DIY.");
                }
                else
                {
                    BuildThemeRow();
                    BuildThemeEditor();
                }
            };
            wrap.Children.Add(b);
        }

        // The boxes the editor draws, kept so their text can be read back when
        // the person presses Use these colours. Rebuilt whenever the editor is.
        static readonly Dictionary<string, TextBox> themeBoxes = new Dictionary<string, TextBox>();
        static CheckBox themeLightBox;

        // The make-your-own editor under the strip. Shown only while the DIY
        // card is selected. It fills from whatever theme is on, so start from
        // a preset, open DIY, change what you want, then Use these colours.
        static void BuildThemeEditor()
        {
            if (themeEditor == null) return;
            themeEditor.Children.Clear();
            themeBoxes.Clear();

            if (!diyPanelOpen)
            {
                themeEditor.Visibility = Visibility.Collapsed;
                return;
            }
            themeEditor.Visibility = Visibility.Visible;

            Theme cur = Themes.Resolve(cfg);

            var head = new TextBlock();
            head.Text = "Make your own";
            head.FontFamily = new FontFamily("Constantia, Georgia");
            head.FontSize = 13;
            head.Foreground = Res("Faint");
            head.Margin = new Thickness(0, 2, 0, 8);
            themeEditor.Children.Add(head);

            var blurb = new TextBlock();
            blurb.Text = "Start from the colours on screen, change any to a hex value like #C8763A, "
                       + "then press Use these colours. The two soft ones put the opacity first, so "
                       + "#3CC8763A is that accent at low opacity. Pick a preset above to leave DIY.";
            blurb.FontSize = 11.5; blurb.Foreground = Res("Faint");
            blurb.TextWrapping = TextWrapping.Wrap; blurb.LineHeight = 17;
            blurb.Margin = new Thickness(0, 0, 0, 12);
            themeEditor.Children.Add(blurb);

            var grid = new WrapPanel();
            foreach (string name in Themes.Names)
            {
                string val;
                cur.Colors.TryGetValue(name, out val);

                var col = new StackPanel();
                col.Width = 152;
                col.Margin = new Thickness(0, 0, 14, 12);

                var l = new TextBlock();
                l.Text = name;
                l.FontSize = 11.5; l.Foreground = Res("Muted");
                l.Margin = new Thickness(2, 0, 0, 4);
                col.Children.Add(l);

                var box = new TextBox();
                box.Text = val == null ? "" : val;
                box.Style = (Style)win.Resources["Field"];
                box.FontFamily = new FontFamily("Cascadia Mono, Consolas");
                col.Children.Add(box);

                themeBoxes[name] = box;
                grid.Children.Add(col);
            }
            themeEditor.Children.Add(grid);

            themeLightBox = new CheckBox();
            themeLightBox.Content = "This is a light theme, so the launcher shades its own graphics for a light background";
            themeLightBox.IsChecked = cur.Light;
            themeLightBox.Margin = new Thickness(2, 2, 0, 14);
            themeEditor.Children.Add(themeLightBox);

            var apply = new Button();
            apply.Content = "Use these colours";
            apply.Style = (Style)win.Resources["Solid"];
            apply.HorizontalAlignment = HorizontalAlignment.Left;
            apply.Click += delegate { ApplyCustomTheme(); };
            themeEditor.Children.Add(apply);
        }

        static void ApplyCustomTheme()
        {
            var pairs = new List<string>();
            foreach (string name in Themes.Names)
            {
                TextBox box;
                if (!themeBoxes.TryGetValue(name, out box)) continue;
                string hex = (box.Text == null ? "" : box.Text).Trim();

                bool good = false;
                try { ColorConverter.ConvertFromString(hex); good = true; }
                catch (Exception ex) { Swallow.Note("ApplyCustomTheme, reading " + name, ex); }
                if (!good)
                {
                    Log("The colour for " + name + " is not a hex value. Use something like #C8763A. Nothing changed.");
                    return;
                }
                pairs.Add(name);
                pairs.Add(hex);
            }

            cfg.CustomColors = pairs.ToArray();
            cfg.CustomLight = themeLightBox != null && themeLightBox.IsChecked == true;
            cfg.Theme = Themes.CustomName;
            diyPanelOpen = true;
            cfg.Save(Paths.CfgFile);
            Themes.Apply(win, Themes.Resolve(cfg));
            Redraw();
            Log("Your own theme is on. Change the colours any time, or pick a preset to leave DIY.");
        }

        // Everything that paints itself from the theme brushes rather than
        // binding to them. Called after a theme change, and nowhere else.
        static void Redraw()
        {
            BuildThemeRow(); BuildThemeEditor(); BuildModList(); DrawStatus(); BuildPathRows(); BuildHelp();
            BuildStatRow(); BuildNews(); BuildLogs(); BuildDisplay(); BuildChat();
            BuildServer(); BuildInstalled(); BuildControls(); BuildDiag(); RefreshDiscord();
            boxSearch.Foreground = Res(boxSearch.Text == SearchHint ? "Faint" : "Ink");
        }

        static void BuildPathRows()
        {
            pathRows.Children.Clear();
            AddPathRow("Install", Paths.Root);
            AddPathRow("Game", Paths.Game);
            // No Saves row. Characters live on the server, and listing
            // Profile\MyGames\Saves told people their character was in a
            // folder it is not (#984, the same reason the Saves page is
            // hidden, #599).
            AddPathRow("Settings", Paths.LiveMyGames);
            DrawInGameBrowser();
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

            // Read out of the real files rather than typed here. A hardcoded
            // list went stale the moment the build moved to SkyMP:
            // it was still offering an F2 party menu that no longer exists and
            // a trade key belonging to a mod that had been removed. A row now
            // appears only if its binding is really there, and it shows the key
            // it is really bound to.
            //
            // The five that matter first for somebody joining the server: the
            // emote wheel, and the four keys that only make sense here, trade,
            // party, friend and journal. All are Thornswood's own, in
            // Thornswood.ini, so each shows the key it is really bound to and
            // the fuller Controls page below carries the rest.
            List<Keys.Binding> keys;
            try { keys = Keys.All(); } catch { keys = new List<Keys.Binding>(); }

            AddKeyFor(keys, "emotewheel", "The emote wheel of gestures and animations, seen by everyone near you.");
            AddKeyFor(keys, "tradewith",  "Offer a trade to whoever you are looking at.");
            AddKeyFor(keys, "party",      "Your friends, who is online, and your party.");
            AddKeyFor(keys, "friendkey",  "Add or remove the friend you are looking at.");
            AddKeyFor(keys, "journal",    "Your journals, their pages, and sharing them.");
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
            sp.HorizontalAlignment = HorizontalAlignment.Center;
            sp.VerticalAlignment = VerticalAlignment.Center;

            var l = new TextBlock();
            l.Text = label; l.FontSize = 11.5;
            l.FontFamily = new FontFamily("Constantia, Georgia");
            // Ink a little dimmed, not Faint: over the banner art Faint could not be read (#596).
            l.Foreground = Res("Ink"); l.Opacity = 0.78;
            sp.Children.Add(l);

            var v = new TextBlock();
            v.Text = value; v.FontSize = 16; v.Foreground = Res("Ink");
            v.FontFamily = new FontFamily("Constantia, Georgia");
            v.Margin = new Thickness(0, 3, 0, 0);
            sp.Children.Add(v);

            statRow.Children.Add(sp);
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
            try { cfg.Save(Paths.CfgFile); } catch (Exception ex) { Swallow.Note("Shell.AutoDisplayOnce, cfg save", ex); }

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

        /// <summary>The folder crash snapshots go in, under the setting (#2626).</summary>
        static void DrawCrashFolder()
        {
            if (txtCrashFolder == null) return;
            string chosen = (cfg.CrashSnapshotFolder ?? "").Trim();
            txtCrashFolder.Text = chosen.Length > 0
                ? "Saved in " + chosen + "."
                : "Saved beside the crash logs, in " + CrashDump.Folder + ", until you choose a folder.";
        }

        /// <summary>Where crash snapshots go: a folder the person chooses (#2626).</summary>
        static void PickCrashFolder()
        {
            string chosen;
            using (var dlg = new System.Windows.Forms.FolderBrowserDialog())
            {
                dlg.Description = "Choose the folder crash snapshots are saved in. One can be 9 GB or more, so pick a drive with room.";
                dlg.ShowNewFolderButton = true;
                try
                {
                    string start = CrashDump.KeptIn(cfg);
                    if (start.Length > 0 && Directory.Exists(start)) dlg.SelectedPath = start;
                }
                catch { /* only where the picker opens; it opens at its own default instead */ }
                if (dlg.ShowDialog() != System.Windows.Forms.DialogResult.OK) return;
                chosen = dlg.SelectedPath;
            }
            cfg.CrashSnapshotFolder = chosen;
            try { cfg.Save(Paths.CfgFile); } catch (Exception ex) { Swallow.Note("Shell.PickCrashFolder, cfg save", ex); }
            Log("Crash snapshots will be saved in " + chosen + ".");
            DrawCrashFolder();
        }

        /// <summary>
        /// After a crash that saved a snapshot (#2626): says where it is and
        /// how big, and asks whether to keep it. No deletes it now.
        /// </summary>
        static void AskKeepSnapshot(string snapshot, string keptIn)
        {
            long size = 0;
            try { size = new FileInfo(snapshot).Length; } catch (Exception ex) { Swallow.Note("Shell.AskKeepSnapshot, size", ex); }
            // Owned by the launcher's window, so it opens in front of it.
            var r = MessageBox.Show(win,
                "The game crashed, and a full crash snapshot was saved:\n\n" + snapshot + "\n" + CrashDump.Size(size) +
                "\n\nIt is only needed if somebody is going to look into this crash. Keep it?\n\nYes keeps it. No deletes it now.",
                "Thornswood", MessageBoxButton.YesNo, MessageBoxImage.Question);
            if (r == MessageBoxResult.Yes)
            {
                // Only now are older ones tidied, so a No below never leaves
                // somebody with none at all. This one is the newest.
                int gone = CrashDump.Tidy(keptIn);
                Log("Kept the crash snapshot " + snapshot + "." +
                    (gone > 0 ? " Deleted " + gone + " older one" + (gone == 1 ? "" : "s") + "; only the newest is kept." : ""));
                return;
            }
            try
            {
                File.Delete(snapshot);
                Log("Deleted the crash snapshot " + snapshot + ", " + CrashDump.Size(size) + " freed.");
            }
            catch (Exception ex)
            {
                Log("Could not delete the crash snapshot " + snapshot + ": " + ex.Message);
            }
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
            // Only the first check says "checking". After that the last answer
            // stays up and changes in place when the new one lands (#596).
            if (string.IsNullOrEmpty(txtPing.Text) || txtPing.Text == "no address")
            {
                txtPing.Text = "checking";
                dotServer.Fill = Res("Faint");
            }

            string host = cfg.ServerAddress;
            if (string.IsNullOrEmpty(host)) { txtPing.Text = "no address"; return; }

            // Main resources are on 3000; Dev on 7788 (same pair Online.AskOther uses).
            int mainPort = 3000;
            int devPort = 7788;
            int minePort = SkyMp.ResourcePortFor(cfg);

            ThreadPool.QueueUserWorkItem(delegate
            {
                long icmp = -1;
                try
                {
                    using (var ping = new Ping())
                    {
                        PingReply r = ping.Send(host, 2000);
                        if (r != null && r.Status == IPStatus.Success) icmp = r.RoundtripTime;
                    }
                }
                catch (Exception ex) { Swallow.Note("Shell.StartPing", ex); }

                long tcpMain = TcpMs(host, mainPort);
                long tcpDev = TcpMs(host, devPort);
                long tcpMine = TcpMs(host, minePort);

                bool up = tcpMine >= 0 || icmp >= 0;
                long ms = icmp >= 0 ? icmp : tcpMine;
                bool serving = tcpMine >= 0;

                // Prefer ICMP for latency when that port answers; "no reply" when TCP missed.
                string mainNow = tcpMain < 0 ? "no reply" : (icmp >= 0 ? icmp + " ms" : tcpMain + " ms");
                string devNow = tcpDev < 0 ? "no reply" : (icmp >= 0 ? icmp + " ms" : tcpDev + " ms");
                string mainKey = tcpMain >= 0 ? "Ok" : "Warn";
                string devKey = tcpDev >= 0 ? "Ok" : "Warn";

                win.Dispatcher.BeginInvoke(new Action(delegate
                {
                    string now = up ? ms + " ms" : "no reply";
                    pingMsText = now;
                    pingMainText = mainNow;
                    pingDevText = devNow;
                    dotMainKey = mainKey;
                    dotDevKey = devKey;
                    // Keep who is on until the next count comes back, so the line
                    // does not shrink and grow again every refresh.
                    string was = txtPing.Text ?? "";
                    int dot = was.IndexOf("   \u00b7   ");
                    string tail = dot >= 0 ? was.Substring(dot) : "";
                    string want = now + tail;
                    if (txtPing.Text != want) txtPing.Text = want;
                    dotServer.Fill = Res(up ? (serving ? "Ok" : "Warn") : "Warn");
                    RecordPing(up ? ms : -1, serving);
                    PaintServerChip();
                    AskOnline();
                }));
            });
        }

        /// <summary>TCP connect time to a resources port, or -1 when it does not answer.</summary>
        static long TcpMs(string host, int port)
        {
            if (string.IsNullOrEmpty(host) || port <= 0) return -1;
            try
            {
                var sw = System.Diagnostics.Stopwatch.StartNew();
                using (var c = new System.Net.Sockets.TcpClient())
                {
                    IAsyncResult ar = c.BeginConnect(host, port, null, null);
                    if (ar.AsyncWaitHandle.WaitOne(2000) && c.Connected)
                    {
                        c.EndConnect(ar);
                        return sw.ElapsedMilliseconds;
                    }
                }
            }
            catch (Exception ex) { Swallow.Note("Shell.TcpMs", ex); }
            return -1;
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
            if (string.IsNullOrEmpty(txtVoiceState.Text)) txtVoiceState.Text = "checking";
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
                    try { System.Net.ServicePointManager.SecurityProtocol |= (System.Net.SecurityProtocolType)3072; } catch (Exception ex) { Swallow.Note("Shell.DrawVoiceState", ex); }
                    var req = (System.Net.HttpWebRequest)System.Net.WebRequest.Create(where + "/health");
                    req.Method = "GET";
                    req.Timeout = 4000;
                    req.ReadWriteTimeout = 4000;
                    using (var resp = (System.Net.HttpWebResponse)req.GetResponse())
                        up = resp.StatusCode == System.Net.HttpStatusCode.OK;
                }
                catch (Exception ex) { Swallow.Note("Shell.DrawVoiceState", ex); }

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
                        catch (Exception ex) { Swallow.Note("Shell.DrawVoiceState", ex); }

                        // where is still used to probe /health; do not show the URL (#797).
                        txtVoiceState.Text = fUp
                            ? ("Running. It starts inside the game on its own." + keys)
                            : ("Not answering, so nobody will hear anybody. It is not installed on the server, or not running.");
                    }
                    catch (Exception ex) { Swallow.Note("Shell.DrawVoiceState", ex); }
                }));
            });
        }

        // The probe waits on a socket, so it does not run on the thread that
        // draws. A settings page that freezes for most of a second every time
        // it is opened is worse than one that fills in a moment later.
        /// <summary>
        /// The compact Server control on Play: the closed label is the server
        /// this build is on, and the dropdown lists Main and Dev. Picking the
        /// other one opens or installs that build; picking the current one
        /// just closes the list. More servers later are more rows (#605).
        /// </summary>
        static void DrawServerPick()
        {
            if (btnServerMain == null || btnServerDev == null || txtServerPick == null) return;
            // Do not assign Content: the XAML holds the status chip layout.
            // Open panel lists both Main and Dev at the chip width; current stays enabled
            // so the covered-chip popup is one complete panel, not a second orphan card.
            if (cfg.IsDev) txtServerPick.Text = "Dev";
            else txtServerPick.Text = "Main";
            btnServerMain.Visibility = Visibility.Visible;
            btnServerDev.Visibility = Visibility.Visible;
            btnServerMain.IsEnabled = true;
            btnServerDev.IsEnabled = true;
            // The open panel covers the chip, so its first row is where the chip
            // was: that row is the server this install is on, the other below.
            // Until 11 Oct the rows kept the XAML order, Main then Dev, and a dev
            // install opened onto Main (Patrick: "it doesnt have the current
            // server you are on as the one on top").
            var rows = btnServerMain.Parent as Panel;
            if (rows != null && rows == btnServerDev.Parent)
            {
                Button first = cfg.IsDev ? btnServerDev : btnServerMain;
                Button second = cfg.IsDev ? btnServerMain : btnServerDev;
                if (rows.Children.IndexOf(first) != 0)
                {
                    rows.Children.Remove(first);
                    rows.Children.Insert(0, first);
                }
                first.Margin = new Thickness(0, 0, 0, 2);
                second.Margin = new Thickness(0);
            }
            PaintServerChip();
        }

        /// <summary>
        /// Status chip on the server button: dot, name, ms, "N of M awake".
        /// Dropdown rows are exactly Main and Dev; each shows its own dot + ms + awake.
        /// </summary>
        static void PaintServerChip()
        {
            string meta = "";
            if (!string.IsNullOrEmpty(pingMsText)) meta = pingMsText;
            if (!string.IsNullOrEmpty(awakeMineText))
                meta = meta.Length == 0 ? awakeMineText : meta + "   \u00b7   " + awakeMineText;
            if (txtServerPickMeta != null && txtServerPickMeta.Text != meta) txtServerPickMeta.Text = meta;

            string mainMeta = "";
            if (!string.IsNullOrEmpty(pingMainText)) mainMeta = pingMainText;
            if (!string.IsNullOrEmpty(awakeMainText))
                mainMeta = mainMeta.Length == 0 ? awakeMainText : mainMeta + "   \u00b7   " + awakeMainText;
            string devMeta = "";
            if (!string.IsNullOrEmpty(pingDevText)) devMeta = pingDevText;
            if (!string.IsNullOrEmpty(awakeDevText))
                devMeta = devMeta.Length == 0 ? awakeDevText : devMeta + "   \u00b7   " + awakeDevText;
            if (txtServerMainMeta != null && txtServerMainMeta.Text != mainMeta) txtServerMainMeta.Text = mainMeta;
            if (txtServerDevMeta != null && txtServerDevMeta.Text != devMeta) txtServerDevMeta.Text = devMeta;

            if (dotServerMain != null) dotServerMain.Fill = Res(dotMainKey);
            if (dotServerDev != null) dotServerDev.Fill = Res(dotDevKey);
            if (dotServerPick != null && dotServer != null)
                dotServerPick.Fill = dotServer.Fill;
        }

        static void ToggleServerPick()
        {
            if (serverPickPopup == null || btnServerPick == null) return;
            if (!serverPickPopup.IsOpen)
            {
                // Exact chip width; cover the chip so open state is one left-aligned
                // panel (Placement Bottom + VerticalOffset = -height), not a second card.
                btnServerPick.UpdateLayout();
                double w = btnServerPick.ActualWidth;
                double h = btnServerPick.ActualHeight;
                if (w < 1) w = btnServerPick.MinWidth > 0 ? btnServerPick.MinWidth : 210;
                if (h < 1) h = 32;
                if (serverPickPanel != null)
                {
                    serverPickPanel.Width = w;
                    serverPickPanel.MinWidth = w;
                    serverPickPanel.MaxWidth = w;
                }
                serverPickPopup.HorizontalOffset = 0;
                serverPickPopup.VerticalOffset = -h;
                serverPickPopup.IsOpen = true;
            }
            else serverPickPopup.IsOpen = false;
        }

        static void CloseServerPick()
        {
            if (serverPickPopup != null) serverPickPopup.IsOpen = false;
        }

        static void SwitchToDev()
        {
            if (cfg.IsDev) return;

            if (DevBuild.Installed)
            {
                try
                {
                    Process.Start(new ProcessStartInfo(DevBuild.Exe) { UseShellExecute = true, WorkingDirectory = Path.GetDirectoryName(DevBuild.Exe) });
                    Log("Opened the dev build.");
                }
                catch (Exception ex) { Log("Could not open the dev build: " + ex.Message); }
                return;
            }

            // The role check is the site asking Discord about this account, so
            // there has to be an account to ask about first.
            if (!Discord.Linked)
            {
                MessageBox.Show(win,
                    "Connect Discord in the sidebar first. The launcher checks your Discord roles before it installs the dev build.",
                    "Thornswood", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }

            Log("Checking whether your Discord roles allow the dev build...");
            if (btnServerDev != null) btnServerDev.IsEnabled = false;
            ThreadPool.QueueUserWorkItem(delegate
            {
                Standing st;
                try { st = Discord.Join(); }
                catch (Exception ex)
                {
                    st = new Standing();
                    st.Ok = false;
                    st.Why = "offline";
                    st.Message = "Could not reach thornswood.net: " + ex.Message;
                }

                win.Dispatcher.BeginInvoke(new Action(delegate
                {
                    try
                    {
                        // Discord.Join has already written dev-allowed.txt when the
                        // answer carried the flag, so DrawServerPick in the finally
                        // reflects the fresh answer either way.
                        if (st.Why == "offline" || st.Why == "could not ask Discord")
                        {
                            MessageBox.Show(win,
                                "Could not reach thornswood.net to check your roles just now. Try again in a minute.",
                                "Thornswood", MessageBoxButton.OK, MessageBoxImage.Warning);
                            return;
                        }
                        if (st.Why == "link")
                        {
                            MessageBox.Show(win,
                                "Connect Discord in the sidebar first, then try again.",
                                "Thornswood", MessageBoxButton.OK, MessageBoxImage.Information);
                            return;
                        }
                        if (!st.Dev)
                        {
                            MessageBox.Show(win,
                                "The dev build is for the staff roles: Owner, Dev, Gamemaster, Moderator and Loremaster. Your account does not have one; ask Patrick if you need it.",
                                "Thornswood", MessageBoxButton.OK, MessageBoxImage.Warning);
                            return;
                        }

                        var r = MessageBox.Show(win,
                            "Your roles allow the dev build. Install it?\n\nIt copies this launcher into " + DevBuild.Root +
                            " and opens it. It follows the dev branch and joins the dev server; this build is not touched.",
                            "Thornswood", MessageBoxButton.YesNo, MessageBoxImage.Question);
                        if (r != MessageBoxResult.Yes) return;
                        try { Log(DevBuild.Install(cfg)); }
                        catch (Exception ex) { Log("Could not install the dev build: " + ex.Message); }
                    }
                    finally
                    {
                        if (btnServerDev != null) btnServerDev.IsEnabled = true;
                        DrawServerPick();
                    }
                }));
            });
        }

        /// <summary>
        /// Switch back to the main server from the dev build: open the main
        /// launcher beside this one. Never installs or touches the main build,
        /// only opens what is already there.
        /// </summary>
        static void SwitchToMain()
        {
            if (!cfg.IsDev) return;
            if (DevBuild.MainInstalled)
            {
                try
                {
                    Process.Start(new ProcessStartInfo(DevBuild.MainExe) { UseShellExecute = true, WorkingDirectory = Path.GetDirectoryName(DevBuild.MainExe) });
                    Log("Opened the main build.");
                }
                catch (Exception ex) { Log("Could not open the main build: " + ex.Message); }
            }
            else
            {
                MessageBox.Show(win,
                    "The main build is not at " + DevBuild.MainRoot + ". Install it again from thornswood.net.",
                    "Thornswood", MessageBoxButton.OK, MessageBoxImage.Warning);
            }
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
            catch (Exception ex) { Swallow.Note("Shell.DoUninstall", ex); }

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
            catch (Exception ex) { Swallow.Note("Shell.DoUninstall", ex); }

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
                catch (Exception ex) { Swallow.Note("Shell.DrawServerState", ex); }

                bool fLocal = local, fUp = up, fOurs = ours, fNode = node;
                string fDir = dir;
                win.Dispatcher.BeginInvoke(new Action(delegate
                {
                    try
                    {
                        var sb = new StringBuilder();
                        // Host:port stays off the UI (see #797). Local still names this machine.
                        sb.Append(fUp ? "UP" : "not answering");
                        if (fLocal) sb.Append("   this machine");
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
                    catch (Exception ex) { Swallow.Note("Shell.DrawServerState", ex); }
                }));
            });
        }

        // ------------------------------------------------------------- updates
        // ------------------------------------------------------------- who is on
        static string pingText = "";

        /// <summary>Presence speaks from its own thread; the log lives on this one.</summary>
        static void PresenceLog(string m)
        {
            try { win.Dispatcher.BeginInvoke(new Action(delegate { Log(m); })); } catch (Exception ex) { Swallow.Note("Shell.PresenceLog", ex); }
        }

        static void AskOnline()
        {
            pingText = txtPing.Text ?? "";
            int dot = pingText.IndexOf("   \u00b7   ");
            if (dot >= 0) pingText = pingText.Substring(0, dot);
            ThreadPool.QueueUserWorkItem(delegate
            {
                Online.Count c = null;
                Online.Count other = null;
                try { c = Online.Ask(cfg); } catch (Exception ex) { Swallow.Note("Shell.AskOnline", ex); }
                try { other = Online.AskOther(cfg); } catch (Exception ex) { Swallow.Note("Shell.AskOnline", ex); }
                Online.Count got = c;
                Online.Count gotOther = other;
                win.Dispatcher.BeginInvoke(new Action(delegate
                {
                    string extra = Online.Line(got);
                    awakeMineText = extra;
                    awakeOtherText = Online.Line(gotOther);
                    if (cfg != null && cfg.IsDev)
                    {
                        awakeDevText = extra;
                        awakeMainText = awakeOtherText;
                    }
                    else
                    {
                        awakeMainText = extra;
                        awakeDevText = awakeOtherText;
                    }
                    string want = extra.Length > 0 ? pingText + "   \u00b7   " + extra : pingText;
                    if (txtPing.Text != want) txtPing.Text = want;
                    PaintServerChip();
                    if (playing && got != null)
                    {
                        try { Presence.Update(got.Known ? got.Now : -1, got.Max); } catch (Exception ex) { Swallow.Note("Shell.AskOnline", ex); }
                    }
                }));
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
            // One download, the client runtime, shown on the Play button (#1145).
            PlayProgress.Begin("Updating", 1);
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
                    PlayProgress.End();
                    if (n > 0) win.Dispatcher.BeginInvoke(new Action(delegate { DrawStatus(); }));
                }
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
        static string CollectionProblem(int revision = -1)
        {
            if (string.IsNullOrEmpty(cfg.CollectionUrl)) return "";
            try
            {
                if (Checks.EnabledPlugins() <= Checks.MostPluginsWithoutCollection) return "none";

                // THE REVISION, NOT A NAMED FILE.
                //
                // This used to ask whether one mod's file was present and
                // call the collection stale when it was not. That was wrong in
                // both directions, and on 22 September it was wrong on
                // Patrick's own machine in the quietest possible way.
                //
                // The file was not in the collection then: a script put it
                // into a build by hand. So anybody
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
                int mine = revision < 0 ? Checks.CollectionRevision(cfg) : revision;
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

        static bool ModsMissing(int revision = -1)
        {
            return CollectionProblem(revision).Length > 0;
        }

        static bool collectionBarUp = false;

        /// <summary>The not-confirmed note is on the bar above Play (see DrawStatus).</summary>
        static bool collectionNoteUp = false;

        /// <summary>
        /// True when CollectionProblem found nothing wrong only because it could
        /// not read which collection revision Vortex installed (Djinn, 2 Oct).
        /// </summary>
        static bool CollectionUnconfirmed(int revision = -1)
        {
            if (string.IsNullOrEmpty(cfg.CollectionUrl)) return false;
            try
            {
                if (revision < 0) revision = Checks.CollectionRevision(cfg);
                if (CollectionProblem(revision).Length > 0) return false;
                return revision <= 0;
            }
            catch (Exception ex) { Swallow.Note("Shell.CollectionUnconfirmed", ex); return false; }
        }

        /// <summary>
        /// Turns the bar above Play into the one thing worth doing first. Same
        /// bar, same button, different job, because a second card underneath a
        /// louder one is a card nobody reads.
        /// </summary>
        static void ShowCollectionBar(int revision = -1)
        {
            if (revision < 0) revision = Checks.CollectionRevision(cfg);
            string problem = CollectionProblem(revision);
            bool stale = problem == "stale";

            if (stale)
            {
                int mine = revision;
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
                int mine = revision;
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

            // Open to everybody (#428). Patrick, 28 Sep: "we are in alpha so the
            // world is open by application". Anyone can download, and the
            // collection's link is on the public Downloads page, so holding it
            // back here until Discord was linked kept nothing from anybody and
            // left somebody still waiting on their application with a button
            // that only said Connect Discord, which the site refuses until they
            // are accepted. The application is what unlocks Play, not the mods.
            btnInstallNow.Content = "Open the collection";
            btnInstallNow.IsEnabled = true;
        }


    }
}
