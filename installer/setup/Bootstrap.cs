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
using System.Reflection;
using System.Runtime.InteropServices;
using Microsoft.Win32;

// What Windows reads off this exe before anybody runs it. csc gives an exe no
// version resource at all unless these are set, so UAC's prompt, SmartScreen's
// panel and Explorer's columns fall back to the bare file name and nothing
// names the program at all. The blank "Unknown" on the publisher line is
// Authenticode's to fill, and that is issue #390, still pending; this is the
// rest of it, so the window a stranger meets first says what the program is
// instead of showing a path.
//
// Product NAME stays stable on purpose. A name that is rewritten every build is
// a new identity every build, which is the same reputation problem the download
// further down was written to escape: a name SmartScreen has never seen before
// earns no trust. The download file name stays Thornswood-Setup.exe;
// version and SHA-256 live in files.json / the Downloads page. The product
// name / company / copyright below do not move with each release either.
// FileVersion and ProductVersion are NOT hardcoded here -
// Build-Launcher.ps1 stamps them at compile time from launcher\app\Updater.cs
// (Version = "x.y.z") so the stub tracks the launcher release number. The
// Downloads page and FAQ can still match on the stable name strings.
[assembly: AssemblyTitle("Thornswood Setup")]
[assembly: AssemblyDescription("Installs Thornswood, the Skyrim multiplayer client, from thornswood.net.")]
[assembly: AssemblyProduct("Thornswood Setup")]
[assembly: AssemblyCompany("Thornswood")]
[assembly: AssemblyCopyright("Copyright (c) Thornswood")]
[assembly: ComVisible(false)]

