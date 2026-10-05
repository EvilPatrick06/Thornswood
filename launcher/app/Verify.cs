using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Text;

namespace Thornswood
{
    class Issue
    {
        public string Text;
        public bool Blocking;      // true = you will be refused by the server
        // The plugin is not in the live list and not on disk ("is not installed").
        // Fix cannot invent a mod Vortex never had; Shell greys the button for
        // these unless Vortex deploys somewhere else (OwnFolderNext).
        public bool Absent;
        // The plugin's file is missing from the game folder's Data, including
        // ones still named in plugins.txt. Set once per plugin the golden list
        // expects but that is not on disk, so the Mods card can count how many
        // and, when it is most of them, say the collection is not deployed in
        // one sentence instead of one line per plugin. Fix restores these from
        // Vortex (OwnGame.RestoreMissingPlugins); it does not drop them from
        // the list. The gate still counts Blocking (see Shell Play).
        public bool FileMissing;
        // The file is there, enabled, in the right place, and its bytes are
        // not the server's. Fix fetches the server's copy. Which file, and what
        // the server says it should be, so Fix does not have to ask twice.
        public string Plugin;
        public long WantSize;
        public int WantCrc;
        public int WantIndex;   // position in the server manifest; the file is served at /plugins/<index>.bin
        // The server hands out its copy: Thornswood's own plugin, the only one
        // its manifest lists as served (#1180). Fix fetches only these; every
        // other plugin is another author's mod, which Vortex installs from its
        // author, and Fix names the mod to put right in Vortex instead.
        public bool Served;
        // The folder Vortex really deploys into, when it is not the Skyrim this
        // install reads. Fix points the launcher at it and Thornswood's own
        // folder is made from it, so the plugins Run finds missing are not a
        // reason to grey Fix out while this is on the list.
        public string VortexFolder;
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

        /// <summary>How many plugins the last Run's reference list enabled, so the
        /// Mods card can tell "most of them are missing" from "one is". 0 when there
        /// was no list to compare against.</summary>
        public static int Expected;

        /// <summary>
        /// The issues the last Run produced. Checks.All (Ready to launch Mods /
        /// Mod list) and the Scan and Fix card both read this so they cannot
        /// disagree: one Run, one truth. Null until the first Run.
        /// </summary>
        public static List<Issue> LastIssues;

        /// <summary>True when the last Run was given a Config, so load order and
        /// bytes were judged against the server the same way Scan does.</summary>
        public static bool LastUsedServer;

        public static List<Issue> Run() { return Run(null); }

        /// <summary>
        /// The shipped plugins.txt is what the server was built against, so it is
        /// the reference for what is on and off. Anything the live list adds or
        /// drops is what gets a person refused at connect. With a Config to hand
        /// it also asks the server for its manifest: the order is judged against
        /// that, the way the game judges it (see LoadOrder), and so are the
        /// bytes of every plugin; see Bytes.
        /// </summary>
        public static List<Issue> Run(Config cfg) { return Run(cfg, true); }

