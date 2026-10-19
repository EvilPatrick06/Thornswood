using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Security.Cryptography;
using System.Text;

namespace Thornswood
{
    static partial class Updater
    {
        public const string Version = "1.2.5";

        /// <summary>
        /// The collection revision the last feed named, or 0 when it named
        /// none. Set by OnVersionDoc as the document arrives, so anything that
        /// asks after that is asking about the release that is actually live.
        ///
        /// Held here rather than in Config because it is not a setting: it is
        /// a fact about the server, and writing it into config.json would mean
        /// a stale copy outliving the release it came from.
        /// </summary>
        public static int FeedCollectionRevision;

        /// <summary>
        /// The address the last check actually read version.json from, so
        /// launcher.log can be read back afterwards and say where the checks
        /// went: the site feed on thornswood.net, the only source since #907.
        /// </summary>
        public static string LastFeedUrl = "";

        /// <summary>
        /// True when the last check was answered out of the cache below
        /// because the feed said nothing had changed, so nothing was
        /// downloaded.
        /// </summary>
        public static bool LastNotModified;

        /// <summary>
        /// One answer from the site feed: the document, the ETag it arrived
        /// with, and the address it came from. All three together, in one
        /// object that is never edited after it is built, because a check from
        /// the timer and a check somebody pressed can be in flight at the same
        /// time. Three separate fields could be left holding one check's tag
        /// beside another's document, and a launcher asking with a tag that
        /// does not belong to the copy it holds would be told nothing had
        /// changed and go on believing an older feed.
        /// </summary>
        class Cached
        {
            public string Url;
            public string Etag;
            public string LastModified;
            public VersionDoc Doc;
        }

        // The last answer the site feed gave.
        //
        // While somebody plays, Check runs every thirty seconds, because the
        // countdown that closes the game has to land inside the server's five
        // minute window (Shell.CheckUpdatesInPlay). The document is around
        // ninety kilobytes and only changes when somebody ships, so that was
        // ten megabytes an hour per launcher to be told the same thing. With
        // the tag on the next request the site answers 304 and no body.
        //
        // Not in config.json on purpose: the tag is worth nothing without the
        // document it belongs to, and a config that kept the tag alone would
        // start up, ask with it, be told nothing had changed, and have nothing
        // to read. So the tag and the document are kept together, in memory
        // and in one file in Profile (CacheFile, #443), and the file is only
        // believed when the document in it still reads. Before the file, every
        // start of the launcher downloaded the whole feed again.
        static Cached cached;
        static bool cacheRead;
        const string CacheMagic = "Thornswood feed cache 1";

        // WebClient has no timeout worth the name, and the default is long
        // enough that a GitHub which accepts the connection and then says
        // nothing looks like a hung launcher. The same helper Online and
        // Roster use. Timeout is the wait for an answer, not for the body, so
        // a large asset still downloads for as long as it needs.
        class Quick : WebClient
        {
            public int Ms = 10000;
            // For the feed only (#443): If-Modified-Since has to go through
            // the request's own property, because WebClient refuses it as a
            // plain header, and a compressed feed is a quarter of the size.
            public DateTime Since = DateTime.MinValue;
            public bool Gzip;
            // The status of the last answer that WebClient returned from
            // rather than threw on, which is every 2xx. 200 and 204 are both
            // success to it and DownloadData gives back bytes either way (an
            // empty array for 204), so a caller that has to tell them apart
            // reads this (#2636). 0 until an answer arrives.
            public int Status;
            protected override WebResponse GetWebResponse(WebRequest request)
            {
                var r = base.GetWebResponse(request);
                var h = r as HttpWebResponse;
                if (h != null) Status = (int)h.StatusCode;
                return r;
            }
            protected override WebRequest GetWebRequest(Uri address)
            {
                var r = base.GetWebRequest(address);
                if (r != null) { r.Timeout = Ms; }
                var h = r as HttpWebRequest;
                if (h != null)
                {
                    if (Since != DateTime.MinValue) h.IfModifiedSince = Since;
                    if (Gzip) h.AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate;
                }
                return r;
            }
        }

        static WebClient Client(Config cfg, bool octet, string url)
        {
            var wc = new Quick();
            wc.Headers["User-Agent"] = "ThornswoodLauncher/" + Version;
            // The token only ever goes to GitHub's own API, never to whatever
            // host an asset URL happens to point at.
            bool github = false;
            try { github = new Uri(url).Host.Equals("api.github.com", StringComparison.OrdinalIgnoreCase); }
            catch (Exception ex) { Swallow.Note("Updater.Client, uri host", ex); }
            if (github && !string.IsNullOrEmpty(cfg.UpdateToken))
                wc.Headers["Authorization"] = "Bearer " + cfg.UpdateToken;
            // GitHub Contents API wants the raw media type; a direct https feed
            // on thornswood.net is ordinary JSON (#649).
            if (github)
                wc.Headers["Accept"] = octet ? "application/octet-stream" : "application/vnd.github.raw";
            else if (octet)
                wc.Headers["Accept"] = "application/octet-stream";
            else
                wc.Headers["Accept"] = "application/json";
            return wc;
        }

        /// <summary>The feed this build reads when config.json names none of Thornswood's.</summary>
        public const string MainFeed = "https://thornswood.net/feed/version.json";
        public const string DevFeed = "https://thornswood.net/feed-dev/version.json";

        /// <summary>
        /// Where version.json is read from. Always somewhere: the update check
        /// cannot be switched off (#937).
        ///
        /// Until #937 an UpdateFeedUrl blanked or bent in config.json turned
        /// the check off, and a launcher with no update source let Play through
        /// on its own say (Unblock, gone with this). So an out of date
        /// launcher was one edit away from playing. Now config.json may only
        /// move the feed within thornswood.net, over https, the way a feed
        /// announces a move (updateFeedUrl); anything else, empty included, is
        /// the built-in address for this build's channel. A feed address that
        /// then does not answer keeps Play shut like any other failed check,
        /// and a dev build pointed at the main feed gets no join pass from the
        /// site, which checks the launcher against its own channel's feed.
        /// </summary>
        public static string FeedUrl(Config cfg)
        {
            bool dev = cfg != null &&
                       (string.Equals(cfg.Channel, "dev", StringComparison.OrdinalIgnoreCase) ||
                        string.Equals(cfg.UpdateBranch, "dev", StringComparison.OrdinalIgnoreCase));
            string builtIn = dev ? DevFeed : MainFeed;
            string said = (cfg == null || cfg.UpdateFeedUrl == null) ? "" : cfg.UpdateFeedUrl.Trim();
            Uri u;
            if (said.Length == 0 || !Uri.TryCreate(said, UriKind.Absolute, out u)) return builtIn;
            if (u.Scheme != Uri.UriSchemeHttps || !u.IsDefaultPort || u.UserInfo.Length > 0) return builtIn;
            string host = u.Host.ToLowerInvariant();
            if (host != "thornswood.net" && !host.EndsWith(".thornswood.net", StringComparison.Ordinal)) return builtIn;
            // A feed may move within its own channel, never across it (Djinn,
            // 2 Oct). The dev feed shipped updateFeedUrl = the main feed on
            // 1 Oct, every dev launcher saved it, and from then on read the
            // main feed: no dev launcher update, no dev client, and Play shut
            // for good on a Client row nothing could put right. A dev build
            // reads a feed-dev address or its built-in one, and a main build
            // never reads feed-dev.
            bool saysDev = u.AbsolutePath.IndexOf("/feed-dev/", StringComparison.OrdinalIgnoreCase) >= 0;
            if (saysDev != dev) return builtIn;
            return said;
        }

