using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;

namespace Thornswood
{
    /// <summary>
    /// Steam's Updates setting for Skyrim: read on every start so the log says
    /// what it is, and changed only when a person says yes to a question that
    /// says what the change is.
    ///
    /// Why it matters. The downgrade puts the 1.6.1170 files in place, but
    /// Steam still believes the game is on the newest build, and with the
    /// setting on "Always keep this game updated" the next Skyrim update Steam
    /// takes undoes the whole downgrade with nobody pressing anything. Until
    /// this, the only protection was a line in the log asking people not to
    /// start Skyrim through Steam.
    ///
    /// The setting lives in Steam's own file for the game,
    /// steamapps\appmanifest_489830.acf in the library that holds Skyrim, as
    /// "AutoUpdateBehavior". 0 is "Always keep this game updated", 1 is "Only
    /// update this game when I launch it", 2 is "High Priority". 1 is what
    /// Steam's own Properties, Updates menu writes, and what every downgrade
    /// guide sets. It is a mitigation, not a lock: Steam still updates the game
    /// when it is started from Steam, which is what the downgrade's last log
    /// line already asks people not to do.
    ///
    /// Measured on Patrick's machine on 24 September, read only: the file is
    /// 1156 bytes of Valve's KeyValues text, tab separated, LF line endings,
    /// with "AutoUpdateBehavior" "0". It also carries the ReadOnly attribute,
    /// the only one of twenty manifests there that does, which is what some
    /// downgrade guides tell people to do. Steam was running at the time.
    ///
    /// So the write, when a person asks for it:
    ///   - never while Steam is running. Steam keeps the setting in memory and
    ///     writes its own copy of the file when it closes, which undoes an edit
    ///     made underneath it without a sign;
    ///   - changes the bytes of that one value and nothing else, read and
    ///     written byte for byte, because a manifest Steam cannot parse is a
    ///     much worse failure than an unwanted update. Anything not laid out
    ///     the way Steam writes it is left alone;
    ///   - goes through a temporary file and File.Replace, so a half-written
    ///     manifest can never be left behind;
    ///   - keeps a read-only file read-only, since somebody chose that.
    /// </summary>
    static class SteamUpdates
    {
        const string AppId = "489830";
        public const string Key = "AutoUpdateBehavior";
        public const string OnLaunchOnly = "1";

        /// <summary>The same change made by hand, for every message that leaves the file alone.</summary>
        public const string How =
            "To change it in Steam yourself: right click Skyrim Special Edition in the library, Properties, Updates, and pick \"Only update this game when I launch it\".";

        // Every byte maps to one char and back, so whatever else is in the
        // file, a UTF-8 path or a byte order mark, is written back exactly as
        // it was read. Everything this class looks for is plain ASCII.
        static readonly Encoding Bytes = Encoding.GetEncoding(28591);

        /// <summary>
        /// Steam's file for the Skyrim in <paramref name="skyrimFolder"/>, or ""
        /// when that folder is not a Steam library's steamapps\common\... folder,
        /// which is the case for a copy of the game the launcher made itself.
        /// Taken from the folder rather than from Steam's own install path,
        /// because a second drive's library keeps its own steamapps.
        /// </summary>
        public static string ManifestFor(string skyrimFolder)
        {
            try
            {
                if (string.IsNullOrEmpty(skyrimFolder)) return "";
                DirectoryInfo game = new DirectoryInfo(skyrimFolder.TrimEnd('\\', '/'));
                DirectoryInfo common = game.Parent;
                if (common == null || !string.Equals(common.Name, "common", StringComparison.OrdinalIgnoreCase)) return "";
                DirectoryInfo steamapps = common.Parent;
                if (steamapps == null || !string.Equals(steamapps.Name, "steamapps", StringComparison.OrdinalIgnoreCase)) return "";
                return Path.Combine(steamapps.FullName, "appmanifest_" + AppId + ".acf");
            }
            catch { return ""; }
        }

        /// <summary>Steam's own words for a value, as its Updates menu shows them.</summary>
        public static string Setting(string value)
        {
            if (value == OnLaunchOnly) return "Only update this game when I launch it";
            if (value == "2") return "High Priority";
            // 0, and no value at all, which Steam reads as its default.
            return "Always keep this game updated";
        }

        /// <summary>
        /// The top level AutoUpdateBehavior in a manifest's text: its value, ""
        /// when the key is not there, or null when the text is not a manifest
        /// laid out the way Steam writes one.
        /// </summary>
        public static string Value(string text)
        {
            List<Token> t = Tokens(text);
            if (t == null) return null;
            List<int> found = new List<int>();
            int close;
            if (!Walk(text, t, found, out close)) return null;
            if (found.Count == 0) return "";
            Token v = t[found[0]];
            return text.Substring(v.Start, v.End - v.Start);
        }

