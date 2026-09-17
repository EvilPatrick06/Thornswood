using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;

namespace Thornswood
{
    class Issue
    {
        public string Text;
        public bool Blocking;      // true = you will be refused by the server
        // The file is not in Data at all. Fix rewrites a plugin list, it cannot
        // install a mod, so offering the button for one of these is worse than
        // not offering it.
        public bool Absent;
        // The file is there, enabled, in the right place, and its bytes are
        // not the server's. Fix fetches the server's copy. Which file, and what
        // the server says it should be, so Fix does not have to ask twice.
        public string Plugin;
        public long WantSize;
        public int WantCrc;
        public int WantIndex;   // position in the server manifest; the file is served at /plugins/<index>.bin
        public Issue(string t, bool b) { Text = t; Blocking = b; }
        public Issue(string t, bool b, bool absent) { Text = t; Blocking = b; Absent = absent; }
    }

    static class Verify
    {
        static List<string> Enabled(string file)
        {
            var l = new List<string>();
            if (!File.Exists(file)) return l;
            foreach (string raw in File.ReadAllLines(file))
            {
                string s = raw.Trim();
                if (s.Length == 0 || s.StartsWith("#")) continue;
                if (s.StartsWith("*")) l.Add(s.Substring(1));
            }
            return l;
        }

        public static List<Issue> Run() { return Run(null); }

        /// <summary>
        /// The shipped plugins.txt is what the server was built against, so it is
        /// the reference. Anything the live list adds, drops or reorders is what
        /// gets a person refused at connect. With a Config to hand it also asks
        /// the server what each plugin's bytes should be; see Bytes.
        /// </summary>
        public static List<Issue> Run(Config cfg)
        {
            var issues = new List<Issue>();
            string golden = Path.Combine(Paths.Golden, "plugins.txt");

            // Paths.Live, not Paths.LocalAD. Under the collection those are two
            // different files and this was reading the wrong one.
            //
            // LocalAD is the launcher's own redirected copy under Profile, which
            // is right for an install that built its own game. A collection
            // install redirects nothing: Vortex writes the real list into
            // Windows' own AppData and that is what Skyrim and the server see.
            // So this compared against a copy the installer laid down once and
            // nothing has touched since, reported plugins from somebody's old
            // collection that are not enabled anywhere any more, and Fix then
            // rewrote that same unread file. The scan found problems that were
            // not there and fixing them changed nothing, every time.
            //
            // Paths.Live is already the right file for both shapes of install.
            string live = Path.Combine(Paths.Live, "plugins.txt");

            if (!File.Exists(golden))
            {
                issues.Add(new Issue("This build shipped without a reference plugin list, so there is nothing to compare against.", false));
                return issues;
            }
            if (!File.Exists(live))
            {
                issues.Add(new Issue("Your plugins.txt is missing. Fix will put the shipped one back.", true));
                return issues;
            }

            List<string> want = Enabled(golden), have = Enabled(live);
            var wantSet = new HashSet<string>(want, StringComparer.OrdinalIgnoreCase);
            var haveSet = new HashSet<string>(have, StringComparer.OrdinalIgnoreCase);

            // Turned off and not installed at all look identical in a plugin
            // list and need completely different answers, so they are told
            // apart by looking in Data rather than guessed at.
            string dataDir = Path.Combine(Paths.Game, "Data");
            foreach (string p in want)
            {
                if (haveSet.Contains(p)) continue;
                bool onDisk = true;
                try { onDisk = File.Exists(Path.Combine(dataDir, p)); } catch { }
                issues.Add(new Issue(
                    onDisk ? p + " is turned off." : p + " is not installed.",
                    true, !onDisk));
            }

            foreach (string p in have)
                if (!wantSet.Contains(p)) issues.Add(new Issue(p + " is enabled but is not part of this build.", true));

            // Another server's client. Not a plugin, so nothing above would ever
            // have found it, and it is the difference between Thornswood loading
            // and Daedric Online's main menu loading instead.
            foreach (string f in Checks.ForeignClients())
                issues.Add(new Issue(
                    Path.GetFileName(f) + " belongs to another server. It replaces the main menu " +
                    "and asks you to sign in to them. Fix moves it aside into Thornswood's " +
                    "Isolated folder and nothing is deleted, so that server still works.", true));

            // The collection installs MCM Helper's plugin without its light flag,
            // which gives it a load order index the server does not have and
            // shifts everything after it by one. See Checks.MustBeLight.
            foreach (string p in Checks.NotLight())
                issues.Add(new Issue(
                    p + " is not flagged light, so from there on your load order counts " +
                    "one place differently from the server's. Fix flags it; nothing else changes.", true));
            if (want.Count == have.Count && issues.Count == 0)
            {
                for (int i = 0; i < want.Count; i++)
                {
                    if (!string.Equals(want[i], have[i], StringComparison.OrdinalIgnoreCase))
                    {
                        issues.Add(new Issue("The load order does not match the server's from " + want[i] + " onwards.", true));
                        break;
                    }
                }
            }

            // A plugin the list references but that is not actually on disk.
            string data = Path.Combine(Paths.Game, "Data");
            foreach (string p in want)
            {
                try { if (!File.Exists(Path.Combine(data, p))) issues.Add(new Issue(p + " is in the list but the file is not in Data.", true)); }
                catch { }
            }

            // Personal mods that carry a plugin will be refused.
            if (Directory.Exists(Paths.Personal))
            {
                foreach (string f in Directory.GetFiles(Paths.Personal, "*.*", SearchOption.AllDirectories))
                {
                    string e = Path.GetExtension(f).ToLowerInvariant();
                    if (e == ".esp" || e == ".esm" || e == ".esl")
                        issues.Add(new Issue("Your own mods folder contains " + Path.GetFileName(f) + ". Plugins there will get you refused.", true));
                }
            }

            // Bytes, not names. Everything above compares names, and a machine
            // can pass every line of it and still be red in the game.
            try { issues.AddRange(Bytes(cfg)); } catch { }

            return issues;
        }

