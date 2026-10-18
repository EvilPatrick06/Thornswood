using System;
using System.Collections.Generic;
using System.Threading;
using System.Windows;

namespace Thornswood
{
    // The update check, the feed notice, the in-play update clock, and the
    // Install path that applies pending packs (and the launcher self-update).
    // They live apart from Shell.cs because they are one self-contained
    // slice, and Shell.cs was long enough (#500).
    static partial class Shell
    {
        static List<Pack> pendingPacks = new List<Pack>();
        static bool selfUpdateOffered;
        static bool retryQueued;
        static bool checkingInPlay = false;
        // #2440: one long-poll tip to /feed/watch while the shell is up.
        static bool feedWatchStarted;
        static volatile bool feedWatchStop;

        // Said once in launcher.log, not every thirty seconds: which feed the
        // checks read, and the first in play check that could not be made.
        // Both were invisible before (#445): the address was nowhere in the
        // log, and the in play catch was empty, so a launcher that had spent
        // the hour's sixty anonymous GitHub requests looked exactly like one
        // that had checked and found nothing.
        static string feedSaid = "";
        static bool inPlayFailSaid;
        static bool notChangedSaid;

        /// <summary>
        /// Keeps one long-poll open against the site's /feed/watch (#2440).
        /// When the tip says the feed moved, runs the same full check the
        /// start path uses, so an open launcher shows a Ship without Restart
        /// or Check now. Started once; stopped when the window closes.
        /// </summary>
        static void StartFeedWatch()
        {
            if (feedWatchStarted) return;
            feedWatchStarted = true;
            feedWatchStop = false;
            ThreadPool.QueueUserWorkItem(delegate
            {
                int failSleep = 5000;
                LogOnly("Watching " + Updater.WatchUrl(cfg) + " for a release while this launcher stays open.");
                while (!feedWatchStop)
                {
                    try
                    {
                        bool changed = Updater.WaitForFeedChange(cfg);
                        failSleep = 5000;
                        if (feedWatchStop) break;
                        if (changed)
                        {
                            LogOnly("The update feed tip said the feed moved; checking now.");
                            CheckUpdatesBackground(false);
                        }
                        // 204, the wait ran out unchanged: tip again at once.
                        // A timeout or any other answer threw, below.
                    }
                    catch (Exception ex)
                    {
                        if (feedWatchStop) break;
                        LogOnly("The update feed tip could not be kept open (" + ex.Message + "). Trying again in " + (failSleep / 1000) + " seconds.");
                        Thread.Sleep(failSleep);
                        failSleep = Math.Min(failSleep * 2, 60000);
                    }
                }
            });
        }

        static void StopFeedWatch()
        {
            feedWatchStop = true;
        }
        static void CheckUpdatesBackground(bool loud)
        {
            try
            {
                VersionDoc v = Updater.Check(cfg);
                if (v == null) { win.Dispatcher.BeginInvoke(new Action(delegate { CheckFailed("the update source had nothing to say"); })); return; }
                // The news file the feed names, if any, here on the check's own
                // thread, so the News tab has it (#1050, FeedNews.cs). Never throws.
                Updater.FillNews(cfg, v);
                win.Dispatcher.BeginInvoke(new Action(delegate { OnVersionDoc(v, loud); }));
            }
            catch (Exception ex)
            {
                string why = ex.Message;
                win.Dispatcher.BeginInvoke(new Action(delegate { CheckFailed(why); }));
            }
        }

        /// <summary>
        /// The source did not answer, so it is not known whether this build is
        /// current, and Play stays shut with the reason on the button. One
        /// retry is queued at a time, thirty seconds out.
        /// </summary>
        static void CheckFailed(string why)
        {
            checkFailed = true;
            updatePending = true;
            updateAnswered = true;
            Log("Could not check for updates: " + why + ". Play stays shut until the update source answers; trying again in 30 seconds.");
            DrawStatus();
            if (retryQueued) return;
            retryQueued = true;
            ThreadPool.QueueUserWorkItem(delegate
            {
                Thread.Sleep(30000);
                retryQueued = false;
                CheckUpdatesBackground(false);
            });
        }

