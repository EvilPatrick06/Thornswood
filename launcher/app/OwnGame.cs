using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Win32.SafeHandles;

namespace Thornswood
{
    /// <summary>
    /// Thornswood's own Skyrim folder, Root\Game, made from whatever Vortex has
    /// deployed while the Thornswood collection is the profile it has on.
    ///
    /// Until 17 September three roleplay servers all ran out of the one
    /// Steam copy of Skyrim. Every launcher wrote its own client into it, every
    /// Vortex profile switch took the other collection out of it, and on 16 Sep
    /// that was a another server session drawing Thornswood's menu, a Daedric menu
    /// behind every server, and a Thornswood launcher that thought its mods were
    /// gone whenever Vortex had another profile on. With a folder of its own,
    /// Thornswood starts from Root\Game, the other servers start from theirs,
    /// and switching the profile in Vortex no longer reaches Thornswood at all.
    ///
    /// The folder is made of hard links, not copies, so the collection is not
    /// on the disk twice. A hard link is the same file under a second name, so
    /// anything written into a linked file in place would land in Vortex's copy
    /// and in every other folder that links it. The game and the mods rewrite
    /// their settings files all the time, and every launcher rewrites its
    /// client. So those are copied and only the big files nothing writes to are
    /// linked: archives, textures, meshes, sounds, plugins. What this launcher
    /// itself writes over goes through Unshare or Separate first.
    ///
    /// Paths.Init already picks Root\Game over the Steam copy when it exists;
    /// that is the layout installs had before the collection. The difference is
    /// only where the files came from, recorded in Profile\OwnGame.
    /// </summary>
    static class OwnGame
    {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern bool CreateHardLink(string lpFileName, string lpExistingFileName, IntPtr lpSecurityAttributes);

        [StructLayout(LayoutKind.Sequential)]
        struct FileInfoByHandle
        {
            public uint FileAttributes;
            public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastAccessTime;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastWriteTime;
            public uint VolumeSerialNumber;
            public uint FileSizeHigh;
            public uint FileSizeLow;
            public uint NumberOfLinks;
            public uint FileIndexHigh;
            public uint FileIndexLow;
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool GetFileInformationByHandle(SafeFileHandle hFile, out FileInfoByHandle info);

        // ---------------------------------------------------------------- where

        /// <summary>The folder this makes. Paths.Init runs the game from here once it exists.</summary>
        public static string Folder { get { return Path.Combine(Paths.Root, "Game"); } }

        /// <summary>The records: what came from where, and when.</summary>
        public static string Dir { get { return Path.Combine(Paths.ProfileDir, "OwnGame"); } }

        /// <summary>
        /// One line per file brought in: kind (L linked, C copied), origin (V
        /// deployed by Vortex, O anything else), size and write time of the
        /// source when it was brought in, then the path under the game folder.
        /// Publish-Update reads the V lines to keep the collection out of packs.
        /// </summary>
        static string FilesList { get { return Path.Combine(Dir, "files.txt"); } }
        static string MadeFile { get { return Path.Combine(Dir, "made.txt"); } }
        static string LeftOutFile { get { return Path.Combine(Dir, "left-out.txt"); } }
        static string DeclinedFile { get { return Path.Combine(Dir, "declined.txt"); } }

        /// <summary>True when the game runs from a folder this made.</summary>
        public static bool Active
        {
            get
            {
                try
                {
                    return !Paths.Collection && File.Exists(FilesList) &&
                           string.Equals(Path.GetFullPath(Paths.Game).TrimEnd('\\'), Path.GetFullPath(Folder).TrimEnd('\\'), StringComparison.OrdinalIgnoreCase);
                }
                catch { return false; }
            }
        }

        /// <summary>Somebody said no to the offer at startup. Settings still has the button.</summary>
        public static bool Declined
        {
            get { try { return File.Exists(DeclinedFile); } catch { return false; } }
        }

        public static void Decline()
        {
            try { Directory.CreateDirectory(Dir); File.WriteAllText(DeclinedFile, DateTime.Now.ToString("o")); } catch { }
        }

        /// <summary>
        /// The Skyrim the game itself comes from: a Steam copy of Skyrim Special
        /// Edition, the one Downgrade keeps at the server's build. When Vortex
        /// deploys into a Steam copy it is that folder, which is the ordinary
        /// case and every install before 24 September. When Vortex deploys into
        /// any other folder it is still the Steam copy and never that folder
        /// (see DeploysInto and Gather). Downgrade, Leaks, Uninstall and the
        /// updater read this, so none of them ever writes into another server's
        /// copy of the game.
        /// </summary>
        public static string Source(Config cfg)
        {
            return GameFor(DeploysInto(cfg));
        }

        /// <summary>
        /// The Skyrim folder Vortex deploys into, where its record of what it
        /// deployed is read. In order: the config's VortexGame when it names a
        /// Skyrim that still holds Vortex's record (Fix and the picker in
        /// Settings set it; without the record it is passed over, so a choice
        /// Vortex has since purged cannot pin Thornswood to it); the Steam copy when
        /// Vortex's record is in it, which is the answer this always gave;
        /// another folder in a Steam library that has Vortex's record (Find);
        /// and last the Steam copy anyway, so WhyNot has a folder to name.
        /// </summary>
        public static string DeploysInto(Config cfg)
        {
            // Fix saves VortexGame by itself, so a tester who later points
            // Vortex back at the Steam copy would otherwise leave Thornswood
            // following a folder Vortex has purged, with nothing said and only
            // Forget in Settings as a way out. Found in review, 24 September.
            //
            // Quotes are taken off and nothing here may throw: a path typed
            // into config.json by hand, pasted from Explorer's Copy as path,
            // arrives in quotes, and Path.Combine threw on it out of here and
            // out of the Settings card on the window's thread. Found by the
            // verification of hotfix 1.1.93.
            string s = cfg == null || cfg.VortexGame == null ? "" : cfg.VortexGame.Trim().Trim('"').Trim().TrimEnd('\\');
            bool usable = false;
            try { usable = s.Length > 0 && File.Exists(Path.Combine(s, "SkyrimSE.exe")) && HasRecord(s); }
            catch { usable = false; }
            if (usable)
            {
                Chosen(s, "VortexGame in config.json names it");
                return s;
            }
            string steam = "";
            try { steam = Steam.SkyrimPath(); } catch { /* no Steam copy: "" is the answer, and WhyNot says so */ }
            if (steam.Length > 0 && HasRecord(steam))
            {
                Chosen(steam, "Vortex's record is in the Steam copy");
                return steam;
            }
            string why = null, found = "";
            try { found = Find(out why); }
            catch (Exception ex) { Swallow.Note("OwnGame.DeploysInto, looking through Steam's libraries for Vortex's folder", ex); }
            if (found.Length > 0)
            {
                Chosen(found, why);
                return found;
            }
            return steam;
        }

        /// <summary>
        /// The folder Vortex deploys into when nothing says, or "".
        ///
        /// 24 September, a tester on the main build: "they have purged and
        /// redeoployed several times, they never got a popup to build their
        /// own folder", and the launcher said Vortex had nothing deployed in
        /// S:\SteamLibrary\steamapps\common\Skyrim Special Edition. Their
        /// Vortex, Mods, Open, Open Game Folder opened
        /// S:\SteamLibrary\steamapps\common\Keizaal Online, another SkyMP
        /// server's copy of Skyrim: their Vortex manages that folder and
        /// deploys the Thornswood collection into it, so the Steam copy had
        /// none of the 94 plugins. Vortex's own note of its game folder is in
        /// %APPDATA%\Vortex\state.v2, a LevelDB whose tables are compressed,
        /// and the path is not readable in it as text. So the folder is found
        /// by what Vortex leaves in every folder it deploys to, whatever the
        /// method: Data\vortex.deployment.json.
        ///
        /// Every folder directly under each library's steamapps\common is
        /// looked at, not only Skyrim Special Edition. A Steam copy of Skyrim
        /// Special Edition comes first when more than one has a record, and
        /// otherwise the most recently written record wins.
        /// </summary>
        static string Find(out string why)
        {
            why = null;
            string best = "";
            long bestAt = -1;
            bool bestSteam = false;
            int count = 0;
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (string lib in Steam.Libraries())
            {
                string[] dirs;
                try { dirs = Directory.GetDirectories(Path.Combine(lib, "steamapps\\common")); }
                catch { continue; }
                foreach (string d in dirs)
                {
                    string full;
                    try { full = Path.GetFullPath(d).TrimEnd('\\'); } catch { continue; }
                    if (!seen.Add(full)) continue;
                    if (!File.Exists(Path.Combine(full, "SkyrimSE.exe")) || !HasRecord(full)) continue;
                    count++;
                    bool steam = Steam.IsSkyrimCopy(full);
                    long at = 0;
                    try { at = File.GetLastWriteTimeUtc(Path.Combine(full, "Data\\vortex.deployment.json")).Ticks; } catch { /* unreadable: counts as the oldest record */ }
                    if (best.Length == 0 || (steam && !bestSteam) || (steam == bestSteam && at > bestAt))
                    {
                        best = full;
                        bestAt = at;
                        bestSteam = steam;
                    }
                }
            }
            if (best.Length == 0) return "";
            if (count == 1)
                why = "found in Steam's libraries, the one folder there with Vortex's record in it";
            else if (bestSteam)
                why = "found in Steam's libraries; " + count + " folders there have Vortex's record, and a Steam copy of Skyrim Special Edition comes first";
            else
                why = "found in Steam's libraries; " + count + " folders there have Vortex's record and none is a Steam copy of Skyrim Special Edition, so the newest record wins";
            return best;
        }

        static readonly object chosenLock = new object();
        static string lastChosen;

        /// <summary>Which folder Vortex deploys into and why, into the log once each time the answer changes.</summary>
        static void Chosen(string folder, string why)
        {
            string line = "Vortex deploys into " + folder + ": " + why + ".";
            lock (chosenLock)
            {
                if (line == lastChosen) return;
                lastChosen = line;
            }
            try { File.AppendAllText(Paths.LogFile, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + line + Environment.NewLine); }
            catch { /* the log is only a note of the choice; the choice stands without it */ }
        }