        /// <summary>
        /// True only when the published launcher is genuinely newer than the
        /// one running.
        ///
        /// This used to be a plain "different from mine" test, and different
        /// includes older. So a machine that had just built a launcher would
        /// open it, see an older number in the release, call that an update,
        /// and overwrite the build it had just made with the one it replaced.
        /// It looks exactly like the build silently not happening, and the
        /// person who did the building is the only one it can happen to.
        /// </summary>
        public static bool IsNewer(string remote, string local)
        {
            if (string.IsNullOrEmpty(remote)) return false;
            if (string.IsNullOrEmpty(local)) return true;
            if (string.Equals(remote, local, StringComparison.OrdinalIgnoreCase)) return false;

            int[] a = Parts(remote), b = Parts(local);
            if (a == null || b == null)
            {
                // Either side did not parse as dotted integers. A different
                // string is not proof that the remote is newer, so an older
                // unreadable version is not an update.
                return false;
            }
            int n = Math.Max(a.Length, b.Length);
            for (int i = 0; i < n; i++)
            {
                int x = i < a.Length ? a[i] : 0;
                int y = i < b.Length ? b[i] : 0;
                if (x != y) return x > y;
            }
            return false;
        }

        static int[] Parts(string v)
        {
            try
            {
                string[] bits = v.Trim().TrimStart('v', 'V').Split('.');
                var o = new int[bits.Length];
                for (int i = 0; i < bits.Length; i++)
                {
                    if (!int.TryParse(bits[i], out o[i])) return null;
                }
                return o;
            }
            catch { return null; }
        }

        /// <summary>
        /// Reads version.json from FeedUrl (direct https on the site, #649),
        /// with the ETag of the last copy so an unchanged feed is answered 304
        /// and not downloaded again. Until #907 a miss fell back to the GitHub
        /// Contents API on UpdateRepo (Thornswood-Releases); that repository is
        /// gone, so a miss throws and the next check tries the site again.
        /// Never null: updates cannot be off (#937).
        /// </summary>
        public static VersionDoc Check(Config cfg)
        {
            ServicePointManager.SecurityProtocol |= (SecurityProtocolType)3072; // Tls12 added, never replaced (#1360)
            LastNotModified = false;

            string feedUrl = FeedUrl(cfg);
            LastFeedUrl = feedUrl;
            // No GitHub fallback any more (#907): Thornswood-Releases is gone.
            // A site feed that misses is what the caller gets, which reads as
            // no answer rather than as no update, so the in play clock is left
            // where it is (Shell.CheckUpdatesInPlay) and the next check, thirty
            // seconds on, asks the site again.
            try { return FromSite(cfg, feedUrl); }
            catch (Exception ex) { throw WrapFeedFail(ex, true); }
        }

        /// <summary>
        /// The long-poll tip beside version.json (#2440). Same host and channel
        /// as FeedUrl: /feed/watch or /feed-dev/watch. A launcher keeps one of
        /// these open so a Ship is seen without restarting or pressing Check now.
        /// </summary>
        public static string WatchUrl(Config cfg)
        {
            string feed = FeedUrl(cfg);
            const string leaf = "/version.json";
            if (feed.EndsWith(leaf, StringComparison.OrdinalIgnoreCase))
                return feed.Substring(0, feed.Length - leaf.Length) + "/watch";
            // FeedUrl always ends in version.json today; if a moved feed uses
            // another leaf, tip at the same folder.
            int slash = feed.LastIndexOf('/');
            if (slash > 0) return feed.Substring(0, slash) + "/watch";
            return feed + "/watch";
        }

        /// <summary>
        /// Long-poll /feed/watch with the ETag of the copy already in hand
        /// (#2440). True when the tip says the feed moved (HTTP 200); false
        /// when the wait ran out unchanged (HTTP 204). Throws when the tip
        /// cannot be reached, gives no answer in time, or answers anything
        /// else, so the caller says so in launcher.log and backs off.
        /// </summary>
        public static bool WaitForFeedChange(Config cfg)
        {
            ServicePointManager.SecurityProtocol |= (SecurityProtocolType)3072; // Tls12 added, never replaced (#1360)
            string tip = WatchUrl(cfg);
            CheckUrl(tip);

            Cached have = cached;
            if (have == null && !cacheRead)
            {
                cacheRead = true;
                have = ReadCache();
                if (have != null) cached = have;
            }
            string tag = "";
            if (have != null && !string.IsNullOrEmpty(have.Etag)
                && string.Equals(have.Url, FeedUrl(cfg), StringComparison.Ordinal))
                tag = have.Etag.Trim();

            // The tip holds the socket for fifty seconds on the site and then
            // answers 204 (measured 18 Oct: 204 after 50.7 s). Sixty here, so
            // the site's own answer always arrives first; Quick's default ten
            // would cut every quiet wait off before the site could answer.
            return Tip(cfg, tip, tag, 60000);
        }

        /// <summary>
        /// The long-poll request itself, apart from CheckUrl so a test can
        /// point it at a server of its own (tests\test-2636-feed-watch-quiet.ps1),
        /// the way Conditional is apart from FromSite.
        ///
        /// The site answers 200 when the feed moved and 204 when its wait ran
        /// out unchanged. WebClient treats every 2xx as success: DownloadData
        /// returns for a 204 with an empty array and never throws. Until #2636
        /// this read any return from DownloadData as "moved" and looked for the
        /// 204 in the catch, where it never arrives, so every quiet fifty
        /// second wait ran a full update check, about seventy an hour for each
        /// open launcher (Djinn's launcher.log, 17 Oct). The status is read
        /// off the answer instead. A client timeout used to be read as
        /// "unchanged" too; the site always answers inside the wait, so no
        /// answer is a fault, and it now throws like any other.
        /// </summary>
        static bool Tip(Config cfg, string tip, string tag, int ms)
        {
            using (var q = (Quick)Client(cfg, false, tip))
            {
                q.Ms = ms;
                q.Gzip = true;
                if (tag.Length > 0) q.Headers["If-None-Match"] = tag;
                try { q.DownloadData(tip); }
                catch (WebException wex) { throw WrapFeedFail(wex, true); }
                // 200: the feed moved, or there was no tag to compare.
                if (q.Status == 200) return true;
                // 204: the wait ran out and the feed is as it was.
                if (q.Status == 204) return false;
                throw new Exception("The update feed tip answered HTTP " + q.Status + ", which says neither that the feed moved nor that it did not.");
            }
        }
        /// <summary>
        /// version.json straight off the site feed, asking with the ETag of the
        /// copy already in hand so an unchanged document is not downloaded
        /// again (#445). The answer is the same VersionDoc either way, so
        /// nothing above here has to know which of the two it got.
        /// </summary>
        static VersionDoc FromSite(Config cfg, string feedUrl)
        {
            CheckUrl(feedUrl);
            return Conditional(cfg, feedUrl);
        }