        /// <summary>
        /// The feed's message in the bar above Play, and the hold on Play when
        /// the feed asks for one. Entry 262: until this the message was one
        /// Log line that scrolled away, so there was no way to say anything to
        /// everybody when something outside the build broke.
        ///
        /// Only ever called with a document that was read, which is what keeps
        /// the hold from coming out of a failed check. Every call replaces the
        /// last answer, so a feed that drops the message or the maintenance
        /// flag takes the bar and the hold away with it. DrawStatus, which
        /// every path through OnVersionDoc reaches, puts the button right.
        /// </summary>
        static void ShowNotice(VersionDoc v)
        {
            FeedNotice was = feedNotice;
            feedNotice = FeedNotice.From(v, Updater.Version);
            if (noticeBar != null)
            {
                noticeBar.Visibility = feedNotice.Title == null ? Visibility.Collapsed : Visibility.Visible;
                noticeBar.BorderBrush = Res(feedNotice.Hold != null ? "Bad" : "Accent");
            }
            if (txtNoticeTitle != null) txtNoticeTitle.Text = feedNotice.Title == null ? "" : feedNotice.Title;
            if (txtNoticeNote != null) txtNoticeNote.Text = feedNotice.Text;

            // Once in the log when it changes, so a report still shows what the
            // bar said, without a line on every check.
            if (feedNotice.Title != null && (feedNotice.Title != was.Title || feedNotice.Text != was.Text))
                Log(feedNotice.Title + ". " + feedNotice.Text);
            if (was.Hold != null && feedNotice.Hold == null)
                Log("The update feed no longer holds Play.");
        }

