using System;
using System.Collections.Generic;
using System.IO;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Ellipse = System.Windows.Shapes.Ellipse;
using Rectangle = System.Windows.Shapes.Rectangle;

namespace Thornswood
{
    // The four pages that are only ever read, never operated: the server, what
    // is installed, the controls, and what the launcher can see about this
    // machine. They live apart from Shell.cs because none of them share
    // anything with the pages that do work, and Shell.cs was long enough.
    static partial class Shell
    {
        static TextBlock txtSrvAddress, txtSrvState, txtSrvPingNote,
                         txtBuildHead, txtBuildSummary, txtDiagNote, txtThemeNote;
        static StackPanel srvPingBars, srvRows, buildBars, buildRows, controlsList, diagReadings, diagCollection, diagAddons;
        static Button btnSrvCopy, btnSrvRetest, btnBuildRefresh, btnDiagBundle, btnDiagOpen;

        // -1 marks a test that got no answer, which is worth drawing as a gap
        // rather than dropping, because a row of gaps is the actual diagnosis.
        static readonly List<long> pingHistory = new List<long>();
        static bool serverUp;
        static int pingTicks;

        static void BindPages()
        {
            txtSrvAddress = F<TextBlock>("TxtSrvAddress"); txtSrvState = F<TextBlock>("TxtSrvState");
            txtSrvPingNote = F<TextBlock>("TxtSrvPingNote");
            txtBuildHead = F<TextBlock>("TxtBuildHead"); txtBuildSummary = F<TextBlock>("TxtBuildSummary");
            txtDiagNote = F<TextBlock>("TxtDiagNote"); txtThemeNote = F<TextBlock>("TxtThemeNote");
            srvPingBars = F<StackPanel>("SrvPingBars"); srvRows = F<StackPanel>("SrvRows");
            buildBars = F<StackPanel>("BuildBars"); buildRows = F<StackPanel>("BuildRows");
            controlsList = F<StackPanel>("ControlsList"); diagReadings = F<StackPanel>("DiagReadings");
            diagCollection = F<StackPanel>("DiagCollection");
            diagAddons = F<StackPanel>("DiagAddons");
            btnSrvCopy = F<Button>("BtnSrvCopy"); btnSrvRetest = F<Button>("BtnSrvRetest");
            btnBuildRefresh = F<Button>("BtnBuildRefresh");
            btnDiagBundle = F<Button>("BtnDiagBundle"); btnDiagOpen = F<Button>("BtnDiagOpen");
        }

        static void WirePages()
        {
            // Nobody needs the address. The launcher does the connecting, and an
            // address on screen is only ever one screenshot away from being
            // somewhere it should not be. It stays in config.json where it is
            // needed and off every page where it is not.
            btnSrvCopy.Visibility = Visibility.Collapsed;
            btnSrvRetest.Click += delegate { StartPing(); Log("Testing the server."); };
            btnBuildRefresh.Click += delegate { buildSizes = null; BuildInstalled(); };
            btnDiagOpen.Click += delegate
            {
                Directory.CreateDirectory(Diag.ReportDir);
                Open(Diag.ReportDir);
            };
            btnDiagBundle.Click += delegate { MakeReport(); };
        }

        // serving: the resources port accepted a connection, which is the only
        // thing that proves a server is actually running rather than the host
        // merely being switched on.
        static bool serverServing;

        static void RecordPing(long ms) { RecordPing(ms, false); }

        static void RecordPing(long ms, bool serving)
        {
            pingHistory.Add(ms);
            while (pingHistory.Count > 40) pingHistory.RemoveAt(0);
            serverUp = ms >= 0;
            serverServing = serving;
            if (pages != null && pages[PageServer].Visibility == Visibility.Visible) BuildServer();
        }