        // ------------------------------------------------------------ bytes
        //
        // The game runs its own check once the world is up: for every plugin in
        // the server's manifest, at the same position, the name has to match
        // and so do the size and the crc32 of the file. One difference paints
        // LOAD ORDER ERROR over the screen for the rest of the session, and
        // every form in that plugin can point at something the server does not
        // mean. This page said "Everything matches" to somebody in exactly
        // that state on 17 Sep, because it only ever compared names: the
        // collection had given his machine another build of one plugin, same
        // name, same place in the order, other bytes.
        //
        // So the same comparison runs here, against the same manifest, and
        // Fix fetches the server's copy of a plugin that differs. The five
        // Bethesda masters and the Creation Club files are left out the way
        // the game leaves them out: Steam owns those, and a person's Skyrim
        // is not the launcher's to rewrite.
        //
        // A server that cannot be reached reports nothing. A check that could
        // not run is not a problem with this machine, and Play should not be
        // refused because the server is down for an update.

        /// <summary>What the launcher writes as server-master-key; the manifest and the files live under it.</summary>
        const string ServerKey = "thornswood";

        static readonly HashSet<string> Storefront = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "Skyrim.esm", "Update.esm", "Dawnguard.esm", "HearthFires.esm", "Dragonborn.esm",
            "ccBGSSSE001-Fish.esm", "ccBGSSSE025-AdvDSGS.esm", "ccBGSSSE037-Curios.esl",
            "ccQDRSSE001-SurvivalMode.esl", "_ResourcePack.esl"
        };

        [DataContract]
        class ServerManifest
        {
            [DataMember] public ServerMod[] mods;
        }

        [DataContract]
        class ServerMod
        {
            [DataMember] public string filename;
            [DataMember] public long size;
            [DataMember] public long crc32;   // the server writes it as a signed 32 bit number
        }