        /// <param name="checkBytes">
        /// False skips the per-plugin CRC pass (Bytes). Bring it up to date from
        /// Vortex uses that when Refresh reported the folder already matched, so
        /// the finish path is not held on hashing every plugin after a no-op.
        /// Names, order, missing files and light flags are still judged.
        /// </param>
        public static List<Issue> Run(Config cfg, bool checkBytes)
        {
            var issues = new List<Issue>();
            Expected = 0;

            // The own folder was chosen at install and is not made yet
            // (#1226): Paths.Game is Profile\Payload, Thornswood's own files
            // and nothing else, so there is no game to hold against the
            // server. Checking Payload would call every plugin of the
            // collection missing while Vortex has it deployed. One line says
            // what is next, and Fix makes the folder (OwnFolderNext).
            if (Paths.OwnFirst)
            {
                string why = null;
                if (cfg != null)
                {
                    try { why = OwnGame.WhyNot(cfg, OwnGame.DeploysInto(cfg)); }
                    catch (Exception ex) { why = ex.Message; }
                }
                issues.Add(new Issue("Thornswood's own Skyrim folder was chosen when Thornswood was installed and is not made yet, so there is no game to check. " +
                                     (why == null ? "Fix makes it from what Vortex has deployed." : "It cannot be made yet: " + why), false));
                if (cfg != null || LastIssues == null)
                {
                    LastIssues = issues;
                    LastUsedServer = cfg != null;
                }
                return issues;
            }
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

            // Vortex deploys the collection somewhere other than the Skyrim this
            // install reads. 24 September, a tester whose Vortex manages another
            // SkyMP server's copy of Skyrim, Keizaal Online, and deploys
            // Thornswood's collection into it: every plugin below then reads as
            // not installed, and nothing said where the mods actually were.
            // Patrick: "can we fix it so the launcher can detect and fix this in
            // scan and fix aswell". First, because the card shows four lines
            // and this one explains the ninety four after it. Blocking, which
            // adds no refusal: it only appears on a shared Skyrim, and Play
            // already refuses to start out of one (Shell.OwnGameRequired).
            if (Paths.Collection && !OwnGame.Active)
            {
                string into = "";
                try { into = OwnGame.DeploysElsewhere(cfg); }
                catch (Exception ex) { Swallow.Note("Verify.Run, asking which folder Vortex deploys into", ex); }
                if (into.Length > 0)
                {
                    string game = "";
                    try { game = OwnGame.Source(cfg); } catch { /* "" reads as apart, which only changes the sentence */ }
                    bool apart = !string.Equals(game, into, StringComparison.OrdinalIgnoreCase);
                    // "Vortex deploys into", not "Thornswood's mods": the record
                    // here says Vortex deployed something, not that it is the
                    // Thornswood collection. Fix checks that before it builds
                    // (OwnGame.WhyNot counts Thornswood's plugins) and says to
                    // enable the Thornswood profile when it is not.
                    var i = new Issue("Vortex deploys into " + into + ", not into " + Paths.Game +
                                      ", so Fix will make Thornswood's own Skyrim folder from what Vortex deployed there, once it has checked that is Thornswood's collection" +
                                      (apart ? ", taking the game itself from the Steam copy and nothing else from that folder." : "."), true);
                    i.VortexFolder = into;
                    issues.Add(i);
                }
            }

            List<string> want = Enabled(golden), have = Enabled(live);
            Expected = want.Count;
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
                try { onDisk = File.Exists(Path.Combine(dataDir, p)); } catch (Exception ex) { Swallow.Note("Verify.Run, asking whether " + p + " is on disk", ex); }
                issues.Add(new Issue(
                    onDisk ? p + " is turned off." : p + " is not installed.",
                    true, !onDisk));
            }

            // An Anniversary owner's Creation Club plugins that take no place in
            // the order are not counted here (#479, LoadOrder.NotInBuild).
            foreach (string p in LoadOrder.NotInBuild(have, want, LightOrMissing))
                issues.Add(new Issue(p + " is enabled but is not part of this build.", true));

            // Another server's client. Not a plugin, so nothing above would ever
            // have found it, and it is the difference between Thornswood loading
            // and another server's main menu loading instead.
            foreach (string f in Checks.ForeignClients())
                issues.Add(new Issue(
                    Path.GetFileName(f) + " belongs to another server. It replaces the main menu " +
                    "and asks you to sign in to them. Fix moves it aside into Thornswood's " +
                    "Isolated folder and nothing is deleted, so that server still works.", true));

            // A plugin the server counts as light but this machine's copy does
            // not, which gives it a load order index the server does not have and
            // shifts everything after it by one. The set is derived from the
            // server's manifest against the collection reference, so a new one is
            // caught without editing Checks. See Verify.MustBeLight.
            foreach (string p in Checks.NotLight(MustBeLight(cfg)))
                issues.Add(new Issue(
                    p + " is not flagged light, so from there on your load order counts " +
                    "one place differently from the server's. Fix flags it; nothing else changes.", true));
            // The order, position by position. Only when nothing above was
            // found, as before: a plugin turned off or not flagged light
            // already explains the shift from there on, and one problem
            // should read as one problem.
            //
            // Against the server's own manifest when the server answers,
            // because that is the list the game compares with: the same
            // walk as loadOrderVerificationService in the client, over the
            // order the game will count (LoadOrder.GameOrder), names only;
            // Bytes below does the sizes and crcs. On 20 Sep a list that
            // matched the shipped reference name for name was in another
            // order than the server's, LOOT having re-sorted both, and the
            // game showed LOAD ORDER ERROR while this said everything checked
            // out. The shipped reference is only for when the server cannot
            // be asked, and never alongside the manifest, or Fix would be
            // chasing two orders.
            if (issues.Count == 0)
            {
                ServerMod[] mods = null;
                try { mods = Manifest(cfg); } catch (Exception ex) { Swallow.Note("Verify.Run, asking the server for its manifest", ex); }
                if (mods != null)
                {
                    List<string> manifest = Names(mods);
                    List<string> game = LoadOrder.GameOrder(have, LightOrMissing, Ccc(), InData);
                    int at = LoadOrder.FirstMismatch(game, manifest);
                    if (at >= 0)
                    {
                        string yours = at < game.Count ? game[at] : "nothing";
                        string theirs = at < manifest.Count ? manifest[at] : "nothing";
                        issues.Add(new Issue(
                            "Your load order is not the server's from position " + at + ": you have " + yours +
                            " there, the server has " + theirs + ". The game shows that as LOAD ORDER ERROR. " +
                            "Fix puts the server's order into this build's plugin list; nothing is downloaded.", true));
                    }
                    else
                    {
                        // The light order, the same walk over the light
                        // plugins (#1715). When it differs every light form id
                        // the server stores names another plugin's form, a
                        // beard turns into nothing, and the person sees a face
                        // that is wrong. The client built from the fork since
                        // #1715 compares the light list too and shows LOAD
                        // ORDER ERROR, and the server ends the session when
                        // refusing is on; this says it before Play.
                        List<string> serverLight = Names(manifestLight);
                        if (serverLight.Count > 0)
                        {
                            List<string> mine = LoadOrder.LightOrder(have, Light, Ccc(), InData);
                            int li = LoadOrder.FirstMismatch(mine, serverLight);
                            if (li >= 0)
                            {
                                string yours = li < mine.Count ? mine[li] : "nothing";
                                string theirs = li < serverLight.Count ? serverLight[li] : "nothing";
                                issues.Add(new Issue(
                                    "Your light plugins are not in the server's order from light position " + li + ": you have " + yours +
                                    " there, the server has " + theirs + ". Hair, beards and other parts from light plugins would show as the wrong ones. " +
                                    "Fix puts the server's order into this build's plugin list; nothing is downloaded.", true));
                            }
                        }
                    }
                }
                else if (want.Count == have.Count)
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
            }