        // ----------------------------------------------------------- server
        static void BuildServer()
        {
            if (srvRows == null) return;

            txtSrvAddress.Text = "ThornsWood";

            // The voice card lives on this page now, so it is re-tested
            // whenever the page is opened rather than only at startup.
            DrawVoiceState();

            long last = pingHistory.Count > 0 ? pingHistory[pingHistory.Count - 1] : -2;
            if (last == -2) txtSrvState.Text = "Not tested yet.";
            else if (last < 0) txtSrvState.Text = "Nothing answered. The server is not running, or nothing can reach it from here.";
            else if (serverServing) txtSrvState.Text = "Up and serving, " + last + " ms away.";
            else txtSrvState.Text = "The machine answered in " + last + " ms, but the server is not listening on it. It is probably not running.";
            txtSrvState.Foreground = Res(last == -2 ? "Faint" : last < 0 ? "Warn" : serverServing ? "Muted" : "Warn");

            DrawPingBars();

            srvRows.Children.Clear();
            srvRows.Children.Add(Fact("Status",
                last == -2 ? "not tested yet"
                : last < 0 ? "no answer"
                : serverServing ? "up" : "reachable, but not serving", false));
            srvRows.Children.Add(Fact("Joining",
                cfg.AutoJoin ? "the launcher writes the address in before the game starts, and it connects on its own"
                             : "off, so the game will not connect", false));

            long best = long.MaxValue, worst = 0; int answered = 0;
            foreach (long p in pingHistory) { if (p < 0) continue; answered++; if (p < best) best = p; if (p > worst) worst = p; }
            srvRows.Children.Add(Fact("Best round trip", answered > 0 ? best + " ms" : "not measured", false));
            srvRows.Children.Add(Fact("Worst round trip", answered > 0 ? worst + " ms" : "not measured", false));
            srvRows.Children.Add(Fact("Tests answered",
                pingHistory.Count == 0 ? "none yet" : answered + " of " + pingHistory.Count, false));
        }

        static void DrawPingBars()
        {
            srvPingBars.Children.Clear();
            if (pingHistory.Count == 0)
            {
                txtSrvPingNote.Text = "Nothing measured yet. The launcher tests the server every half minute while it is open.";
                return;
            }

            long top = 40;
            foreach (long p in pingHistory) if (p > top) top = p;

            foreach (long p in pingHistory)
            {
                var col = new StackPanel();
                col.Width = 13;
                col.VerticalAlignment = VerticalAlignment.Bottom;

                var r = new Rectangle();
                r.Width = 7;
                r.HorizontalAlignment = HorizontalAlignment.Center;
                if (p < 0)
                {
                    r.Height = 3;
                    r.Fill = Res("Bad");
                }
                else
                {
                    r.Height = Math.Max(3, 64.0 * p / top);
                    r.Fill = Res(p < 90 ? "Ok" : p < 180 ? "Warn" : "Bad");
                }
                col.Children.Add(r);
                srvPingBars.Children.Add(col);
            }

            txtSrvPingNote.Text = "Newest on the right, one bar per test, tallest bar is " + top + " ms. "
                                + "Under 90 ms is comfortable, over 180 and you will feel it.";
        }

        // ------------------------------------------------------ what is installed
        class Slice { public string Name; public long Bytes; }
        static List<Slice> buildSizes;
        static bool buildCounting;

