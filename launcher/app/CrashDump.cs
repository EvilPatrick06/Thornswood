using System;
using System.Collections.Generic;
using System.IO;

namespace Thornswood
{
    /// <summary>
    /// A full crash snapshot of the game, kept on the dev build and on staff
    /// PCs only (#1191).
    ///
    /// Crash Logger writes a text log for every crash: a scan of the stack
    /// and its best guess at the module. For the rare crashes that is not
    /// enough to find the cause (#407, where frame 0 is the bad address
    /// itself, and #408). Crash Logger can also write a snapshot beside the
    /// log, crash-(time).dmp, holding all of the game's memory at that moment
    /// (it asks Windows for MiniDumpWithFullMemory), which a debugger opens
    /// as if the crash were happening in front of it. One is about 1 GB, more
    /// with a big load order.
    ///
    /// Patrick, 29 Sep: yes, on the dev build and on staff PCs only, and only
    /// the newest one kept. So before every Play this writes Crash Logger's
    /// own switch into this install's CrashLogger.ini: on for the dev build
    /// and for a Discord account the site says holds a staff role, off for
    /// everybody else, and off again at the first Play after an install stops
    /// being either, with any snapshot it left deleted. The file is in the
    /// game folder this launcher owns, so nothing here needs administrator.
    /// Windows Error Reporting's LocalDumps would do the same from the
    /// registry, but for every SkyrimSE.exe the Windows account starts, the
    /// other install and a Steam copy included, so it is not used.
    ///
    /// Staff is the site's own answer. /api/play/join says dev true for the
    /// roles in its access.dev (Owner, Dev, Gamemaster, Moderator,
    /// Loremaster), the same answer that lets somebody onto the dev build,
    /// and Discord.Join writes it down as dev-allowed.txt on every check in.
    /// The Discord check runs before every Play, so a role taken away turns
    /// the snapshot off at the next Play, and an unlinked install is not
    /// staff whatever the file says.
    ///
    /// Only the newest is kept. Crash Logger's own Max Minidumps = 1 clears
    /// down to one before it writes the next, so there are two on the disk
    /// for a moment; the launcher deletes the older as the game closes and
    /// again before Play.
    ///
    /// A snapshot is never sent anywhere: not with the session logs, not in
    /// the report zip, not by any button. It holds whatever was in the game's
    /// memory, and it stays on the PC it was written on.
    /// </summary>
    static class CrashDump
    {
        // Crash Logger's own keys, as its CrashLogger.ini spells them, all
        // under [Debug].
        const string Section   = "Debug";
        const string WriteKey  = "Crash Log Write Minidump";
        const string KeepKey   = "Max Minidumps";
        // The snapshot Ctrl+Shift+F12 writes for a hang. Nothing here turns
        // it on; it is held off where snapshots are not kept, so nobody else
        // gets one either.
        const string ThreadKey = "Thread Dump Write Minidump";
        const string Sep = " = ";

        public static string Ini { get { return Path.Combine(Paths.Game, "Data\\SKSE\\Plugins\\CrashLogger.ini"); } }
        static string Dll { get { return Path.Combine(Paths.Game, "Data\\SKSE\\Plugins\\CrashLogger.dll"); } }

        /// <summary>Where the snapshots are: beside the crash logs, in this install's Profile\MyGames\SKSE.</summary>
        public static string Folder { get { return Files.SkseLogDir; } }

        /// <summary>The dev build, or a linked account the site says is staff.</summary>
        public static bool Wanted(bool devBuild, bool linked, bool staff)
        {
            return devBuild || (linked && staff);
        }

        public static bool Wanted(Config cfg)
        {
            return Wanted(cfg != null && cfg.IsDev, Discord.Linked, Discord.DevAllowed);
        }

        /// <summary>
        /// Before Play: the switch written for this install, and any
        /// snapshot it should not keep deleted. Returns a line for the log
        /// when anything changed, or null.
        /// </summary>
        public static string Apply(Config cfg)
        {
            return Apply(cfg != null && cfg.IsDev, Discord.Linked && Discord.DevAllowed);
        }

