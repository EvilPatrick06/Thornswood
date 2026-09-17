using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Text;

namespace Thornswood
{
    /// <summary>
    /// The launcher's end of the character register.
    ///
    /// Two calls, both to the voice service, which is used here for the same
    /// reason creation choices go through it: it is the only thing the
    /// launcher can reach over the internet and the gamemode can reach over
    /// loopback, and it is already running next to the game server.
    ///
    ///     Claim   these profile ids belong to this Steam account
    ///     Whoami  what does this Steam account own
    ///
    /// Claim goes out on every launch rather than once. That is what carries a
    /// character made before any of this existed: the id does not change, it
    /// just stops being a fact known only to one hard drive. It also means the
    /// register repairs itself, since losing it costs one launch per person.
    ///
    /// Nothing here is load bearing. Every failure is quiet and leaves the
    /// launcher behaving exactly as it did before, because the alternative is
    /// a server hiccup standing between somebody and their game.
    /// </summary>
    static class Account
    {
        public class Entry
        {
            public int Slot;
            public int ProfileId;
            public string Name = "";
            public long Played;

            // Everything else the launcher knows about a character and the
            // game server does not.
            //
            // These were left out of the first version on the theory that the
            // profile id is the character and the rest is decoration. It is
            // not: a restored slot with no trade, no town and no hours reads
            // as a blank character in the launcher, next to one that has them,
            // and looks like the restore only half worked. Which, without
            // these, it had.
            public long Seconds;
            public string Trade = "";
            public string Town = "";
        }

        static string Url(Config cfg, string route)
        {
            if (cfg == null || string.IsNullOrEmpty(cfg.ServerAddress)) return "";
            int port = 7778;
            int.TryParse(cfg.VoicePort, out port);
            if (port <= 0) port = 7778;
            return "http://" + cfg.ServerAddress + ":" + port + route;
        }

        /// <summary>What this Steam account owns. Empty on any failure.</summary>
        public static List<Entry> Whoami(Config cfg, string steamId)
        {
            var outp = new List<Entry>();
            if (string.IsNullOrEmpty(steamId)) return outp;
            string url = Url(cfg, "/whoami");
            if (url.Length == 0) return outp;

            // No password. SkyMP has no join password: there is no sPassword in
            // server-settings.json and nothing in the gamemode reads one, and
            // the voice server never looks at this field either. It was carried
            // over from Skyrim Together, and all it did here was put a value
            // that looks like a credential onto the wire in clear text.
            string body = "{\"steamId\":\"" + Esc(steamId) + "\"}";
            string answer = Post(url, body);
            if (answer == null) return outp;

            // Parsed by hand. The launcher's only serializer is the data
            // contract one, and teaching it a shape for one small reply is
            // more moving parts than reading four numbers out of a line.
            foreach (string block in Blocks(answer))
            {
                var e = new Entry();
                e.Slot = (int)Num(block, "slot");
                e.ProfileId = (int)Num(block, "profileId");
                e.Played = Num(block, "played");
                e.Seconds = Num(block, "seconds");
                e.Name = Str(block, "name");
                e.Trade = Str(block, "trade");
                e.Town = Str(block, "town");
                if (e.Slot > 0 && e.ProfileId > 0) outp.Add(e);
            }
            return outp;
        }

        /// <summary>Record that this Steam account owns these. True when it landed.</summary>
        public static bool Claim(Config cfg, string steamId, List<Entry> list)
        {
            if (string.IsNullOrEmpty(steamId) || list == null || list.Count == 0) return false;
            string url = Url(cfg, "/claim");
            if (url.Length == 0) return false;

            var sb = new StringBuilder();
            sb.Append("{\"steamId\":\"").Append(Esc(steamId))
              .Append("\",\"profiles\":[");
            for (int i = 0; i < list.Count; i++)
            {
                if (i > 0) sb.Append(',');
                sb.Append("{\"slot\":").Append(list[i].Slot)
                  .Append(",\"profileId\":").Append(list[i].ProfileId)
                  .Append(",\"played\":").Append(list[i].Played)
                  .Append(",\"seconds\":").Append(list[i].Seconds)
                  .Append(",\"name\":\"").Append(Esc(list[i].Name))
                  .Append("\",\"trade\":\"").Append(Esc(list[i].Trade))
                  .Append("\",\"town\":\"").Append(Esc(list[i].Town)).Append("\"}");
            }
            sb.Append("]}");

            return Post(url, sb.ToString()) != null;
        }