        static void BuildInstalled()
        {
            if (buildRows == null) return;

            int plugins = Checks.EnabledPlugins();
            // The game's facts come from Paths.Skyrim, which is the Steam copy
            // while the own folder is chosen and not made: Paths.Game is then
            // Profile\Payload, and read there the game and the script extender
            // were "missing" until the folder was made (#1235).
            int skse = 0;
            try
            {
                var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                foreach (string d in Paths.SksePluginDirs)
                    if (Directory.Exists(d))
                        foreach (string f in Directory.GetFiles(d, "*.dll")) names.Add(Path.GetFileName(f));
                skse = names.Count;
            }
            catch (Exception ex) { Swallow.Note("Pages.BuildInstalled, SKSE plugins", ex); }

            txtBuildHead.Text = plugins + " plugins and " + skse + " script extender plugins";
            txtBuildSummary.Text = "Everything here was installed by the setup program and is kept in step by the launcher. "
                                 + "Nothing in this folder is shared with your own Skyrim, which is why your other mods keep working.";

            buildRows.Children.Clear();
            long exe = 0;
            try { exe = new FileInfo(Paths.SkyrimExe).Length; } catch (Exception ex) { Swallow.Note("Pages.BuildInstalled, game exe size", ex); }
            buildRows.Children.Add(Fact("Skyrim", exe == cfg.ExpectedExeBytes ? "1.6.1170, the version the mods expect" : "not the expected build", false));
            buildRows.Children.Add(Fact("Script extender",
                File.Exists(Path.Combine(Paths.Skyrim, "skse64_1_6_1170.dll")) ? "skse64 2.2.6" : "missing", false));
            buildRows.Children.Add(Fact("Multiplayer client", File.Exists(Paths.MpClient) ? "SkyMP" : "missing", false));
            buildRows.Children.Add(Fact("Plugins the server sees", plugins.ToString(), false));
            buildRows.Children.Add(Fact("Script extender plugins", skse.ToString(), false));

            int mine = 0;
            try { mine = Verify.PersonalFiles().Length; } catch (Exception ex) { Swallow.Note("Pages.BuildInstalled, PersonalFiles", ex); }
            buildRows.Children.Add(Fact("Files of your own", mine == 0 ? "none" : mine.ToString(), false));
            buildRows.Children.Add(Fact("Last update", string.IsNullOrEmpty(Stats.LastUpdate) ? "never" : Stats.LastUpdate, false));
            buildRows.Children.Add(Fact("Installed at", Paths.Root, true));

            DrawBuildBars();
        }

        static void DrawBuildBars()
        {
            buildBars.Children.Clear();

            if (buildSizes == null)
            {
                var note = new TextBlock();
                note.Text = buildCounting ? "Counting..." : "Adding up about 27,000 files. This takes a moment.";
                note.Foreground = Res("Faint"); note.FontSize = 12;
                buildBars.Children.Add(note);
                if (!buildCounting) StartSizeCount();
                return;
            }

            long total = 0;
            foreach (Slice s in buildSizes) total += s.Bytes;
            if (total <= 0) total = 1;

            foreach (Slice s in buildSizes)
                buildBars.Children.Add(Bar(s.Name, Human(s.Bytes), (double)s.Bytes / total));

            var sum = new TextBlock();
            sum.Text = Human(total) + " in total";
            sum.Foreground = Res("Muted"); sum.FontSize = 12;
            sum.Margin = new Thickness(0, 12, 0, 0);
            buildBars.Children.Add(sum);
        }

        static void StartSizeCount()
        {
            buildCounting = true;
            ThreadPool.QueueUserWorkItem(delegate
            {
                var found = new List<Slice>();
                try
                {
                    string data = Path.Combine(Paths.Game, "Data");
                    if (Directory.Exists(data))
                    {
                        long loose = 0;
                        foreach (string f in Directory.GetFiles(data))
                        { try { loose += new FileInfo(f).Length; } catch (Exception ex) { Swallow.Note("Pages.StartSizeCount, loose file size", ex); } }
                        if (loose > 0) found.Add(new Slice { Name = "Archives and plugins", Bytes = loose });

                        foreach (string dir in Directory.GetDirectories(data))
                        {
                            long n = 0;
                            try
                            {
                                foreach (string f in Directory.EnumerateFiles(dir, "*", SearchOption.AllDirectories))
                                { try { n += new FileInfo(f).Length; } catch (Exception ex) { Swallow.Note("Pages.StartSizeCount, folder file size", ex); } }
                            }
                            catch (Exception ex) { Swallow.Note("Pages.StartSizeCount, enumerating " + dir, ex); }
                            if (n > 0) found.Add(new Slice { Name = Path.GetFileName(dir), Bytes = n });
                        }
                    }
                }
                catch (Exception ex) { Swallow.Note("Pages.StartSizeCount", ex); }

                found.Sort(delegate(Slice a, Slice b) { return b.Bytes.CompareTo(a.Bytes); });

                // Past the sixth slice the bars are too short to read, so the
                // tail is added up rather than drawn one hair at a time.
                if (found.Count > 6)
                {
                    long rest = 0;
                    for (int i = 6; i < found.Count; i++) rest += found[i].Bytes;
                    found.RemoveRange(6, found.Count - 6);
                    found.Add(new Slice { Name = "Everything else", Bytes = rest });
                }

                win.Dispatcher.BeginInvoke(new Action(delegate
                {
                    buildSizes = found;
                    buildCounting = false;
                    DrawBuildBars();
                }));
            });
        }

