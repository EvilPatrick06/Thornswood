using System;
using System.IO;
using System.Security.Cryptography;

namespace Thornswood
{
    /// <summary>
    /// Takes back files a release must never have carried: somebody's saved
    /// sign in, and the machine that ships' own settings and notes.
    ///
    /// The installer built on 16 Sep was packaged out of the game folder on
    /// the machine that ships, and that folder held
    /// Data\Platform\PluginsNoLoad\auth-data-no-load.js, the SkyMP client's
    /// saved token for the account signed in there. Every install made from
    /// that installer got a copy. The packaging rules now leave the folder
    /// out (Ship-Rules.ps1), and this removes the copies that already went.
    ///
    /// The dev release records of 28 and 29 Sep listed that machine's mod
    /// menu settings, window layouts and notes as Thornswood's files, so a dev
    /// launcher that synced to one fetched them (#1252). Ship-Rules keeps them
    /// out of every record and pack since (#1239), and this removes the copies
    /// that already went, from Thornswood's own folder only.
    ///
    /// Matched by content, never by name. On a machine that plays another server or
    /// Daedric the same file name holds that person's own sign in, and that
    /// is theirs; only the exact bytes that shipped are taken away. The same
    /// for the settings: a file changed since it was handed out is the
    /// person's own now and stays.
    /// </summary>
    static class Leaks
    {
        // SHA-256 of the file as it shipped, and the path it shipped at.
        static readonly string[][] Shipped = {
            new[] { "Data\\Platform\\PluginsNoLoad\\auth-data-no-load.js",
                    "d7578172d2f3d5d539b4b907ab6baebd4a2d114dfb737d37216526043391cf9d" },
        };

        // Path, size and SHA-256 of each file of the machine that ships as the
        // dev records of 28 and 29 Sep handed it out (#1252): 20260928-2324-dev,
        // 20260929-0259-dev, 1129-dev, 122410-dev and 140118-dev, read from
        // those five records as they were before Scrub-Feed replaced them on
        // 29 Sep (#1239). Every path had one set of bytes in all five, except
        // the join pass, which had two; 1129-dev listed no pass.
        static readonly string[][] Synced = {
            // Saved in those mods' menus on the machine that ships; the first
            // two are another server's values (Daedric Online, Audit-ModMenus.js).
            new[] { "Data\\MCM\\Settings\\Precision.ini", "1962",
                    "104c05be571b6e21fd3030387b1d81c52d1e379e22838107aec7e65b53adc968" },
            new[] { "Data\\MCM\\Settings\\TrueDirectionalMovement.ini", "1035",
                    "422cba303141fbca9648c63b44d3a8aeb92ae60c92900d514c0a011a09989cef" },
            new[] { "Data\\MCM\\Settings\\TrueHUD.ini", "118",
                    "b18a67662cf4ee8d723f0442a24367e708d27c972d8b270392b120c1c3164a0f" },
            // That machine's graphics settings, and where two mods' windows sat
            // on its screen.
            new[] { "Data\\SKSE\\Plugins\\CommunityShaders\\SettingsUser.json", "12727",
                    "7ac69fd287373e9ed4d2d68d2073bbc9f99fd9b36b1c5f3c69c54a826c7191cb" },
            new[] { "Data\\SKSE\\Plugins\\CommunityShaders_ImGui.ini", "136",
                    "cae9617a0fbc1b7e61404b87fadd5631f52d995d4baa875368a66a72251100db" },
            new[] { "Data\\SKSE\\Plugins\\OpenAnimationReplacer_ImGui.ini", "66",
                    "68e286a0f4b010097db2ad6079f583f30150a86cbc84ef4b991076553398f933" },
            // The spot marker's output, a hang report and two expired join
            // passes. Play deletes and rewrites the pass (JoinPass.Forget), so
            // only an install that has not played since still has one.
            new[] { "Data\\Platform\\thornswood-spots.txt", "243",
                    "664a034fd3e4822c5d3208f5233b6b3f6af41b7a514389fce11f5064f5467873" },
            new[] { "Data\\Platform\\js-hang-culprit.txt", "776",
                    "2674e36bb3aaa83e8c7173a9c8ce05c46283c52daaf4bfc26f1f62445e86eb69" },
            new[] { "Data\\Platform\\thornswood-pass.txt", "184",
                    "c0c937692021446fb4f0d592161088f0cab74eaf15aa20fb14158e622778721c" },
            new[] { "Data\\Platform\\thornswood-pass.txt", "184",
                    "c6d96ffb786dbce4bcbb63fdf4164cd9a7d190c94ac5e4d77b1ab09eaa38f35b" },
        };

