using System;
using System.IO;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;

namespace Thornswood
{
    /// <summary>
    /// Data\SKSE\Plugins\Thornswood.ini: one machine's key binds, microphone
    /// name and field of view. The launcher writes it (Keys, Mics, Display)
    /// and the game plugins read it.
    ///
    /// It never travels. Until 17 Sep it did: Publish-Update packaged it out
    /// of the machine that ships, so three packs put that machine's Fov=120
    /// and its binds on everybody, and every update put them back over
    /// whatever people had set. It is on Ship-Rules' machine list now, and
    /// two things follow from that, both here: a machine with no file gets
    /// the template (launcher\Thornswood.ini, built into the exe), and the
    /// Fov=120 those packs left behind is taken back once, the way Leaks takes
    /// back the sign in file.
    /// </summary>
    static class ThornIni
    {
        public static string File_
        {
            get { return Path.Combine(Paths.Game, "Data\\SKSE\\Plugins\\Thornswood.ini"); }
        }

        /// <summary>
        /// Writes the template when there is no file. Mics will not write a
        /// microphone into a file that does not exist and Keys will not
        /// rebind in one, so a fresh install needs this before Play. Returns
        /// a line for the log, or null when there was nothing to do.
        /// </summary>
        public static string Ensure()
        {
            try
            {
                string p = File_;
                if (File.Exists(p)) return null;
                string text = Template();
                if (text == null) return null;
                Directory.CreateDirectory(Path.GetDirectoryName(p));
                File.WriteAllText(p, text, new UTF8Encoding(false));
                return "Wrote Data\\SKSE\\Plugins\\Thornswood.ini with the default keys. The Controls page changes them.";
            }
            catch { return null; }
        }

        /// <summary>launcher\Thornswood.ini, as Build-Launcher put it in the exe.</summary>
        static string Template()
        {
            try
            {
                using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("Thornswood.ini"))
                {
                    if (s == null) return null;
                    using (var r = new StreamReader(s, Encoding.UTF8))
                        return r.ReadToEnd();
                }
            }
            catch { return null; }
        }

        /// <summary>
        /// Once per install: a Fov=120 goes back to Skyrim's own 65. That is
        /// the exact value the 16 Sep packs carried. Whoever wants 120 sets it
        /// in Settings, and from then on it stays, because this never runs a
        /// second time. Returns a line for the log, or null.
        /// </summary>
        public static string UndoShippedFov()
        {
            try
            {
                string flag = Path.Combine(Paths.ProfileDir, "fov-120-undone.txt");
                if (File.Exists(flag)) return null;
                Mark(flag);
                string p = File_;
                if (!File.Exists(p)) return null;
                var rx = new Regex(@"^\s*Fov\s*=\s*120\s*$", RegexOptions.IgnoreCase);
                bool hit = false;
                foreach (string line in File.ReadAllLines(p))
                    if (rx.IsMatch(line)) { hit = true; break; }
                if (!hit) return null;
                if (!Fov.Set(Fov.Default)) return null;
                return "Field of view put back to Skyrim's 65. The 16 Sep updates carried another machine's 120 by mistake. Settings has it if you want it changed.";
            }
            catch { return null; }
        }

        static void Mark(string flag)
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(flag));
                File.WriteAllText(flag, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
            }
            catch (Exception ex) { Swallow.Note("ThornIni.Mark, " + flag, ex); }
        }
    }
}
