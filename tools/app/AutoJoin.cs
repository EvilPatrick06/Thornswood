using System;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;

namespace Thornswood
{
    /// <summary>
    /// Points the game at the server before it starts.
    ///
    /// Under Skyrim Together this was a real piece of work: its join menu was a
    /// Chromium page, so connecting for someone meant injecting a script beside
    /// it, wrapping the bridge object the game put on the window, fanning out
    /// listeners because the bridge allowed only one per event, and retrying.
    ///
    /// SkyMP has no join menu. The client reads server-ip and server-port out of
    /// skymp5-client-settings.txt at startup and connects on its own, so all
    /// that is left is writing two values into a file.
    ///
    /// Edited as text rather than parsed and rewritten. DataContractJsonSerializer
    /// drops keys it was not told about, and this file belongs to SkyMP, not to
    /// us: a key added upstream would vanish the first time the launcher touched
    /// it. Everything not named here is left exactly as found.
    /// </summary>
    static class AutoJoin
    {
        public static string SettingsFile
        {
            get { return Path.Combine(Paths.Game, "Data\\Platform\\Plugins\\skymp5-client-settings.txt"); }
        }

        /// <summary>Writes the address and port. Returns a line for the log, or null when nothing changed.</summary>

        /// <summary>
        /// Cheap structural check before anything is written back.
        ///
        /// This file is read by SkyrimPlatform while it loads plugins, so a
        /// malformed one does not just break joining: it throws during startup
        /// and every plugin after the throw never runs. That is the emote wheel
        /// and the creation menus gone, with the only evidence a single line in
        /// skyrim-platform.log that nobody thinks to look at. Whatever is wrong
        /// with an edit, leaving the old file in place is better.
        ///
        /// Not a parser, deliberately: balanced braces and quotes catch the
        /// shape of every corruption an edit here can produce, and the launcher
        /// has no JSON reader that round trips a document it was not told about.
        /// </summary>
        static bool LooksLikeJson(string t)
        {
            if (string.IsNullOrEmpty(t)) return false;
            string s = t.Trim();
            if (s.Length < 2 || s[0] != '{' || s[s.Length - 1] != '}') return false;

            int depth = 0;
            bool inStr = false, esc = false;
            foreach (char c in s)
            {
                if (inStr)
                {
                    if (esc) { esc = false; continue; }
                    if (c == '\\') { esc = true; continue; }
                    if (c == '"') inStr = false;
                    continue;
                }
                if (c == '"') { inStr = true; continue; }
                if (c == '{' || c == '[') depth++;
                else if (c == '}' || c == ']') { depth--; if (depth < 0) return false; }
                // A lone $ outside a string is the signature of a regex
                // replacement that did not expand, which is what put "$17777"
                // in this file where the port should have been.
                else if (c == '$') return false;
            }
            return depth == 0 && !inStr;
        }

        public static string Apply(Config cfg)
        {
            try
            {
                string file = SettingsFile;
                if (!File.Exists(file))
                    return "SkyMP's client settings file is missing, so the server address was not set.";

                if (!cfg.AutoJoin)
                    return "Auto join is off, leaving the server address as it is.";

                int port;
                if (!int.TryParse(cfg.ServerPort, out port) || port <= 0) port = 7777;

                string host = cfg.ServerAddress;
                if (string.IsNullOrEmpty(host))
                    return "No server address is set, so the game was left pointing wherever it was.";

                string before = File.ReadAllText(file);
                string after = SetString(before, "server-ip", host);
                after = SetNumber(after, "server-port", port);

                // Where the client goes looking for the load order it has to
                // match. Left empty, getMasterUrl falls back to
                // https://gateway.skymp.net and getServerMasterKey falls back
                // to "<address>:<port>", so every launch asked a public server
                // about an address it has never heard of, five times, and got
                // an empty mod list back.
                //
                // An empty list is not an error to that code. It prints the
                // yellow "you have more mods than server" line for five
                // seconds and then compares against nothing, so the load order
                // has never once been checked here. The gamemode publishes the
                // real manifest at this key on the resources port, which makes
                // the warning go away and the check mean something.
                //
                // A name rather than the address, because the key lands in a
                // file path on the server and a colon cannot go in one.
                after = SetString(after, "master", "http://" + host + ":" + ResourcePort(port));
                after = SetString(after, "server-master-key", "thornswood");

                // The publish step diffs the game folder by size and date, so a
                // file rewritten on every launch would show as a change every
                // single time even when nothing moved.
                if (string.Equals(before, after, StringComparison.Ordinal)) return null;

                if (!LooksLikeJson(after))
                    return "Left the client settings alone: the edit would have broken the file, " +
                           "and a broken one stops SkyrimPlatform loading any plugin at all.";

                File.WriteAllText(file, after, new UTF8Encoding(false));
                return "Pointed the game at " + host + ":" + port + ".";
            }
            catch (Exception ex)
            {
                return "Could not set the server address: " + ex.Message;
            }
        }

