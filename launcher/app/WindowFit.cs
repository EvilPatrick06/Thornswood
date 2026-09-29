using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;

namespace Thornswood
{
    /// <summary>
    /// Keeps a window inside the screen it is on, at any display scale (#463).
    ///
    /// Both exes are per-monitor DPI aware (PerMonitorV2 in their manifests),
    /// so WPF draws them sharp at the scale of whichever monitor they are on
    /// and keeps their size in WPF units (1/96 inch) when they move. A window
    /// laid out at 1220 by 800 units is 2440 by 1600 pixels at 200 percent,
    /// taller than a 1080 line screen, and its minimum size alone would push
    /// the bottom edge (and the buttons on it) off the screen. So the size and
    /// the minimum are clamped to the work area of the monitor the window is
    /// on, at startup and again whenever it lands on a monitor with another
    /// scale. The minimums from the markup are kept, so a bigger screen gets
    /// them back.
    ///
    /// Shared: Build-Launcher.ps1 compiles this file into the setup program as
    /// well, so it uses nothing else from launcher\app (no Swallow, no Paths).
    /// Callers wrap it in their own try and log the way their exe logs.
    /// tests\test-app-manifest.ps1 runs Clamp at 100 to 200 percent.
    /// </summary>
    static class WindowFit
    {
        /// <summary>
        /// The whole rule, in WPF units. workW/workH is the work area of the
        /// monitor (screen less taskbar). designMinW/designMinH are the
        /// window's own minimums from its markup. w and h come in as the size
        /// the window has now and go out as the size it should have.
        /// </summary>
        public static void Clamp(double workW, double workH, double designMinW, double designMinH,
                                 ref double w, ref double h, out double minW, out double minH)
        {
            minW = Math.Min(designMinW, workW);
            minH = Math.Min(designMinH, workH);
            w = Math.Max(minW, Math.Min(w, workW));
            h = Math.Max(minH, Math.Min(h, workH));
        }

        /// <summary>
        /// Clamps now, again once the window has a handle (the monitor it is
        /// really on is known then), and after every change of scale. Call it
        /// once, before the window is first shown and before it is centred.
        /// </summary>
        public static void Keep(Window win)
        {
            double designMinW = win.MinWidth, designMinH = win.MinHeight;
            Apply(win, designMinW, designMinH);
            win.SourceInitialized += delegate { Apply(win, designMinW, designMinH); };
            // WPF resizes the window to the new monitor's suggested rectangle
            // while it handles the scale change, so the clamp runs after that,
            // not inside it, or WPF's own resize would undo it.
            win.DpiChanged += delegate
            {
                win.Dispatcher.BeginInvoke(DispatcherPriority.Loaded,
                    new Action(delegate { Apply(win, designMinW, designMinH); }));
            };
        }

        static void Apply(Window win, double designMinW, double designMinH)
        {
            Rect work = WorkAreaOf(win);
            if (work.IsEmpty || work.Width <= 0 || work.Height <= 0) return;
            double w = win.Width, h = win.Height;
            if (double.IsNaN(w) || w <= 0) w = win.ActualWidth;
            if (double.IsNaN(h) || h <= 0) h = win.ActualHeight;
            double minW, minH;
            Clamp(work.Width, work.Height, designMinW, designMinH, ref w, ref h, out minW, out minH);
            win.MinWidth = minW;
            win.MinHeight = minH;
            if (win.WindowState != WindowState.Normal) return;
            if (w > 0 && Math.Abs(w - win.Width) > 0.5) win.Width = w;
            if (h > 0 && Math.Abs(h - win.Height) > 0.5) win.Height = h;
        }

        /// <summary>
        /// The work area of the monitor the window is on, in that monitor's
        /// WPF units. Before the window has a handle that is the main monitor,
        /// which is where both windows open.
        /// </summary>
        public static Rect WorkAreaOf(Window win)
        {
            var src = PresentationSource.FromVisual(win) as HwndSource;
            if (src != null && src.Handle != IntPtr.Zero && src.CompositionTarget != null)
            {
                IntPtr mon = MonitorFromWindow(src.Handle, MONITOR_DEFAULTTONEAREST);
                var mi = new MONITORINFO();
                mi.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
                if (mon != IntPtr.Zero && GetMonitorInfo(mon, ref mi))
                {
                    Matrix m = src.CompositionTarget.TransformFromDevice;
                    Point a = m.Transform(new Point(mi.rcWork.Left, mi.rcWork.Top));
                    Point b = m.Transform(new Point(mi.rcWork.Right, mi.rcWork.Bottom));
                    return new Rect(a, b);
                }
            }
            return SystemParameters.WorkArea;
        }

        /// <summary>
        /// The resize frame plus its padding, in pixels, at the scale the
        /// window is drawn at. GetSystemMetrics answers at the scale Windows
        /// started with, which is wrong on a second monitor with another scale
        /// now that the process is per-monitor aware; GetSystemMetricsForDpi
        /// (Windows 10 1607 and later) answers for the scale asked.
        /// </summary>
        public static int FramePixels(double scale)
        {
            uint dpi = (uint)Math.Round(96 * (scale > 0 ? scale : 1));
            try { return GetSystemMetricsForDpi(SM_CXSIZEFRAME, dpi) + GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi); }
            catch (EntryPointNotFoundException)
            {
                // Windows before 10.0.1607: the scale Windows started with is
                // the only answer there is.
                return GetSystemMetrics(SM_CXSIZEFRAME) + GetSystemMetrics(SM_CXPADDEDBORDER);
            }
        }

        const int SM_CXSIZEFRAME = 32, SM_CXPADDEDBORDER = 92;
        const uint MONITOR_DEFAULTTONEAREST = 2;

        [StructLayout(LayoutKind.Sequential)]
        struct RECT { public int Left, Top, Right, Bottom; }

        [StructLayout(LayoutKind.Sequential)]
        struct MONITORINFO { public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags; }

        [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint flags);
        [DllImport("user32.dll")] static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFO lpmi);
        [DllImport("user32.dll")] static extern int GetSystemMetrics(int index);
        [DllImport("user32.dll")] static extern int GetSystemMetricsForDpi(int index, uint dpi);
    }
}
