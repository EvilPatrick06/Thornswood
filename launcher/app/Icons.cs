using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;

namespace Thornswood
{
    /// <summary>
    /// Keeping the shortcut showing the icon it is supposed to show.
    ///
    /// Windows draws a shortcut's icon once and then remembers the picture
    /// against the place it came from. Every build used to point the shortcut
    /// at the launcher exe's own first icon, so that address never changed and
    /// neither did the remembered picture. New artwork could sit inside the exe for a week
    /// while the desktop went on showing the old one, and a reboot does not
    /// clear it, which is what makes people think the update did not arrive.
    ///
    /// So the artwork gets its own file, named after a hash of itself. New
    /// artwork means a new name means an address Windows has never drawn
    /// before, and it has nothing cached to show instead. Unchanged artwork
    /// keeps the same name and nothing happens at all.
    ///
    /// The icon travels inside the exe as a resource, so the update that
    /// replaces the launcher brings its own, the same way the emblem does.
    ///
    /// The name under the icon and the label that appears when you hover come
    /// from the shortcut file rather than from the program, so this fixes
    /// those too. A shortcut still carrying an old name goes on saying so
    /// forever otherwise, and the pinned taskbar copy is its own file in its
    /// own folder that no build script was ever looking at.
    /// </summary>
    static class Icons
    {
        const int SHCNE_ASSOCCHANGED = 0x08000000;
        const int SHCNE_UPDATEITEM = 0x00002000;
        const uint SHCNF_IDLIST = 0x0000;
        const uint SHCNF_PATHW = 0x0005;
        const uint SHCNF_FLUSH = 0x1000;

        [DllImport("shell32.dll", CharSet = CharSet.Auto)]
        static extern void SHChangeNotify(int eventId, uint flags, IntPtr item1, IntPtr item2);

        // Same entry point, path form: telling Explorer about one .lnk is what
        // makes a blank shortcut redraw without clearing the whole icon cache.
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        static extern void SHChangeNotify(int eventId, uint flags, string item1, string item2);

        /// <summary>
        /// The running launcher, wherever it is and whatever it is called.
        /// Asking the assembly means the shortcut points at the one that is
        /// actually there.
        /// </summary>
        static string LauncherExe
        {
            get
            {
                try
                {
                    string me = System.Reflection.Assembly.GetExecutingAssembly().Location;
                    if (!string.IsNullOrEmpty(me) && File.Exists(me)) return me;
                }
                catch (Exception ex) { Swallow.Note("Icons.LauncherExe", ex); }
                return Path.Combine(Paths.LauncherDir, "Thornswood.exe");
            }
        }

        /// <summary>
        /// Writes the icon out beside the launcher under a name that changes
        /// only when the artwork does. Returns the path, or null when this
        /// build carries no icon resource and the exe has to do.
        /// </summary>
        static string IconFile()
        {
            try
            {
                string pick;
                byte[] bytes = IconBytes(out pick);
                if (bytes == null) return null;
                string hash = Hash(bytes);

                if (!Directory.Exists(Paths.LauncherDir)) return null;
                string want = Path.Combine(Paths.LauncherDir, "icon-" + hash + ".ico");
                if (!File.Exists(want) || new FileInfo(want).Length != bytes.Length)
                {
                    File.WriteAllBytes(want, bytes);
                    // The shortcuts may have been drawn while it was gone, and
                    // Windows keeps that blank against this same name (#887).
                    iconWritten = true;
                }
                return want;
            }
            catch { return null; }
        }

        static bool iconWritten;

        /// <summary>
        /// The artwork this build's shortcuts show, out of the exe, or null
        /// when it carries none. The dev build's shortcuts get the dev icon,
        /// app-dev.ico; the main build keeps app.ico. A dev build without it
        /// uses app.ico.
        /// </summary>
        static byte[] IconBytes(out string pick)
        {
            pick = null;
            Assembly asm = Assembly.GetExecutingAssembly();
            if (Art.Dev)
                foreach (string n in asm.GetManifestResourceNames())
                    if (n.EndsWith("app-dev.ico", StringComparison.OrdinalIgnoreCase)) { pick = n; break; }
            if (pick == null)
                foreach (string n in asm.GetManifestResourceNames())
                    if (n.EndsWith("app.ico", StringComparison.OrdinalIgnoreCase)) { pick = n; break; }
            if (pick == null) return null;
            using (Stream st = asm.GetManifestResourceStream(pick))
            {
                if (st == null) return null;
                var ms = new MemoryStream();
                st.CopyTo(ms);
                byte[] bytes = ms.ToArray();
                return bytes.Length == 0 ? null : bytes;
            }
        }

