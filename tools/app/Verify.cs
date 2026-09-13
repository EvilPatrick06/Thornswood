using System;
using System.Collections.Generic;
using System.IO;

namespace Thornswood
{
    class Issue
    {
        public string Text;
        public bool Blocking;      // true = you will be refused by the server
        public Issue(string t, bool b) { Text = t; Blocking = b; }
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
            string live = Path.Combine(Paths.LocalAD, "plugins.txt");

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

            foreach (string p in want)
                if (!haveSet.Contains(p)) issues.Add(new Issue(p + " is turned off or missing.", true));

            foreach (string p in have)
                if (!wantSet.Contains(p)) issues.Add(new Issue(p + " is enabled but is not part of this build.", true));

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

        public static int Fix()
        {
            int n = 0;
            foreach (string f in new string[] { "plugins.txt", "loadorder.txt" })
            {
                string src = Path.Combine(Paths.Golden, f);
                if (!File.Exists(src)) continue;
                Directory.CreateDirectory(Paths.LocalAD);
                File.Copy(src, Path.Combine(Paths.LocalAD, f), true);
                n++;
            }
            return n;
        }

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