        /// <summary>
        /// The conditional request itself, apart from CheckUrl so a test can
        /// point it at a server of its own (tests\test-feed-conditional.ps1).
        /// Asks with the ETag, and with Last-Modified when the server gave one,
        /// of the copy in memory, or on the first check of a session the copy
        /// in Profile (#443), so a restart is a 304 too.
        /// </summary>
        static VersionDoc Conditional(Config cfg, string feedUrl)
        {
            // Read once. Anything that replaces it while this check is out
            // replaces the whole object, so what is used below cannot change
            // underneath it.
            Cached have = cached;
            if (have == null && !cacheRead)
            {
                cacheRead = true;
                have = ReadCache();
                if (have != null) cached = have;
            }
            DateTime since = DateTime.MinValue;
            if (have != null && !string.IsNullOrEmpty(have.LastModified))
            {
                DateTime t;
                if (DateTime.TryParseExact(have.LastModified.Trim(), "r", System.Globalization.CultureInfo.InvariantCulture,
                        System.Globalization.DateTimeStyles.AssumeUniversal | System.Globalization.DateTimeStyles.AdjustToUniversal, out t))
                    since = t;
            }
            bool asked = have != null
                         && have.Doc != null
                         && (!string.IsNullOrEmpty(have.Etag) || since != DateTime.MinValue)
                         && string.Equals(have.Url, feedUrl, StringComparison.Ordinal);
            using (var wc = Client(cfg, false, feedUrl))
            {
                var q = wc as Quick;
                if (q != null) q.Gzip = true;
                if (asked && !string.IsNullOrEmpty(have.Etag)) wc.Headers["If-None-Match"] = have.Etag;
                if (asked && q != null) q.Since = since;
                byte[] body;
                try { body = wc.DownloadData(feedUrl); }
                catch (WebException wex)
                {
                    // The .NET Framework hands a 304 back as a WebException
                    // rather than as an answer, so the one reply this cache
                    // exists to get arrives as a throw. Anything else really
                    // is a failed check and goes on up.
                    if (asked && NotChanged(wex))
                    {
                        LastNotModified = true;
                        return have.Doc;
                    }
                    throw;
                }
                // Belt as well as braces, for a stack that hands a 304 back as
                // an answer with no body instead of throwing.
                if (asked && (body == null || body.Length == 0))
                {
                    LastNotModified = true;
                    return have.Doc;
                }
                VersionDoc doc = VersionDoc.Parse(body);
                // Kept only once the document parsed, so a tag is never held
                // beside something the launcher could not read.
                string tag = null, mod = null;
                if (wc.ResponseHeaders != null)
                {
                    tag = wc.ResponseHeaders["ETag"];
                    mod = wc.ResponseHeaders["Last-Modified"];
                }
                var fresh = new Cached();
                fresh.Url = feedUrl;
                fresh.Etag = tag == null ? "" : tag.Trim();
                fresh.LastModified = mod == null ? "" : mod.Trim();
                fresh.Doc = doc;
                cached = fresh;
                if (fresh.Etag.Length > 0 || fresh.LastModified.Length > 0) WriteCache(fresh, body);
                return doc;
            }
        }

        /// <summary>
        /// Profile\feed-cache.txt: four lines (what the file is, the feed
        /// address, the ETag, the Last-Modified) and then the document exactly
        /// as it arrived. One file, so the tag can never be read beside some
        /// other copy's document. Null when Profile is not known.
        /// </summary>
        static string CacheFile
        {
            get { return string.IsNullOrEmpty(Paths.ProfileDir) ? null : Path.Combine(Paths.ProfileDir, "feed-cache.txt"); }
        }

        static void WriteCache(Cached c, byte[] body)
        {
            string file = CacheFile;
            if (file == null || body == null) return;
            string tmp = file + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                byte[] head = new UTF8Encoding(false).GetBytes(
                    CacheMagic + "\n" + OneLine(c.Url) + "\n" + OneLine(c.Etag) + "\n" + OneLine(c.LastModified) + "\n");
                using (var f = File.Create(tmp))
                {
                    f.Write(head, 0, head.Length);
                    f.Write(body, 0, body.Length);
                }
                // Written aside and copied over, so a check that reads while
                // another writes finds the old copy or the new one, and a
                // copy cut short does not parse and is not believed.
                File.Copy(tmp, file, true);
            }
            catch (Exception ex) { Swallow.Note("Updater.WriteCache", ex); }
            finally
            {
                try { if (File.Exists(tmp)) File.Delete(tmp); } catch (Exception ex) { Swallow.Note("Updater.WriteCache, tidy", ex); }
            }
        }

        static string OneLine(string s)
        {
            return s == null ? "" : s.Replace("\r", "").Replace("\n", "");
        }

        /// <summary>
        /// The copy in Profile, or null when there is none, it is from an older
        /// shape, or its document does not read. Null only ever costs one full
        /// download, which is what every start of the launcher did before.
        /// </summary>
        static Cached ReadCache()
        {
            string file = CacheFile;
            try
            {
                if (file == null || !File.Exists(file)) return null;
                byte[] raw = File.ReadAllBytes(file);
                var lines = new string[4];
                int at = 0;
                for (int i = 0; i < 4; i++)
                {
                    int nl = Array.IndexOf(raw, (byte)'\n', at);
                    if (nl < 0) return null;
                    lines[i] = Encoding.UTF8.GetString(raw, at, nl - at).TrimEnd('\r');
                    at = nl + 1;
                }
                if (!string.Equals(lines[0], CacheMagic, StringComparison.Ordinal)) return null;
                if (at >= raw.Length) return null;
                byte[] body = new byte[raw.Length - at];
                Buffer.BlockCopy(raw, at, body, 0, body.Length);
                VersionDoc doc = VersionDoc.Parse(body);
                if (doc == null) return null;
                var c = new Cached();
                c.Url = lines[1];
                c.Etag = lines[2];
                c.LastModified = lines[3];
                c.Doc = doc;
                return c;
            }
            catch (Exception ex)
            {
                Swallow.Note("Updater.ReadCache", ex);
                return null;
            }
        }