        /// <summary>The first eight hex digits of the artwork's SHA-256, which name its file.</summary>
        static string Hash(byte[] bytes)
        {
            using (SHA256 sha = SHA256.Create())
                return BitConverter.ToString(sha.ComputeHash(bytes), 0, 4).Replace("-", "").ToLowerInvariant();
        }

        /// <summary>
        /// Whether the shortcuts need redrawing even where IconLocation already
        /// reads right, issue #887. A rebuild or a Ship copies a new exe over
        /// the old one and leaves no .old, and Install-Launcher used to delete
        /// the icon file the Start menu and pinned shortcuts name; Windows then
        /// drew them blank and kept that. So Profile\icons.stamp remembers the
        /// icon and the exe (size, write time) of the last redraw, and a start
        /// where either differs, or where the icon file had to be written
        /// again, redraws. An ordinary start matches and stays quiet.
        /// </summary>
        static bool Due(string exe, string want, bool wrote)
        {
            if (wrote) return true;
            try
            {
                string stamp = Path.Combine(Paths.ProfileDir, "icons.stamp");
                if (!File.Exists(stamp)) return true;
                return !string.Equals(File.ReadAllText(stamp).Trim(), Mark(exe, want), StringComparison.OrdinalIgnoreCase);
            }
            catch (Exception ex) { Swallow.Note("Icons.Due", ex); return true; }
        }

        static void Remember(string exe, string want)
        {
            try
            {
                if (Directory.Exists(Paths.ProfileDir))
                    File.WriteAllText(Path.Combine(Paths.ProfileDir, "icons.stamp"), Mark(exe, want));
            }
            catch (Exception ex) { Swallow.Note("Icons.Remember", ex); }
        }

        static string Mark(string exe, string want)
        {
            var fi = new FileInfo(exe);
            return want + "|" + (fi.Exists ? fi.Length + "|" + fi.LastWriteTimeUtc.Ticks : "none");
        }

        static void Sweep(string keep)
        {
            try
            {
                foreach (string f in Directory.GetFiles(Paths.LauncherDir, "icon-*.ico"))
                    if (!string.Equals(f, keep, StringComparison.OrdinalIgnoreCase))
                        try { File.Delete(f); } catch (Exception ex) { Swallow.Note("Icons.Sweep, delete", ex); }
            }
            catch (Exception ex) { Swallow.Note("Icons.Sweep", ex); }
        }

        class Place
        {
            public string Dir;
            public bool MayRename;      // false where the file name is load bearing
            public bool MakeIfMissing;  // a place the build wants a shortcut in, put back when it is gone
            public Place(string d, bool r) : this(d, r, r) { }
            public Place(string d, bool r, bool m) { Dir = d; MayRename = r; MakeIfMissing = m; }
        }

        /// <summary>
        /// Where a shortcut to this launcher might be. Renaming is fine on the
        /// desktop and in the install folder. It is not fine for a pinned
        /// taskbar item: Windows ties the pin to that exact file, so renaming
        /// or replacing it unpins the launcher and the person has to pin it
        /// again after every update. Those get their icon and their label
        /// fixed in place and nothing else.
        /// </summary>
        static List<Place> Places()
        {
            var l = new List<Place>();
            try { l.Add(new Place(Environment.GetFolderPath(Environment.SpecialFolder.Desktop), true)); } catch (Exception ex) { Swallow.Note("Icons.Places, desktop", ex); }
            try { l.Add(new Place(Paths.Root, true)); } catch (Exception ex) { Swallow.Note("Icons.Places, root", ex); }
            try
            {
                string app = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
                l.Add(new Place(Path.Combine(app, "Microsoft\\Internet Explorer\\Quick Launch\\User Pinned\\TaskBar"), false));
                // The Start menu gets one made for it if it has none. Typing
                // "Thornswood" into Start should find the launcher, and tools
                // that only know a program by its Start menu entry (screen
                // sharing and remote control among them) cannot see it
                // otherwise. Still never renamed: a Start menu tile can be
                // pinned, and a pin dies with the file it points at.
                l.Add(new Place(Path.Combine(app, "Microsoft\\Windows\\Start Menu\\Programs"), false, true));
            }
            catch (Exception ex) { Swallow.Note("Icons.Places, start menu", ex); }
            return l;
        }

