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
    /// Play page can turn through them one at a time, and the one door this
    /// end may write through: reporting a picture that should not be up.
    ///
    /// The site still keeps the queue and staff still choose what goes into
    /// gallery.json. Rotation asks /api/public, the same public feed the front
    /// page reads, so a launcher shows only what is already public and cannot
    /// put a picture up.
    ///
    /// WHAT THE LAUNCHER MAY DO AT THE SITE, AND WHY IT IS ONLY THIS (#731).
    /// The gallery doors that came with the site's #675 read who is asking
    /// out of who(req) in site\server.js, which is the twa Discord cookie a
    /// browser gets from /auth/discord/callback and nothing else. Two of them,
    /// /api/gallery/submit and /api/gallery/report, take the launcher's signed
    /// ticket in the query instead, verified the way /api/play/join verifies
    /// it. So Report goes over the ticket from here, and approve, reject and
    /// the delete of an approved shot stay on the site, where the person's
    /// cookie is: the launcher never sees one, and forging a staff answer at
    /// this end would be a second door into the same list.
    ///
    /// Everything fails quietly. A site that is down, a picture that will not
    /// load, an empty list: each leaves the card hidden with nothing said, the
    /// same way the online count and the roster do. The one thing that does
    /// speak is Report, because somebody pressed a button and is owed an
    /// answer.
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

        /// <summary>
        /// What /api/gallery/who says, for whoever is asking.
        ///
        /// Answered is the useful one here: a site older than the gallery
        /// doors has no such address and says nothing, and the Play page hides
        /// Report rather than offering a button that cannot work. The rest is
        /// the site's word about a BROWSER session, so from the launcher, which
        /// carries no cookie, Signed and Staff read false however the person is
        /// signed in elsewhere. Who the launcher is acting for is its ticket,
        /// and whether that ticket is staff is the dev flag /api/play/join
        /// already hands back (Standing.Dev), which is the same access.dev set
        /// the site calls staff.
        /// </summary>
        public class Who
        {
            public bool Answered;
            public bool Signed;
            public bool CanSubmit;
            public bool Staff;
            public bool Admin;
            public string Name = "";
        }

        // The public document. Same host the door and the roster already ask.
        static string Feed { get { return Discord.Site + "/api/public"; } }

        /// <summary>
        /// The site page where staff look through the queue, approve or reject
        /// what is waiting, and take an approved picture back down. The browser
        /// is signed in to Discord there, so that page can call the doors this
        /// end cannot.
        /// </summary>
        public static string StaffPage { get { return Discord.Site + "/uploads"; } }

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
        /// Blocking. Call it off the UI thread. What the site says the caller
        /// may do on the gallery, or an unanswered Who when the address is not
        /// there or the site could not be reached.
        /// </summary>
        public static Who AskWho()
        {
            var w = new Who();
            string text = GetText(Discord.Site + "/api/gallery/who", 5000);
            // A site without the gallery doors answers 404, which GetText
            // brings back as "". Anything else must at least carry the fields
            // before it is read as an answer.
            if (text.IndexOf("\"signed\"", StringComparison.Ordinal) < 0) return w;
            w.Answered = true;
            w.Signed = Flag(text, "signed");
            w.CanSubmit = Flag(text, "canSubmit");
            w.Staff = Flag(text, "staff");
            w.Admin = Flag(text, "admin");
            w.Name = Str(text, "name");
            return w;
        }

        /// <summary>
        /// Blocking. Call it off the UI thread. Reports one approved picture to
        /// staff, over the same signed ticket the door uses at /api/play/join.
        /// "" when the site took it, and a sentence to show the person when it
        /// did not.
        ///
        /// Nothing comes down here: the report sits in gallery-reports.json for
        /// staff to look at, and the picture stays on the gallery until one of
        /// them takes it off at the site.
        /// </summary>
        public static string Report(string name, string why)
        {
            if (name == null || name.Trim().Length == 0)
                return "There is no picture on the card to report.";
            if (!Discord.Linked)
                return "Connect Discord first, so the site knows who is reporting this.";

            string reason = why == null ? "" : why.Trim();
            // The site keeps the first 500 characters and drops the rest, so
            // the cut happens here rather than surprising anybody later.
            if (reason.Length > 500) reason = reason.Substring(0, 500);

            string url = Discord.Site + "/api/gallery/report?ticket=" +
                         Uri.EscapeDataString(Discord.Ticket);
            string body = "{\"name\":\"" + Discord.Escape(name.Trim()) + "\"" +
                          ",\"why\":\"" + Discord.Escape(reason) + "\"}";

            string reply = "";
            int code;
            try { code = Discord.PostJson(url, body, out reply); }
            catch (Exception ex)
            {
                Swallow.Note("Gallery.Report", ex);
                return "Could not reach thornswood.net to send that report.";
            }

            if (code == 200) return "";
            if (code == 0) return "Could not reach thornswood.net to send that report.";

            // The site says why on every refusal it means. Its own words are
            // better than anything invented here, so they are what is shown.
            string said = Str(reply, "error");
            if (said.Length == 0) said = Str(reply, "message");
            if (said.Length > 0) return said;

            if (code == 401) return "The site would not take this copy's Discord link. Connect Discord again and try once more.";
            if (code == 403) return "That Discord account is not allowed to report pictures.";
            if (code == 404) return "That picture is not on the gallery any more.";
            return "The site answered " + code + ", so the report was not kept.";
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

        /// <summary>
        /// One true or false field out of a flat document. Anything that is
        /// not the word true reads as false, so a field the site stops sending
        /// is a no rather than a yes.
        /// </summary>
        static bool Flag(string json, string key)
        {
            return Regex.IsMatch(json, "\"" + key + "\"\\s*:\\s*true");
        }
    }
}
