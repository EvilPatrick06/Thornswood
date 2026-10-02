using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;

namespace Thornswood
{
    /// <summary>
    /// The load order as the game counts it, and how to put a plugin list
    /// into the server's order. Pure functions over lists: nothing in here
    /// reads a path, a setting or the window, so the file compiles on its own
    /// with a test, and tools\LoadOrder.ps1 carries the same rule for the
    /// publisher, line for line.
    ///
    /// The game hands a normal index to the five masters, then to every
    /// plugin Skyrim.ccc names that is in Data, then to every enabled entry
    /// of plugins.txt that is in Data. Light plugins (an .esl, or the ESL
    /// flag in the header) get no normal index and are skipped throughout.
    /// That is the list Game.getModCount and getModName walk, and the client
    /// (loadOrderVerificationService) compares it with the server's manifest
    /// position by position: one name out of place from any index onwards is
    /// LOAD ORDER ERROR for the whole session.
    ///
    /// On 20 Sep the launcher said everything checked out while the game
    /// showed exactly that. Every plugin was present with the server's bytes;
    /// LOOT had re-sorted the list, and the launcher only compared it with
    /// the shipped reference, which had been re-sorted the same way.
    /// </summary>
    static class LoadOrder
    {
        /// <summary>The five the game loads before it reads any list. Never written to plugins.txt.</summary>
        public static readonly string[] Masters = {
            "Skyrim.esm", "Update.esm", "Dawnguard.esm", "HearthFires.esm", "Dragonborn.esm"
        };

