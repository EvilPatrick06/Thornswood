using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;

namespace Thornswood
{
    /// <summary>
    /// The script that puts a downloaded launcher in place of the running one,
    /// and the launcher's own half of the way back when the new one will not
    /// start.
    ///
    /// Before this the script moved the new exe straight over the old one.
    /// The old launcher was gone the moment that move went through, so a new
    /// build that Defender flagged, or that fell over on its first start, left
    /// somebody with no launcher at all and a reinstall as the only way back.
    /// On the To Do List as "The launcher's self update destroys the old exe
    /// and has no way back": "An unsigned exe that Defender flags is exactly
    /// when a fallback is needed".
    ///
    /// Now the old exe is renamed to Thornswood.exe.old before the new one
    /// goes in, and it stays there until the new one has shown it started:
    /// the new launcher deletes the .old itself once its window has drawn
    /// (Settle, wired in Shell.Run). The script watches for that. If the new
    /// launcher has gone and the .old is still there, it never started
    /// cleanly, so the script moves it aside as Thornswood.exe.bad, puts the
    /// .old back and starts that. The launcher that comes back says so in the
    /// log and clears the .bad.
    ///
    /// Kept apart from Updater, with nothing in it but the framework, so that
    /// tools\test-self-update.ps1 can compile it on its own and drive the
    /// real script against stub launchers in a scratch folder, broken ones
    /// included.
    /// </summary>
    static class SelfSwap
    {
        /// <summary>
        /// How many times, about a second apart, the script looks for the new
        /// launcher to have started before it stops watching: five minutes.
        ///
        /// A launcher that cannot start goes in seconds: an exception at
        /// startup, Defender ending it, or the "could not start" box somebody
        /// reads and closes. Longer than this and a launcher that is still up
        /// has not failed, it is slow, and it is left alone. The .old then
        /// stays until that launcher draws its window and clears it.
        ///
        /// Bounded for a second reason. A launcher built from source older
        /// than this file never clears the .old, so one of those shipped as a
        /// rollback reads as a failed start if it is closed inside the watch,
        /// and the launcher before it comes back and offers it again. Five
        /// minutes keeps that to somebody who updates and closes straight away.
        /// </summary>
        public const int WatchChecks = 300;

        public static string OldOf(string exe) { return exe + ".old"; }
        public static string BadOf(string exe) { return exe + ".bad"; }

        public static string Script(string exe, string neu, int pid)
        {
            return Script(exe, neu, pid, WatchChecks);
        }

