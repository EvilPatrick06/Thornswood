using System;
using System.Collections.Generic;
using System.IO;
using System.Threading;

namespace Thornswood
{
    /// <summary>
    /// Waits for the game to write one of the voice files, rather than looking
    /// ten times a second.
    ///
    /// Issue #977, from the #963 audit: the voice file channel slept 100 ms,
    /// opened voice-ptt.txt and voice-muted.txt in both folders, and went
    /// round again, for the whole life of the launcher, game or no game. So
    /// it waits on a watcher over the folders instead and wakes when one of
    /// the named files is written, or when the slow tick is due. Push to talk
    /// arrives as soon as Windows says the file changed, which is sooner than
    /// the old 100 ms poll, not later.
    ///
    /// Only the named files wake it. The game's own logs sit in the same
    /// folder and are written thousands of times a minute; the watcher's
    /// filter and the name check below keep those from reaching the loop. Our
    /// own voice-status.txt is not on the list either, so the launcher's write
    /// does not wake the launcher.
    ///
    /// When no watcher can be made (a folder missing, the watcher refused),
    /// Wait falls back to the old 100 ms sleep, so push to talk is never
    /// slower than it was.
    /// </summary>
    class ChannelWait : IDisposable
    {
        /// <summary>The old poll, kept for when there is no watcher.</summary>
        public const int Poll = 100;

        readonly List<FileSystemWatcher> watchers = new List<FileSystemWatcher>();
        readonly HashSet<string> names;
        readonly AutoResetEvent changed = new AutoResetEvent(false);

        /// <summary>How many times a watched file woke the wait, for the test.</summary>
        public int Wakes;

        /// <summary>True when at least one folder is watched.</summary>
        public bool Watching { get { return watchers.Count > 0; } }

        public ChannelWait(string[] dirs, params string[] files)
        {
            names = new HashSet<string>(files, StringComparer.OrdinalIgnoreCase);
            foreach (string d in dirs)
            {
                try
                {
                    if (!Directory.Exists(d)) continue;
                    var w = new FileSystemWatcher(d, "voice-*.txt");
                    w.IncludeSubdirectories = false;
                    // Room for a burst of the logs beside the files before
                    // Windows gives up and reports a lost buffer (Error).
                    w.InternalBufferSize = 65536;
                    w.NotifyFilter = NotifyFilters.FileName | NotifyFilters.LastWrite | NotifyFilters.Size;
                    w.Changed += OnChange;
                    w.Created += OnChange;
                    w.Renamed += OnRename;
                    // A full buffer means changes were lost: look anyway.
                    w.Error += delegate { changed.Set(); };
                    w.EnableRaisingEvents = true;
                    watchers.Add(w);
                }
                catch (Exception ex) { Swallow.Note("ChannelWait, watching " + d, ex); }
            }
        }

        void OnRename(object sender, RenamedEventArgs e) { Hit(e.Name); }
        void OnChange(object sender, FileSystemEventArgs e) { Hit(e.Name); }

        void Hit(string name)
        {
            if (name == null || !names.Contains(name)) return;
            Interlocked.Increment(ref Wakes);
            changed.Set();
        }

        /// <summary>
        /// Returns when a watched file changed (true) or when <paramref name="ms"/>
        /// has gone by (false). With no watcher it sleeps the old 100 ms and
        /// says true, so the caller reads the files as often as it used to.
        /// </summary>
        public bool Wait(int ms)
        {
            if (!Watching) { Thread.Sleep(Poll); return true; }
            return changed.WaitOne(ms);
        }

        public void Dispose()
        {
            foreach (FileSystemWatcher w in watchers)
            {
                try { w.EnableRaisingEvents = false; w.Dispose(); }
                catch (Exception ex) { Swallow.Note("ChannelWait.Dispose", ex); }
            }
            watchers.Clear();
        }
    }
}
