using System;
using System.Collections.Generic;
using System.IO;

namespace Thornswood
{
    /// <summary>
    /// A full crash snapshot of the game, only when the person turns it on
    /// (#2626, which replaces the dev-and-staff rule of #1191).
    ///
    /// Crash Logger writes a text log for every crash: a scan of the stack
    /// and its best guess at the module. For the rare crashes that is not
    /// enough to find the cause (#407, where frame 0 is the bad address
    /// itself, and #408). Crash Logger can also write a snapshot beside the
    /// log, crash-(time).dmp, holding all of the game's memory at that moment
    /// (it asks Windows for MiniDumpWithFullMemory), which a debugger opens
    /// as if the crash were happening in front of it.
    ///
    /// WHY IT IS OFF UNLESS ASKED FOR. Until 17 October this was turned on
    /// by itself for the dev build and for every staff Discord account, and
    /// the comment here said one was "about 1 GB". The one written on Djinn's
    /// PC that day was 9,829,847,602 bytes and took about 95 seconds, and
    /// nobody had told him it was being written. His words: "filling my PC
    /// with information I knew nothing about taking up space and resources is
    /// not cool". So it is a setting, Settings, Crash snapshots, off for
    /// everybody until they tick it, with the size said beside the box and a
    /// folder they choose.
    ///
    /// Before every Play, Apply writes Crash Logger's own switch into this
    /// install's CrashLogger.ini to match the setting. Turning it off stops
    /// new snapshots and deletes nothing: a file already on somebody's disk
    /// is theirs to keep or delete. With it on, only the newest is kept, and
    /// the setting says so before it is ticked.
    ///
    /// As the game closes after a crash, AfterSession moves the snapshot to
    /// the chosen folder when there is one, and the launcher shows it with
    /// its size and asks whether to keep it (Shell.cs).
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
        // it on, and it is held off whenever snapshots are.
        const string ThreadKey = "Thread Dump Write Minidump";
        const string Sep = " = ";

        /// <summary>What the setting tells people before they tick it.</summary>
        public const string SizeNote =
            "A snapshot is a copy of everything in the game's memory at the moment it crashed. " +
            "One can be 9 GB or more, and writing it takes a minute or two. Only the newest is kept. " +
            "It stays on this PC and nothing sends it anywhere. Leave this off unless somebody looking into a crash asks for one.";

        public static string Ini { get { return Path.Combine(Paths.Game, "Data\\SKSE\\Plugins\\CrashLogger.ini"); } }
        static string Dll { get { return Path.Combine(Paths.Game, "Data\\SKSE\\Plugins\\CrashLogger.dll"); } }

        /// <summary>Where Crash Logger writes its logs and snapshots: this install's Profile\MyGames\SKSE.</summary>
        public static string Folder { get { return Files.SkseLogDir; } }

        /// <summary>Whether the person turned snapshots on.</summary>
        public static bool Wanted(Config cfg)
        {
            return cfg != null && cfg.CrashSnapshots;
        }

        /// <summary>The folder the person chose, or Crash Logger's own when they chose none.</summary>
        public static string KeptIn(Config cfg)
        {
            string chosen = cfg == null ? "" : (cfg.CrashSnapshotFolder ?? "").Trim();
            return chosen.Length > 0 ? chosen : Folder;
        }

        /// <summary>
        /// Before Play: Crash Logger's switch written to match the setting.
        /// Returns a line for the log when anything changed, or null.
        /// </summary>
        public static string Apply(Config cfg)
        {
            return Apply(Wanted(cfg), KeptIn(cfg));
        }

        public static string Apply(bool want, string keptIn)
        {
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

            int gone = want ? Tidy(keptIn) : 0;

            var said = new List<string>();
            if (turned && want)
                said.Add("Crash snapshots are on, as you set in Settings. If the game crashes, a full snapshot is saved in " + keptIn +
                         ". One can be 9 GB or more, only the newest is kept, and it stays on this PC.");
            if (turned && !want)
                said.Add("Crash snapshots are off. Any already saved are left where they are; you can delete them from " + keptIn + ".");
            if (gone > 0)
                said.Add("Deleted " + gone + " older crash snapshot" + (gone == 1 ? "" : "s") + ". Only the newest is kept.");
            return said.Count == 0 ? null : string.Join(" ", said.ToArray());
        }