        static bool NotChanged(WebException wex)
        {
            var r = wex.Response as HttpWebResponse;
            return r != null && (int)r.StatusCode == 304;
        }

        static Exception WrapFeedFail(Exception ex, bool fromHost)
        {
            string where = fromHost ? "the site update feed" : "GitHub";
            var wex = ex as WebException;
            if (wex != null && wex.Status == WebExceptionStatus.Timeout)
                return new Exception(where + " did not answer in time. The check runs again by itself.");
            if (!string.IsNullOrEmpty(ex.Message)
                && (ex.Message.StartsWith("the ", StringComparison.Ordinal)
                    || ex.Message.StartsWith("GitHub ", StringComparison.Ordinal)
                    || ex.Message.StartsWith("The update feed", StringComparison.Ordinal)))
                return ex;
            return new Exception("could not reach " + where);
        }

        public static HashSet<string> Applied()
        {
            var s = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            try { if (File.Exists(Paths.AppliedFile)) foreach (string l in File.ReadAllLines(Paths.AppliedFile)) if (l.Trim().Length > 0) s.Add(l.Trim()); }
            catch (Exception ex) { Swallow.Note("Updater.Applied, read", ex); }
            return s;
        }

        /// <summary>
        /// Write a pack off without applying it. For one that cannot be
        /// downloaded at all, so it stops being offered on every check.
        /// </summary>
        public static void Skip(string id)
        {
            if (string.IsNullOrEmpty(id)) return;
            MarkApplied(id);
        }

        static void MarkApplied(string id)
        {
            try { File.AppendAllText(Paths.AppliedFile, id + Environment.NewLine); } catch (Exception ex) { Swallow.Note("Updater.MarkApplied, append", ex); }
        }

        /// <summary>
        /// Take a pack back out of applied.txt.
        ///
        /// The file was append only, which was fine while every pack was a
        /// required update that only ever went on. An optional pack can come
        /// off again, and a line that cannot be removed means the launcher
        /// would go on believing it was installed forever.
        /// </summary>
        static void Unapply(string id)
        {
            try
            {
                if (!File.Exists(Paths.AppliedFile)) return;
                var keep = new List<string>();
                foreach (string l in File.ReadAllLines(Paths.AppliedFile))
                {
                    string t = l.Trim();
                    if (t.Length == 0) continue;
                    if (string.Equals(t, id, StringComparison.OrdinalIgnoreCase)) continue;
                    keep.Add(t);
                }
                File.WriteAllLines(Paths.AppliedFile, keep.ToArray());
            }
            catch (Exception ex) { Swallow.Note("Updater.Unapply, write", ex); }
        }

        /// <summary>True if this pack is on disk right now.</summary>
        public static bool IsInstalled(string id)
        {
            return !string.IsNullOrEmpty(id) && Applied().Contains(id);
        }


        /// <summary>
        /// Is this path really inside that folder?
        ///
        /// A plain StartsWith is not enough, and it matters most in the one
        /// place that deletes things. "C:\Thornswood2\anything" starts with
        /// "C:\Thornswood", so a pack whose file list contained ..\Thornswood2
        /// would pass a prefix test and be treated as ours. Comparing against
        /// the folder plus its separator is the whole fix.
        /// </summary>
        static bool Inside(string full, string folder)
        {
            if (string.IsNullOrEmpty(full) || string.IsNullOrEmpty(folder)) return false;
            string fence = folder.TrimEnd(Path.DirectorySeparatorChar,
                                          Path.AltDirectorySeparatorChar)
                         + Path.DirectorySeparatorChar;
            return full.StartsWith(fence, StringComparison.OrdinalIgnoreCase);
        }

        static string PackListFile(string id)
        {
            var clean = new StringBuilder();
            foreach (char c in id)
                clean.Append(Array.IndexOf(Path.GetInvalidFileNameChars(), c) >= 0 ? '_' : c);
            return Path.Combine(Paths.PacksDir, clean.ToString() + ".files");
        }

        /// <summary>
        /// Every path some other pack's file list still claims, in the shape
        /// the lists hold them: a game\ prefix for a game path, nothing for a
        /// Root one.
        ///
        /// Ownership is recorded per pack and not per file. When a later pack
        /// writes over a file an earlier one created, the later list says "R|"
        /// because the file was already there and the earlier one still says
        /// "N|". Taking the earlier pack off then deleted the file the later
        /// one is using, and what somebody saw was a build missing part of an
        /// add-on they had not touched.
        /// </summary>
        static HashSet<string> ClaimedElsewhere(string mine)
        {
            var s = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            string leaf = "";
            try { leaf = Path.GetFileName(mine); } catch (Exception ex) { Swallow.Note("Updater.ClaimedElsewhere, leaf", ex); }
            try
            {
                if (!Directory.Exists(Paths.PacksDir)) return s;
                foreach (string f in Directory.GetFiles(Paths.PacksDir, "*.files"))
                {
                    if (string.Equals(Path.GetFileName(f), leaf, StringComparison.OrdinalIgnoreCase)) continue;
                    string[] all;
                    try { all = File.ReadAllLines(f); }
                    catch { continue; }
                    foreach (string raw in all)
                    {
                        string line = raw.Trim();
                        if (line.Length < 3 || line[1] != '|') continue;
                        s.Add(line.Substring(2));
                    }
                }
            }
            catch (Exception ex) { Swallow.Note("Updater.ClaimedElsewhere", ex); }
            return s;
        }

        /// <summary>
        /// Every path Vortex says it has deployed into the game folder. Under
        /// a folder of Thornswood's own the record lives in the folder Vortex
        /// deploys into (OwnGame.DeploysInto), never in Thornswood's folder,
        /// because the refresh leaves Vortex's own records behind. That is the
        /// Steam copy, unless Vortex deploys into another folder, and then the
        /// record is there and not in the Steam copy (OwnGame.Source), which is
        /// why this does not read Source (review, 24 September). Empty when
        /// there is nothing to read, which leaves the removal as it was.
        /// </summary>
        static HashSet<string> DeployedNow(Config cfg)
        {
            try
            {
                string src = OwnGame.Active ? OwnGame.DeploysInto(cfg) : Paths.Game;
                if (string.IsNullOrEmpty(src)) return new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                return OwnGame.DeployedIn(src);
            }
            catch { return new HashSet<string>(StringComparer.OrdinalIgnoreCase); }
        }