        static void OnVersionDoc(VersionDoc v, bool loud)
        {
            checkFailed = false;
            pendingDoc = v;

            // Where the answer came from, once, and again if it ever changes.
            // A line in launcher.log naming thornswood.net is what says where
            // the checks go. Until #907 a line naming api.github.com said the
            // site feed was missing and the GitHub fallback was carrying it;
            // that fallback went with Thornswood-Releases.
            if (feedSaid != Updater.LastFeedUrl)
            {
                feedSaid = Updater.LastFeedUrl;
                LogOnly("Update checks read " + feedSaid + ".");
            }

            bool install = installWhenSeen;
            installWhenSeen = false;

            bool moved = false;
            if (!string.IsNullOrEmpty(v.serverAddress) && v.serverAddress != cfg.ServerAddress) { cfg.ServerAddress = v.serverAddress; moved = true; }
            if (!string.IsNullOrEmpty(v.collectionUrl) && v.collectionUrl != cfg.CollectionUrl) { cfg.CollectionUrl = v.collectionUrl; moved = true; }
            if (!string.IsNullOrEmpty(v.serverPort) && v.serverPort != cfg.ServerPort) { cfg.ServerPort = v.serverPort; moved = true; }
            if (v.maxOnline > 0 && v.maxOnline != cfg.MaxOnline) { cfg.MaxOnline = v.maxOnline; moved = true; }
            if (moved)
            {
                cfg.Save(Paths.CfgFile);
                PaintServerBoxes();
                Log("The server moved. The launcher already has the new address.");
                StartPing();
            }

            // Which collection revision this release agrees with. Not a
            // setting and never written to config.json: it is a fact about the
            // server that belongs to the feed it came from, and a stale copy
            // outliving its release is exactly the failure this replaced.
            Updater.FeedCollectionRevision = v.collectionRevision;

            // Quietly, and without a line in the log. Nobody set these and
            // nobody needs telling they changed.
            bool quiet = false;
            if (!string.IsNullOrEmpty(v.voicePort) && v.voicePort != cfg.VoicePort)
            {
                cfg.VoicePort = v.voicePort; quiet = true;
            }
            // updateRepo is no longer read: it named the GitHub fallback, which
            // went with Thornswood-Releases (#907). A feed can still announce a
            // move of the site feed by shipping the new URL under the old one.
            if (!string.IsNullOrEmpty(v.updateFeedUrl) && v.updateFeedUrl != cfg.UpdateFeedUrl)
            {
                cfg.UpdateFeedUrl = v.updateFeedUrl; quiet = true;
            }
            // The Discord presence card's application, the site its buttons
            // point at, and the picture on it.
            if (!string.IsNullOrEmpty(v.discordAppId) && v.discordAppId != cfg.DiscordAppId) { cfg.DiscordAppId = v.discordAppId; quiet = true; }
            if (!string.IsNullOrEmpty(v.siteUrl) && v.siteUrl != cfg.SiteUrl) { cfg.SiteUrl = v.siteUrl; quiet = true; }
            // Not IsNullOrEmpty, deliberately. An empty voiceUrl in the feed
            // puts the launcher back on the built-in address (Config.Voice);
            // it used to send it back to the raw port, which is shut (#1304).
            // Null means the feed did not mention it.
            if (v.voiceUrl != null && v.voiceUrl != cfg.VoiceUrl) { cfg.VoiceUrl = v.voiceUrl; quiet = true; }
            if (!string.IsNullOrEmpty(v.presenceImage) && v.presenceImage != cfg.PresenceImage) { cfg.PresenceImage = v.presenceImage; quiet = true; }
            // The Skyrim build the checks and the Downgrade button look for
            // (#471). A feed without it leaves what the launcher was built with.
            if (Downgrade.AdoptPin(cfg, v)) { LogOnly("Took the Skyrim build from the update feed: SkyrimSE.exe of " + cfg.ExpectedExeBytes + " bytes, and the depots the Downgrade button asks Steam for."); quiet = true; }
            if (quiet)
            {
                cfg.Save(Paths.CfgFile);
                if (txtUpdateSource != null) txtUpdateSource.Text = Updater.FeedUrl(cfg);
                DrawVoiceState();
            }
            ShowNotice(v);
            BuildNews();

            // The add-ons are drawn straight from this document, so redraw
            // them when the check lands: the Mods page's tab if somebody is
            // sitting on it, and their place on Diagnostics (#1170).
            if (modTab == 3) BuildModList();
            DrawAddons();

            // Packs a launcher before 1.1.32 marked as applied on a collection
            // install without writing a single game file. Back into the queue
            // they go, and this time they land. See Updater.Requeue.
            int again = Updater.Requeue();
            if (again > 0)
                Log(again + (again == 1 ? " earlier update" : " earlier updates") +
                    " never reached the game folder on this install, a launcher fault fixed in " +
                    Updater.Version + ". " + (again == 1 ? "It goes" : "They go") +
                    " in again with this update.");
            pendingPacks = Updater.Pending(v);
            bool newLauncher = Updater.IsNewer(v.launcherVersion, Updater.Version)
                               && !string.IsNullOrEmpty(v.launcherUrl);
            // Scan and Fix's card goes by the same answer (#2627), so the Fix
            // button knows about an update waiting without Scan being pressed.
            FeedOnCard(v);

            // Before a word is said about updates. An update into a build with
            // no mods in it cannot work, and reporting that it failed when the
            // cause is an uninstalled collection sends somebody looking for a
            // problem that is not there.
            if (ModsMissing())
            {
                if (!newLauncher)
                {
                    updatePending = false;
                    updateAnswered = true;
                    if (Downgrade.Needed(cfg))
                    {
                        DrawStatus();
                        Log("The collection is not installed yet and Skyrim is on the wrong build. The downgrade comes first; the collection card follows it. Updates wait until both are done.");
                        return;
                    }
                    ShowCollectionBar();
                    DrawStatus();
                    Log("The collection is not installed yet. Updates wait until it is.");
                    return;
                }
                // The launcher itself needs no mods to update. Holding it back
                // with the packs left a machine whose Vortex was on another
                // server's profile stuck on an old launcher for good, and the
                // fix for that (this line) could never reach it. The packs
                // still wait; the exe goes ahead.
                pendingPacks = new List<Pack>();
                collectionBarUp = false;
                Log("The collection is not installed yet. The mod updates wait until it is; the launcher update goes ahead.");
            }
            else
            {
                collectionBarUp = false;
            }
            btnInstallNow.Content = "Install now";

            if (pendingPacks.Count == 0 && !newLauncher)
            {
                updateBar.Visibility = Visibility.Collapsed;
                btnInstallNow.Visibility = Visibility.Collapsed;
                updatePending = false;
                updateAnswered = true;
                DrawStatus();
                if (loud || !moved) Log("Up to date.");
                return;
            }
            updatePending = true;
            updateAnswered = true;
            DrawStatus();

            selfUpdateOffered = newLauncher;
            var parts = new List<string>();
            if (newLauncher) parts.Add("launcher " + v.launcherVersion);
            if (pendingPacks.Count > 0) parts.Add(pendingPacks.Count + (pendingPacks.Count == 1 ? " mod update" : " mod updates"));
            txtUpdateTitle.Text = "Update available";
            string note = string.Join(", ", parts.ToArray());
            if (pendingPacks.Count > 0 && !string.IsNullOrEmpty(pendingPacks[0].notes))
                note += "  ·  " + pendingPacks[0].notes;
            txtUpdateNote.Text = note;
            updateBar.Visibility = Visibility.Visible;
            btnInstallNow.Visibility = Visibility.Visible;
            Log("Update available. Install it from the card above the Play button, or in Settings.");

            // The game was just closed for this. With automatic updates on it
            // goes in now, so the person is back in the world in a minute
            // rather than looking at a card.
            if (install && cfg.AutoUpdate)
            {
                Log("Installing it now.");
                RunUpdate();
            }
        }