        /// <summary>
        /// Where snapshots are kept: deletes all but the newest crash
        /// snapshot in that folder, and in Crash Logger's own when it is a
        /// different one. Called only with snapshots on. Returns how many
        /// went.
        /// </summary>
        public static int Tidy(string keptIn)
        {
            int gone = 0;
            try
            {
                var dumps = new List<FileInfo>();
                var folders = new List<string>();
                folders.Add(Folder);
                if (!string.IsNullOrEmpty(keptIn) && !SameFolder(keptIn, Folder)) folders.Add(keptIn);
                foreach (string dir in folders)
                {
                    if (!Directory.Exists(dir)) continue;
                    foreach (string f in Directory.GetFiles(dir, "crash-*.dmp")) dumps.Add(new FileInfo(f));
                }
                dumps.Sort(delegate(FileInfo a, FileInfo b) { return b.LastWriteTimeUtc.CompareTo(a.LastWriteTimeUtc); });
                for (int i = 1; i < dumps.Count; i++)
                {
                    try { dumps[i].Delete(); gone++; }
                    catch (Exception ex) { Swallow.Note("CrashDump.Tidy, " + dumps[i].Name, ex); }
                }
            }
            catch (Exception ex) { Swallow.Note("CrashDump.Tidy", ex); }
            return gone;
        }

        static bool SameFolder(string a, string b)
        {
            try
            {
                return string.Equals(Path.GetFullPath(a).TrimEnd('\\', '/'), Path.GetFullPath(b).TrimEnd('\\', '/'),
                                     StringComparison.OrdinalIgnoreCase);
            }
            catch { return false; }
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
        /// log since sinceLocal), the line saying so. With snapshots on and a
        /// snapshot beside the log, it is moved to the chosen folder, older
        /// ones there are deleted, and snapshot is its path, for the launcher
        /// to show and ask about. Null when it did not crash.
        /// </summary>
        public static string AfterSession(DateTime sinceLocal, bool want, string keptIn, out string snapshot)
        {
            snapshot = null;
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

                string line = "The game crashed. Its crash log is " + log.Name + " in " + Folder + ".";
                string dmp = Beside(log.FullName);
                if (dmp == null || !want) return line;

                string to = dmp;
                if (!string.IsNullOrEmpty(keptIn) && !SameFolder(keptIn, Folder))
                {
                    try
                    {
                        Directory.CreateDirectory(keptIn);
                        to = Path.Combine(keptIn, Path.GetFileName(dmp));
                        if (File.Exists(to)) File.Delete(to);
                        File.Move(dmp, to);
                    }
                    catch (Exception ex)
                    {
                        Swallow.Note("CrashDump.AfterSession, move", ex);
                        line += " The snapshot could not be moved to " + keptIn + " (" + ex.Message + "), so it is still beside the crash log.";
                        to = dmp;
                    }
                }
                Tidy(keptIn);
                snapshot = File.Exists(to) ? to : null;
                if (snapshot != null)
                    line += " A full crash snapshot was saved: " + snapshot + ", " + Size(new FileInfo(snapshot).Length) +
                            ". It holds what was in the game's memory, so it stays on this PC and nothing sends it anywhere.";
                return line;
            }
            catch (Exception ex) { Swallow.Note("CrashDump.AfterSession", ex); }
            return null;
        }

        public static string Size(long b)
        {
            if (b < 1024L * 1024 * 1024) return (b / (1024.0 * 1024.0)).ToString("F0") + " MB";
            return (b / (1024.0 * 1024.0 * 1024.0)).ToString("F1") + " GB";
        }
    }
}