        static bool HasRecord(string dir)
        {
            try { return File.Exists(Path.Combine(dir, "Data\\vortex.deployment.json")); }
            catch { return false; }
        }

        /// <summary>
        /// The Steam copy the game itself comes from when Vortex deploys into
        /// <paramref name="into"/>: that folder when it is a Steam copy of
        /// Skyrim Special Edition, otherwise the first Steam copy and never the
        /// other folder. "" when the machine has no Steam copy.
        /// </summary>
        static string GameFor(string into)
        {
            if (string.IsNullOrEmpty(into)) return "";
            if (Steam.IsSkyrimCopy(into)) return into;
            try { return Steam.SkyrimPath(); } catch { return ""; }
        }

        /// <summary>
        /// For Scan: the folder Vortex deploys into, when it has Vortex's
        /// record and is not the Skyrim this install reads (Paths.Game). That
        /// is when Fix has somewhere to point the launcher. "" otherwise.
        /// </summary>
        public static string DeploysElsewhere(Config cfg)
        {
            string into = DeploysInto(cfg);
            if (into.Length == 0 || !HasRecord(into) || SameFolder(into, Paths.Game)) return "";
            return into;
        }

        /// <summary>
        /// Fix, and the picker in Settings: the launcher takes Vortex's files
        /// from <paramref name="folder"/> from now on, saved as VortexGame.
        /// Only a Skyrim Vortex has deployed into is accepted, which is
        /// SkyrimSE.exe and Vortex's record in Data. "" clears the setting and
        /// the search takes over again. Returns a sentence for the log saying
        /// what it did, or why nothing changed; <paramref name="ok"/> says which.
        /// </summary>
        public static string PointAt(Config cfg, string folder, out bool ok)
        {
            ok = false;
            // Quotes off, for the same reason as in DeploysInto.
            string f = (folder ?? "").Trim().Trim('"').Trim();
            if (f.Length == 0)
            {
                cfg.VortexGame = "";
                cfg.Save(Paths.CfgFile);
                ok = true;
                return "Thornswood no longer has a folder chosen for Vortex, so it looks for the one Vortex deploys into by itself again.";
            }
            try { f = Path.GetFullPath(f).TrimEnd('\\'); }
            catch { return f + " is not a folder Thornswood can read, so nothing changed."; }
            if (!File.Exists(Path.Combine(f, "SkyrimSE.exe")))
                return f + " has no SkyrimSE.exe in it, so it is not a Skyrim folder and nothing changed. Choose the folder that Open Game Folder opens in Vortex.";
            if (!HasRecord(f))
                return "Vortex has not deployed into " + f + ": it has no Data\\vortex.deployment.json, the record Vortex leaves in every folder it deploys to, so nothing changed. Choose the folder that Open Game Folder opens in Vortex.";
            cfg.VortexGame = f;
            cfg.Save(Paths.CfgFile);
            ok = true;
            string game = GameFor(f);
            if (SameFolder(game, f)) return "Thornswood now takes what Vortex deployed from " + f + ".";
            // No Steam copy: saying the game will come from one was untrue on
            // exactly that machine (verification of hotfix 1.1.93). WhyNot
            // refuses to build there; this says so up front.
            if (game.Length == 0)
                return "Thornswood will take what Vortex deployed into " + f + ", but it takes the game itself only from Steam's own copy of Skyrim Special Edition, " +
                       "and this machine has none, so the folder cannot be made until Skyrim Special Edition is installed in Steam.";
            return "Thornswood now takes what Vortex deployed into " + f + " from Vortex's own mods folder, only the files Vortex's record lists, and the game itself from " +
                   "the Steam copy in " + game + ". Nothing else in " + f + " is used.";
        }

        // ------------------------------------------------------------ is it time

        /// <summary>
        /// Null when a folder can be made or refreshed from <paramref name="src"/>
        /// right now, otherwise a sentence saying why not.
        /// </summary>
        public static string WhyNot(Config cfg, string src)
        {
            if (string.IsNullOrEmpty(src) || !File.Exists(Path.Combine(src, "SkyrimSE.exe")))
                return "There is no Skyrim to make it from. Steam does not list one.";
            // The game itself comes from a Steam copy whatever Vortex deploys
            // into (Source). When Vortex deploys into the Steam copy the two are
            // one folder and every check below reads exactly as it always did.
            string game = GameFor(src);
            bool apart = !SameFolder(game, src);
            if (game.Length == 0)
                return "Vortex deploys into " + src + ", but Thornswood takes the game itself only from Steam's own copy of Skyrim Special Edition, " +
                       "never from another folder, and this machine has none, so install Skyrim Special Edition in Steam and try again.";
            // Steam updates the Steam copy by itself. Bringing that build in would
            // put Thornswood on a Skyrim the server does not run, so the Steam
            // copy is put right first and the folder follows it (Downgrade).
            long exeBytes = -1;
            try { exeBytes = new FileInfo(Path.Combine(game, "SkyrimSE.exe")).Length; } catch { /* unreadable: -1, and the build check is skipped as it always was */ }
            if (exeBytes >= 0 && exeBytes != cfg.ExpectedExeBytes)
                return "Skyrim in " + game + " is " + Downgrade.Describe(cfg, Path.Combine(game, "SkyrimSE.exe")) +
                       ", most likely because Steam updated it. Press Downgrade on the Play page first; the folder is brought up to date from it after that.";
            if (SameFolder(src, Folder))
                return "Vortex is set to deploy into Thornswood's own folder, which would make it out of itself.";
            if (!HasRecord(src))
                return "Vortex has nothing deployed in " + src + " right now. In Vortex, enable the Thornswood profile and let it deploy, then try again. " +
                       "If it is deployed, Vortex is deploying into another folder: in Vortex, Mods, Open, Open Game Folder shows which, " +
                       "and Choose Vortex's folder in Settings points Thornswood at it.";

            List<string> want = ShippedPlugins();
            if (want.Count == 0)
                return "This install has no reference plugin list yet, so there is no telling whether Vortex has Thornswood's collection on. Let the launcher update first.";
            Record rec = apart ? Staged(src) : null;
            HashSet<string> stale = null;
            int missing = 0, unstaged = 0;
            foreach (string p in want)
            {
                try
                {
                    // Apart, a plugin counts only where Gather will take it
                    // from: Vortex's mods folder by its record, or the Steam
                    // copy's own game. One the record lists whose copy in
                    // Vortex's mods folder is gone is counted apart: the
                    // Thornswood profile is deployed, the deployment is just
                    // out of date (verification of hotfix 1.1.93).
                    string from;
                    if (!apart) { if (!File.Exists(Path.Combine(src, "Data", p))) missing++; }
                    else if (!(rec.From.TryGetValue("Data\\" + p, out from) && File.Exists(from)))
                    {
                        if (stale == null) stale = Deployed(game);
                        if (!File.Exists(Path.Combine(game, "Data", p)) || stale.Contains("Data\\" + p))
                        {
                            if (from != null) unstaged++; else missing++;
                        }
                    }
                }
                catch { missing++; }
            }
            if (missing == 0 && unstaged > 0)
                return unstaged + " of Thornswood's " + want.Count + " plugins are in Vortex's record for " + src +
                       " but no longer in Vortex's own mods folder, so that deployment is out of date. In Vortex, press Deploy Mods, then try again.";
            // Not only another profile: Vortex may be deploying Thornswood into
            // a different folder while an old record sits here, which is the
            // one case the search cannot see past. The picker is the way out.
            if (missing + unstaged > 0)
                return (missing + unstaged) + " of Thornswood's " + want.Count + " plugins are not in " + src +
                       ", so Vortex has another profile deployed, or deploys Thornswood into another folder. In Vortex, enable the Thornswood profile and let it deploy. " +
                       "If it is deployed, Mods, Open, Open Game Folder in Vortex shows where, and Choose Vortex's folder in Settings points Thornswood at it.";

            // Two drives, which is where this used to stop. Both of these said
            // "Thornswood has to be installed on the same drive as Skyrim for
            // this" and ended there: a rule, with nothing to press and nothing
            // to do. Since Play began refusing a shared Skyrim
            // (Shell.OwnGameRequired) that sentence was the whole game for
            // anybody who keeps Steam on a second drive, and plenty of people
            // do. It is still a refusal, because a hard link cannot cross a
            // volume, but OneDriveOnly names both ways out and the paths.
            if (!SameVolume(game, Paths.Root))
                return OneDriveOnly("Skyrim is in " + game, Volume(game),
                    "move Skyrim to " + Volume(Paths.Root) + ", in Steam, Settings, Storage: choose " + Volume(game) +
                    " at the top, tick Skyrim Special Edition, press Move and pick " + Volume(Paths.Root));
            if (apart)
            {
                foreach (string dir in rec.Staging)
                    if (!SameVolume(dir, Paths.Root))
                        return OneDriveOnly("Vortex keeps its mods in " + dir, Volume(dir),
                            "move Vortex's mods to " + Volume(Paths.Root) + ", in Vortex, Settings, Mods: set the mod staging folder to one on " +
                            Volume(Paths.Root) + " and let Vortex move what is there");
            }
            return null;
        }


        /// <summary>True when Vortex has deployed since the folder was last made or refreshed.</summary>
        /// <summary>
        /// Which build of the rules in this file a folder was made under.
        ///
        /// Bump this whenever Foreign, MustCopy or anything else that decides
        /// what goes in the folder changes. Every folder made under an older
        /// number then refreshes itself the next time the launcher opens.
        ///
        /// 1: NirnLabUIPlatform is another server's and is left out. Before
        ///    this the folder was given it, SkyrimPlatform would not start on
        ///    the browser we ship while it was there, and CEFSubprocess.exe
        ///    came with it for Windows Firewall to ask about.
        /// 2: Creation Club plugins the reference list does not name are left
        ///    out, and taken out of a folder that already has them. See
        ///    UnwantedCreation.
        /// 3: Data\SkyrimTogetherReborn is another server's and is left out,
        ///    all of it rather than the two subfolders Ship-Rules named.
        /// 4: the retired dresser, thornswood-chargen.js, is left out, so a
        ///    refresh cannot copy the Steam copy's old one back in after a
        ///    pack deletes it. See Foreign.
        /// 5: what Nemesis or FNIS writes (behavior files, the two character
        ///    defaults, FNIS.pex) is copied, never linked, and a folder that
        ///    already has them as links gets its own copy of each, as they are
        ///    now. Folders parked at the game's root or in Data (a name that
        ///    starts with an underscore, such as _Parked or _disabledByKzl) are
        ///    left out, and taken out of a folder that already has them. See
        ///    Generated and Parked.
        /// 6: Vortex's Data\Platform\Distribution redistributables (the 68 CEF
        ///    and Node files the collection carries, not the two recorded in
        ///    records\client-build.json) are hard linked, even though they are
        ///    .dll/.exe. A folder that still holds its own copy of each gets
        ///    the link instead, giving the disk the second copy back. See
        ///    MustCopy.
        /// </summary>
        const int Rules = 6;