            // Creation Club plugins the game loads because Skyrim.ccc names
            // them, which no plugin list shows, and only the ones that take a
            // place in the order: a light one is nothing to the server, the
            // same as the light plugins in the list (Checks.StrayCreations
            // says why). After the positional pass on purpose: that pass only
            // runs when nothing else was found.
            foreach (string p in Checks.StrayCreations(wantSet, LightNames(cfg)))
            {
                // A light one is stray only against a server that publishes
                // its light order (Checks.StrayCreations), and it moves the
                // light plugins rather than the full ones.
                bool lightStray = Checks.TakesNoPlace(p);
                issues.Add(new Issue(
                    p + " is loaded by the game on its own, because Skyrim.ccc names it, and the server does not have it, " +
                    (lightStray
                        ? "so every light plugin after it is one place off the server's, and hair, beards and other parts from light plugins show as the wrong ones. "
                        : "so every plugin after it is out of place and the game shows LOAD ORDER ERROR. ") +
                    "Fix moves it aside into Thornswood's Isolated folder and nothing is deleted.",
                    true));
            }

            // A plugin the list references but that is not actually on disk.
            // One per expected plugin, flagged FileMissing so the card can count
            // them: when it is most of the list, Vortex has not deployed the
            // collection, and the card says that once instead of once per plugin.
            string data = Path.Combine(Paths.Game, "Data");
            foreach (string p in want)
            {
                try
                {
                    if (!File.Exists(Path.Combine(data, p)))
                    {
                        var gone = new Issue(p + " is in the list but the file is not in Data.", true);
                        gone.FileMissing = true;
                        gone.Plugin = p;
                        issues.Add(gone);
                    }
                }
                catch (Exception ex) { Swallow.Note("Verify.Run, asking whether " + p + " is missing from Data", ex); }
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
            // can pass every line of it and still be red in the game. Skipped
            // when the caller already knows the plugin files did not change
            // (Bring it up to date after an already-matched Refresh).
            if (checkBytes)
            {
                try { issues.AddRange(Bytes(cfg)); } catch (Exception ex) { Swallow.Note("Verify.Run, Bytes", ex); }
            }

            // Only a server-aware Run is remembered as the shared truth. A
            // local-only Run(null) from Checks.All must not overwrite a Scan,
            // or the checklist drifts from the card on the next redraw.
            if (cfg != null)
            {
                LastIssues = issues;
                LastUsedServer = true;
            }
            else if (LastIssues == null)
            {
                LastIssues = issues;
                LastUsedServer = false;
            }
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
        // Fix fetches the server's copy of a plugin that differs when the
        // server hands that plugin out, which it does for Thornswood's own and
        // nothing else (#1180, the manifest's "served" list). Another author's
        // plugin comes from its author through Vortex, and Fix names the mod
        // to update or reinstall there. The five Bethesda masters and the
        // Creation Club files are left out the way the game leaves them out:
        // Steam owns those, and a person's Skyrim is not the launcher's to
        // rewrite.
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
            // The plugins the server hands out at /plugins/<index>.bin:
            // Thornswood's own, by the gamemode's server manifest block (#1180).
            [DataMember] public string[] served;
            // A server that loads light plugins publishes them apart from
            // mods, in light index order (#1715): mods stays the full plugins
            // the client's own check compares with Game.getModName. loadOrder
            // is the server's whole order, full and light together. Both are
            // absent on a server that loads no light plugin.
            [DataMember] public ServerMod[] light;
            [DataMember] public string[] loadOrder;
        }

