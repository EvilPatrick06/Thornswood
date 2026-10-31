using System;
using System.IO;
using System.Text;
using System.Threading;

namespace Thornswood
{
    /// <summary>
    /// The collection card notices Vortex finishing an update by itself (#5136).
    ///
    /// Patrick, 31 Oct, on his dev install: "after updating to collection
    /// version 6 I had to click in the diagnasotics page and manually click
    /// scan and fix the app didnt catch automatically that I had updated to
    /// revision 6". Two things were missing, and both had to be there:
    ///
    ///   1. Nothing looked at Vortex again. DrawStatus reads the installed
    ///      revision fresh, but only runs on a page change, a scan, a feed
    ///      answer or Steam starting and stopping. Somebody who pressed
    ///      "Open revision N", updated in Vortex and came back to the Play
    ///      page touched none of those, so the card said the mods needed
    ///      updating long after they did not.
    ///   2. The updates that waited on the collection were never asked for
    ///      again. OnVersionDoc returns early while ModsMissing, with no mod
    ///      updates pending, so even a redraw that took the card down left
    ///      the release built on the new revision uninstalled and Play open
    ///      on the old one. Only Scan, which hands its feed answer back to
    ///      OnVersionDoc, ever put that right.
    ///
    /// So while the collection card or the not-confirmed note is up, the two
    /// second tick compares what Vortex has on disk (its state.v2 files and
    /// the plugin list, by name, size and write time, which is a directory
    /// listing and nothing more). Only when that changes is the revision read
    /// again, off the UI thread, because the read walks Vortex's whole state
    /// database. When the answer differs from what the card was drawn from,
    /// the card is drawn again; when the card comes down, the feed is asked
    /// again the same way the start and Scan ask it, with Play shut on
    /// CHECKING until it answers, so the waiting updates are offered, and go
    /// in by themselves when automatic updates are on.
    ///
    /// Every later change Vortex writes is looked at the same way, so the
    /// card follows Vortex to where it stops. Play's own gates (Verify, and
    /// OwnGameRefreshIfDue for Thornswood's own folder) still judge the
    /// folder Vortex left, as they always have.
    /// </summary>
    static partial class Shell
    {
        /// <summary>What Vortex had on disk at the last look, or null before the first one with the card up.</summary>
        static string vortexSeen;

        /// <summary>A look is under way on a pool thread, so the tick never starts a second one.</summary>
        static bool vortexLooking;

        /// <summary>
        /// The revision and the problem the collection card was last drawn
        /// from (DrawStatus), so a look can tell whether anything it reads
        /// would change what the card says.
        /// </summary>
        static string collectionDrawn = "";

        static string CollectionKey(int revision, string problem)
        {
            return revision + "|" + problem;
        }

        /// <summary>
        /// Vortex's state.v2 files and the plugin list Play reads, by name,
        /// size and write time. Null when the listing itself failed, which is
        /// noted and means no look this tick.
        /// </summary>
        static string VortexOnDisk()
        {
            var sb = new StringBuilder();
            try
            {
                string state = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Vortex\\state.v2");
                if (Directory.Exists(state))
                {
                    string[] files = Directory.GetFiles(state);
                    Array.Sort(files, StringComparer.OrdinalIgnoreCase);
                    foreach (string f in files)
                    {
                        var i = new FileInfo(f);
                        sb.Append(i.Name).Append('|').Append(i.Length).Append('|').Append(i.LastWriteTimeUtc.Ticks).Append('\n');
                    }
                }
                if (!string.IsNullOrEmpty(Paths.Live))
                {
                    string plugins = Path.Combine(Paths.Live, "plugins.txt");
                    if (File.Exists(plugins))
                    {
                        var i = new FileInfo(plugins);
                        sb.Append("plugins.txt|").Append(i.Length).Append('|').Append(i.LastWriteTimeUtc.Ticks).Append('\n');
                    }
                }
            }
            catch (Exception ex) { Swallow.Note("Shell.VortexOnDisk", ex); return null; }
            return sb.ToString();
        }

        /// <summary>
        /// The tick's look at Vortex while the collection card or note is up.
        /// Cheap when nothing changed: a directory listing compared with the
        /// last one.
        /// </summary>
        static void WatchVortex()
        {
            if (!collectionBarUp && !collectionNoteUp) { vortexSeen = null; return; }
            // Fix and an update paint the card themselves when they are done.
            if (vortexLooking || fixing || updating || playing) return;
            vortexLooking = true;
            string was = vortexSeen;
            ThreadPool.QueueUserWorkItem(delegate
            {
                string now = null;
                int revision = 0;
                string problem = "";
                bool look = false;
                try
                {
                    now = VortexOnDisk();
                    look = now != null && now != was;
                    if (look)
                    {
                        revision = Checks.CollectionRevision(cfg);
                        problem = CollectionProblem(revision);
                    }
                }
                catch (Exception ex) { Swallow.Note("Shell.WatchVortex", ex); look = false; }
                try
                {
                    win.Dispatcher.BeginInvoke(new Action(delegate
                    {
                        vortexLooking = false;
                        if (now == null) return;
                        vortexSeen = now;
                        if (look) VortexChanged(revision, problem);
                    }));
                }
                catch (Exception ex) { vortexLooking = false; Swallow.Note("Shell.WatchVortex, dispatch", ex); }
            });
        }

        /// <summary>
        /// On the UI thread, after a look found Vortex's files changed. Draws
        /// the card again when the revision or the problem it was drawn from
        /// moved, and asks the feed again when the card came down.
        /// </summary>
        static void VortexChanged(int revision, string problem)
        {
            if (CollectionKey(revision, problem) == collectionDrawn) return;
            // The card may have come down some other way while the look ran.
            if (!collectionBarUp && !collectionNoteUp) return;
            bool barWasUp = collectionBarUp;
            DrawStatus();
            if (!barWasUp || collectionBarUp)
            {
                if (barWasUp && revision > 0)
                    LogOnly("Vortex now has collection revision " + revision + " installed; the server's is " + Updater.FeedCollectionRevision + ".");
                return;
            }
            Log("Vortex now has collection revision " + revision + " installed, the one the server was built against. Checking for the updates that waited on it.");
            // Play stays shut on CHECKING until the feed answers, as at the
            // start: the release built on this revision may have mod updates.
            updatePending = true;
            updateAnswered = false;
            DrawStatus();
            ThreadPool.QueueUserWorkItem(delegate { CheckUpdatesBackground(false); });
        }
    }
}