        /// <summary>True when the last Run got a manifest out of the server, so "Everything matches" can say what it covered.</summary>
        public static bool BytesChecked;

        static ServerMod[] manifestCache;
        static DateTime manifestAt = DateTime.MinValue;
        static string manifestFrom = "";

        static string ServerBase(Config cfg)
        {
            return "http://" + cfg.ServerAddress + ":" + SkyMp.ResourcePortFor(cfg) + "/api/servers/" + ServerKey;
        }

        /// <summary>The server's manifest, kept for a minute so Play and Scan a second apart do not fetch it twice.</summary>
        static ServerMod[] Manifest(Config cfg)
        {
            string url = ServerBase(cfg) + "/manifest.json";
            if (manifestCache != null && manifestFrom == url && (DateTime.UtcNow - manifestAt).TotalSeconds < 60)
                return manifestCache;
            byte[] raw = Get(url, 4000);
            if (raw == null) return null;
            try
            {
                var ser = new DataContractJsonSerializer(typeof(ServerManifest));
                ServerManifest doc;
                using (var ms = new MemoryStream(raw)) doc = (ServerManifest)ser.ReadObject(ms);
                if (doc == null || doc.mods == null || doc.mods.Length == 0) return null;
                manifestCache = doc.mods;
                manifestAt = DateTime.UtcNow;
                manifestFrom = url;
                return doc.mods;
            }
            catch { return null; }
        }

        /// <summary>Every plugin whose size or crc32 is not the server's, as blocking issues that carry what Fix needs.</summary>
        public static List<Issue> Bytes(Config cfg)
        {
            var issues = new List<Issue>();
            BytesChecked = false;
            if (cfg == null || string.IsNullOrEmpty(cfg.ServerAddress)) return issues;
            ServerMod[] mods = Manifest(cfg);
            if (mods == null) return issues;
            BytesChecked = true;

            string data = Path.Combine(Paths.Game, "Data");
            for (int idx = 0; idx < mods.Length; idx++)
            {
                ServerMod m = mods[idx];
                if (m == null || string.IsNullOrEmpty(m.filename) || Storefront.Contains(m.filename)) continue;
                string p = Path.Combine(data, m.filename);
                long size;
                try
                {
                    if (!File.Exists(p)) continue;   // Run has already said it is not installed
                    size = new FileInfo(p).Length;
                }
                catch { continue; }

                bool same = size == m.size;
                if (same)
                {
                    try { same = Crc32Of(p, size) == (int)m.crc32; }
                    catch { continue; }   // open elsewhere; it is checked again next time
                }
                if (same) continue;

                var i = new Issue(
                    m.filename + " is not the same file the server has" +
                    (size == m.size ? " (same size, other contents)" : " (yours is " + Fmt(size) + ", the server's is " + Fmt(m.size) + ")") +
                    ". The game shows that as LOAD ORDER ERROR and anything in it can mean something else here than on the server. Fix fetches the server's copy.",
                    true);
                i.Plugin = m.filename;
                i.WantSize = m.size;
                i.WantCrc = (int)m.crc32;
                i.WantIndex = idx;
                issues.Add(i);
            }
            return issues;
        }

        static string Fmt(long bytes)
        {
            if (bytes >= 1048576) return (bytes / 1048576.0).ToString("0.0") + " MB";
            if (bytes >= 1024) return (bytes / 1024.0).ToString("0.0") + " KB";
            return bytes + " bytes";
        }

        // Standard CRC-32 (the zlib one), which is what the server's manifest
        // carries, read back as the signed number the manifest prints. Cached
        // by size and write time, because Run is called at Play and again when
        // the game closes and there is no reason to read thirty megabytes twice.
        static uint[] crcTable;
        class CrcEntry { public long Size; public DateTime Written; public int Crc; }
        static readonly Dictionary<string, CrcEntry> crcCache = new Dictionary<string, CrcEntry>(StringComparer.OrdinalIgnoreCase);

