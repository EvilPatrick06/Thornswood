using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net.NetworkInformation;
using System.Reflection;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Markup;
using System.Windows.Media;
using Ellipse = System.Windows.Shapes.Ellipse;   // not the namespace: System.Windows.Shapes.Path would collide with System.IO.Path
using System.Windows.Threading;

namespace SkyrimTogether
{
    static class Shell
    {
        static Window win;
        static Config cfg;
        static VersionDoc pendingDoc;
        static List<Pack> pendingPacks = new List<Pack>();
        static bool playing, selfUpdateOffered;
        static int modTab;   // 0 server plugins, 1 script extender, 2 your own
        static DispatcherTimer timer;

        static TextBlock txtServer, txtPing, txtStatus, txtStatusRight, txtVersion, txtBuildLine,
                         txtUpdateTitle, txtUpdateNote, txtModCount, txtUpdateSource,
                         txtPageTitle, txtHeroLine, txtVerifyTitle, txtVerifyNote;
        static Ellipse dotServer, dotVerify;
        static StackPanel statusList, modList, themeRow, pathRows, helpList;
        static TextBox boxSearch, boxAddress, boxPort;
        static CheckBox chkAutoUpdate;
        static Border updateBar, mineCard;
        static Grid titleBar;
        static Button btnPlay, btnRecheck, btnCopy, btnUpdate, btnMin, btnMax, btnClose,
                      btnSaveServer, btnCheckNow, btnFolder, btnOpenLog, btnOpenSaves,
                      btnRepair, btnRestore, tabPlugins, tabSkse, tabMine,
                      btnScan, btnFix, btnOpenMine, btnRefreshMine;
        static Button[] navButtons;
        static UIElement[] pages;

        const string SearchHint = "Search";