        /// <summary>
        /// The same text with the top level AutoUpdateBehavior set to 1, or null
        /// when it is not something to write into. Only the characters of the
        /// value change. When the key is not there at all, it goes in on a line
        /// of its own just above the closing brace, tab indented and separated
        /// like every other line Steam writes, with the file's own line ending.
        /// Already 1 comes back unchanged.
        /// </summary>
        public static string Held(string text)
        {
            List<Token> t = Tokens(text);
            if (t == null) return null;
            List<int> found = new List<int>();
            int close;
            if (!Walk(text, t, found, out close)) return null;

            if (found.Count > 0)
            {
                // From the end, so the earlier positions still hold.
                StringBuilder sb = new StringBuilder(text);
                for (int j = found.Count - 1; j >= 0; j--)
                {
                    Token v = t[found[j]];
                    sb.Remove(v.Start, v.End - v.Start);
                    sb.Insert(v.Start, OnLaunchOnly);
                }
                string after = sb.ToString();
                return after == text ? text : after;
            }

            // The closing brace has to be alone on its line, as Steam writes it.
            // Anything else is a shape this has never seen, and it is left alone.
            int lineStart = text.LastIndexOf('\n', close) + 1;
            if (lineStart == 0) return null;
            for (int j = lineStart; j < close; j++)
                if (text[j] != ' ' && text[j] != '\t') return null;
            string nl = text.IndexOf("\r\n", StringComparison.Ordinal) >= 0 ? "\r\n" : "\n";
            return text.Substring(0, lineStart) + "\t\"" + Key + "\"\t\t\"" + OnLaunchOnly + "\"" + nl + text.Substring(lineStart);
        }

        /// <summary>The value in the file, "" when the key is absent, null when it cannot be read or is not a manifest.</summary>
        public static string Read(string manifest)
        {
            try
            {
                if (string.IsNullOrEmpty(manifest) || !File.Exists(manifest)) return null;
                return Value(Bytes.GetString(File.ReadAllBytes(manifest)));
            }
            catch { return null; }
        }

        /// <summary>
        /// One line for the log on every start, so somebody who changed the
        /// setting in Steam can see it took, and somebody who has not is told
        /// what it will do. Null when there is no Steam file for this Skyrim or
        /// it cannot be read. Reads only.
        /// </summary>
        public static string Report(string skyrimFolder)
        {
            string manifest = ManifestFor(skyrimFolder);
            string v = Read(manifest);
            if (v == null) return null;
            if (v == OnLaunchOnly)
                return "Steam's Updates setting for Skyrim is \"" + Setting(v) + "\", so Steam leaves it on 1.6.1170 unless Skyrim is started from Steam.";
            return "Steam's Updates setting for Skyrim is \"" + Setting(v) + "\", so the next Skyrim update Steam takes moves it off 1.6.1170 and it has to be downgraded again. " + How;
        }

        /// <summary>True when the file is there, readable, and not already on 1. What the question after a downgrade is asked on.</summary>
        public static bool NeedsHolding(string manifest)
        {
            string v = Read(manifest);
            return v != null && v != OnLaunchOnly;
        }

        public static bool SteamRunning()
        {
            try
            {
                Process[] found = Process.GetProcessesByName("steam");
                foreach (Process p in found) p.Dispose();
                return found.Length > 0;
            }
            // Not knowing counts as running, so nothing is written under it.
            catch { return true; }
        }

        /// <summary>
        /// Sets Skyrim's Updates setting to "Only update this game when I launch
        /// it" in Steam's file. Only ever called after a person has said yes.
        /// Returns one line for the log saying what happened.
        /// </summary>
        public static string Hold(string manifest) { return Hold(manifest, SteamRunning()); }