namespace ThornswoodSetup
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
        // TW for Thornswood. Written by Package-Thornswood.ps1 -OneFile from
        // the stub built out of this same file, so the two always agree.
        const string Magic = "TWSFX001";
        const int TrailerLen = 24;          // 8 magic + 8 offset + 8 length

        // Two shapes: the payload attached to the end of this program, or
        // nothing, in which case the published one is fetched from the site
        // and checked against the SHA-256 the site gives for it.
        //
        // A zip lying about is never used. This took the first setup zip or
        // payload.zip it found beside itself or anywhere in the Downloads
        // folder, before the payload attached to it and before asking the
        // site, unpacked it with no check at all and ran whatever Setup.bat
        // was inside. Anybody with a zip left over from an earlier download,
        // the old multiplayer mod's included, got that old install from a new
        // looking window. Nobody is told to put a zip beside this any more:
        // Publish-Installer publishes the payload hidden and the Downloads
        // page has one button.

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
        // C: is only where it starts when Skyrim cannot be found: Run replaces
        // this with Skyrim's own drive when Steam says where that is.
        static string installRoot = @"C:\Thornswood";
        static TextBlock txtRoot, txtRoom, txtSkyrim;
        static WrapPanel driveRow;
        static Button btnPick;
        static bool running;

        // The install itself, Setup-Thornswood.ps1, runs inside this window
        // now (issue #889): no console of its own, its lines in TxtLog and in
        // a log file, and its exit code the answer.
        static TextBox txtLog;
        static Border rootBox;
        static bool installing;
        static StreamWriter logFile;
        static readonly object logLock = new object();
        static string lastStop = "";

        [STAThread]
        static void Main()
        {
            // Per-monitor DPI is in the setup program's manifest (#463,
            // installer\setup\Setup.manifest). Framework WPF only rescales on a
            // change of monitor scale when this switch is false, and reads it
            // once, so it is set before any window or message box exists.
            AppContext.SetSwitch("Switch.System.Windows.DoNotScaleForDpiChanges", false);
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

        // ------------------------------------------------------- Skyrim's drive
        //
        // The launcher builds Thornswood its own game folder out of the Steam
        // copy of Skyrim, most of it as hard links so the collection is not on
        // the disk twice, and a hard link cannot cross a drive. So an install
        // on a different drive from Skyrim is an install that cannot play:
        // OwnGame.WhyNot names it and Play stops there. This window offered
        // every fixed drive with no hint which one that was, and C:\Thornswood
        // by default, so somebody who keeps games on D: found out after the
        // whole install. Issue #473.
        //
        // The walk is the launcher's, kept in step with launcher\app\Steam.cs
        // (Path_, Libraries, SkyrimCopies): Steam's own folder out of the
        // registry, then every path in config\libraryfolders.vdf, and the
        // first library holding steamapps\common\Skyrim Special Edition with
        // SkyrimSE.exe in it is the answer. The executable rather than the
        // folder, because uninstalling leaves the folder behind with the saves
        // and the screenshots still in it.
        //
        // Nothing here is a refusal. It steers, and says plainly what a
        // different drive costs, because whether the launcher may fall back to
        // copies instead is not this program's to decide.
        static string skyrimPath;

        /// <summary>Where Steam's copy of Skyrim Special Edition is, or "".</summary>
        static string SkyrimPath()
        {
            if (skyrimPath != null) return skyrimPath;
            skyrimPath = "";
            const string tail = "steamapps\\common\\Skyrim Special Edition";
            foreach (string lib in SteamLibraries())
            {
                try
                {
                    string game = Path.Combine(lib, tail);
                    if (!File.Exists(Path.Combine(game, "SkyrimSE.exe"))) continue;
                    skyrimPath = game;
                    break;
                }
                catch { }
            }
            return skyrimPath;
        }

        /// <summary>The drive Skyrim is on, as "D:\", or "" when it was not found.</summary>
        static string SkyrimDrive()
        {
            string game = SkyrimPath();
            if (game.Length == 0) return "";
            try { return Path.GetPathRoot(game); }
            catch { return ""; }
        }

        /// <summary>Where Steam itself is installed, or "".</summary>
        static string SteamPath()
        {
            foreach (string key in new string[] {
                @"Software\Valve\Steam", @"Software\Wow6432Node\Valve\Steam" })
            {
                try
                {
                    using (RegistryKey k = Registry.CurrentUser.OpenSubKey(key))
                    {
                        if (k == null) continue;
                        object v = k.GetValue("SteamPath");
                        if (v == null) continue;
                        string p = Convert.ToString(v).Replace('/', '\\');
                        if (p.Length > 0 && Directory.Exists(p)) return p;
                    }
                }
                catch { }
            }
            try
            {
                using (RegistryKey k = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Wow6432Node\Valve\Steam"))
                {
                    if (k != null)
                    {
                        object v = k.GetValue("InstallPath");
                        if (v != null)
                        {
                            string p = Convert.ToString(v);
                            if (p.Length > 0 && Directory.Exists(p)) return p;
                        }
                    }
                }
            }
            catch { }
            return "";
        }

        /// <summary>
        /// Every Steam library on this machine: Steam's own folder first, then
        /// each path in config\libraryfolders.vdf, in the order Steam lists
        /// them. Anybody with a second drive has more than one.
        /// </summary>
        static List<string> SteamLibraries()
        {
            var roots = new List<string>();
            string root = "";
            try { root = SteamPath(); } catch { }
            if (root.Length == 0) return roots;
            roots.Add(root);

            try
            {
                string vdf = Path.Combine(root, "config\\libraryfolders.vdf");
                if (File.Exists(vdf))
                {
                    foreach (string raw in File.ReadAllLines(vdf))
                    {
                        string[] parts = Quoted(raw.Trim());
                        if (parts.Length < 2) continue;
                        if (parts[0].ToLowerInvariant() != "path") continue;
                        // Valve escapes the separator in this file.
                        string p = parts[1].Replace("\\\\", "\\");
                        if (p.Length > 0) roots.Add(p);
                    }
                }
            }
            catch { }
            return roots;
        }

        // Everything between pairs of double quotes on one line. Valve's key
        // value text, read by hand rather than properly, because the only
        // question asked of it here is which paths are libraries.
        static string[] Quoted(string line)
        {
            var found = new List<string>();
            var sb = new StringBuilder();
            bool inside = false;
            foreach (char c in line)
            {
                if (c == '"')
                {
                    if (inside) { found.Add(sb.ToString()); sb.Length = 0; }
                    inside = !inside;
                    continue;
                }
                if (inside) sb.Append(c);
            }
            return found.ToArray();
        }

        static bool SameDrive(string a, string b)
        {
            if (string.IsNullOrEmpty(a) || string.IsNullOrEmpty(b)) return false;
            return string.Equals(a.TrimEnd('\\'), b.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase);
        }

        /// <summary>"D:" rather than "D:\", for the middle of a sentence.</summary>
        static string Letter(string driveRoot)
        {
            return driveRoot == null ? "" : driveRoot.TrimEnd('\\');
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

            string sky = SkyrimDrive();

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
                letter.Foreground = B("Ink");

                var room = new TextBlock();
                room.Text = Gb(free) + " free";
                room.FontSize = 11;
                room.Foreground = B("Muted");
                room.Margin = new Thickness(0, 3, 0, 0);

                var sp = new StackPanel();
                sp.Children.Add(letter);
                sp.Children.Add(room);

                // The one drive this install can work on gets said so on the
                // button itself, not only in the line underneath, because the
                // buttons are what a person reads before pressing one.
                if (SameDrive(d.Name, sky))
                {
                    var mark = new TextBlock();
                    mark.Text = "Skyrim is here";
                    mark.FontSize = 11;
                    mark.Foreground = B("Accent");
                    mark.Margin = new Thickness(0, 2, 0, 0);
                    sp.Children.Add(mark);
                }

                var b = new Button();
                b.Content = sp;
                b.Style = (Style)win.Resources["Btn"];
                b.Padding = new Thickness(15, 9, 15, 9);
                b.Margin = new Thickness(0, 0, 8, 8);
                b.MinWidth = 104;
                b.HorizontalContentAlignment = HorizontalAlignment.Left;
                b.Tag = captured.Name;
                b.BorderBrush = B("Line");
                b.Background = B("Deep");
                b.Foreground = B("Ink");
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
                b.Background = B(on ? "CardHover" : "Deep");
                b.BorderBrush = B(on ? "Accent" : "Line");
            }

            SaySkyrim(root);
            SayOwnGame();

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
                txtRoom.Foreground = B("Bad");
            }
            else if (free < want)
            {
                txtRoom.Text = Gb(free) + " free, and this " + about + Gb(want) +
                               ". That is close, so it may not fit.";
                txtRoom.Foreground = B("Warn");
            }
            else
            {
                txtRoom.Text = Gb(free) + " free, and this " + about + Gb(want) +
                               ". Everything is unpacked on the same drive, so nothing lands on C: unless you choose it.";
                txtRoom.Foreground = B("Faint");
            }
        }

        /// <summary>
        /// Says where Skyrim is against where this is about to install, under
        /// the drive buttons. A different drive is said in full, in the colour
        /// the window uses for something that will not work, because it is the
        /// one choice here that cannot be undone with a button afterwards.
        /// </summary>
        static void SaySkyrim(string root)
        {
            if (txtSkyrim == null) return;
            string sky = SkyrimDrive();

            if (sky.Length == 0)
            {
                txtSkyrim.Text = "Steam's copy of Skyrim Special Edition was not found on this PC, so this cannot " +
                                 "say which drive it is on. Thornswood has to go on the same drive as Skyrim, " +
                                 "because it builds its game folder out of your Steam copy with hard links and a " +
                                 "link cannot cross a drive.";
                txtSkyrim.Foreground = B("Warn");
                return;
            }

            // A path with no drive root to read is not a drive to warn about,
            // but Skyrim's is still worth naming.
            if (string.IsNullOrEmpty(root))
            {
                txtSkyrim.Text = "Skyrim is on " + Letter(sky) + ", and Thornswood has to go on that same drive. " +
                                 "It builds its game folder out of your Steam copy with hard links, and a link " +
                                 "cannot cross a drive.";
                txtSkyrim.Foreground = B("Warn");
                return;
            }

            if (SameDrive(sky, root))
            {
                txtSkyrim.Text = "Skyrim is on " + Letter(sky) + ", which is this drive. Thornswood builds its game " +
                                 "folder out of your Steam copy with hard links, which take no extra space, and that " +
                                 "only works on one drive.";
                txtSkyrim.Foreground = B("Faint");
                return;
            }

            txtSkyrim.Text = "Skyrim is on " + Letter(sky) + " and this would put Thornswood on " + Letter(root) +
                             ". Thornswood has to share Skyrim's drive: it builds a game folder of its own out of " +
                             "your Steam copy with hard links, and a link cannot cross a drive. Installed here, the " +
                             "launcher cannot build that folder and will not let you play. Pick " + Letter(sky) + ".";
            txtSkyrim.Foreground = B("Bad");
        }

        // --------------------------------------- Thornswood's own Skyrim folder
        //
        // Issue #906, Patrick on 28 September: "let's offer the own folder
        // during install as well". The launcher offers it in a box the first
        // time it opens and in Settings, Maintenance; a new person could only
        // find it there. This card asks the same question with the same words
        // before the launcher is ever opened.
        //
        // What it can and cannot do from here. The folder is Root\Game, made
        // by the launcher (OwnGame.Make) from what Vortex has deployed, and
        // nothing is deployed yet while this window is up: the collection is
        // the step after it. So a tick is the launcher's own question answered
        // in advance, written into config.json as MakeOwnGame, and the launcher
        // then makes the folder without asking once Vortex has deployed
        // (ShellOwnGame.AskOwnGame). No tick is what every install did before
        // this: the launcher asks. It stays that way by default. Thornswood
        // will not start out of a shared Skyrim either way (OwnGameRequired),
        // which is why the off line says Play asks for it too.
        //
        // The tick also decides where Thornswood's own files go (#1226,
        // Patrick, 29 Sep). Ticked, Setup-Thornswood.ps1 puts them in
        // Profile\Payload and nothing is written into the Steam copy; the
        // launcher makes the folder from them. Not ticked, they go into the
        // Steam copy as they always have, and the launcher takes them back
        // out once the folder is turned on and made (OwnGame.CleanSteamCopy).
        //
        // Choose Vortex's folder is the Settings button of the same name,
        // taken early: the same check as OwnGame.PointAt, saved into
        // config.json as the same VortexGame field.
        static CheckBox chkOwn;
        static TextBlock txtOwn;
        static Border ownBox;
        static Button btnVortexPick, btnVortexForget;
        // Read on the window's thread when Install is pressed, because Work
        // runs on another one and a WPF control may only be read on its own.
        static bool makeOwnGame;
        static string vortexGame = "";

        /// <summary>
        /// The line under the tick box: on or off, where the folder goes and
        /// what it is made from, whether the drive picked can hold it, and the
        /// chosen Vortex folder. Drawn again whenever any of those change.
        /// </summary>
        static void SayOwnGame()
        {
            if (txtOwn == null) return;
            string root = "";
            try { root = Path.GetPathRoot(installRoot); } catch { }

            string text;
            if (chkOwn != null && chkOwn.IsChecked == true)
            {
                text = "On. Thornswood will run from " + Path.Combine(installRoot, "Game") +
                       ", made from what Vortex has deployed" + (vortexGame.Length > 0 ? " in " + vortexGame : "") +
                       ". The launcher makes it by itself once Vortex has deployed the Thornswood collection, " +
                       "and restarts when it is done. Nothing is written into your Steam copy of Skyrim: " +
                       "Thornswood's own files wait beside the launcher until the folder is made.";
            }
            else
            {
                text = "Off for now. Thornswood's own files go into your Steam copy of Skyrim, and the launcher asks " +
                       "before it makes the folder; Settings, Maintenance has the button, and once the folder is made " +
                       "the launcher takes Thornswood's files back out of the Steam copy. Thornswood will not start out " +
                       "of a Skyrim shared with other servers, so Play asks for it too.";
            }

            // The same drive logic as the line under the drive buttons: the
            // folder is mostly hard links out of the Steam copy.
            string sky = SkyrimDrive();
            bool apart = sky.Length > 0 && !string.IsNullOrEmpty(root) && !SameDrive(sky, root);
            if (apart)
                text += "\nIt cannot be made on " + Letter(root) + ", because Skyrim is on " + Letter(sky) +
                        " and a link cannot cross a drive.";
            if (vortexGame.Length > 0)
                text += "\nVortex's folder is set to " + vortexGame + ". Forget the chosen folder to have Thornswood look for it again.";

            txtOwn.Text = text;
            txtOwn.Foreground = B(apart ? "Bad" : "Faint");
            if (btnVortexForget != null)
                btnVortexForget.Visibility = vortexGame.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
        }

        /// <summary>
        /// Null when the launcher's OwnGame.PointAt would take this folder, else
        /// its sentence saying why not. <paramref name="full"/> is the folder as
        /// it is saved: quotes off, the full path, no trailing backslash.
        /// </summary>
        static string VortexFolderProblem(string folder, out string full)
        {
            full = (folder ?? "").Trim().Trim('"').Trim();
            string f = full;
            try { f = Path.GetFullPath(f).TrimEnd('\\'); }
            catch { return f + " is not a folder Thornswood can read, so nothing changed."; }
            full = f;
            if (!File.Exists(Path.Combine(f, "SkyrimSE.exe")))
                return f + " has no SkyrimSE.exe in it, so it is not a Skyrim folder and nothing changed. Choose the folder that Open Game Folder opens in Vortex.";
            if (!File.Exists(Path.Combine(f, "Data\\vortex.deployment.json")))
                return "Vortex has not deployed into " + f + ": it has no Data\\vortex.deployment.json, the record Vortex leaves in every folder it deploys to, so nothing changed. Choose the folder that Open Game Folder opens in Vortex.";
            return null;
        }

        static void PickVortexFolder()
        {
            string chosen;
            try
            {
                var dlg = new System.Windows.Forms.FolderBrowserDialog();
                dlg.Description = "Choose the Skyrim folder Vortex deploys into. In Vortex, Mods, Open, Open Game Folder opens it.";
                dlg.ShowNewFolderButton = false;
                string start = vortexGame.Length > 0 ? vortexGame : SkyrimPath();
                if (start.Length > 0 && Directory.Exists(start)) dlg.SelectedPath = start;
                if (dlg.ShowDialog() != System.Windows.Forms.DialogResult.OK) return;
                chosen = dlg.SelectedPath;
            }
            catch (Exception ex)
            {
                MessageBox.Show("Could not open the folder picker: " + ex.Message,
                                "Thornswood Setup", MessageBoxButton.OK, MessageBoxImage.Error);
                return;
            }
            string full;
            string why = VortexFolderProblem(chosen, out full);
            if (why != null)
            {
                MessageBox.Show(why, "Thornswood Setup", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }
            vortexGame = full;
            SayOwnGame();
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

        // ==== the three pages a person accepts ====
        // Issue #1009, Patrick on 28 September: "check boxes that lock the
        // install for reading and accepting terms and conditions, privacy
        // policy, and agreeing to the rules", "and links to all 3". Each name
        // is the page's address on the site, its name for /api/page, and the
        // ChkX and LnkX in the window. tests\test-setup-agreements.ps1 holds
        // the three together and proves Install stays off until all are ticked.
        static readonly string[] Pages = { "terms", "privacy", "rules" };
        const string AcceptedFile = "accepted.json";
        static CheckBox[] agree;
        static DateTime acceptedAt;

        static string Cap(string s)
        {
            return char.ToUpperInvariant(s[0]) + s.Substring(1);
        }

        /// <summary>The three page boxes in the order of Pages, or null when any is missing.</summary>
        static CheckBox[] FindAgreements(FrameworkElement w)
        {
            var found = new CheckBox[Pages.Length];
            for (int i = 0; i < Pages.Length; i++)
            {
                found[i] = w.FindName("Chk" + Cap(Pages[i])) as CheckBox;
                if (found[i] == null) return null;
            }
            return found;
        }

        /// <summary>Install is on only while every box is ticked, looked at again on each tick and untick.</summary>
        static void Gate(Button go, CheckBox[] boxes)
        {
            RoutedEventHandler check = delegate { go.IsEnabled = AllTicked(boxes); };
            foreach (CheckBox c in boxes)
            {
                if (c == null) continue;
                c.Checked += check;
                c.Unchecked += check;
            }
            go.IsEnabled = AllTicked(boxes);
        }

        static bool AllTicked(CheckBox[] boxes)
        {
            if (boxes == null || boxes.Length == 0) return false;
            foreach (CheckBox c in boxes)
            {
                if (c == null || c.IsChecked != true) return false;
            }
            return true;
        }

        static void HookPageLinks(FrameworkElement w)
        {
            foreach (string p in Pages)
            {
                var link = w.FindName("Lnk" + Cap(p)) as System.Windows.Documents.Hyperlink;
                if (link == null) continue;
                link.RequestNavigate += delegate(object s, System.Windows.Navigation.RequestNavigateEventArgs e)
                {
                    OpenPage(e.Uri);
                    e.Handled = true;
                };
            }
        }

        /// <summary>
        /// The browser, on one of the site's own pages and nothing else. This
        /// is the one Process.Start in the setup program, and it only ever
        /// hands Windows an https address on thornswood.net.
        /// </summary>
        static void OpenPage(Uri uri)
        {
            string url = uri == null ? "" : uri.AbsoluteUri;
            if (!url.StartsWith(Site + "/", StringComparison.OrdinalIgnoreCase)) return;
            try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); }
            catch (Exception)
            {
                MessageBox.Show(win, "Windows would not open your browser. The page is at " + url + ".",
                                "Thornswood Setup", MessageBoxButton.OK, MessageBoxImage.Information);
            }
        }

        /// <summary>
        /// A JSON string's value by its key, unescaped, or null. Enough for
        /// the site's page answer, {"md":"...","html":"..."}, without a JSON
        /// library in a program that has none.
        /// </summary>
        static string JsonString(string doc, string key)
        {
            if (doc == null) return null;
            string head = "\"" + key + "\":";
            int i = doc.IndexOf(head, StringComparison.Ordinal);
            if (i < 0) return null;
            i += head.Length;
            while (i < doc.Length && char.IsWhiteSpace(doc[i])) i++;
            if (i >= doc.Length || doc[i] != '"') return null;
            var sb = new StringBuilder();
            for (i++; i < doc.Length; i++)
            {
                char c = doc[i];
                if (c == '"') return sb.ToString();
                if (c != '\\') { sb.Append(c); continue; }
                if (++i >= doc.Length) return null;
                char e = doc[i];
                if (e == 'n') sb.Append('\n');
                else if (e == 'r') sb.Append('\r');
                else if (e == 't') sb.Append('\t');
                else if (e == 'b') sb.Append('\b');
                else if (e == 'f') sb.Append('\f');
                else if (e == 'u')
                {
                    if (i + 4 >= doc.Length) return null;
                    sb.Append((char)Convert.ToInt32(doc.Substring(i + 1, 4), 16));
                    i += 4;
                }
                else sb.Append(e);
            }
            return null;
        }

        /// <summary>SHA-256 of a page's text as UTF-8, lower case hex: the version that was accepted.</summary>
        static string PageSha(string md)
        {
            if (md == null) return "";
            using (var h = SHA256.Create())
            {
                byte[] d = h.ComputeHash(new UTF8Encoding(false).GetBytes(md));
                var sb = new StringBuilder();
                foreach (byte b in d) sb.Append(b.ToString("x2"));
                return sb.ToString();
            }
        }

        /// <summary>
        /// What goes in Profile\accepted.json. shas are in the order of Pages,
        /// empty for a page the site did not answer for. No name, no account,
        /// nothing about the machine: when, which pages, which versions.
        /// </summary>
        static string AcceptanceJson(DateTime at, string[] shas)
        {
            var sb = new StringBuilder();
            sb.Append("{\n");
            sb.Append("  \"accepted\": \"" + at.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'",
                      System.Globalization.CultureInfo.InvariantCulture) + "\",\n");
            sb.Append("  \"pages\": {\n");
            for (int i = 0; i < Pages.Length; i++)
            {
                string sha = shas != null && i < shas.Length && shas[i] != null ? shas[i] : "";
                sb.Append("    \"" + Pages[i] + "\": { \"url\": \"" + Site + "/" + Pages[i] +
                          "\", \"sha256\": \"" + sha + "\" }" + (i < Pages.Length - 1 ? "," : "") + "\n");
            }
            sb.Append("  },\n");
            sb.Append("  \"about\": \"Ticked in Thornswood Setup before Install. sha256 is of each page's text as " +
                      Site + "/api/page/<name> served it when Install was pressed, and is empty when the site " +
                      "did not answer.\"\n");
            sb.Append("}\n");
            return sb.ToString();
        }

        /// <summary>The page's text as the site serves it now, or null.</summary>
        static string FetchPage(string name)
        {
            ServicePointManager.SecurityProtocol |= (SecurityProtocolType)3072; // Tls12 added, never replaced (#1360)
            var req = (HttpWebRequest)WebRequest.Create(Site + "/api/page/" + name);
            req.UserAgent = "ThornswoodSetup";
            req.Timeout = 15000;
            req.ReadWriteTimeout = 15000;
            using (var resp = (HttpWebResponse)req.GetResponse())
            using (var r = new StreamReader(resp.GetResponseStream(), new UTF8Encoding(false)))
            {
                return JsonString(r.ReadToEnd(), "md");
            }
        }

        /// <summary>
        /// Writes Profile\accepted.json in the install. Never stops the
        /// install: the boxes were ticked whatever the site or the disk says.
        /// </summary>
        static void RecordAcceptance(string profileDir, DateTime at)
        {
            var shas = new string[Pages.Length];
            for (int i = 0; i < Pages.Length; i++)
            {
                try { shas[i] = PageSha(FetchPage(Pages[i])); }
                catch (Exception) { shas[i] = ""; }
            }
            try
            {
                Directory.CreateDirectory(profileDir);
                File.WriteAllText(Path.Combine(profileDir, AcceptedFile), AcceptanceJson(at, shas), new UTF8Encoding(false));
            }
            catch (Exception e) { Say("Could not note what you accepted: " + e.Message); }
        }
        // ==== end the three pages a person accepts ====

        // A colour of the window by its name in the launcher's Themes.cs
        // (Ink, Faint, Bad and the rest), never a literal: the window is drawn
        // in Forge from there (#2851), so the setup program's text reaches the
        // same 4.5 to 1 as the launcher's and cannot fall behind it again.
        static Brush B(string name)
        {
            return (Brush)win.FindResource(name);
        }

        // Built from markup rather than by hand, because a WPF Button keeps its
        // own chrome unless you replace the template, and setting Background on
        // one gets you the system button with an odd tint instead of the button
        // you meant.
        const string Ui = @"