        /// <summary>
        /// The update check that runs while the game is up. It only decides
        /// whether an update exists; the cards, the addresses and the rest of
        /// what a version document brings wait for OnVersionDoc, after the
        /// game is gone. First sight starts a five minute clock and says so in
        /// the log; when it runs out the game is closed and the tick's closed
        /// path takes it from there.
        /// </summary>
        static void CheckUpdatesInPlay()
        {
            if (checkingInPlay) return;
            checkingInPlay = true;
            ThreadPool.QueueUserWorkItem(delegate
            {
                bool due = false;
                // A check that could not be made is not a check that said no.
                // GitHub answers 403 once the hour's requests are spent, and a
                // thrown check landed below looking exactly like "no update",
                // so it wiped the five minute clock every two minutes and the
                // countdown the server was already running never ran out on
                // this machine. True until a document actually comes back.
                bool failed = true;
                string what = "";
                try
                {
                    VersionDoc v = Updater.Check(cfg);
                    if (v != null)
                    {
                        failed = false;
                        // Once a session, so launcher.log can show the feed's
                        // ETag doing its job: a check that cost a few bytes and
                        // one that downloaded the whole ninety kilobyte
                        // document look identical from the outside (#445).
                        if (Updater.LastNotModified && !notChangedSaid)
                        {
                            notChangedSaid = true;
                            LogOnly("The update feed answered that nothing has changed, so this check cost " +
                                    "a few bytes instead of the whole feed. This is said once a session.");
                        }
                        List<Pack> packs = Updater.Pending(v);
                        bool newLauncher = Updater.IsNewer(v.launcherVersion, Updater.Version)
                                           && !string.IsNullOrEmpty(v.launcherUrl);
                        due = packs.Count > 0 || newLauncher;
                        var parts = new List<string>();
                        if (newLauncher) parts.Add("launcher " + v.launcherVersion);
                        if (packs.Count > 0) parts.Add(packs.Count + (packs.Count == 1 ? " mod update" : " mod updates"));
                        what = string.Join(", ", parts.ToArray());
                    }
                }
                catch (Exception ex)
                {
                    // Once a session, in launcher.log only (#445). This catch
                    // was empty, so a launcher that had spent the hour's sixty
                    // anonymous GitHub requests left no line anywhere and
                    // looked exactly like one that had checked and found
                    // nothing: a search of launcher.log for the rate limit
                    // wording found nothing on any machine. Every thirty
                    // seconds would be a hundred and twenty lines an hour, so
                    // the first one is the one that is kept, and the clock is
                    // left alone either way by the failed flag above.
                    if (!inPlayFailSaid)
                    {
                        inPlayFailSaid = true;
                        LogOnly("The update check could not be made while the game runs, reading " +
                                Updater.LastFeedUrl + ". It runs again in thirty seconds, and this " +
                                "is said once a session. What came back: " + ex.Message);
                    }
                }
                try
                {
                    win.Dispatcher.BeginInvoke(new Action(delegate
                    {
                        checkingInPlay = false;
                        // Leave the clock alone when there was no answer. Only
                        // a check that came back and found nothing clears it.
                        if (failed) return;
                        if (!playing || !due) { updateSeenAt = DateTime.MinValue; return; }
                        if (updateSeenAt == DateTime.MinValue)
                        {
                            updateSeenAt = DateTime.Now;
                            Log("An update went out while you were playing (" + what + "). The server is telling everybody the same. When its countdown ends, in about four and a half minutes, the game closes so the launcher can install it.");
                            return;
                        }
                        // Ship tells the server five minutes right after the
                        // pack goes out, and the pack is seen within thirty
                        // seconds of that, so four and a half minutes from
                        // first sight is the server's zero, give or take the
                        // poll. Nobody is left in a world the room has moved
                        // past: the server says out, and the game goes.
                        if ((DateTime.Now - updateSeenAt).TotalMinutes < 4.5) return;
                        if (!Checks.GameRunning()) return;
                        closedForUpdate = true;
                        Log("Closing the game for the update (" + what + ").");
                        bool still = false;
                        Waiting(delegate { Checks.CloseGame(); still = Checks.GameRunning(); });
                        if (still)
                        {
                            closedForUpdate = false;
                            Log("Skyrim would not close. Quit it yourself and the update goes in.");
                        }
                    }));
                }
                catch { checkingInPlay = false; }
            });
        }

