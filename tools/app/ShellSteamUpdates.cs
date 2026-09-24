using System;
using System.Windows;

namespace Thornswood
{
    static partial class Shell
    {
        /// <summary>
        /// Asked once a downgrade has worked, and only then: whether the
        /// launcher should set Steam's Updates setting for Skyrim to "Wait
        /// until I launch the game" (SteamUpdates). Nothing is
        /// written unless the person presses Yes, and the question says what
        /// Yes changes and where.
        ///
        /// Steam is always running at this point, because the downgrade needs
        /// its console, and a change made to the file while Steam runs is
        /// undone when Steam closes. So the question asks for Steam to be
        /// closed first and checks that it is, and asks again if it is not.
        /// No leaves everything as it is, and the log says how to make the same
        /// change in Steam. Play is never held on this.
        /// </summary>
        static void AskToHoldSteamUpdates()
        {
            string manifest = "";
            try { manifest = SteamUpdates.ManifestFor(Downgrade.Target(cfg)); } catch { }
            if (!SteamUpdates.NeedsHolding(manifest)) return;

            string ask =
                "Skyrim is on 1.6.1170 now, but Steam can still update it by itself, and the next update Steam takes puts it back on the newer build.\n\n" +
                "Yes changes Steam's Updates setting for Skyrim to \"" + SteamUpdates.OnLaunchWords + "\", the same as picking it under Automatic Updates on Steam's own Properties, Updates page. " +
                "It changes that one value in Steam's file for Skyrim and nothing else:\n\n    " + manifest + "\n\n" +
                "Steam has to be closed first, or it writes the old setting back when it closes. Exit Steam from its own menu (Steam, Exit), then press Yes.\n\n" +
                "No leaves it as it is.";
            while (true)
            {
                MessageBoxResult r = MessageBox.Show(win, ask, "Thornswood", MessageBoxButton.YesNo, MessageBoxImage.Question);
                if (r != MessageBoxResult.Yes)
                {
                    Log("Left Steam's Updates setting for Skyrim as it is. " + SteamUpdates.How);
                    return;
                }
                if (!SteamUpdates.SteamRunning()) break;
                ask = "Steam is still running, so nothing has been changed.\n\n" +
                      "Exit Steam from its own menu (Steam, Exit) and wait for it to close, then press Yes. No leaves the setting as it is.";
            }
            Log(SteamUpdates.Hold(manifest));
        }
    }
}