        public static bool IsMaster(string name)
        {
            if (name == null) return false;
            string n = name.Trim();
            foreach (string m in Masters)
                if (string.Equals(m, n, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }

        /// <summary>
        /// The full plugin order the game will use: the masters, then the
        /// Skyrim.ccc entries that are in Data, then the enabled entries that
        /// are in Data, each skipped when isLightOrMissing says so, and a
        /// name never listed twice. Case insensitive throughout.
        /// </summary>
        public static List<string> GameOrder(IList<string> enabled, Func<string, bool> isLightOrMissing, IList<string> ccc, Func<string, bool> existsInData)
        {
            var order = new List<string>();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (string m in Masters) { order.Add(m); seen.Add(m); }
            Take(order, seen, ccc, isLightOrMissing, existsInData);
            Take(order, seen, enabled, isLightOrMissing, existsInData);
            return order;
        }

        static void Take(List<string> order, HashSet<string> seen, IList<string> names, Func<string, bool> isLightOrMissing, Func<string, bool> existsInData)
        {
            if (names == null) return;
            foreach (string raw in names)
            {
                string n = raw == null ? "" : raw.Trim();
                if (n.Length == 0 || seen.Contains(n)) continue;
                if (existsInData != null && !existsInData(n)) continue;
                if (isLightOrMissing != null && isLightOrMissing(n)) continue;
                seen.Add(n);
                order.Add(n);
            }
        }

        /// <summary>
        /// An official Creation Club plugin, by its name: cc, three letters for
        /// who made it, SSE and three digits (ccBGSSSE001-Fish.esm,
        /// ccQDRSSE001-SurvivalMode.esl, ccASVSSE001-ALMSIVI.esm). Every
        /// Creation Club name an Anniversary Edition Skyrim.ccc lists has that
        /// shape: 73 of its 74 lines on the shipping machine, the other being
        /// _ResourcePack.esl, which is the base game's. Decided by Patrick on
        /// 28 Sep (#479): Special Edition is all Thornswood needs, and somebody
        /// who owns the Anniversary upgrade still plays.
        /// </summary>
        public static bool IsCreation(string name)
        {
            if (name == null) return false;
            return Regex.IsMatch(name.Trim(), @"^cc[a-z]{3}sse\d{3}.*\.es[mlp]$", RegexOptions.IgnoreCase);
        }

        /// <summary>
        /// What an enabled list switches on that the reference does not, in
        /// list order, each once: the "is enabled but is not part of this
        /// build" issues. An official Creation Club plugin that takes no place
        /// in the game's order (light, or not in Data) is not counted. An
        /// Anniversary owner's list can name every creation they own, and the
        /// game's own rewrite of the list can add them, but one the game gives
        /// no index moves nothing the server compares, and Thornswood's own
        /// folder never has one in Data (OwnGame.UnwantedCreation). Stopping
        /// Play over it would stop them for nothing. A full one that is in
        /// Data still counts, because it takes a place and every plugin after
        /// it is then out of position.
        /// </summary>
        public static List<string> NotInBuild(IList<string> enabled, IList<string> reference, Func<string, bool> isLightOrMissing)
        {
            var want = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            if (reference != null)
                foreach (string r in reference) { string t = Norm(r); if (t.Length > 0) want.Add(t); }
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var result = new List<string>();
            if (enabled == null) return result;
            foreach (string raw in enabled)
            {
                string n = Norm(raw);
                if (n.Length == 0 || want.Contains(n) || !seen.Add(n)) continue;
                if (IsCreation(n) && (isLightOrMissing == null || isLightOrMissing(n))) continue;
                result.Add(n);
            }
            return result;
        }

        /// <summary>
        /// The first position where the two lists name different plugins, or
        /// where one of them ends; -1 when they are the same list. The same
        /// walk the client does, names only.
        /// </summary>
        public static int FirstMismatch(IList<string> game, IList<string> manifest)
        {
            int g = game == null ? 0 : game.Count;
            int m = manifest == null ? 0 : manifest.Count;
            int n = Math.Max(g, m);
            for (int i = 0; i < n; i++)
            {
                if (i >= g || i >= m) return i;
                if (!string.Equals(Norm(game[i]), Norm(manifest[i]), StringComparison.OrdinalIgnoreCase)) return i;
            }
            return -1;
        }

        static string Norm(string s)
        {
            return s == null ? "" : s.Trim();
        }

        /// <summary>The plugin an enabled line switches on, or null for a comment, a blank or a disabled line.</summary>
        public static string EnabledName(string line)
        {
            if (line == null) return null;
            string s = line.Trim();
            if (!s.StartsWith("*")) return null;
            string n = s.Substring(1).Trim();
            return n.Length == 0 ? null : n;
        }

        /// <summary>
        /// The same plugins.txt lines with the full enabled plugins in the
        /// server's order.
        ///
        /// The rule: a line moves only when it enables a plugin the server
        /// names and that plugin is not light. Those lines' positions are the
        /// slots, and the slots are refilled top to bottom in the server's
        /// order. Every other line keeps its index: the header, the comments,
        /// the disabled entries, the light plugins and anything the server
        /// does not name. So the result is the same set of lines, two light
        /// plugins that were in one order are still in it, and the full ones
        /// read in the server's order, which is what the game will count.
        ///
        /// The five masters are skipped on the server's side, because the game
        /// loads them before any list and a list never carries them. A light
        /// plugin the server names holds its place: the game gives it no index
        /// either way, and the flag is Checks.NotLight's to put right. A plugin
        /// the server names that no line enables is not this function's to
        /// switch on, so it returns null and leaves the list as it was; the
        /// "is turned off" and "is not installed" issues own that.
        /// </summary>
        public static List<string> Reorder(IList<string> lines, IList<string> manifest, Func<string, bool> isLight)
        {
            if (lines == null || manifest == null) return null;

            // Which line enables each plugin. Two lines enabling the same
            // name is a list nothing here can put in one order, so it is
            // left alone.
            var at = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
            for (int i = 0; i < lines.Count; i++)
            {
                string name = EnabledName(lines[i]);
                if (name == null) continue;
                if (at.ContainsKey(name)) return null;
                at[name] = i;
            }

            var order = new List<string>();
            var slots = new List<int>();
            var placed = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (string raw in manifest)
            {
                string n = Norm(raw);
                if (n.Length == 0 || IsMaster(n) || placed.Contains(n)) continue;
                placed.Add(n);
                int line;
                if (!at.TryGetValue(n, out line)) return null;
                if (isLight != null && isLight(n)) continue;
                order.Add(lines[line]);
                slots.Add(line);
            }

            slots.Sort();
            var result = new List<string>(lines);
            for (int k = 0; k < slots.Count; k++) result[slots[k]] = order[k];
            return result;
        }

        /// <summary>
        /// How many lines Reorder changed, and the plugin now sitting on the
        /// first of them, for saying what was done. Same length lists only.
        /// </summary>
        public static int Moved(IList<string> before, IList<string> after, out string first)
        {
            first = null;
            int n = 0;
            if (before == null || after == null || before.Count != after.Count) return 0;
            for (int i = 0; i < before.Count; i++)
            {
                if (string.Equals(before[i], after[i], StringComparison.Ordinal)) continue;
                if (first == null)
                {
                    first = EnabledName(after[i]);
                    if (first == null) first = after[i];
                }
                n++;
            }
            return n;
        }

        /// <summary>
        /// The manifest's plugin names that Reorder would have to enable and
        /// cannot, for saying which ones. Empty when Reorder would not return
        /// null for that reason.
        /// </summary>
        public static List<string> NotEnabled(IList<string> lines, IList<string> manifest)
        {
            var missing = new List<string>();
            if (lines == null || manifest == null) return missing;
            var have = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (string l in lines)
            {
                string name = EnabledName(l);
                if (name != null) have.Add(name);
            }
            foreach (string raw in manifest)
            {
                string n = Norm(raw);
                if (n.Length == 0 || IsMaster(n) || have.Contains(n)) continue;
                if (!missing.Contains(n)) missing.Add(n);
            }
            return missing;
        }
    }
}