        [DataContract]
        class ServerMod
        {
            [DataMember] public string filename;
            [DataMember] public long size;
            [DataMember] public long crc32;   // the server writes it as a signed 32 bit number
            // Named in the manifest's "served" list, set by Manifest (#1180).
            public bool Served;
        }

        /// <summary>True when the last Run got a manifest out of the server, so "Everything matches" can say what it covered.</summary>
        public static bool BytesChecked;

        static ServerMod[] manifestCache;
        // The light half and the whole order of the same manifest, set with
        // manifestCache so the three always describe one answer.
        static ServerMod[] manifestLight;
        static string[] manifestAll;
        static DateTime manifestAt = DateTime.MinValue;
        static string manifestFrom = "";
        // A fetch that failed is remembered for the same minute a good one is
        // kept, because Run asks for the manifest once for the order and Bytes
        // asks again, and a server that does not answer used to cost the four
        // second timeout twice before the scan could say so.
        static DateTime manifestFailedAt = DateTime.MinValue;
        static string manifestFailedFrom = "";

        static string ServerBase(Config cfg)
        {
            return "http://" + cfg.ServerAddress + ":" + SkyMp.ResourcePortFor(cfg) + "/api/servers/" + ServerKey;
        }

        /// <summary>The server's manifest, kept for a minute so Play and Scan a second apart do not fetch it twice.</summary>
        static ServerMod[] Manifest(Config cfg)
        {
            if (cfg == null || string.IsNullOrEmpty(cfg.ServerAddress)) return null;
            string url = ServerBase(cfg) + "/manifest.json";
            if (manifestCache != null && manifestFrom == url && (DateTime.UtcNow - manifestAt).TotalSeconds < 60)
                return manifestCache;
            if (manifestFailedFrom == url && (DateTime.UtcNow - manifestFailedAt).TotalSeconds < 60)
                return null;
            byte[] raw = Get(url, 4000);
            if (raw == null) { manifestFailedFrom = url; manifestFailedAt = DateTime.UtcNow; return null; }
            try
            {
                var ser = new DataContractJsonSerializer(typeof(ServerManifest));
                ServerManifest doc;
                using (var ms = new MemoryStream(raw)) doc = (ServerManifest)ser.ReadObject(ms);
                if (doc == null || doc.mods == null || doc.mods.Length == 0) return null;
                var served = new HashSet<string>(doc.served ?? new string[0], StringComparer.OrdinalIgnoreCase);
                foreach (ServerMod m in doc.mods)
                    if (m != null && m.filename != null) m.Served = served.Contains(m.filename);
                manifestLight = doc.light ?? new ServerMod[0];
                manifestAll = doc.loadOrder ?? new string[0];
                manifestCache = doc.mods;
                manifestAt = DateTime.UtcNow;
                manifestFrom = url;
                manifestFailedFrom = "";
                return doc.mods;
            }
            catch { manifestFailedFrom = url; manifestFailedAt = DateTime.UtcNow; return null; }
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

            // The light plugins a server publishes (#1715) after its full
            // ones: a light plugin with other bytes holds other forms under
            // the same light index, which is the same fault as a full one.
            // None of them is served, so Fix sends the person to Vortex.
            ServerMod[] light = manifestLight ?? new ServerMod[0];
            int all = mods.Length + light.Length;
            string data = Path.Combine(Paths.Game, "Data");
            for (int idx = 0; idx < all; idx++)
            {
                // On the Play button only while it is waiting on this, after
                // the game folder is prepared (#1145); PlayProgress drops it
                // otherwise.
                PlayProgress.Files("Checking files", idx + 1, all);
                bool isLight = idx >= mods.Length;
                ServerMod m = isLight ? light[idx - mods.Length] : mods[idx];
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
                    ". The game shows that as LOAD ORDER ERROR and anything in it can mean something else here than on the server. " +
                    (m.Served ? "Fix fetches the server's copy." : FromVortex(cfg, m.filename)),
                    true);
                i.Plugin = m.filename;
                i.WantSize = m.size;
                i.WantCrc = (int)m.crc32;
                // Where the file is served, /plugins/<index>.bin, which only a
                // full plugin of ours ever is. Manifest marks served on mods
                // alone, so a light entry is never served and Fix sends the
                // person to Vortex for it.
                i.WantIndex = isLight ? -1 : idx;
                i.Served = m.Served;
                issues.Add(i);
            }
            return issues;
        }

        /// <summary>
        /// What puts another author's plugin right, said by Scan and by Fix.
        /// The server hands out only Thornswood's own plugin (#1180): any
        /// other is that author's to give out, through Vortex and the
        /// collection, so Vortex is where it is put right. The mod is named by
        /// Vortex's own deployment record when there is one.
        /// </summary>
        static string FromVortex(Config cfg, string plugin)
        {
            string mod = null;
            try { mod = OwnGame.VortexModOf(cfg, plugin); }
            catch (Exception ex) { Swallow.Note("Verify.FromVortex, asking Vortex's record which mod has " + plugin, ex); }
            return "It comes from another author's mod, which Vortex installs from its author, so the server does not hand it out. " +
                   "In Vortex, update the Thornswood collection, or reinstall " +
                   (string.IsNullOrEmpty(mod) ? "the mod that has " + plugin : mod) +
                   " (right click it on the Mods page, Reinstall), then press Scan.";
        }