        /// <summary>
        /// What this install still has to take from the feed. When the feed
        /// names a release record this install has not synced to, that is one
        /// entry standing for the whole release (Sync.cs, #1050), and no pack
        /// is replayed. Otherwise every pack id not in applied.txt, in order.
        /// </summary>
        public static List<Pack> Pending(VersionDoc v)
        {
            var list = new List<Pack>();
            Pack release = RecordDue(v);
            if (release != null) { list.Add(release); return list; }
            var done = Applied();
            if (v == null || v.packs == null) return list;
            foreach (var p in v.packs)
                if (p != null && !string.IsNullOrEmpty(p.id) && !done.Contains(p.id)) list.Add(p);
            return list;
        }

        static string Sha256(string file)
        {
            using (var s = File.OpenRead(file))
            using (var h = SHA256.Create())
            {
                byte[] d = h.ComputeHash(s);
                var sb = new StringBuilder();
                foreach (byte b in d) sb.Append(b.ToString("x2"));
                return sb.ToString();
            }
        }

        /// <summary>
        /// Where an update is allowed to come from. version.json is a file we
        /// write, but it is also a file somebody else could write if they ever
        /// got at the repository, and the thing on the other end of this url
        /// gets executed on somebody's machine. So the url is checked against
        /// this list before a single byte is fetched.
        /// </summary>
        static readonly string[] AllowedHosts =
        {
            "github.com",
            "objects.githubusercontent.com",
            "release-assets.githubusercontent.com",
            "api.github.com",
            "thornswood.net"
        };

        static void CheckUrl(string url)
        {
            Uri u;
            if (!Uri.TryCreate(url, UriKind.Absolute, out u))
                throw new Exception("The update feed gave an address that is not an address. Nothing was downloaded.");
            if (u.Scheme != Uri.UriSchemeHttps)
                throw new Exception("The update feed asked for a download over plain http. Refused.");
            string h = u.Host.ToLowerInvariant();
            bool ok = false;
            foreach (string a in AllowedHosts)
                if (h == a || h.EndsWith("." + a, StringComparison.Ordinal)) { ok = true; break; }
            if (!ok)
                throw new Exception("The update feed pointed at " + u.Host + ", which is not where Thornswood updates come from. Refused.");
        }

        /// <summary>
        /// Download, for a caller that wants the zip and not the install.
        ///
        /// ClientRuntime.Heal takes the six recorded client files out of a pack
        /// WITHOUT applying it, because applying a pack twice writes applied.txt
        /// and a fresh file list in which every path reads as one that pack
        /// wrote over, which puts its own files out of reach of its own Remove.
        /// A repair must not move that bookkeeping. Every check Download makes
        /// is still made: the url is checked and the checksum is mandatory.
        /// </summary>
        public static string Fetch(Config cfg, string url, string expectSha, Action<string> log)
        {
            return Download(cfg, url, expectSha, log);
        }

        static string Download(Config cfg, string url, string expectSha, Action<string> log)
        {
            CheckUrl(url);

            // An update with no checksum used to be accepted quietly, which
            // meant one blank field in version.json was enough to run anything
            // on every machine. There is no such thing as an optional check on
            // a file that is about to be executed.
            if (string.IsNullOrEmpty(expectSha))
                throw new Exception("That update arrived without a checksum, so it has not been downloaded. This is a publishing mistake, not something wrong with your install.");

            ServicePointManager.SecurityProtocol |= (SecurityProtocolType)3072; // Tls12 added, never replaced (#1360)
            string tmp = Path.Combine(Path.GetTempPath(), "thornswood-" + Guid.NewGuid().ToString("N") + ".bin");
            // Read in pieces rather than DownloadFile, so the Play button can
            // show the bytes as they come (#1145, PlayProgress.Part).
            try
            {
                using (var wc = Client(cfg, true, url))
                using (Stream s = wc.OpenRead(url))
                using (var f = new FileStream(tmp, FileMode.Create, FileAccess.Write, FileShare.None))
                {
                    long length;
                    if (wc.ResponseHeaders == null || !long.TryParse(wc.ResponseHeaders["Content-Length"], out length)) length = -1;
                    byte[] buf = new byte[81920];
                    long had = 0;
                    int n;
                    PlayProgress.Part(0, length);
                    while ((n = s.Read(buf, 0, buf.Length)) > 0)
                    {
                        f.Write(buf, 0, n);
                        had += n;
                        PlayProgress.Part(had, length);
                    }
                }
            }
            catch
            {
                try { File.Delete(tmp); } catch (Exception ex) { Swallow.Note("Updater.Download, delete part", ex); }
                throw;
            }
            PlayProgress.PartDone();

            string got = Sha256(tmp);
            if (!string.Equals(got, expectSha, StringComparison.OrdinalIgnoreCase))
            {
                try { File.Delete(tmp); } catch (Exception ex) { Swallow.Note("Updater.Download, delete", ex); }
                throw new Exception("Checksum did not match. Download rejected.");
            }
            log("Checksum verified.");
            return tmp;
        }

        /// <summary>
        /// First line of every file list written since the fence below was
        /// fixed. A list without it was written by a launcher that could not
        /// put anything into a Steam copy of the game, and Requeue reads that
        /// as "apply this pack again".
        /// </summary>
        const string ListHeader = "# fence=game";

        /// <summary>Prefix on a list line whose path is under the game folder
        /// rather than under Root. Root relative lines carry no prefix.</summary>
        const string GameMark = "game\\";

        /// <summary>
        /// A pack is a zip holding game/ and profile/ trees, plus an optional
        /// delete.txt listing paths under Game to remove.
        ///
        /// Two fences, one per tree. The check used to be Inside(full, Root)
        /// for every entry, which is right for the profile tree and was right
        /// for the game tree while the game was Root\Game. On a collection
        /// install the game is the Steam copy, which is nowhere near Root, so
        /// every game\ entry failed the test and was skipped in silence. The
        /// pack was then marked applied and logged as "applied, 2 files": the
        /// two profile files, and not one file of the actual update. Every
        /// pack published for the collection build did this on every machine
        /// until 1.1.32.
        /// </summary>
        public static void ApplyPack(Config cfg, Pack p, Action<string> log)
        {
            // A whole release, synced to its record rather than unpacked.
            if (p != null && p.Record != null) { SyncRecord(cfg, p.Record, p.Doc, log); return; }
            // A retry runs the whole list again and everything before the pack
            // that broke is already in. A second helping means another line in
            // applied.txt and a file list written afresh in which every path
            // reads as one this pack wrote over, which puts the pack's own
            // files out of reach of its own Remove.
            if (IsInstalled(p.id)) { log(p.id + " is already in."); return; }
            log("Downloading " + p.id + "...");
            string zip = Download(cfg, p.url, p.sha256, log);
            try { Install(zip, p, log); }
            finally { try { File.Delete(zip); } catch (Exception ex) { Swallow.Note("Updater.ApplyPack, delete", ex); } }
        }

