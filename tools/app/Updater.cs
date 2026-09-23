using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Security.Cryptography;
using System.Text;

namespace Thornswood
{
    static class Updater
    {
        public const string Version = "1.1.85";

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

        // WebClient has no timeout worth the name, and the default is long
        // enough that a GitHub which accepts the connection and then says
        // nothing looks like a hung launcher. The same helper Online and
        // Roster use. Timeout is the wait for an answer, not for the body, so
        // a large asset still downloads for as long as it needs.
        class Quick : WebClient
        {
            public int Ms = 10000;
            protected override WebRequest GetWebRequest(Uri address)
            {
                var r = base.GetWebRequest(address);
                if (r != null) { r.Timeout = Ms; }
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
            catch { }
            if (github && !string.IsNullOrEmpty(cfg.UpdateToken))
                wc.Headers["Authorization"] = "Bearer " + cfg.UpdateToken;
            wc.Headers["Accept"] = octet ? "application/octet-stream" : "application/vnd.github.raw";
            return wc;
        }

        public static bool Enabled(Config cfg)
        {
            // No token needed. Releases live in a public repository of their own
            // now, holding version.json and the assets and nothing else, because
            // the alternative was shipping a credential to every machine that
            // installs the game so it could read a private one. UpdateToken is
            // still honoured if somebody sets one, which is what keeps a private
            // source working for whoever is developing against it.
            return !string.IsNullOrEmpty(cfg.UpdateRepo)
                   && cfg.UpdateRepo.Contains("/");
        }

        public static string WhyDisabled(Config cfg)
        {
            if (string.IsNullOrEmpty(cfg.UpdateRepo) || !cfg.UpdateRepo.Contains("/")) return "no update source set";
            return cfg.UpdateRepo;
        }

        /// <summary>Reads version.json from the repo. Returns null if updates are off or unreachable.</summary>
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
                // Unparseable on either side: fall back to the old behaviour
                // rather than refusing an update nobody can then install.
                return !string.Equals(remote, local, StringComparison.OrdinalIgnoreCase);
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
        /// The repository names worth trying, in order. The project was renamed
        /// from skyrim-together to Thornswood, and a config.json written either
        /// side of that rename is still out there on somebody's machine.
        ///
        /// Rewriting the name in the config on load was the obvious fix and the
        /// wrong one: it renamed everybody's config before the repository
        /// itself was renamed, so every launcher started asking GitHub for
        /// something that did not exist yet. Trying is the only thing that
        /// works whichever side of the rename a machine is on.
        /// </summary>
        static List<string> RepoCandidates(string repo)
        {
            var l = new List<string>();
            if (string.IsNullOrEmpty(repo)) return l;
            l.Add(repo);

            int slash = repo.LastIndexOf('/');
            if (slash <= 0) return l;
            string owner = repo.Substring(0, slash + 1);
            string name = repo.Substring(slash + 1);

            if (string.Equals(name, "skyrim-together", StringComparison.OrdinalIgnoreCase)) l.Add(owner + "Thornswood");
            else if (string.Equals(name, "Thornswood", StringComparison.OrdinalIgnoreCase)) l.Add(owner + "skyrim-together");
            return l;
        }

        public static VersionDoc Check(Config cfg)
        {
            if (!Enabled(cfg)) return null;
            ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072; // Tls12

            string branch = string.IsNullOrEmpty(cfg.UpdateBranch) ? "main" : cfg.UpdateBranch;
            List<string> tries = RepoCandidates(cfg.UpdateRepo);
            Exception last = null;

            foreach (string repo in tries)
            {
                string url = "https://api.github.com/repos/" + repo +
                             "/contents/version.json?ref=" + branch;
                try
                {
                    VersionDoc doc;
                    using (var wc = Client(cfg, false, url))
                        doc = VersionDoc.Parse(wc.DownloadData(url));

                    // Settle on whichever one answered, so the next check is one
                    // request rather than two.
                    if (!string.Equals(repo, cfg.UpdateRepo, StringComparison.Ordinal))
                    {
                        cfg.UpdateRepo = repo;
                        try { cfg.Save(Paths.CfgFile); } catch { }
                    }
                    return doc;
                }
                catch (WebException wex)
                {
                    var r = wex.Response as HttpWebResponse;
                    if (r != null)
                    {
                        int code = (int)r.StatusCode;
                        // Only a missing repo is worth trying the other name for.
                        // A refused token would fail identically on both and the
                        // second attempt would only hide what is actually wrong.
                        if (code == 404)
                        {
                            last = new Exception("the repo or the branch could not be read, check UpdateRepo and that the token still has access");
                            continue;
                        }
                        if (code == 401) throw new Exception("the access token was refused, it may have expired");
                        if (code == 403 || code == 429)
                        {
                            // GitHub answers a rate limit with 403 as well as
                            // with 429, and an install with no token of its own
                            // shares sixty calls an hour with everybody on its
                            // address. Calling that a refused token sent people
                            // looking for a credential they never set, on an
                            // install that is meant to need none.
                            string left = null;
                            try { left = r.Headers["X-RateLimit-Remaining"]; } catch { }
                            if (code == 429 || string.Equals(left, "0", StringComparison.Ordinal) ||
                                string.IsNullOrEmpty(cfg.UpdateToken))
                                throw new Exception("GitHub answered " + code + ": too many update checks have come from this connection for now. Nothing is wrong with your install and it clears by itself, usually within the hour.");
                            throw new Exception("the access token was refused, it may have expired");
                        }
                    }
                    if (wex.Status == WebExceptionStatus.Timeout)
                        throw new Exception("GitHub did not answer in time. The check runs again by itself.");
                    throw new Exception("could not reach GitHub");
                }
            }
            throw (last != null ? last : new Exception("could not reach GitHub"));
        }