        static string Human(long b)
        {
            if (b < 1024L * 1024) return (b / 1024) + " KB";
            if (b < 1024L * 1024 * 1024) return (b / (1024.0 * 1024.0)).ToString("F0") + " MB";
            return (b / (1024.0 * 1024.0 * 1024.0)).ToString("F1") + " GB";
        }

        // ---------------------------------------------------------- controls
        // Moved here whole from the Help page, which is where this used to live.
        // Almost everything is rebindable from the panel above now; what is
        // left down here is the handful that is bound inside the game itself,
        // plus two things worth knowing that are not keys anybody set.
        // Two columns: a group name on its own, or an empty group and then the
        // key and what it does.
        static readonly string[][] ControlTable = new string[][] {
            new string[] { "Bound inside the game", "", "" },
            // SunHelm was the example here until it left the collection (To Do
            // List entry 133). QuickLoot is one that is still in the build,
            // with its own page, QuickLootIEMCM.pex. The line that said these
            // choices are kept in your save went with it, because it is not
            // true of what is left: five of the pages are MCM Helper ones,
            // which write Data\MCM\Settings\*.ini (checked 24 September), and
            // known.md says the script kind resets every session.
            new string[] { "", "Esc,  Mod Configuration", "The classic SkyUI settings pages. QuickLoot and the older mods live here, and this is where their keys get rebound. Nothing out here can move those choices." },
            new string[] { "", "E   /   R  at a container", "Loot without opening anything. Your Activate key takes the highlighted item, R takes the lot. Rebindable on the QuickLoot page of the mod settings menu." },
            new string[] { "", "Your Activate key", "Picks up, talks, opens. Rebindable in Skyrim's own controls, under Settings, Controls." },

            new string[] { "Worth knowing", "", "" },
            new string[] { "", "Esc", "The game does not pause. Menus stay live for everyone else, so do not sort your bags mid fight." },
            new string[] { "", "~", "The console. Using it on a shared world is how saves get broken, so leave it alone." },
        };

        static Keys.Binding capturing;
        static Button capturingButton;