        static int Crc32Of(string path, long size)
        {
            DateTime written = File.GetLastWriteTimeUtc(path);
            CrcEntry hit;
            lock (crcCache)
            {
                if (crcCache.TryGetValue(path, out hit) && hit.Size == size && hit.Written == written) return hit.Crc;
            }
            int crc;
            using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                crc = Crc32Of(fs);
            lock (crcCache)
            {
                crcCache[path] = new CrcEntry { Size = size, Written = written, Crc = crc };
            }
            return crc;
        }

        static int Crc32Of(Stream s)
        {
            if (crcTable == null)
            {
                var t = new uint[256];
                for (uint i = 0; i < 256; i++)
                {
                    uint c = i;
                    for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320u ^ (c >> 1) : c >> 1;
                    t[i] = c;
                }
                crcTable = t;
            }
            uint crc = 0xFFFFFFFFu;
            var buf = new byte[1 << 16];
            int n;
            while ((n = s.Read(buf, 0, buf.Length)) > 0)
                for (int i = 0; i < n; i++) crc = crcTable[(crc ^ buf[i]) & 0xFF] ^ (crc >> 8);
            return (int)(crc ^ 0xFFFFFFFFu);
        }

        // WebClient has no timeout worth the name. This one does.
        static byte[] Get(string url, int ms)
        {
            try
            {
                var req = (HttpWebRequest)WebRequest.Create(url);
                req.Timeout = ms;
                req.ReadWriteTimeout = ms;
                req.UserAgent = "ThornswoodLauncher/" + Updater.Version;
                using (var res = (HttpWebResponse)req.GetResponse())
                using (var s = res.GetResponseStream())
                using (var ms_ = new MemoryStream())
                {
                    s.CopyTo(ms_);
                    return ms_.ToArray();
                }
            }
            catch { return null; }
        }

        /// <summary>
        /// The server's copy of one plugin, written over the file that is here.
        /// Written into the existing file rather than swapped for a new one, so
        /// a hard link (Vortex's deployment, the launcher's own Game folder,
        /// which share the file with the Steam copy) sees the same bytes
        /// everywhere and Vortex has nothing to report. The old bytes are kept
        /// whole under Profile\Replaced first. Nothing is written unless what
        /// came down is exactly what the manifest describes.
        /// </summary>
        static bool FetchPlugin(Config cfg, Issue i, Action<string> say)
        {
            string dest = Path.Combine(Paths.Game, "Data", i.Plugin);
            // Served by manifest position, not name: the resources server refuses
            // any URL whose name contains .esp/.esm/.esl. gamemode publishFiles
            // writes each plugin as <index>.bin at the same position.
            byte[] bytes = Get(ServerBase(cfg) + "/plugins/" + i.WantIndex + ".bin", 90000);
            if (bytes == null)
            {
                say(i.Plugin + ": the server did not hand over its copy. It publishes the files at start, so a server older than this launcher, or one that is down, has none to give.");
                return false;
            }
            int crc;
            using (var ms = new MemoryStream(bytes)) crc = Crc32Of(ms);
            if (bytes.LongLength != i.WantSize || crc != i.WantCrc)
            {
                say(i.Plugin + ": what the server handed over is not what its own manifest describes, so nothing was changed.");
                return false;
            }
            try
            {
                Directory.CreateDirectory(Paths.Replaced);
                File.Copy(dest, Path.Combine(Paths.Replaced, i.Plugin + "." + DateTime.Now.ToString("yyyyMMdd-HHmmss")), true);
            }
            catch { }
            // Our bytes go in our copy of the file and nowhere else.
            //
            // Vortex deploys by hard link, so this plugin and the Nexus mod in
            // Vortex's staging are one file under two names, and staging is
            // shared with every other Skyrim profile on this machine. Without
            // this, pressing Fix here reached into another SkyMP server's
            // collection and changed a plugin it was relying on. FileMode.Create
            // truncates the file it is given rather than replacing it, so the
            // link has to come off first.
            OwnGame.Detach(dest);
            try
            {
                using (var fs = new FileStream(dest, FileMode.Create, FileAccess.Write, FileShare.None))
                    fs.Write(bytes, 0, bytes.Length);
            }
            catch (Exception ex)
            {
                say(i.Plugin + " could not be written (" + ex.Message.TrimEnd('.') + "). Close Skyrim and Vortex and press Fix again.");
                return false;
            }
            lock (crcCache) { crcCache.Remove(dest); }
            say(i.Plugin + " is now the server's copy (" + Fmt(bytes.LongLength) + "). Yours is kept in Profile\\Replaced.");
            return true;
        }