        public static HashSet<string> Applied()
        {
            var s = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            try { if (File.Exists(Paths.AppliedFile)) foreach (string l in File.ReadAllLines(Paths.AppliedFile)) if (l.Trim().Length > 0) s.Add(l.Trim()); }
            catch { }
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
            try { File.AppendAllText(Paths.AppliedFile, id + Environment.NewLine); } catch { }
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
            catch { }
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
            try { leaf = Path.GetFileName(mine); } catch { }
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
            catch { }
            return s;
        }

        /// <summary>
        /// Every path Vortex says it has deployed into the game folder. Under
        /// a folder of Thornswood's own the record lives in the Steam copy the
        /// folder was made from, never in the folder, because the refresh
        /// leaves Vortex's own records behind. Empty when there is nothing to
        /// read, which leaves the removal as it was.
        /// </summary>
        static HashSet<string> DeployedNow(Config cfg)
        {
            try
            {
                string src = OwnGame.Active ? OwnGame.Source(cfg) : Paths.Game;
                if (string.IsNullOrEmpty(src)) return new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                return OwnGame.DeployedIn(src);
            }
            catch { return new HashSet<string>(StringComparer.OrdinalIgnoreCase); }
        }

        public static List<Pack> Pending(VersionDoc v)
        {
            var done = Applied();
            var list = new List<Pack>();
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

            ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072;
            string tmp = Path.Combine(Path.GetTempPath(), "st-" + Guid.NewGuid().ToString("N") + ".bin");
            using (var wc = Client(cfg, true, url)) wc.DownloadFile(url, tmp);

            string got = Sha256(tmp);
            if (!string.Equals(got, expectSha, StringComparison.OrdinalIgnoreCase))
            {
                try { File.Delete(tmp); } catch { }
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
            // A retry runs the whole list again and everything before the pack
            // that broke is already in. A second helping means another line in
            // applied.txt and a file list written afresh in which every path
            // reads as one this pack wrote over, which puts the pack's own
            // files out of reach of its own Remove.
            if (IsInstalled(p.id)) { log(p.id + " is already in."); return; }
            log("Downloading " + p.id + "...");
            string zip = Download(cfg, p.url, p.sha256, log);
            try { Install(zip, p, log); }
            finally { try { File.Delete(zip); } catch { } }
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
                                try { if (File.Exists(target)) { File.Delete(target); log("removed " + line); } } catch { }
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
                catch { }
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
        /// folder of its own, because that whole folder goes at uninstall.
        /// </summary>
        static void NoteInstalledIntoGame(List<string> rels)
        {
            if (!Paths.Collection || rels == null || rels.Count == 0) return;
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
            catch { }
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
                    try { File.Delete(list); } catch { }
                    n++;
                }
            }
            catch { }
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
                catch { }
            }

            // The kept copies go with the files. Install put a copy of every
            // Data\Platform file this pack wrote under Profile\Keep, and
            // Keep.Restore puts those back before every Play, so without this
            // the pack was in the game again at the next press of Play.
            Keep.Forget(removed);

            // On a folder of Thornswood's own the same file can still be in
            // the Steam copy the folder is made from, because the pack went in
            // while this was a collection install and the folder took its copy
            // from there. Refresh brings anything the source has and the folder
            // does not straight back over. Only the paths this pack created are
            // touched, the ones deleted above.
            int fromSteam = 0;
            string src = "";
            try { if (OwnGame.Active) src = OwnGame.Source(cfg); }
            catch { }
            if (!string.IsNullOrEmpty(src))
            {
                foreach (string r in removed)
                {
                    string at;
                    try { at = Path.GetFullPath(Path.Combine(src, r)); }
                    catch { continue; }
                    if (!Inside(at, src)) continue;
                    try { if (File.Exists(at)) { File.Delete(at); fromSteam++; } } catch { }
                }
            }

            try { File.Delete(list); } catch { }
            Unapply(p.id);
            Swap.RepairConfigs();

            string msg = p.Title + " removed, " + gone + " file" + (gone == 1 ? "" : "s") + " deleted.";
            if (fromSteam > 0)
                msg += "  " + fromSteam + " file" + (fromSteam == 1 ? "" : "s") +
                       " also went from the Skyrim on Steam that Thornswood's own folder is made from, " +
                       "or the next refresh would bring " + (fromSteam == 1 ? "it" : "them") + " back.";
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
        /// This is a third layer, not the only one. The host allow list at
        /// AllowedHosts decides where a byte may come from, the SHA-256 in
        /// version.json decides the bytes are the ones published, and this
        /// decides who built them. Removing either of the other two because
        /// this exists would be a straight loss.
        /// </summary>
        public const string ExpectedSigner = "";