        static void BuildControls()
        {
            if (controlsList == null) return;
            CancelCapture();
            controlsList.Children.Clear();

            // Everything the launcher can actually write, first, because it
            // is the part of this page anybody can act on. Press Change, press
            // the key you want, done.
            var top = new TextBlock();
            top.Text = "Change any of these";
            top.FontFamily = new FontFamily("Constantia, Georgia");
            top.FontSize = 13;
            top.Foreground = Res("Faint");
            top.Margin = new Thickness(0, 0, 0, 10);
            controlsList.Children.Add(top);

            // Thirty rows in one slab is a wall. Break them where the
            // bindings themselves already say to, which is also where a clash
            // would actually matter.
            StackPanel rebind = null;
            string lastGroup = null;
            bool firstGroup = true;
            foreach (Keys.Binding b in Keys.All())
            {
                if (rebind == null || !string.Equals(b.Group, lastGroup, StringComparison.OrdinalIgnoreCase))
                {
                    var gh = new TextBlock();
                    gh.Text = b.Group;
                    gh.FontFamily = new FontFamily("Constantia, Georgia");
                    gh.FontSize = 12.5;
                    gh.Foreground = Res("Faint");
                    gh.Margin = new Thickness(2, firstGroup ? 2 : 22, 0, 9);
                    controlsList.Children.Add(gh);
                    firstGroup = false;
                    lastGroup = b.Group;
                    rebind = new StackPanel();
                    var groupCard = new Border();
                    groupCard.Style = (Style)win.Resources["Slab"];
                    groupCard.Padding = new Thickness(20, 16, 20, 16);
                    groupCard.Child = rebind;
                    controlsList.Children.Add(groupCard);
                }
                rebind.Children.Add(RebindRow(b, rebind.Children.Count > 0));
            }

            var note = new TextBlock();
            note.Text = "Close Skyrim before changing one. These mods write their settings files back "
                      + "when the game exits, so a change made while it is running would be thrown away. "
                      + "Everything below is bound inside the game instead and has to be rebound there.";
            note.FontSize = 11.5; note.Foreground = Res("Faint");
            note.TextWrapping = TextWrapping.Wrap; note.LineHeight = 17;
            note.Margin = new Thickness(2, 11, 0, 0);
            controlsList.Children.Add(note);

            StackPanel group = null;
            foreach (string[] row in ControlTable)
            {
                if (row[0].Length > 0)
                {
                    var head = new TextBlock();
                    head.Text = row[0];
                    head.FontFamily = new FontFamily("Constantia, Georgia");
                    head.FontSize = 13;
                    head.Foreground = Res("Faint");
                    head.Margin = new Thickness(0, 26, 0, 10);
                    controlsList.Children.Add(head);

                    group = new StackPanel();
                    var card = new Border();
                    card.Style = (Style)win.Resources["Slab"];
                    card.Padding = new Thickness(20, 16, 20, 16);
                    card.Child = group;
                    controlsList.Children.Add(card);
                    continue;
                }
                if (group == null) continue;
                group.Children.Add(KeyLine(row[1], row[2], group.Children.Count > 0));
            }
        }

        static UIElement RebindRow(Keys.Binding b, bool rule)
        {
            var outer = new StackPanel();
            if (rule)
            {
                var line = new Rectangle();
                line.Height = 1; line.Fill = Res("Line");
                line.Margin = new Thickness(0, 13, 0, 13);
                outer.Children.Add(line);
            }

            var g = new Grid();
            var c0 = new ColumnDefinition(); c0.Width = new GridLength(126);
            var c1 = new ColumnDefinition(); c1.Width = new GridLength(1, GridUnitType.Star);
            var c2 = new ColumnDefinition(); c2.Width = GridLength.Auto;
            g.ColumnDefinitions.Add(c0); g.ColumnDefinitions.Add(c1); g.ColumnDefinitions.Add(c2);

            var k = new TextBlock();
            k.Text = b.Value.Length > 0 ? b.Value : "not set";
            k.FontFamily = new FontFamily("Cascadia Mono, Consolas");
            k.FontSize = 13; k.Foreground = Res("Accent");
            k.VerticalAlignment = VerticalAlignment.Center;
            k.Margin = new Thickness(0, 0, 14, 0);
            Grid.SetColumn(k, 0); g.Children.Add(k);

            var sp = new StackPanel();
            var t = new TextBlock();
            t.Text = b.Label; t.FontSize = 13; t.Foreground = Res("Ink");
            sp.Children.Add(t);
            var d = new TextBlock();
            d.Text = b.What; d.FontSize = 12; d.Foreground = Res("Muted");
            d.TextWrapping = TextWrapping.Wrap; d.LineHeight = 18;
            d.Margin = new Thickness(0, 3, 0, 0);
            sp.Children.Add(d);
            Grid.SetColumn(sp, 1); g.Children.Add(sp);

            var change = new Button();
            change.Content = "Change";
            change.Style = (Style)win.Resources["Ghost"];
            change.Padding = new Thickness(14, 6, 14, 6);
            change.VerticalAlignment = VerticalAlignment.Center;
            change.Margin = new Thickness(16, 0, 0, 0);
            Keys.Binding captured = b;
            change.Click += delegate { StartCapture(captured, change); };
            Grid.SetColumn(change, 2); g.Children.Add(change);

            outer.Children.Add(g);
            return outer;
        }