        /// <summary>
        /// The server's light plugins in light index order, or an empty list
        /// when it publishes none: a server that loads no light plugin, or one
        /// that cannot be asked. #1715.
        /// </summary>
        static List<string> LightNames(Config cfg)
        {
            ServerMod[] mods = null;
            try { mods = Manifest(cfg); } catch (Exception ex) { Swallow.Note("Verify.LightNames, asking the server for its manifest", ex); }
            if (mods == null) return new List<string>();
            return Names(manifestLight);
        }

        /// <summary>
        /// The server's whole order, full and light plugins together, by name,
        /// when it publishes a light order; otherwise null, and the order to
        /// put a list into is the full one alone.
        /// </summary>
        static List<string> WholeOrder()
        {
            if (manifestLight == null || manifestLight.Length == 0 || manifestAll == null || manifestAll.Length == 0) return null;
            var l = new List<string>();
            foreach (string p in manifestAll)
            {
                if (string.IsNullOrEmpty(p)) continue;
                string n = p.Trim();
                int cut = Math.Max(n.LastIndexOf('/'), n.LastIndexOf('\\'));
                if (cut >= 0) n = n.Substring(cut + 1);
                if (n.Length > 0) l.Add(n);
            }
            return l;
        }

        /// <summary>The manifest's plugin names in its order, which is the server's load order.</summary>
        static List<string> Names(ServerMod[] mods)
        {
            var l = new List<string>();
            if (mods == null) return l;
            foreach (ServerMod m in mods)
                if (m != null && !string.IsNullOrEmpty(m.filename)) l.Add(m.filename);
            return l;
        }

        /// <summary>
        /// The plugins that have to carry the ESL flag on this machine, worked
        /// out from the server rather than kept by hand.
        ///
        /// The server's manifest names every plugin it counts, in order; the
        /// shipped reference list (Paths.Golden) enables the whole collection,
        /// its light plugins and all. A plugin the reference enables that the
        /// manifest leaves out is one the server treats as light: it drops light
        /// plugins, and anything mastering to one, because Game.GetModCount gives
        /// them no index. So this machine has to leave it out of the count too,
        /// or from that plugin on its load order sits one place off the server's
        /// and the game shows LOAD ORDER ERROR. That is Djinn's position 52 on
        /// 2026-09-24 exactly: his Immersive Armors copy was not light, so it
        /// took an index the server does not have.
        ///
        /// Derived, so the next plugin that ships light on the server but not on
        /// a tester's disk is caught without a name being added to Checks. The
        /// hand list in Checks.MustBeLight is always folded in: it is the answer
        /// when the server cannot be asked (no manifest to derive from), and belt
        /// and braces for the two names found by hand. Bethesda's masters and the
        /// Creation Club files are left out the way Bytes leaves them out, and an
        /// .esl takes no place in the order to begin with, so neither is flagged.
        /// </summary>
        public static List<string> MustBeLight(Config cfg)
        {
            var names = new List<string>();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (string n in Checks.MustBeLight)
                if (!string.IsNullOrEmpty(n) && seen.Add(n)) names.Add(n);

            ServerMod[] mods = null;
            try { mods = Manifest(cfg); }
            catch (Exception ex) { Swallow.Note("Verify.MustBeLight, asking the server for its manifest", ex); }
            if (mods != null)
            {
                var counted = new HashSet<string>(Names(mods), StringComparer.OrdinalIgnoreCase);
                foreach (string p in Enabled(Path.Combine(Paths.Golden, "plugins.txt")))
                {
                    if (p.EndsWith(".esl", StringComparison.OrdinalIgnoreCase)) continue;
                    if (counted.Contains(p) || Storefront.Contains(p)) continue;
                    if (seen.Add(p)) names.Add(p);
                }
            }
            return names;
        }

        // ------------------------------------------------------------ order
        //
        // What LoadOrder needs to know about this machine, and nothing else:
        // which plugins Skyrim.ccc names, which are in Data, which are light.

        /// <summary>Every plugin Skyrim.ccc names, in its order. The game loads the ones it finds before it reads any list.</summary>
        static List<string> Ccc()
        {
            var l = new List<string>();
            try
            {
                string ccc = Path.Combine(Paths.Game, "Skyrim.ccc");
                if (!File.Exists(ccc)) return l;
                foreach (string raw in File.ReadAllLines(ccc))
                {
                    string n = raw.Trim();
                    if (n.Length == 0 || n.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0) continue;
                    l.Add(n);
                }
            }
            catch (Exception ex) { Swallow.Note("Verify.Ccc", ex); }
            return l;
        }

