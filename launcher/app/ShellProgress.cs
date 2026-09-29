using System;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;

namespace Thornswood
{
    /// <summary>
    /// The Play button as a progress bar (#1145): while the launcher prepares
    /// Thornswood's own game folder, puts an update in or checks files, the
    /// button fills from the left and says what it is doing and how far it
    /// has got. PlayBar in Progress.cs decides the words and the fill; this
    /// only paints them, at most every PlayBar.DrawEveryMs.
    ///
    /// The fill is "fill" in the Primary style's template in ui.xaml, behind
    /// the text: the accent colour, faded, with a solid accent line along its
    /// bottom edge. The button is off while it runs, so its face is the Card
    /// colour, and the text is drawn in Ink so it reads on both.
    /// </summary>
    static partial class Shell
    {
        static readonly PlayBar playBar = new PlayBar();
        static DispatcherTimer playBarTimer;
        static int playBarTicking;
        static FrameworkElement playFill;
        static TranslateTransform playFillSlide;
        static bool playFillMoving;

        static void WireProgress()
        {
            PlayProgress.Sink = delegate(ProgressStep s)
            {
                if (s == null) playBar.Stop(); else playBar.Offer(s);
                WakePlayBar();
            };
            if (btnPlay != null)
                btnPlay.SizeChanged += delegate { if (playBar.Active) PaintPlayFill(true); };
        }

        // From any thread: make sure the timer is running. One BeginInvoke
        // per run, not one per report.
        static void WakePlayBar()
        {
            if (Interlocked.CompareExchange(ref playBarTicking, 1, 0) != 0) return;
            try { win.Dispatcher.BeginInvoke(new Action(StartPlayBarTimer)); }
            catch (Exception ex) { Interlocked.Exchange(ref playBarTicking, 0); Swallow.Note("Shell.WakePlayBar", ex); }
        }

        static void StartPlayBarTimer()
        {
            if (playBarTimer == null)
            {
                playBarTimer = new DispatcherTimer(DispatcherPriority.Background);
                playBarTimer.Interval = TimeSpan.FromMilliseconds(PlayBar.DrawEveryMs);
                playBarTimer.Tick += delegate { PlayBarTick(); };
            }
            playBarTimer.Start();
            PlayBarTick();
        }

        static void PlayBarTick()
        {
            if (playBar.TakeDirty()) DrawPlayBar();
            if (playBar.Active) return;
            playBarTimer.Stop();
            Interlocked.Exchange(ref playBarTicking, 0);
            // A report that landed between the two lines above.
            if (playBar.Dirty) WakePlayBar();
        }

        static void DrawPlayBar()
        {
            if (btnPlay == null) return;
            bool active; string text; double fill;
            playBar.Read(out active, out text, out fill);
            if (active && !playing)
            {
                btnPlay.IsEnabled = false;
                btnPlay.Content = PlayBarCaption(text);
                btnPlay.ToolTip = "Play comes back when this is done.";
                btnPlay.SetResourceReference(Control.ForegroundProperty, "Ink");
                PaintPlayFill(false);
                return;
            }
            HidePlayFill();
            // Back to whatever the button says without it: Play, or the reason
            // it is off, a failed update included.
            DrawStatus();
        }

        // The button's other words are in capitals; so are these.
        static string PlayBarCaption(string text)
        {
            return (text ?? "").ToUpperInvariant();
        }

        static bool FindPlayFill()
        {
            if (playFill != null) return true;
            if (btnPlay == null || btnPlay.Template == null) return false;
            btnPlay.ApplyTemplate();
            playFill = btnPlay.Template.FindName("fill", btnPlay) as FrameworkElement;
            if (playFill == null) return false;
            playFillSlide = new TranslateTransform();
            playFill.RenderTransform = playFillSlide;
            return true;
        }

        static void PaintPlayFill(bool resized)
        {
            if (!FindPlayFill()) return;
            double f = playBar.Fill;
            double w = btnPlay.ActualWidth;
            playFill.Visibility = Visibility.Visible;
            if (f >= 0)
            {
                if (playFillMoving) { playFillSlide.BeginAnimation(TranslateTransform.XProperty, null); playFillSlide.X = 0; playFillMoving = false; }
                playFill.Width = Math.Max(0, Math.Min(1.0, f)) * w;
                return;
            }
            // Nobody knows the total yet: a quarter of the button sliding
            // steadily from end to end and back.
            if (playFillMoving && !resized) return;
            double band = w / 4;
            playFill.Width = band;
            var slide = new DoubleAnimation(0, Math.Max(0, w - band), new Duration(TimeSpan.FromMilliseconds(1400)));
            slide.AutoReverse = true;
            slide.RepeatBehavior = RepeatBehavior.Forever;
            slide.EasingFunction = new SineEase { EasingMode = EasingMode.EaseInOut };
            playFillSlide.BeginAnimation(TranslateTransform.XProperty, slide);
            playFillMoving = true;
        }

        static void HidePlayFill()
        {
            if (btnPlay != null) btnPlay.ClearValue(Control.ForegroundProperty);
            if (playFill == null) return;
            if (playFillMoving) { playFillSlide.BeginAnimation(TranslateTransform.XProperty, null); playFillSlide.X = 0; playFillMoving = false; }
            playFill.Width = 0;
            playFill.Visibility = Visibility.Collapsed;
        }
    }
}