        // ------------------------------------------------------------ plumbing

        static string Post(string url, string body)
        {
            try
            {
                var req = (HttpWebRequest)WebRequest.Create(url);
                req.Method = "POST";
                req.ContentType = "application/json";
                req.Timeout = 6000;
                req.ReadWriteTimeout = 6000;
                byte[] raw = Encoding.UTF8.GetBytes(body);
                req.ContentLength = raw.Length;
                using (Stream s = req.GetRequestStream()) { s.Write(raw, 0, raw.Length); }
                using (var resp = (HttpWebResponse)req.GetResponse())
                {
                    int code = (int)resp.StatusCode;
                    if (code < 200 || code >= 300) return null;
                    using (Stream s = resp.GetResponseStream())
                    {
                        if (s == null) return "";
                        using (var r = new StreamReader(s, Encoding.UTF8)) return r.ReadToEnd();
                    }
                }
            }
            catch { return null; }
        }

        // Every {...} run inside the profiles array. Good enough for a reply
        // this service wrote itself and nothing deeper is ever nested in it.
        static List<string> Blocks(string json)
        {
            var outp = new List<string>();
            if (string.IsNullOrEmpty(json)) return outp;
            int at = json.IndexOf("\"profiles\"", StringComparison.OrdinalIgnoreCase);
            if (at < 0) return outp;
            int depth = 0, start = -1;
            for (int i = at; i < json.Length; i++)
            {
                char c = json[i];
                if (c == '{') { if (depth == 0) start = i; depth++; }
                else if (c == '}')
                {
                    depth--;
                    if (depth == 0 && start >= 0) { outp.Add(json.Substring(start, i - start + 1)); start = -1; }
                }
                else if (c == ']' && depth == 0) break;
            }
            return outp;
        }

        static long Num(string block, string key)
        {
            int at = block.IndexOf("\"" + key + "\"", StringComparison.Ordinal);
            if (at < 0) return 0;
            at = block.IndexOf(':', at);
            if (at < 0) return 0;
            var sb = new StringBuilder();
            for (int i = at + 1; i < block.Length; i++)
            {
                char c = block[i];
                if (c == ' ') continue;
                if ((c >= '0' && c <= '9') || (c == '-' && sb.Length == 0)) sb.Append(c);
                else break;
            }
            long v;
            return long.TryParse(sb.ToString(), out v) ? v : 0;
        }

        static string Str(string block, string key)
        {
            int at = block.IndexOf("\"" + key + "\"", StringComparison.Ordinal);
            if (at < 0) return "";
            at = block.IndexOf(':', at);
            if (at < 0) return "";
            int open = block.IndexOf('"', at);
            if (open < 0) return "";
            var sb = new StringBuilder();
            for (int i = open + 1; i < block.Length; i++)
            {
                char c = block[i];
                if (c == '\\' && i + 1 < block.Length) { sb.Append(block[++i]); continue; }
                if (c == '"') break;
                sb.Append(c);
            }
            return sb.ToString();
        }

        static string Esc(string s)
        {
            if (s == null) return "";
            var sb = new StringBuilder();
            foreach (char c in s)
            {
                if (c == '"' || c == '\\') sb.Append('\\').Append(c);
                else if (c >= ' ') sb.Append(c);
            }
            return sb.ToString();
        }
    }
}
