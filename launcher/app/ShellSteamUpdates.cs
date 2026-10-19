using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Windows;
using System.Windows.Threading;

namespace Thornswood
{
    static partial class Shell
    {
        /// <summary>
        /// On the way in, once no downgrade is needed: Steam's Updates setting
        /// for Skyrim is read into the log and, when it does not hold the
        /// version (SteamUpdates.OnStart), set. With Steam closed that happens
        /// here and now, with nothing to ask. With Steam open it needs Steam
        /// closed for a moment, so the question is put once the window is up,
        /// and a No is remembered so it is not asked at every start.
        ///
        /// Issue #493, Patrick on 29 September: "Our Repo should write this so
        /// it doesn't auto update the game and people have to re do the
        /// downgrade again". Until then it was only ever offered right after a
        /// downgrade, so anybody downgraded before that question existed, or
        /// who pressed No once, had nothing holding Steam back.
        /// </summary>
        static void HoldSteamUpdatesOnStart()
        {
            string target = OwnGame.Source(cfg);
            string manifest = SteamUpdates.ManifestFor(target);
            string what = SteamUpdates.OnStart(SteamUpdates.NeedsHolding(manifest), SteamUpdates.SteamRunning(), playing, cfg.SteamUpdatesDeclined);
            if (what == SteamUpdates.Write) { Log(SteamUpdates.Hold(manifest)); return; }
            string upd = SteamUpdates.Report(target);
            if (upd != null) Log(upd);
            if (what != SteamUpdates.Ask) return;
            win.Dispatcher.BeginInvoke(new Action(delegate
            {
                try { AskToHoldSteamUpdates(); }
                catch (Exception ex) { Swallow.Note("Shell.HoldSteamUpdatesOnStart, the question", ex); }
            }), DispatcherPriority.ApplicationIdle);
        }

        /// <summary>
        /// The question: whether the launcher should set Steam's Updates
        /// setting for Skyrim to "Wait until I launch the game"
        /// (SteamUpdates). Asked on the way in (above). It used to follow every
        /// downgrade as well, when the downgrade put the Steam copy on
        /// 1.6.1170; the downgrade never writes the Steam copy now (#1218), so
        /// there is nothing there for the setting to hold. Nothing is written
        /// unless the person presses Yes, and the question says what Yes
        /// changes and where.
        ///
        /// Steam is usually running. A change made to the
        /// file while Steam runs is undone when Steam closes, so Yes closes
        /// Steam itself (steam://exit, the same as Steam, Exit), waits for it
        /// to go, makes the change, and starts Steam again in the tray, on a
        /// pool thread so the window does not freeze while Steam shuts down.
        /// Never while Skyrim runs, which needs Steam. No leaves everything as
        /// it is, is remembered for the start, and the log says how to make
        /// the same change in Steam. Play is never held on this.
        /// </summary>
        static void AskToHoldSteamUpdates()
        {
            string manifest = "";
            try { manifest = SteamUpdates.ManifestFor(OwnGame.Source(cfg)); } catch (Exception ex) { Swallow.Note("Shell.AskToHoldSteamUpdates, finding Steam's file for Skyrim", ex); }
            if (!SteamUpdates.NeedsHolding(manifest)) return;
            if (playing || Checks.GameRunning()) return;

            bool steamUp = SteamUpdates.SteamRunning();
            MessageBoxResult r = MessageBox.Show(win, SteamUpdates.Question(manifest, steamUp), "Thornswood", MessageBoxButton.YesNo, MessageBoxImage.Question);
            if (r != MessageBoxResult.Yes)
            {
                cfg.SteamUpdatesDeclined = true;
                try { cfg.Save(Paths.CfgFile); } catch (Exception ex) { Swallow.Note("Shell.AskToHoldSteamUpdates, remembering No", ex); }
                Log("Left Steam's Updates setting for Skyrim as it is. " + SteamUpdates.How);
                return;
            }
            if (!steamUp) { Log(SteamUpdates.Hold(manifest)); return; }

            Log("Closing Steam for a moment to change its Updates setting for Skyrim. It starts again by itself.");
            ThreadPool.QueueUserWorkItem(delegate
            {
                string said;
                try
                {
                    Downgrade.AskSteam("steam://exit", LogOnly);
                    if (!SteamUpdates.WaitClosed(60))
                        said = "Steam did not close within a minute, so nothing was changed, and the launcher asks again the next time it starts. " + SteamUpdates.How;
                    else
                    {
                        said = SteamUpdates.Hold(manifest, false);
                        StartSteamAgain();
                    }
                }
                catch (Exception ex) { said = "Could not change Steam's Updates setting for Skyrim: " + ex.Message + " " + SteamUpdates.How; }
                try { win.Dispatcher.BeginInvoke(new Action(delegate { Log(said); })); }
                catch (Exception ex) { Swallow.Note("Shell.AskToHoldSteamUpdates, saying what happened", ex); LogOnly(said); }
            });
        }

        /// <summary>
        /// Starts Steam again after the question closed it, in the tray the way
        /// it usually runs (-silent), rather than opening its window over the
        /// launcher. Through its steam:// link when steam.exe is not where
        /// Steam's install says.
        /// </summary>
        static void StartSteamAgain()
        {
            // The same start Fix makes when Scan finds Steam not running (#2627).
            Upkeep.StartSteam(LogOnly);
        }
    }
}
