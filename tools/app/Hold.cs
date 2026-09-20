using System;
using System.Collections.Generic;
using System.IO;

namespace Thornswood
{
    /// <summary>
    /// Holds Thornswood's own game files open, read only, for as long as the
    /// game runs, so nothing else can change them under it.
    ///
    /// Keep puts our files back before Play and parks other servers' plugins,
    /// then puts theirs back when the game closes. Between those two moments
    /// the launcher is not the thing running, and that gap is where the mixing
    /// actually happened: on 16 Sep Thornswood started the game at 19:03 and
    /// another server's launcher was opened at 19:08, while the game was live.
    /// At 19:08:47 it rewrote UI\index.html, skymp5-client.js, the client
    /// settings and its own activity plugin. Skyrim Platform reloads plugins
    /// the moment their files change, so the swap took effect at once and both
    /// servers were on screen together.
    ///
    /// A file held open with FileShare.Read can be read by anybody (the game,
    /// Skyrim Platform, the menu's browser) and written, replaced or deleted by
    /// nobody, including this launcher, which is why its own writers go through
    /// Around(). Where a parked plugin used to be, an empty file of the same
    /// name is held as well, so the other launcher cannot put its copy back
    /// there mid-session. Everything is let go the moment the game closes,
    /// before Keep returns the parked plugins.
    ///
    /// A watcher on Plugins and UI says in the log when something else writes
    /// there during the session. It cannot get through to a held file, but the
    /// line in the log is the fact worth having when two servers look mixed.
    /// </summary>
    static class Hold
    {
        static readonly List<FileStream> open = new List<FileStream>();
        static readonly List<string> stubs = new List<string>();
        static readonly HashSet<string> said = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        static readonly object gate = new object();
        static FileSystemWatcher watcher;
        static Action<string> say;

        /// <summary>
        /// Files of ours in the game folder that are not kept copies but are
        /// rewritten by every SkyMP launcher, ours included, at Play.
        /// </summary>
        static readonly string[] Extra = {
            "Data\\Platform\\Plugins\\skymp5-client-settings.txt",
        };

        /// <summary>
        /// Takes hold of everything. Called last thing before the game starts,
        /// after Keep has put our files back and parked the others. Returns how
        /// many files are held. <paramref name="log"/> may be called from
        /// another thread.
        /// </summary>
        public static int Take(Action<string> log)
        {
            Release();
            say = log;
            int n = 0;
            lock (gate)
            {
                var rels = new List<string>();
                try { rels.AddRange(Keep.Held()); } catch { }
                rels.AddRange(Extra);
                foreach (string rel in rels)
                {
                    string p = Path.Combine(Paths.Game, rel);
                    if (!File.Exists(p)) continue;
                    if (Grip(p)) n++;
                }

                // An empty stand-in where each parked plugin was. Skyrim Platform
                // loads it as a plugin that does nothing; the other launcher
                // cannot write over it.
                List<string> homes = new List<string>();
                try { homes = Keep.ParkedHomes(); } catch { }
                foreach (string home in homes)
                {
                    try
                    {
                        if (File.Exists(home)) continue;
                        File.WriteAllText(home, "");
                        if (Grip(home)) { stubs.Add(home); n++; }
                        else { try { File.Delete(home); } catch { } }
                    }
                    catch { }
                }
            }
            Watch();
            return n;
        }

        static bool Grip(string p)
        {
            try
            {
                open.Add(new FileStream(p, FileMode.Open, FileAccess.Read, FileShare.Read));
                return true;
            }
            catch { return false; }
        }

        /// <summary>Lets everything go. Safe to call any time, as often as wanted.</summary>
        public static void Release()
        {
            try
            {
                if (watcher != null)
                {
                    watcher.EnableRaisingEvents = false;
                    watcher.Dispose();
                    watcher = null;
                }
            }
            catch { }
            lock (gate)
            {
                foreach (FileStream fs in open) { try { fs.Dispose(); } catch { } }
                open.Clear();
                foreach (string s in stubs)
                {
                    try { if (File.Exists(s) && new FileInfo(s).Length == 0) File.Delete(s); } catch { }
                }
                stubs.Clear();
            }
            lock (said) said.Clear();
        }