        public static string Hold(string manifest, bool steamRunning)
        {
            if (string.IsNullOrEmpty(manifest) || !File.Exists(manifest))
                return "Steam's file for Skyrim was not found, so nothing was changed. " + How;
            if (steamRunning)
                return "Steam is still running, so nothing was changed. Steam writes its own copy of the setting back when it closes, which would undo the change. Exit Steam from its own menu first.";

            string before;
            try { before = Bytes.GetString(File.ReadAllBytes(manifest)); }
            catch (Exception ex) { return "Could not read " + manifest + ": " + ex.Message + " Nothing was changed. " + How; }

            string after = Held(before);
            if (after == null || Value(after) != OnLaunchOnly)
                return manifest + " is not laid out the way Steam writes it, so the launcher left it alone. " + How;
            if (after == before)
                return "Steam's Updates setting for Skyrim is already \"" + Setting(OnLaunchOnly) + "\". Nothing was changed.";

            string tmp = Path.Combine(Path.GetDirectoryName(manifest), "thornswood-" + AppId + ".tmp");
            FileAttributes attrs = FileAttributes.Normal;
            bool readOnly = false;
            try
            {
                File.WriteAllBytes(tmp, Bytes.GetBytes(after));
                attrs = File.GetAttributes(manifest);
                readOnly = (attrs & FileAttributes.ReadOnly) != 0;
                // File.Replace cannot take the place of a read-only file.
                if (readOnly) File.SetAttributes(manifest, attrs & ~FileAttributes.ReadOnly);
                File.Replace(tmp, manifest, null);
            }
            catch (Exception ex)
            {
                try { if (File.Exists(tmp)) File.Delete(tmp); } catch { }
                try { if (readOnly) File.SetAttributes(manifest, attrs); } catch { }
                return "Could not change " + manifest + ": " + ex.Message + " It is as it was. " + How;
            }
            if (readOnly)
            {
                try { File.SetAttributes(manifest, File.GetAttributes(manifest) | FileAttributes.ReadOnly); } catch { }
            }

            string now = Read(manifest);
            if (now != OnLaunchOnly)
                return "Wrote " + manifest + " but it " + (now == null ? "could not be read back" : "reads back as \"" + Setting(now) + "\"") + ". " + How;
            return "Steam's Updates setting for Skyrim is now \"" + Setting(OnLaunchOnly) + "\". Only that one value in " + manifest +
                   " changed" + (readOnly ? ", and the file is read-only again, as it was." : ".") +
                   " Steam's own Properties, Updates menu shows it the next time Steam starts.";
        }

        // ------------------------------------------------------------ reading

        // One token of Valve's KeyValues text: a quoted string, where Start and
        // End are the span inside the quotes, or a brace.
        struct Token { public char Kind; public int Start, End; }

        /// <summary>
        /// Quoted strings and braces, or null for anything else. Steam quotes
        /// every key and value in this file, and escapes a backslash or a quote
        /// inside one with a backslash (LauncherPath is written
        /// "C:\\Program Files (x86)\\Steam\\steam.exe"). An unquoted word or a
        /// [$WIN32] condition is legal KeyValues but not something Steam puts
        /// here, so it is refused rather than guessed at.
        /// </summary>
        static List<Token> Tokens(string text)
        {
            if (text == null) return null;
            List<Token> list = new List<Token>();
            int i = 0, n = text.Length;
            // A UTF-8 byte order mark, as bytes or as the one char it decodes to.
            if (text.StartsWith("\u00EF\u00BB\u00BF", StringComparison.Ordinal)) i = 3;
            else if (n > 0 && text[0] == '\uFEFF') i = 1;
            while (i < n)
            {
                char c = text[i];
                if (c == ' ' || c == '\t' || c == '\r' || c == '\n') { i++; continue; }
                if (c == '{' || c == '}')
                {
                    Token b = new Token();
                    b.Kind = c; b.Start = i; b.End = i + 1;
                    list.Add(b);
                    i++;
                    continue;
                }
                if (c == '/' && i + 1 < n && text[i + 1] == '/')
                {
                    while (i < n && text[i] != '\n') i++;
                    continue;
                }
                if (c != '"') return null;
                int start = ++i;
                while (i < n && text[i] != '"')
                {
                    if (text[i] == '\\') i++;
                    i++;
                }
                if (i >= n) return null;
                Token s = new Token();
                s.Kind = '"'; s.Start = start; s.End = i;
                list.Add(s);
                i++;
            }
            return list;
        }

        /// <summary>
        /// "AppState" { key value ... } and nothing after it, with every block
        /// balanced. Collects where each top level AutoUpdateBehavior value is,
        /// and where the closing brace of AppState sits.
        /// </summary>
        static bool Walk(string text, List<Token> t, List<int> found, out int close)
        {
            close = -1;
            if (t.Count < 3) return false;
            if (t[0].Kind != '"' || !Is(text, t[0], "AppState")) return false;
            if (t[1].Kind != '{') return false;
            int depth = 1;
            int i = 2;
            while (i < t.Count)
            {
                Token k = t[i];
                if (k.Kind == '}')
                {
                    depth--;
                    i++;
                    if (depth == 0) { close = k.Start; break; }
                    continue;
                }
                if (k.Kind != '"' || i + 1 >= t.Count) return false;
                Token v = t[i + 1];
                if (v.Kind == '{') { depth++; i += 2; continue; }
                if (v.Kind != '"') return false;
                if (depth == 1 && Is(text, k, Key)) found.Add(i + 1);
                i += 2;
            }
            return depth == 0 && i == t.Count;
        }

        // Valve's reader matches keys without regard to case.
        static bool Is(string text, Token t, string word)
        {
            return t.End - t.Start == word.Length &&
                   string.Compare(text, t.Start, word, 0, word.Length, StringComparison.OrdinalIgnoreCase) == 0;
        }
    }
}
