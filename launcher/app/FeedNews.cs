using System;
using System.IO;
using System.Net;
using System.Runtime.Serialization.Json;
using System.Security.Cryptography;
using System.Text;

namespace Thornswood
{
    /// <summary>
    /// THE NEWS AS A FILE OF ITS OWN (#1050). Measured 12 Oct, the news was
    /// 31,282 of main's 95,085 bytes of version.json and 19,980 of dev's
    /// 111,305, the biggest part left once the packs came off, read on every
    /// check a launcher makes, every thirty seconds while the game runs. So the
    /// publisher can put the notes in a file of their own, named by its sha256
    /// like every asset, /feed[-dev]/assets/&lt;sha256&gt;, and name it in the feed
    /// as "newsFile": { url, sha256, count }, leaving "news" in version.json
    /// short or empty.
    ///
    /// A launcher that reads newsFile puts those notes into the document's
    /// news after the ones the feed itself carries (any note the feed carries
    /// is not shown twice), so the News tab and everything else that reads
    /// VersionDoc.news needs nothing new. Every launcher before this reads only
    /// "news", which is why the publisher empties it only once the channel's
    /// minLauncher reads the file.
    ///
    /// The file is checked like every other download: https to a host on the
    /// list (CheckUrl), stored under its own sha256, and its bytes must hash to
    /// that. It is kept in Profile\news.json, so a restart reads it from disk
    /// and a check that finds the same file fetches nothing. The news is
    /// cosmetic: a file that cannot be had or read leaves the notes the feed
    /// carries, says why once in launcher.log, and never fails the update
    /// check.
    /// </summary>
    static partial class Updater
    {
        static readonly object newsLock = new object();
        static string newsHeld = "";
        static NewsItem[] newsItems;

        static string NewsCacheFile
        {
            get { return string.IsNullOrEmpty(Paths.ProfileDir) ? null : Path.Combine(Paths.ProfileDir, "news.json"); }
        }

        /// <summary>
        /// The feed's news file, after the notes the feed carries, into v.news.
        /// Nothing when the feed names none. Never throws.
        /// </summary>
        public static void FillNews(Config cfg, VersionDoc v)
        {
            if (v == null || v.newsRef == null) return;
            try
            {
                CheckUrl(v.newsRef.url);
                ServicePointManager.SecurityProtocol |= (SecurityProtocolType)3072; // Tls12 added, never replaced (#1360)
                v.news = MergeNews(v.news, NewsFile(cfg, v.newsRef));
            }
            catch (Exception ex) { Swallow.Note("Updater.FillNews, " + v.newsRef.url, ex); }
        }

        /// <summary>
        /// The notes in the file the feed names, from memory, from
        /// Profile\news.json when that is the same file, or downloaded. Apart
        /// from CheckUrl, so tests\test-1050-news-file.ps1 can point it at a
        /// server of its own.
        /// </summary>
        static NewsItem[] NewsFile(Config cfg, NewsRef r)
        {
            lock (newsLock)
            {
                if (newsItems != null && newsHeld == r.sha256) return newsItems;
            }
            string u = r.url;
            int q = u.IndexOfAny(new[] { '?', '#' });
            if (q >= 0) u = u.Substring(0, q);
            if (!u.EndsWith("/" + r.sha256, StringComparison.OrdinalIgnoreCase))
                throw new Exception("The update feed names a news file that is not stored under its own checksum.");

            byte[] raw = null;
            string cache = NewsCacheFile;
            if (cache != null && File.Exists(cache))
            {
                byte[] had = File.ReadAllBytes(cache);
                if (ShaOf(had) == r.sha256) raw = had;
            }
            if (raw == null)
            {
                using (var wc = Client(cfg, true, r.url)) raw = wc.DownloadData(r.url);
                if (ShaOf(raw) != r.sha256)
                    throw new Exception("The news file did not match its checksum, so it was not read.");
                if (cache != null)
                {
                    string tmp = cache + ".tmp";
                    File.WriteAllBytes(tmp, raw);
                    if (File.Exists(cache)) File.Delete(cache);
                    File.Move(tmp, cache);
                }
            }
            NewsItem[] items = ParseNews(raw);
            lock (newsLock)
            {
                newsItems = items;
                newsHeld = r.sha256;
            }
            return items;
        }

        /// <summary>A news file: a JSON list of the same notes "news" holds.</summary>
        internal static NewsItem[] ParseNews(byte[] raw)
        {
            int at = 0;
            if (raw.Length >= 3 && raw[0] == 0xEF && raw[1] == 0xBB && raw[2] == 0xBF) at = 3;
            using (var ms = new MemoryStream(raw, at, raw.Length - at))
            {
                var items = (NewsItem[])new DataContractJsonSerializer(typeof(NewsItem[])).ReadObject(ms);
                return items ?? new NewsItem[0];
            }
        }

        /// <summary>
        /// The feed's own notes first, then the file's that the feed does not
        /// carry, by date and title. A feed written by a publisher from before
        /// the file existed carries its newest note in "news" beside an older
        /// file, and both are shown.
        /// </summary>
        internal static NewsItem[] MergeNews(NewsItem[] feed, NewsItem[] file)
        {
            var all = new System.Collections.Generic.List<NewsItem>();
            var seen = new System.Collections.Generic.HashSet<string>(StringComparer.Ordinal);
            foreach (NewsItem[] list in new[] { feed, file })
            {
                if (list == null) continue;
                foreach (NewsItem n in list)
                {
                    if (n == null) continue;
                    if (!seen.Add((n.date ?? "") + "\n" + (n.title ?? ""))) continue;
                    all.Add(n);
                }
            }
            return all.ToArray();
        }

        static string ShaOf(byte[] b)
        {
            using (var h = SHA256.Create())
            {
                byte[] d = h.ComputeHash(b);
                var sb = new StringBuilder();
                foreach (byte x in d) sb.Append(x.ToString("x2"));
                return sb.ToString();
            }
        }
    }
}