<Window xmlns=""http://schemas.microsoft.com/winfx/2006/xaml/presentation""
        xmlns:x=""http://schemas.microsoft.com/winfx/2006/xaml""
        Title=""Thornswood Setup"" Width=""700"" Height=""800""
        MinWidth=""560"" MinHeight=""520""
        ResizeMode=""CanResize"" WindowStartupLocation=""Manual""
        Background=""{DynamicResource Bg}"" FontFamily=""Segoe UI""
        TextOptions.TextFormattingMode=""Display"">
  <Window.Resources>
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

  <Border BorderBrush=""{DynamicResource Line}"" BorderThickness=""1"">
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height=""Auto""/>
        <RowDefinition Height=""*""/>
        <RowDefinition Height=""Auto""/>
      </Grid.RowDefinitions>

      <Border Grid.Row=""0"" Background=""{DynamicResource Panel}""
              BorderBrush=""{DynamicResource Line}"" BorderThickness=""0,0,0,1"">
        <Grid>
          <Rectangle Fill=""{StaticResource Hatch}"" Opacity=""0.85""/>
          <StackPanel Margin=""36,24,36,22"" Orientation=""Horizontal"">
            <Image x:Name=""Logo"" Width=""78"" Height=""78"" Margin=""0,0,22,0"" VerticalAlignment=""Center""
                   RenderOptions.BitmapScalingMode=""HighQuality"" Visibility=""Collapsed""/>
            <StackPanel VerticalAlignment=""Center"">
            <TextBlock Text=""Setup"" Foreground=""{DynamicResource Faint}"" FontSize=""13""
                       FontFamily=""Constantia, Georgia"" Typography.Capitals=""SmallCaps""
                       TextOptions.TextFormattingMode=""Ideal"" Margin=""1,0,0,4""/>
            <TextBlock x:Name=""TxtHead"" Text=""Thornswood"" Foreground=""{DynamicResource Ink}""
                       FontSize=""30"" FontFamily=""Constantia, Georgia""
                       Typography.Capitals=""SmallCaps"" TextOptions.TextFormattingMode=""Ideal""/>
            <Rectangle Height=""2"" Width=""42"" Fill=""{DynamicResource Accent}""
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
                   Foreground=""{DynamicResource Muted}"" FontSize=""13"" LineHeight=""21""
                   TextWrapping=""Wrap""
                   Text=""This puts the launcher and Thornswood's own content on your PC. With Thornswood's own Skyrim folder chosen below, it does not install into the Skyrim you already have on Steam, and that copy is left as it is, for you to play and mod however you like. Without it, Thornswood's own content goes into that copy until you turn the folder on in the launcher, which then takes it back out.&#10;&#10;Thornswood runs from its own game folder. The launcher builds it out of your Steam copy and what Vortex has deployed there, most of it as hard links that take no extra space, and copies of the few files other programs rewrite. Hard links only work inside one drive, so Thornswood goes on the same drive as Skyrim.&#10;&#10;The mods themselves come from a collection on Nexus. Vortex installs them into a profile of their own, so switching back to your usual profile and running Purge Mods leaves your Skyrim where you started. The launcher has the link and walks you through it.&#10;&#10;Nothing of Bethesda's is renamed or deleted. You need Steam running and Skyrim on build 1.6.1170.""/>

        <Border x:Name=""RootBox"" Grid.Row=""1"" Margin=""0,20,0,0"" Padding=""17,14"" CornerRadius=""2""
                Background=""{DynamicResource Card}"" BorderBrush=""{DynamicResource Line}"" BorderThickness=""1"">
          <StackPanel>
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width=""*""/>
                <ColumnDefinition Width=""Auto""/>
              </Grid.ColumnDefinitions>
              <StackPanel Grid.Column=""0"">
                <TextBlock Text=""Install to"" Foreground=""{DynamicResource Faint}"" FontSize=""12""
                           FontFamily=""Constantia, Georgia"" Typography.Capitals=""SmallCaps""
                           TextOptions.TextFormattingMode=""Ideal"" Margin=""0,0,0,6""/>
                <TextBlock x:Name=""TxtRoot"" Foreground=""{DynamicResource Ink}"" FontSize=""14""
                           FontFamily=""Cascadia Mono, Consolas"" TextTrimming=""CharacterEllipsis""/>
              </StackPanel>
              <Button x:Name=""BtnPick"" Grid.Column=""1"" Style=""{StaticResource Btn}"" Content=""Another folder""
                      Padding=""16,7"" FontSize=""12"" VerticalAlignment=""Bottom""
                      Background=""{DynamicResource Deep}"" BorderBrush=""{DynamicResource Line}""
                      Foreground=""{DynamicResource Ink}""/>
            </Grid>
            <WrapPanel x:Name=""DriveRow"" Margin=""0,13,0,0""/>
            <TextBlock x:Name=""TxtSkyrim"" Foreground=""{DynamicResource Faint}"" FontSize=""11.5""
                       TextWrapping=""Wrap"" LineHeight=""18"" Margin=""0,11,0,0""/>
            <TextBlock x:Name=""TxtRoom"" Foreground=""{DynamicResource Faint}"" FontSize=""11.5""
                       TextWrapping=""Wrap"" Margin=""0,8,0,0""/>
          </StackPanel>
        </Border>

        <!-- Thornswood's own Skyrim folder, offered here as well as in the
             launcher's Settings, Maintenance (issue #906). The words are that
             panel's own, launcher\ui.xaml PnlOwnGame, so the two say the same
             thing. -->
        <Border x:Name=""OwnBox"" Margin=""0,14,0,0"" Padding=""17,14"" CornerRadius=""2""
                Background=""{DynamicResource Card}"" BorderBrush=""{DynamicResource Line}"" BorderThickness=""1"">
          <StackPanel>
            <TextBlock Text=""Thornswood's own Skyrim folder"" Foreground=""{DynamicResource Faint}"" FontSize=""12""
                       FontFamily=""Constantia, Georgia"" Typography.Capitals=""SmallCaps""
                       TextOptions.TextFormattingMode=""Ideal"" Margin=""0,0,0,6""/>
            <TextBlock x:Name=""TxtOwnAbout"" Foreground=""{DynamicResource Muted}"" FontSize=""11.5"" LineHeight=""18""
                       TextWrapping=""Wrap""
                       Text=""Runs Thornswood from a Skyrim folder of its own, made from what Vortex has deployed while the Thornswood profile is on. Any other Vortex profile can then use the Steam copy without reaching Thornswood, and switching profiles in Vortex no longer takes Thornswood's mods away. The big files are links to Vortex's copies, so the collection is not on the disk twice. When Vortex deploys a newer Thornswood collection, the launcher brings it in by itself the next time it starts.""/>
            <CheckBox x:Name=""ChkOwnGame"" Margin=""0,12,0,0"" Foreground=""{DynamicResource Ink}"">
              <TextBlock Foreground=""{DynamicResource Ink}"" FontSize=""12.5"" LineHeight=""18""
                         TextWrapping=""Wrap"" Margin=""4,0,0,0""
                         Text=""Give Thornswood a Skyrim folder of its own""/>
            </CheckBox>
            <TextBlock x:Name=""TxtOwnGame"" Foreground=""{DynamicResource Faint}"" FontSize=""11.5"" LineHeight=""18""
                       TextWrapping=""Wrap"" Margin=""0,8,0,0""/>
            <TextBlock Foreground=""{DynamicResource Faint}"" FontSize=""11.5"" LineHeight=""18""
                       TextWrapping=""Wrap"" Margin=""0,12,0,0""
                       Text=""The launcher finds the folder Vortex deploys into when it is in a Steam library. If it is somewhere else, choose it here: in Vortex, Mods, Open, Open Game Folder shows which one. Only the files Vortex lists in it are used, and the game itself always comes from the Steam copy.""/>
            <StackPanel Orientation=""Horizontal"" Margin=""0,9,0,0"">
              <Button x:Name=""BtnVortexPick"" Style=""{StaticResource Btn}"" Content=""Choose Vortex's folder""
                      Padding=""16,7"" FontSize=""12"" Margin=""0,0,8,0""
                      Background=""{DynamicResource Deep}"" BorderBrush=""{DynamicResource Line}""
                      Foreground=""{DynamicResource Ink}""/>
              <Button x:Name=""BtnVortexForget"" Style=""{StaticResource Btn}"" Content=""Forget the chosen folder""
                      Padding=""16,7"" FontSize=""12"" Visibility=""Collapsed""
                      Background=""{DynamicResource Deep}"" BorderBrush=""{DynamicResource Line}""
                      Foreground=""{DynamicResource Ink}""/>
            </StackPanel>
          </StackPanel>
        </Border>

        <Border x:Name=""FoundBox"" Margin=""0,14,0,0"" Padding=""17,14""
                CornerRadius=""2"" Background=""{DynamicResource Card}""
                BorderBrush=""{DynamicResource Line}"" BorderThickness=""1"">
          <StackPanel>
            <TextBlock Text=""Installing from"" Foreground=""{DynamicResource Faint}"" FontSize=""12""
                       FontFamily=""Constantia, Georgia"" Typography.Capitals=""SmallCaps""
                       TextOptions.TextFormattingMode=""Ideal"" Margin=""0,0,0,6""/>
            <TextBlock x:Name=""TxtFound"" Foreground=""{DynamicResource Ink}"" FontSize=""13""
                       TextWrapping=""Wrap"" LineHeight=""20"" Text=""Looking...""/>
          </StackPanel>
        </Border>

        <!-- What the install script prints, shown here in place of the two
             boxes above once it starts, instead of in a console of its own. -->
        <TextBox x:Name=""TxtLog"" Margin=""0,16,0,0"" Height=""330"" Visibility=""Collapsed""
                 IsReadOnly=""True"" TextWrapping=""Wrap"" VerticalScrollBarVisibility=""Auto""
                 FontFamily=""Cascadia Mono, Consolas"" FontSize=""11.5"" Padding=""10,8""
                 Background=""{DynamicResource Deep}"" Foreground=""{DynamicResource Muted}""
                 BorderBrush=""{DynamicResource Line}"" BorderThickness=""1""/>

          </StackPanel>
        </ScrollViewer>

        <StackPanel Grid.Row=""1"" VerticalAlignment=""Bottom"" Margin=""0,0,0,4"">
          <ProgressBar x:Name=""Bar"" Height=""5"" Minimum=""0"" Maximum=""1000""
                       Foreground=""{DynamicResource Accent}"" Background=""{DynamicResource Deep}""
                       BorderThickness=""0"" Margin=""0,20,0,0"" Visibility=""Collapsed""/>
          <TextBlock x:Name=""TxtStat"" Foreground=""{DynamicResource Faint}"" FontSize=""11.5""
                     FontFamily=""Cascadia Mono, Consolas"" Margin=""0,11,0,0""
                     TextTrimming=""CharacterEllipsis""/>
        </StackPanel>
      </Grid>

      <Border Grid.Row=""2"" Background=""{DynamicResource Panel}""
              BorderBrush=""{DynamicResource Line}"" BorderThickness=""0,1,0,0"" Padding=""36,18"">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width=""*""/>
            <ColumnDefinition Width=""Auto""/>
          </Grid.ColumnDefinitions>
          <!-- Install stays off until all four boxes are ticked (issue #1009
               added the three pages). Each link opens that page on the site
               in the browser, so what a person reads is the current text and
               never a copy in here that goes stale. The link sits beside its
               box, not inside it, so opening the page does not tick it, and
               goes under it on a narrow window, where the words wrap. -->
          <StackPanel Grid.Column=""0"" VerticalAlignment=""Center"" Margin=""0,0,24,0"">
            <CheckBox x:Name=""ChkAge"" Foreground=""{DynamicResource Ink}"">
              <TextBlock Foreground=""{DynamicResource Ink}"" FontSize=""12.5"" LineHeight=""18""
                         TextWrapping=""Wrap"" Margin=""4,0,0,0""
                         Text=""I am 18 or over. Thornswood is an adult server.""/>
            </CheckBox>
            <WrapPanel Margin=""0,7,0,0"">
              <CheckBox x:Name=""ChkTerms"" Foreground=""{DynamicResource Ink}"" VerticalAlignment=""Center""
                        MaxWidth=""{Binding ActualWidth, RelativeSource={RelativeSource AncestorType=StackPanel}}"">
                <TextBlock Foreground=""{DynamicResource Ink}"" FontSize=""12.5"" Margin=""4,0,0,0"" TextWrapping=""Wrap""
                           Text=""I have read and accept the Terms and Conditions""/>
              </CheckBox>
              <TextBlock FontSize=""12.5"" Margin=""10,0,0,0"" VerticalAlignment=""Center"">
                <Hyperlink x:Name=""LnkTerms"" NavigateUri=""https://thornswood.net/terms""
                           Foreground=""{DynamicResource Accent}""
                           ToolTip=""Opens thornswood.net/terms in your browser"">Read them</Hyperlink>
              </TextBlock>
            </WrapPanel>
            <WrapPanel Margin=""0,7,0,0"">
              <CheckBox x:Name=""ChkPrivacy"" Foreground=""{DynamicResource Ink}"" VerticalAlignment=""Center""
                        MaxWidth=""{Binding ActualWidth, RelativeSource={RelativeSource AncestorType=StackPanel}}"">
                <TextBlock Foreground=""{DynamicResource Ink}"" FontSize=""12.5"" Margin=""4,0,0,0"" TextWrapping=""Wrap""
                           Text=""I have read and accept the Privacy Policy""/>
              </CheckBox>
              <TextBlock FontSize=""12.5"" Margin=""10,0,0,0"" VerticalAlignment=""Center"">
                <Hyperlink x:Name=""LnkPrivacy"" NavigateUri=""https://thornswood.net/privacy""
                           Foreground=""{DynamicResource Accent}""
                           ToolTip=""Opens thornswood.net/privacy in your browser"">Read it</Hyperlink>
              </TextBlock>
            </WrapPanel>
            <WrapPanel Margin=""0,7,0,0"">
              <CheckBox x:Name=""ChkRules"" Foreground=""{DynamicResource Ink}"" VerticalAlignment=""Center""
                        MaxWidth=""{Binding ActualWidth, RelativeSource={RelativeSource AncestorType=StackPanel}}"">
                <TextBlock Foreground=""{DynamicResource Ink}"" FontSize=""12.5"" Margin=""4,0,0,0"" TextWrapping=""Wrap""
                           Text=""I have read and agree to the Rules""/>
              </CheckBox>
              <TextBlock FontSize=""12.5"" Margin=""10,0,0,0"" VerticalAlignment=""Center"">
                <Hyperlink x:Name=""LnkRules"" NavigateUri=""https://thornswood.net/rules""
                           Foreground=""{DynamicResource Accent}""
                           ToolTip=""Opens thornswood.net/rules in your browser"">Read them</Hyperlink>
              </TextBlock>
            </WrapPanel>
          </StackPanel>
          <StackPanel Grid.Column=""1"" Orientation=""Horizontal"" HorizontalAlignment=""Right""
                      VerticalAlignment=""Bottom"">
            <Button x:Name=""BtnClose"" Style=""{StaticResource Btn}"" Content=""Not now""
                    Background=""{DynamicResource Card}"" BorderBrush=""{DynamicResource Line}""
                    Foreground=""{DynamicResource Ink}"" Margin=""0,0,10,0""/>
            <Button x:Name=""BtnGo"" Style=""{StaticResource Btn}"" Content=""Install"" IsEnabled=""False""
                    Background=""{DynamicResource Accent}"" BorderBrush=""{DynamicResource Accent}""
                    Foreground=""{DynamicResource AccentInk}"" FontWeight=""SemiBold""/>
          </StackPanel>
        </Grid>
      </Border>
    </Grid>
  </Border>
