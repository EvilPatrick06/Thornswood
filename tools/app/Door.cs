using System;
using System.Threading;
using System.Windows;

namespace Thornswood
{
    /// <summary>
    /// The Discord check that stands in front of Play.
    ///
    /// Kept out of Shell.cs because it is the one thing in the launcher that
    /// can refuse to start the game, and burying that in a two thousand line
    /// file is how it ends up accidentally bypassed.
    ///
    /// It asks the site rather than deciding anything itself. The site asks
    /// Discord. So removing somebody's role, or removing them from the server,
    /// stops their next launch with nothing to remember to change anywhere.
    ///
    /// The answer is held for a few minutes so pressing Play twice is not two
    /// round trips, and not longer than that, because the whole point is that a
    /// ban lands without waiting for anybody to restart anything.
    /// </summary>
    public static class Door
    {
        const int HoldSeconds = 300;

        static DateTime clearedAt = DateTime.MinValue;

        public static bool RecentlyCleared
        {
            get { return (DateTime.Now - clearedAt).TotalSeconds < HoldSeconds; }
        }

        public static void Forget() { clearedAt = DateTime.MinValue; }

        /// <summary>
        /// Asks, off the UI thread, then calls onAllowed back ON the UI thread
        /// if the answer is yes. If the answer is no it says why and calls
        /// nothing. onRefused runs on the UI thread either way it finishes, so
        /// a disabled button can be put back.
        /// </summary>
        public static void Check(Window win, Action<string> log,
                                 Action<Standing> shout, Action onAllowed, Action onDone)
        {
            if (RecentlyCleared)
            {
                if (onAllowed != null) onAllowed();
                if (onDone != null) onDone();
                return;
            }

            log("Asking Discord whether you are still allowed in...");

            ThreadPool.QueueUserWorkItem(delegate
            {
                Standing st;
                try { st = Discord.Join(); }
                catch (Exception ex)
                {
                    st = new Standing();
                    st.Ok = false;
                    st.Why = "offline";
                    st.Message = "Could not reach thornswood.net: " + ex.Message;
                }

                win.Dispatcher.BeginInvoke(new Action(delegate
                {
                    try
                    {
                        if (st.Ok)
                        {
                            clearedAt = DateTime.Now;
                            if (st.Name != null && st.Name.Length > 0) log("Discord says yes. " + st.Name + ".");
                            else log("Discord says yes.");
                            if (onAllowed != null) onAllowed();
                            return;
                        }

                        // The site being down is not the person's fault and is
                        // not a reason to stop them playing. Everything else is.
                        if (st.Why == "offline")
                        {
                            log("thornswood.net did not answer, so letting you in on trust.");
                            clearedAt = DateTime.Now;
                            if (onAllowed != null) onAllowed();
                            return;
                        }

                        log(st.Message ?? "Discord said no.");
                        shout(st);
                    }
                    finally { if (onDone != null) onDone(); }
                }));
            });
        }

        /// <summary>The message box, kept here so the wording lives in one place.</summary>
        public static void Explain(Window win, Standing st, Action connect)
        {
            string title = "Thornswood";
            string body = st.Message ?? "Discord said no.";

            if (st.Why == "link")
            {
                body += "\n\nPress Connect Discord on the Play page, then try again.";
                MessageBox.Show(win, body, title, MessageBoxButton.OK, MessageBoxImage.Information);
                if (connect != null) connect();
                return;
            }

            if (st.Why == "guild" && st.Invite != null && st.Invite.Length > 0)
            {
                body += "\n\nOpen the Discord and join it?";
                if (MessageBox.Show(win, body, title, MessageBoxButton.YesNo,
                                    MessageBoxImage.Information) == MessageBoxResult.Yes)
                {
                    try
                    {
                        var psi = new System.Diagnostics.ProcessStartInfo(st.Invite);
                        psi.UseShellExecute = true;
                        System.Diagnostics.Process.Start(psi);
                    }
                    catch { }
                }
                return;
            }

            // banned, or a role that is not on the list. Neither is something
            // the launcher can help with, so it says so once and stops.
            MessageBox.Show(win, body, title, MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }
}