        /// <summary>
        /// The whole cmd script, CRLF line ends, for File.WriteAllText.
        /// </summary>
        public static string Script(string exe, string neu, int pid, int checks)
        {
            string old = OldOf(exe);
            string bad = BadOf(exe);
            string e = "\"" + exe + "\"";
            string n = "\"" + neu + "\"";
            string o = "\"" + old + "\"";
            string b = "\"" + bad + "\"";

            // Waits for this launcher to actually be gone, then keeps trying
            // the move.
            //
            // It used to sleep two seconds and move once. Closing runs
            // Swap.Restore, Hold.Release, Keep.Unpark and SkyMp.Stop, which
            // together take longer than that, so the move could hit an exe
            // that was still running, fail silently, and start would reopen
            // the old one. The next check then offered the same update again,
            // and again. This is the tasklist wait Uninstall.Finish uses.
            //
            // cmd reads a .cmd file in the console's OEM code page, not the
            // UTF-8 this is written in, so a path with any character outside
            // ASCII would reach move and start as different bytes and the new
            // launcher would never be put in place. chcp tells cmd how to read
            // the rest of the file.
            var bs = new StringBuilder();
            bs.Append("@echo off\r\n");
            bs.Append("chcp 65001 >nul\r\n");
            bs.Append("setlocal\r\n");
            bs.Append(":wait\r\n");
            bs.Append("tasklist /fi \"PID eq " + pid + "\" | find \"" + pid + "\" >nul 2>&1\r\n");
            // ping rather than timeout for the pause: timeout wants a console
            // of its own and this script is started hidden.
            bs.Append("if not errorlevel 1 ( ping 127.0.0.1 -n 2 >nul & goto wait )\r\n");
            bs.Append("set /a tries=0\r\n");
            // A .old still here is one a launcher could not clear. The one that
            // just asked for this update is running fine, so it is the copy
            // worth keeping now. /f because a read-only .old would refuse the
            // rename below and the update would never go in.
            bs.Append("if exist " + o + " del /f /q " + o + " >nul 2>&1\r\n");
            bs.Append(":swap\r\n");
            // Already gone means somebody else finished the job.
            bs.Append("if not exist " + n + " goto run\r\n");
            // Nothing to keep if there is no old exe, and the new one goes in
            // the way it always did.
            bs.Append("if not exist " + e + " goto place\r\n");
            // Renamed, not copied: a rename is one step, so there is no moment
            // with half a file at either name.
            bs.Append("move /y " + e + " " + o + " >nul 2>&1\r\n");
            bs.Append("if errorlevel 1 goto again\r\n");
            bs.Append(":place\r\n");
            bs.Append("move /y " + n + " " + e + " >nul 2>&1\r\n");
            bs.Append("if not errorlevel 1 goto swapped\r\n");
            // The new one would not go in. The old one goes straight back, so
            // there is a launcher at the path between tries and after them.
            bs.Append("if not exist " + e + " if exist " + o + " move /y " + o + " " + e + " >nul 2>&1\r\n");
            bs.Append(":again\r\n");
            // Windows can hold a file open for a moment after the process that
            // had it has ended. About a minute of trying, then start whatever
            // is there rather than leave somebody with no launcher at all.
            bs.Append("set /a tries+=1\r\n");
            bs.Append("if %tries% lss 30 ( ping 127.0.0.1 -n 2 >nul & goto swap )\r\n");
            bs.Append(":run\r\n");
            bs.Append("if not exist " + e + " if exist " + o + " move /y " + o + " " + e + " >nul 2>&1\r\n");
            bs.Append("start \"\" " + e + "\r\n");
            bs.Append("goto done\r\n");

            // The new one is in and the old one is kept beside it.
            bs.Append(":swapped\r\n");
            bs.Append("if not exist " + o + " goto run\r\n");
            // start on a file that is not there puts up a "Windows cannot
            // find" box and waits on it, so a new exe that went missing (this
            // is where a quarantine shows) goes straight to the way back.
            bs.Append("if not exist " + e + " goto back\r\n");
            bs.Append("set /a looked=0\r\n");
            // start leaves errorlevel as it found it when it works, measured
            // 24 September: after a failed command, a good start still reads
            // 1. So it is cleared first, and a non-zero one after start is
            // start's own.
            bs.Append("(call )\r\n");
            bs.Append("start \"\" " + e + "\r\n");
            bs.Append("if errorlevel 1 goto back\r\n");
            bs.Append(":watch\r\n");
            bs.Append("ping 127.0.0.1 -n 2 >nul\r\n");
            // The new launcher deletes the .old once its window has drawn.
            bs.Append("if not exist " + o + " goto done\r\n");
            bs.Append("if not exist " + e + " goto back\r\n");
            // Is the new launcher still running? A rename cannot say: measured
            // 24 September, a running exe renames without complaint. It cannot
            // be opened for writing, though, and can be the moment it exits.
            // Opening it that way writes nothing and leaves its size and time
            // alone. So an open that works means it has gone without ever
            // clearing the .old, and that is a launcher that did not start.
            bs.Append("2>nul ( >>" + e + " (call ) ) && goto back\r\n");
            bs.Append("set /a looked+=1\r\n");
            bs.Append("if %looked% lss " + checks + " goto watch\r\n");
            bs.Append("goto done\r\n");

            // The way back. Checked again first: a launcher that cleared the
            // .old and was closed straight after is a good one.
            bs.Append(":back\r\n");
            bs.Append("if not exist " + o + " goto done\r\n");
            bs.Append("if exist " + b + " del /f /q " + b + " >nul 2>&1\r\n");
            bs.Append("if exist " + e + " move /y " + e + " " + b + " >nul 2>&1\r\n");
            // Could not move the new one aside: leave everything where it is.
            // The .old stays for whoever looks next.
            bs.Append("if exist " + e + " goto done\r\n");
            bs.Append("move /y " + o + " " + e + " >nul 2>&1\r\n");
            bs.Append("if not exist " + e + " goto unback\r\n");
            bs.Append("start \"\" " + e + "\r\n");
            bs.Append("goto done\r\n");
            bs.Append(":unback\r\n");
            bs.Append("if exist " + b + " move /y " + b + " " + e + " >nul 2>&1\r\n");
            bs.Append(":done\r\n");
            bs.Append("del \"%~f0\"\r\n");
            return bs.ToString();
        }

        /// <summary>
        /// The launcher's half, run once its window has drawn, which is what
        /// a clean start means here. Deletes the .old the update script kept,
        /// which is how the script knows this one started, and clears a .bad
        /// left by a way back, saying which version it was. Returns a line for
        /// the log, or null when there is nothing to say, which is every start
        /// but the first after an update.
        /// </summary>
        public static string Settle(string exe)
        {
            if (String.IsNullOrEmpty(exe)) return null;
            string said = null;

            string old = OldOf(exe);
            // A few tries, because antivirus can hold a file it is reading for
            // a moment, and a .old that stays is what the script takes for a
            // launcher that never started.
            for (int i = 0; i < 5 && File.Exists(old); i++)
            {
                try
                {
                    File.SetAttributes(old, FileAttributes.Normal);
                    File.Delete(old);
                }
                catch (Exception ex)
                {
                    if (i == 4)
                        said = "Could not clear the copy of the previous launcher at " + old + " (" + ex.Message + ").";
                    else
                        Thread.Sleep(1000);
                }
            }

            string bad = BadOf(exe);
            if (File.Exists(bad))
            {
                string v = null;
                try { v = FileVersionInfo.GetVersionInfo(bad).ProductVersion; } catch { }
                string what = String.IsNullOrEmpty(v) ? "The last launcher update" : "Launcher " + v;
                string line = what + " did not start on this machine, so the launcher you had before was put back. " +
                              "The update is offered again. If it fails the same way, tell Patrick.";
                try
                {
                    File.SetAttributes(bad, FileAttributes.Normal);
                    File.Delete(bad);
                }
                catch { }
                said = said == null ? line : line + "  " + said;
            }
            return said;
        }
    }
}