        /// <summary>
        /// Removes any shipped copy found, in the folder the game runs from and,
        /// when that is Thornswood's own folder, in the Steam copy it is made
        /// from: the installer put its copy into the Steam copy, and the own
        /// folder never takes that file in. The same while the own folder is
        /// chosen and not made (Paths.OwnFirst, #1226): the game folder is then
        /// Profile\Payload, and an earlier install may have left the file in the
        /// Steam copy. Only ever this one exact file is deleted there.
        /// Then the files the dev records handed out (Synced).
        /// Returns a line for the log, or null.
        /// </summary>
        public static string Clean(Config cfg)
        {
            var games = new System.Collections.Generic.List<string> { Paths.Game };
            try
            {
                if (OwnGame.Active || Paths.OwnFirst)
                {
                    string src = OwnGame.Source(cfg);
                    if (src.Length > 0) games.Add(src);
                }
            }
            catch (Exception ex) { Swallow.Note("Leaks.Clean, OwnGame.Source", ex); }

            int n = 0;
            foreach (string game in games)
            foreach (string[] s in Shipped)
            {
                try
                {
                    string p = Path.Combine(game, s[0]);
                    if (!File.Exists(p)) continue;
                    if (!string.Equals(Sha256(p), s[1], StringComparison.OrdinalIgnoreCase)) continue;
                    File.SetAttributes(p, FileAttributes.Normal);
                    File.Delete(p);
                    n++;
                }
                catch (Exception ex) { Swallow.Note("Leaks.Clean, deleting " + Path.Combine(game, s[0]), ex); }
            }
            string said = null;
            if (n > 0)
                said = "Removed " + n + " saved sign in " + (n == 1 ? "file" : "files") +
                       " that an earlier installer carried by mistake. It was not yours and nothing of yours was touched.";

            string synced = CleanSynced();
            if (synced == null) return said;
            return said == null ? synced : said + " " + synced;
        }

        /// <summary>
        /// Takes the files the dev records of 28 and 29 Sep handed out (Synced)
        /// out of Thornswood's own folder while each is still exactly the bytes
        /// it was handed out as (#1252, Patrick's answer of 5 Oct).
        ///
        /// Why every start and not once: a collection install that synced kept
        /// them in the Steam copy on its installed-into-game list, and Make
        /// brings them into the own folder whenever that person makes it. A
        /// start that has none of them only asks whether nine paths exist.
        ///
        /// Never the Steam copy, unlike Shipped above: another server's
        /// launcher may have written the same bytes there (the first two menu
        /// files hold Daedric Online's values and were in the Steam copy of the
        /// machine that ships on 14 Sep, before Thornswood's first pack), and
        /// there they are that server's. Nor Profile\Payload, which is not the folder the game
        /// runs from; Make brings what it holds in and the next start judges
        /// it here.
        /// </summary>
        static string CleanSynced()
        {
            bool own;
            try { own = OwnGame.Active; }
            catch (Exception ex) { Swallow.Note("Leaks.CleanSynced, OwnGame.Active", ex); return null; }
            if (!own) return null;

            var gone = new System.Collections.Generic.List<string>();
            foreach (string[] s in Synced)
            {
                string p = Path.Combine(OwnGame.Folder, s[0]);
                try
                {
                    if (!File.Exists(p)) continue;
                    if (new FileInfo(p).Length != long.Parse(s[1])) continue;
                    if (!string.Equals(Sha256(p), s[2], StringComparison.OrdinalIgnoreCase)) continue;
                    // This folder's name for it only: a folder made before
                    // #1218 may share it with the Steam copy by hard link, and
                    // the Steam copy's name stays.
                    OwnGame.DropName(p);
                    gone.Add(s[0]);
                }
                catch (Exception ex) { Swallow.Note("Leaks.CleanSynced, " + p, ex); }
            }
            if (gone.Count == 0) return null;
            return "Removed " + gone.Count + (gone.Count == 1 ? " file" : " files") + " from Thornswood's own folder that a dev release of 28 or 29 September " +
                   "handed out by mistake: mod menu settings, window layouts and notes from the machine that ships, each still exactly as it was handed out (" +
                   string.Join(", ", gone.ToArray()) + "). A copy changed since is yours and was kept.";
        }

        static string Sha256(string path)
        {
            using (var sha = SHA256.Create())
            using (var fs = File.OpenRead(path))
            {
                byte[] h = sha.ComputeHash(fs);
                var sb = new System.Text.StringBuilder(64);
                foreach (byte b in h) sb.Append(b.ToString("x2"));
                return sb.ToString();
            }
        }
    }
}