</Window>";

        static void Run()
        {
            win = (Window)XamlReader.Parse(Ui);
            // Every colour in the markup is a DynamicResource by name, filled
            // in here from the launcher's Forge (#2851) before anything is
            // drawn or reads one.
            Thornswood.Themes.Apply(win, "Forge");

            txtHead  = (TextBlock)win.FindName("TxtHead");
            txtBody  = (TextBlock)win.FindName("TxtBody");
            txtFound = (TextBlock)win.FindName("TxtFound");
            txtStat  = (TextBlock)win.FindName("TxtStat");
            bar      = (ProgressBar)win.FindName("Bar");
            btnGo    = (Button)win.FindName("BtnGo");
            btnClose = (Button)win.FindName("BtnClose");
            foundBox = (Border)win.FindName("FoundBox");
            txtLog   = (TextBox)win.FindName("TxtLog");
            rootBox  = (Border)win.FindName("RootBox");

            txtRoot   = (TextBlock)win.FindName("TxtRoot");
            txtRoom   = (TextBlock)win.FindName("TxtRoom");
            txtSkyrim = (TextBlock)win.FindName("TxtSkyrim");
            driveRow  = (WrapPanel)win.FindName("DriveRow");
            btnPick   = (Button)win.FindName("BtnPick");
            btnPick.Click += delegate { PickFolder(); };

            ownBox          = (Border)win.FindName("OwnBox");
            chkOwn          = (CheckBox)win.FindName("ChkOwnGame");
            txtOwn          = (TextBlock)win.FindName("TxtOwnGame");
            btnVortexPick   = (Button)win.FindName("BtnVortexPick");
            btnVortexForget = (Button)win.FindName("BtnVortexForget");
            if (chkOwn != null)
            {
                chkOwn.Checked   += delegate { SayOwnGame(); };
                chkOwn.Unchecked += delegate { SayOwnGame(); };
            }
            if (btnVortexPick != null) btnVortexPick.Click += delegate { PickVortexFolder(); };
            if (btnVortexForget != null) btnVortexForget.Click += delegate { vortexGame = ""; SayOwnGame(); };

            // Start on the drive Skyrim is on. It is the only drive this
            // install can play from, and it is not something a person can put
            // right with a button afterwards: it is a reinstall, or moving a
            // Steam library. C:\Thornswood stays the answer when there is no
            // Steam copy to find.
            string sky = SkyrimDrive();
            if (sky.Length > 0)
            {
                try { installRoot = Path.Combine(sky, "Thornswood").TrimEnd('\\'); }
                catch { }
            }

            BuildDrives();
            SetRoot(installRoot);

            var logo = (Image)win.FindName("Logo");
            BitmapImage art = Emblem();
            if (logo != null && art != null) { logo.Source = art; logo.Visibility = Visibility.Visible; }
            if (art != null) win.Icon = art;

            btnClose.Click += delegate { win.Close(); };
            btnGo.Click += delegate { Start(); };

            // Install starts switched off and these are the only thing that
            // turns it on: the age box, then the terms, the privacy policy and
            // the rules (issue #1009), all four ticked. A box somebody can
            // ignore and press Install anyway is decoration, so they gate the
            // button rather than sitting next to it.
            chkAge = (CheckBox)win.FindName("ChkAge");
            agree = FindAgreements(win);
            HookPageLinks(win);
            if (chkAge != null && agree != null)
            {
                btnGo.IsEnabled = false;
                var all = new List<CheckBox>();
                all.Add(chkAge);
                all.AddRange(agree);
                Gate(btnGo, all.ToArray());
            }
            else
            {
                // Rather than an installer nobody can ever start.
                btnGo.IsEnabled = true;
            }

            win.Closing += delegate(object s, System.ComponentModel.CancelEventArgs e)
            {
                // Once the install script is moving files, stopping half way
                // leaves half of them moved. Nothing in it waits for ever: its
                // one question comes to this window and every other read stops
                // it, so it ends by itself.
                if (installing)
                {
                    MessageBox.Show(win, "Thornswood is being installed and cannot be stopped part way, because " +
                                    "that would leave it half moved. This window closes by itself when it is done.",
                                    "Thornswood Setup", MessageBoxButton.OK, MessageBoxImage.Information);
                    e.Cancel = true;
                    return;
                }
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
                // No bigger than the screen at any display scale, minimum
                // included, so Install is never below its edge (#463).
                // WindowFit.cs is launcher\app's, compiled in by Build-Launcher.
                Thornswood.WindowFit.Keep(win);
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
                foundBox.BorderBrush = B("Bad");
                txtFound.Foreground = B("Bad");
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
            // spell TWSFX001 by accident is caught by checking that what it
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
            ServicePointManager.SecurityProtocol |= (SecurityProtocolType)3072; // Tls12 added, never replaced (#1360)

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
                // What Publish-Installer measured on the zip it sent. A site
                // that carries no such field, or an empty one, leaves this
                // empty, and nothing is fetched: the bytes behind this url are
                // unpacked and run, so there is nothing to measure them with.
                sha = Between(doc, "\"sha256\":\"", "\"").Trim();
            }
            catch (Exception e)
            {
                throw new Exception("Could not reach " + Site + " to get Thornswood's files. Check the " +
                                    "connection and run this again. (" + e.Message + ")");
            }
            if (url.Length == 0) throw new Exception("The site is not offering a download right now. Try again in a bit.");
            url = PayloadUrl(Site, url);
            if (sha.Length == 0)
                throw new Exception("The site is not saying what the download should measure, so nothing has been " +
                                    "fetched and nothing was run. Try again in a bit.");
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
                Say("Checking Thornswood's files");
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
            Say("Checking Thornswood's files");
            CheckPayload(target, sha);
            return target;
        }

        /// <summary>
        /// Where the payload may be fetched from. A relative url is joined
        /// onto the site as it always was; an absolute one has to be https,
        /// and http, or any other scheme, is refused rather than fetched,
        /// because what comes down this url is unpacked and run on the
        /// machine of somebody installing for the first time. Updater.cs
        /// CheckUrl holds the launcher to the same.
        /// </summary>
        static string PayloadUrl(string site, string url)
        {
            // A scheme is the letters, digits, plus, minus and dots before the
            // first colon. Read by hand rather than through Uri, which answers
            // differently about a leading slash depending on the machine it
            // runs on. A colon further along a path is part of the path.
            int colon = url.IndexOf(':');
            bool absolute = colon > 0;
            for (int i = 0; i < colon; i++)
            {
                char c = url[i];
                if (char.IsLetterOrDigit(c) || c == '+' || c == '-' || c == '.') continue;
                absolute = false;
                break;
            }
            if (!absolute) return site + url;
            if (!url.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
                throw new Exception("The site offered the download over something other than https, so nothing " +
                                    "has been fetched. Try again in a bit.");
            return url;
        }

        /// <summary>
        /// Whether the file is the one the site published. An empty hash is
        /// not a pass. It used to be, so that a new installer against a site
        /// from before the hash still installed, which made one blank field
        /// on the site enough to unpack and run whatever came down. Nothing
        /// here runs unmeasured now, the standard Updater.cs already holds
        /// the launcher to.
        /// </summary>
        static bool PayloadMatches(string file, string sha)
        {
            if (sha == null) return false;
            sha = sha.Trim();
            if (sha.Length == 0) return false;
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
        /// rather than carrying on from bad bytes. A payload with no hash to
        /// measure it against goes the same way, though Download stops before
        /// it fetches anything when the site gives none.
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

                // Said once more on the way out, because the line under the
                // drive buttons can be scrolled past and this is the last
                // moment it costs nothing. It asks rather than refuses:
                // whether the launcher may build the folder some other way on
                // a second drive is a decision for Patrick and Djinn, not for
                // the installer to take by blocking it here (issue #473).
                string sky = SkyrimDrive();
                if (sky.Length > 0 && !SameDrive(sky, root))
                {
                    if (MessageBox.Show("Skyrim is on " + Letter(sky) + " and this would install Thornswood on " +
                                        Letter(root) + ".\n\nThornswood builds a game folder of its own out of your " +
                                        "Steam copy of Skyrim, with hard links, and a link cannot cross a drive. On " +
                                        Letter(root) + " the launcher cannot build that folder, and it will not let " +
                                        "you play until Thornswood and Skyrim are on one drive.\n\nNo goes back so you " +
                                        "can pick " + Letter(sky) + ". Yes installs on " + Letter(root) + " anyway.",
                                        "Thornswood Setup", MessageBoxButton.YesNo,
                                        MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
                }

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
            if (agree != null) foreach (CheckBox c in agree) c.IsEnabled = false;
            // When the boxes were ticked and Install pressed, for the record
            // Work writes (issue #1009).
            acceptedAt = DateTime.UtcNow;
            btnPick.IsEnabled = false;
            // The own folder choice as it stands now, for Work on its own thread.
            makeOwnGame = chkOwn != null && chkOwn.IsChecked == true;
            if (chkOwn != null) chkOwn.IsEnabled = false;
            if (btnVortexPick != null) btnVortexPick.IsEnabled = false;
            if (btnVortexForget != null) btnVortexForget.IsEnabled = false;
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
        ///
        /// It is asked for politely, and the last resort is asked about.
        /// CloseMainWindow is the window's own close button and a running game
        /// saves and exits on it; Kill is not, and a program that ends
        /// somebody's game without a word is both rude and exactly the shape a
        /// behaviour scanner is built to flag. Five engines on VirusTotal
        /// flagged the setup stub on 27 September with nothing but machine
        /// learning verdicts behind it, and this was one of the two things it
        /// did that earned them (docs\VIRUSTOTAL-FALSE-POSITIVE.md). So
        /// anything still alive after the wait is named in a Yes or No box:
        /// Yes ends it, No stops the install having changed nothing.
        /// </summary>
        static int StopSkyrim()
        {
            var found = new List<Process>();
            foreach (string n in new string[] { "SkyrimSE", "skse64_loader" })
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
                    if (StillOpen(found).Count == 0) break;
                }
            }

            List<string> left = StillOpen(found);
            if (left.Count > 0)
            {
                if (!AskToClose(left))
                {
                    foreach (Process p in found) { try { p.Dispose(); } catch { } }
                    throw new Exception("Skyrim is still open, so nothing was installed and nothing was " +
                                        "closed for you. Close it yourself, check the taskbar and the " +
                                        "system tray for anything of Skyrim's left behind, and run this " +
                                        "again.");
                }
                foreach (Process p in found) { try { if (!p.HasExited) p.Kill(); } catch { } }
            }
            foreach (Process p in found) { try { p.Dispose(); } catch { } }
            Thread.Sleep(750);
            return found.Count;
        }

        /// <summary>The names of the ones that are still running, each named once.</summary>
        static List<string> StillOpen(List<Process> all)
        {
            var names = new List<string>();
            foreach (Process p in all)
            {
                try
                {
                    if (p.HasExited) continue;
                    string n = p.ProcessName;
                    if (!names.Contains(n)) names.Add(n);
                }
                catch { }
            }
            return names;
        }

        /// <summary>
        /// Yes or No on ending what is still running, asked on the window's own
        /// thread because this runs on the unpack thread. Anything that goes
        /// wrong asking counts as No: not installing is recoverable, ending
        /// somebody's game without their say so is not.
        /// </summary>
        static bool AskToClose(List<string> names)
        {
            string text = "Skyrim is still running (" + string.Join(", ", names.ToArray()) + ").\n\n" +
                          "It may be the game itself, or a helper of it left behind by a crash, with " +
                          "no window of its own. It holds the game files open, and the " +
                          "install cannot carry on while it is there.\n\n" +
                          "Close it now?\n\n" +
                          "Yes ends it, and anything not saved in the game is lost.\n" +
                          "No stops the install and changes nothing, so you can save and quit " +
                          "yourself, then run this again.";
            var answer = MessageBoxResult.No;
            try
            {
                win.Dispatcher.Invoke(new Action(delegate
                {
                    answer = MessageBox.Show(win, text, "Thornswood Setup",
                                             MessageBoxButton.YesNo, MessageBoxImage.Warning);
                }));
            }
            catch { return false; }
            return answer == MessageBoxResult.Yes;
        }

        /// <summary>
        /// The PowerShell Setup.bat would pick: PowerShell 7 when it is on the
        /// PATH, Windows PowerShell otherwise. The two differ in whether a text
        /// file gets a byte order mark, so the choice stays the same as by hand.
        /// </summary>
        static string PowerShellExe()
        {
            foreach (string name in new string[] { "pwsh.exe", "powershell.exe" })
            {
                string path = Environment.GetEnvironmentVariable("PATH") ?? "";
                foreach (string dir in path.Split(';'))
                {
                    try
                    {
                        string d = dir.Trim().Trim('"');
                        if (d.Length == 0) continue;
                        string p = Path.Combine(d, name);
                        if (File.Exists(p)) return p;
                    }
                    catch { }
                }
            }
            string sys = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
                                      "WindowsPowerShell\\v1.0\\powershell.exe");
            return File.Exists(sys) ? sys : "powershell.exe";
        }

        /// <summary>
        /// Setup.bat's own command line with no console: the same script, the
        /// same -MovePayload and -Root, from the payload's folder. -NonInteractive
        /// goes twice. Before -File it is PowerShell's, so anything that reads
        /// the keyboard fails at once instead of waiting on a window nobody can
        /// see; after it, the script's, so it asks this window instead.
        /// The own folder card adds -MakeOwnGame when it is ticked and
        /// -VortexGame when a folder was chosen, and nothing when it was left
        /// alone, so an untouched card starts the script exactly as before.
        /// </summary>
        static ProcessStartInfo SetupStartInfo(string ps, string script, string root, bool makeOwn, string vortex)
        {
            var psi = new ProcessStartInfo(ps);
            psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" + script +
                            "\" -MovePayload -Root \"" + root.TrimEnd('\\') + "\" -NonInteractive";
            if (makeOwn) psi.Arguments += " -MakeOwnGame";
            if (!string.IsNullOrEmpty(vortex)) psi.Arguments += " -VortexGame \"" + vortex.TrimEnd('\\') + "\"";
            psi.WorkingDirectory = Path.GetDirectoryName(script);
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            psi.RedirectStandardInput = true;
            // What a console child writes in when it has no console window of
            // its own to take a code page from: the OEM one.
            Encoding oem = Encoding.GetEncoding(System.Globalization.CultureInfo.CurrentCulture.TextInfo.OEMCodePage);
            psi.StandardOutputEncoding = oem;
            psi.StandardErrorEncoding = oem;
            return psi;
        }

        [DllImport("user32.dll")]
        static extern bool AllowSetForegroundWindow(int processId);

        /// <summary>
        /// Runs the install script with its lines in TxtLog and in the log
        /// file, answers its one question with a box, and returns its exit code.
        /// </summary>
        static int RunSetupScript(ProcessStartInfo psi, string log)
        {
            lock (logLock)
            {
                try { logFile = new StreamWriter(log, false, new UTF8Encoding(false)); logFile.AutoFlush = true; }
                catch { logFile = null; }
            }
            Log("Thornswood Setup, " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
            Log(psi.FileName + " " + psi.Arguments);

            win.Dispatcher.Invoke(new Action(delegate
            {
                rootBox.Visibility = Visibility.Collapsed;
                foundBox.Visibility = Visibility.Collapsed;
                if (ownBox != null) ownBox.Visibility = Visibility.Collapsed;
                txtLog.Visibility = Visibility.Visible;
                txtBody.Text = "Installing. What it is doing shows below, and Thornswood opens by itself when it is done.";
                bar.IsIndeterminate = true;
            }));

            var outDone = new ManualResetEvent(false);
            var errDone = new ManualResetEvent(false);
            var p = new Process();
            p.StartInfo = psi;
            p.OutputDataReceived += delegate(object s, DataReceivedEventArgs e)
            {
                if (e.Data == null) outDone.Set(); else Line(p, e.Data, false);
            };
            p.ErrorDataReceived += delegate(object s, DataReceivedEventArgs e)
            {
                if (e.Data == null) errDone.Set(); else Line(p, e.Data, true);
            };
            installing = true;
            try
            {
                p.Start();
                // The script opens the launcher at the end and brings it to
                // the front, which Windows allows a process only when the
                // one in front says so. The console used to be that one.
                try { AllowSetForegroundWindow(p.Id); } catch { }
                p.BeginOutputReadLine();
                p.BeginErrorReadLine();
                // With a timeout: WaitForExit() with none also waits for the
                // output to close, and the launcher the script opens could
                // hold it open for as long as it runs.
                while (!p.WaitForExit(500)) { }
                outDone.WaitOne(3000);
                errDone.WaitOne(3000);
                int code = p.ExitCode;
                Log("Exit code " + code);
                return code;
            }
            finally
            {
                installing = false;
                try { p.Dispose(); } catch { }
                lock (logLock)
                {
                    if (logFile != null) { try { logFile.Dispose(); } catch { } }
                    logFile = null;
                }
            }
        }

        static void Log(string s)
        {
            lock (logLock)
            {
                if (logFile == null) return;
                try { logFile.WriteLine(s); } catch { }
            }
        }

        /// <summary>One line from the script: to the log, to the window, or a question.</summary>
        static void Line(Process p, string s, bool err)
        {
            Log(err ? "error: " + s : s);
            const string ask = "THORNSWOOD-ASK ";
            if (!err && s.StartsWith(ask, StringComparison.Ordinal))
            {
                bool ok = AskForScript(s.Substring(ask.Length));
                Log(ok ? "Answered OK" : "Answered Cancel");
                try { p.StandardInput.WriteLine(ok ? "ok" : "no"); p.StandardInput.Flush(); } catch { }
                return;
            }
            string t = s.Trim();
            if (t.StartsWith("STOP. ", StringComparison.Ordinal)) lastStop = t.Substring(6);
            else if (err && lastStop.Length == 0 && t.Length > 0) lastStop = t;
            win.Dispatcher.BeginInvoke(new Action(delegate
            {
                txtLog.AppendText(s + "\n");
                txtLog.ScrollToEnd();
                if (t.Trim('-').Length > 0) txtStat.Text = t;
            }));
        }

        /// <summary>
        /// The script's question, as an OK or Cancel box on the window's own
        /// thread. Anything that goes wrong asking counts as Cancel, which
        /// stops the script with a reason rather than guessing.
        /// </summary>
        static bool AskForScript(string text)
        {
            var answer = MessageBoxResult.Cancel;
            try
            {
                win.Dispatcher.Invoke(new Action(delegate
                {
                    answer = MessageBox.Show(win, text, "Thornswood Setup",
                                             MessageBoxButton.OKCancel, MessageBoxImage.Information);
                }));
            }
            catch { return false; }
            return answer == MessageBoxResult.OK;
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

                // What Setup.bat does, done from here: the same PowerShell,
                // the same script and the same arguments, but with no console
                // of its own. Its lines come into this window (issue #889).
                // Setup.bat and Install.bat stay in the payload for a person
                // running it by hand.
                // What was accepted, and when, before the script opens the
                // launcher at its end. Never a stop: the boxes were ticked
                // whatever the site says right now.
                Say("Noting what you accepted");
                RecordAcceptance(Path.Combine(installRoot, "Profile"), acceptedAt);

                Say("Starting the installer");
                string script = Path.Combine(temp, "Setup-Thornswood.ps1");
                if (!File.Exists(script)) throw new Exception("Setup-Thornswood.ps1 was not in the payload.");
                string log = Path.Combine(temp, "setup-log.txt");
                int code = RunSetupScript(SetupStartInfo(PowerShellExe(), script, installRoot, makeOwnGame, vortexGame), log);

                running = false;
                if (code == 0)
                {
                    win.Dispatcher.BeginInvoke(new Action(delegate { win.Close(); }));
                    return;
                }
                string why = lastStop.Length > 0 ? lastStop : "Setup stopped with code " + code + ".";
                win.Dispatcher.BeginInvoke(new Action(delegate
                {
                    bar.Visibility = Visibility.Collapsed;
                    txtBody.Text = why + "\n\nEverything it printed is below, and saved in " + log +
                                   ". Send staff a screenshot of this window, or that file, in the Discord.";
                    txtStat.Text = "";
                    btnClose.IsEnabled = true;
                    btnClose.Content = "Close";
                }));
            }
            catch (Exception ex)
            {
                running = false;
                installing = false;
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
