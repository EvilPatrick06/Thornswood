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
    /// at "SkyrimTogether.exe,0", so that address never changed and neither did
    /// the remembered picture. New artwork could sit inside the exe for a week
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
    /// those too. A shortcut still called "Skyrim Together" goes on saying so
    /// forever otherwise, and the pinned taskbar copy is its own file in its
    /// own folder that no build script was ever looking at.
    /// </summary>
    static class Icons
    {
        const int SHCNE_ASSOCCHANGED = 0x08000000;
        const uint SHCNF_IDLIST = 0x0000;

        [DllImport("shell32.dll", CharSet = CharSet.Auto)]
        static extern void SHChangeNotify(int eventId, uint flags, IntPtr item1, IntPtr item2);

        /// <summary>
        /// The running launcher, wherever it is and whatever it is called. It
        /// was SkyrimTogether.exe and is Thornswood.exe now, and installs made
        /// before the rename keep the old name because the launcher replaces
        /// itself in place when it updates. Asking the assembly means the
        /// shortcut points at the one that is actually there.
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
                catch { }
                foreach (string n in new[] { "Thornswood.exe", "SkyrimTogether.exe" })
                {
                    string p = Path.Combine(Paths.LauncherDir, n);
                    if (File.Exists(p)) return p;
                }
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
                Assembly asm = Assembly.GetExecutingAssembly();
                string pick = null;
                foreach (string n in asm.GetManifestResourceNames())
                    if (n.EndsWith("app.ico", StringComparison.OrdinalIgnoreCase)) { pick = n; break; }
                if (pick == null) return null;

                byte[] bytes;
                using (Stream st = asm.GetManifestResourceStream(pick))
                {
                    if (st == null) return null;
                    var ms = new MemoryStream();
                    st.CopyTo(ms);
                    bytes = ms.ToArray();
                }
                if (bytes.Length == 0) return null;

                string hash;
                using (SHA256 sha = SHA256.Create())
                    hash = BitConverter.ToString(sha.ComputeHash(bytes), 0, 4).Replace("-", "").ToLowerInvariant();

                if (!Directory.Exists(Paths.LauncherDir)) return null;
                string want = Path.Combine(Paths.LauncherDir, "icon-" + hash + ".ico");
                if (!File.Exists(want) || new FileInfo(want).Length != bytes.Length)
                    File.WriteAllBytes(want, bytes);
                return want;
            }
            catch { return null; }
        }

        static void Sweep(string keep)
        {
            try
            {
                foreach (string f in Directory.GetFiles(Paths.LauncherDir, "icon-*.ico"))
                    if (!string.Equals(f, keep, StringComparison.OrdinalIgnoreCase))
                        try { File.Delete(f); } catch { }
            }
            catch { }
        }

        class Place
        {
            public string Dir;
            public bool MayRename;      // false where the file name is load bearing
            public Place(string d, bool r) { Dir = d; MayRename = r; }
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
            try { l.Add(new Place(Environment.GetFolderPath(Environment.SpecialFolder.Desktop), true)); } catch { }
            try { l.Add(new Place(Paths.Root, true)); } catch { }
            try
            {
                string app = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
                l.Add(new Place(Path.Combine(app, "Microsoft\\Internet Explorer\\Quick Launch\\User Pinned\\TaskBar"), false));
                l.Add(new Place(Path.Combine(app, "Microsoft\\Windows\\Start Menu\\Programs"), false));
            }
            catch { }
            return l;
        }

        /// <summary>
        /// Points every shortcut that runs this launcher at the current icon.
        /// Returns how many it had to change, so a start that changed nothing
        /// can stay quiet. Never throws and never restarts anything.
        /// </summary>
        public static int Ensure()
        {
            string icon = IconFile();
            string exe = LauncherExe;
            string want = (icon == null ? exe : icon) + ",0";

            int changed = 0;
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

                            // Wrong file name, which is where "Skyrim Together"
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
                                    changed++;
                                }
                                continue;
                            }

                            bool touched = false;
                            string now = t.InvokeMember("IconLocation", BindingFlags.GetProperty,
                                                        null, sc, null) as string;
                            if (!string.Equals(now, want, StringComparison.OrdinalIgnoreCase))
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
                                changed++;
                            }
                        }
                        catch { }
                        finally
                        {
                            if (sc != null) try { Marshal.ReleaseComObject(sc); } catch { }
                        }
                    }

                    // A desktop that has lost its shortcut gets it back. Only
                    // the two places the build put one in the first place.
                    if (!found && spot.MayRename && File.Exists(exe))
                        if (Make(shellType, shell, Path.Combine(place, Name), exe, want)) changed++;
                }
            }
            catch { }
            finally
            {
                if (shell != null) try { Marshal.ReleaseComObject(shell); } catch { }
            }

            if (icon != null) Sweep(icon);

            // Telling the shell an association changed is what makes Explorer
            // redraw. Unlike clearing the cache it costs nothing and nobody
            // sees their taskbar disappear.
            if (changed > 0) try { SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, IntPtr.Zero, IntPtr.Zero); } catch { }
            return changed;
        }

        /// <summary>
        /// The heavy pass, for the Settings button. Repoints the shortcuts as
        /// above, then throws away the pictures Windows has remembered and
        /// restarts Explorer so it draws them again. The desktop and taskbar
        /// vanish for a second. Returns a line to show the person.
        /// </summary>
        public static string Repair()
        {
            int changed = Ensure();

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
                catch { }

                foreach (string f in targets)
                    try { if (File.Exists(f)) { File.Delete(f); gone++; } } catch { }
            }
            catch { }
            finally
            {
                try { Process.Start("explorer.exe"); restarted = true; } catch { }
            }

            try { SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, IntPtr.Zero, IntPtr.Zero); } catch { }

            string said = "Shortcut icon refreshed";
            if (changed > 0) said += ", " + changed + (changed == 1 ? " shortcut repointed" : " shortcuts repointed");
            if (gone > 0) said += ", " + gone + " cached copies thrown away";
            if (!restarted) said += ". Explorer did not come back on its own, press Ctrl Shift Esc, File, Run explorer.exe";
            else said += ".";
            if (changed == 0 && gone == 0)
                said = "Nothing needed changing. If a pinned taskbar item is still wrong, unpin it and pin it again: Windows keeps its own note of what was pinned and that is the only thing out here that cannot reach it.";
            return said;
        }

        const string Name  = "Thornswood.lnk";
        const string Label = "Thornswood";

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
                if (made != null) try { Marshal.ReleaseComObject(made); } catch { }
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
                if (made != null) try { Marshal.ReleaseComObject(made); } catch { }
            }
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
            catch { }
        }
    }
}