        /// <summary>The part of ApplyPack after the download: unpack the zip
        /// into place and record what it did. Separate so it can be exercised
        /// on a zip that never came from the feed.</summary>
        public static void Install(string zip, Pack p, Action<string> log)
        {
            {
                int files = 0;
                var wrote = new List<string>();
                wrote.Add(ListHeader);
                var newInGame = new List<string>();
                var gameWritten = new List<string>();
                var removed = new List<string>();
                // Whether this pack carried a reference plugin list, so it can
                // be settled into the live location once the pack is out.
                bool carriedProfile = false;
                using (var ar = ZipFile.OpenRead(zip))
                {
                    var del = ar.GetEntry("delete.txt");
                    if (del != null)
                    {
                        using (var sr = new StreamReader(del.Open()))
                        {
                            string line;
                            while ((line = sr.ReadLine()) != null)
                            {
                                line = line.Trim();
                                if (line.Length == 0 || line.StartsWith("#")) continue;
                                string rel = line.Replace('/', '\\');
                                string target;
                                // Fenced after the path is resolved, not
                                // before. Combine leaves the .. in a line like
                                // ..\..\Profile\x where it is, so the path
                                // still begins with the game folder as text,
                                // passes the test, and Delete is what resolves
                                // it, outside the game.
                                try { target = Path.GetFullPath(Path.Combine(Paths.Game, rel)); }
                                catch { continue; }
                                if (!Inside(target, Paths.Game)) continue;
                                try { if (File.Exists(target)) { File.Delete(target); log("removed " + line); } } catch (Exception ex) { Swallow.Note("Updater.Install, delete", ex); }
                                removed.Add(rel);
                            }
                        }
                    }

                    foreach (var e in ar.Entries)
                    {
                        if (string.IsNullOrEmpty(e.Name)) continue;           // directory entry
                        string rel = e.FullName.Replace('/', '\\');
                        string dest = null;
                        bool inGame = false;

                        if (rel.StartsWith("game\\", StringComparison.OrdinalIgnoreCase))
                        {
                            dest = Path.Combine(Paths.Game, rel.Substring(5));
                            inGame = true;
                        }
                        else if (rel.StartsWith("profile\\", StringComparison.OrdinalIgnoreCase))
                        {
                            dest = Path.Combine(Paths.Golden, Path.GetFileName(rel));
                            string leaf = Path.GetFileName(rel);
                            if (leaf.Equals("plugins.txt", StringComparison.OrdinalIgnoreCase) ||
                                leaf.Equals("loadorder.txt", StringComparison.OrdinalIgnoreCase))
                                carriedProfile = true;
                        }
                        else if (rel.Equals("delete.txt", StringComparison.OrdinalIgnoreCase))
                            continue;
                        else if (rel.Equals("ui-assets.txt", StringComparison.OrdinalIgnoreCase))
                        {
                            // Hashed assets build.js named, written by Ship
                            // (#1318). OwnGame.Foreign reads this rather than
                            // parsing build.js.
                            try
                            {
                                string dir = Path.Combine(Paths.ProfileDir, "OwnGame");
                                Directory.CreateDirectory(dir);
                                dest = Path.Combine(dir, "ui-front-assets.txt");
                                e.ExtractToFile(dest, true);
                            }
                            catch (Exception ex) { Swallow.Note("Updater.Install, ui-assets", ex); }
                            continue;
                        }
                        else
                            continue;

                        // The fence is the folder the entry is meant for. A
                        // game entry has to land under the game, wherever the
                        // game is; a profile entry has to land under Root.
                        string full = Path.GetFullPath(dest);
                        string fence = inGame ? Paths.Game : Paths.Root;
                        if (!Inside(full, fence)) continue;
                        Directory.CreateDirectory(Path.GetDirectoryName(full));

                        // Whether this file was already here decides whether
                        // taking the pack off again may delete it. A pack that
                        // creates a file owns it. A pack that writes over one
                        // that came with the build does not, and deleting that
                        // on removal would leave a hole in the core.
                        bool existed = File.Exists(full);
                        // In a game folder made of links, extracting over a
                        // linked file would rewrite Vortex's copy with it.
                        if (existed && inGame) OwnGame.Unshare(full);
                        e.ExtractToFile(full, true);
                        string under = full.Substring(fence.TrimEnd('\\', '/').Length).TrimStart('\\', '/');
                        wrote.Add((existed ? "R|" : "N|") + (inGame ? GameMark : "") + under);
                        if (inGame && !existed) newInGame.Add(under);
                        if (inGame) gameWritten.Add(under);
                        files++;
                    }
                }

                // A reference plugin list that arrived in this pack goes into
                // the file the game actually reads, now, rather than waiting
                // for somebody to press Fix.
                //
                // Until 22 September it waited. A release that moved the load
                // order installed cleanly, left the new list in
                // Profile\Default, and the game then turned the person away
                // with LOAD ORDER ERROR until they went back to the launcher
                // and pressed a button nothing had told them about. A first
                // time person reads that as the game being broken.
                //
                // Only this one step of Fix. The rest of Fix moves other
                // people's files aside and asks the server, and none of that
                // is wanted unprompted after every pack.
                if (carriedProfile)
                {
                    try
                    {
                        int settled = Verify.SettleLoadOrder();
                        if (settled > 0)
                            log("The plugin list this update carried is in place, so the load order is right without pressing Fix.");
                    }
                    catch (Exception ex)
                    {
                        log("Could not put this update's plugin list in place: " + ex.Message + ". Press Fix in the launcher.");
                    }
                }

                // Settings that shipped with the pack become the new baseline
                // and are pushed into the live profile too.
                Swap.RepairConfigs();
                try
                {
                    Directory.CreateDirectory(Paths.PacksDir);
                    File.WriteAllLines(PackListFile(p.id), wrote.ToArray());
                }
                catch (Exception ex) { Swallow.Note("Updater.Install, write", ex); }
                NoteInstalledIntoGame(newInGame);
                // The copies this pack just wrote are the ones to put back if
                // another server's launcher changes them. See Keep.
                int kept = Keep.Remember(gameWritten);
                if (kept > 0) log("Kept " + kept + " of " + Keep.Build() + "'s own game " + (kept == 1 ? "file" : "files") + " to put back if another server or build changes " + (kept == 1 ? "it." : "them."));
                // A file this pack took out must not come back at the next Play.
                Keep.Forget(removed);
                MarkApplied(p.id);
                log(p.id + " applied, " + files + " files.");
            }
        }

