using System;
using System.IO;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;

namespace Thornswood
{
    /// <summary>
    /// Data\SKSE\Plugins\Thornswood.ini: one machine's key binds, microphone
    /// name, field of view, chat fade and needs bars. Settings in the game
    /// writes the keys and the rest (#3126), the launcher writes the
    /// microphone (Mics), and the game plugins read it.
    ///
    /// It never travels. Until 17 Sep it did: Publish-Update packaged it out
    /// of the machine that ships, so three packs put that machine's Fov=120
    /// and its binds on everybody, and every update put them back over
    /// whatever people had set. It is on Ship-Rules' machine list now, so a
    /// machine with no file gets the template (launcher\Thornswood.ini,
    /// built into the exe) here.
    /// </summary>
    static class ThornIni
    {
        public static string File_
        {
            get { return Path.Combine(Paths.Game, "Data\\SKSE\\Plugins\\Thornswood.ini"); }
        }

        /// <summary>
        /// Writes the template when there is no file. Mics will not write a
        /// microphone into a file that does not exist, so a fresh install
        /// needs this before Play. Returns
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
                return "Wrote Data\\SKSE\\Plugins\\Thornswood.ini with the default keys. Settings in the game changes them.";
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
    }
}