        static bool InData(string name)
        {
            try { return File.Exists(Path.Combine(Paths.Game, "Data", name)); }
            catch { return false; }
        }

        /// <summary>True when the game gives the plugin no normal index: not in Data, an .esl, or flagged light.</summary>
        static bool LightOrMissing(string name)
        {
            return !InData(name) || Checks.TakesNoPlace(name);
        }

        /// <summary>True for a plugin in Data that is light. A missing one is not light; the "not in Data" issue owns it.</summary>
        static bool Light(string name)
        {
            return InData(name) && Checks.TakesNoPlace(name);
        }

        /// <summary>
        /// This build's plugin list in the server's order, when the server
        /// answers and the order is not already its own. LoadOrder.Reorder
        /// moves only the full plugins the server names and leaves every
        /// other line where it was, so the file keeps its header, its
        /// comments, its disabled entries and its light plugins. A server
        /// that publishes a light order (#1715) has its light plugins moved
        /// too, by LoadOrder.ReorderWhole, and the list is rewritten when
        /// either order is not the server's. Written
        /// back with the encoding and line endings it had: a byte order mark
        /// or a changed newline is enough for the game to read the list as
        /// something else. Returns 1 when the file was rewritten.
        /// </summary>
        public static int PutInServerOrder(Config cfg, Action<string> say)
        {
            ServerMod[] mods = null;
            try { mods = Manifest(cfg); } catch (Exception ex) { Swallow.Note("Verify.PutInServerOrder, asking the server for its manifest", ex); }
            if (mods == null) return 0;
            List<string> manifest = Names(mods);
            List<string> serverLight = Names(manifestLight);
            List<string> whole = WholeOrder();
            List<string> ccc = Ccc();

            // OrderFolder, not Paths.Live. Before the own folder exists
            // Live is Windows' own Skyrim folder (#1234).
            string live = Path.Combine(OrderFolder, "plugins.txt");
            if (!File.Exists(live)) return 0;
            List<string> enabledNow = Enabled(live);
            bool fullRight = LoadOrder.FirstMismatch(LoadOrder.GameOrder(enabledNow, LightOrMissing, ccc, InData), manifest) < 0;
            bool lightRight = serverLight.Count == 0 ||
                LoadOrder.FirstMismatch(LoadOrder.LightOrder(enabledNow, Light, ccc, InData), serverLight) < 0;
            if (fullRight && lightRight) return 0;

            byte[] raw;
            try { raw = File.ReadAllBytes(live); }
            catch { return 0; }
            bool bom = raw.Length >= 3 && raw[0] == 0xEF && raw[1] == 0xBB && raw[2] == 0xBF;
            var utf8 = new UTF8Encoding(false);
            string text = utf8.GetString(raw, bom ? 3 : 0, raw.Length - (bom ? 3 : 0));
            string nl = text.IndexOf("\r\n", StringComparison.Ordinal) >= 0 ? "\r\n" : "\n";
            bool trailing = text.EndsWith("\n");
            var lines = new List<string>(text.Split(new string[] { "\r\n", "\n" }, StringSplitOptions.None));
            if (trailing && lines.Count > 0) lines.RemoveAt(lines.Count - 1);

            // A server with a light order: every line it names, full and
            // light, into its whole order (#1715), so the light plugins take
            // the server's light indices and sit among the full ones where the
            // server has them. The Skyrim.ccc names are the game's to load
            // first and are skipped, as the masters are.
            List<string> ordered = whole != null ? LoadOrder.ReorderWhole(lines, whole, ccc) : LoadOrder.Reorder(lines, manifest, Light);
            if (ordered == null)
            {
                List<string> off = whole != null ? LoadOrder.NotEnabledWhole(lines, whole, ccc) : LoadOrder.NotEnabled(lines, manifest);
                say(off.Count > 0
                    ? "The server's order names " + string.Join(", ", off.ToArray()) + ", which this build's plugin list does not enable, so the order was left alone."
                    : "This build's plugin list enables the same plugin twice, so the order was left alone.");
                return 0;
            }
            string first;
            int moved = LoadOrder.Moved(lines, ordered, out first);
            if (moved == 0) return 0;

            var body = new List<byte>();
            if (bom) body.AddRange(new byte[] { 0xEF, 0xBB, 0xBF });
            body.AddRange(utf8.GetBytes(string.Join(nl, ordered.ToArray()) + (trailing ? nl : "")));
            try
            {
                File.WriteAllBytes(live, body.ToArray());
            }
            catch (Exception ex)
            {
                say("The plugin list could not be written (" + ex.Message.TrimEnd('.') + "). Close Skyrim and press Fix again.");
                return 0;
            }
            say(moved + (moved == 1 ? " plugin" : " plugins") + " moved into the server's order, the first " + first + ".");
            return 1;
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
            // Only what the server lists as served, Thornswood's own plugin
            // (#1180). Before that this fetched any plugin that differed, and
            // the server handed out 42 other authors' mods to anybody who
            // asked (measured on both servers, 5 Oct).
            if (!i.Served)
            {
                say(i.Plugin + " was left as it is. " + FromVortex(cfg, i.Plugin));
                return false;
            }
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
            bool hadLocal = false;
            try { hadLocal = File.Exists(dest); }
            catch (Exception ex) { Swallow.Note("Verify.FetchPlugin, asking whether " + i.Plugin + " was already in Data", ex); }
            if (hadLocal)
            {
                try
                {
                    Directory.CreateDirectory(Paths.Replaced);
                    File.Copy(dest, Path.Combine(Paths.Replaced, i.Plugin + "." + DateTime.Now.ToString("yyyyMMdd-HHmmss")), true);
                }
                catch (Exception ex) { Swallow.Note("Verify.FetchPlugin, keeping the old copy of " + i.Plugin + " under Profile\\Replaced", ex); }
            }
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
            say(i.Plugin + " is now the server's copy (" + Fmt(bytes.LongLength) + ")." + (hadLocal ? " Yours is kept in Profile\\Replaced." : ""));
            return true;
        }

