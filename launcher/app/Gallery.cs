using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Media.Imaging;

namespace Thornswood
{
    /// <summary>
    /// The pictures thornswood.net is showing from the world, read here so the
    /// Play page can turn through them one at a time.
    ///
    /// Read only. The site keeps the queue and the staff choose what goes into
    /// gallery.json; this end asks /api/public, the same public feed the front
    /// page reads, and shows what is already public. Nothing here sends,
    /// approves or writes anything back, so a launcher cannot put a picture up.
    ///
    /// Everything fails quietly. A site that is down, a picture that will not
    /// load, an empty list: each leaves the card hidden with nothing said, the
    /// same way the online count and the roster do.
    /// </summary>
    static class Gallery
    {
        /// <summary>One picture in the feed, and the loaded image once it has been fetched.</summary>
        public class Shot
        {
            public string Name = "";
            public string By = "";
            public string ImageUrl = "";     // absolute, ready to fetch
            public BitmapImage Image;        // null until Fetch has loaded it
        }

        // The public document. Same host the door and the roster already ask.
        static string Feed { get { return Discord.Site + "/api/public"; } }

        /// <summary>
        /// Blocking. Call it off the UI thread. The pictures the site is
        /// showing, in the order it put them, or an empty list when the feed
        /// cannot be read. No image is fetched here; that waits until the card
        /// turns to one.
        /// </summary>
        public static List<Shot> Load()
        {
            var shots = new List<Shot>();
            try
            {
                string text = GetText(Feed, 5000);
                if (text.Length == 0) return shots;

                // Only the gallery array out of the document, so a "url" or a
                // "name" somewhere else in it is not read as a picture.
                string arr = ArrayField(text, "gallery");
                if (arr.Length == 0) return shots;

                foreach (Match m in Regex.Matches(arr, "\\{(.*?)\\}", RegexOptions.Singleline))
                {
                    string body = m.Groups[1].Value;
                    string img = Resolve(Str(body, "url"), Str(body, "name"));
                    if (img.Length == 0) continue;

                    var s = new Shot();
                    s.Name = Str(body, "name");
                    s.By = Str(body, "by");
                    s.ImageUrl = img;
                    shots.Add(s);
                }
            }
            catch
            {
                // The gallery is a nicety on the Play page, never a reason to
                // stop anybody. A feed that will not read leaves the list empty
                // and the card hidden, and nothing is logged over a picture.
            }
            return shots;
        }

        /// <summary>
        /// The picture behind a shot, fetched once and kept on it. Blocking;
        /// call it off the UI thread. Null when it cannot be loaded, and the
        /// caller then turns to the next one.
        /// </summary>
        public static BitmapImage Fetch(Shot shot)
        {
            if (shot == null) return null;
            if (shot.Image != null) return shot.Image;
            try
            {
                byte[] raw = GetBytes(shot.ImageUrl, 8000);
                if (raw == null || raw.Length == 0) return null;

                var bi = new BitmapImage();
                bi.BeginInit();
                // OnLoad, so the stream can close under it and the image is not
                // read lazily and left blank, the same as Art.Load does.
                bi.CacheOption = BitmapCacheOption.OnLoad;
                bi.StreamSource = new MemoryStream(raw);
                bi.EndInit();
                bi.Freeze();
                shot.Image = bi;
                return bi;
            }
            catch { return null; }
        }

        /// <summary>
        /// The address to fetch a picture from. An absolute url is used as it
        /// is; a site-relative one such as /shot/&lt;name&gt; hangs off the
        /// site; failing both, the name alone goes to the shot door the site
        /// serves pictures from.
        /// </summary>
        static string Resolve(string url, string name)
        {
            if (url.StartsWith("http://", StringComparison.OrdinalIgnoreCase) ||
                url.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
                return url;
            if (url.Length > 0)
                return Discord.Site + (url.StartsWith("/") ? url : "/" + url);
            if (name.Length > 0)
                return Discord.Site + "/shot/" + name;
            return "";
        }

        // WebClient's own timeout is far too long, so a site that is merely
        // slow does not look like a hung launcher. The same Quick both Online
        // and Roster use.
        class Quick : WebClient
        {
            public int Ms = 5000;
            protected override WebRequest GetWebRequest(Uri address)
            {
                var r = base.GetWebRequest(address);
                if (r != null) { r.Timeout = Ms; }
                return r;
            }
        }

        static byte[] GetBytes(string url, int ms)
        {
            try
            {
                ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
                using (var q = new Quick())
                {
                    q.Ms = ms;
                    q.Headers["User-Agent"] = "ThornswoodLauncher/" + Updater.Version;
                    return q.DownloadData(url);
                }
            }
            catch { return null; }
        }

        static string GetText(string url, int ms)
        {
            byte[] raw = GetBytes(url, ms);
            if (raw == null || raw.Length == 0) return "";
            int at = 0;
            if (raw.Length >= 3 && raw[0] == 0xEF && raw[1] == 0xBB && raw[2] == 0xBF) at = 3;
            return Encoding.UTF8.GetString(raw, at, raw.Length - at);
        }

        /// <summary>
        /// The value of one array field out of a flat document, brackets and
        /// all, aware of strings so a bracket inside a name or a byline does
        /// not end it early. "" when the key is not there.
        /// </summary>
        static string ArrayField(string json, string key)
        {
            int i = json.IndexOf("\"" + key + "\"", StringComparison.Ordinal);
            if (i < 0) return "";
            i = json.IndexOf('[', i);
            if (i < 0) return "";

            int depth = 0;
            bool inStr = false;
            for (int j = i; j < json.Length; j++)
            {
                char c = json[j];
                if (inStr)
                {
                    if (c == '\\') { j++; continue; }
                    if (c == '"') inStr = false;
                    continue;
                }
                if (c == '"') { inStr = true; continue; }
                if (c == '[') depth++;
                else if (c == ']') { depth--; if (depth == 0) return json.Substring(i, j - i + 1); }
            }
            return "";
        }

        /// <summary>
        /// One string field out of an object body. Read with a regex rather
        /// than a serializer for the same reason Roster does it: the launcher
        /// targets the .NET Framework that ships in Windows, and its only
        /// serializer cannot read a shape it is not told in advance.
        /// </summary>
        static string Str(string body, string key)
        {
            var m = Regex.Match(body, "\"" + key + "\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
            if (!m.Success) return "";
            return m.Groups[1].Value
                    .Replace("\\\"", "\"")
                    .Replace("\\/", "/")
                    .Replace("\\\\", "\\");
        }
    }
}
