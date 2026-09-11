using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Text;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

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

    static class Setup
    {
        const string Magic = "STSFX001";
        const int TrailerLen = 24;          // 8 magic + 8 offset + 8 length

        static Window win;
        static TextBlock txtHead, txtBody, txtStat;
        static ProgressBar bar;
        static Button btnGo, btnClose;
        static string temp;
        static bool running;

        [STAThread]
        static void Main()
        {
            try { Run(); }
            catch (Exception ex)
            {
                MessageBox.Show(ex.Message, "Skyrim Together Setup", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        static SolidColorBrush B(string hex)
        {
            return new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex));
        }

        static void Run()
        {
            win = new Window();
            win.Title = "Skyrim Together Setup";
            win.Width = 560; win.Height = 330;
            win.ResizeMode = ResizeMode.NoResize;
            win.WindowStartupLocation = WindowStartupLocation.CenterScreen;
            win.Background = B("#0E1216");
            win.FontFamily = new FontFamily("Segoe UI");

            var root = new StackPanel();
            root.Margin = new Thickness(34, 30, 34, 26);

            txtHead = new TextBlock();
            txtHead.Text = "Skyrim Together";
            txtHead.FontSize = 24; txtHead.FontWeight = FontWeights.Bold;
            txtHead.Foreground = B("#E4EAEE");
            root.Children.Add(txtHead);

            var rule = new System.Windows.Shapes.Rectangle();
            rule.Height = 2; rule.Width = 34; rule.Fill = B("#C8763A");
            rule.HorizontalAlignment = HorizontalAlignment.Left;
            rule.Margin = new Thickness(2, 10, 0, 0);
            root.Children.Add(rule);

            txtBody = new TextBlock();
            txtBody.Text = "This installs a complete, self-contained copy of Skyrim with the whole mod list already set up, into C:\\SkyrimTogether.\n\n" +
                           "Your Steam copy of Skyrim is only read from. Nothing in it is renamed, patched or deleted, so anything else you play with it keeps working.\n\n" +
                           "You need about 25 GB free and Steam running.";
            txtBody.FontSize = 12.5; txtBody.Foreground = B("#7E8D97");
            txtBody.TextWrapping = TextWrapping.Wrap; txtBody.LineHeight = 19;
            txtBody.Margin = new Thickness(0, 20, 0, 0);
            root.Children.Add(txtBody);

            bar = new ProgressBar();
            bar.Height = 4; bar.Minimum = 0; bar.Maximum = 1000;
            bar.Foreground = B("#C8763A"); bar.Background = B("#1B232A");
            bar.BorderThickness = new Thickness(0);
            bar.Margin = new Thickness(0, 22, 0, 0);
            bar.Visibility = Visibility.Collapsed;
            root.Children.Add(bar);

            txtStat = new TextBlock();
            txtStat.FontSize = 11.5; txtStat.Foreground = B("#4E5A63");
            txtStat.FontFamily = new FontFamily("Consolas");
            txtStat.Margin = new Thickness(0, 10, 0, 0);
            root.Children.Add(txtStat);

            var row = new StackPanel();
            row.Orientation = Orientation.Horizontal;
            row.HorizontalAlignment = HorizontalAlignment.Right;
            row.Margin = new Thickness(0, 22, 0, 0);

            btnClose = Flat("Cancel", "#182028", "#C4CFD4");
            btnClose.Margin = new Thickness(0, 0, 10, 0);
            btnClose.Click += delegate { win.Close(); };
            row.Children.Add(btnClose);

            btnGo = Flat("Install", "#C8763A", "#FFF3E8");
            btnGo.Click += delegate { Start(); };
            row.Children.Add(btnGo);

            root.Children.Add(row);
            win.Content = root;

            win.Closing += delegate(object s, System.ComponentModel.CancelEventArgs e)
            {
                if (running)
                {
                    var r = MessageBox.Show("Setup is still unpacking. Stop it?", "Skyrim Together Setup",
                                            MessageBoxButton.YesNo, MessageBoxImage.Warning);
                    if (r != MessageBoxResult.Yes) { e.Cancel = true; }
                }
            };

            new Application().Run(win);
        }

        static Button Flat(string text, string bg, string fg)
        {
            var b = new Button();
            b.Content = text;
            b.Padding = new Thickness(22, 9, 22, 9);
            b.FontSize = 12.5;
            b.Cursor = System.Windows.Input.Cursors.Hand;
            b.Foreground = B(fg);
            b.Background = B(bg);
            b.BorderBrush = B("#232E36");
            b.BorderThickness = new Thickness(1);
            return b;
        }

        static void Say(string s)
        {
            win.Dispatcher.BeginInvoke(new Action(delegate { txtStat.Text = s; }));
        }

        static void Start()
        {
            btnGo.IsEnabled = false;
            btnClose.IsEnabled = false;
            bar.Visibility = Visibility.Visible;
            txtBody.Text = "Unpacking. This takes a few minutes and the installer opens by itself when it is done.";
            running = true;
            var t = new Thread(Work);
            t.IsBackground = true;
            t.Start();
        }

        static void Work()
        {
            try
            {
                string exe = System.Reflection.Assembly.GetExecutingAssembly().Location;
                long offset, length;
                using (var fs = File.OpenRead(exe))
                {
                    if (fs.Length < TrailerLen) throw new Exception("This copy of setup has no payload attached.");
                    fs.Position = fs.Length - TrailerLen;
                    var br = new BinaryReader(fs);
                    string magic = Encoding.ASCII.GetString(br.ReadBytes(8));
                    if (magic != Magic) throw new Exception("This copy of setup has no payload attached, or the download is truncated.");
                    offset = br.ReadInt64();
                    length = br.ReadInt64();
                    if (offset <= 0 || length <= 0 || offset + length > fs.Length)
                        throw new Exception("The payload looks damaged. Download the file again.");
                }

                temp = Path.Combine(Path.GetTempPath(), "SkyrimTogether-setup");
                if (Directory.Exists(temp)) { try { Directory.Delete(temp, true); } catch { } }
                Directory.CreateDirectory(temp);

                using (var fs = File.OpenRead(exe))
                using (var slice = new SliceStream(fs, offset, length))
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

                Say("Starting the installer");
                string bat = Path.Combine(temp, "Setup.bat");
                if (!File.Exists(bat)) throw new Exception("Setup.bat was not in the payload.");
                var psi = new ProcessStartInfo(bat);
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