        /// <summary>
        /// Runs a write of the launcher's own against a file that may be held:
        /// the hold comes off that one file, the write happens, the hold goes
        /// back on. Rebinding a key in Settings while the game runs goes through
        /// here. Anything not held just runs.
        /// </summary>
        public static void Around(string path, Action write)
        {
            FileStream held = null;
            lock (gate)
            {
                string full = "";
                try { full = Path.GetFullPath(path); } catch { full = path; }
                foreach (FileStream fs in open)
                {
                    if (string.Equals(fs.Name, full, StringComparison.OrdinalIgnoreCase)) { held = fs; break; }
                }
                if (held != null) { open.Remove(held); try { held.Dispose(); } catch { } }
            }
            // The launcher's own write is not news for the log.
            lock (said) { try { said.Add(Rel(path)); } catch { } }
            try { write(); }
            finally
            {
                if (held != null) lock (gate) { if (File.Exists(held.Name)) Grip(held.Name); }
            }
        }

        // ----------------------------------------------------------- watching

        static void Watch()
        {
            try
            {
                string dir = Path.Combine(Paths.Game, "Data\\Platform");
                if (!Directory.Exists(dir)) return;
                watcher = new FileSystemWatcher(dir);
                watcher.IncludeSubdirectories = true;
                watcher.NotifyFilter = NotifyFilters.FileName | NotifyFilters.LastWrite | NotifyFilters.Size;
                watcher.Changed += OnChange;
                watcher.Created += OnChange;
                watcher.Deleted += OnChange;
                watcher.Renamed += OnRename;
                watcher.EnableRaisingEvents = true;
            }
            catch { watcher = null; }
        }

        static void OnRename(object sender, RenamedEventArgs e) { Notice(e.FullPath, "renamed into place"); }
        static void OnChange(object sender, FileSystemEventArgs e)
        {
            string what = e.ChangeType == WatcherChangeTypes.Deleted ? "deleted" :
                          e.ChangeType == WatcherChangeTypes.Created ? "written" : "changed";
            Notice(e.FullPath, what);
        }

        /// <summary>
        /// Only Plugins and UI matter: that is where servers write. Logs and
        /// the voice plugin's live files sit in the Platform root and change all
        /// session long on purpose. Said once per file per session.
        /// </summary>
        static string Rel(string full)
        {
            string game = Paths.Game.TrimEnd('\\') + "\\";
            try { full = Path.GetFullPath(full); } catch { }
            if (!full.StartsWith(game, StringComparison.OrdinalIgnoreCase)) return null;
            return full.Substring(game.Length);
        }

        static void Notice(string full, string what)
        {
            try
            {
                string rel = Rel(full);
                if (rel == null) return;
                bool inPlugins = rel.StartsWith("Data\\Platform\\Plugins\\", StringComparison.OrdinalIgnoreCase);
                bool inUi = rel.StartsWith("Data\\Platform\\UI\\", StringComparison.OrdinalIgnoreCase);
                if (!inPlugins && !inUi) return;
                if (rel.EndsWith(".log", StringComparison.OrdinalIgnoreCase)) return;
                lock (gate)
                {
                    foreach (string s in stubs) if (string.Equals(s, full, StringComparison.OrdinalIgnoreCase)) return;
                }
                lock (said)
                {
                    if (said.Contains(rel)) return;
                    said.Add(rel);
                }
                Action<string> s2 = say;
                if (s2 != null)
                    s2("Something else " + what + " " + rel + " while " + Keep.Build() + " was running, another server's launcher most likely. " +
                       Keep.Build() + "'s own files are held and did not change.");
            }
            catch { }
        }
    }
}