        /// <summary>
        /// Puts the shipped load order back, into the file that is actually
        /// read. Same correction as Run: Paths.Live rather than Paths.LocalAD.
        ///
        /// Under the collection this is Vortex's file. Writing it here is still
        /// right, because the server refuses a mismatched list and this is what
        /// it expects, but Vortex will write its own version again the next time
        /// it deploys. The launcher says so rather than letting somebody fix the
        /// same thing twice and wonder why.
        /// </summary>
        public static int Fix() { return Fix(null, null); }

        public static int Fix(Config cfg, Action<string> say)
        {
            if (say == null) say = delegate(string m) { };
            int n = 0;
            foreach (string f in new string[] { "plugins.txt", "loadorder.txt" })
            {
                string src = Path.Combine(Paths.Golden, f);
                if (!File.Exists(src)) continue;
                Directory.CreateDirectory(Paths.Live);
                File.Copy(src, Path.Combine(Paths.Live, f), true);
                n++;
            }

            // Fix means make this install match what the server expects, and
            // another server's client running the main menu is the furthest
            // from that anything gets. It is moved aside, never deleted,
            // because somebody who plays here may also play there.
            n += Checks.IsolateForeign(null);
            n += Checks.FlagLight(null);

            // The server's copy of every plugin whose bytes are not its own.
            if (cfg != null)
            {
                foreach (Issue i in Bytes(cfg))
                    if (i.Plugin != null && FetchPlugin(cfg, i, say)) n++;
            }
            return n;
        }

        /// <summary>Where the load order being judged actually lives, for the
        /// launcher to show, because the last hour of this was not knowing.</summary>
        public static string LiveFile { get { return Path.Combine(Paths.Live, "plugins.txt"); } }

        /// <summary>Copies the player's own loose files into the game before launch.</summary>
        public static int DeployPersonal()
        {
            if (!Directory.Exists(Paths.Personal)) { Directory.CreateDirectory(Paths.Personal); return 0; }
            string dataRoot = Path.Combine(Paths.Game, "Data");
            int n = 0;
            foreach (string src in Directory.GetFiles(Paths.Personal, "*.*", SearchOption.AllDirectories))
            {
                string rel = src.Substring(Paths.Personal.Length).TrimStart('\\');
                string ext = Path.GetExtension(src).ToLowerInvariant();
                if (ext == ".esp" || ext == ".esm" || ext == ".esl") continue;   // never, it breaks the check
                string dest = Path.Combine(dataRoot, rel);
                string full = Path.GetFullPath(dest);
                if (!full.StartsWith(dataRoot, StringComparison.OrdinalIgnoreCase)) continue;
                try
                {
                    Directory.CreateDirectory(Path.GetDirectoryName(full));
                    // Detach rather than Unshare: the same reason as the plugin
                    // write above. Unshare does nothing on a collection install,
                    // which is the layout that ships, so somebody's own file
                    // copied over a Vortex deployed one went straight into the
                    // Nexus mod in staging.
                    OwnGame.Detach(full);
                    File.Copy(src, full, true);
                    n++;
                }
                catch { }
            }
            return n;
        }

        public static string[] PersonalFiles()
        {
            try
            {
                if (!Directory.Exists(Paths.Personal)) return new string[0];
                return Directory.GetFiles(Paths.Personal, "*.*", SearchOption.AllDirectories);
            }
            catch { return new string[0]; }
        }
    }
}