        public static bool NeedsRefresh(Config cfg)
        {
            if (!Active) return false;
            string src = DeploysInto(cfg);
            if (WhyNot(cfg, src) != null) return false;

            // The rules changed under a folder that was already made.
            //
            // This used to ask one question: has Vortex deployed since. That
            // misses the case where Vortex has not moved at all and it is this
            // launcher that now wants something different from the same
            // deployment. A folder built before a rule existed keeps whatever
            // that rule was added to take out, for as long as Vortex sits
            // still, which on a settled collection is forever. The person has
            // no way to know: nothing on screen says their folder is built to
            // rules nobody uses any more.
            //
            // A folder with no number in its record was made before any of
            // this and reads as -1, so it refreshes once and then matches.
            if (Recorded("rules") != Rules) return true;

            return DeploymentStamp(src) != Recorded("deployment");
        }

        // ------------------------------------------------------------ making it

        class Found
        {
            public string Rel;
            // Where it is brought from: the file itself in a walked folder, or
            // Vortex's staging copy of it (Gather).
            public string From;
            public long Size, Ticks;
        }

        class Rec
        {
            public char Kind, Origin;
            public long Size, Ticks;
        }

        /// <summary>
        /// Makes Root\Game. Runs on a pool thread; <paramref name="say"/> is
        /// called from it. Returns a line for the log, or throws with a sentence
        /// worth showing.
        /// </summary>
        public static string Make(Config cfg, Action<string> say)
        {
            string src = DeploysInto(cfg);
            string why = WhyNot(cfg, src);
            if (why != null) throw new Exception(why);
            if (Directory.Exists(Folder))
                throw new Exception("There is already a Game folder at " + Folder + ", so nothing was made.");

            // A half made one from an attempt that stopped part way. Only ever
            // this launcher's, and only ever links and copies.
            string temp = Folder + ".new";
            if (Directory.Exists(temp)) Directory.Delete(temp, true);
            Directory.CreateDirectory(Dir);

            HashSet<string> deployed = Deployed(src);
            wantedPlugins = new HashSet<string>(ShippedPlugins(), StringComparer.OrdinalIgnoreCase);
            var left = new List<string>();
            List<Found> all = Gather(src, left);

            long copyBytes = 0, totalBytes = 0;
            foreach (Found f in all)
            {
                if (Skip(f.Rel) != null) continue;
                totalBytes += f.Size;
                if (MustCopy(f.Rel, deployed)) copyBytes += f.Size;
            }
            long free = FreeSpace(Paths.Root);
            if (free >= 0 && free < copyBytes + 512L * 1024 * 1024)
                throw new Exception("There is not enough room on " + Volume(Paths.Root) + ". The copied part needs " +
                                    Mb(copyBytes) + " and " + Mb(free) + " is free.");

            var lines = new List<string>();
            int linked = 0, copied = 0, fellBack = 0;
            long done = 0; int shown = 0;
            foreach (Found f in all)
            {
                string skip = Skip(f.Rel);
                if (skip != null) { left.Add(f.Rel + "  (" + skip + ")"); continue; }

                bool copy = MustCopy(f.Rel, deployed);
                bool asLink;
                try
                {
                    Place(f.From, Path.Combine(temp, f.Rel), copy, out asLink);
                }
                catch (Exception ex)
                {
                    left.Add(f.Rel + "  (could not be brought over: " + ex.Message + ")");
                    continue;
                }
                if (asLink) linked++; else { copied++; if (!copy) fellBack++; }
                lines.Add((asLink ? "L" : "C") + "|" + (deployed.Contains(f.Rel) ? "V" : "O") + "|" + f.Size + "|" + f.Ticks + "|" + f.Rel);

                done += f.Size;
                int pct = totalBytes > 0 ? (int)(done * 100 / totalBytes) : 100;
                if (say != null && pct >= shown + 10) { shown = pct - pct % 10; say("Making Thornswood's own Skyrim folder: " + shown + "%"); }
            }

            File.WriteAllLines(FilesList, lines.ToArray());
            File.WriteAllLines(LeftOutFile, left.ToArray());
            Directory.Move(temp, Folder);
            WriteMade(src, SumCopied(lines));
            SettleSettings(true);

            string said = "Thornswood's own Skyrim folder is ready at " + Folder + ": " +
                          linked.ToString("n0") + " files linked, " + copied.ToString("n0") + " copied (" + Mb(copyBytes) + ")";
            if (fellBack > 0) said += ", " + fellBack.ToString("n0") + " of them copied because a link could not be made";
            said += ". " + left.Count.ToString("n0") + " left out, other servers' files among them; the list is in " + LeftOutFile + ".";
            return said;
        }

        /// <summary>
        /// Brings Root\Game up to date with what Vortex has deployed now. New and
        /// changed files come in, files the collection no longer has go, and
        /// anything a Thornswood update wrote into the folder stays as that
        /// update left it. Returns a line for the log, or throws.
        /// </summary>
        public static string Refresh(Config cfg, Action<string> say)
        {
            if (!Active) throw new Exception("This install is not running from a folder of its own.");
            string src = DeploysInto(cfg);

            // Same deployment stamp and same rules as the last refresh: nothing
            // to bring in. Skip WhyNot, Gather, the per-file Links walk, and
            // SettleSettings. SettleSettings used to copy Golden plugins.txt
            // over Paths.Live on every refresh, which put Thornswood-Content.esp
            // (and the rest) back out of the server's order and left Mod list
            // red after "already matches". ShellOwnGame applies PutInServerOrder
            // after this returns; when nothing changed that write is a no-op.
            if (!string.IsNullOrEmpty(src)
                && Recorded("rules") == Rules
                && DeploymentStamp(src) == Recorded("deployment")
                && Recorded("deployment") != 0)
                return "Thornswood's own Skyrim folder already matches what Vortex has deployed.";

            string why = WhyNot(cfg, src);
            if (why != null) throw new Exception(why);

            Dictionary<string, Rec> old = ReadFiles();
            HashSet<string> deployed = Deployed(src);
            HashSet<string> owned = Owned(deployed);
            wantedPlugins = new HashSet<string>(ShippedPlugins(), StringComparer.OrdinalIgnoreCase);
            var left = new List<string>();
            List<Found> all = Gather(src, left);

            var lines = new List<string>();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            int added = 0, changed = 0, removed = 0, kept = 0, separated = 0, relinked = 0;
            long copyBytes = 0;

            foreach (Found f in all)
            {
                string skip = Skip(f.Rel);
                if (skip != null) { left.Add(f.Rel + "  (" + skip + ")"); continue; }
                seen.Add(f.Rel);

                string dest = Path.Combine(Folder, f.Rel);
                char origin = deployed.Contains(f.Rel) ? 'V' : 'O';
                bool exists = File.Exists(dest);
                Rec r;
                bool had = old.TryGetValue(f.Rel, out r);

                if (exists && (owned.Contains(f.Rel) || (had && r.Size == f.Size && r.Ticks == f.Ticks)))
                {
                    // Unchanged in Vortex, or Thornswood's own update wrote it.
                    // Recorded against what the source holds now either way.
                    char kind = had ? r.Kind : 'C';
                    // Rules 5: a generated file this folder still shares with
                    // the Steam copy gets a copy of its own, as it is now.
                    // Rules 6: a Distribution redistributable this folder still
                    // holds as its own copy becomes a hard link to Vortex's.
                    // Only Distribution: a broader !MustCopy re-link also
                    // undid Fix's light-flag Separates on plugins such as
                    // CBBE.esp (copy, ESL set, then Bring it up to date from
                    // Vortex replaced it with Vortex's unflagged staging).
                    try
                    {
                        if (MustCopy(f.Rel, deployed) && Links(dest) > 1)
                        {
                            Separate(dest);
                            if (Links(dest) <= 1) { kind = 'C'; separated++; }
                        }
                        else if (!MustCopy(f.Rel, deployed) && origin == 'V' && Links(dest) <= 1
                                 && f.Rel.StartsWith("Data\\Platform\\Distribution\\", StringComparison.OrdinalIgnoreCase))
                        {
                            bool nowLink;
                            DropName(dest);
                            Place(f.From, dest, false, out nowLink);
                            if (nowLink) { kind = 'L'; relinked++; }
                            else kind = 'C';
                        }
                    }
                    catch { /* unreadable right now: left as it was */ }
                    lines.Add(kind + "|" + origin + "|" + f.Size + "|" + f.Ticks + "|" + f.Rel);
                    kept++;
                    continue;
                }

                bool copy = MustCopy(f.Rel, deployed);
                bool asLink;
                try
                {
                    // Deleting the name here removes this folder's link and
                    // nothing else. The file Vortex has stays where it is.
                    if (exists) DropName(dest);
                    Place(f.From, dest, copy, out asLink);
                }
                catch (Exception ex)
                {
                    left.Add(f.Rel + "  (could not be brought over: " + ex.Message + ")");
                    if (exists && had) lines.Add(r.Kind + "|" + r.Origin + "|" + r.Size + "|" + r.Ticks + "|" + f.Rel);
                    continue;
                }
                if (!asLink) copyBytes += f.Size;
                lines.Add((asLink ? "L" : "C") + "|" + origin + "|" + f.Size + "|" + f.Ticks + "|" + f.Rel);
                if (exists) changed++; else added++;
            }

            // The collection dropped these. Only Vortex's files are taken out;
            // anything else in the folder is not this refresh's to judge.
            //
            // Except a Creation Club plugin this folder brought in itself before
            // rules 2. Those were never Vortex's, so without this a folder that
            // already had them would keep them for good and keep showing LOAD
            // ORDER ERROR, which is the thing rules 2 is for.
            foreach (KeyValuePair<string, Rec> kv in old)
            {
                if (seen.Contains(kv.Key) || owned.Contains(kv.Key)) continue;
                if (kv.Value.Origin != 'V' && !UnwantedCreation(kv.Key) && !Parked(kv.Key)) continue;
                try
                {
                    string dest = Path.Combine(Folder, kv.Key);
                    if (File.Exists(dest)) { DropName(dest); removed++; }
                }
                catch { }
            }

            File.WriteAllLines(FilesList, lines.ToArray());
            File.WriteAllLines(LeftOutFile, left.ToArray());
            WriteMade(src, SumCopied(lines));
            SettleSettings(false);

            string own = "";
            if (separated > 0) own += " " + separated.ToString("n0") + " animation file(s) it shared with the Steam copy are its own copies now.";
            if (relinked > 0) own += " " + relinked.ToString("n0") + " Distribution redistributable(s) it held as its own copies are hard links now.";
            if (added + changed + removed == 0)
                return "Thornswood's own Skyrim folder already matches what Vortex has deployed." + own;
            return "Thornswood's own Skyrim folder is up to date with Vortex: " + added.ToString("n0") + " new, " +
                   changed.ToString("n0") + " changed, " + removed.ToString("n0") + " taken out" +
                   (copyBytes > 0 ? ", " + Mb(copyBytes) + " copied" : "") + "." + own;
        }