        [STAThread]
        static void Main(string[] args)
        {
            bool fresh;
            using (var mutex = new Mutex(true, "SkyrimTogetherLauncher", out fresh))
            {
                if (!fresh) return;
                try { Run(args); }
                catch (Exception ex)
                {
                    MessageBox.Show(ex.ToString(), "Skyrim Together could not start",
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

            string xaml;
            using (var s = Assembly.GetExecutingAssembly().GetManifestResourceStream("ui.xaml"))
            using (var r = new StreamReader(s))
                xaml = r.ReadToEnd();
            win = (Window)XamlReader.Parse(xaml);

            Bind();
            Themes.Apply(win, cfg.Theme);
            Wire();
            BuildThemeRow();
            BuildPathRows();
            BuildHelp();
            BuildModList();
            ShowPage(0);

            if (Swap.Restore()) Log("Cleaned up a redirect left behind by a crash.");
            RunScan();
            if (DrawStatus()) Log("Ready."); else Log("Something needs attention before you can play.");
            StartPing();
            if (cfg.AutoUpdate && Updater.Enabled(cfg))
                ThreadPool.QueueUserWorkItem(delegate { CheckUpdatesBackground(false); });

            new Application().Run(win);
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
            dotServer = F<Ellipse>("DotServer"); dotVerify = F<Ellipse>("DotVerify");
            mineCard = F<Border>("MineCard");
            statusList = F<StackPanel>("StatusList"); modList = F<StackPanel>("ModList");
            themeRow = F<StackPanel>("ThemeRow"); pathRows = F<StackPanel>("PathRows");
            helpList = F<StackPanel>("HelpList");
            boxSearch = F<TextBox>("BoxSearch"); boxAddress = F<TextBox>("BoxAddress"); boxPort = F<TextBox>("BoxPort");
            chkAutoUpdate = F<CheckBox>("ChkAutoUpdate");
            updateBar = F<Border>("UpdateBar"); titleBar = F<Grid>("TitleBar");

            btnPlay = F<Button>("BtnPlay"); btnRecheck = F<Button>("BtnRecheck"); btnCopy = F<Button>("BtnCopy");
            btnUpdate = F<Button>("BtnUpdate"); btnMin = F<Button>("BtnMin"); btnMax = F<Button>("BtnMax");
            btnClose = F<Button>("BtnClose"); btnSaveServer = F<Button>("BtnSaveServer");
            btnCheckNow = F<Button>("BtnCheckNow"); btnFolder = F<Button>("BtnFolder");
            btnOpenLog = F<Button>("BtnOpenLog"); btnOpenSaves = F<Button>("BtnOpenSaves");
            btnRepair = F<Button>("BtnRepair"); btnRestore = F<Button>("BtnRestore");
            tabPlugins = F<Button>("TabPlugins"); tabSkse = F<Button>("TabSkse"); tabMine = F<Button>("TabMine");
            btnScan = F<Button>("BtnScan"); btnFix = F<Button>("BtnFix");
            btnOpenMine = F<Button>("BtnOpenMine"); btnRefreshMine = F<Button>("BtnRefreshMine");

            navButtons = new Button[] { F<Button>("NavPlay"), F<Button>("NavMods"), F<Button>("NavSettings"), F<Button>("NavHelp") };
            pages = new UIElement[] { F<Grid>("PagePlay"), F<Grid>("PageMods"), F<Grid>("PageSettings"), F<Grid>("PageHelp") };
        }

        static Brush Res(string key) { return (Brush)win.Resources[key]; }

        static void Log(string m)
        {
            txtStatus.Text = m;
            try { File.AppendAllText(Paths.LogFile, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + m + Environment.NewLine); }
            catch { }
        }

        // ------------------------------------------------------------- pages
        static readonly string[] PageTitles = { "PLAY", "MODS", "SETTINGS", "HELP" };

        static void ShowPage(int i)
        {
            for (int k = 0; k < pages.Length; k++)
            {
                pages[k].Visibility = (k == i) ? Visibility.Visible : Visibility.Collapsed;
                navButtons[k].Tag = (k == i) ? "on" : "off";
            }
            txtPageTitle.Text = PageTitles[i];
            if (i == 1) BuildModList();
        }

        static void Wire()
        {
            txtServer.Text = cfg.ServerAddress + ":" + cfg.ServerPort;
            boxAddress.Text = cfg.ServerAddress;
            boxPort.Text = cfg.ServerPort;
            chkAutoUpdate.IsChecked = cfg.AutoUpdate;
            txtVersion.Text = "launcher " + Updater.Version;
            txtUpdateSource.Text = Updater.WhyDisabled(cfg);
            boxSearch.Text = SearchHint;
            boxSearch.Foreground = Res("Faint");

            long bytes = 0;
            try { if (File.Exists(Paths.Exe)) bytes = new FileInfo(Paths.Exe).Length; } catch { }
            txtBuildLine.Text = (bytes == cfg.ExpectedExeBytes ? "game 1.6.1170" : "game unknown");
            txtStatusRight.Text = Paths.Root;
            txtHeroLine.Text = Checks.EnabledPlugins() + " plugins  ·  build 1.6.1170  ·  " + cfg.ServerAddress;

            try
            {
                var ico = System.Drawing.Icon.ExtractAssociatedIcon(
                    File.Exists(Paths.Exe) ? Paths.Exe : Assembly.GetExecutingAssembly().Location);
                win.Icon = System.Windows.Interop.Imaging.CreateBitmapSourceFromHIcon(
                    ico.Handle, Int32Rect.Empty,
                    System.Windows.Media.Imaging.BitmapSizeOptions.FromEmptyOptions());
            }
            catch { }

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

            btnCopy.Click += delegate
            {
                try { Clipboard.SetText(cfg.ServerAddress + ":" + cfg.ServerPort); Log("Server address copied to the clipboard."); }
                catch { Log("Could not reach the clipboard."); }
            };
            btnRecheck.Click += delegate
            {
                Log(DrawStatus() ? "Everything checks out." : "Something is still off, see the red rows.");
                StartPing();
            };
            btnPlay.Click += delegate { Play(); };
            btnUpdate.Click += delegate { RunUpdate(); };

            tabPlugins.Click += delegate { modTab = 0; BuildModList(); };
            tabSkse.Click += delegate { modTab = 1; BuildModList(); };
            tabMine.Click += delegate { modTab = 2; BuildModList(); };
            btnScan.Click += delegate { RunScan(); };
            btnFix.Click += delegate
            {
                int n = Verify.Fix();
                Log("Put back " + n + " list files from the shipped originals. Restart the game for it to take effect.");
                RunScan(); BuildModList();
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

            btnSaveServer.Click += delegate
            {
                string a = boxAddress.Text.Trim(), p = boxPort.Text.Trim();
                if (a.Length == 0) { Log("Server address cannot be empty."); return; }
                cfg.ServerAddress = a;
                cfg.ServerPort = p.Length > 0 ? p : "25565";
                cfg.Save(Paths.CfgFile);
                txtServer.Text = cfg.ServerAddress + ":" + cfg.ServerPort;
                Log("Server saved as " + txtServer.Text);
                StartPing();
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

            win.Closing += delegate(object s, System.ComponentModel.CancelEventArgs e)
            {
                if (playing)
                {
                    var r = MessageBox.Show(
                        "Skyrim is still running. Quit the game first, otherwise this session's saves end up in the wrong folder.\n\nClose the launcher anyway?",
                        "Skyrim Together", MessageBoxButton.YesNo, MessageBoxImage.Warning);
                    if (r != MessageBoxResult.Yes) { e.Cancel = true; return; }
                }
                if (timer != null) timer.Stop();
                Swap.Restore();
            };

            timer = new DispatcherTimer();
            timer.Interval = TimeSpan.FromSeconds(2);
            timer.Tick += delegate
            {
                if (!playing) return;
                if (Checks.GameRunning()) return;
                playing = false;
                Swap.Restore();
                btnPlay.Content = "PLAY";
                Log("Game closed. Your Windows Skyrim folders are back to normal.");
                DrawStatus();
                win.WindowState = WindowState.Normal;
                win.Activate();
            };
            timer.Start();
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
            btnPlay.IsEnabled = all && !playing;
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
                    modList.Children.Add(ModRow(index, name, true, Path.GetExtension(name).TrimStart('.').ToUpperInvariant()));
                    shown++;
                }
                int off = total - enabled;
                txtModCount.Text = enabled + " plugins, in the order the server expects them." +
                                   (off > 0 ? "   ·   " + off + " switched off and not shown" : "") +
                                   (filter.Length > 0 ? "   ·   showing " + shown : "");
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
                    modList.Children.Add(ModRow(index, name, true, kb + " KB"));
                    shown++;
                }
                txtModCount.Text = total + " script extender plugins. The server never sees these." +
                                   (filter.Length > 0 ? "   ·   showing " + shown : "");
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
                    modList.Children.Add(ModRow(index, rel, !bad, bad ? "PLUGIN, NOT ALLOWED" : kb + " KB"));
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

        static UIElement ModRow(int index, string name, bool on, string tag)
        {
            var g = new Grid();
            g.Margin = new Thickness(0, 0, 0, 1);
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(42) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            var idx = new TextBlock();
            idx.Text = index.ToString();
            idx.FontFamily = new FontFamily("Consolas");
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
            tg.FontFamily = new FontFamily("Consolas");
            tg.FontSize = 10.5;
            tg.Foreground = Res(on ? "Muted" : "Bad");
            tg.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(tg, 2); g.Children.Add(tg);

            var b = new Border();
            b.Padding = new Thickness(10, 8, 12, 8);
            b.Background = Res("Panel");
            b.Margin = new Thickness(0, 0, 8, 3);
            b.Child = g;
            return b;
        }

        // ------------------------------------------------------------- settings
        static void BuildThemeRow()
        {
            themeRow.Children.Clear();
            foreach (Theme t in Themes.All)
            {
                Theme captured = t;
                var sw = new Border();
                sw.Width = 22; sw.Height = 22;
                sw.Background = new SolidColorBrush((Color)ColorConverter.ConvertFromString(t.Swatch));
                sw.Margin = new Thickness(0, 0, 9, 0);

                var label = new TextBlock();
                label.Text = t.Name; label.VerticalAlignment = VerticalAlignment.Center;

                var sp = new StackPanel();
                sp.Orientation = Orientation.Horizontal;
                sp.Children.Add(sw);
                sp.Children.Add(label);

                var b = new Button();
                b.Content = sp;
                b.Style = (Style)win.Resources["Ghost"];
                b.Margin = new Thickness(0, 0, 10, 0);
                b.Padding = new Thickness(11, 8, 15, 8);
                if (string.Equals(t.Name, cfg.Theme, StringComparison.OrdinalIgnoreCase))
                    b.Background = Res("CardHover");
                b.Click += delegate
                {
                    cfg.Theme = captured.Name;
                    cfg.Save(Paths.CfgFile);
                    Themes.Apply(win, captured.Name);
                    BuildThemeRow(); BuildModList(); DrawStatus(); BuildPathRows(); BuildHelp();
                    boxSearch.Foreground = Res(boxSearch.Text == SearchHint ? "Faint" : "Ink");
                    Log("Theme set to " + captured.Name + ".");
                };
                themeRow.Children.Add(b);
            }
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
            v.Text = value; v.FontSize = 11.5; v.FontFamily = new FontFamily("Consolas");
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

        // ------------------------------------------------------------- ping
        static void StartPing()
        {
            txtPing.Text = "checking";
            dotServer.Fill = Res("Faint");
            try
            {
                var p = new Ping();
                p.PingCompleted += delegate(object s, PingCompletedEventArgs e)
                {
                    win.Dispatcher.BeginInvoke(new Action(delegate
                    {
                        bool up = e.Error == null && !e.Cancelled && e.Reply != null && e.Reply.Status == IPStatus.Success;
                        if (up) { txtPing.Text = e.Reply.RoundtripTime + " ms"; dotServer.Fill = Res("Ok"); }
                        else { txtPing.Text = "no reply"; dotServer.Fill = Res("Warn"); }
                    }));
                };
                p.SendAsync(cfg.ServerAddress, 2000, null);
            }
            catch { txtPing.Text = "not tested"; }
        }

        // ------------------------------------------------------------- play
        static void Play()
        {
            try
            {
                if (!File.Exists(Paths.Str)) { Log("SkyrimTogether.exe is missing from this build."); return; }

                // Checked again here, not just at startup, because the player's
                // own mods folder and the plugin list can both change in between.
                int blockers = 0;
                foreach (Issue i in Verify.Run()) if (i.Blocking) blockers++;
                if (blockers > 0)
                {
                    Log("Not launching. " + blockers + " problem" + (blockers == 1 ? "" : "s") + " with your mod list would desync everyone.");
                    RunScan();
                    DrawStatus();
                    ShowPage(1);
                    MessageBox.Show(
                        "Your mod list does not match the one this build shipped with.\n\n" +
                        "Joining like this desyncs the whole server, so the launcher will not start the game until it is sorted.\n\n" +
                        "Press Fix on the Mods page, then try again.",
                        "Skyrim Together", MessageBoxButton.OK, MessageBoxImage.Warning);
                    return;
                }

                int mine = Verify.DeployPersonal();
                if (mine > 0) Log("Copied in " + mine + " of your own files.");
                Log("Pointing Skyrim settings and saves at this build.");
                Swap.Apply();
                playing = true;
                btnPlay.IsEnabled = false;
                btnPlay.Content = "RUNNING";

                // Working directory must be the game root. Address Library
                // resolves Data/SKSE/Plugins/versionlib-*.bin relative to it.
                var psi = new ProcessStartInfo(Paths.Str);
                psi.WorkingDirectory = Paths.Game;
                psi.UseShellExecute = true;
                Process.Start(psi);
                Log("Starting the game.");

                try { File.WriteAllText(Paths.PlayedFile, DateTime.Now.ToString("o")); } catch { }
                Thread.Sleep(1200);
                win.WindowState = WindowState.Minimized;
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
            if (moved)
            {
                cfg.Save(Paths.CfgFile);
                txtServer.Text = cfg.ServerAddress + ":" + cfg.ServerPort;
                boxAddress.Text = cfg.ServerAddress; boxPort.Text = cfg.ServerPort;
                Log("Server address changed to " + txtServer.Text);
                StartPing();
            }
            if (!string.IsNullOrEmpty(v.message)) Log(v.message);

            pendingPacks = Updater.Pending(v);
            bool newLauncher = !string.IsNullOrEmpty(v.launcherVersion)
                               && v.launcherVersion != Updater.Version
                               && !string.IsNullOrEmpty(v.launcherUrl);

            if (pendingPacks.Count == 0 && !newLauncher)
            {
                updateBar.Visibility = Visibility.Collapsed;
                if (loud || !moved) Log("Up to date.");
                return;
            }

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
            Log("Update available.");
        }

        static void RunUpdate()
        {
            if (playing) { Log("Quit the game first."); return; }
            btnUpdate.IsEnabled = false;
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
                    foreach (Pack p in packs) Updater.ApplyPack(cfg, p, log);

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
                        btnUpdate.IsEnabled = true;
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
                        DrawStatus();
                    }));
                }
            });
        }
    }
}
