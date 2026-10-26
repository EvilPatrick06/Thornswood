using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Themes.Fluent;
using Avalonia.Threading;

// The Avalonia prototype for the launcher stack study (#3209). README.md has
// the contract every prototype keeps.
class App : Application
{
    public override void Initialize() => Styles.Add(new FluentTheme());

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
            desktop.MainWindow = Proto.MakeWindow();
        base.OnFrameworkInitializationCompleted();
    }
}

static class Proto
{
    [DllImport("winmm.dll", CharSet = CharSet.Unicode)]
    static extern bool PlaySound(string file, IntPtr module, uint flags);
    const uint SND_ASYNC = 0x1, SND_LOOP = 0x8, SND_FILENAME = 0x20000;

    static readonly string Here = AppContext.BaseDirectory;
    static TextBlock state;

    [STAThread]
    static int Main(string[] args) =>
        AppBuilder.Configure<App>().UsePlatformDetect().StartWithClassicDesktopLifetime(args);

    public static Window MakeWindow()
    {
        var win = new Window
        {
            Title = "Thornswood avalonia",
            Width = 1220,
            Height = 800,
            Background = new SolidColorBrush(Color.FromRgb(0x14, 0x11, 0x0e)),
            WindowStartupLocation = WindowStartupLocation.CenterScreen,
        };
        var grid = new Grid();
        string art = Path.Combine(Here, "art.png");
        if (File.Exists(art))
            grid.Children.Add(new Image { Source = new Bitmap(art), Stretch = Stretch.UniformToFill });
        var panel = new StackPanel { HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(48) };
        panel.Children.Add(new TextBlock { Text = "THORNSWOOD", FontSize = 40, Foreground = new SolidColorBrush(Color.FromRgb(0xea, 0xdf, 0xc8)) });
        var play = new Button { Content = "Play", Width = 220, Height = 56, FontSize = 20, Margin = new Thickness(0, 12, 0, 12), Background = new SolidColorBrush(Color.FromRgb(0xc9, 0xa4, 0x5c)) };
        play.Click += (s, e) => { Music(); StartGame(); };
        panel.Children.Add(play);
        state = new TextBlock { Text = "Ready to launch", Foreground = Brushes.White };
        panel.Children.Add(state);
        grid.Children.Add(panel);
        win.Content = grid;
        // Two animation frames after Opened: the second callback runs once the
        // first frame is drawn, as in index.html.
        win.Opened += (s, e) => win.RequestAnimationFrame(_ => win.RequestAnimationFrame(_ =>
        {
            Ready();
            DispatcherTimer.RunOnce(() => { Music(); StartGame(); }, TimeSpan.FromSeconds(4));
        }));
        return win;
    }

    static void Ready()
    {
        string f = Environment.GetEnvironmentVariable("PROTO_READY");
        if (!string.IsNullOrEmpty(f)) File.WriteAllText(f, "ready");
    }

    static void Music()
    {
        if (OperatingSystem.IsWindows())
            PlaySound(Path.Combine(Here, "loop.wav"), IntPtr.Zero, SND_ASYNC | SND_LOOP | SND_FILENAME);
    }

    static void StartGame()
    {
        var p = OperatingSystem.IsWindows()
            ? Process.Start(new ProcessStartInfo("cmd.exe", "/c exit 0") { UseShellExecute = false, CreateNoWindow = true })
            : Process.Start(new ProcessStartInfo("/bin/true") { UseShellExecute = false });
        state.Text = "Started " + p.Id;
        string f = Environment.GetEnvironmentVariable("PROTO_READY");
        if (!string.IsNullOrEmpty(f)) File.WriteAllText(f + ".active", "active");
    }
}
