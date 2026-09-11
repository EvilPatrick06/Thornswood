using System;
using System.Diagnostics;
using System.IO;

namespace SkyrimTogether
{
    // Skyrim always reads its settings and saves from fixed folders under the
    // user's profile. To keep this build from colliding with any other Skyrim
    // on the machine, those folders are pointed here for the length of a play
    // session and put back afterwards.
    static class Swap
    {
        static bool IsLink(string p)
        {
            try
            {
                if (!Directory.Exists(p)) return false;
                return (new DirectoryInfo(p).Attributes & FileAttributes.ReparsePoint) != 0;
            }
            catch { return false; }
        }

        static void DropLink(string p)
        {
            // Removes the link, never the folder it points at.
            try { Directory.Delete(p); } catch { }
        }

        static bool MakeLink(string link, string target)
        {
            try
            {
                var psi = new ProcessStartInfo("cmd.exe", "/c mklink /J \"" + link + "\" \"" + target + "\"");
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                psi.RedirectStandardOutput = true;
                psi.RedirectStandardError = true;
                using (var pr = Process.Start(psi)) { pr.StandardOutput.ReadToEnd(); pr.StandardError.ReadToEnd(); pr.WaitForExit(); }
            }
            catch { }
            return IsLink(link);
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

        public static void Apply()
        {
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
                    Directory.Move(win, bak);
                }
                Directory.CreateDirectory(Path.GetDirectoryName(win));
                if (!MakeLink(win, ours[i]))
                    throw new Exception("Could not redirect " + win);
            }
            File.WriteAllText(Paths.StateFile, "{\"swappedAt\":\"" + DateTime.Now.ToString("o") + "\"}");
        }

        public static int RepairConfigs()
        {
            int n = 0;
            if (!Directory.Exists(Paths.Golden)) return 0;
            foreach (string f in Directory.GetFiles(Paths.Golden))
            {
                string dest = Path.GetExtension(f).ToLowerInvariant() == ".ini" ? Paths.MyGames : Paths.LocalAD;
                Directory.CreateDirectory(dest);
                File.Copy(f, Path.Combine(dest, Path.GetFileName(f)), true);
                n++;
            }
            return n;
        }
    }
}