        /// <summary>
        /// The port the server serves its resources folder on.
        ///
        /// Worked out the same way the server does it, in ui.ts:
        ///
        ///     const uiPort = settings.port === 7777 ? 3000 : settings.port + 1;
        /// </summary>
        static int ResourcePort(int gamePort)
        {
            return gamePort == 7777 ? 3000 : gamePort + 1;
        }

        /// <summary>Which character slot the client asks the server for.</summary>
        public static bool SetProfileId(int profileId)
        {
            try
            {
                string file = SettingsFile;
                if (!File.Exists(file)) return false;
                string before = File.ReadAllText(file);
                string after = SetNumber(before, "profileId", profileId);
                if (string.Equals(before, after, StringComparison.Ordinal)) return false;
                if (!LooksLikeJson(after)) return false;
                File.WriteAllText(file, after, new UTF8Encoding(false));
                return true;
            }
            catch { return false; }
        }

        // ------------------------------------------------------------ text edits
        // Replace the value of an existing key, or add the key if it is absent.
        // Absent is worth handling: an older settings file predates some of
        // these keys, and silently doing nothing would leave the game pointed at
        // localhost with no sign of why.

        static string SetString(string json, string key, string value)
        {
            string quoted = "\"" + Escape(value) + "\"";
            var rx = new Regex("(\"" + Regex.Escape(key) + "\"\\s*:\\s*)(\"(?:[^\"\\\\]|\\\\.)*\"|null)");
            if (rx.IsMatch(json)) return rx.Replace(json, "${1}" + quoted.Replace("$", "$$"), 1);
            return Insert(json, key, quoted);
        }

        static string SetNumber(string json, string key, int value)
        {
            var rx = new Regex("(\"" + Regex.Escape(key) + "\"\\s*:\\s*)(-?\\d+(?:\\.\\d+)?|null)");
            // ${1} rather than $1, and the braces are the whole point. A
            // replacement of "$1" + 7777 is the string "$17777", which .NET
            // reads as capture group 17777. There is no such group, so it gives
            // up and writes the six characters literally: the file ends up with
            //     $17777
            // where the port should be, and profile id 2 lands as $12. That is
            // not valid JSON, so SkyrimPlatform throws while loading plugins,
            // and every plugin after the throw never runs. It costs you the
            // emote wheel and the creation menus and says nothing about why.
            if (rx.IsMatch(json)) return rx.Replace(json, "${1}" + value.ToString(), 1);
            return Insert(json, key, value.ToString());
        }

        static string Insert(string json, string key, string literal)
        {
            int brace = json.IndexOf('{');
            if (brace < 0) throw new Exception("skymp5-client-settings.txt is not an object");

            // Match the file's own indentation rather than imposing ours, so the
            // diff stays to the one line that actually changed.
            string indent = "  ";
            var m = Regex.Match(json.Substring(brace), "\\r?\\n([ \\t]+)\"");
            if (m.Success) indent = m.Groups[1].Value;

            string rest = json.Substring(brace + 1);
            string sep = Regex.IsMatch(rest, "^\\s*\\}") ? "" : ",";
            return json.Substring(0, brace + 1) + Environment.NewLine +
                   indent + "\"" + key + "\": " + literal + sep + rest;
        }

        static string Escape(string s)
        {
            if (s == null) return "";
            var b = new StringBuilder();
            foreach (char c in s)
            {
                if (c == '\\' || c == '"') b.Append('\\').Append(c);
                else if (c == '\r') b.Append("\\r");
                else if (c == '\n') b.Append("\\n");
                else if (c == '\t') b.Append("\\t");
                else if (c < ' ') b.Append("\\u").Append(((int)c).ToString("x4"));
                else b.Append(c);
            }
            return b.ToString();
        }
    }
}
