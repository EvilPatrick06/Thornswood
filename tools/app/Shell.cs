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
        static bool updatePending;
        static DateTime playStartedAt;
        static int modTab;   // 0 server plugins, 1 script extender, 2 your own
        static DispatcherTimer timer;

        static Border charBar;
        static StackPanel charRow;
        static TextBlock txtCharNote;
        static bool charPickerOpen;

        static TextBlock txtServer, txtPing, txtStatus, txtStatusRight, txtVersion, txtBuildLine,
                         txtUpdateTitle, txtUpdateNote, txtModCount, txtUpdateSource,
                         txtPageTitle, txtHeroLine, txtVerifyTitle, txtVerifyNote,
                         txtSaveNote, txtSaveCount, txtLogCount, txtDisplayNote;
        static Ellipse dotServer, dotVerify;
        static StackPanel statusList, modList, themeRow, pathRows, helpList,
                          newsList, saveList, logList, statRow, displayModeRow,
                          firstRunCard, quickKeysCard, quickKeys;
        static TextBox boxSearch, boxAddress, boxPort, boxResolution, boxFrameLimit;
        static CheckBox chkAutoUpdate, chkVSync, chkKeepOpen, chkLockRes;
        static CheckBox chkKeepSaves;
        static Button btnVoiceTest;
        static TextBlock txtVoiceState;
        static Button btnUninstall, btnServerStart, btnServerStop;
        static TextBlock txtServerState;
        static Border updateBar, mineCard;
        static Grid titleBar;
        static Button btnPlay, btnRecheck, btnCopy, btnUpdate, btnMin, btnMax, btnClose,
                      btnSaveServer, btnCheckNow, btnFolder, btnOpenLog, btnOpenSaves,
                      btnRepair, btnRestore, btnIcons, tabPlugins, tabSkse, tabMine,
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
            using (var mutex = new Mutex(true, "ThornswoodLauncher", out fresh))
            {
                if (!fresh) return;
                try { Run(args); }
                catch (Exception ex)
                {
                    MessageBox.Show(ex.ToString(), "Thornswood could not start",
                                    MessageBoxButton.OK, MessageBoxImage.Error);
                }
            }
        }

        static void Run(string[] args)
        {
            string root = null;
            for (int i = 0; i < args.Length - 1; i++)
                if (args[i].Equals("-root", StringComparison.OrdinalIgnoreCase)) root = args[i + 1];

            Paths.Init(root);
            cfg = Config.Load(Paths.CfgFile);
            Stats.Load();

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
            BuildStatRow();
            BuildPathRows();
            BuildHelp();
            BuildModList();
            ShowPage(PagePlay);

            if (Swap.Restore()) Log("Cleaned up a redirect left behind by a crash.");

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

            // Anyone upgrading has saves sitting in the old shared folder.
            // They belong to a person, so they become character one rather
            // than being stranded behind a link.
            try { Chars.Adopt(); } catch { }
            try
            {
                int named = Files.FixPresetNames();
                if (named > 0) Log("Put " + named + " class name" + (named == 1 ? "" : "s") + " back to the right spelling.");
            }
            catch { }
            ClearStuckGame(false);
            RunScan();
            if (DrawStatus()) Log("Ready."); else Log("Something needs attention before you can play.");
            AutoDisplayOnce();
            StartPing();
            if (cfg.AutoUpdate && Updater.Enabled(cfg))
                ThreadPool.QueueUserWorkItem(delegate { CheckUpdatesBackground(false); });

            CentreOnMainScreen();

            new Application().Run(win);
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
            chkVSync = F<CheckBox>("ChkVSync"); chkKeepOpen = F<CheckBox>("ChkKeepOpen");
            btnBackupSaves = F<Button>("BtnBackupSaves"); btnOpenSaveFolder = F<Button>("BtnOpenSaveFolder");
            btnCopyCrash = F<Button>("BtnCopyCrash"); btnOpenLogFolder = F<Button>("BtnOpenLogFolder");
            btnSaveDisplay = F<Button>("BtnSaveDisplay");
            btnQuitGame = F<Button>("BtnQuitGame");
            chkLockRes = F<CheckBox>("ChkLockRes");
            dotServer = F<Ellipse>("DotServer"); dotVerify = F<Ellipse>("DotVerify");
            mineCard = F<Border>("MineCard");
            statusList = F<StackPanel>("StatusList"); modList = F<StackPanel>("ModList");
            themeRow = F<StackPanel>("ThemeRow"); pathRows = F<StackPanel>("PathRows");
            helpList = F<StackPanel>("HelpList");
            boxSearch = F<TextBox>("BoxSearch"); boxAddress = F<TextBox>("BoxAddress"); boxPort = F<TextBox>("BoxPort");
            btnShowServer = F<Button>("BtnShowServer");
            charBar = F<Border>("CharBar"); charRow = F<StackPanel>("CharRow");
            txtCharNote = F<TextBlock>("TxtCharNote");
            chkAutoUpdate = F<CheckBox>("ChkAutoUpdate");
            updateBar = F<Border>("UpdateBar"); titleBar = F<Grid>("TitleBar");

            btnPlay = F<Button>("BtnPlay"); btnRecheck = F<Button>("BtnRecheck"); btnCopy = F<Button>("BtnCopy");
            btnUpdate = F<Button>("BtnUpdate"); btnMin = F<Button>("BtnMin"); btnMax = F<Button>("BtnMax");
            btnClose = F<Button>("BtnClose"); btnSaveServer = F<Button>("BtnSaveServer");
            btnCheckNow = F<Button>("BtnCheckNow"); btnInstallNow = F<Button>("BtnInstallNow");
            btnFolder = F<Button>("BtnFolder");
            btnOpenLog = F<Button>("BtnOpenLog"); btnOpenSaves = F<Button>("BtnOpenSaves");
            btnRepair = F<Button>("BtnRepair"); btnRestore = F<Button>("BtnRestore");
            btnIcons = F<Button>("BtnIcons");
            btnUninstall = F<Button>("BtnUninstall"); chkKeepSaves = F<CheckBox>("ChkKeepSaves");
            btnServerStart = F<Button>("BtnServerStart"); btnServerStop = F<Button>("BtnServerStop");
            txtServerState = F<TextBlock>("TxtServerState");
            btnVoiceTest = F<Button>("BtnVoiceTest");
            txtVoiceState = F<TextBlock>("TxtVoiceState");
            tabPlugins = F<Button>("TabPlugins"); tabSkse = F<Button>("TabSkse"); tabMine = F<Button>("TabMine");
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

            BindPages();
        }

        static Brush Res(string key) { return (Brush)win.Resources[key]; }

        static void Log(string m)
        {
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
            else if (i == PageSaves) BuildSaves();
            else if (i == PageControls) BuildControls();
            else if (i == PageLogs) BuildLogs();
            else if (i == PageDiag) BuildDiag();
        }

        static void Wire()
        {
            // The Play page names the server rather than addressing it. See the
            // note on BtnSrvCopy in Pages.cs.
            txtServer.Text = "Thornswood";
            PaintServerBoxes();
            chkAutoUpdate.IsChecked = cfg.AutoUpdate;
            txtVersion.Text = "launcher " + Updater.Version;
            boxSearch.Text = SearchHint;
            boxSearch.Foreground = Res("Faint");

            long bytes = 0;
            try { if (File.Exists(Paths.Exe)) bytes = new FileInfo(Paths.Exe).Length; } catch { }
            txtBuildLine.Text = (bytes == cfg.ExpectedExeBytes ? "game 1.6.1170" : "game unknown");
            txtStatusRight.Text = Paths.Root;
            txtHeroLine.Text = Checks.EnabledPlugins() + " plugins  ·  game 1.6.1170  ·  launcher " + Updater.Version;
            chkKeepOpen.IsChecked = cfg.KeepLauncherOpen;
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
            DrawVoiceState();

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
                if (Updater.Enabled(cfg))
                {
                    Log("Checking for updates...");
                    ThreadPool.QueueUserWorkItem(delegate { CheckUpdatesBackground(true); });
                }
                else Log("Updates are off: " + Updater.WhyDisabled(cfg));
            };
            btnPlay.Click += delegate
            {
                // Play used to launch straight into whatever save happened to
                // be newest, which on a shared save folder meant whoever
                // played last. Now it asks first.
                if (playing) { Play(); return; }
                charPickerOpen = !charPickerOpen;
                if (charPickerOpen) BuildChars();
                charBar.Visibility = charPickerOpen ? Visibility.Visible : Visibility.Collapsed;
                btnPlay.Content = charPickerOpen ? "Not yet" : "Play";
            };
            btnUpdate.Click += delegate { RunUpdate(); };
            btnInstallNow.Click += delegate { RunUpdate(); };

            chkKeepOpen.Click += delegate
            {
                cfg.KeepLauncherOpen = chkKeepOpen.IsChecked == true;
                cfg.Save(Paths.CfgFile);
            };

            btnVoiceTest.Click += delegate { DrawVoiceState(); };

            btnUninstall.Click += delegate { DoUninstall(); };

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

                int n = Checks.CloseGame();
                if (Checks.GameRunning()) { Log("Skyrim would not close. Restart your PC and try again."); return; }
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

            tabPlugins.Click += delegate { modTab = 0; BuildModList(); };
            tabSkse.Click += delegate { modTab = 1; BuildModList(); };
            tabMine.Click += delegate { modTab = 2; BuildModList(); };
            btnScan.Click += delegate { RunScan(); };
            btnFix.Click += delegate
            {
                int n = Verify.Fix();
                Log("Put back " + n + " list files from the shipped originals. Restart the game for it to take effect.");
                RunScan(); BuildModList(); DrawStatus();
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
            btnFolder.Click += delegate { Open(Paths.Root); };
            btnOpenLog.Click += delegate
            {
                if (File.Exists(Paths.LogFile)) Open(Paths.LogFile); else Log("Nothing has been logged yet.");
            };
            btnOpenSaves.Click += delegate { Open(Path.Combine(Paths.MyGames, "Saves")); };
            btnRepair.Click += delegate
            {
                Log("Restored " + Swap.RepairConfigs() + " settings files from the shipped originals.");
                DrawStatus(); BuildModList();
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
                if (playing)
                {
                    var r = MessageBox.Show(
                        "Skyrim is still running. Quit the game first, otherwise this session's saves end up in the wrong folder.\n\nClose the launcher anyway?",
                        "Thornswood", MessageBoxButton.YesNo, MessageBoxImage.Warning);
                    if (r != MessageBoxResult.Yes) { e.Cancel = true; return; }
                }
                if (timer != null) timer.Stop();
                Swap.Restore();
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
                if (Checks.GameRunning()) return;
                playing = false;
                Swap.Restore();
                Stats.StoppedPlaying(playStartedAt);
                // Against the character, not just the install. Skyrim keeps its
                // own play time inside the save, and under SkyMP the character
                // is a change form on the server with often no save here at all,
                // so the launcher is the only thing in a position to count.
                try { Chars.AddPlaytime(Chars.Active(), DateTime.Now - playStartedAt); } catch { }
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
                int broke = 0;
                try { foreach (Issue i in Verify.Run()) if (i.Blocking) broke++; } catch { }
                if (broke > 0)
                    Log("Skyrim changed your plugin list on the way out, " + broke +
                        (broke == 1 ? " problem" : " problems") + ". Mods, then Fix.");

                DrawStatus();
                win.WindowState = WindowState.Normal;
                win.Activate();
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

            int n = Checks.CloseGame();
            if (Checks.GameRunning())
            {
                Log("Skyrim would not close. Restart your PC and try again.");
                return false;
            }
            if (n > 0) Log("Closed " + n + " Skyrim process" + (n == 1 ? "" : "es") + " that was still open.");
            return true;
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
                if (!c.Ok) all = false;
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
                dot.Fill = Res(c.Ok ? "Ok" : "Bad");
                Grid.SetColumn(dot, 0); row.Children.Add(dot);

                var t1 = new TextBlock();
                t1.Text = c.Name; t1.FontSize = 13; t1.Foreground = Res("Ink");
                t1.VerticalAlignment = VerticalAlignment.Center;
                Grid.SetColumn(t1, 1); row.Children.Add(t1);

                var t2 = new TextBlock();
                t2.Text = c.Detail; t2.FontSize = 11.5;
                t2.VerticalAlignment = VerticalAlignment.Center;
                t2.Foreground = Res(c.Ok ? "Muted" : "Bad");
                Grid.SetColumn(t2, 2); row.Children.Add(t2);

                back.Child = row;
                statusList.Children.Add(back);
            }
            btnPlay.IsEnabled = all && !playing && !updatePending;
            // Only worth offering while there is something to quit, and it is
            // the one control on this page that stays live during a session.
            if (btnQuitGame != null)
                btnQuitGame.Visibility = Checks.GameRunning() ? Visibility.Visible : Visibility.Collapsed;
            if (updatePending && !playing)
            {
                btnPlay.Content = "UPDATE FIRST";
                btnPlay.ToolTip = "There is an update waiting. Install it and Play comes back.";
                if (charPickerOpen)
                {
                    charPickerOpen = false;
                    charBar.Visibility = Visibility.Collapsed;
                }
            }
            else if (!playing)
            {
                btnPlay.ToolTip = null;
                if (!charPickerOpen) btnPlay.Content = "PLAY";
            }
            return all;
        }

        // ------------------------------------------------------------- mods
        static void RunScan()
        {
            var issues = Verify.Run();
            int blocking = 0;
            foreach (Issue i in issues) if (i.Blocking) blocking++;

            if (issues.Count == 0)
            {
                dotVerify.Fill = Res("Ok");
                txtVerifyTitle.Text = "Everything matches";
                txtVerifyNote.Text = "Your plugin list is identical to the one the server expects.";
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
                txtVerifyNote.Text = sb.ToString();
                btnFix.IsEnabled = blocking > 0;
            }
            Log("Scan finished. " + issues.Count + " issue" + (issues.Count == 1 ? "" : "s") + " found.");
        }

        static void BuildModList()
        {
            if (modList == null) return;
            modList.Children.Clear();
            tabPlugins.Background = Res(modTab == 0 ? "CardHover" : "Card");
            tabSkse.Background    = Res(modTab == 1 ? "CardHover" : "Card");
            tabMine.Background    = Res(modTab == 2 ? "CardHover" : "Card");
            mineCard.Visibility   = modTab == 2 ? Visibility.Visible : Visibility.Collapsed;
            verifyCardVisible(modTab != 2);

            string filter = (boxSearch.Text == SearchHint) ? "" : boxSearch.Text.Trim().ToLowerInvariant();
            int shown = 0, total = 0, enabled = 0;

            if (modTab == 0)
            {
                string plug = Path.Combine(Paths.LocalAD, "plugins.txt");
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
                    modList.Children.Add(LinkedRow(index, name, true, kb + " KB"));
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
                    modList.Children.Add(ModRow(index, rel, !bad,
                        bad ? "PLUGIN, NOT ALLOWED" : kb + " KB",
                        delegate { Reveal(full); }, "Show this file in Explorer"));
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

        static void verifyCardVisible(bool on)
        {
            var c = win.FindName("VerifyCard") as UIElement;
            if (c != null) c.Visibility = on ? Visibility.Visible : Visibility.Collapsed;
        }

        // Plugin and DLL rows go to the mod's own page. Anything the catalogue
        // does not have a confirmed address for falls back to a Nexus search
        // for the name, which is honest about not knowing and still lands the
        // reader one click away. The Bethesda masters and the two Keizaal
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

        // A row in the mod list. When there is somewhere to send the reader,
        // the whole row becomes the link: hand cursor, a lift on hover, and an
        // arrow at the end so it reads as clickable before anyone hovers it.
        static UIElement ModRow(int index, string name, bool on, string tag, Action onClick, string hint)
        {
            var g = new Grid();
            g.Margin = new Thickness(0, 0, 0, 1);
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(42) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
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
            Grid.SetColumn(arrow, 3); g.Children.Add(arrow);

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
            BuildStatRow(); BuildNews(); BuildSaves(); BuildLogs(); BuildDisplay();
            BuildServer(); BuildInstalled(); BuildControls(); BuildDiag();
            boxSearch.Foreground = Res(boxSearch.Text == SearchHint ? "Faint" : "Ink");
        }

        static void BuildPathRows()
        {
            pathRows.Children.Clear();
            AddPathRow("Install", Paths.Root);
            AddPathRow("Game", Paths.Game);
            AddPathRow("Saves", Path.Combine(Paths.MyGames, "Saves"));
            AddPathRow("Settings", Paths.MyGames);
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
                    ? "Nothing posted yet. Anything Gavin writes to the update feed turns up here."
                    : "Updates are not set up on this copy, so there is no news feed to read.";
                empty.Foreground = Res("Faint"); empty.FontSize = 12.5;
                empty.TextWrapping = TextWrapping.Wrap;
                newsList.Children.Add(empty);
                return;
            }

            foreach (NewsItem n in items)
            {
                var sp = new StackPanel();

                if (!string.IsNullOrEmpty(n.date))
                {
                    var d = new TextBlock();
                    d.Text = n.date.ToUpperInvariant();
                    d.FontSize = 9.5; d.FontWeight = FontWeights.SemiBold;
                    d.Foreground = Res("Accent");
                    d.Margin = new Thickness(0, 0, 0, 6);
                    sp.Children.Add(d);
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

            if (!Display.Available)
            {
                txtDisplayNote.Text = "SSE Display Tweaks is not in this build, so there is nothing to set here.";
                boxResolution.IsEnabled = false; boxFrameLimit.IsEnabled = false;
                chkVSync.IsEnabled = false; btnSaveDisplay.IsEnabled = false;
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
            boxResolution.Text = res == null ? "" : res;

            Display.ScreenMode screen = Display.Detect();
            string note = "Resolution as 1920x1080, frame limit in frames per second. Blank resolution leaves it to the game.";
            if (screen != null)
            {
                note += "  Your screen is " + screen + (screen.Hz > 0 ? " at " + screen.Hz + " Hz" : "") + ".";
                if (res != null && !string.Equals(res, screen.ToString(), StringComparison.OrdinalIgnoreCase))
                    note += "  The game is set to something else, which is fine if you meant it.";
            }
            txtDisplayNote.Text = note;
            boxFrameLimit.Text = Display.GetInt("FramerateLimit", 0).ToString();
            chkVSync.IsChecked = Display.GetBool("EnableVSync", true);
            chkLockRes.IsChecked = cfg.LockResolution;
        }

        static void SaveDisplay()
        {
            if (!Display.Available) return;
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
                        IAsyncResult ar = c.BeginConnect(host, SkyMp.ResourcePort, null, null);
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
                int port = 7778;
                int.TryParse(c.VoicePort, out port);
                bool up = false;
                try
                {
                    using (var s = new System.Net.Sockets.TcpClient())
                    {
                        IAsyncResult ar = s.BeginConnect(c.ServerAddress, port, null, null);
                        if (ar.AsyncWaitHandle.WaitOne(900) && s.Connected) { s.EndConnect(ar); up = true; }
                    }
                }
                catch { }

                bool fUp = up;
                int fPort = port;
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
                            ? ("Running on " + c.ServerAddress + ":" + fPort +
                               ". It starts inside the game on its own." + keys)
                            : ("Not answering on " + c.ServerAddress + ":" + fPort +
                               ", so nobody will hear anybody. It is not installed on the server, or not running.");
                    }
                    catch { }
                }));
            });
        }

        // The probe waits on a socket, so it does not run on the thread that
        // draws. A settings page that freezes for most of a second every time
        // it is opened is worse than one that fills in a moment later.
        static void DoUninstall()
        {
            string why = Uninstall.WhyNot();
            if (why != null)
            {
                MessageBox.Show(why, "Thornswood", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }

            bool keep = chkKeepSaves.IsChecked == true;

            int files = 0;
            long bytes = Uninstall.Measure(Paths.Game, ref files);
            string size = bytes > 0 ? (bytes / 1024.0 / 1024.0 / 1024.0).ToString("0.0") + " GB" : "some space";

            var goes = new StringBuilder();
            goes.AppendLine("    " + Paths.Game + "   (" + size + ")");
            goes.AppendLine("    " + Paths.LauncherDir);
            goes.AppendLine("    " + Paths.Personal);
            if (!keep)
            {
                goes.AppendLine("    " + Paths.ProfileDir + "   (your characters and settings)");
                goes.AppendLine("    " + Paths.CfgFile);
            }

            var stays = new StringBuilder();
            if (keep)
            {
                stays.AppendLine("    " + Paths.ProfileDir + "   (your characters and settings)");
                stays.AppendLine("    " + Paths.CfgFile);
            }
            stays.AppendLine("    Your own Skyrim on Steam, and your own saves");

            var r1 = MessageBox.Show(
                "This removes:\n\n" + goes +
                "\nThis is left alone:\n\n" + stays +
                "\nWindows\u2019 Skyrim settings and saves folders are pointed back at your own copy " +
                "first. If that fails, nothing is deleted.\n\nContinue?",
                "Uninstall Thornswood", MessageBoxButton.YesNo, MessageBoxImage.Warning);
            if (r1 != MessageBoxResult.Yes) return;

            var r2 = MessageBox.Show(
                keep
                  ? "Last check. The game folder goes, your characters stay.\n\nThe launcher closes as it finishes."
                  : "Last check. Everything goes, including your characters, and none of it can be got back.\n\nThe launcher closes as it finishes.",
                "Uninstall Thornswood", MessageBoxButton.YesNo, MessageBoxImage.Warning);
            if (r2 != MessageBoxResult.Yes) return;

            btnUninstall.IsEnabled = false;
            try
            {
                string[] rest = Uninstall.Begin(keep, Log);
                Log("Handing the rest to Windows and closing...");
                Uninstall.Finish(rest, keep);
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

                string why = SkyMp.Start(cfg, Log);
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
                if (!File.Exists(Paths.Loader)) { Log("skse64_loader.exe is missing from this build."); return; }
                if (!File.Exists(Paths.MpClient)) { Log("MpClientPlugin.dll is missing, so this build has no multiplayer in it."); return; }

                // Starting a second one on top of a copy that never exited is
                // how people end up staring at a launcher that says the game is
                // running while their screen says otherwise.
                if (!ClearStuckGame(true)) return;

                // Checked again here, not just at startup, because the player's
                // own mods folder and the plugin list can both change in between.
                int blockers = 0;
                foreach (Issue i in Verify.Run()) if (i.Blocking) blockers++;
                if (blockers > 0)
                {
                    Log("Not launching. " + blockers + " problem" + (blockers == 1 ? "" : "s") + " with your mod list would desync everyone.");
                    RunScan();
                    DrawStatus();
                    ShowPage(PageMods);
                    MessageBox.Show(
                        "Your mod list does not match the one this build shipped with.\n\n" +
                        "Joining like this desyncs the whole server, so the launcher will not start the game until it is sorted.\n\n" +
                        "Press Fix on the Mods page, then try again.",
                        "Thornswood", MessageBoxButton.OK, MessageBoxImage.Warning);
                    return;
                }

                int mine = Verify.DeployPersonal();
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

                int held = Enforce.Apply(cfg);
                if (held > 0) Log("Put back " + held + " setting" + (held == 1 ? "" : "s") + " the last session overwrote.");

                // Written fresh every launch so the address and port the client
                // reads are whatever the launcher is showing. SkyMP has no join
                // screen: this file is the whole of joining.
                string join = AutoJoin.Apply(cfg);
                if (join != null) Log(join);

                if (!EnsureServer()) return;

                Log("Pointing Skyrim settings and saves at this build.");
                Swap.Apply();
                playing = true;
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
                Log("Starting the game.");

                try { File.WriteAllText(Paths.PlayedFile, DateTime.Now.ToString("o")); } catch { }
                playStartedAt = DateTime.Now;
                Stats.StartedPlaying();
                BuildStatRow();
                Thread.Sleep(1200);
                if (!cfg.KeepLauncherOpen) win.WindowState = WindowState.Minimized;
            }
            catch (Exception ex)
            {
                Log("Failed to start: " + ex.Message);
                Swap.Restore();
                playing = false;
                btnPlay.Content = "PLAY";
                DrawStatus();
            }
        }

        // ------------------------------------------------------------- updates
        // ------------------------------------------------------------- who is on
        static string pingText = "";

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
                }));
            });
        }

        // ------------------------------------------------------------- characters
        /// <summary>The name on a slot, or null. Chars keeps them in its list.</summary>
        static string SlotName(int slot)
        {
            try
            {
                foreach (Chars.Who w in Chars.All())
                {
                    if (w.Slot == slot) return string.IsNullOrEmpty(w.Name) ? null : w.Name;
                }
            }
            catch { }
            return null;
        }

        static void StartAs(int slot, bool fresh)
        {
            // A new character picks a trade and a town here, before anything
            // else happens. This used to be two message boxes inside the game,
            // fed by books the server put in your pack, and it depended on the
            // client and the server numbering their plugins identically. When
            // that slipped, which was often, you got a room with no menus and
            // no way out of it. Asked here it can be checked before the game
            // even starts.
            string trade = null, town = null;
            if (fresh)
            {
                if (!Creation.Ask(win, SlotName(slot), out trade, out town)) return;
            }

            try { Chars.Use(slot, fresh); }
            catch (Exception ex) { Log(ex.Message); return; }

            if (fresh)
            {
                int id = 0;
                try { id = Chars.ProfileOf(slot); } catch { }
                try { Chars.SetChoice(slot, trade, town); } catch { }
                string why = Creation.Send(cfg, id, trade, town, SlotName(slot));
                if (why == null)
                {
                    Log("You are starting as a " + trade + " in " + town + ".");
                }
                else
                {
                    // Not fatal. The server still has the books, so the old
                    // flow takes over rather than nothing happening.
                    Log("Could not tell the server your choice (" + why +
                        "). It will ask you in game instead.");
                }
            }

            charPickerOpen = false;
            charBar.Visibility = Visibility.Collapsed;
            btnPlay.Content = "Play";
            Log(fresh ? "Starting a new character in slot " + slot + "."
                      : "Loading character " + slot + ".");
            Play();
        }

        static void ForgetChar(int slot, Chars.Who who)
        {
            if (Checks.GameRunning()) { Log("Close Skyrim first."); return; }

            string name = string.IsNullOrEmpty(who.Name) ? "this character" : who.Name;
            var answer = MessageBox.Show(
                "Delete " + name + "?\n\n" +
                who.Saves + (who.Saves == 1 ? " save" : " saves") + " will be moved into Profile\\Characters\\_deleted.\n" +
                "Nothing is destroyed, so this can be undone by hand if you change your mind.",
                "Thornswood", MessageBoxButton.YesNo, MessageBoxImage.Question);
            if (answer != MessageBoxResult.Yes) return;

            try
            {
                string moved = Chars.Delete(slot);
                Log(moved == null ? "That slot was already empty."
                                  : name + " moved to " + System.IO.Path.GetFileName(moved) + ".");
            }
            catch (Exception ex) { Log("Could not delete that character: " + ex.Message); }
            BuildChars();
        }

        /// <summary>
        /// The line under a character's name.
        ///
        /// Three sources, in order of how much they know. The server holds the
        /// race, the sex and the trade, because all three are settled after the
        /// game has started and the character is a change form up there rather
        /// than a file down here. The launcher holds the trade and the town it
        /// asked for, which is what to show before the first session has been
        /// played. A local save, when there is one, holds a race and a level.
        ///
        /// The profile id is last and quiet. It is the thing that actually picks
        /// the character so it is worth being able to read, but on its own it
        /// told nobody anything, which is what this is fixing.
        /// </summary>
        static string DescribeChar(Chars.Who w, bool isActive)
        {
            var bits = new List<string>();

            Roster.Row r = null;
            try { r = Roster.For(w.ProfileId); } catch { }

            string fromServer = Roster.Describe(r);
            if (fromServer.Length > 0)
            {
                bits.Add(fromServer);
            }
            else
            {
                // Nothing from the server yet. Everything that is known here.
                if (!string.IsNullOrEmpty(w.Race)) bits.Add(w.Race);
                string trade = Creation.LabelOf(Creation.Trades, w.Trade);
                string town = Creation.LabelOf(Creation.Towns, w.Town);
                if (trade.Length > 0 && town.Length > 0) bits.Add(trade + " in " + town);
                else if (trade.Length > 0) bits.Add(trade);
                else if (town.Length > 0) bits.Add("started in " + town);
            }

            if (w.Level > 0) bits.Add("level " + w.Level);

            string played = Chars.PlayedText(w.PlaySeconds);
            if (played.Length > 0) bits.Add(played);
            else if (bits.Count > 0) bits.Add("not played yet");

            if (w.ProfileId > 0) bits.Add("profile " + w.ProfileId);

            if (bits.Count == 0) return "on the server, nothing known here yet";

            string line = string.Join(",  ", bits.ToArray());
            if (isActive) line += "   ·   last played";
            return line;
        }

        // Asked when the cards are drawn rather than on a timer. The answer only
        // changes when somebody plays, and a launcher sitting open all evening
        // has no reason to keep asking.
        static void RefreshRoster()
        {
            if (Roster.Fresh) return;
            ThreadPool.QueueUserWorkItem(delegate
            {
                bool moved = false;
                try { moved = Roster.Refresh(cfg); } catch { }
                if (!moved) return;
                try
                {
                    win.Dispatcher.BeginInvoke(new Action(delegate { BuildChars(); }));
                }
                catch { }
            });
        }

        static void BuildChars()
        {
            if (charRow == null) return;
            RefreshRoster();
            charRow.Children.Clear();

            int active = Chars.Active();
            if (txtCharNote != null)
            {
                txtCharNote.Text =
                    "Skyrim opens on its own menu and then walks in by itself once the server has your character. " +
                    "That takes a few seconds. Nothing to press.";
            }
            foreach (Chars.Who w in Chars.All())
            {
                int slot = w.Slot;
                Chars.Who who = w;

                var card = new Border();
                card.Style = (Style)win.Resources["Slab"];
                card.Padding = new Thickness(18, 14, 18, 14);
                card.Margin = new Thickness(0, 0, 0, 10);

                var row = new StackPanel();
                row.Orientation = Orientation.Horizontal;

                var left = new StackPanel();
                left.MinWidth = 320;

                var title = new TextBlock();
                title.Text = w.Empty ? "Empty slot"
                           : (string.IsNullOrEmpty(w.Name) ? "Character " + slot : w.Name);
                title.FontSize = 15;
                title.FontWeight = FontWeights.SemiBold;
                title.Foreground = Res(w.Empty ? "Faint" : "Ink");
                left.Children.Add(title);

                var sub = new TextBlock();
                sub.Text = w.Empty ? "Nobody here yet" : DescribeChar(w, slot == active);
                sub.FontSize = 11.5;
                sub.Foreground = Res("Muted");
                sub.TextWrapping = TextWrapping.Wrap;
                sub.Margin = new Thickness(0, 3, 0, 0);
                left.Children.Add(sub);

                row.Children.Add(left);

                var go = new Button();
                go.Style = (Style)win.Resources["Solid"];
                go.Content = w.Empty ? "Make a character" : "Play";
                go.Margin = new Thickness(18, 0, 0, 0);
                bool fresh = w.Empty;
                go.Click += delegate { StartAs(slot, fresh); };
                row.Children.Add(go);

                if (!w.Empty)
                {
                    var del = new Button();
                    del.Style = (Style)win.Resources["Ghost"];
                    del.Content = "Delete";
                    del.Margin = new Thickness(8, 0, 0, 0);
                    del.Click += delegate { ForgetChar(slot, who); };
                    row.Children.Add(del);
                }

                card.Child = row;
                charRow.Children.Add(card);
            }
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

        static void CheckUpdatesBackground(bool loud)
        {
            try
            {
                VersionDoc v = Updater.Check(cfg);
                if (v == null) return;
                win.Dispatcher.BeginInvoke(new Action(delegate { OnVersionDoc(v, loud); }));
            }
            catch (Exception ex)
            {
                win.Dispatcher.BeginInvoke(new Action(delegate { Log("Update check failed: " + ex.Message); }));
            }
        }

        static void OnVersionDoc(VersionDoc v, bool loud)
        {
            pendingDoc = v;

            bool moved = false;
            if (!string.IsNullOrEmpty(v.serverAddress) && v.serverAddress != cfg.ServerAddress) { cfg.ServerAddress = v.serverAddress; moved = true; }
            if (!string.IsNullOrEmpty(v.serverPort) && v.serverPort != cfg.ServerPort) { cfg.ServerPort = v.serverPort; moved = true; }
            if (v.maxOnline > 0 && v.maxOnline != cfg.MaxOnline) { cfg.MaxOnline = v.maxOnline; moved = true; }
            if (moved)
            {
                cfg.Save(Paths.CfgFile);
                PaintServerBoxes();
                Log("The server moved. The launcher already has the new address.");
                StartPing();
            }

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
            if (quiet)
            {
                cfg.Save(Paths.CfgFile);
                if (txtUpdateSource != null) txtUpdateSource.Text = Updater.WhyDisabled(cfg);
                DrawVoiceState();
            }
            if (!string.IsNullOrEmpty(v.message)) Log(v.message);
            BuildNews();

            pendingPacks = Updater.Pending(v);
            bool newLauncher = Updater.IsNewer(v.launcherVersion, Updater.Version)
                               && !string.IsNullOrEmpty(v.launcherUrl);

            if (pendingPacks.Count == 0 && !newLauncher)
            {
                updateBar.Visibility = Visibility.Collapsed;
                btnInstallNow.Visibility = Visibility.Collapsed;
                updatePending = false;
                DrawStatus();
                if (loud || !moved) Log("Up to date.");
                return;
            }
            updatePending = true;
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
        }

        static void RunUpdate()
        {
            if (playing) { Log("Quit the game first."); return; }
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