        public static string Apply(bool devBuild, bool staff)
        {
            bool want = devBuild || staff;
            bool turned = false;
            if (want)
            {
                // Only where Crash Logger is. A missing ini beside the plugin
                // is made with the lines under [Debug]; Crash Logger reads
                // its defaults for the rest.
                if (File.Exists(Dll) || File.Exists(Ini))
                {
                    if (Enforce.SetOrAdd(Ini, Section, WriteKey, "true", Sep)) turned = true;
                    Enforce.SetOrAdd(Ini, Section, KeepKey, "1", Sep);
                }
            }
            else
            {
                // A file without the line is at Crash Logger's default, off.
                if (Enforce.Set(Ini, WriteKey, "false", Sep)) turned = true;
                Enforce.Set(Ini, ThreadKey, "false", Sep);
            }

            int gone = Tidy(want);

            var said = new List<string>();
            if (turned && want)
                said.Add("This install now keeps a full crash snapshot, because " +
                         (devBuild ? "it is the dev build" : "your Discord account holds a staff role") +
                         ". If the game crashes, one is written beside the crash log in " + Folder +
                         ", only the newest kept, about 1 GB. It holds what was in the game's memory, so it stays on this PC and nothing sends it anywhere.");
            if (turned && !want)
                said.Add("This install no longer keeps a crash snapshot: it is not the dev build and your Discord account holds no staff role.");
            if (gone > 0)
                said.Add(want
                    ? "Deleted " + gone + " older crash snapshot" + (gone == 1 ? "" : "s") + ". Only the newest is kept."
                    : "Deleted " + gone + " crash snapshot" + (gone == 1 ? "" : "s") + " from " + Folder + ", because this install no longer keeps them.");
            return said.Count == 0 ? null : string.Join(" ", said.ToArray());
        }

        /// <summary>
        /// Deletes the snapshots this install should not have: all but the
        /// newest where they are kept, every one where they are not. Returns
        /// how many went.
        /// </summary>
        public static int Tidy(bool want)
        {
            int gone = 0;
            try
            {
                if (!Directory.Exists(Folder)) return 0;
                var dumps = new List<FileInfo>();
                foreach (string f in Directory.GetFiles(Folder, "crash-*.dmp")) dumps.Add(new FileInfo(f));
                if (!want)
                    foreach (string f in Directory.GetFiles(Folder, "threaddump-*.dmp")) dumps.Add(new FileInfo(f));
                dumps.Sort(delegate(FileInfo a, FileInfo b) { return b.LastWriteTimeUtc.CompareTo(a.LastWriteTimeUtc); });
                for (int i = want ? 1 : 0; i < dumps.Count; i++)
                {
                    try { dumps[i].Delete(); gone++; }
                    catch (Exception ex) { Swallow.Note("CrashDump.Tidy, " + dumps[i].Name, ex); }
                }
            }
            catch (Exception ex) { Swallow.Note("CrashDump.Tidy", ex); }
            return gone;
        }

        /// <summary>The snapshot written with this crash log, or null.</summary>
        public static string Beside(string crashLog)
        {
            if (string.IsNullOrEmpty(crashLog)) return null;
            string dmp = Path.ChangeExtension(crashLog, ".dmp");
            return File.Exists(dmp) ? dmp : null;
        }

        /// <summary>
        /// As the game closes: when it crashed (Crash Logger wrote a crash
        /// log since sinceLocal), the line saying so, naming the log and the
        /// snapshot beside it when there is one. Null when it did not crash.
        /// The older snapshot is deleted first where they are kept.
        /// </summary>
        public static string AfterSession(DateTime sinceLocal, bool want)
        {
            try
            {
                if (!Directory.Exists(Folder)) return null;
                FileInfo log = null;
                foreach (string f in Directory.GetFiles(Folder, "crash-*.log"))
                {
                    var fi = new FileInfo(f);
                    if (fi.LastWriteTime < sinceLocal) continue;
                    if (log == null || fi.LastWriteTime > log.LastWriteTime) log = fi;
                }
                if (log == null) return null;

                if (want) Tidy(true);
                string line = "The game crashed. Its crash log is " + log.Name + " in " + Folder + ".";
                string dmp = Beside(log.FullName);
                if (dmp != null)
                    line += " The full crash snapshot is beside it: " + Path.GetFileName(dmp) + ", " + Gb(new FileInfo(dmp).Length) +
                            ". Keep it until the crash has been looked at. It holds what was in the game's memory, so it stays on this PC and nothing sends it anywhere.";
                return line;
            }
            catch (Exception ex) { Swallow.Note("CrashDump.AfterSession", ex); }
            return null;
        }

        static string Gb(long b)
        {
            if (b < 1024L * 1024 * 1024) return (b / (1024.0 * 1024.0)).ToString("F0") + " MB";
            return (b / (1024.0 * 1024.0 * 1024.0)).ToString("F1") + " GB";
        }
    }
}
