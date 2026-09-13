using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Text;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace SkyrimTogetherSetup
{
    /// <summary>Presents a slice of a bigger file as if it were the whole thing.</summary>
    class SliceStream : Stream
    {
        readonly Stream inner;
        readonly long start, len;
        public SliceStream(Stream s, long offset, long length) { inner = s; start = offset; len = length; inner.Position = offset; }

        public override bool CanRead { get { return true; } }
        public override bool CanSeek { get { return true; } }
        public override bool CanWrite { get { return false; } }
        public override long Length { get { return len; } }
        public override long Position
        {
            get { return inner.Position - start; }
            set { inner.Position = start + value; }
        }
        public override int Read(byte[] b, int o, int c)
        {
            long left = len - Position;
            if (left <= 0) return 0;
            if (c > left) c = (int)left;
            return inner.Read(b, o, c);
        }
        public override long Seek(long offset, SeekOrigin origin)
        {
            long p = origin == SeekOrigin.Begin ? offset
                   : origin == SeekOrigin.Current ? Position + offset
                   : len + offset;
            Position = p;
            return p;
        }
        public override void Flush() { }
        public override void SetLength(long v) { throw new NotSupportedException(); }
        public override void Write(byte[] b, int o, int c) { throw new NotSupportedException(); }
        protected override void Dispose(bool d) { if (d) inner.Dispose(); base.Dispose(d); }
    }

    class Payload
    {
        public string File;     // the file the zip lives in
        public long Offset;     // where it starts inside that file
        public long Length;
    }

    static class Setup
    {
        const string Magic = "STSFX001";
        const int TrailerLen = 24;          // 8 magic + 8 offset + 8 length

        // Windows will not load an executable anywhere near this payload's size,
        // so it ships as a zip beside this program rather than inside it. The
        // attached form is still read, for builds small enough to carry one.
        static readonly string[] PayloadNames = { "SkyrimTogether-Setup.zip", "payload.zip" };

        static Window win;
        static TextBlock txtHead, txtBody, txtFound, txtStat;
        static Border foundBox;
        static ProgressBar bar;
        static Button btnGo, btnClose;
        static string temp;

        // Where the build ends up. The drive matters more than the folder to
        // most people, so the drives are offered as buttons and the full path
        // is only there to be read back.
        static string installRoot = @"C:\SkyrimTogether";
        static TextBlock txtRoot, txtRoom;
        static WrapPanel driveRow;
        static Button btnPick;
        static bool running;

        [STAThread]
        static void Main()
        {
            try { Run(); }
            catch (Exception ex)
            {
                MessageBox.Show(ex.Message, "Thornswood Setup", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        static Payload cachedPayload;
        static bool payloadScanned;

        /// <summary>Locate is a directory scan, so it happens once rather than on every click.</summary>
        static Payload FindPayload()
        {
            if (payloadScanned) return cachedPayload;
            payloadScanned = true;
            try { cachedPayload = Locate(System.Reflection.Assembly.GetExecutingAssembly().Location); }
            catch { cachedPayload = null; }
            return cachedPayload;
        }

        /// <summary>How much room the whole install wants, from the size of the payload.</summary>
        static long Needed(long payloadBytes)
        {
            // Unpacked is roughly twice the zip, and the copy of Skyrim on top
            // of that is a little over half again. Three times the zip is the
            // honest number and it is better to say so before starting.
            return payloadBytes * 3L;
        }

        static void BuildDrives()
        {
            driveRow.Children.Clear();
            DriveInfo[] all;
            try { all = DriveInfo.GetDrives(); } catch { return; }

            foreach (DriveInfo d in all)
            {
                DriveInfo captured = d;
                long free;
                try
                {
                    if (d.DriveType != DriveType.Fixed || !d.IsReady) continue;
                    free = d.AvailableFreeSpace;
                }
                catch { continue; }

                var letter = new TextBlock();
                letter.Text = d.Name.TrimEnd('\\');
                letter.FontFamily = new FontFamily("Cascadia Mono, Consolas");
                letter.FontSize = 14;
                letter.Foreground = B("#EDE5D8");

                var room = new TextBlock();
                room.Text = Gb(free) + " free";
                room.FontSize = 11;
                room.Foreground = B("#9C8D79");
                room.Margin = new Thickness(0, 3, 0, 0);

                var sp = new StackPanel();
                sp.Children.Add(letter);
                sp.Children.Add(room);

                var b = new Button();
                b.Content = sp;
                b.Style = (Style)win.Resources["Btn"];
                b.Padding = new Thickness(15, 9, 15, 9);
                b.Margin = new Thickness(0, 0, 8, 8);
                b.MinWidth = 104;
                b.HorizontalContentAlignment = HorizontalAlignment.Left;
                b.Tag = captured.Name;
                b.BorderBrush = B("#2C251D");
                b.Background = B("#0A0807");
                b.Foreground = B("#EDE5D8");
                b.Click += delegate { SetRoot(Path.Combine(captured.Name, "SkyrimTogether")); };
                driveRow.Children.Add(b);
            }
        }

        static void SetRoot(string path)
        {
            if (string.IsNullOrEmpty(path)) return;
            installRoot = path.TrimEnd('\\');
            txtRoot.Text = installRoot;

            string root = "";
            try { root = Path.GetPathRoot(installRoot); } catch { }

            foreach (object o in driveRow.Children)
            {
                var b = o as Button;
                if (b == null) continue;
                bool on = string.Equals((string)b.Tag, root, StringComparison.OrdinalIgnoreCase);
                b.Background = B(on ? "#262019" : "#0A0807");
                b.BorderBrush = B(on ? "#C8763A" : "#2C251D");
            }

            long free = -1;
            try { free = new DriveInfo(root).AvailableFreeSpace; } catch { }

            Payload pay = FindPayload();
            long want = pay != null ? Needed(pay.Length) : 35L * 1024 * 1024 * 1024;

            if (free < 0) txtRoom.Text = "Could not read how much room is on that drive.";
            else if (free < want)
            {
                txtRoom.Text = "Only " + Gb(free) + " free there, and this needs about " + Gb(want) + ". Pick another drive.";
                txtRoom.Foreground = B("#BC5039");
            }
            else
            {
                txtRoom.Text = Gb(free) + " free, and this needs about " + Gb(want) + ". Everything is unpacked on the same drive, so nothing lands on C: unless you choose it.";
                txtRoom.Foreground = B("#66594A");
            }
        }

        static void PickFolder()
        {
            try
            {
                var dlg = new System.Windows.Forms.FolderBrowserDialog();
                dlg.Description = "Where should Thornswood go? A folder called SkyrimTogether is made inside whatever you pick.";
                dlg.ShowNewFolderButton = true;
                if (dlg.ShowDialog() != System.Windows.Forms.DialogResult.OK) return;

                string chosen = dlg.SelectedPath;
                // Picking the folder it is already in should not nest another
                // one inside it every time the button is pressed.
                if (!chosen.TrimEnd('\\').EndsWith("SkyrimTogether", StringComparison.OrdinalIgnoreCase))
                    chosen = Path.Combine(chosen, "SkyrimTogether");
                SetRoot(chosen);
            }
            catch (Exception ex)
            {
                MessageBox.Show("Could not open the folder picker: " + ex.Message,
                                "Thornswood Setup", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        /// <summary>The emblem, compiled into this exe as a resource.</summary>
        static BitmapImage Emblem()
        {
            try
            {
                var asm = System.Reflection.Assembly.GetExecutingAssembly();
                string pick = null;
                foreach (string n in asm.GetManifestResourceNames())
                    if (n.EndsWith("logo.png", StringComparison.OrdinalIgnoreCase)) { pick = n; break; }
                if (pick == null) return null;

                using (Stream st = asm.GetManifestResourceStream(pick))
                {
                    if (st == null) return null;
                    var ms = new MemoryStream();
                    st.CopyTo(ms);
                    ms.Position = 0;
                    var bi = new BitmapImage();
                    bi.BeginInit();
                    bi.CacheOption = BitmapCacheOption.OnLoad;   // or it reads after the stream has closed
                    bi.StreamSource = ms;
                    bi.EndInit();
                    bi.Freeze();
                    return bi;
                }
            }
            catch { return null; }
        }

        static SolidColorBrush B(string hex)
        {
            return new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex));
        }

        // Built from markup rather than by hand, because a WPF Button keeps its
        // own chrome unless you replace the template, and setting Background on
        // one gets you the system button with an odd tint instead of the button
        // you meant.
        const string Ui = @"
<Window xmlns=""http://schemas.microsoft.com/winfx/2006/xaml/presentation""
        xmlns:x=""http://schemas.microsoft.com/winfx/2006/xaml""
        Title=""Thornswood Setup"" Width=""700"" Height=""640""
        ResizeMode=""NoResize"" WindowStartupLocation=""Manual""
        Background=""#100D0A"" FontFamily=""Segoe UI""
        TextOptions.TextFormattingMode=""Display"">
  <Window.Resources>
    <SolidColorBrush x:Key=""Ink""    Color=""#EDE5D8""/>
    <SolidColorBrush x:Key=""Muted""  Color=""#9C8D79""/>
    <SolidColorBrush x:Key=""Faint""  Color=""#66594A""/>
    <SolidColorBrush x:Key=""Line""   Color=""#2C251D""/>
    <SolidColorBrush x:Key=""Card""   Color=""#1D1813""/>
    <SolidColorBrush x:Key=""Deep""   Color=""#0A0807""/>
    <SolidColorBrush x:Key=""Panel""  Color=""#171310""/>
    <SolidColorBrush x:Key=""Accent"" Color=""#C8763A""/>
    <SolidColorBrush x:Key=""Bad""    Color=""#BC5039""/>

    <DrawingBrush x:Key=""Hatch"" TileMode=""Tile"" Viewport=""0,0,9,9"" ViewportUnits=""Absolute"">
      <DrawingBrush.Drawing>
        <GeometryDrawing>
          <GeometryDrawing.Geometry>
            <LineGeometry StartPoint=""0,9"" EndPoint=""9,0""/>
          </GeometryDrawing.Geometry>
          <GeometryDrawing.Pen><Pen Brush=""#16808080"" Thickness=""1""/></GeometryDrawing.Pen>
        </GeometryDrawing>
      </DrawingBrush.Drawing>
    </DrawingBrush>

    <Style x:Key=""Btn"" TargetType=""Button"">
      <Setter Property=""Padding"" Value=""26,11""/>
      <Setter Property=""FontSize"" Value=""13""/>
      <Setter Property=""Cursor"" Value=""Hand""/>
      <Setter Property=""Template"">
        <Setter.Value>
          <ControlTemplate TargetType=""Button"">
            <Border x:Name=""Bd"" Background=""{TemplateBinding Background}"" CornerRadius=""2""
                    BorderBrush=""{TemplateBinding BorderBrush}"" BorderThickness=""1""
                    Padding=""{TemplateBinding Padding}"" SnapsToDevicePixels=""True"">
              <ContentPresenter HorizontalAlignment=""Center"" VerticalAlignment=""Center""/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property=""IsMouseOver"" Value=""True"">
                <Setter TargetName=""Bd"" Property=""Opacity"" Value=""0.82""/>
              </Trigger>
              <Trigger Property=""IsEnabled"" Value=""False"">
                <Setter TargetName=""Bd"" Property=""Opacity"" Value=""0.35""/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Border BorderBrush=""{StaticResource Line}"" BorderThickness=""1"">
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height=""Auto""/>
        <RowDefinition Height=""*""/>
        <RowDefinition Height=""Auto""/>
      </Grid.RowDefinitions>

      <Border Grid.Row=""0"" Background=""{StaticResource Panel}""
              BorderBrush=""{StaticResource Line}"" BorderThickness=""0,0,0,1"">
        <Grid>
          <Rectangle Fill=""{StaticResource Hatch}"" Opacity=""0.85""/>
          <StackPanel Margin=""36,24,36,22"" Orientation=""Horizontal"">
            <Image x:Name=""Logo"" Width=""78"" Height=""78"" Margin=""0,0,22,0"" VerticalAlignment=""Center""
                   RenderOptions.BitmapScalingMode=""HighQuality"" Visibility=""Collapsed""/>
            <StackPanel VerticalAlignment=""Center"">
            <TextBlock Text=""Setup"" Foreground=""{StaticResource Faint}"" FontSize=""13""
                       FontFamily=""Constantia, Georgia"" Typography.Capitals=""SmallCaps""
                       TextOptions.TextFormattingMode=""Ideal"" Margin=""1,0,0,4""/>
            <TextBlock x:Name=""TxtHead"" Text=""Thornswood"" Foreground=""{StaticResource Ink}""
                       FontSize=""30"" FontFamily=""Constantia, Georgia""
                       Typography.Capitals=""SmallCaps"" TextOptions.TextFormattingMode=""Ideal""/>
            <Rectangle Height=""2"" Width=""42"" Fill=""{StaticResource Accent}""
                       HorizontalAlignment=""Left"" Margin=""2,12,0,0""/>
            </StackPanel>
          </StackPanel>
        </Grid>
      </Border>

      <Grid Grid.Row=""1"" Margin=""36,24,36,0"">
        <Grid.RowDefinitions>
          <RowDefinition Height=""Auto""/>
          <RowDefinition Height=""Auto""/>
          <RowDefinition Height=""Auto""/>
          <RowDefinition Height=""*""/>
        </Grid.RowDefinitions>

        <TextBlock x:Name=""TxtBody"" Grid.Row=""0""
                   Foreground=""{StaticResource Muted}"" FontSize=""13"" LineHeight=""21""
                   TextWrapping=""Wrap""
                   Text=""This builds a complete, separate Skyrim at C:\SkyrimTogether with the whole mod list already set up. You do not install any mods yourself.&#10;&#10;Your Steam copy is only read from. Nothing there is renamed, patched or deleted, so everything else you play with it keeps working.&#10;&#10;You need about 45 GB free and Steam running.""/>

        <Border Grid.Row=""1"" Margin=""0,20,0,0"" Padding=""17,14"" CornerRadius=""2""
                Background=""{StaticResource Card}"" BorderBrush=""{StaticResource Line}"" BorderThickness=""1"">
          <StackPanel>
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width=""*""/>
                <ColumnDefinition Width=""Auto""/>
              </Grid.ColumnDefinitions>
              <StackPanel Grid.Column=""0"">
                <TextBlock Text=""Install to"" Foreground=""{StaticResource Faint}"" FontSize=""12""
                           FontFamily=""Constantia, Georgia"" Typography.Capitals=""SmallCaps""
                           TextOptions.TextFormattingMode=""Ideal"" Margin=""0,0,0,6""/>
                <TextBlock x:Name=""TxtRoot"" Foreground=""{StaticResource Ink}"" FontSize=""14""
                           FontFamily=""Cascadia Mono, Consolas"" TextTrimming=""CharacterEllipsis""/>
              </StackPanel>
              <Button x:Name=""BtnPick"" Grid.Column=""1"" Style=""{StaticResource Btn}"" Content=""Another folder""
                      Padding=""16,7"" FontSize=""12"" VerticalAlignment=""Bottom""
                      Background=""{StaticResource Deep}"" BorderBrush=""{StaticResource Line}""
                      Foreground=""{StaticResource Ink}""/>
            </Grid>
            <WrapPanel x:Name=""DriveRow"" Margin=""0,13,0,0""/>
            <TextBlock x:Name=""TxtRoom"" Foreground=""{StaticResource Faint}"" FontSize=""11.5""
                       TextWrapping=""Wrap"" Margin=""0,11,0,0""/>
          </StackPanel>
        </Border>

        <Border x:Name=""FoundBox"" Grid.Row=""2"" Margin=""0,14,0,0"" Padding=""17,14""
                CornerRadius=""2"" Background=""{StaticResource Card}""
                BorderBrush=""{StaticResource Line}"" BorderThickness=""1"">
          <StackPanel>
            <TextBlock Text=""Installing from"" Foreground=""{StaticResource Faint}"" FontSize=""12""
                       FontFamily=""Constantia, Georgia"" Typography.Capitals=""SmallCaps""
                       TextOptions.TextFormattingMode=""Ideal"" Margin=""0,0,0,6""/>
            <TextBlock x:Name=""TxtFound"" Foreground=""{StaticResource Ink}"" FontSize=""13""
                       TextWrapping=""Wrap"" LineHeight=""20"" Text=""Looking...""/>
          </StackPanel>
        </Border>

        <StackPanel Grid.Row=""3"" VerticalAlignment=""Bottom"" Margin=""0,0,0,4"">
          <ProgressBar x:Name=""Bar"" Height=""5"" Minimum=""0"" Maximum=""1000""
                       Foreground=""{StaticResource Accent}"" Background=""{StaticResource Deep}""
                       BorderThickness=""0"" Margin=""0,20,0,0"" Visibility=""Collapsed""/>
          <TextBlock x:Name=""TxtStat"" Foreground=""{StaticResource Faint}"" FontSize=""11.5""
                     FontFamily=""Cascadia Mono, Consolas"" Margin=""0,11,0,0""
                     TextTrimming=""CharacterEllipsis""/>
        </StackPanel>
      </Grid>

      <Border Grid.Row=""2"" Background=""{StaticResource Panel}""
              BorderBrush=""{StaticResource Line}"" BorderThickness=""0,1,0,0"" Padding=""36,18"">
        <StackPanel Orientation=""Horizontal"" HorizontalAlignment=""Right"">
          <Button x:Name=""BtnClose"" Style=""{StaticResource Btn}"" Content=""Not now""
                  Background=""{StaticResource Card}"" BorderBrush=""{StaticResource Line}""
                  Foreground=""{StaticResource Ink}"" Margin=""0,0,10,0""/>
          <Button x:Name=""BtnGo"" Style=""{StaticResource Btn}"" Content=""Install""
                  Background=""{StaticResource Accent}"" BorderBrush=""{StaticResource Accent}""
                  Foreground=""#1B1205"" FontWeight=""SemiBold""/>
        </StackPanel>
      </Border>
    </Grid>
  </Border>
</Window>";

        static void Run()
        {
            win = (Window)XamlReader.Parse(Ui);

            txtHead  = (TextBlock)win.FindName("TxtHead");
            txtBody  = (TextBlock)win.FindName("TxtBody");
            txtFound = (TextBlock)win.FindName("TxtFound");
            txtStat  = (TextBlock)win.FindName("TxtStat");
            bar      = (ProgressBar)win.FindName("Bar");
            btnGo    = (Button)win.FindName("BtnGo");
            btnClose = (Button)win.FindName("BtnClose");
            foundBox = (Border)win.FindName("FoundBox");

            txtRoot  = (TextBlock)win.FindName("TxtRoot");
            txtRoom  = (TextBlock)win.FindName("TxtRoom");
            driveRow = (WrapPanel)win.FindName("DriveRow");
            btnPick  = (Button)win.FindName("BtnPick");
            btnPick.Click += delegate { PickFolder(); };
            BuildDrives();
            SetRoot(installRoot);

            var logo = (Image)win.FindName("Logo");
            BitmapImage art = Emblem();
            if (logo != null && art != null) { logo.Source = art; logo.Visibility = Visibility.Visible; }
            if (art != null) win.Icon = art;

            btnClose.Click += delegate { win.Close(); };
            btnGo.Click += delegate { Start(); };

            win.Closing += delegate(object s, System.ComponentModel.CancelEventArgs e)
            {
                if (running)
                {
                    var r = MessageBox.Show("Setup is still unpacking. Stop it?", "Thornswood Setup",
                                            MessageBoxButton.YesNo, MessageBoxImage.Warning);
                    if (r != MessageBoxResult.Yes) { e.Cancel = true; }
                }
            };

            // Centre on the main monitor. WPF's CenterScreen uses the whole
            // desktop, which on a two monitor setup is the gap between them.
            try
            {
                Rect work = SystemParameters.WorkArea;
                win.Left = work.Left + Math.Max(0, (work.Width - win.Width) / 2);
                win.Top = work.Top + Math.Max(0, (work.Height - win.Height) / 2);
            }
            catch { }

            ShowWhatWasFound();

            new Application().Run(win);
        }

        /// <summary>The zip is the thing people get wrong, so it is said plainly and up front.</summary>
        static void ShowWhatWasFound()
        {
            Payload found = null;
            string exe = "";
            try
            {
                exe = System.Reflection.Assembly.GetExecutingAssembly().Location;
                found = Locate(exe);
            }
            catch { }

            if (found == null)
            {
                foundBox.BorderBrush = (Brush)win.FindResource("Bad");
                txtFound.Foreground = (Brush)win.FindResource("Bad");
                txtFound.Text = "SkyrimTogether-Setup.zip is not here.\n\n" +
                                "It downloads separately and has to sit in the same folder as this program. " +
                                "Put the two together and run this again. Do not unzip it.";
                btnGo.IsEnabled = false;
                txtStat.Text = "looked beside this program and in Downloads";
                return;
            }

            if (found.File == exe)
            {
                txtFound.Text = "Everything needed is inside this program.";
                return;
            }

            txtFound.Text = Path.GetFileName(found.File) + "   ·   " + Gb(found.Length);
            txtStat.Text = Path.GetDirectoryName(found.File);
        }

        /// <summary>The setup zip, beside this program or in the Downloads folder.</summary>
        static string FindZip(string exeDir)
        {
            var roots = new System.Collections.Generic.List<string>();
            if (!string.IsNullOrEmpty(exeDir)) roots.Add(exeDir);
            try
            {
                string dl = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
                if (!roots.Contains(dl)) roots.Add(dl);
            }
            catch { }

            foreach (string root in roots)
            {
                if (!Directory.Exists(root)) continue;

                foreach (string name in PayloadNames)
                {
                    string exact = Path.Combine(root, name);
                    if (File.Exists(exact)) return exact;
                }

                // A browser that has seen the file before saves the next one as
                // "SkyrimTogether-Setup (1).zip". Take the biggest match.
                string best = null; long bestLen = -1;
                try
                {
                    foreach (string f in Directory.GetFiles(root, "SkyrimTogether-Setup*.zip"))
                    {
                        long len = new FileInfo(f).Length;
                        if (len > bestLen) { bestLen = len; best = f; }
                    }
                }
                catch { }
                if (best != null) return best;
            }
            return null;
        }

        /// <summary>Where the payload is: a zip beside this program, or attached to it.</summary>
        static Payload Locate(string exe)
        {
            string zip = FindZip(Path.GetDirectoryName(exe));
            if (zip != null)
                return new Payload { File = zip, Offset = 0, Length = new FileInfo(zip).Length };

            try
            {
                using (var fs = File.OpenRead(exe))
                {
                    if (fs.Length < TrailerLen) return null;
                    fs.Position = fs.Length - TrailerLen;
                    var br = new BinaryReader(fs);
                    if (Encoding.ASCII.GetString(br.ReadBytes(8)) != Magic) return null;
                    long off = br.ReadInt64(), len = br.ReadInt64();
                    if (off <= 0 || len <= 0 || off + len > fs.Length) return null;
                    return new Payload { File = exe, Offset = off, Length = len };
                }
            }
            catch { return null; }
        }

        static string Gb(long bytes)
        {
            return (bytes / 1073741824.0).ToString("0.0") + " GB";
        }

        static void Say(string s)
        {
            win.Dispatcher.BeginInvoke(new Action(delegate { txtStat.Text = s; }));
        }

        static void Start()
        {
            try
            {
                string root = Path.GetPathRoot(installRoot);
                Payload check = FindPayload();
                long free = new DriveInfo(root).AvailableFreeSpace;
                if (check != null && free < Needed(check.Length))
                {
                    MessageBox.Show("There is only " + Gb(free) + " free on " + root +
                                    " and this needs about " + Gb(Needed(check.Length)) +
                                    ".\n\nPick another drive.",
                                    "Thornswood Setup", MessageBoxButton.OK, MessageBoxImage.Warning);
                    return;
                }
            }
            catch { }

            btnGo.IsEnabled = false;
            btnPick.IsEnabled = false;
            foreach (object o in driveRow.Children) { var b = o as Button; if (b != null) b.IsEnabled = false; }
            btnClose.IsEnabled = false;
            bar.Visibility = Visibility.Visible;
            txtBody.Text = "Unpacking. This takes a few minutes and the installer opens by itself when it is done.";
            running = true;
            var t = new Thread(Work);
            t.IsBackground = true;
            t.Start();
        }

        /// <summary>
        /// Skyrim does not always exit when it looks like it has. A crash, an
        /// Alt-F4, or one of the multiplayer client's browser helpers leaves a
        /// process behind with no window, which nobody can see and nobody can
        /// close. It holds files open under the build and the installer script
        /// refuses to run while it is there, so it goes first.
        /// </summary>
        static int StopSkyrim()
        {
            var found = new List<Process>();
            foreach (string n in new string[] { "SkyrimSE", "skse64_loader", "SkyrimTogether" })
            {
                try { found.AddRange(Process.GetProcessesByName(n)); } catch { }
            }
            if (found.Count == 0) return 0;

            bool asked = false;
            foreach (Process p in found)
            {
                try
                {
                    if (p.MainWindowHandle == IntPtr.Zero) continue;
                    p.CloseMainWindow();
                    asked = true;
                }
                catch { }
            }
            if (asked)
            {
                for (int i = 0; i < 24; i++)
                {
                    Thread.Sleep(250);
                    bool any = false;
                    foreach (Process p in found) { try { if (!p.HasExited) any = true; } catch { } }
                    if (!any) break;
                }
            }
            foreach (Process p in found) { try { if (!p.HasExited) p.Kill(); } catch { } }
            foreach (Process p in found) { try { p.Dispose(); } catch { } }
            Thread.Sleep(750);
            return found.Count;
        }

        static void Work()
        {
            try
            {
                int stopped = StopSkyrim();
                if (stopped > 0)
                    Say("Closed " + stopped + " Skyrim process" + (stopped == 1 ? "" : "es") + " that was still open");

                string exe = System.Reflection.Assembly.GetExecutingAssembly().Location;
                Payload pay = Locate(exe);
                if (pay == null)
                    throw new Exception("SkyrimTogether-Setup.zip is missing. It has to sit in the same folder as this program. Put both files together and run this again.");

                if (pay.File != exe && pay.Length < 64L * 1024 * 1024)
                    throw new Exception(Path.GetFileName(pay.File) + " is only " + (pay.Length / 1048576) +
                                        " MB, so it did not finish downloading. Delete it and get it again.");

                // Unpacked beside where it is going, not in %TEMP%. On a
                // machine where C: is full and the build is headed for D: that
                // is the difference between working and not, and it turns the
                // final move into a rename rather than another 18 GB copy.
                temp = Path.Combine(Path.GetPathRoot(installRoot), "SkyrimTogether-setup");
                try
                {
                    if (Directory.Exists(temp)) Directory.Delete(temp, true);
                    Directory.CreateDirectory(temp);
                }
                catch
                {
                    temp = Path.Combine(Path.GetTempPath(), "SkyrimTogether-setup");
                    if (Directory.Exists(temp)) { try { Directory.Delete(temp, true); } catch { } }
                    Directory.CreateDirectory(temp);
                }

                long free = -1;
                try { free = new DriveInfo(Path.GetPathRoot(temp)).AvailableFreeSpace; } catch { }
                if (free >= 0 && free < Needed(pay.Length))
                    throw new Exception("This needs about " + Gb(Needed(pay.Length)) + " free on " +
                                        Path.GetPathRoot(temp) + " and there is " + Gb(free) +
                                        ". Close this, pick another drive, and start again.");

                try
                {
                    using (var fs = File.OpenRead(pay.File))
                    using (var slice = new SliceStream(fs, pay.Offset, pay.Length))
                    using (var zip = new ZipArchive(slice, ZipArchiveMode.Read))
                    {
                        int total = zip.Entries.Count, n = 0;
                        foreach (ZipArchiveEntry e in zip.Entries)
                        {
                            n++;
                            if (string.IsNullOrEmpty(e.Name)) continue;
                            string dest = Path.Combine(temp, e.FullName.Replace('/', '\\'));
                            string full = Path.GetFullPath(dest);
                            if (!full.StartsWith(temp, StringComparison.OrdinalIgnoreCase)) continue;
                            Directory.CreateDirectory(Path.GetDirectoryName(full));
                            e.ExtractToFile(full, true);
                            if ((n & 63) == 0 || n == total)
                            {
                                double frac = (double)n / total;
                                win.Dispatcher.BeginInvoke(new Action(delegate { bar.Value = frac * 1000; }));
                                Say(string.Format("{0:n0} of {1:n0} files", n, total));
                            }
                        }
                    }
                }
                catch (InvalidDataException)
                {
                    throw new Exception(Path.GetFileName(pay.File) +
                                        " is damaged or did not finish downloading. Delete it and download it again.");
                }

                Say("Starting the installer");
                string bat = Path.Combine(temp, "Setup.bat");
                if (!File.Exists(bat)) throw new Exception("Setup.bat was not in the payload.");
                var psi = new ProcessStartInfo(bat);
                psi.Arguments = "\"" + installRoot.TrimEnd('\\') + "\"";
                psi.WorkingDirectory = temp;
                psi.UseShellExecute = true;
                Process.Start(psi);

                running = false;
                win.Dispatcher.BeginInvoke(new Action(delegate { win.Close(); }));
            }
            catch (Exception ex)
            {
                running = false;
                win.Dispatcher.BeginInvoke(new Action(delegate
                {
                    bar.Visibility = Visibility.Collapsed;
                    txtBody.Text = ex.Message;
                    txtStat.Text = "";
                    btnClose.IsEnabled = true;
                    btnClose.Content = "Close";
                }));
            }
        }
    }
}