        /// <summary>
        /// The Subject of whoever signed a file, or an empty string when it is
        /// not signed. CreateFromSignedFile throws on an unsigned file rather
        /// than returning null, so the throw is what "unsigned" looks like.
        /// </summary>
        static string SignerOf(string path)
        {
            try
            {
                var c = System.Security.Cryptography.X509Certificates.X509Certificate
                            .CreateFromSignedFile(path);
                if (c == null) return "";
                return c.Subject;
            }
            catch { return ""; }
        }

        /// <summary>
        /// Refuses a launcher that is not signed by us. Says which of the two
        /// things went wrong, because "it would not update" with no reason is
        /// the report nobody can act on.
        /// </summary>
        static void CheckSigner(string path, Action<string> log)
        {
            if (String.IsNullOrEmpty(ExpectedSigner)) return;
            string who = SignerOf(path);
            if (who.Length == 0)
            {
                throw new Exception(
                    "The launcher that was downloaded is not signed. " +
                    "Nothing has been replaced and the one you are running is untouched.");
            }
            if (who.IndexOf(ExpectedSigner, StringComparison.OrdinalIgnoreCase) < 0)
            {
                throw new Exception(
                    "The launcher that was downloaded was signed by somebody else. " +
                    "Nothing has been replaced. Tell Patrick before running anything.");
            }
            log("Signed by the expected publisher.");
        }

        /// <summary>Replaces the running exe and restarts, via a short detached script.</summary>
        public static void SelfUpdate(Config cfg, VersionDoc v, Action<string> log)
        {
            log("Downloading launcher " + v.launcherVersion + "...");
            string tmp = Download(cfg, v.launcherUrl, v.launcherSha256, log);
            string exe = System.Reflection.Assembly.GetExecutingAssembly().Location;
            string neu = exe + ".new";
            // Before the copy, not after. Once a file is sitting at exe.new the
            // swap script will pick it up on the next start whatever happens
            // here, so a check that ran later would be checking a decision
            // already made.
            CheckSigner(tmp, log);
            File.Copy(tmp, neu, true);
            try { File.Delete(tmp); } catch { }

            string bat = Path.Combine(Path.GetTempPath(), "st-update.cmd");
            int me = System.Diagnostics.Process.GetCurrentProcess().Id;

            // Waits for this launcher to actually be gone, then keeps trying
            // the move.
            //
            // It used to sleep two seconds and move once. Closing runs
            // Swap.Restore, Hold.Release, Keep.Unpark and SkyMp.Stop, which
            // together take longer than that, so the move could hit an exe
            // that was still running, fail silently, and start would reopen
            // the old one. The next check then offered the same update again,
            // and again. This is the tasklist wait Uninstall.Finish uses.
            //
            // cmd reads a .cmd file in the console's OEM code page, not the
            // UTF-8 this is written in, so a path with any character outside
            // ASCII would reach move and start as different bytes and the new
            // launcher would never be put in place. chcp tells cmd how to read
            // the rest of the file.
            var bs = new StringBuilder();
            bs.Append("@echo off\r\n");
            bs.Append("chcp 65001 >nul\r\n");
            bs.Append("setlocal\r\n");
            bs.Append(":wait\r\n");
            bs.Append("tasklist /fi \"PID eq " + me + "\" | find \"" + me + "\" >nul 2>&1\r\n");
            // ping rather than timeout for the pause: timeout wants a console
            // of its own and this script is started hidden.
            bs.Append("if not errorlevel 1 ( ping 127.0.0.1 -n 2 >nul & goto wait )\r\n");
            bs.Append("set /a tries=0\r\n");
            bs.Append(":swap\r\n");
            // Already gone means somebody else finished the job.
            bs.Append("if not exist \"" + neu + "\" goto run\r\n");
            bs.Append("move /y \"" + neu + "\" \"" + exe + "\" >nul 2>&1\r\n");
            bs.Append("if not errorlevel 1 goto run\r\n");
            // Windows can hold a file open for a moment after the process that
            // had it has ended. About a minute of trying, then start whatever
            // is there rather than leave somebody with no launcher at all.
            bs.Append("set /a tries+=1\r\n");
            bs.Append("if %tries% lss 30 ( ping 127.0.0.1 -n 2 >nul & goto swap )\r\n");
            bs.Append(":run\r\n");
            bs.Append("start \"\" \"" + exe + "\"\r\n");
            bs.Append("del \"%~f0\"\r\n");
            File.WriteAllText(bat, bs.ToString());

            var psi = new System.Diagnostics.ProcessStartInfo(bat);
            psi.WindowStyle = System.Diagnostics.ProcessWindowStyle.Hidden;
            psi.CreateNoWindow = true;
            psi.UseShellExecute = true;
            System.Diagnostics.Process.Start(psi);
        }
    }
}