        static void StartCapture(Keys.Binding b, Button button)
        {
            // These live in files the mods rewrite from memory when Skyrim
            // exits, so a change made mid session is thrown away on quit.
            if (Checks.GameRunning())
            {
                Log("Close Skyrim first. It writes these files back when it exits, which would undo the change.");
                return;
            }

            CancelCapture();
            capturing = b;
            capturingButton = button;
            button.Content = "Press a key";
            Log("Press the key you want for " + b.Label.ToLowerInvariant() +
                ", or one of the two thumb buttons on your mouse, or Escape to leave it alone.");
            win.PreviewKeyDown += OnCaptureKey;
            // The extra mouse buttons never arrive as key events, which is the
            // whole of why they could not be bound. See OnCaptureMouse.
            win.PreviewMouseDown += OnCaptureMouse;
        }

        static void CancelCapture()
        {
            if (capturing == null) return;
            win.PreviewKeyDown -= OnCaptureKey;
            win.PreviewMouseDown -= OnCaptureMouse;
            if (capturingButton != null) capturingButton.Content = "Change";
            capturing = null;
            capturingButton = null;
        }

        static void OnCaptureKey(object sender, KeyEventArgs e)
        {
            if (capturing == null) return;
            e.Handled = true;

            Key key = e.Key == Key.System ? e.SystemKey : e.Key;
            if (key == Key.Escape) { CancelCapture(); Log("Left it as it was."); return; }

            Keys.Binding b = capturing;
            CancelCapture();
            Bind(b, KeyInterop.VirtualKeyFromKey(key));
        }

        /// <summary>
        /// The two thumb buttons on a mouse, which are not key presses.
        ///
        /// Grim Reefer, 21 September: "trying to change controls for voice to
        /// mouse 4 or 5 it doesn't work. It registers for other keys but not
        /// for mouse 4 or 5." Nothing was broken. A key press arrives as
        /// PreviewKeyDown and the extra mouse buttons do not, they arrive here
        /// as XButton1 and XButton2, and this window was only listening for the
        /// first kind. Mouse 4 and 5 are where push to talk lives for a lot of
        /// people precisely because the game does not use them.
        ///
        /// ONLY THE THUMB BUTTONS ARE TAKEN. Left, right and middle fall
        /// through unhandled so the page carries on working normally while it
        /// is waiting: the person still has to be able to press Change on
        /// something else, or scroll, or give up and click away. Binding push
        /// to talk to the attack button would also be a poor thing to make one
        /// click away.
        /// </summary>
        static void OnCaptureMouse(object sender, MouseButtonEventArgs e)
        {
            if (capturing == null) return;

            int vk;
            if (e.ChangedButton == MouseButton.XButton1) vk = 0x05;
            else if (e.ChangedButton == MouseButton.XButton2) vk = 0x06;
            else return;

            e.Handled = true;
            Keys.Binding b = capturing;
            CancelCapture();
            Bind(b, vk);
        }

        /// <summary>Write the binding and say what happened. Shared, because a
        /// thumb button and a key differ only in how they arrived.</summary>
        static void Bind(Keys.Binding b, int vk)
        {
            string why = Keys.Set(b, vk);
            if (why.Length > 0) { Log(why); return; }

            Log(b.Label + " is now " + Keys.Name(vk) + ". It applies next time the game starts.");
            BuildControls();
        }

        static UIElement KeyLine(string key, string what, bool rule)
        {
            var outer = new StackPanel();

            if (rule)
            {
                var line = new Rectangle();
                line.Height = 1; line.Fill = Res("Line");
                line.Margin = new Thickness(0, 12, 0, 12);
                outer.Children.Add(line);
            }

            var g = new Grid();
            var c0 = new ColumnDefinition(); c0.Width = new GridLength(126);
            var c1 = new ColumnDefinition(); c1.Width = new GridLength(1, GridUnitType.Star);
            g.ColumnDefinitions.Add(c0);
            g.ColumnDefinitions.Add(c1);

            var k = new TextBlock();
            k.Text = key;
            k.FontFamily = new FontFamily("Cascadia Mono, Consolas");
            k.FontSize = 11.5;
            k.Foreground = Res("Accent");
            k.TextWrapping = TextWrapping.Wrap;
            k.Margin = new Thickness(0, 0, 14, 0);
            Grid.SetColumn(k, 0); g.Children.Add(k);

            var v = new TextBlock();
            v.Text = what; v.FontSize = 12.5; v.Foreground = Res("Muted");
            v.TextWrapping = TextWrapping.Wrap; v.LineHeight = 19;
            Grid.SetColumn(v, 1); g.Children.Add(v);

            outer.Children.Add(g);
            return outer;
        }