        /// <summary>
        /// Files a pack has just created inside the Steam copy join the list
        /// the uninstaller works from, so taking Thornswood out later takes
        /// them out too. The installer writes that list at install time and
        /// knows nothing about what arrived afterwards. Paths in it are
        /// relative to the game folder, one per line, which is what the
        /// uninstaller reads. Nothing is done on an install that has a game
        /// folder of its own, because that whole folder goes at uninstall, nor
        /// on one whose own folder was chosen and is not made yet, whose game
        /// files are in Profile\Payload and never in the Steam copy (#1226).
        /// The list is also what OwnGame.CleanSteamCopy takes out of the Steam
        /// copy once the folder is made.
        /// </summary>
        static void NoteInstalledIntoGame(List<string> rels)
        {
            if (!Paths.Collection || Paths.OwnFirst || rels == null || rels.Count == 0) return;
            try
            {
                string list = Path.Combine(Paths.ProfileDir, "installed-into-game.txt");
                var have = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                if (File.Exists(list))
                    foreach (string l in File.ReadAllLines(list))
                        if (l.Trim().Length > 0) have.Add(l.Trim());
                var add = new List<string>();
                foreach (string r in rels)
                    if (!have.Contains(r)) { have.Add(r); add.Add(r); }
                if (add.Count == 0) return;
                Directory.CreateDirectory(Paths.ProfileDir);
                File.AppendAllText(list, string.Join(Environment.NewLine, add.ToArray()) + Environment.NewLine);
            }
            catch (Exception ex) { Swallow.Note("Updater.NoteInstalledIntoGame, append", ex); }
        }

        /// <summary>
        /// Puts back into the queue every pack that a launcher before 1.1.32
        /// "applied" to a collection install. Returns how many.
        ///
        /// Such a pack left a file list with no header line and nothing but
        /// the two profile files in it, because the old fence skipped the
        /// whole game tree. The installer's own seeding of applied.txt leaves
        /// no file list at all, and those packs really are in the build, so
        /// they are left alone. A list written by this launcher starts with
        /// ListHeader and is trusted whatever it contains.
        ///
        /// Content based rather than a run-once flag on purpose: the update
        /// flow applies the packs with the launcher that is running and only
        /// then replaces the launcher, so the very update that carries this
        /// fix is applied once by the old code first. Its list has no header,
        /// so the new launcher sees it here on its first check and does it
        /// properly. Safe to call on every check; it only ever finds
        /// something once.
        /// </summary>
        public static int Requeue()
        {
            if (!Paths.Collection) return 0;
            int n = 0;
            try
            {
                if (!Directory.Exists(Paths.PacksDir)) return 0;
                foreach (string id in Applied())
                {
                    string list = PackListFile(id);
                    if (!File.Exists(list)) continue;
                    bool headed = false;
                    try
                    {
                        foreach (string l in File.ReadAllLines(list))
                        {
                            if (l.Trim().Length == 0) continue;
                            headed = l.Trim().Equals(ListHeader, StringComparison.Ordinal);
                            break;
                        }
                    }
                    catch { continue; }
                    if (headed) continue;
                    Unapply(id);
                    try { File.Delete(list); } catch (Exception ex) { Swallow.Note("Updater.Requeue, delete", ex); }
                    n++;
                }
            }
            catch (Exception ex) { Swallow.Note("Updater.Requeue, delete", ex); }
            return n;
        }

        /// <summary>
        /// Takes an optional pack back off.
        ///
        /// Only files the pack created are deleted. Anything it wrote over was
        /// part of the build before the pack arrived, and the zip did not keep
        /// a copy of what was there, so those are left alone and counted. The
        /// Scan and Fix buttons on the same page put those back, because that
        /// is exactly the job they already do: compare against the server list
        /// and re-download anything that does not match.
        /// </summary>
        public static void RemovePack(Config cfg, Pack p, Action<string> log)
        {
            if (p == null || string.IsNullOrEmpty(p.id)) return;

            string list = PackListFile(p.id);
            if (!File.Exists(list))
            {
                // Installed by a launcher old enough not to have kept a list.
                // Forgetting it is still better than claiming it is on when
                // there is no way to act on that.
                Unapply(p.id);
                log(p.Title + " has no file list, so nothing could be deleted. " +
                    "It is no longer listed as installed. Press Scan then Fix to " +
                    "put the build back the way the server expects it.");
                return;
            }

            int gone = 0, kept = 0, stuck = 0, shared = 0;
            // Read once, not per line.
            var claimed = ClaimedElsewhere(list);
            var deployed = DeployedNow(cfg);
            // Folder to prune from, and the fence it must never climb past.
            var dirs = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            // Game relative paths this pack is taking out, for Keep below.
            var removed = new List<string>();
            foreach (string raw in File.ReadAllLines(list))
            {
                string line = raw.Trim();
                if (line.Length < 3 || line[1] != '|') continue;
                bool mine = line[0] == 'N';
                string rel = line.Substring(2);
                if (!mine) { kept++; continue; }
                // Something else has this file now: a pack that wrote over it
                // afterwards, or Vortex, which may have deployed a mod carrying
                // the same path since. Either way it is not this pack's to
                // delete, whatever its own list says.
                if (claimed.Contains(rel) ||
                    (rel.StartsWith(GameMark, StringComparison.OrdinalIgnoreCase) &&
                     deployed.Contains(rel.Substring(GameMark.Length))))
                {
                    shared++;
                    continue;
                }

                // A game line resolves under the game folder, wherever that
                // is. On an install with its own Game folder the old lists
                // read "Game\Data\...", relative to Root, which resolves to
                // the same file either way.
                string fence = Paths.Root;
                if (rel.StartsWith(GameMark, StringComparison.OrdinalIgnoreCase))
                {
                    fence = Paths.Game;
                    rel = rel.Substring(GameMark.Length);
                }

                string full;
                try { full = Path.GetFullPath(Path.Combine(fence, rel)); }
                catch { continue; }
                if (!Inside(full, fence)) continue;

                try
                {
                    if (File.Exists(full))
                    {
                        File.Delete(full);
                        gone++;
                        string d = Path.GetDirectoryName(full);
                        if (!dirs.ContainsKey(d)) dirs[d] = fence;
                    }
                    // Taken from the resolved path rather than from the line,
                    // so an old list that wrote a game path relative to Root
                    // lands in the same place as a game\ one. Only a file that
                    // is really out of the way is recorded: one that would not
                    // delete is still in the game, so its kept copy stays.
                    if (Inside(full, Paths.Game))
                        removed.Add(full.Substring(Paths.Game.TrimEnd('\\', '/').Length).TrimStart('\\', '/'));
                }
                catch { stuck++; }
            }

            // Folders the pack brought with it and nothing else is using.
            var order = new List<string>(dirs.Keys);
            order.Sort();
            order.Reverse();                      // deepest first
            foreach (string d in order)
            {
                string fence = dirs[d];
                try
                {
                    string at = d;
                    while (at.Length > fence.Length &&
                           Inside(at, fence) &&
                           Directory.Exists(at) &&
                           Directory.GetFileSystemEntries(at).Length == 0)
                    {
                        Directory.Delete(at);
                        at = Path.GetDirectoryName(at);
                    }
                }
                catch (Exception ex) { Swallow.Note("Updater.RemovePack, rmdir", ex); }
            }

            // The kept copies go with the files. Install put a copy of every
            // Data\Platform file this pack wrote under Profile\Keep, and
            // Keep.Restore puts those back before every Play, so without this
            // the pack was in the game again at the next press of Play.
            Keep.Forget(removed);

            // Nothing is taken out of the Steam copy. A pack that went in while
            // this was a collection install can still have a copy there, and
            // this used to delete it, because a refresh brought back anything
            // the Steam copy had and the folder did not. A refresh takes only
            // Vortex's files now (#1218), so that copy never comes back, and
            // the Steam copy is the person's and is not written.

            try { File.Delete(list); } catch (Exception ex) { Swallow.Note("Updater.RemovePack, delete", ex); }
            Unapply(p.id);
            Swap.RepairConfigs();

            string msg = p.Title + " removed, " + gone + " file" + (gone == 1 ? "" : "s") + " deleted.";
            if (stuck > 0)
                msg += "  " + stuck + " would not delete, usually because Skyrim is still open.";
            if (kept > 0)
                msg += "  " + kept + " file" + (kept == 1 ? "" : "s") +
                       " here replaced part of the build and " + (kept == 1 ? "was" : "were") +
                       " left alone. Press Scan, then Fix, to put " +
                       (kept == 1 ? "it" : "those") + " back.";
            if (shared > 0)
                msg += "  " + shared + " file" + (shared == 1 ? "" : "s") +
                       " here " + (shared == 1 ? "is" : "are") +
                       " in use by another add-on or by the collection now and " +
                       (shared == 1 ? "was" : "were") + " left in place.";
            log(msg);
        }

