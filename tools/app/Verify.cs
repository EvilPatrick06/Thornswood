using System;
using System.Collections.Generic;
using System.IO;

namespace Thornswood
{
    class Issue
    {
        public string Text;
        public bool Blocking;      // true = you will be refused by the server
        // The file is not in Data at all. Fix rewrites a plugin list, it cannot
        // install a mod, so offering the button for one of these is worse than
        // not offering it.
        public bool Absent;
        public Issue(string t, bool b) { Text = t; Blocking = b; }
        public Issue(string t, bool b, bool absent) { Text = t; Blocking = b; Absent = absent; }
    }

    static class Verify
    {
        static List<string> Enabled(string file)
        {
            var l = new List<string>();
            if (!File.Exists(file)) return l;
            foreach (string raw in File.ReadAllLines(file))
            {
                string s = raw.Trim();
                if (s.Length == 0 || s.StartsWith("#")) continue;
                if (s.StartsWith("*")) l.Add(s.Substring(1));
            }
            return l;
        }

        /// <summary>
        /// The shipped plugins.txt is what the server was built against, so it is
        /// the reference. Anything the live list adds, drops or reorders is what
        /// gets a player refused at connect.
        /// </summary>
        public static List<Issue> Run()
        {
            var issues = new List<Issue>();
            string golden = Path.Combine(Paths.Golden, "plugins.txt");

            // Paths.Live, not Paths.LocalAD. Under the collection those are two
            // different files and this was reading the wrong one.
            //
            // LocalAD is the launcher's own redirected copy under Profile, which
            // is right for an install that built its own game. A collection
            // install redirects nothing: Vortex writes the real list into
            // Windows' own AppData and that is what Skyrim and the server see.
            // So this compared against a copy the installer laid down once and
            // nothing has touched since, reported plugins from somebody's old
            // collection that are not enabled anywhere any more, and Fix then
            // rewrote that same unread file. The scan found problems that were
            // not there and fixing them changed nothing, every time.
            //
            // Paths.Live is already the right file for both shapes of install.
            string live = Path.Combine(Paths.Live, "plugins.txt");

            if (!File.Exists(golden))
            {
                issues.Add(new Issue("This build shipped without a reference plugin list, so there is nothing to compare against.", false));
                return issues;
            }
            if (!File.Exists(live))
            {
                issues.Add(new Issue("Your plugins.txt is missing. Fix will put the shipped one back.", true));
                return issues;
            }

            List<string> want = Enabled(golden), have = Enabled(live);
            var wantSet = new HashSet<string>(want, StringComparer.OrdinalIgnoreCase);
            var haveSet = new HashSet<string>(have, StringComparer.OrdinalIgnoreCase);

            // Turned off and not installed at all look identical in a plugin
            // list and need completely different answers, so they are told
            // apart by looking in Data rather than guessed at.
            string dataDir = Path.Combine(Paths.Game, "Data");
            foreach (string p in want)
            {
                if (haveSet.Contains(p)) continue;
                bool onDisk = true;
                try { onDisk = File.Exists(Path.Combine(dataDir, p)); } catch { }
                issues.Add(new Issue(
                    onDisk ? p + " is turned off." : p + " is not installed.",
                    true, !onDisk));
            }

            foreach (string p in have)
                if (!wantSet.Contains(p)) issues.Add(new Issue(p + " is enabled but is not part of this build.", true));

            // Another server's client. Not a plugin, so nothing above would ever
            // have found it, and it is the difference between Thornswood loading
            // and Daedric Online's main menu loading instead.
            foreach (string f in Checks.ForeignClients())
                issues.Add(new Issue(
                    Path.GetFileName(f) + " belongs to another server. It replaces the main menu " +
                    "and asks you to sign in to them. Fix moves it aside into Thornswood's " +
                    "Isolated folder and nothing is deleted, so that server still works.", true));

            // The collection installs MCM Helper's plugin without its light flag,
            // which gives it a load order index the server does not have and
            // shifts everything after it by one. See Checks.MustBeLight.
            foreach (string p in Checks.NotLight())
                issues.Add(new Issue(
                    p + " is not flagged light, so from there on your load order counts " +
                    "one place differently from the server's. Fix flags it; nothing else changes.", true));
            if (want.Count == have.Count && issues.Count == 0)
            {
                for (int i = 0; i < want.Count; i++)
                {
                    if (!string.Equals(want[i], have[i], StringComparison.OrdinalIgnoreCase))
                    {
                        issues.Add(new Issue("The load order does not match the server's from " + want[i] + " onwards.", true));
                        break;
                    }
                }
            }

            // A plugin the list references but that is not actually on disk.
            string data = Path.Combine(Paths.Game, "Data");
            foreach (string p in want)
            {
                try { if (!File.Exists(Path.Combine(data, p))) issues.Add(new Issue(p + " is in the list but the file is not in Data.", true)); }
                catch { }
            }

            // Personal mods that carry a plugin will be refused.
            if (Directory.Exists(Paths.Personal))
            {
                foreach (string f in Directory.GetFiles(Paths.Personal, "*.*", SearchOption.AllDirectories))
                {
                    string e = Path.GetExtension(f).ToLowerInvariant();
                    if (e == ".esp" || e == ".esm" || e == ".esl")
                        issues.Add(new Issue("Your own mods folder contains " + Path.GetFileName(f) + ". Plugins there will get you refused.", true));
                }
            }

            return issues;
        }