        /// <summary>
        /// Puts the shipped plugin list back, into the file that is actually
        /// read, then the server's order into it when the server can be asked
        /// (PutInServerOrder). The file is OrderFolder: Profile until the own
        /// folder exists, and the file the game reads after that.
        ///
        /// Before the own folder exists this does not write Vortex's file in
        /// Windows' own Skyrim folder. The order waits in Profile (#1234).
        /// Once the folder exists, the file written is the one the game reads.
        /// </summary>
        public static int Fix() { return Fix(null, null); }

        /// <summary>
        /// Where plugins.txt and loadorder.txt are written. After the own
        /// folder exists, Paths.Live, the file the game reads. Before it
        /// exists, Paths.Live is Windows' own Skyrim folder, so the order
        /// waits in Profile and reaches the game when the folder is made
        /// (#1234).
        /// </summary>
        public static string OrderFolder
        {
            get { return Paths.Collection ? Paths.LocalAD : Paths.Live; }
        }

        /// <summary>
        /// The reference plugin list into the file the game actually reads.
        /// How many files were copied.
        ///
        /// Its own method because it is also run straight after an update that
        /// carried one, and it is the ONLY part of Fix that may be. Until
        /// 22 September a pack's profile entry landed in Profile\Default and
        /// stopped there, so a release that moved the load order installed
        /// cleanly and then refused the person at the door until they went
        /// back to the launcher and pressed Fix. A first time person reads
        /// that as the game being broken, and they are not wrong to.
        ///
        /// Nothing else in Fix may run on that path. IsolateForeign and
        /// IsolateCreations move other people's files aside and PutInServerOrder
        /// asks the server, and none of that is wanted unprompted after every
        /// pack.
        /// </summary>
        public static int SettleLoadOrder()
        {
            int n = 0;
            foreach (string f in new string[] { "plugins.txt", "loadorder.txt" })
            {
                string src = Path.Combine(Paths.Golden, f);
                if (!File.Exists(src)) continue;
                // Profile until the own folder exists. Paths.Live is then
                // Windows' own plugins.txt, the person's Steam Skyrim and
                // the active Vortex profile (#1234). SettleSettings carries
                // a list already waiting in Profile into the folder.
                Directory.CreateDirectory(OrderFolder);
                File.Copy(src, Path.Combine(OrderFolder, f), true);
                n++;
            }
            return n;
        }

        /// <summary>
        /// Set by Fix when it pointed the launcher at the folder Vortex really
        /// deploys into. The launcher then makes Thornswood's own folder the
        /// way Make it in Settings does, which is its job and not this one's:
        /// it asks, shows what is in the way, and restarts into the folder.
        /// </summary>
        public static bool OwnFolderNext;