        /// <summary>
        /// Who the downloaded launcher has to be signed by.
        ///
        /// Empty means the check is skipped, and that is deliberate. Every
        /// release before signing begins is unsigned, so a launcher that
        /// refused them would strand everybody on whatever they already have.
        ///
        /// Fill this in with a distinctive part of the certificate's Subject
        /// line, in the same release that first ships a signed exe, and never
        /// before. Match on a fragment rather than the whole Subject, because
        /// certificate authorities add and reorder fields between renewals and
        /// an exact-match check would refuse a perfectly good update the day
        /// the certificate is renewed.
        ///
        /// Since #912 this is the last of five checks, not the only one:
        /// Signature.cs first has Windows verify the signature and pins
        /// Microsoft's Artifact Signing and Thornswood's durable identity.
        /// scripts\release\Assert-PublishSigned.ps1 reads this line.
        ///
        /// This is a third layer, not the only one. The host allow list at
        /// AllowedHosts decides where a byte may come from, the SHA-256 in
        /// version.json decides the bytes are the ones published, and this
        /// decides who built them. Removing either of the other two because
        /// this exists would be a straight loss.
        /// </summary>
        public const string ExpectedSigner = "Gavin Knotts";

        /// <summary>
        /// Refuses a launcher that is not signed by us, and says which check it
        /// failed, because "it would not update" with no reason is the report
        /// nobody can act on.
        ///
        /// Until #912 this read the Subject of the embedded certificate and
        /// nothing else, so a certificate anybody can make with this name on
        /// it passed. Signature.Refusal now has Windows verify the signature
        /// and its chain, then pins Microsoft's Artifact Signing root and
        /// Thornswood's durable identity in the certificate, and only then
        /// looks for ExpectedSigner in the Subject. Signature.cs says why each.
        /// </summary>
        static void CheckSigner(string path, Action<string> log)
        {
            if (String.IsNullOrEmpty(ExpectedSigner)) return;
            string said;
            string why = Signature.Refusal(path, ExpectedSigner, out said);
            if (why.Length > 0)
            {
                throw new Exception(
                    "The launcher that was downloaded " + why + " " +
                    "Nothing has been replaced and the one you are running is untouched. " +
                    "Tell Patrick before running anything.");
            }
            log(said);
        }

        /// <summary>Replaces the running exe and restarts, via a short detached script.</summary>
        public static void SelfUpdate(Config cfg, VersionDoc v, Action<string> log)
        {
            SwapIn(FetchLauncher(cfg, v, log), log);
        }

        /// <summary>
        /// The new launcher, downloaded and checked against its checksum, in
        /// the temp folder; nothing is replaced yet. Apart from SwapIn so an
        /// update can download while the game folder is prepared (#2210).
        /// </summary>
        public static string FetchLauncher(Config cfg, VersionDoc v, Action<string> log)
        {
            log("Downloading launcher " + v.launcherVersion + "...");
            return Download(cfg, v.launcherUrl, v.launcherSha256, log);
        }

        /// <summary>
        /// Puts the launcher FetchLauncher downloaded into place once this one
        /// has gone, after the signer check, and deletes the download either
        /// way.
        /// </summary>
        public static void SwapIn(string tmp, Action<string> log)
        {
            string exe = System.Reflection.Assembly.GetExecutingAssembly().Location;
            string neu = exe + ".new";
            // Before the copy, not after. Once a file is sitting at exe.new the
            // swap script will pick it up on the next start whatever happens
            // here, so a check that ran later would be checking a decision
            // already made.
            // The download is deleted whichever way this goes. A launcher the
            // signer check refused used to stay in %TEMP%, one more copy on
            // every check that offered it again.
            try
            {
                CheckSigner(tmp, log);
                File.Copy(tmp, neu, true);
            }
            finally
            {
                try { File.Delete(tmp); } catch (Exception ex) { Swallow.Note("Updater.SwapIn, delete", ex); }
            }

            int me = System.Diagnostics.Process.GetCurrentProcess().Id;
            // Named for the launcher it waits on. The script stays up for a few
            // minutes now, watching the new launcher start, and with one fixed
            // name the dev build updating in that time would write over a
            // script cmd is still reading.
            string bat = Path.Combine(Path.GetTempPath(), "thornswood-update-" + me + ".cmd");

            // Waits for this launcher to be gone, keeps it as Thornswood.exe.old,
            // puts the new one in, and puts the old one back if the new one
            // does not start. SelfSwap.cs has the script and the failures each
            // line of it is there for.
            File.WriteAllText(bat, SelfSwap.Script(exe, neu, me));

            var psi = new System.Diagnostics.ProcessStartInfo(bat);
            psi.WindowStyle = System.Diagnostics.ProcessWindowStyle.Hidden;
            psi.CreateNoWindow = true;
            psi.UseShellExecute = true;
            System.Diagnostics.Process.Start(psi);
        }
    }
}
