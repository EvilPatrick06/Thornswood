using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Security.Cryptography;
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

        // Two shapes: the payload attached to the end of this program, or
        // nothing, in which case the published one is fetched from the site
        // and checked against the SHA-256 the site gives for it.
        //
        // A zip lying about is never used. This took the first
        // SkyrimTogether-Setup.zip, payload.zip or Thornswood-Setup*.zip it
        // found beside itself or anywhere in the Downloads folder, before the
        // payload attached to it and before asking the site, unpacked it with
        // no check at all and ran whatever Setup.bat was inside. Anybody with a
        // zip left over from an earlier download, the Skyrim Together ones
        // included, got that old install from a new looking window. Nobody is
        // told to put a zip beside this any more: Publish-Installer publishes
        // the payload hidden and the Downloads page has one button.

        // Where to get it when there is none either way.
        //
        // Carrying it inside made one file to download, which is what it should
        // be, and cost two things. Windows would not draw the icon on a 710 MB
        // executable, so it arrived in the browser as a blank mark next to every
        // other server's logo. And a new 710 MB binary every release is a new
        // hash every release, so SmartScreen never accumulates any reputation
        // and warns forever.
        //
        // Fetching it keeps this program small enough for both: the icon
        // renders, the binary stops changing between releases, and a download
        // that drops carries on instead of starting at zero.
        const string Site = "https://thornswood.net";

        static Window win;
        static TextBlock txtHead, txtBody, txtFound, txtStat;
        static Border foundBox;
        static ProgressBar bar;
        static Button btnGo, btnClose;
        static CheckBox chkAge;
        static string temp;

        // Where the build ends up. The drive matters more than the folder to
        // most people, so the drives are offered as buttons and the full path
        // is only there to be read back.
        // Setup-Thornswood.ps1 has defaulted to C:\Thornswood the whole time.
        // This defaulted to the pre-rename name, so the folder the setup window
        // offered and the folder the script expected were two different places,
        // and the one a person read was the old project's name.
        static string installRoot = @"C:\Thornswood";
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
                b.Click += delegate { SetRoot(Path.Combine(captured.Name, "Thornswood")); };
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
            // With no payload to measure this is an estimate, and it read as a
            // measurement: "only 35.0 GB free and this needs about 35.0 GB" is
            // a refusal to somebody who has exactly enough, in red, over a
            // number nothing had actually weighed. Say which it is, and only
            // go red when the shortfall is real rather than a rounding.
            bool guess = (pay == null);
            long want = guess ? 6L * 1024 * 1024 * 1024 : Needed(pay.Length);
            string about = guess ? "wants roughly " : "needs about ";

            if (free < 0) txtRoom.Text = "Could not read how much room is on that drive.";
            else if (free < want - (guess ? 2L * 1024 * 1024 * 1024 : 0))
            {
                txtRoom.Text = "Only " + Gb(free) + " free there, and this " + about + Gb(want) +
                               ". Pick another drive.";
                txtRoom.Foreground = B("#BC5039");
            }
            else if (free < want)
            {
                txtRoom.Text = Gb(free) + " free, and this " + about + Gb(want) +
                               ". That is close, so it may not fit.";
                txtRoom.Foreground = B("#8A7A5E");
            }
            else
            {
                txtRoom.Text = Gb(free) + " free, and this " + about + Gb(want) +
                               ". Everything is unpacked on the same drive, so nothing lands on C: unless you choose it.";
                txtRoom.Foreground = B("#66594A");
            }
        }

        static void PickFolder()
        {
            try
            {
                var dlg = new System.Windows.Forms.FolderBrowserDialog();
                dlg.Description = "Where should Thornswood go? A folder called Thornswood is made inside whatever you pick.";
                dlg.ShowNewFolderButton = true;
                if (dlg.ShowDialog() != System.Windows.Forms.DialogResult.OK) return;

                string chosen = dlg.SelectedPath;
                // Picking the folder it is already in should not nest another
                // one inside it every time the button is pressed.
                if (!chosen.TrimEnd('\\').EndsWith("Thornswood", StringComparison.OrdinalIgnoreCase))
                    chosen = Path.Combine(chosen, "Thornswood");
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
        Title=""Thornswood Setup"" Width=""700"" Height=""740""
        MinWidth=""560"" MinHeight=""520""
        ResizeMode=""CanResize"" WindowStartupLocation=""Manual""
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
          <RowDefinition Height=""*""/>
          <RowDefinition Height=""Auto""/>
        </Grid.RowDefinitions>

        <!-- Everything above the progress bar scrolls. On a short
             screen, or once the drive warning wraps to three lines, the
             box saying what it is about to install ran off the bottom
             of a window that could not be resized or scrolled, so the
             only thing a person could do was guess. -->
        <ScrollViewer Grid.Row=""0"" VerticalScrollBarVisibility=""Auto""
                      HorizontalScrollBarVisibility=""Disabled"" Padding=""0,0,6,0"">
          <StackPanel>

        <TextBlock x:Name=""TxtBody""
                   Foreground=""{StaticResource Muted}"" FontSize=""13"" LineHeight=""21""
                   TextWrapping=""Wrap""
                   Text=""This puts in the launcher, the script extender and Thornswood's own content. The launcher then builds a game folder of its own from the Skyrim you already have on Steam, most of it as hard links that take no extra space, and leaves your own Skyrim alone.&#10;&#10;The mods themselves come from a collection on Nexus. Vortex installs them into a profile of their own, so switching back to your usual profile and running Purge Mods leaves your Skyrim where you started. The launcher has the link and walks you through it.&#10;&#10;Nothing of Bethesda's is renamed or deleted. You need Steam running and Skyrim on build 1.6.1170.""/>

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

        <Border x:Name=""FoundBox"" Margin=""0,14,0,0"" Padding=""17,14""
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

          </StackPanel>
        </ScrollViewer>

        <StackPanel Grid.Row=""1"" VerticalAlignment=""Bottom"" Margin=""0,0,0,4"">
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
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width=""*""/>
            <ColumnDefinition Width=""Auto""/>
          </Grid.ColumnDefinitions>
          <CheckBox x:Name=""ChkAge"" Grid.Column=""0"" VerticalAlignment=""Center""
                    Margin=""0,0,24,0"" Foreground=""{StaticResource Ink}"">
            <TextBlock Foreground=""{StaticResource Ink}"" FontSize=""12.5"" LineHeight=""18""
                       TextWrapping=""Wrap"" Margin=""4,0,0,0""
                       Text=""I am 18 or over. Thornswood is an adult server.""/>
          </CheckBox>
          <StackPanel Grid.Column=""1"" Orientation=""Horizontal"" HorizontalAlignment=""Right"">
            <Button x:Name=""BtnClose"" Style=""{StaticResource Btn}"" Content=""Not now""
                    Background=""{StaticResource Card}"" BorderBrush=""{StaticResource Line}""
                    Foreground=""{StaticResource Ink}"" Margin=""0,0,10,0""/>
            <Button x:Name=""BtnGo"" Style=""{StaticResource Btn}"" Content=""Install"" IsEnabled=""False""
                    Background=""{StaticResource Accent}"" BorderBrush=""{StaticResource Accent}""
                    Foreground=""#1B1205"" FontWeight=""SemiBold""/>
          </StackPanel>
        </Grid>
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

            // Install starts switched off and this is the only thing that
            // turns it on. A box somebody can ignore and press Install anyway
            // is decoration, so it gates the button rather than sitting next
            // to it.
            chkAge = (CheckBox)win.FindName("ChkAge");
            if (chkAge != null)
            {
                btnGo.IsEnabled = false;
                chkAge.Checked   += delegate { btnGo.IsEnabled = true; };
                chkAge.Unchecked += delegate { btnGo.IsEnabled = false; };
            }
            else
            {
                // Rather than an installer nobody can ever start.
                btnGo.IsEnabled = true;
            }

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
                // Not an error any more. There is nothing beside this program
                // and nothing in it, so it fetches Thornswood's own files itself when Install is
                // pressed. Saying so up front stops the wait being a surprise.
                txtFound.Text = "Nothing to unpack yet. Press Install and it gets Thornswood's own " +
                                "files from thornswood.net first, about half a gigabyte. The mods themselves come from Vortex afterwards, not from here.\n\n" +
                                "If it stops part way, run it again and it carries on from there.";
                txtStat.Text = "";
                return;
            }

            txtFound.Text = "Everything needed is inside this program.";
        }

        /// <summary>The payload attached to this program, or null when it has none and the site's is fetched.</summary>
        static Payload Locate(string exe)
        {
            // The trailer is the last 24 bytes of the file as the packager
            // leaves it. Signing the installer puts the certificate on the end
            // AFTER that, so on a signed build the last 24 bytes are part of a
            // signature blob and the trailer sits in front of it. Reading a
            // fixed offset from the end would find nothing and the installer
            // would tell people their payload was missing, on the one build
            // that Windows does not warn about.
            //
            // So scan back for the magic instead. A megabyte is far more than
            // any Authenticode blob, and the run of bytes that happens to
            // spell STSFX001 by accident is caught by checking that what it
            // points at actually starts like a zip.
            try
            {
                const int Window = 1 << 20;
                using (var fs = File.OpenRead(exe))
                {
                    if (fs.Length < TrailerLen) return null;
                    int take = (int)Math.Min((long)Window, fs.Length);
                    fs.Position = fs.Length - take;
                    var tail = new byte[take];
                    int got = 0;
                    while (got < take)
                    {
                        int r = fs.Read(tail, got, take - got);
                        if (r <= 0) break;
                        got += r;
                    }

                    byte[] magic = Encoding.ASCII.GetBytes(Magic);
                    for (int i = got - TrailerLen; i >= 0; i--)
                    {
                        bool hit = true;
                        for (int k = 0; k < magic.Length; k++)
                        {
                            if (tail[i + k] != magic[k]) { hit = false; break; }
                        }
                        if (!hit) continue;

                        long off = BitConverter.ToInt64(tail, i + 8);
                        long len = BitConverter.ToInt64(tail, i + 16);
                        if (off <= 0 || len <= 0 || off + len > fs.Length) continue;

                        fs.Position = off;
                        if (fs.ReadByte() != 0x50) continue;   // P
                        if (fs.ReadByte() != 0x4B) continue;   // K
                        if (fs.ReadByte() != 0x03) continue;
                        if (fs.ReadByte() != 0x04) continue;

                        return new Payload { File = exe, Offset = off, Length = len };
                    }
                    return null;
                }
            }
            catch { return null; }
        }

        static void Progress(double frac)
        {
            win.Dispatcher.BeginInvoke(new Action(delegate {
                if (frac < 0) { bar.IsIndeterminate = true; return; }
                bar.IsIndeterminate = false;
                bar.Value = frac * 1000;
            }));
        }

        /// <summary>
        /// Pull the payload down beside the unpack folder, carrying on from
        /// whatever is already there. Returns the path, or throws with
        /// something a person can act on.
        /// </summary>
        static string Download(string intoDir)
        {
            ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072; // Tls12

            string name, url;
            string sha = "";
            long size = 0;
            try
            {
                string doc;
                using (var wc = new WebClient())
                {
                    wc.Headers["User-Agent"] = "ThornswoodSetup";
                    doc = wc.DownloadString(Site + "/api/payload");
                }
                name = Between(doc, "\"name\":\"", "\"");
                url  = Between(doc, "\"url\":\"", "\"");
                string sz = Between(doc, "\"size\":", ",");
                if (sz.Length == 0) sz = Between(doc, "\"size\":", "}");
                long.TryParse(sz.Trim(), out size);
                // What Publish-Installer measured on the zip it sent.
                // A site from before this carries no such field and the string
                // search comes back empty, which PayloadMatches reads as
                // nothing to check.
                sha = Between(doc, "\"sha256\":\"", "\"").Trim();
            }
            catch (Exception e)
            {
                throw new Exception("Could not reach " + Site + " to get Thornswood's files. Check the " +
                                    "connection and run this again. (" + e.Message + ")");
            }
            if (url.Length == 0) throw new Exception("The site is not offering a download right now. Try again in a bit.");
            if (!url.StartsWith("http")) url = Site + url;
            if (name.Length == 0) name = "Thornswood-payload.zip";

            string target = Path.Combine(intoDir, name);
            long have = 0;
            try { if (File.Exists(target)) have = new FileInfo(target).Length; } catch { }
            // The right length is not proof of the right bytes. A zip that
            // finished under an installer from before this check was never
            // measured, and a resume stitches whatever was already here onto
            // what the site sends now. One that does not match is fetched again
            // rather than trusted for its size.
            if (size > 0 && have == size)
            {
                if (sha.Length > 0) Say("Checking Thornswood's files");
                if (PayloadMatches(target, sha)) { Say("Already got Thornswood's files"); return target; }
                try { File.Delete(target); } catch { }
                have = 0;
            }
            if (size > 0 && have > size) { try { File.Delete(target); } catch { } have = 0; }

            Say("Getting Thornswood's own files");
            Progress(-1);

            var req = (HttpWebRequest)WebRequest.Create(url);
            req.UserAgent = "ThornswoodSetup";
            req.Timeout = 60000;
            req.ReadWriteTimeout = 120000;
            if (have > 0) req.AddRange(have);

            using (var resp = (HttpWebResponse)req.GetResponse())
            {
                // A server that ignores the range answers 200 with the whole
                // file. Starting over is better than writing the front of the
                // file onto the end of what is already here.
                if (have > 0 && (int)resp.StatusCode != 206) have = 0;

                long total = size > 0 ? size : (have + resp.ContentLength);
                using (var net = resp.GetResponseStream())
                using (var file = new FileStream(target,
                                                 have > 0 ? FileMode.Append : FileMode.Create,
                                                 FileAccess.Write, FileShare.None, 1 << 20))
                {
                    var buf = new byte[1 << 20];
                    long done = have, at0 = have;
                    int n, tick = 0;
                    var clock = Stopwatch.StartNew();
                    while ((n = net.Read(buf, 0, buf.Length)) > 0)
                    {
                        file.Write(buf, 0, n);
                        done += n;
                        if (++tick % 8 != 0) continue;

                        string rate = "";
                        double secs = clock.Elapsed.TotalSeconds;
                        if (secs > 1)
                        {
                            double mbs = ((done - at0) / 1048576.0) / secs;
                            rate = "   " + mbs.ToString("0.0") + " MB/s";
                        }
                        if (total > 0)
                        {
                            Progress((double)done / total);
                            Say("Getting Thornswood's own files   " + (done / 1048576) + " of " +
                                (total / 1048576) + " MB" + rate);
                        }
                        else Say("Getting Thornswood's own files   " + (done / 1048576) + " MB" + rate);
                    }
                    file.Flush();
                }
            }

            long got = new FileInfo(target).Length;
            if (size > 0 && got != size)
                throw new Exception("The download stopped early, " + (got / 1048576) + " MB of " +
                                    (size / 1048576) + " MB. Run this again and it carries on from there.");
            Progress(-1);
            // Length was the only test here, and Work unpacks this and starts
            // the Setup.bat inside it. The launcher holds every pack it fetches
            // to a SHA-256 and deletes one that does not match (Updater.cs
            // Download); the installer, which is the first thing a stranger
            // runs, did not. Same standard now.
            if (sha.Length > 0) Say("Checking Thornswood's files");
            CheckPayload(target, sha);
            return target;
        }

        /// <summary>
        /// Whether the file is the one the site published. An empty hash
        /// means the site did not say, which is an older site, and that
        /// passes, so a new installer against an old site still installs.
        /// </summary>
        static bool PayloadMatches(string file, string sha)
        {
            if (string.IsNullOrEmpty(sha)) return true;
            // Streamed, never read whole. The payload is over half a gigabyte.
            using (var s = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 20))
            using (var h = SHA256.Create())
            {
                byte[] d = h.ComputeHash(s);
                var sb = new StringBuilder();
                foreach (byte b in d) sb.Append(b.ToString("x2"));
                // Get-FileHash writes upper case and this writes lower, so
                // the case is not part of the comparison.
                return string.Equals(sb.ToString(), sha, StringComparison.OrdinalIgnoreCase);
            }
        }

        /// <summary>
        /// Deletes a payload that is not the published one and stops, so the
        /// Setup.bat inside it never runs and the next run downloads it fresh
        /// rather than carrying on from bad bytes.
        /// </summary>
        static void CheckPayload(string file, string sha)
        {
            if (PayloadMatches(file, sha)) return;
            try { File.Delete(file); } catch { }
            throw new Exception("What came down is not the file the site published, so it has been deleted " +
                                "and nothing in it was run. Run this again to download it fresh.");
        }

        static string Between(string s, string a, string b)
        {
            int i = s.IndexOf(a, StringComparison.Ordinal);
            if (i < 0) return "";
            i += a.Length;
            int j = s.IndexOf(b, i, StringComparison.Ordinal);
            if (j < 0) return "";
            return s.Substring(i, j - i);
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
                // With nothing to measure yet, budget for the payload this
                // build fetches plus what it unpacks to. Better a warning that
                // turns out to be generous than filling somebody's drive at
                // 90 percent of an 18 GB unpack.
                if (check == null && free < 6L * 1024 * 1024 * 1024)
                {
                    if (MessageBox.Show("There is " + Gb(free) + " free on " + root +
                                        " and this wants about 6 GB once the download is " +
                                        "unpacked.\n\nCarry on anyway?",
                                        "Thornswood Setup", MessageBoxButton.YesNo,
                                        MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
                }
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
            if (chkAge != null) chkAge.IsEnabled = false;
            btnPick.IsEnabled = false;
            foreach (object o in driveRow.Children) { var b = o as Button; if (b != null) b.IsEnabled = false; }
            btnClose.IsEnabled = false;
            bar.Visibility = Visibility.Visible;
            // It said Unpacking while it was downloading 549 MB, which is the
            // longest part and the one a person most wants named.
            txtBody.Text = FindPayload() == null
                ? "Getting Thornswood's own files, then unpacking. This takes a few minutes and the installer opens by itself when it is done."
                : "Unpacking. This takes a few minutes and the installer opens by itself when it is done.";
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

                // Unpacked beside where it is going, not in %TEMP%. On a
                // machine where C: is full and the build is headed for D: that
                // is the difference between working and not, and it turns the
                // final move into a rename rather than another 18 GB copy.
                temp = Path.Combine(Path.GetPathRoot(installRoot), "Thornswood-setup");
                try
                {
                    // A half finished download from a previous run lives in
                    // here, so the folder is only cleared when there is nothing
                    // worth keeping in it. Wiping it every time would mean
                    // starting the 700 MB again after every stumble.
                    if (Directory.Exists(temp) && pay != null) Directory.Delete(temp, true);
                    Directory.CreateDirectory(temp);
                }
                catch
                {
                    temp = Path.Combine(Path.GetTempPath(), "Thornswood-setup");
                    if (Directory.Exists(temp) && pay != null) { try { Directory.Delete(temp, true); } catch { } }
                    Directory.CreateDirectory(temp);
                }

                // Nothing beside this program and nothing inside it, so go and
                // get it. This is the normal path now: the setup program is
                // small on purpose.
                bool downloaded = false;
                if (pay == null)
                {
                    string got = Download(temp);
                    pay = new Payload { File = got, Offset = 0, Length = new FileInfo(got).Length };
                    downloaded = true;
                    Say("Unpacking");
                }

                if (pay.File != exe && pay.Length < 64L * 1024 * 1024)
                    throw new Exception(Path.GetFileName(pay.File) + " is only " + (pay.Length / 1048576) +
                                        " MB, so it did not finish downloading. Delete it and run this again.");

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
                    // A zip we fetched ourselves goes, so running this again is
                    // a clean download rather than the same broken file twice.
                    if (downloaded) { try { File.Delete(pay.File); } catch { } }
                    throw new Exception(downloaded
                        ? "The download came down damaged. Run this again and it starts that part over."
                        : Path.GetFileName(pay.File) + " is damaged or did not finish downloading. " +
                          "Delete it and download it again.");
                }

                // 700 MB of zip sitting next to 18 GB of what came out of it,
                // on a drive that was already asked for three times the zip.
                if (downloaded) { try { File.Delete(pay.File); } catch { } }

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