        /// <summary>
        /// Puts collection plugins the golden list expects but Game\Data does not
        /// have back into Data, from what Vortex has deployed (or its staging).
        /// Does not remove anything from plugins.txt: Gavin's Diagnostics case
        /// (CFTO-Lanterns, CFTO-CoveredCarriages, BeardMaskFix and the like) is
        /// light plugins the person wants kept on, and the server never serves
        /// light plugins, so Fix cannot fetch them. Refreshing the own folder,
        /// or linking/copying each missing file from Vortex, is how Fix clears
        /// "in the list but the file is not in Data". Returns how many were
        /// restored. Works for Main (C:\Thornswood) and DevBuild the same way,
        /// because Paths.Game and DeploysInto already follow this install.
        /// </summary>
        public static int RestoreMissingPlugins(Config cfg, Action<string> say)
        {
            if (say == null) say = delegate(string m) { };

            List<string> want = ShippedPlugins();
            if (want.Count == 0) return 0;

            string data = Path.Combine(Paths.Game, "Data");
            var missing = new List<string>();
            foreach (string p in want)
            {
                try
                {
                    if (!File.Exists(Path.Combine(data, p))) missing.Add(p);
                }
                catch (Exception ex)
                {
                    Swallow.Note("OwnGame.RestoreMissingPlugins, asking whether " + p + " is in Data", ex);
                    missing.Add(p);
                }
            }
            if (missing.Count == 0) return 0;

            // Own folder: Refresh brings every missing plugin from Vortex and
            // keeps files.txt honest. Targeted Place alone would leave the
            // record short and the next NeedsRefresh confused.
            if (Active)
            {
                string srcOwn = "";
                try { srcOwn = DeploysInto(cfg); }
                catch (Exception ex) { Swallow.Note("OwnGame.RestoreMissingPlugins, asking which folder Vortex deploys into", ex); }
                string why = null;
                if (srcOwn.Length > 0)
                {
                    try { why = WhyNot(cfg, srcOwn); }
                    catch (Exception ex)
                    {
                        Swallow.Note("OwnGame.RestoreMissingPlugins, asking whether the own folder can refresh", ex);
                        why = ex.Message;
                    }
                }
                else why = "Vortex has no folder Thornswood can refresh from.";

                if (why == null)
                {
                    try
                    {
                        say(Refresh(cfg, say));
                        int got = 0;
                        foreach (string p in missing)
                        {
                            try { if (File.Exists(Path.Combine(data, p))) got++; }
                            catch (Exception ex) { Swallow.Note("OwnGame.RestoreMissingPlugins, checking " + p + " after refresh", ex); }
                        }
                        if (got < missing.Count)
                            say((missing.Count - got) + " plugin" + (missing.Count - got == 1 ? "" : "s") +
                                " still missing from Data after refresh. In Vortex, enable the Thornswood profile and press Deploy.");
                        return got;
                    }
                    catch (Exception ex)
                    {
                        Swallow.Note("OwnGame.RestoreMissingPlugins, refreshing the own folder", ex);
                        say("Could not refresh Thornswood's own folder (" + ex.Message.TrimEnd('.') + "). Trying Vortex's files one by one.");
                    }
                }
                else
                {
                    say("Could not refresh Thornswood's own folder: " + why + " Trying Vortex's files one by one.");
                }
            }

            string src = "";
            try { src = DeploysInto(cfg); }
            catch (Exception ex) { Swallow.Note("OwnGame.RestoreMissingPlugins, asking which folder Vortex deploys into for a one-by-one restore", ex); }
            if (string.IsNullOrEmpty(src))
            {
                say("Fix could not find Vortex's deploy folder, so the missing plugins were not put back. In Vortex, Mods, Open, Open Game Folder shows which folder it uses.");
                return 0;
            }

            string game = GameFor(src);
            bool apart = game.Length > 0 && !SameFolder(game, src);
            Record rec = null;
            if (apart)
            {
                try { rec = Staged(src); }
                catch (Exception ex)
                {
                    Swallow.Note("OwnGame.RestoreMissingPlugins, reading Vortex's staging records", ex);
                    say("Vortex's staging record for " + src + " could not be read (" + ex.Message.TrimEnd('.') + ").");
                }
            }

            HashSet<string> deployed = null;
            try { deployed = Deployed(src); }
            catch (Exception ex)
            {
                Swallow.Note("OwnGame.RestoreMissingPlugins, reading what Vortex deployed", ex);
                deployed = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            }

            int n = 0;
            foreach (string p in missing)
            {
                try { if (File.Exists(Path.Combine(data, p))) continue; }
                catch (Exception ex) { Swallow.Note("OwnGame.RestoreMissingPlugins, re-checking " + p + " before place", ex); }

                string rel = "Data\\" + p;
                string from = null;
                if (rec != null)
                {
                    string staged;
                    if (rec.From.TryGetValue(rel, out staged) && !string.IsNullOrEmpty(staged) && File.Exists(staged))
                        from = staged;
                }
                if (from == null)
                {
                    string direct = Path.Combine(src, "Data", p);
                    try { if (File.Exists(direct)) from = direct; }
                    catch (Exception ex) { Swallow.Note("OwnGame.RestoreMissingPlugins, looking for " + p + " under Vortex's deploy folder", ex); }
                }
                if (from == null && game.Length > 0 && apart)
                {
                    string steamCopy = Path.Combine(game, "Data", p);
                    try
                    {
                        if (File.Exists(steamCopy) && (deployed == null || !deployed.Contains(rel)))
                            from = steamCopy;
                    }
                    catch (Exception ex) { Swallow.Note("OwnGame.RestoreMissingPlugins, looking for " + p + " under the Steam copy", ex); }
                }
                if (from == null)
                {
                    say(p + " is still missing: Vortex does not have a copy to put back. In Vortex, enable the Thornswood profile and press Deploy.");
                    continue;
                }

                string dest = Path.Combine(data, p);
                try
                {
                    bool copy = MustCopy(rel, deployed);
                    bool linked;
                    if (File.Exists(dest)) DropName(dest);
                    Place(from, dest, copy, out linked);
                    say(p + " was put back into Data from Vortex" + (linked ? " (linked)." : "."));
                    n++;
                }
                catch (Exception ex)
                {
                    Swallow.Note("OwnGame.RestoreMissingPlugins, placing " + p, ex);
                    say(p + " could not be put back (" + ex.Message.TrimEnd('.') + "). Close Skyrim and Vortex and press Fix again.");
                }
            }
            return n;
        }

