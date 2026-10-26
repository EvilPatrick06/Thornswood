using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;

// The WinUI 3 prototype for the launcher stack study (#3209), unpackaged.
// README.md has the contract every prototype keeps.
class App : Application
{
    [DllImport("winmm.dll", CharSet = CharSet.Unicode)]
    static extern bool PlaySound(string file, IntPtr module, uint flags);
    const uint SND_ASYNC = 0x1, SND_LOOP = 0x8, SND_FILENAME = 0x20000;

    static readonly string Here = AppContext.BaseDirectory;
    Window win;
    TextBlock state;
    bool fired;

    [STAThread]
    static void Main()
    {
        WinRT.ComWrappersSupport.InitializeComWrappers();
        Application.Start(p =>
        {
            var context = new Microsoft.UI.Dispatching.DispatcherQueueSynchronizationContext(Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread());
            System.Threading.SynchronizationContext.SetSynchronizationContext(context);
            new App();
        });
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        Resources.MergedDictionaries.Add(new XamlControlsResources());
        win = new Window { Title = "Thornswood winui3" };
        win.AppWindow.Resize(new Windows.Graphics.SizeInt32(1220, 800));
        var grid = new Grid { Background = new SolidColorBrush(ColorHelper.FromArgb(255, 0x14, 0x11, 0x0e)) };
        string art = Path.Combine(Here, "art.png");
        // BitmapImage decodes off the window's thread, so the first frame is
        // counted once the art has opened, as the other prototypes do.
        if (File.Exists(art))
        {
            var image = new Image { Source = new BitmapImage(new Uri(art)), Stretch = Stretch.UniformToFill };
            image.ImageOpened += (s, e) => CompositionTarget.Rendering += FirstFrame;
            image.ImageFailed += (s, e) => CompositionTarget.Rendering += FirstFrame;
            grid.Children.Add(image);
        }
        else
            CompositionTarget.Rendering += FirstFrame;
        var panel = new StackPanel { HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(48), Spacing = 12 };
        panel.Children.Add(new TextBlock { Text = "THORNSWOOD", FontSize = 40, Foreground = new SolidColorBrush(ColorHelper.FromArgb(255, 0xea, 0xdf, 0xc8)) });
        var play = new Button { Content = "Play", Width = 220, Height = 56, FontSize = 20 };
        play.Click += (s, e) => { Music(); StartGame(); };
        panel.Children.Add(play);
        state = new TextBlock { Text = "Ready to launch", Foreground = new SolidColorBrush(Colors.White) };
        panel.Children.Add(state);
        grid.Children.Add(panel);
        win.Content = grid;
        win.Activate();
    }

    void FirstFrame(object sender, object e)
    {
        if (fired) return;
        fired = true;
        CompositionTarget.Rendering -= FirstFrame;
        string f = Environment.GetEnvironmentVariable("PROTO_READY");
        if (!string.IsNullOrEmpty(f)) File.WriteAllText(f, "ready");
        var t = win.DispatcherQueue.CreateTimer();
        t.Interval = TimeSpan.FromSeconds(4);
        t.IsRepeating = false;
        t.Tick += (s, e2) => { Music(); StartGame(); };
        t.Start();
    }

    static void Music() => PlaySound(Path.Combine(Here, "loop.wav"), IntPtr.Zero, SND_ASYNC | SND_LOOP | SND_FILENAME);

    void StartGame()
    {
        var p = Process.Start(new ProcessStartInfo("cmd.exe", "/c exit 0") { UseShellExecute = false, CreateNoWindow = true });
        state.Text = "Started " + p.Id;
        string f = Environment.GetEnvironmentVariable("PROTO_READY");
        if (!string.IsNullOrEmpty(f)) File.WriteAllText(f + ".active", "active");
    }
}