        public static int Fix(Config cfg, Action<string> say)
        {
            if (say == null) say = delegate(string m) { };

            // Chosen at install and not made yet (#1226): what Fix puts right
            // is the folder Thornswood plays from, and that folder is what is
            // missing. Making it is the fix, the way Make it in Settings does
            // it; nothing else is touched first, least of all the Steam copy.
            if (Paths.OwnFirst)
            {
                OwnFolderNext = true;
                say("Thornswood's own Skyrim folder is made next, from what Vortex has deployed. Nothing else needs putting right before it exists.");
                return 1;
            }

            int n = SettleLoadOrder();

            // Run's first issue, when Vortex deploys somewhere else: saved as
            // VortexGame, so the own folder is made from there (OwnFolderNext).
            OwnFolderNext = false;
            if (cfg != null && Paths.Collection && !OwnGame.Active)
            {
                string into = "";
                try { into = OwnGame.DeploysElsewhere(cfg); }
                catch (Exception ex) { Swallow.Note("Verify.Fix, asking which folder Vortex deploys into", ex); }
                if (into.Length > 0)
                {
                    bool ok;
                    say(OwnGame.PointAt(cfg, into, out ok));
                    if (ok)
                    {
                        OwnFolderNext = true;
                        n++;
                    }
                }
            }

            // Fix means make this install match what the server expects, and
            // another server's client running the main menu is the furthest
            // from that anything gets. It is moved aside, never deleted,
            // because somebody who plays here may also play there.
            n += Checks.IsolateForeign(null);
            n += Checks.FlagLight(MustBeLight(cfg), null);

            // Creation Club plugins the game would load because Skyrim.ccc
            // names them. Moved aside the same way, and said, because these are
            // Steam's files and somebody may go looking for them.
            var wanted = new HashSet<string>(Enabled(Path.Combine(Paths.Golden, "plugins.txt")), StringComparer.OrdinalIgnoreCase);
            List<string> theirLight = cfg != null ? LightNames(cfg) : new List<string>();
            n += Checks.IsolateCreations(wanted, theirLight, say);

            // The server's order, into this build's own list. After the
            // reference copy, which settles what is on and off, and after the
            // creations are moved aside, so the order is judged on what the
            // game will count. Nothing is fetched for it, and the reference
            // under Profile\Default is not touched: the next release carries
            // the server's order in it (Publish-Update) and until then this
            // is what puts it right on a machine.
            if (cfg != null)
            {
                try { n += PutInServerOrder(cfg, say); } catch (Exception ex) { Swallow.Note("Verify.Fix, PutInServerOrder", ex); }
            }

            // Missing plugins the golden list expects. SettleLoadOrder only
            // rewrites plugins.txt; it never puts a file back into Data, which
            // is why Diagnostics Fix left CFTO-Lanterns / BeardMaskFix and the
            // like uncleared on Djinn's machine. Restore from Vortex first
            // (light plugins are not on the server at all). Then fetch any
            // still-missing non-light plugin the manifest names.
            try { n += OwnGame.RestoreMissingPlugins(cfg, say); }
            catch (Exception ex) { Swallow.Note("Verify.Fix, restoring missing plugins from Vortex", ex); say("Could not restore missing plugins from Vortex (" + ex.Message.TrimEnd('.') + ")."); }

            // The server's copy of our own plugin when its bytes are not the
            // server's; another author's is named for Vortex (#1180).
            if (cfg != null)
            {
                foreach (Issue i in Bytes(cfg))
                    if (i.Plugin != null && FetchPlugin(cfg, i, say)) n++;
            }

            // Still missing from Data and served by the server, which is our
            // own plugin only (#1180): fetch that copy. Bytes skips absent
            // files on purpose (Run already named them); Fix still has to put
            // ours back when the game folder lost it. Another author's missing
            // plugin is Vortex's to put back, and RestoreMissingPlugins above
            // has already said so.
            if (cfg != null)
            {
                try
                {
                    ServerMod[] mods = Manifest(cfg);
                    if (mods != null)
                    {
                        string dataDir = Path.Combine(Paths.Game, "Data");
                        for (int idx = 0; idx < mods.Length; idx++)
                        {
                            ServerMod m = mods[idx];
                            if (m == null || string.IsNullOrEmpty(m.filename) || Storefront.Contains(m.filename) || !m.Served) continue;
                            string dest = Path.Combine(dataDir, m.filename);
                            bool goneFile = false;
                            try { goneFile = !File.Exists(dest); }
                            catch (Exception ex) { Swallow.Note("Verify.Fix, asking whether " + m.filename + " is still missing before fetch", ex); goneFile = true; }
                            if (!goneFile) continue;
                            var miss = new Issue(m.filename + " is missing from Data; Fix fetches the server's copy.", true);
                            miss.FileMissing = true;
                            miss.Plugin = m.filename;
                            miss.WantSize = m.size;
                            miss.WantCrc = (int)m.crc32;
                            miss.WantIndex = idx;
                            miss.Served = true;
                            if (FetchPlugin(cfg, miss, say)) n++;
                        }
                    }
                }
                catch (Exception ex) { Swallow.Note("Verify.Fix, fetching still-missing plugins from the server", ex); }
            }
            return n;
        }

        /// <summary>Where the load order being judged actually lives, for the
        /// launcher to show, because the last hour of this was not knowing.</summary>
        public static string LiveFile { get { return Path.Combine(Paths.Live, "plugins.txt"); } }

        /// <summary>Copies the person's own loose files into the game before launch.</summary>
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
                catch (Exception ex) { Swallow.Note("Verify.DeployPersonal, " + rel, ex); }
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
