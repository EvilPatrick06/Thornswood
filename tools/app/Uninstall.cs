using System;
using System.Diagnostics;
using System.IO;
using System.Text;

namespace Thornswood
{
    /// <summary>
    /// Removing the build, in the one order that is safe.
    ///
    /// The dangerous part is not deleting the game folder, it is the profile
    /// redirect. While this build is running, Windows' own Skyrim settings and
    /// saves folders are junctions pointing into Profile, and the real ones are
    /// sitting next to them renamed .st-backup. Delete Profile with those
    /// junctions live and Windows follows them: your saves go with it, and the
    /// backup is left orphaned under a name nothing looks for. So Swap.Restore
    /// runs first, every time, and nothing else happens until it has.
    ///
    /// Nothing here touches the Skyrim you own on Steam. This build keeps its
    /// own copy of the game under Root, which is the whole reason it exists.
    ///
    /// The launcher cannot delete the folder it is running from, so the last
    /// step hands a small script to cmd, which waits for this process to exit
    /// and then finishes the job.
    /// </summary>
    static class Uninstall
    {
        /// <summary>
        /// Refuses anything that does not look like one of our installs. A
        /// wrong Root here would be a very bad afternoon, and the check costs
        /// nothing.
        /// </summary>
        public static string WhyNot()
        {
            string root = Paths.Root;
            if (string.IsNullOrEmpty(root)) return "The install folder is not set.";
            if (!Directory.Exists(root)) return "The install folder is already gone.";

            try
            {
                var di = new DirectoryInfo(root);
                if (di.Parent == null) return "The install folder is a drive root, which this will not touch.";
            }
            catch { return "The install folder could not be read."; }

            bool looksRight = Directory.Exists(Paths.Game) || Directory.Exists(Paths.ProfileDir);
            if (!looksRight)
                return "That folder does not contain a Game or Profile folder, so it is not this build.";

            // Somebody pointing Root at their Steam library would be the one
            // mistake worth refusing outright.
            string steam = Environment.GetEnvironmentVariable("ProgramFiles(x86)");
            if (!string.IsNullOrEmpty(steam) &&
                root.StartsWith(Path.Combine(steam, "Steam"), StringComparison.OrdinalIgnoreCase))
                return "That is inside your Steam folder. This will not remove it.";

            return null;
        }

        public static long Measure(string dir, ref int files)
        {
            long total = 0;
            try
            {
                foreach (string f in Directory.GetFiles(dir)) { try { total += new FileInfo(f).Length; files++; } catch { } }
                foreach (string d in Directory.GetDirectories(dir))
                {
                    // Never walk through a junction while measuring either.
                    try { if ((new DirectoryInfo(d).Attributes & FileAttributes.ReparsePoint) != 0) continue; } catch { continue; }
                    total += Measure(d, ref files);
                }
            }
            catch { }
            return total;
        }

        static void Kill()
        {
            try { Checks.CloseGame(); } catch { }
        }

        static void DropShortcuts()
        {
            string[] spots = {
                Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
                Environment.GetFolderPath(Environment.SpecialFolder.CommonDesktopDirectory),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                             "Microsoft\\Windows\\Start Menu\\Programs"),
            };
            foreach (string spot in spots)
            {
                if (string.IsNullOrEmpty(spot) || !Directory.Exists(spot)) continue;
                foreach (string name in new[] { "Thornswood.lnk", "Skyrim Together.lnk" })
                {
                    string p = Path.Combine(spot, name);
                    try { if (File.Exists(p)) File.Delete(p); } catch { }
                }
            }
        }

        /// <summary>
        /// Everything that can be done from inside a running launcher. Returns
        /// what is left for the handover script, or an empty array if nothing
        /// is.
        /// </summary>
        public static string[] Begin(bool keepSaves, Action<string> say)
        {
            say("Closing the game...");
            Kill();

            say("Putting the Windows Skyrim folders back...");
            Swap.Restore();

            // Refusing to continue while a junction is still live is the whole
            // safety property of this. Better a failed uninstall than a deleted
            // saves folder.
            foreach (string win in new[] { Paths.WinMyGames, Paths.WinLocalAD })
            {
                try
                {
                    if (Directory.Exists(win) &&
                        (new DirectoryInfo(win).Attributes & FileAttributes.ReparsePoint) != 0)
                    {
                        throw new Exception(
                            "Windows' Skyrim folder is still redirected at this build:\n\n    " + win +
                            "\n\nNothing has been removed. Close Skyrim, press Restore on this page, and try again.");
                    }
                }
                catch (Exception ex) { if (ex.Message.StartsWith("Windows'")) throw; }
            }

            say("Removing the shortcut...");
            DropShortcuts();

            var leave = new System.Collections.Generic.List<string>();
            leave.Add(Paths.Game);
            leave.Add(Paths.Personal);
            if (!keepSaves)
            {
                leave.Add(Paths.ProfileDir);
                leave.Add(Paths.CfgFile);
            }
            leave.Add(Paths.LauncherDir);
            return leave.ToArray();
        }

        /// <summary>
        /// Hands the rest to cmd and returns. The launcher has to be gone before
        /// its own folder can go, so this waits on the process id rather than
        /// guessing at a delay.
        /// </summary>
        public static void Finish(string[] targets, bool keepSaves)
        {
            var sb = new StringBuilder();
            sb.AppendLine("@echo off");
            sb.AppendLine("setlocal");
            sb.AppendLine(":wait");
            sb.AppendLine("tasklist /fi \"PID eq " + Process.GetCurrentProcess().Id + "\" | find \"" +
                          Process.GetCurrentProcess().Id + "\" >nul 2>&1");
            sb.AppendLine("if not errorlevel 1 ( timeout /t 1 /nobreak >nul & goto wait )");

            foreach (string t in targets)
            {
                if (string.IsNullOrEmpty(t)) continue;
                sb.AppendLine("rmdir /s /q \"" + t + "\" 2>nul");
                sb.AppendLine("del /f /q \"" + t + "\" 2>nul");
            }

            if (!keepSaves)
            {
                // Only then is the install folder itself worth trying. It goes
                // only if it is empty, so anything the user put in there by hand
                // survives and tells them where it was.
                sb.AppendLine("rmdir \"" + Paths.Root + "\" 2>nul");
            }

            sb.AppendLine("del /f /q \"%~f0\" >nul 2>&1");

            string script = Path.Combine(Path.GetTempPath(), "thornswood-uninstall.cmd");
            File.WriteAllText(script, sb.ToString(), Encoding.Default);

            var psi = new ProcessStartInfo("cmd.exe", "/c \"" + script + "\"");
            psi.CreateNoWindow = true;
            psi.UseShellExecute = false;
            psi.WorkingDirectory = Path.GetTempPath();
            Process.Start(psi);
        }
    }
}
