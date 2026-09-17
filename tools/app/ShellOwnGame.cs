using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Threading;
using System.Windows;
using System.Windows.Controls;

namespace Thornswood
{
    /// <summary>
    /// The launcher's side of OwnGame: the card in Settings, the offer at
    /// startup on a machine where another SkyMP server has been, and bringing
    /// the folder up to date by itself when Vortex has deployed a newer
    /// Thornswood collection. Play stays off while either runs.
    /// </summary>
    static partial class Shell
    {
        static bool ownGameBusy, ownGameStarted, restarting;
        static TextBlock txtOwnGameState;
        static Button btnOwnGameMake, btnOwnGameRefresh;

        static void WireOwnGame()
        {
            txtOwnGameState = F<TextBlock>("TxtOwnGameState");
            btnOwnGameMake = F<Button>("BtnOwnGameMake");
            btnOwnGameRefresh = F<Button>("BtnOwnGameRefresh");
            var panel = F<StackPanel>("PnlOwnGame");

            if (btnOwnGameMake != null) btnOwnGameMake.Click += delegate { AskOwnGame(false); };
            if (btnOwnGameRefresh != null) btnOwnGameRefresh.Click += delegate { StartOwnGame(false, true); };
            if (panel != null) panel.IsVisibleChanged += delegate { if (panel.IsVisible) DrawOwnGame(); };

            // Once the window is on screen, so a question has something to sit
            // in front of and the check does not hold up the first draw.
            win.ContentRendered += delegate
            {
                if (ownGameStarted) return;
                ownGameStarted = true;
                OwnGameAtStart();
            };

            win.Closing += delegate(object s, System.ComponentModel.CancelEventArgs e)
            {
                if (!ownGameBusy || restarting) return;
                var r = MessageBox.Show(
                    "Thornswood's own Skyrim folder is still being prepared.\n\nClose anyway? It starts again from where it can the next time the launcher opens.",
                    "Thornswood", MessageBoxButton.YesNo, MessageBoxImage.Warning);
                if (r != MessageBoxResult.Yes) e.Cancel = true;
            };

            DrawOwnGame();
        }

        static void OwnGameAtStart()
        {
            Config c = cfg;
            bool active = OwnGame.Active;
            bool collection = Paths.Collection;
            ThreadPool.QueueUserWorkItem(delegate
            {
                bool refresh = false, offer = false;
                try
                {
                    if (active) refresh = OwnGame.NeedsRefresh(c);
                    else if (collection && !OwnGame.Declined)
                    {
                        string src = OwnGame.Source(c);
                        offer = OwnGame.WhyNot(c, src) == null && OwnGame.OtherServerHere(src);
                    }
                }
                catch { }
                if (!refresh && !offer) return;
                try
                {
                    win.Dispatcher.BeginInvoke((Action)delegate
                    {
                        if (refresh) StartOwnGame(false, false);
                        else AskOwnGame(true);
                    });
                }
                catch { }
            });
        }