        // ------------------------------------------------------- diagnostics
        static void BuildDiag()
        {
            if (diagReadings == null) return;

            // Scan and Fix and Ready to launch share one Verify.Run(cfg).
            // When a server-aware LastIssues is already in hand (Scan, Fix,
            // Play, or a finished Vortex bring-up-to-date), paint from that
            // instead of Waiting on another full Run: opening Diagnostics to
            // press a button there was paying the server
            // round trip every time after #709. Fresh Run only when there is
            // no shared truth yet.
            if (Verify.LastUsedServer && Verify.LastIssues != null)
                ShowVerify(Verify.LastIssues, false);
            else
                RunScan();

            if (diagCollection != null)
            {
                diagCollection.Children.Clear();
                // After the last Ready to launch row, before Bring it up to
                // date from Vortex. Used to sit in DiagReadings under What the
                // launcher can see right now, which put it under the Vortex
                // section.
                diagCollection.Children.Add(CollectionStatusCard());
            }

            // The optional packs, under the collection card (#1170).
            DrawAddons();

            diagReadings.Children.Clear();

            string ping = pingHistory.Count > 0 && pingHistory[pingHistory.Count - 1] >= 0
                        ? pingHistory[pingHistory.Count - 1] + " ms" : "not measured";

            foreach (Reading r in Diag.Readings(cfg, serverUp, ping))
                diagReadings.Children.Add(ReadingRow(r));

            string newest = "";
            try
            {
                if (Directory.Exists(Diag.ReportDir))
                {
                    var files = Directory.GetFiles(Diag.ReportDir, "*.zip");
                    Array.Sort(files);
                    if (files.Length > 0) newest = Path.GetFileName(files[files.Length - 1]);
                }
            }
            catch (Exception ex) { Swallow.Note("Pages.BuildDiag, newest report", ex); }
            txtDiagNote.Text = newest.Length > 0
                ? "Last report: " + newest + ", in Profile, Reports."
                : "No report built yet.";
        }

        static void MakeReport()
        {
            btnDiagBundle.IsEnabled = false;
            Log("Gathering logs.");
            ThreadPool.QueueUserWorkItem(delegate
            {
                string path = null, err = null;
                try { path = Diag.Report(cfg, Updater.Version); }
                catch (Exception ex) { err = ex.Message; }

                win.Dispatcher.BeginInvoke(new Action(delegate
                {
                    btnDiagBundle.IsEnabled = true;
                    if (err != null) { Log("Could not build the report: " + err); return; }
                    BuildDiag();
                    Log("Report written to " + path);
                    Reveal(path);
                }));
            });
        }

        static UIElement ReadingRow(Reading r)
        {
            var g = new Grid();
            var c0 = new ColumnDefinition(); c0.Width = GridLength.Auto;
            var c1 = new ColumnDefinition(); c1.Width = new GridLength(1, GridUnitType.Star);
            g.ColumnDefinitions.Add(c0); g.ColumnDefinitions.Add(c1);

            var dot = new Ellipse();
            dot.Width = 9; dot.Height = 9;
            dot.VerticalAlignment = VerticalAlignment.Top;
            dot.Margin = new Thickness(0, 5, 15, 0);
            dot.Fill = Res(r.Level == 0 ? "Ok" : r.Level == 1 ? "Warn" : "Bad");
            Grid.SetColumn(dot, 0); g.Children.Add(dot);

            var sp = new StackPanel();
            var t = new TextBlock();
            t.Text = r.Title; t.FontSize = 13.5; t.FontWeight = FontWeights.SemiBold;
            t.Foreground = Res("Ink"); t.TextWrapping = TextWrapping.Wrap;
            sp.Children.Add(t);

            var d = new TextBlock();
            d.Text = r.Detail; d.FontSize = 12.5; d.Foreground = Res("Muted");
            d.TextWrapping = TextWrapping.Wrap; d.LineHeight = 19;
            d.Margin = new Thickness(0, 4, 0, 0);
            sp.Children.Add(d);

            Grid.SetColumn(sp, 1); g.Children.Add(sp);

            var card = new Border();
            card.Style = (Style)win.Resources["Slab"];
            card.Margin = new Thickness(0, 0, 0, 8);
            card.Child = g;
            return card;
        }