        /// <summary>
        /// Points every shortcut that runs this launcher at the current icon.
        /// Returns how many it had to change, so a start that changed nothing
        /// can stay quiet. Never throws and never restarts anything.
        ///
        /// Pass force after a self-update: Windows can blank the cached picture
        /// for a shortcut even when IconLocation still names the right file, and
        /// a quiet Ensure then skips the notify that would redraw it. Force
        /// rewrites the same IconLocation, tells Explorer about each .lnk, and
        /// asks ie4uinit to refresh, without killing Explorer (Repair still does
        /// that from Settings when somebody needs the heavy pass). Ensure also
        /// forces itself when the exe or the icon changed since the last pass
        /// (Due), which covers a rebuild or a Ship that leaves no .old.
        /// </summary>
        public static int Ensure()
        {
            return Ensure(false);
        }

        /// <summary>See <see cref="Ensure()"/>.</summary>
        public static int Ensure(bool force)
        {
            iconWritten = false;
            string icon = IconFile();
            string exe = LauncherExe;
            string want = (icon == null ? exe : icon) + ",0";

            // SelfSwap keeps the previous exe as Thornswood.exe.old until this
            // window has drawn. Seeing that file means this is the first start
            // after an update, which is when blank icons show up.
            if (!force)
            {
                try { if (File.Exists(exe + ".old")) force = true; } catch { /* .old gone mid-check: treat as ordinary start */ }
            }
            // A rebuild or a Ship leaves no .old; the stamp catches those.
            if (!force && Due(exe, want, iconWritten)) force = true;

            int changed = 0;
            var touchedLinks = new List<string>();
            object shell = null;
            Type shellType = null;
            try
            {
                shellType = Type.GetTypeFromProgID("WScript.Shell");
                if (shellType == null) return 0;
                shell = Activator.CreateInstance(shellType);

                foreach (Place spot in Places())
                {
                    string place = spot.Dir;
                    if (string.IsNullOrEmpty(place) || !Directory.Exists(place)) continue;
                    string[] links;
                    try { links = Directory.GetFiles(place, "*.lnk"); }
                    catch { continue; }
                    bool found = false;

                    foreach (string lnk in links)
                    {
                        object sc = null;
                        try
                        {
                            sc = shellType.InvokeMember("CreateShortcut", BindingFlags.InvokeMethod,
                                                        null, shell, new object[] { lnk });
                            if (sc == null) continue;
                            Type t = sc.GetType();

                            string target = t.InvokeMember("TargetPath", BindingFlags.GetProperty,
                                                           null, sc, null) as string;
                            // The multiplayer client carries the same file name
                            // as the launcher, so this has to match the whole
                            // path or a shortcut to the game gets an icon that
                            // is not the game's.
                            if (string.IsNullOrEmpty(target)) continue;
                            if (!string.Equals(Full(target), Full(exe),
                                               StringComparison.OrdinalIgnoreCase)) continue;

                            // Wrong file name, which is where an old name
                            // survives: the label under a shortcut and the one
                            // that appears on hover are the file name, not
                            // anything inside the program.
                            found = true;
                            if (spot.MayRename &&
                                !string.Equals(Path.GetFileName(lnk), Name,
                                               StringComparison.OrdinalIgnoreCase))
                            {
                                string dest = Path.Combine(place, Name);
                                if (File.Exists(dest))
                                {
                                    // The right one is already sitting beside
                                    // it, so this is the leftover.
                                    if (Kill(lnk)) changed++;
                                }
                                else if (Rename(shellType, shell, sc, dest, want))
                                {
                                    Kill(lnk);
                                    touchedLinks.Add(dest);
                                    changed++;
                                }
                                continue;
                            }

                            bool touched = false;
                            string now = t.InvokeMember("IconLocation", BindingFlags.GetProperty,
                                                        null, sc, null) as string;
                            // Force rewrites even when the string matches: the
                            // .lnk timestamp and a shell notify are what clear a
                            // blank cache entry after SelfSwap replaced the exe.
                            if (force || !string.Equals(now, want, StringComparison.OrdinalIgnoreCase))
                            {
                                t.InvokeMember("IconLocation", BindingFlags.SetProperty,
                                               null, sc, new object[] { want });
                                touched = true;
                            }

                            string desc = t.InvokeMember("Description", BindingFlags.GetProperty,
                                                         null, sc, null) as string;
                            if (!string.Equals(desc, Label, StringComparison.Ordinal))
                            {
                                t.InvokeMember("Description", BindingFlags.SetProperty,
                                               null, sc, new object[] { Label });
                                touched = true;
                            }

                            if (touched)
                            {
                                t.InvokeMember("Save", BindingFlags.InvokeMethod, null, sc, null);
                                touchedLinks.Add(lnk);
                                changed++;
                            }
                        }
                        catch (Exception ex) { Swallow.Note("Icons.Ensure, shortcut", ex); }
                        finally
                        {
                            if (sc != null) try { Marshal.ReleaseComObject(sc); } catch (Exception ex) { Swallow.Note("Icons.Ensure, release shortcut", ex); }
                        }
                    }

                    // A desktop that has lost its shortcut gets it back, and
                    // the Start menu gets one it never had. Only the places
                    // the build wants one in; never the taskbar pins.
                    if (!found && spot.MakeIfMissing && File.Exists(exe))
                    {
                        string made = Path.Combine(place, Name);
                        if (Make(shellType, shell, made, exe, want))
                        {
                            touchedLinks.Add(made);
                            changed++;
                        }
                    }
                }
                // Every shortcut has been walked, so the next start with the
                // same exe and icon can stay quiet.
                Remember(exe, want);
            }
            catch (Exception ex) { Swallow.Note("Icons.Ensure", ex); }
            finally
            {
                if (shell != null) try { Marshal.ReleaseComObject(shell); } catch (Exception ex) { Swallow.Note("Icons.Ensure, release shell", ex); }
            }

            if (icon != null) Sweep(icon);

            if (changed > 0 || force)
            {
                // The icon file first, since Windows keeps the picture against
                // its path, then one .lnk at a time: ASSOCCHANGED alone leaves
                // blank shortcut icons after a self-update on some machines.
                if (icon != null)
                    try { SHChangeNotify(SHCNE_UPDATEITEM, SHCNF_PATHW | SHCNF_FLUSH, icon, null); } catch (Exception ex) { Swallow.Note("Icons.Ensure, notify icon file", ex); }
                foreach (string lnk in touchedLinks)
                    try { SHChangeNotify(SHCNE_UPDATEITEM, SHCNF_PATHW | SHCNF_FLUSH, lnk, null); } catch { /* shell notify is best-effort */ }
                try { SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, IntPtr.Zero, IntPtr.Zero); } catch { /* shell notify is best-effort */ }
                // Same soft ask Install-Launcher uses before it ever kills Explorer.
                AskIconCache();
            }
            return changed;
        }