        /// <summary>
        /// Puts the shipped load order back, into the file that is actually
        /// read. Same correction as Run: Paths.Live rather than Paths.LocalAD.
        ///
        /// Under the collection this is Vortex's file. Writing it here is still
        /// right, because the server refuses a mismatched list and this is what
        /// it expects, but Vortex will write its own version again the next time
        /// it deploys. The launcher says so rather than letting somebody fix the
        /// same thing twice and wonder why.
        /// </summary>
        public static int Fix()
        {
            int n = 0;
            foreach (string f in new string[] { "plugins.txt", "loadorder.txt" })
            {
                string src = Path.Combine(Paths.Golden, f);
                if (!File.Exists(src)) continue;
                Directory.CreateDirectory(Paths.Live);
                File.Copy(src, Path.Combine(Paths.Live, f), true);
                n++;
            }

            // Fix means make this install match what the server expects, and
            // another server's client running the main menu is the furthest
            // from that anything gets. It is moved aside, never deleted,
            // because somebody who plays here may also play there.
            n += Checks.IsolateForeign(null);
            n += Checks.FlagLight(null);
            return n;
        }

        /// <summary>Where the load order being judged actually lives, for the
        /// launcher to show, because the last hour of this was not knowing.</summary>
        public static string LiveFile { get { return Path.Combine(Paths.Live, "plugins.txt"); } }

        /// <summary>Copies the player's own loose files into the game before launch.</summary>
        public static int DeployPersonal()
        {
            if (!Directory.Exists(Paths.Personal)) { Directory.CreateDirectory(Paths.Personal); return 0; }
            string dataRoot = Path.Combine(Paths.Game, "Data");
            int n = 0;
            foreach (string src in Directory.GetFiles(Paths.Personal, "*.*", SearchOption.AllDirectories))
            {
                string rel = src.Substring(Paths.Personal.Length).TrimStart('\\');
                string ext = Path.GetExtension(src).ToLowerInvariant();
                if (ext == ".esp" || ext == ".esm" || ext == ".esl") continue;   // never, it breaks the check
                string dest = Path.Combine(dataRoot, rel);
                string full = Path.GetFullPath(dest);
                if (!full.StartsWith(dataRoot, StringComparison.OrdinalIgnoreCase)) continue;
                try
                {
                    Directory.CreateDirectory(Path.GetDirectoryName(full));
                    OwnGame.Unshare(full);
                    File.Copy(src, full, true);
                    n++;
                }
                catch { }
            }
            return n;
        }

        public static string[] PersonalFiles()
        {
            try
            {
                if (!Directory.Exists(Paths.Personal)) return new string[0];
                return Directory.GetFiles(Paths.Personal, "*.*", SearchOption.AllDirectories);
            }
            catch { return new string[0]; }
        }
    }
}
