using System;
using System.Collections.Generic;
using System.IO;
using System.Text.RegularExpressions;

namespace Thornswood
{
    /// <summary>
    /// Settings this build insists on, re-applied every time you press Play.
    ///
    /// Several of these mods keep their settings in memory and write their own
    /// ini back over the top when Skyrim exits. That means a fix written into
    /// one of those files does not survive the next session: the mod simply
    /// puts its own value back on the way out. Shipping the file in an update
    /// has the same problem, because the very next quit undoes it.
    ///
    /// So rather than editing those files once and hoping, the launcher writes
    /// them immediately before it starts the game, every time. The mod can
    /// write whatever it likes on the way out; the next launch puts it back.
    ///
    /// Only settings that fix a real fault belong here. Anything a person might
    /// reasonably want to change for themselves does not, or the launcher ends
    /// up arguing with them every time they play.
    /// </summary>
    static class Enforce
    {
        class Rule
        {
            public string File, Key, Value, Why;
            public Rule(string f, string k, string v, string why) { File = f; Key = k; Value = v; Why = why; }
        }

        static string P(string name) { return Path.Combine(Paths.Game, "Data\\SKSE\\Plugins\\" + name); }

        static List<Rule> Rules()
        {
            var l = new List<Rule>();

            // Skyrim Souls keeps the world running while a menu is open. Two of
            // its menus break badly in this build: the favourites list crashes
            // the game through Inventory Interface Information Injector, and
            // the Tab menu locks up with no cursor and no way out.
            l.Add(new Rule(P("SkyrimSoulsRE.ini"), "bFavoritesMenu", "false", "the favourites menu crash"));
            l.Add(new Rule(P("SkyrimSoulsRE.ini"), "bTweenMenu",     "false", "the Tab menu locking up"));

            return l;
        }

        /// <summary>
        /// Writes every rule, plus wherever the launcher has been told to put
        /// the minimap. Returns how many values it had to change, so a launch
        /// that changed nothing can stay quiet.
        /// </summary>
        public static int Apply(Config cfg)
        {
            int changed = 0;
            foreach (Rule r in Rules())
                if (Set(r.File, r.Key, r.Value)) changed++;

            return changed;
        }

        static bool Set(string file, string key, string value) { return SetNth(file, key, value, 1); }

        /// <summary>
        /// Replaces the nth live occurrence of a key. These files repeat the
        /// same key under several headings, so the minimap's own position is
        /// the first uPositionX and the compass and meters own the rest.
        /// Returns true only when something actually changed.
        /// </summary>
        static bool SetNth(string file, string key, string value, int which)
        {
            try
            {
                if (!File.Exists(file)) return false;
                var lines = new List<string>(File.ReadAllLines(file));
                var rx = new Regex("^(\\s*)" + Regex.Escape(key) + "\\s*=\\s*(.*?)\\s*$", RegexOptions.IgnoreCase);

                int seen = 0;
                for (int i = 0; i < lines.Count; i++)
                {
                    string t = lines[i].TrimStart();
                    if (t.StartsWith(";") || t.StartsWith("#")) continue;
                    Match m = rx.Match(lines[i]);
                    if (!m.Success) continue;

                    seen++;
                    if (seen != which) continue;
                    if (string.Equals(m.Groups[2].Value, value, StringComparison.OrdinalIgnoreCase)) return false;

                    lines[i] = key + " = " + value;
                    File.WriteAllLines(file, lines.ToArray());
                    return true;
                }
            }
            catch { }
            return false;
        }

        /// <summary>What the table above is holding in place, for the Help page.</summary>
        public static string[] Describe()
        {
            var l = new List<string>();
            foreach (Rule r in Rules())
                l.Add(Path.GetFileName(r.File) + "  ->  " + r.Key + " = " + r.Value + "   (" + r.Why + ")");
            return l.ToArray();
        }
    }
}
