using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;

namespace Thornswood
{
    /// <summary>
    /// Stops Windows asking about the game's browser.
    ///
    /// Skyrim Platform does not draw its interface inside the game's own
    /// process. It starts a second program to do it, and that program binds a
    /// listening socket, so the first time it runs Windows Firewall stops
    /// everything and asks whether public and private networks may reach
    /// "skyrimplatformcef.exe.hidden", published by Unknown. Nobody recognises
    /// that name and nobody should have to decide about it mid session.
    ///
    /// There are two of these and which one appears depends on the browser
    /// backend. SkyrimPlatformCEF.exe.hidden is ours and ships in the
    /// installer. CEFSubprocess.exe is NirnLab's, which is another server's
    /// framework and is no longer put into the folder this build runs from,
    /// but it is still on machines that run from the Steam copy.
    ///
    /// Windows only asks when no rule matches the program, so the fix is for a
    /// rule to be there first. It is a BLOCK, not an allow:
    ///
    ///   - The helper talks to the game, which is on the same machine, and
    ///     Windows Firewall does not filter loopback at all. Blocking it from
    ///     the network changes nothing about how the interface draws.
    ///   - Allow is what the prompt offers and it is the wrong answer. It opens
    ///     a browser engine to the local network for no reason anybody can name.
    ///   - Somebody who already pressed Cancel is in this state already and the
    ///     game has been working, which is the evidence that it costs nothing.
    ///
    /// Outbound is untouched. Windows allows outbound by default and nothing
    /// here changes that.
    ///
    /// Writing a firewall rule needs administrator, and the launcher is not
    /// and should not be. So this asks once, through the usual Windows prompt,
    /// and records the answer whatever it is. One prompt on one day beats the
    /// firewall interrupting every fresh install.
    /// </summary>
    public static class Firewall
    {
        /// <summary>The name every rule this writes shares, so they can be found again.</summary>
        const string RuleName = "Thornswood browser helper";

        /// <summary>
        /// The out of process browser helpers, relative to the game folder.
        /// The same two names Checks.Helpers watches for after a crash; if one
        /// list grows the other should.
        /// </summary>
        static readonly string[] Relative =
        {
            @"Data\Platform\Distribution\RuntimeDependencies\SkyrimPlatformCEF.exe.hidden",
            @"Data\NirnLabUIPlatform\CEFSubprocess.exe"
        };

        /// <summary>Which of them are actually on this machine.</summary>
        public static List<string> Present()
        {
            var found = new List<string>();
            foreach (string rel in Relative)
            {
                try
                {
                    string full = Path.Combine(Paths.Game, rel);
                    if (File.Exists(full)) found.Add(full);
                }
                catch (Exception ex) { Swallow.Note("Firewall.Present, " + rel, ex); }
            }
            return found;
        }

        /// <summary>
        /// Writes the rules, asking for administrator once.
        ///
        /// Returns null when there was nothing to do, otherwise a line for the
        /// log. Never throws: a firewall rule is a convenience and the game
        /// runs without it, so nothing here is allowed to stop a launch.
        /// </summary>
        public static string Ensure(Action<string> say)
        {
            List<string> helpers = Present();
            if (helpers.Count == 0) return null;

            string script = null;
            try
            {
                // One elevated run, not one per rule, so there is one prompt.
                //
                // Each rule is deleted before it is added, because netsh adds a
                // second rule of the same name rather than replacing the first,
                // and a folder that moves would otherwise leave a rule pointing
                // at a path that no longer exists.
                var sb = new StringBuilder();
                sb.AppendLine("@echo off");
                foreach (string full in helpers)
                {
                    string name = RuleName + " (" + Path.GetFileName(full) + ")";
                    sb.AppendLine("netsh advfirewall firewall delete rule name=\"" + name + "\" >nul 2>&1");
                    sb.AppendLine("netsh advfirewall firewall add rule name=\"" + name + "\"" +
                                  " dir=in action=block program=\"" + full + "\" enable=yes");
                }

                Directory.CreateDirectory(Paths.ProfileDir);
                script = Path.Combine(Paths.ProfileDir, "firewall-rules.cmd");
                File.WriteAllText(script, sb.ToString(), new UTF8Encoding(false));
            }
            catch (Exception ex)
            {
                if (say != null) say("Could not write the firewall rules: " + ex.Message);
                return null;
            }

            try
            {
                var psi = new ProcessStartInfo(script);
                psi.UseShellExecute = true;   // required for runas
                psi.Verb = "runas";           // this is the Windows prompt
                psi.CreateNoWindow = true;
                psi.WindowStyle = ProcessWindowStyle.Hidden;

                Process p = Process.Start(psi);
                if (p != null) p.WaitForExit(20000);
            }
            catch (Exception ex)
            {
                // The usual one is the person saying no to the Windows prompt,
                // which is their call and is not an error. Said once, quietly,
                // and never asked again.
                if (say != null)
                    say("Windows was not allowed to add the firewall rules, so it may still " +
                        "ask about the game's browser. Nothing is broken either way: " + ex.Message);
                return null;
            }
            finally
            {
                try { if (script != null) File.Delete(script); }
                catch (Exception ex) { Swallow.Note("Firewall.Ensure, deleting script", ex); }
            }

            return helpers.Count == 1
                ? "Windows will stop asking about the game's browser."
                : "Windows will stop asking about the game's " + helpers.Count + " browser helpers.";
        }
    }
}
