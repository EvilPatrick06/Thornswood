using System;
using System.Threading;
using System.Windows;
using System.Windows.Input;
using System.Windows.Threading;

namespace Thornswood
{
    static partial class Shell
    {
        /// <summary>How many Waiting calls are still running.</summary>
        static int waitDepth;

        /// <summary>
        /// Runs <paramref name="work"/> on a pool thread and keeps the window
        /// drawing until it is done, then carries on from the next line, the
        /// same as a plain call would. The window's controls are off for the
        /// wait, so nothing can be pressed twice.
        ///
        /// Closing a stuck Skyrim waits up to nine seconds for it to go, and
        /// that wait used to happen on the window's own thread. Windows calls
        /// a window that has not answered for five seconds not responding and
        /// offers to close it. On 16 Sep it closed this launcher that way three
        /// times while the game was up (event 1002 in the Application log).
        ///
        /// Before the window is on screen there is nothing to keep drawing, and
        /// pumping messages that early would run queued startup work out of
        /// order, so the work simply runs.
        /// </summary>
        static void Waiting(Action work)
        {
            if (win == null || !win.IsVisible || !win.Dispatcher.CheckAccess()) { work(); return; }

            Exception fault = null;
            var done = new ManualResetEvent(false);
            var frame = new DispatcherFrame();
            var content = win.Content as UIElement;
            bool wasEnabled = content != null && content.IsEnabled;

            waitDepth++;
            if (waitDepth == 1)
            {
                if (content != null) content.IsEnabled = false;
                Mouse.OverrideCursor = Cursors.Wait;
            }
            try
            {
                ThreadPool.QueueUserWorkItem(delegate
                {
                    try { work(); }
                    catch (Exception ex) { fault = ex; }
                    finally
                    {
                        done.Set();
                        try { win.Dispatcher.BeginInvoke(new Action(delegate { frame.Continue = false; })); } catch { }
                    }
                });

                try { Dispatcher.PushFrame(frame); }
                catch (InvalidOperationException) { }
                // PushFrame is refused while the dispatcher is suspended, during
                // layout for one. The work still finishes; wait for it plainly.
                done.WaitOne();
            }
            finally
            {
                waitDepth--;
                if (waitDepth == 0)
                {
                    if (content != null) content.IsEnabled = wasEnabled;
                    Mouse.OverrideCursor = null;
                }
            }
            if (fault != null) throw new Exception(fault.Message, fault);
        }
    }
}