        /// <summary>
        /// Settings that live outside the game folder. Under the collection the
        /// launcher left Windows' own Skyrim folders alone; from here on it points
        /// them at Profile for each session (Swap), so those need something in
        /// them first.
        /// </summary>
        static void SettleSettings(bool first)
        {
            // Seed the plugin list where Skyrim will read it. On Make (first),
            // always lay Golden down. On Refresh, only fill a missing file:
            // overwriting Live every time put Golden's order (Thornswood-Content
            // near the end) over a Fix/PutInServerOrder list and Mod list went
            // red after Bring it up to date said the folder already matched.
            try
            {
                Directory.CreateDirectory(Paths.LocalAD);
                foreach (string n in new string[] { "plugins.txt", "loadorder.txt" })
                {
                    string shipped = Path.Combine(Paths.Golden, n);
                    string dest = Path.Combine(Paths.LocalAD, n);
                    if (!File.Exists(shipped)) continue;
                    if (first || !File.Exists(dest)) File.Copy(shipped, dest, true);
                }
            }
            catch { }

            // Vortex's Thornswood profile list, for Publish-Update on a machine
            // that ships (#557). Windows' live plugins.txt follows whichever
            // Vortex profile is active; the named Thornswood profile is the
            // collection's order. Nothing here writes to Vortex.
            try
            {
                string tw = Checks.VortexProfileDir("Thornswood");
                string livePlugins = Path.Combine(Paths.WinLocalAD, "plugins.txt");
                if (tw == null)
                {
                    try { File.AppendAllText(Paths.LogFile, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  OwnGame: Vortex profile Thornswood was not found; leaving Profile\\OwnGame plugin list alone rather than copying Windows' live list from another profile." + Environment.NewLine); } catch { /* the log is only a note; leaving OwnGame alone stands without it */ }
                }
                else
                {
                    Directory.CreateDirectory(Dir);
                    foreach (string n in new string[] { "plugins.txt", "loadorder.txt" })
                    {
                        string from = Path.Combine(tw, n);
                        if (File.Exists(from)) File.Copy(from, Path.Combine(Dir, n), true);
                    }
                    string twPlugins = Path.Combine(tw, "plugins.txt");
                    if (File.Exists(livePlugins) && File.Exists(twPlugins) && !Junction.IsLink(Paths.WinLocalAD))
                    {
                        string a = File.ReadAllText(livePlugins);
                        string b = File.ReadAllText(twPlugins);
                        if (!string.Equals(a, b, StringComparison.Ordinal))
                            try { File.AppendAllText(Paths.LogFile, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  OwnGame: Windows' live plugins.txt differs from the Thornswood Vortex profile at " + tw + "; baked OwnGame from Thornswood." + Environment.NewLine); } catch { /* the log is only a note; the bake stands without it */ }
                    }
                }
            }
            catch (Exception ex) { try { File.AppendAllText(Paths.LogFile, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  OwnGame: baking Thornswood profile list failed: " + ex.Message + Environment.NewLine); } catch { /* the log itself failed; nowhere left to say so */ } }

            if (!first) return;

            // Skyrim's own ini files, so the first session is not on defaults.
            try
            {
                Directory.CreateDirectory(Paths.MyGames);
                foreach (string n in new string[] { "Skyrim.ini", "SkyrimPrefs.ini", "SkyrimCustom.ini" })
                {
                    string from = Path.Combine(Paths.WinMyGames, n);
                    string to = Path.Combine(Paths.MyGames, n);
                    if (File.Exists(from) && !File.Exists(to)) File.Copy(from, to, false);
                }
            }
            catch { }

            // Under the collection a character's saves were linked into Windows'
            // own save folder, and the link stayed there between sessions, so
            // every other server's game saved into a Thornswood character.
            // Taking the link off leaves the saves where they really are.
            try
            {
                string saves = Path.Combine(Paths.WinMyGames, "Saves");
                if (Junction.IsLink(saves) && !Junction.IsLink(Paths.WinMyGames))
                {
                    Directory.Delete(saves);
                    Directory.CreateDirectory(saves);
                }
            }
            catch { }
        }

        // ------------------------------------------------------------ writes

        /// <summary>
        /// Before a write that replaces a whole file: in a folder made of links
        /// the name comes off first, so the new file belongs to this folder
        /// alone. Nothing happens under the collection, where the Steam copy is
        /// Vortex's and its links are left as Vortex made them.
        /// </summary>
        public static void Unshare(string path)
        {
            if (Paths.Collection) return;
            try
            {
                if (File.Exists(path) && Links(path) > 1) File.Delete(path);
            }
            catch { }
        }

        /// <summary>
        /// Before a write into part of a file, which has to keep the rest of it:
        /// this folder gets a copy of its own first. Same rule as Unshare about
        /// the collection.
        /// </summary>
        public static void Separate(string path)
        {
            if (Paths.Collection) return;
            try
            {
                if (!File.Exists(path) || Links(path) <= 1) return;
                string own = path + ".own";
                File.Copy(path, own, true);
                File.Delete(path);
                File.Move(own, path);
            }
            catch { }
        }

        /// <summary>
        /// Takes one name off a file. Attributes belong to the file rather than
        /// the name, so read only is only cleared when the delete is refused,
        /// and then on a file this folder is letting go of anyway.
        /// </summary>
        public static void DropName(string path)
        {
            try { File.Delete(path); }
            catch (UnauthorizedAccessException)
            {
                File.SetAttributes(path, FileAttributes.Normal);
                File.Delete(path);
            }
        }

        /// <summary>
        /// Break a hard link before a write that replaces the whole file.
        ///
        /// Unshare above deliberately leaves the collection layout alone,
        /// because there the game IS the Steam copy and nearly everything in
        /// it belongs to Vortex. That is the right rule for a file this build
        /// only touches. It is the wrong rule for a plugin that Fix is
        /// replacing outright.
        ///
        /// Vortex deploys by hard link, so the plugin in the Steam copy and
        /// the Nexus mod inside Vortex's staging folder are one file with two
        /// names, and staging is shared by every Skyrim profile on the machine.
        /// Writing through that link puts this build's copy of a plugin inside
        /// another server's collection, where nothing says it came from here
        /// and nobody would think to look. Somebody who plays Thornswood and
        /// one other SkyMP server gets turned away by the other one, and the
        /// only trace is a checksum that stopped matching.
        ///
        /// So this one always breaks the link, whatever the layout. The cost is
        /// that Vortex's staging keeps the bytes it had, so a later Vortex
        /// deploy can put them back here. Scan sees that the moment it runs and
        /// Fix puts it right again, which is a loop somebody can see and get
        /// out of. The other way round is silent and lands on somebody else.
        /// </summary>
        public static void Detach(string path)
        {
            try
            {
                if (File.Exists(path) && Links(path) > 1) File.Delete(path);
            }
            catch { }
        }

        static int Links(string path)
        {
            using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            {
                FileInfoByHandle info;
                if (!GetFileInformationByHandle(fs.SafeFileHandle, out info)) return 1;
                return (int)info.NumberOfLinks;
            }
        }

        // ------------------------------------------------------------ what goes

        /// <summary>
        /// Null when the file belongs in Thornswood's folder, otherwise why not.
        /// </summary>
        static string Skip(string rel)
        {
            string leaf = Path.GetFileName(rel);
            if (leaf.StartsWith("vortex.deployment", StringComparison.OrdinalIgnoreCase)) return "Vortex's record of the Steam copy";
            if (leaf.Equals("__folder_managed_by_vortex", StringComparison.OrdinalIgnoreCase)) return "Vortex's marker";
            if (leaf.EndsWith(".vortex_backup", StringComparison.OrdinalIgnoreCase)) return "Vortex's backup";
            if (leaf.IndexOf(Checks.OffSuffix, StringComparison.OrdinalIgnoreCase) >= 0) return "moved aside earlier";
            if (leaf.EndsWith(".log", StringComparison.OrdinalIgnoreCase) || leaf.EndsWith(".pdb", StringComparison.OrdinalIgnoreCase)) return "log";
            if (Regex.IsMatch(rel, @"(^|\\)Claude outputs\\", RegexOptions.IgnoreCase)) return "not part of the game";
            if (rel.StartsWith("_to_delete\\", StringComparison.OrdinalIgnoreCase)) return "not part of the game";
            if (Parked(rel)) return "a folder something parked in the Steam copy, not part of the game";
            if (rel.StartsWith(".sentry-native\\", StringComparison.OrdinalIgnoreCase)) return "crash reporter scratch";
            if (rel.Equals("Data\\Platform\\thornswood-session.txt", StringComparison.OrdinalIgnoreCase)) return "session note";
            if (ClientFile(rel)) return "the client runtime comes from the build, not the Steam copy";
            if (Foreign(rel)) return "not one of ours";
            if (UnwantedCreation(rel)) return "a Creation Club plugin the server does not load";
            if (CrashesUs(rel)) return "it crashes the quick favourites menu";
            return null;
        }

        /// <summary>
        /// Deployed by Vortex, deliberately kept out of Thornswood's folder.
        /// </summary>
        /// <remarks>
        /// Not clutter and not another server's. Somebody chose this mod, so it
        /// gets a reason and a date and comes back the day the reason goes.
        ///
        /// Inventory Interface Information Injector (InventoryInjector.dll,
        /// v1.1.1, its last release, 2023). Choose a favourite, press Q again,
        /// the game is gone. Seven crash logs across 18 and 19 Sep are the same
        /// crash down to the address: EXCEPTION_ACCESS_VIOLATION executing
        /// 0x656D6167, which is the four characters "game" being called as code.
        /// The return address on the stack is InventoryInjector.dll+0x3AA85 and
        /// R13 holds its own Hooks::IconSetter::ProcessListFunc, with
        /// FavoritesMenu and MagicFavorites beside them; the 21:51 log even has
        /// the source path and "Running IconSetter.processList hook" on the
        /// stack. It calls through a freed pointer while building that list.
        ///
        /// What frees it is this server. SkyMP rebuilds the character's
        /// inventory from the server's copy after an equip, and the Papyrus VM
        /// in every one of those logs has a TESModPlatform.Add queued at the
        /// moment of the fault.
        ///
        /// Taken out rather than worked around: it is the code that faults, it
        /// is not built here, and no other script extender plugin names it, so
        /// nothing else in the build depends on it. What goes with it is the
        /// icons its JSON files put on inventory rows. I4IconAddon.esp stays
        /// loaded and inert, so no plugin is enabled or disabled and the load
        /// order does not move.
        ///
        /// Djinn, 19 Sep. This is the launcher's own folder build, which is what
        /// makes Thornswood\Game. New-GameFolder.ps1 is the same job for
        /// another server and Daedric and is not where this belongs: their folders are
        /// their business.
        /// </remarks>
        static bool CrashesUs(string rel)
        {
            if (rel.Equals("Data\\SKSE\\Plugins\\InventoryInjector.dll", StringComparison.OrdinalIgnoreCase)) return true;
            if (rel.StartsWith("Data\\SKSE\\Plugins\\InventoryInjector\\", StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }

        /// <summary>
        /// The plugins switched on in the reference list, set at the start of
        /// Make and Refresh.
        /// </summary>
        static HashSet<string> wantedPlugins = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        /// <summary>
        /// A Creation Club plugin in Data that the reference list does not name.
        ///
        /// Skyrim.ccc lists the Creation Club's plugins, and the game loads any of
        /// them it finds in Data straight after the five masters, whatever
        /// plugins.txt says. Steam installs four with the game since the 1.6
        /// updates (Fish and AdvDSGS are full masters, Curios and SurvivalMode
        /// are light), and the server's list has none of them. So a folder that is
        /// given them loads two masters the server does not have, and every
        /// plugin after Dragonborn.esm sits two places off: LOAD ORDER ERROR.
        ///
        /// Measured on 19 Sep. Something else had moved them out of the Steam
        /// copy's Data and something else again had put them back, and the
        /// next refresh brought them in here. The game loaded 62 full plugins
        /// against the server's 60 while the scan said everything checks out. The archives stay, because nothing loads
        /// an archive without its plugin. Packs never carry any of these either:
        /// Publish-Update.ps1 counts cc*.es? as vanilla.
        /// </summary>
        static bool UnwantedCreation(string rel)
        {
            if (!Regex.IsMatch(rel, @"^Data\\cc[^\\]*\.(esm|esl|esp)$", RegexOptions.IgnoreCase)) return false;
            return !wantedPlugins.Contains(rel.Substring("Data\\".Length));
        }

        /// <summary>
        /// The SkyMP client runtime Thornswood ships: the six files the fork
        /// builds that differ from upstream, put into the game folder by
        /// tools\Sync-Client.ps1 against tools\client-build.json. They are
        /// never taken from the Steam copy, because until 20 September the Steam
        /// copy held another server's launcher's builds of every one of them
        /// and this class copied them across on every rebuild.
        /// </summary>
        public static readonly string[] ClientFiles = {
            "Data\\SKSE\\Plugins\\MpClientPlugin.dll",
            "Data\\SKSE\\Plugins\\SkyrimPlatform.dll",
            "Data\\Platform\\Distribution\\RuntimeDependencies\\SkyrimPlatformImpl.dll",
            "Data\\Platform\\Distribution\\RuntimeDependencies\\SkyrimPlatformCEF.exe.hidden",
            "Data\\Platform\\Plugins\\skymp5-client.js",
            "Data\\Scripts\\TESModPlatform.pex",
        };

        public static bool ClientFile(string rel)
        {
            foreach (string c in ClientFiles)
                if (rel.Equals(c, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }

        /// <summary>
        /// Not one of ours, by what belongs rather than by whose it is. The
        /// same shape as Test-ShipOtherServer in tools\Ship-Rules.ps1; change
        /// both together. Nothing here names another server: the list is what
        /// Thornswood's folder holds, and anything else in these places is
        /// left out whoever wrote it.
        /// </summary>
        public static bool Foreign(string rel)
        {
            const RegexOptions I = RegexOptions.IgnoreCase;
            string leaf = Path.GetFileName(rel);
            // NirnLab UI Platform, another server's interface framework, and
            // the one thing this folder must not be handed.
            //
            // SkyrimPlatform will not start on its own browser while NirnLab is
            // in the folder. NirnLab puts its directory on the process PATH, its
            // libcef.dll is loaded instead of the one in
            // Data\Platform\Distribution, and SkyrimPlatform stops with "Your PATH
            // environment variable contains incompatible entries" before the game
            // draws anything. Measured on 17 Sep in a folder this class built.
            //
            // It is also what brings CEFSubprocess.exe, which is the second
            // program Windows Firewall stops the game to ask about.
            if (rel.StartsWith("Data\\NirnLabUIPlatform\\", StringComparison.OrdinalIgnoreCase)) return true;
            if (leaf.Equals("NirnLabUIPlugin.dll", StringComparison.OrdinalIgnoreCase)) return true;
            // Skyrim Together Reborn's folder. Nothing here supports another
            // server's install, so its files are not taken into ours either.
            // Ship-Rules.ps1 carries the same rule; change the two together.
            if (rel.StartsWith("Data\\SkyrimTogetherReborn\\", StringComparison.OrdinalIgnoreCase)) return true;
            if (rel.Equals("Data\\SkyrimTogetherReborn", StringComparison.OrdinalIgnoreCase)) return true;
            // The client's per machine sign in data. It holds an access token.
            if (rel.StartsWith("Data\\Platform\\PluginsNoLoad\\", StringComparison.OrdinalIgnoreCase)) return true;

            /*
              A LOOSE map.swf, WHICH IS SOMEBODY ELSE'S AND BREAKS SkyUI.

              22 September: a full screen box on the way in, "SKYUI ERROR CODE
              5. Incompatible menu file (map.swf)." SkyUI checks that file's
              version and refuses one it does not recognise, so the box is
              SkyUI saying something else's copy won.

              MEASURED RATHER THAN GUESSED. The file is in the Steam copy, this
              class hard linked it into Thornswood's folder, and the publish
              baseline ships it. Vortex's own deployment record does NOT list
              it: nothing in the collection put it there. SkyUI ships its
              map.swf inside SkyUI_SE.bsa, and A Quality World Map, which is
              the other mod anybody would suspect, ships 32 files and not one
              of them is a .swf or anything under Interface at all. Its map is
              Textures\terrain\*.dds, the ESP and two scripts.

              So the loose file is an orphan another launcher left in the Steam
              copy, it overrides SkyUI's copy because loose beats an archive,
              and it is the only reason for the error.

              TAKING IT OUT LOSES NOTHING AND KEEPS THE GOOD MAP. SkyUI's own
              copy loads from its archive, and A Quality World Map's terrain
              textures are untouched, so the map still looks the way Patrick
              wants it to.

              This is the same disease as the SkyMP client runtime above, in a
              different folder: a file in the Steam copy that is not the
              collection's, taken into our folder and then shipped to everybody
              as though it were ours. Ship-Rules.ps1 carries the same rule;
              change the two together.
            */
            if (rel.Equals("Data\\Interface\\map.swf", StringComparison.OrdinalIgnoreCase)) return true;

            if (!rel.StartsWith("Data\\Platform\\", StringComparison.OrdinalIgnoreCase)) return false;
            if (leaf.EndsWith(".bak", StringComparison.OrdinalIgnoreCase)) return true;
            // The retired dresser, To Do List entry 127: it put the best armour
            // it could find into every empty slot, which is Patrick's "it is
            // auto equipping things sometimes, like a hat", and it is deleted
            // from the repo. A Steam copy that took packs before its machine had
            // a folder of its own still has the old one; on Patrick's machine on
            // 24 Sep that is 11,654 bytes dated 16 Sep, with its equipItem call.
            // Packs delete it here and Keep.Forget drops the kept copy, and
            // without this line the next refresh finds the name missing, copies
            // that file back in with its 16 Sep time, and Keep.Seed takes it for
            // a kept copy because the old pack records list it. Ship-Rules.ps1
            // carries the same rule and puts the path on $ShipDeleteAlways;
            // change them together.
            if (rel.Equals("Data\\Platform\\Plugins\\thornswood-chargen.js", StringComparison.OrdinalIgnoreCase)) return true;
            // The bundle is on ClientFiles and answered above in WhyLeft, so
            // here it is simply not ours to take from the Steam copy either.
            if (Regex.IsMatch(rel, @"^Data\\Platform\\Plugins\\[^\\]+\.js$", I))
                return !leaf.StartsWith("thornswood-", StringComparison.OrdinalIgnoreCase);
            if (rel.StartsWith("Data\\Platform\\UI\\", StringComparison.OrdinalIgnoreCase))
            {
                if (rel.StartsWith("Data\\Platform\\UI\\assets\\", StringComparison.OrdinalIgnoreCase)) return true;
                if (leaf.Equals("app.js", StringComparison.OrdinalIgnoreCase) || leaf.Equals("vite.svg", StringComparison.OrdinalIgnoreCase)) return true;
                // Everything else flat under UI is ours: index.html, build.js,
                // the thornswood-*.js overlays, and the front's own hashed
                // fonts, icons and sounds beside build.js. Somebody else's menu
                // is a Vite build, which is the assets folder and the two
                // names above. The first version of this rule on 20 September
                // whitelisted three names and would have left the front's 147
                // asset files out of the next refresh.
            }
            return false;
        }

        static readonly string[] CopyTypes = {
            ".ini", ".json", ".toml", ".txt", ".cfg", ".xml", ".yaml", ".yml", ".js", ".html", ".htm",
            ".css", ".dll", ".exe", ".asi", ".bat", ".cmd", ".ps1", ".count", ".bak", ".ess", ".skse",
            ".md", ".csv", ".jslot"
        };

        /// <summary>
        /// Skyrim's own master files. The server checks plugins by size and
        /// checksum, and anything else that writes into the Steam copy would
        /// change a linked master under Thornswood, so these are copied.
        /// </summary>
        static readonly string[] Masters = {
            "Data\\Skyrim.esm", "Data\\Update.esm", "Data\\Dawnguard.esm", "Data\\HearthFires.esm",
            "Data\\Dragonborn.esm", "Data\\_ResourcePack.esl"
        };


        /// <summary>
        /// What a behavior generator writes into the game: Nemesis and FNIS
        /// rebuild every behavior graph, the two character defaults and FNIS.pex
        /// for the mod list they are run against, and they write over the
        /// existing files IN PLACE.
        ///
        /// 26 September, Djinn's machine. Nemesis was run at 5:32 AM for a Solo
        /// profile in the Steam copy. Both Thornswood folders on that machine,
        /// the live one and the dev one, had those files as hard links to the
        /// Steam copy's, so both started playing the Solo animations at that
        /// moment without any refresh, and the next dev Ship tried to send
        /// them to every tester (the ship check stopped it). Running Nemesis
        /// again for the Thornswood profile at 2:26 PM changed them back in all
        /// three folders at once, which is the same leak the other way round.
        ///
        /// Copied, the folder keeps what it was built with until a refresh
        /// brings in what Vortex has deployed for Thornswood, whatever anybody
        /// generates in the Steam copy for another profile in between.
        /// </summary>
        static bool Generated(string rel)
        {
            const RegexOptions I = RegexOptions.IgnoreCase;
            if (Regex.IsMatch(rel, @"^Data\\Meshes\\.*\\behaviors\\[^\\]+\.hkx$", I)) return true;
            if (Regex.IsMatch(rel, @"^Data\\Meshes\\actors\\character\\characters( female)?\\default(male|female)\.hkx$", I)) return true;
            if (Regex.IsMatch(rel, @"^Data\\Scripts\\FNIS[^\\]*\.pex$", I)) return true;
            return false;
        }

        /// <summary>
        /// A folder somebody parked inside the Steam copy: a name starting with
        /// an underscore, at the game's root or directly in Data. Skyrim ships
        /// none, and nothing loads from one. What was in them on 26 September:
        /// _Parked (a whole multiplayer client with a voice token), _Solo Mods,
        /// _Profile Switch (a switch script) and Data\_disabledByKzl. A file
        /// whose own name starts with one, such as Data\_ResourcePack.esl, is
        /// the game's and is not matched: only a folder is.
        /// </summary>
        static bool Parked(string rel)
        {
            string[] p = rel.Split('\\');
            if (p.Length > 1 && p[0].StartsWith("_")) return true;
            if (p.Length > 2 && p[0].Equals("Data", StringComparison.OrdinalIgnoreCase) && p[1].StartsWith("_")) return true;
            return false;
        }

        /// <summary>
        /// Copied rather than linked: anything in the game's root folder, the
        /// client and browser folders, the script extender's folder and MCM's
        /// settings, any settings, script or program file wherever it is, the
        /// game's master files. Those are what gets rewritten in place.
        ///
        /// Exception under Data\Platform\Distribution: a file Vortex deployed
        /// that is not one of the six recorded in records\client-build.json
        /// (ClientFile) is hard linked, even when it is a .dll or .exe. Those
        /// are the 68 CEF and Node redistributables the collection carries;
        /// nothing rewrites them in place. The two recorded Distribution
        /// files (SkyrimPlatformImpl.dll and SkyrimPlatformCEF.exe.hidden)
        /// stay copied. Everything else under Data\Platform keeps being
        /// copied. Issue #392.
        /// </summary>
        public static bool MustCopy(string rel, HashSet<string> deployed)
        {
            if (rel.IndexOf('\\') < 0) return true;
            // Vortex redistributables under Distribution: link, even .dll/.exe.
            // The two recorded client-build files stay copied (ClientFile).
            if (rel.StartsWith("Data\\Platform\\Distribution\\", StringComparison.OrdinalIgnoreCase)
                && deployed != null
                && deployed.Contains(rel)
                && !ClientFile(rel))
                return false;
            foreach (string d in new string[] { "Data\\Platform\\", "Data\\SKSE\\", "Data\\MCM\\", "Data\\Video\\" })
                if (rel.StartsWith(d, StringComparison.OrdinalIgnoreCase)) return true;
            foreach (string m in Masters)
                if (rel.Equals(m, StringComparison.OrdinalIgnoreCase)) return true;
            if (Generated(rel)) return true;
            return Array.IndexOf(CopyTypes, Path.GetExtension(rel).ToLowerInvariant()) >= 0;
        }

        static void Place(string from, string to, bool copy, out bool linked)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(to));
            if (!copy && CreateHardLink(to, from, IntPtr.Zero)) { linked = true; return; }
            File.Copy(from, to, false);
            linked = false;
        }

        // ------------------------------------------------------------ records

        static readonly Regex RelPath = new Regex("\"relPath\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");

        /// <summary>
        /// Every path Vortex says it deployed, relative to the game folder. The
        /// record in Data is relative to Data; the ones in the game's root (the
        /// script extender's loader is one) are relative to the root.
        /// </summary>
        public static HashSet<string> DeployedIn(string src) { return Deployed(src); }

        static HashSet<string> Deployed(string src)
        {
            var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            ReadDeployment(set, Path.Combine(src, "Data"), "Data\\");
            ReadDeployment(set, src, "");
            return set;
        }

        static void ReadDeployment(HashSet<string> set, string dir, string prefix)
        {
            string[] files;
            try { files = Directory.GetFiles(dir, "vortex.deployment*.json"); } catch { return; }
            foreach (string f in files)
            {
                string text;
                try { text = File.ReadAllText(f); } catch { continue; }
                foreach (Match m in RelPath.Matches(text))
                {
                    string rel = Unescape(m.Groups[1].Value).Replace('/', '\\').TrimStart('\\');
                    if (rel.Length > 0) set.Add(prefix + rel);
                }
            }
        }

        static string Unescape(string s)
        {
            if (s.IndexOf('\\') < 0) return s;
            var sb = new StringBuilder(s.Length);
            for (int i = 0; i < s.Length; i++)
            {
                char c = s[i];
                if (c != '\\' || i + 1 >= s.Length) { sb.Append(c); continue; }
                char n = s[++i];
                switch (n)
                {
                    case 'n': sb.Append('\n'); break;
                    case 't': sb.Append('\t'); break;
                    case 'r': sb.Append('\r'); break;
                    case 'b': sb.Append('\b'); break;
                    case 'f': sb.Append('\f'); break;
                    case 'u':
                        if (i + 4 < s.Length)
                        {
                            sb.Append((char)Convert.ToInt32(s.Substring(i + 1, 4), 16));
                            i += 4;
                        }
                        break;
                    default: sb.Append(n); break;
                }
            }
            return sb.ToString();
        }

        /// <summary>
        /// Every file that goes into Thornswood's folder when Vortex deploys
        /// into <paramref name="src"/>, each with where it is brought from.
        /// Anything that cannot be brought in is said in <paramref name="left"/>.
        ///
        /// When src is a Steam copy this is what it always was, a walk of src.
        ///
        /// When it is not, NO BLEED. Patrick, 24 September, about a tester
        /// whose Vortex deploys into another server's copy of Skyrim: "can you
        /// make it so our launcher detcts and fixes this but doesnt have the
        /// servers bleed still". That folder holds the other server's own
        /// SkyrimSE.exe, script extender, dlls, ini files, client and whatever
        /// its installer put in Data, and none of it may reach Thornswood. So
        /// nothing is read out of src but Vortex's records, and the folder is
        /// made of exactly two things: the game from the Steam copy (Source),
        /// walked the same way the Steam copy always has been, and the files
        /// those records list, from Vortex's staging folder where they live.
        /// A record's file replaces the Steam copy's at the same path, which is
        /// what Vortex deploying into the Steam copy does. The result is what
        /// somebody whose Vortex deploys into the Steam copy gets.
        /// </summary>
        static List<Found> Gather(string src, List<string> left)
        {
            string game = GameFor(src);
            if (SameFolder(game, src)) return Walk(src);

            // The game, and not an older deployment Vortex left in the Steam
            // copy before it moved: those files are its record there, if any.
            var byRel = new Dictionary<string, Found>(StringComparer.OrdinalIgnoreCase);
            HashSet<string> stale = Deployed(game);
            foreach (Found f in Walk(game))
            {
                if (stale.Contains(f.Rel)) { left.Add(f.Rel + "  (an older Vortex deployment in the Steam copy, not where Vortex deploys now)"); continue; }
                byRel[f.Rel] = f;
            }

            Record rec = Staged(src);
            left.AddRange(rec.Refused);
            foreach (KeyValuePair<string, string> kv in rec.From)
            {
                var f = new Found();
                f.Rel = kv.Key;
                f.From = kv.Value;
                try
                {
                    var fi = new FileInfo(kv.Value);
                    if (!fi.Exists)
                    {
                        left.Add(kv.Key + "  (Vortex's record lists it and its mods folder does not have it)");
                        continue;
                    }
                    f.Size = fi.Length;
                    f.Ticks = fi.LastWriteTimeUtc.Ticks;
                }
                catch
                {
                    left.Add(kv.Key + "  (Vortex's copy of it could not be read)");
                    continue;
                }
                byRel[f.Rel] = f;
            }
            return new List<Found>(byRel.Values);
        }

        [DataContract]
        class VortexRecord
        {
            [DataMember] public string stagingPath;
            [DataMember] public VortexFile[] files;
        }

        [DataContract]
        class VortexFile
        {
            [DataMember] public string relPath;
            [DataMember] public string source;
        }

        /// <summary>What Vortex's records in a folder list, and where Vortex keeps each file.</summary>
        class Record
        {
            // Path under the game folder, the same one Deployed gives, to the
            // file in staging: stagingPath\source\relPath. Measured on
            // Patrick's machine on 24 September: all 29,964 files the two
            // records in the Steam copy list are at exactly that path.
            public Dictionary<string, string> From = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            public List<string> Staging = new List<string>();
            public List<string> Refused = new List<string>();
        }

        static readonly object recordLock = new object();
        static string recordKey;
        static Record recordCache;

        /// <summary>
        /// Vortex's records in <paramref name="src"/>, read in full. The one in
        /// Data is six megabytes on a full collection and takes about half a
        /// second to read, and the settings card asks WhyNot on the window's
        /// thread, so the answer is kept until Vortex deploys again.
        /// </summary>
        static Record Staged(string src)
        {
            string key = src + "|" + DeploymentStamp(src);
            lock (recordLock) { if (recordCache != null && recordKey == key) return recordCache; }

            var r = new Record();
            foreach (string[] where in new string[][] { new string[] { Path.Combine(src, "Data"), "Data\\" }, new string[] { src, "" } })
            {
                string[] files;
                try { files = Directory.GetFiles(where[0], "vortex.deployment*.json"); } catch { continue; }
                Array.Sort(files, StringComparer.OrdinalIgnoreCase);
                foreach (string f in files)
                {
                    VortexRecord doc = null;
                    try
                    {
                        using (var fs = File.OpenRead(f))
                            doc = (VortexRecord)new DataContractJsonSerializer(typeof(VortexRecord)).ReadObject(fs);
                    }
                    catch { /* doc stays null, and the record is refused just below with a line saying so */ }
                    if (doc == null || doc.files == null || string.IsNullOrEmpty(doc.stagingPath))
                    {
                        r.Refused.Add(f.Substring(src.TrimEnd('\\').Length).TrimStart('\\') + "  (Vortex's record could not be read, so nothing it lists was brought in)");
                        continue;
                    }
                    // A mods folder that is the folder Vortex deploys into, or
                    // sits inside it, would bring that folder's own files in
                    // whenever the record listed them. Vortex does not accept a
                    // staging folder inside the game folder, so such a record
                    // was not written by it; refusing it keeps the no-bleed rule
                    // true for any record at all. Verification of hotfix 1.1.93.
                    if (Overlaps(doc.stagingPath, src))
                    {
                        r.Refused.Add(f.Substring(src.TrimEnd('\\').Length).TrimStart('\\') + "  (Vortex's record names a mods folder that overlaps " + src + ", so nothing it lists was brought in)");
                        continue;
                    }
                    bool listed = false;
                    foreach (string s in r.Staging) if (SameFolder(s, doc.stagingPath)) listed = true;
                    if (!listed) r.Staging.Add(doc.stagingPath);
                    // Each mod's folder in staging, worked out once per mod
                    // rather than once per file: thirty thousand entries.
                    var mods = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                    foreach (VortexFile e in doc.files)
                    {
                        if (e == null || string.IsNullOrEmpty(e.relPath) || string.IsNullOrEmpty(e.source)) continue;
                        string under = e.relPath.Replace('/', '\\').TrimStart('\\');
                        string rel = where[1] + under;
                        string mod;
                        if (!mods.TryGetValue(e.source, out mod)) { mod = ModFolder(doc.stagingPath, e.source); mods[e.source] = mod; }
                        if (mod == null || !Tidy(under) || !Tidy(rel))
                        {
                            r.Refused.Add(rel + "  (Vortex's record points outside Thornswood's folder or Vortex's mods folder)");
                            continue;
                        }
                        if (!r.From.ContainsKey(rel)) r.From[rel] = mod + under;
                    }
                }
            }
            lock (recordLock) { recordKey = key; recordCache = r; }
            return r;
        }

        /// <summary>
        /// stagingPath\source\ with a closing separator, or null when the mod's
        /// name would put it anywhere but directly inside staging. A file under
        /// it stays inside it as long as its own path is Tidy.
        /// </summary>
        static string ModFolder(string staging, string source)
        {
            try
            {
                if (source.IndexOfAny(new char[] { '\\', '/', ':' }) >= 0 || source.Trim('.', ' ').Length == 0) return null;
                string root = Path.GetFullPath(staging).TrimEnd('\\') + "\\";
                string mod = Path.GetFullPath(Path.Combine(staging, source)).TrimEnd('\\') + "\\";
                if (!mod.StartsWith(root, StringComparison.OrdinalIgnoreCase) || mod.Length <= root.Length) return null;
                return mod;
            }
            catch { return null; }
        }

        /// <summary>
        /// One folder is the other or holds it. Anything that cannot be
        /// worked out counts as overlapping, because refusing only means
        /// nothing is brought in from that record.
        /// </summary>
        static bool Overlaps(string a, string b)
        {
            try
            {
                string x = Path.GetFullPath(a).TrimEnd('\\') + "\\";
                string y = Path.GetFullPath(b).TrimEnd('\\') + "\\";
                return x.StartsWith(y, StringComparison.OrdinalIgnoreCase) || y.StartsWith(x, StringComparison.OrdinalIgnoreCase);
            }
            catch { return true; }
        }

        /// <summary>A path under the game folder that stays under it: no drive, no "..".</summary>
        static bool Tidy(string rel)
        {
            if (rel.Length == 0 || rel.IndexOf(':') >= 0 || rel.StartsWith("\\")) return false;
            foreach (string part in rel.Split('\\')) if (part == "..") return false;
            return true;
        }

        /// <summary>When Vortex last deployed, as the newest write time of its records.</summary>
        static long DeploymentStamp(string src)
        {
            long newest = 0;
            foreach (string dir in new string[] { src, Path.Combine(src, "Data") })
            {
                try
                {
                    foreach (string f in Directory.GetFiles(dir, "vortex.deployment*.json"))
                        newest = Math.Max(newest, File.GetLastWriteTimeUtc(f).Ticks);
                }
                catch { }
            }
            return newest;
        }

        /// <summary>
        /// Sum of sizes for files this folder holds as its own copies (C lines
        /// in files.txt). Hard-linked Vortex files are left out on purpose so
        /// Installed apps does not show forty gigabytes of shared collection.
        /// </summary>
        static long SumCopied(List<string> lines)
        {
            long n = 0;
            foreach (string line in lines)
            {
                string[] p = line.Split(new char[] { '|' }, 5);
                if (p.Length < 3 || p[0] != "C") continue;
                long s;
                if (long.TryParse(p[2], out s)) n += s;
            }
            return n;
        }

        static void WriteMade(string src, long copied)
        {
            File.WriteAllLines(MadeFile, new string[] {
                "source=" + src,
                "game=" + GameFor(src),
                "deployment=" + DeploymentStamp(src),
                "rules=" + Rules,
                "copied=" + copied,
                "at=" + DateTime.Now.ToString("o")
            });
        }

        static long Recorded(string key)
        {
            try
            {
                foreach (string line in File.ReadAllLines(MadeFile))
                {
                    if (!line.StartsWith(key + "=", StringComparison.Ordinal)) continue;
                    long v;
                    if (long.TryParse(line.Substring(key.Length + 1), out v)) return v;
                }
            }
            catch { }
            return -1;
        }

        static Dictionary<string, Rec> ReadFiles()
        {
            var d = new Dictionary<string, Rec>(StringComparer.OrdinalIgnoreCase);
            try
            {
                foreach (string line in File.ReadAllLines(FilesList))
                {
                    string[] p = line.Split(new char[] { '|' }, 5);
                    if (p.Length < 5 || p[0].Length != 1 || p[1].Length != 1) continue;
                    var r = new Rec();
                    r.Kind = p[0][0];
                    r.Origin = p[1][0];
                    long.TryParse(p[2], out r.Size);
                    long.TryParse(p[3], out r.Ticks);
                    d[p[4]] = r;
                }
            }
            catch { }
            return d;
        }

        /// <summary>
        /// Files a Thornswood update or the installer put into the game, which
        /// a refresh leaves as they are. What the installer laid down that Vortex
        /// also deploys stays Vortex's, so collection updates still reach it.
        /// </summary>
        static HashSet<string> Owned(HashSet<string> deployed)
        {
            var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            try
            {
                if (Directory.Exists(Paths.PacksDir))
                {
                    foreach (string rec in Directory.GetFiles(Paths.PacksDir, "*.files"))
                    {
                        foreach (string line in File.ReadAllLines(rec))
                        {
                            int bar = line.IndexOf('|');
                            if (bar < 0) continue;
                            string rel = line.Substring(bar + 1);
                            if (rel.StartsWith("game\\", StringComparison.OrdinalIgnoreCase)) set.Add(rel.Substring(5));
                        }
                    }
                }
            }
            catch { }
            try { foreach (string rel in Keep.Held()) set.Add(rel); } catch { }
            try
            {
                string list = Path.Combine(Paths.ProfileDir, "installed-into-game.txt");
                if (File.Exists(list))
                    foreach (string line in File.ReadAllLines(list))
                    {
                        string rel = line.Trim();
                        if (rel.Length > 0 && !deployed.Contains(rel)) set.Add(rel);
                    }
            }
            catch { }
            return set;
        }

        /// <summary>Plugins switched on in the list this build shipped with.</summary>
        static List<string> ShippedPlugins()
        {
            var l = new List<string>();
            try
            {
                string golden = Path.Combine(Paths.Golden, "plugins.txt");
                if (!File.Exists(golden)) return l;
                foreach (string raw in File.ReadAllLines(golden))
                {
                    string s = raw.Trim();
                    if (s.StartsWith("*") && s.Length > 1) l.Add(s.Substring(1));
                }
            }
            catch { }
            return l;
        }

        // ------------------------------------------------------------ disk

        /// <summary>Every file under <paramref name="root"/>, without following links to folders.</summary>
        static List<Found> Walk(string root)
        {
            var l = new List<Found>();
            string fence = root.TrimEnd('\\') + "\\";
            var stack = new Stack<string>();
            stack.Push(root);
            while (stack.Count > 0)
            {
                string dir = stack.Pop();
                try
                {
                    foreach (string sub in Directory.GetDirectories(dir))
                    {
                        try
                        {
                            if ((new DirectoryInfo(sub).Attributes & FileAttributes.ReparsePoint) != 0) continue;
                        }
                        catch { continue; }
                        stack.Push(sub);
                    }
                }
                catch { }
                try
                {
                    foreach (string f in Directory.GetFiles(dir))
                    {
                        try
                        {
                            var fi = new FileInfo(f);
                            var found = new Found();
                            found.From = f;
                            found.Rel = f.Substring(fence.Length);
                            found.Size = fi.Length;
                            found.Ticks = fi.LastWriteTimeUtc.Ticks;
                            l.Add(found);
                        }
                        catch { }
                    }
                }
                catch { }
            }
            return l;
        }

        static bool SameFolder(string a, string b)
        {
            try { return string.Equals(Path.GetFullPath(a).TrimEnd('\\'), Path.GetFullPath(b).TrimEnd('\\'), StringComparison.OrdinalIgnoreCase); }
            catch { return false; }
        }

        static string Volume(string p)
        {
            try { return Path.GetPathRoot(Path.GetFullPath(p)).TrimEnd('\\'); } catch { return p; }
        }

        static bool SameVolume(string a, string b)
        {
            return string.Equals(Volume(a), Volume(b), StringComparison.OrdinalIgnoreCase);
        }

        /// <summary>
        /// WhyNot's answer when the folder would have to link across two
        /// drives: which drive each side is on, and the two things that put
        /// them on one.
        ///
        /// The links stay. A hard link is the same file under a second name and
        /// Windows will not make one across volumes, so this is a real refusal
        /// and not a message that could be argued out of; whether the launcher
        /// may copy instead, at the 26 to 41 GB measured in a built folder on
        /// 24 September, is the team's call and not this method's. What it stops
        /// is ending the road. Both ways out are somebody else's screen, so
        /// each is named down to the drive letter, the path it lands in and the
        /// buttons to press.
        ///
        /// One sentence, no line breaks: the same string goes to a MessageBox,
        /// to the card in Settings, to the one line status strip on the Play
        /// page and to Profile\launcher.log, which is one entry to a line.
        /// </summary>
        /// <param name="where">Where the other side is, "Skyrim is in D:\SteamLibrary\...".</param>
        /// <param name="theirs">The drive that side is on, "D:".</param>
        /// <param name="move">The second way out: moving that side to Thornswood's drive.</param>
        static string OneDriveOnly(string where, string theirs, string move)
        {
            string here = Volume(Paths.Root);
            return where + ", on " + theirs + ", and Thornswood is in " + Paths.Root + ", on " + here +
                   ". A hard link is the same file under a second name, and Windows cannot make one across two drives, " +
                   "so the folder cannot be made while they are apart. Either of these puts them on one drive. " +
                   "Install Thornswood on " + theirs + " by running the Thornswood setup program again, the one from the " +
                   "Downloads page, and choosing " + theirs + " when it asks where to put it, which installs it in " +
                   theirs + "\\Thornswood. Or " + move + ".";
        }

        static long FreeSpace(string p)
        {
            try { return new DriveInfo(Volume(p)).AvailableFreeSpace; } catch { return -1; }
        }

        static string Mb(long bytes)
        {
            return (bytes / 1024.0 / 1024.0).ToString("n0") + " MB";
        }
    }
}