        static void RunUpdate() { RunUpdate(null); }

        /// <param name="after">Run on the window's thread when the update has gone in or failed without restarting the launcher, or null. Fix takes the update last and scans again after it (#2627).</param>
        static void RunUpdate(Action after)
        {
            if (playing) { Log("Quit the game first."); return; }
            // An update writes into the build. A game still holding files open
            // down there turns that into a half written install.
            if (!ClearStuckGame(true)) return;
            btnUpdate.IsEnabled = false;
            btnInstallNow.IsEnabled = false;
            btnPlay.IsEnabled = false;
            txtUpdateTitle.Text = "Updating";
            var doc = pendingDoc;
            var packs = pendingPacks;
            bool withLauncher = selfUpdateOffered;
            // The Play button shows how far it has got (#1145). One download
            // per pack with a link; a release synced to its record says its
            // own counts from Sync.cs.
            int downloads = 0;
            foreach (Pack p in packs)
                if (p != null && !string.IsNullOrEmpty(p.url) && p.url.Trim().Length > 0) downloads++;
            // Second, so a folder being prepared keeps the button (#2210).
            PlayProgress.Second(true);
            try { PlayProgress.Begin("Updating", downloads); }
            finally { PlayProgress.Second(false); }
            DrawStatus();
            // Decided by Patrick on 12 Oct (#2210): the update downloads while
            // Thornswood's own Skyrim folder is prepared, and goes in once that
            // is done. Until then this refused here and the download waited
            // for the whole refresh.
            if (ownGameBusy)
                Log("Thornswood's own Skyrim folder is being prepared. The update downloads now and goes in as soon as the folder is ready.");

            ThreadPool.QueueUserWorkItem(delegate
            {
                Action<string> log = delegate(string m)
                {
                    win.Dispatcher.BeginInvoke(new Action(delegate { Log(m); }));
                };
                Updater.Fetched got = null;
                // What this thread reports stays off the Play button while the
                // folder is being prepared (PlayProgress.FolderFirst).
                PlayProgress.Second(true);
                try
                {
                    // The download: nothing in the game folder or its records
                    // changes, so it runs beside a refresh.
                    got = Updater.FetchUpdate(cfg, packs, withLauncher ? doc : null, log);
                    // The write: after a refresh under way, and none starts
                    // until it is done (OwnGame.Alone).
                    Updater.Fetched write = got;
                    OwnGame.Alone(delegate { Updater.WriteUpdate(cfg, write, log); },
                        delegate { log("The update is downloaded. It goes in as soon as Thornswood's own Skyrim folder is ready."); });

                    string launcher = Updater.LauncherOf(got);
                    if (launcher != null)
                    {
                        log("Updating the launcher. It will restart.");
                        got = null;
                        Updater.SwapIn(launcher, log);
                        win.Dispatcher.BeginInvoke(new Action(delegate { win.Close(); }));
                        return;
                    }

                    win.Dispatcher.BeginInvoke(new Action(delegate
                    {
                        updateBar.Visibility = Visibility.Collapsed;
                        btnInstallNow.Visibility = Visibility.Collapsed;
                        Stats.LastUpdate = DateTime.Now.ToString("d MMM HH:mm");
                        Stats.Save();
                        BuildStatRow();
                        btnUpdate.IsEnabled = true;
                        PlayProgress.End();
                        updatePending = false;
                        DrawStatus(); BuildModList();
                        Log("Update finished.");
                        if (after != null) after();
                    }));
                }
                catch (Exception ex)
                {
                    Updater.Drop(got);
                    win.Dispatcher.BeginInvoke(new Action(delegate
                    {
                        Log("Update failed: " + ex.Message);
                        // Everything before the pack that broke is in. Without
                        // this the card still counts them and pressing Update
                        // again unpacks them a second time, which rewrites each
                        // one's file list with every path marked as one the pack
                        // wrote over, so a later Remove leaves its own files.
                        pendingPacks = Updater.Pending(doc);
                        txtUpdateTitle.Text = "Update failed";
                        btnUpdate.IsEnabled = true;
                        btnInstallNow.IsEnabled = true;
                        PlayProgress.End();
                        DrawStatus();
                        Log("Play stays off until the update goes through, because the server is expecting the newer mod list.");
                        if (after != null) after();
                    }));
                }
                finally { PlayProgress.Second(false); }
            });
        }
    }
}