        /// <summary>
        /// What Ensure would change, said and not done (#2627): each shortcut
        /// to this launcher that names another icon or another label or has
        /// an old name, the desktop or the Start menu without one, the icon
        /// file not written yet, and a launcher that changed since the
        /// shortcuts were last redrawn (Due). Empty when Ensure would find
        /// nothing to do. Scan asks this; Fix then runs Ensure. Never writes
        /// and never throws.
        /// </summary>
        public static List<string> OutOfDate()
        {
            var l = new List<string>();
            string exe = LauncherExe;
            string icon = null;
            try
            {
                string pick;
                byte[] bytes = IconBytes(out pick);
                if (bytes != null && Directory.Exists(Paths.LauncherDir))
                {
                    icon = Path.Combine(Paths.LauncherDir, "icon-" + Hash(bytes) + ".ico");
                    if (!File.Exists(icon) || new FileInfo(icon).Length != bytes.Length) l.Add("the icon file " + Path.GetFileName(icon) + " is not beside the launcher");
                }
            }
            catch (Exception ex) { Swallow.Note("Icons.OutOfDate, the icon file", ex); }
            string want = (icon == null ? exe : icon) + ",0";
            if (l.Count == 0 && Due(exe, want, false)) l.Add("the launcher changed since the shortcuts were last redrawn");

            object shell = null;
            Type shellType = null;
            try
            {
                shellType = Type.GetTypeFromProgID("WScript.Shell");
                if (shellType == null) return l;
                shell = Activator.CreateInstance(shellType);
                foreach (Place spot in Places())
                {
                    string place = spot.Dir;
                    if (string.IsNullOrEmpty(place) || !Directory.Exists(place)) continue;
                    string[] links;
                    try { links = Directory.GetFiles(place, "*.lnk"); }
                    catch (Exception ex) { Swallow.Note("Icons.OutOfDate, listing " + place, ex); continue; }
                    bool found = false;
                    foreach (string lnk in links)
                    {
                        object sc = null;
                        try
                        {
                            sc = shellType.InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null, shell, new object[] { lnk });
                            if (sc == null) continue;
                            Type t = sc.GetType();
                            string target = t.InvokeMember("TargetPath", BindingFlags.GetProperty, null, sc, null) as string;
                            if (string.IsNullOrEmpty(target) || !string.Equals(Full(target), Full(exe), StringComparison.OrdinalIgnoreCase)) continue;
                            found = true;
                            if (spot.MayRename && !string.Equals(Path.GetFileName(lnk), Name, StringComparison.OrdinalIgnoreCase))
                            {
                                l.Add(lnk + " has an old name");
                                continue;
                            }
                            string now = t.InvokeMember("IconLocation", BindingFlags.GetProperty, null, sc, null) as string;
                            string desc = t.InvokeMember("Description", BindingFlags.GetProperty, null, sc, null) as string;
                            if (!string.Equals(now, want, StringComparison.OrdinalIgnoreCase)) l.Add(lnk + " shows another icon");
                            else if (!string.Equals(desc, Label, StringComparison.Ordinal)) l.Add(lnk + " has another label");
                        }
                        catch (Exception ex) { Swallow.Note("Icons.OutOfDate, shortcut", ex); }
                        finally
                        {
                            if (sc != null) try { Marshal.ReleaseComObject(sc); } catch (Exception ex) { Swallow.Note("Icons.OutOfDate, release shortcut", ex); }
                        }
                    }
                    if (!found && spot.MakeIfMissing && File.Exists(exe)) l.Add(Path.Combine(place, Name) + " is missing");
                }
            }
            catch (Exception ex) { Swallow.Note("Icons.OutOfDate", ex); }
            finally
            {
                if (shell != null) try { Marshal.ReleaseComObject(shell); } catch (Exception ex) { Swallow.Note("Icons.OutOfDate, release shell", ex); }
            }
            return l;
        }

        /// <summary>
        /// The heavy pass, for the Settings button. Repoints the shortcuts as
        /// above, then throws away the pictures Windows has remembered and
        /// restarts Explorer so it draws them again. The desktop and taskbar
        /// vanish for a second. Returns a line to show the person.
        /// </summary>
        public static string Repair()
        {
            int changed = Ensure(true);

            int gone = 0;
            bool restarted = false;
            try
            {
                Run("taskkill", "/f /im explorer.exe", 8000);

                string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                var targets = new List<string>();
                targets.Add(Path.Combine(local, "IconCache.db"));
                try
                {
                    string dir = Path.Combine(local, "Microsoft\\Windows\\Explorer");
                    if (Directory.Exists(dir))
                        targets.AddRange(Directory.GetFiles(dir, "iconcache_*.db"));
                }
                catch (Exception ex) { Swallow.Note("Icons.Repair, list cache", ex); }

                foreach (string f in targets)
                    try { if (File.Exists(f)) { File.Delete(f); gone++; } } catch (Exception ex) { Swallow.Note("Icons.Repair, delete cache", ex); }
            }
            catch (Exception ex) { Swallow.Note("Icons.Repair", ex); }
            finally
            {
                try { Process.Start("explorer.exe"); restarted = true; } catch (Exception ex) { Swallow.Note("Icons.Repair, restart explorer", ex); }
            }

            try { SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, IntPtr.Zero, IntPtr.Zero); } catch (Exception ex) { Swallow.Note("Icons.Repair, notify", ex); }

            string said = "Shortcut icon refreshed";
            if (changed > 0) said += ", " + changed + (changed == 1 ? " shortcut repointed" : " shortcuts repointed");
            if (gone > 0) said += ", " + gone + " cached copies thrown away";
            if (!restarted) said += ". Explorer did not come back on its own, press Ctrl Shift Esc, File, Run explorer.exe";
            else said += ".";
            if (changed == 0 && gone == 0)
                said = "Nothing needed changing. If a pinned taskbar item is still wrong, unpin it and pin it again: Windows keeps its own note of what was pinned and that is the only thing out here that cannot reach it.";
            return said;
        }

        /// <summary>Set by the shell from the config: "Thornswood" or "Thornswood Dev".</summary>
        public static string BuildName = "Thornswood";
        static string Name  { get { return BuildName + ".lnk"; } }
        static string Label { get { return BuildName == "Thornswood" ? "ThornsWood" : BuildName; } }

        /// <summary>Where a shortcut of that name would be: the desktop and the Start menu.</summary>
        public static List<string> ShortcutPaths(string buildName)
        {
            var l = new List<string>();
            try { l.Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Desktop), buildName + ".lnk")); } catch (Exception ex) { Swallow.Note("Icons.ShortcutPaths, desktop", ex); }
            try { l.Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Microsoft\\Windows\\Start Menu\\Programs\\" + buildName + ".lnk")); } catch (Exception ex) { Swallow.Note("Icons.ShortcutPaths, start menu", ex); }
            return l;
        }

        static string Full(string p)
        {
            try { return Path.GetFullPath(p); } catch { return p; }
        }

        static bool Kill(string path)
        {
            try { File.Delete(path); return true; } catch { return false; }
        }

        /// <summary>
        /// Writes the same shortcut out under the right name. A shortcut cannot
        /// be renamed through the scripting object, so the properties are read
        /// off the old one and written to a new one beside it.
        /// </summary>
        static bool Rename(Type shellType, object shell, object src, string dest, string icon)
        {
            object made = null;
            try
            {
                Type st = src.GetType();
                string target = st.InvokeMember("TargetPath", BindingFlags.GetProperty, null, src, null) as string;
                string args   = st.InvokeMember("Arguments", BindingFlags.GetProperty, null, src, null) as string;
                string wd     = st.InvokeMember("WorkingDirectory", BindingFlags.GetProperty, null, src, null) as string;

                made = shellType.InvokeMember("CreateShortcut", BindingFlags.InvokeMethod,
                                              null, shell, new object[] { dest });
                if (made == null) return false;
                Type mt = made.GetType();
                mt.InvokeMember("TargetPath", BindingFlags.SetProperty, null, made, new object[] { target });
                mt.InvokeMember("Arguments", BindingFlags.SetProperty, null, made, new object[] { args == null ? "" : args });
                mt.InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null, made, new object[] { wd == null ? "" : wd });
                mt.InvokeMember("IconLocation", BindingFlags.SetProperty, null, made, new object[] { icon });
                mt.InvokeMember("Description", BindingFlags.SetProperty, null, made, new object[] { Label });
                mt.InvokeMember("Save", BindingFlags.InvokeMethod, null, made, null);
                return true;
            }
            catch { return false; }
            finally
            {
                if (made != null) try { Marshal.ReleaseComObject(made); } catch (Exception ex) { Swallow.Note("Icons.Rename, release", ex); }
            }
        }

        static bool Make(Type shellType, object shell, string dest, string exe, string icon)
        {
            object made = null;
            try
            {
                made = shellType.InvokeMember("CreateShortcut", BindingFlags.InvokeMethod,
                                              null, shell, new object[] { dest });
                if (made == null) return false;
                Type mt = made.GetType();
                mt.InvokeMember("TargetPath", BindingFlags.SetProperty, null, made, new object[] { exe });
                mt.InvokeMember("Arguments", BindingFlags.SetProperty, null, made, new object[] { "" });
                mt.InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null, made,
                                new object[] { Path.GetDirectoryName(exe) });
                mt.InvokeMember("IconLocation", BindingFlags.SetProperty, null, made, new object[] { icon });
                mt.InvokeMember("Description", BindingFlags.SetProperty, null, made, new object[] { Label });
                mt.InvokeMember("Save", BindingFlags.InvokeMethod, null, made, null);
                return true;
            }
            catch { return false; }
            finally
            {
                if (made != null) try { Marshal.ReleaseComObject(made); } catch (Exception ex) { Swallow.Note("Icons.Make, release", ex); }
            }
        }

        /// <summary>
        /// Asks Windows to rebuild what it has drawn for icons, without killing
        /// Explorer. Matches Install-Launcher.ps1's soft pass.
        /// </summary>
        static void AskIconCache()
        {
            try
            {
                string ie4 = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "ie4uinit.exe");
                if (!File.Exists(ie4)) return;
                Run(ie4, "-show", 8000);
            }
            catch { /* ie4uinit missing or refused: Ensure already notified each .lnk */ }
        }

        static void Run(string file, string args, int waitMs)
        {
            try
            {
                var psi = new ProcessStartInfo(file, args);
                psi.CreateNoWindow = true;
                psi.UseShellExecute = false;
                psi.WindowStyle = ProcessWindowStyle.Hidden;
                Process p = Process.Start(psi);
                if (p != null) p.WaitForExit(waitMs);
            }
            catch (Exception ex) { Swallow.Note("Icons.Run", ex); }
        }
    }
}
