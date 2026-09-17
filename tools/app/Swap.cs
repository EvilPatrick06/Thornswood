using System;
using System.Diagnostics;
using System.IO;

namespace Thornswood
{
    // Skyrim always reads its settings and saves from fixed folders under the
    // user's profile. To keep this build from colliding with any other Skyrim
    // on the machine, those folders are pointed here for the length of a play
    // session and put back afterwards.
    static class Swap
    {
        static bool IsLink(string p) { return Junction.IsLink(p); }

        static void DropLink(string p)
        {
            // Removes the link, never the folder it points at.
            try { Directory.Delete(p); } catch { }
        }

        static bool MakeLink(string link, string target)
        {
            string why;
            return Junction.Create(link, target, out why);
        }

        static string[] Pairs(out string[] ours)
        {
            ours = new string[] { Paths.MyGames, Paths.LocalAD };
            return new string[] { Paths.WinMyGames, Paths.WinLocalAD };
        }

        /// <summary>Undo the redirect. Safe to call any time, including after a crash.</summary>
        public static bool Restore()
        {
            bool had = File.Exists(Paths.StateFile);
            bool did = false;
            string[] ours;
            foreach (string win in Pairs(out ours))
            {
                string bak = win + ".st-backup";
                if (IsLink(win)) { DropLink(win); did = true; }
                if (Directory.Exists(bak) && !Directory.Exists(win))
                {
                    try { Directory.Move(bak, win); did = true; } catch { }
                }
            }
            try { if (had) File.Delete(Paths.StateFile); } catch { }
            return did || had;
        }

        /// <summary>
        /// Moves a folder aside, with a second go if the first is refused.
        /// Windows says access denied when anything still holds the folder
        /// open, and a game that has just fallen over holds it for a few
        /// seconds after it has stopped showing in the task list. Clearing
        /// whatever is left of Skyrim and waiting is what turns this from a
        /// failed launch into a pause nobody notices.
        /// </summary>
        static void MoveAside(string from, string to)
        {
            try { Directory.Move(from, to); return; }
            catch (UnauthorizedAccessException) { }
            catch (IOException) { }

            try { Checks.CloseGame(); } catch { }

            for (int i = 0; i < 10; i++)
            {
                System.Threading.Thread.Sleep(400);
                try { Directory.Move(from, to); return; }
                catch (UnauthorizedAccessException) { }
                catch (IOException) { }
            }

            // Out of ideas, so name the folder and the two causes that are
            // actually worth acting on, rather than repeating the word
            // Windows used.
            throw new Exception(
                "Windows would not let go of\n\n    " + from + "\n\n" +
                "Something still has it open. Almost always that is Skyrim or the " +
                "multiplayer client left over from a crash, so a restart clears it. " +
                "If it happens again straight after a restart, that folder is most " +
                "likely in OneDrive, and moving it out of OneDrive fixes it for good.");
        }

        public static void Apply()
        {
            // Under the collection, Vortex owns this. A Vortex profile with
            // local saves and local game settings turned on redirects the same
            // two folders, and two things junctioning one folder is how saves
            // end up somewhere neither of them looks. So the launcher stands
            // down and leaves the folders alone.
            if (Paths.Collection) return;

            Directory.CreateDirectory(Paths.MyGames);
            Directory.CreateDirectory(Paths.LocalAD);
            Directory.CreateDirectory(Path.Combine(Paths.MyGames, "Saves"));

            string[] ours;
            string[] wins = Pairs(out ours);
            for (int i = 0; i < wins.Length; i++)
            {
                string win = wins[i], bak = win + ".st-backup";
                if (IsLink(win)) DropLink(win);
                else if (Directory.Exists(win))
                {
                    if (Directory.Exists(bak))
                        try { Directory.Move(bak, bak + "-" + DateTime.Now.ToString("yyyyMMdd-HHmmss")); } catch { }
                    MoveAside(win, bak);
                }
                Directory.CreateDirectory(Path.GetDirectoryName(win));
                if (!MakeLink(win, ours[i]))
                    throw new Exception("Could not redirect " + win);
            }
            File.WriteAllText(Paths.StateFile, "{\"swappedAt\":\"" + DateTime.Now.ToString("o") + "\"}");
        }

        // The plugin lists are not anyone's to keep. The server compares load
        // orders, so those go back exactly as shipped every single time.
        static readonly string[] Forced = new string[] { "plugins.txt", "loadorder.txt" };

        /// <summary>
        /// Puts the shipped originals back. The plugin lists always. The ini
        /// files only when they are missing, because everything in
        /// SkyrimPrefs.ini is changed from inside the game: volume, gamma,
        /// difficulty, view distance. Copying the shipped one over the top
        /// after every update is exactly why those changes kept vanishing.
        /// </summary>
        public static int RepairConfigs() { return RepairConfigs(false); }

        /// <param name="overwriteSettings">
        /// True only for the Fix button, where putting the originals back over
        /// someone's own settings is the whole point of pressing it.
        /// </param>
        public static int RepairConfigs(bool overwriteSettings)
        {
            int n = 0;

            // Under the collection none of this is the launcher's to write.
            // The plugin list belongs to the active Vortex profile, and
            // putting the shipped one over it would undo the install somebody
            // just did and leave Vortex and the game disagreeing about what is
            // loaded. The ini files are the profile's too. A mismatch here is
            // fixed in Vortex, not by copying files over the top of it, which
            // is what the launcher says when it finds one.
            if (Paths.Collection) return 0;

            if (!Directory.Exists(Paths.Golden)) return 0;
            foreach (string f in Directory.GetFiles(Paths.Golden))
            {
                string name = Path.GetFileName(f);
                string dest = Path.GetExtension(f).ToLowerInvariant() == ".ini" ? Paths.MyGames : Paths.LocalAD;
                Directory.CreateDirectory(dest);
                string target = Path.Combine(dest, name);

                bool forced = false;
                for (int i = 0; i < Forced.Length; i++)
                    if (string.Equals(name, Forced[i], StringComparison.OrdinalIgnoreCase)) forced = true;

                if (!forced && !overwriteSettings && File.Exists(target)) continue;

                File.Copy(f, target, true);
                n++;
            }
            return n;
        }
    }
}
