using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

// The WPF prototype for the launcher stack study (#3209), built three ways by
// the project files beside it: .NET Framework 4.8.1 with WebView2, which is
// how the launcher draws and plays music today; .NET 10 with the music played
// by the launcher process itself; and .NET 10 with WebView2. README.md has the
// contract every prototype keeps.
static class Proto
{
    [DllImport("winmm.dll", CharSet = CharSet.Unicode)]
    static extern bool PlaySound(string file, IntPtr module, uint flags);
    const uint SND_ASYNC = 0x1, SND_LOOP = 0x8, SND_FILENAME = 0x20000;

    static readonly string Here = AppDomain.CurrentDomain.BaseDirectory;
    static TextBlock state;

    [STAThread]
    static void Main()
    {
        var app = new Application();
        var win = new Window
        {
            Title = "Thornswood " + Stack,
            Width = 1220,
            Height = 800,
            Background = new SolidColorBrush(Color.FromRgb(0x14, 0x11, 0x0e)),
            WindowStartupLocation = WindowStartupLocation.CenterScreen,
        };
#if WEBVIEW
        var view = new Microsoft.Web.WebView2.Wpf.WebView2();
        view.CoreWebView2InitializationCompleted += (s, e) =>
        {
            view.CoreWebView2.SetVirtualHostNameToFolderMapping("proto.local", Here, Microsoft.Web.WebView2.Core.CoreWebView2HostResourceAccessKind.Allow);
            view.CoreWebView2.WebMessageReceived += (s2, m) =>
            {
                string msg = m.TryGetWebMessageAsString();
                if (msg == "ready") Ready();
                else if (msg == "play") StartGame();
            };
            view.CoreWebView2.Navigate("https://proto.local/index.html");
        };
        win.Content = view;
        win.Loaded += async (s, e) => await view.EnsureCoreWebView2Async(await Microsoft.Web.WebView2.Core.CoreWebView2Environment.CreateAsync(null, Path.Combine(Path.GetTempPath(), "proto-" + Stack + "-webview")));
#else
        var grid = new Grid();
        string art = Path.Combine(Here, "art.png");
        if (File.Exists(art))
        {
            var bmp = new BitmapImage();
            bmp.BeginInit();
            bmp.UriSource = new Uri(art);
            bmp.CacheOption = BitmapCacheOption.OnLoad;
            bmp.EndInit();
            grid.Children.Add(new Image { Source = bmp, Stretch = Stretch.UniformToFill });
        }
        var panel = new StackPanel { HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(48) };
        panel.Children.Add(new TextBlock { Text = "THORNSWOOD", FontSize = 40, Foreground = new SolidColorBrush(Color.FromRgb(0xea, 0xdf, 0xc8)) });
        var play = new Button { Content = "Play", Width = 220, Height = 56, FontSize = 20, Margin = new Thickness(0, 12, 0, 12), Background = new SolidColorBrush(Color.FromRgb(0xc9, 0xa4, 0x5c)) };
        play.Click += (s, e) => { Music(); StartGame(); };
        panel.Children.Add(play);
        state = new TextBlock { Text = "Ready to launch", Foreground = Brushes.White };
        panel.Children.Add(state);
        grid.Children.Add(panel);
        win.Content = grid;
        win.ContentRendered += (s, e) =>
        {
            Ready();
            var t = new DispatcherTimer { Interval = TimeSpan.FromSeconds(4) };
            t.Tick += (s2, e2) => { t.Stop(); Music(); StartGame(); };
            t.Start();
        };
#endif
        app.Run(win);
    }

#if WEBVIEW
#if NETFRAMEWORK
    const string Stack = "wpf-net481-webview2";
#else
    const string Stack = "wpf-net10-webview2";
#endif
#else
#if NETFRAMEWORK
    const string Stack = "wpf-net481";
#else
    const string Stack = "wpf-net10";
#endif
#endif

    static void Ready()
    {
        string f = Environment.GetEnvironmentVariable("PROTO_READY");
        if (!string.IsNullOrEmpty(f)) File.WriteAllText(f, "ready");
    }

    static void Music()
    {
        PlaySound(Path.Combine(Here, "loop.wav"), IntPtr.Zero, SND_ASYNC | SND_LOOP | SND_FILENAME);
    }

    static void StartGame()
    {
        var p = Process.Start(new ProcessStartInfo("cmd.exe", "/c exit 0") { UseShellExecute = false, CreateNoWindow = true });
        if (state != null) state.Text = "Started " + p.Id;
        string f = Environment.GetEnvironmentVariable("PROTO_READY");
        if (!string.IsNullOrEmpty(f)) File.WriteAllText(f + ".active", "active");
    }
}
