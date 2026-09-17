using System;
using System.IO;
using System.Security.Cryptography;

namespace Thornswood
{
    /// <summary>
    /// Takes back the one kind of file a release must never have carried:
    /// somebody's saved sign in.
    ///
    /// The installer built on 16 Sep was packaged out of the game folder on
    /// the machine that ships, and that folder held
    /// Data\Platform\PluginsNoLoad\auth-data-no-load.js, the SkyMP client's
    /// saved token for the account signed in there. Every install made from
    /// that installer got a copy. The packaging rules now leave the folder
    /// out (Ship-Rules.ps1), and this removes the copies that already went.
    ///
    /// Matched by content, never by name. On a machine that plays Keizaal or
    /// Daedric the same file name holds that person's own sign in, and that
    /// is theirs; only the exact bytes that shipped are taken away.
    /// </summary>
    static class Leaks
    {
        // SHA-256 of the file as it shipped, and the path it shipped at.
        static readonly string[][] Shipped = {
            new[] { "Data\\Platform\\PluginsNoLoad\\auth-data-no-load.js",
                    "d7578172d2f3d5d539b4b907ab6baebd4a2d114dfb737d37216526043391cf9d" },
        };

        /// <summary>
        /// Removes any shipped copy found, in the folder the game runs from and,
        /// when that is Thornswood's own folder, in the Steam copy it is made
        /// from: the installer put its copy into the Steam copy, and the own
        /// folder never takes that file in. Returns a line for the log, or null.
        /// </summary>
        public static string Clean(Config cfg)
        {
            var games = new System.Collections.Generic.List<string> { Paths.Game };
            try
            {
                if (OwnGame.Active)
                {
                    string src = OwnGame.Source(cfg);
                    if (src.Length > 0) games.Add(src);
                }
            }
            catch { }

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
                catch { }
            }
            if (n == 0) return null;
            return "Removed " + n + " saved sign in " + (n == 1 ? "file" : "files") +
                   " that an earlier installer carried by mistake. It was not yours and nothing of yours was touched.";
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