        static void AskOwnGame(bool atStart)
        {
            if (OwnGame.Active) { Log("Thornswood already runs from its own Skyrim folder, " + OwnGame.Folder + "."); return; }
            string src = OwnGame.Source(cfg);
            string why = OwnGame.WhyNot(cfg, src);
            if (why != null)
            {
                Log(why);
                if (!atStart) MessageBox.Show(why, "Thornswood", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }

            var r = MessageBox.Show(
                "Give Thornswood a Skyrim folder of its own?\n\n" +
                "Thornswood and other servers are sharing one Skyrim right now, which is how their menus, plugins and mods get into each other. " +
                "With a folder of its own, Thornswood only ever starts from " + OwnGame.Folder + ", and switching profiles in Vortex no longer reaches it.\n\n" +
                "It is made from what Vortex has deployed in " + src + ". The big files are links, so the collection is not on the disk twice. " +
                "It takes a few minutes, and the launcher restarts when it is done." +
                (atStart ? "\n\nSay no and the button stays in Settings, under Maintenance." : ""),
                "Thornswood", MessageBoxButton.YesNo, MessageBoxImage.Question);
            if (r != MessageBoxResult.Yes)
            {
                if (atStart)
                {
                    OwnGame.Decline();
                    Log("Left Thornswood in the shared Skyrim. Settings, Maintenance has the button when you want it.");
                }
                return;
            }
            StartOwnGame(true, true);
        }

        /// <param name="make">True to make the folder, false to bring it up to date.</param>
        /// <param name="loud">True when somebody pressed a button, so failures get a box as well as a log line.</param>
        static void StartOwnGame(bool make, bool loud)
        {
            if (ownGameBusy) return;
            // The downgrade is writing into the Steam copy this reads from. It
            // starts the refresh itself when it is done.
            if (Downgrade.Busy)
            {
                Log("Skyrim is being downgraded. Thornswood's own folder is brought up to date when that is done.");
                return;
            }
            if (playing || Checks.GameRunning())
            {
                string msg = "Close Skyrim first, then " + (make ? "make" : "update") + " Thornswood's own folder. " + Checks.StuckReport();
                Log(msg);
                if (loud) MessageBox.Show(msg, "Thornswood", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }
            if (!make && !OwnGame.Active) { Log("Thornswood does not have its own Skyrim folder yet."); return; }

            ownGameBusy = true;
            DrawStatus();
            DrawOwnGame();
            Log(make ? "Making Thornswood's own Skyrim folder from what Vortex has deployed. Play comes back when it is done."
                     : "Bringing Thornswood's own Skyrim folder up to date with what Vortex has deployed. Play comes back when it is done.");

            Config c = cfg;
            ThreadPool.QueueUserWorkItem(delegate
            {
                string said = null, fail = null;
                Action<string> say = delegate(string m)
                {
                    try { win.Dispatcher.BeginInvoke((Action)delegate { Log(m); }); } catch { }
                };
                try { said = make ? OwnGame.Make(c, say) : OwnGame.Refresh(c, say); }
                catch (Exception ex) { fail = ex.Message; }

                try
                {
                    win.Dispatcher.BeginInvoke((Action)delegate
                    {
                        ownGameBusy = false;
                        if (fail != null)
                        {
                            Log((make ? "Thornswood's own Skyrim folder was not made. " : "Thornswood's own Skyrim folder was not brought up to date. ") + fail);
                            if (loud) MessageBox.Show(fail, "Thornswood", MessageBoxButton.OK, MessageBoxImage.Warning);
                        }
                        else
                        {
                            Log(said);
                            if (make)
                            {
                                Log("Restarting the launcher so it runs from the new folder.");
                                RestartLauncher();
                                return;
                            }
                        }
                        DrawStatus();
                        DrawOwnGame();
                    });
                }
                catch { }
            });
        }

        static void DrawOwnGame()
        {
            if (txtOwnGameState == null) return;
            bool active = OwnGame.Active;
            string state;
            if (ownGameBusy) state = "Working on it now.";
            else if (active) state = "On. Thornswood runs from " + OwnGame.Folder + ", made from " + OwnGame.Source(cfg) + ".";
            else if (!Paths.Collection) state = "This install already has a Game folder of its own from its installer.";
            else
            {
                string why = OwnGame.WhyNot(cfg, OwnGame.Source(cfg));
                state = why == null ? "Off. Vortex has the Thornswood collection deployed, so it can be made now." : "Off. " + why;
            }
            txtOwnGameState.Text = state;

            if (btnOwnGameMake != null)
            {
                btnOwnGameMake.Visibility = active ? Visibility.Collapsed : Visibility.Visible;
                btnOwnGameMake.IsEnabled = !ownGameBusy && Paths.Collection;
            }
            if (btnOwnGameRefresh != null)
            {
                btnOwnGameRefresh.Visibility = active ? Visibility.Visible : Visibility.Collapsed;
                btnOwnGameRefresh.IsEnabled = !ownGameBusy;
            }
        }

        /// <summary>
        /// Paths are worked out once, when the launcher starts, so running from a
        /// new game folder means starting again. Same short detached script the
        /// self update uses: wait for this one to go, start the exe.
        /// </summary>
        static void RestartLauncher()
        {
            try
            {
                string exe = Assembly.GetExecutingAssembly().Location;
                string bat = Path.Combine(Path.GetTempPath(), "ts-restart-" + Process.GetCurrentProcess().Id + ".cmd");
                // cmd reads a .cmd file in the console's OEM code page, not
                // the UTF-8 this is written in, so a path with any character
                // outside ASCII would reach start as different bytes and the
                // launcher would close and never come back.
                File.WriteAllText(bat,
                    "@echo off\r\n" +
                    "chcp 65001 >nul\r\n" +
                    "ping 127.0.0.1 -n 3 >nul\r\n" +
                    "start \"\" \"" + exe + "\"\r\n" +
                    "del \"%~f0\"\r\n");
                var psi = new ProcessStartInfo(bat);
                psi.WindowStyle = ProcessWindowStyle.Hidden;
                psi.CreateNoWindow = true;
                psi.UseShellExecute = true;
                Process.Start(psi);
            }
            catch (Exception ex)
            {
                Log("Could not restart by itself (" + ex.Message + "). Close the launcher and open it again.");
                return;
            }
            restarting = true;
            win.Close();
        }
    }
}