        // ------------------------------------------------------------ shared
        static UIElement Fact(string label, string value, bool mono)
        {
            var g = new Grid();
            var c0 = new ColumnDefinition(); c0.Width = new GridLength(210);
            var c1 = new ColumnDefinition(); c1.Width = new GridLength(1, GridUnitType.Star);
            g.ColumnDefinitions.Add(c0); g.ColumnDefinitions.Add(c1);

            var l = new TextBlock();
            l.Text = label; l.FontSize = 12.5; l.Foreground = Res("Faint");
            l.VerticalAlignment = VerticalAlignment.Center;
            l.Margin = new Thickness(0, 0, 16, 0);
            Grid.SetColumn(l, 0); g.Children.Add(l);

            var v = new TextBlock();
            v.Text = value; v.FontSize = 12.5; v.Foreground = Res("Ink");
            v.TextWrapping = TextWrapping.Wrap; v.LineHeight = 19;
            if (mono) { v.FontFamily = new FontFamily("Cascadia Mono, Consolas"); v.FontSize = 12; }
            Grid.SetColumn(v, 1); g.Children.Add(v);

            var b = new Border();
            b.Padding = new Thickness(16, 11, 16, 11);
            b.Background = Res("Panel");
            b.Margin = new Thickness(0, 0, 0, 3);
            b.Child = g;
            return b;
        }

        static UIElement Bar(string label, string value, double frac)
        {
            if (frac < 0.003) frac = 0.003;
            if (frac > 1) frac = 1;

            var head = new Grid();
            var h0 = new ColumnDefinition(); h0.Width = new GridLength(1, GridUnitType.Star);
            var h1 = new ColumnDefinition(); h1.Width = GridLength.Auto;
            head.ColumnDefinitions.Add(h0); head.ColumnDefinitions.Add(h1);

            var l = new TextBlock();
            l.Text = label; l.FontSize = 12.5; l.Foreground = Res("Ink");
            l.TextTrimming = TextTrimming.CharacterEllipsis;
            Grid.SetColumn(l, 0); head.Children.Add(l);

            var v = new TextBlock();
            v.Text = value; v.FontSize = 11.5; v.Foreground = Res("Muted");
            v.FontFamily = new FontFamily("Cascadia Mono, Consolas");
            v.Margin = new Thickness(12, 0, 0, 0);
            Grid.SetColumn(v, 1); head.Children.Add(v);

            // Two star columns rather than a fixed width, so the bar keeps its
            // proportion when the window is resized.
            var track = new Grid();
            track.Height = 7;
            track.Margin = new Thickness(0, 7, 0, 0);
            var t0 = new ColumnDefinition(); t0.Width = new GridLength(frac, GridUnitType.Star);
            var t1 = new ColumnDefinition(); t1.Width = new GridLength(1 - frac, GridUnitType.Star);
            track.ColumnDefinitions.Add(t0); track.ColumnDefinitions.Add(t1);

            var back = new Rectangle();
            back.Fill = Res("Line");
            Grid.SetColumn(back, 0); Grid.SetColumnSpan(back, 2); track.Children.Add(back);

            var fill = new Rectangle();
            fill.Fill = Res("Accent");
            Grid.SetColumn(fill, 0); track.Children.Add(fill);

            var sp = new StackPanel();
            sp.Margin = new Thickness(0, 0, 0, 15);
            sp.Children.Add(head);
            sp.Children.Add(track);
            return sp;
        }
    }
}
