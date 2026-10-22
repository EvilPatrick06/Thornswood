using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;

namespace Thornswood
{
    /// <summary>
    /// Reads and writes the handful of SSE Display Tweaks settings worth having
    /// in a launcher. Several ship commented out with a '#', so setting one has
    /// to uncomment the existing line rather than append a duplicate the game
    /// would ignore.
    /// </summary>
    /// <summary>
    /// Field of view, kept in Thornswood.ini rather than with the rest of the
    /// display settings.
    ///
    /// Two reasons it is not in SSEDisplayTweaks.ini with its neighbours. That
    /// file belongs to a mod which may not be in the build, and everything on
    /// this page goes dead when it is missing, whereas the field of view has
    /// nothing to do with it. And the game plugin has to read this at runtime:
    /// Skyrim rewrites its own fDefaultWorldFOV on loads, menus and anything
    /// that swaps the camera, so a number in an ini the game reads once does
    /// not hold. Thornswood.ini is the file the plugins already read, so the
    /// launcher writes one place and the game picks it up from there.
    /// </summary>
    static class Fov
    {
        /// <summary>
        /// What Skyrim uses when nobody has said otherwise.
        ///
        /// fDefaultWorldFOV is not written into Skyrim.ini or SkyrimPrefs.ini
        /// in this build, so the game is running its own built in number. The
        /// box rests on it, and a value equal to it removes the setting rather
        /// than storing it, so the game plugin has nothing to read and does not
        /// register an update handler at all. Setting the field of view to the
        /// number it already is should cost nothing, not cost a call a second.
        /// </summary>
        public const int Default = 65;

        public const int Min = 60;
        public const int Max = 140;

        static string IniPath
        {
            get { return Path.Combine(Paths.Game, "Data\\SKSE\\Plugins\\Thornswood.ini"); }
        }

        /// <summary>The set value, or Skyrim's own default when nothing is set.</summary>
        public static int Get()
        {
            try
            {
                // No file means nothing has been set, which means the game is
                // using its own default. This returned 0, and the settings page
                // prints whatever comes back, so a fresh install showed a field
                // of view of 0. A collection install has no Thornswood.ini until
                // something writes one, so every one of them started that way.
                if (!File.Exists(IniPath)) return Default;
                var rx = new Regex(@"^\s*Fov\s*=\s*(\d+)\s*$", RegexOptions.IgnoreCase);
                foreach (string line in File.ReadAllLines(IniPath))
                {
                    string t = line.TrimStart();
                    if (t.StartsWith("#") || t.StartsWith(";")) continue;
                    Match m = rx.Match(line);
                    if (m.Success)
                    {
                        int n;
                        if (int.TryParse(m.Groups[1].Value, out n)) return n;
                    }
                }
            }
            catch (Exception ex) { Swallow.Note("Fov.Get, reading " + IniPath, ex); }
            return Default;
        }

        /// <summary>
        /// The default, or anything out of range, removes the line and hands
        /// the field of view back to the game untouched.
        /// </summary>
        public static bool Set(int fov)
        {
            try
            {
                // Same reason: with no file there was nothing to edit and this
                // returned false, so somebody on a fresh install could not set
                // a field of view at all. Make one rather than refusing.
                if (!File.Exists(IniPath))
                {
                    if (fov <= 0 || fov == Default) return true;   // nothing to record
                    try { Directory.CreateDirectory(Path.GetDirectoryName(IniPath)); } catch (Exception ex) { Swallow.Note("Fov.Set, creating " + Path.GetDirectoryName(IniPath), ex); }
                    File.WriteAllLines(IniPath, new string[] { "Fov=" + fov });
                    return true;
                }
                var lines = new List<string>(File.ReadAllLines(IniPath));
                var rx = new Regex(@"^\s*Fov\s*=", RegexOptions.IgnoreCase);

                for (int i = lines.Count - 1; i >= 0; i--)
                    if (rx.IsMatch(lines[i])) lines.RemoveAt(i);

                if (fov > 0 && fov != Default) lines.Add("Fov=" + fov);
                File.WriteAllLines(IniPath, lines);
                return true;
            }
            catch { return false; }
        }
    }

    /// <summary>
    /// How long the chat stays on screen after its last line, in seconds, or
    /// 0 for always.
    ///
    /// Patrick, 24 September: "can you make the default for the chat to hide
    /// after 10 seconds if the server sends a message or someone else or if
    /// you do and it come back when you hit enter and add an option in the
    /// launcher settings to make it 5, 10, 15, 20 or permeant like it is now."
    ///
    /// Kept in Thornswood.ini as ChatFade, beside the field of view and for
    /// the same reason: the game plugin reads that file and hands the number
    /// to the chat page. Ten is the default and is not written, so an install
    /// that never opens Settings gets ten with nothing in the file.
    /// </summary>
    static class ChatFade
    {
        public const int Default = 10;

        /// <summary>The choices in Settings, in the order they are shown. 0 is always on screen.</summary>
        public static readonly int[] Choices = { 5, 10, 15, 20, 0 };

        static string IniPath
        {
            get { return Path.Combine(Paths.Game, "Data\\SKSE\\Plugins\\Thornswood.ini"); }
        }

        /// <summary>The set value, or the default when nothing, or nothing it could be, is set.</summary>
        public static int Get()
        {
            try
            {
                if (!File.Exists(IniPath)) return Default;
                var rx = new Regex(@"^\s*ChatFade\s*=\s*(\d+)\s*$", RegexOptions.IgnoreCase);
                foreach (string line in File.ReadAllLines(IniPath))
                {
                    Match m = rx.Match(line);
                    if (!m.Success) continue;
                    int n;
                    if (int.TryParse(m.Groups[1].Value, out n) && Array.IndexOf(Choices, n) >= 0) return n;
                    return Default;
                }
            }
            catch (Exception ex) { Swallow.Note("ChatFade.Get, reading " + IniPath, ex); }
            return Default;
        }

        /// <summary>
        /// Writes the choice. The default takes the line out rather than
        /// writing it, and a number that is not one of the choices is refused.
        /// </summary>
        public static bool Set(int seconds)
        {
            if (Array.IndexOf(Choices, seconds) < 0) return false;
            try
            {
                if (!File.Exists(IniPath))
                {
                    if (seconds == Default) return true;   // nothing to record
                    Directory.CreateDirectory(Path.GetDirectoryName(IniPath));
                    File.WriteAllLines(IniPath, new string[] { "ChatFade=" + seconds });
                    return true;
                }
                var lines = new List<string>(File.ReadAllLines(IniPath));
                var rx = new Regex(@"^\s*ChatFade\s*=", RegexOptions.IgnoreCase);
                for (int i = lines.Count - 1; i >= 0; i--)
                    if (rx.IsMatch(lines[i])) lines.RemoveAt(i);
                if (seconds != Default) lines.Add("ChatFade=" + seconds);
                File.WriteAllLines(IniPath, lines);
                return true;
            }
            catch (Exception ex)
            {
                Swallow.Note("ChatFade.Set, writing " + IniPath, ex);
                return false;
            }
        }
    }

    /// <summary>
    /// Whether the needs bars (Hunger, Thirst, Rest, Temp) are drawn on screen.
    ///
    /// Patrick, 24 September: "also add an option in settings to hide the
    /// needs menu on the screen so it doesnt show and they can do /needs to
    /// find it all". Hidden is NeedsBars=0 in Thornswood.ini; shown is no line
    /// at all, so an install that never opens Settings keeps the bars. The
    /// needs themselves carry on either way, and the Body page on K says them.
    /// /needs went with #1631 and came back as a line of text for somebody
    /// who hid the bars (Patrick, 11 Oct, #2267).
    /// </summary>
    static class NeedsBars
    {
        static string IniPath
        {
            get { return Path.Combine(Paths.Game, "Data\\SKSE\\Plugins\\Thornswood.ini"); }
        }

        public static bool Shown()
        {
            try
            {
                if (!File.Exists(IniPath)) return true;
                var rx = new Regex(@"^\s*NeedsBars\s*=\s*0\s*$", RegexOptions.IgnoreCase);
                foreach (string line in File.ReadAllLines(IniPath))
                    if (rx.IsMatch(line)) return false;
            }
            catch (Exception ex) { Swallow.Note("NeedsBars.Shown, reading " + IniPath, ex); }
            return true;
        }

        public static bool Set(bool shown)
        {
            try
            {
                if (!File.Exists(IniPath))
                {
                    if (shown) return true;   // nothing to record
                    Directory.CreateDirectory(Path.GetDirectoryName(IniPath));
                    File.WriteAllLines(IniPath, new string[] { "NeedsBars=0" });
                    return true;
                }
                var lines = new List<string>(File.ReadAllLines(IniPath));
                var rx = new Regex(@"^\s*NeedsBars\s*=", RegexOptions.IgnoreCase);
                for (int i = lines.Count - 1; i >= 0; i--)
                    if (rx.IsMatch(lines[i])) lines.RemoveAt(i);
                if (!shown) lines.Add("NeedsBars=0");
                File.WriteAllLines(IniPath, lines);
                return true;
            }
            catch (Exception ex)
            {
                Swallow.Note("NeedsBars.Set, writing " + IniPath, ex);
                return false;
            }
        }
    }

    static class Display
    {
        public static string IniPath
        {
            get { return Path.Combine(Paths.Game, "Data\\SKSE\\Plugins\\SSEDisplayTweaks.ini"); }
        }

        public static bool Available { get { return File.Exists(IniPath); } }

        public static string Get(string key)
        {
            try
            {
                if (!Available) return null;
                var rx = new Regex("^\\s*" + Regex.Escape(key) + "\\s*=\\s*(.*?)\\s*$", RegexOptions.IgnoreCase);
                foreach (string line in File.ReadAllLines(IniPath))
                {
                    string t = line.TrimStart();
                    if (t.StartsWith("#") || t.StartsWith(";")) continue;   // commented out means "game default"
                    Match m = rx.Match(line);
                    if (m.Success) return m.Groups[1].Value;
                }
            }
            catch (Exception ex) { Swallow.Note("Display.Get, reading " + IniPath, ex); }
            return null;
        }

        public static bool GetBool(string key, bool fallback)
        {
            string v = Get(key);
            if (v == null) return fallback;
            return v.Trim().Equals("true", StringComparison.OrdinalIgnoreCase) || v.Trim() == "1";
        }

        public static int GetInt(string key, int fallback)
        {
            int n;
            string v = Get(key);
            if (v != null && int.TryParse(v.Trim(), out n)) return n;
            return fallback;
        }

        public static bool Set(string key, string value)
        {
            try
            {
                if (!Available) return false;
                var lines = new List<string>(File.ReadAllLines(IniPath));
                var live = new Regex("^(\\s*)" + Regex.Escape(key) + "\\s*=", RegexOptions.IgnoreCase);
                var dead = new Regex("^(\\s*)[#;]\\s*" + Regex.Escape(key) + "\\s*=", RegexOptions.IgnoreCase);

                for (int i = 0; i < lines.Count; i++)
                {
                    if (live.IsMatch(lines[i])) { lines[i] = key + "=" + value; WriteBack(lines); return true; }
                }
                for (int i = 0; i < lines.Count; i++)
                {
                    if (dead.IsMatch(lines[i])) { lines[i] = key + "=" + value; WriteBack(lines); return true; }
                }

                // Not mentioned at all, so add it under [Render].
                int render = lines.FindIndex(l => l.Trim().Equals("[Render]", StringComparison.OrdinalIgnoreCase));
                if (render >= 0) lines.Insert(render + 1, key + "=" + value);
                else lines.Add(key + "=" + value);
                WriteBack(lines);
                return true;
            }
            catch { return false; }
        }

        static void WriteBack(List<string> lines)
        {
            File.WriteAllLines(IniPath, lines.ToArray());
        }

        // ---- the three display modes, expressed as the two flags the mod uses
        public static string Mode
        {
            get
            {
                if (GetBool("Fullscreen", false)) return "Fullscreen";
                if (GetBool("Borderless", true)) return "Borderless";
                return "Windowed";
            }
        }

        public static void SetMode(string mode)
        {
            if (mode == "Fullscreen") { Set("Fullscreen", "true"); Set("Borderless", "false"); }
            else if (mode == "Windowed") { Set("Fullscreen", "false"); Set("Borderless", "false"); }
            else { Set("Fullscreen", "false"); Set("Borderless", "true"); }
        }

        /// <summary>
        /// Skyrim's own ini decides how big a window it asks for, and Display
        /// Tweaks decides what it actually gets. Leave the two disagreeing and
        /// you get the thing that looks like a broken install: a game window
        /// that does not reach the bottom of the screen, with the desktop
        /// showing underneath.
        ///
        /// Returns what it changed it to, or null when it was already right or
        /// could not be read.
        /// </summary>
        public static string MatchScreen()
        {
            ScreenMode m = Detect();
            if (m == null) return null;
            string want = m.ToString();

            bool moved = false;
            if (Available && !string.Equals(Get("Resolution"), want, StringComparison.OrdinalIgnoreCase))
                moved = Set("Resolution", want) || moved;

            if (SetPrefsSize(m.Width, m.Height)) moved = true;
            return moved ? want : null;
        }

        static string PrefsPath { get { return Path.Combine(Paths.LiveMyGames, "SkyrimPrefs.ini"); } }

        /// <summary>
        /// iSize W and iSize H, written in place. The space in "iSize W" is
        /// Bethesda's, not a typo, and a key written without it is ignored.
        /// </summary>
        static bool SetPrefsSize(int w, int h)
        {
            try
            {
                string file = PrefsPath;
                if (!File.Exists(file)) return false;
                var lines = new List<string>(File.ReadAllLines(file));
                bool changed = false;
                var want = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                want["iSize W"] = w.ToString();
                want["iSize H"] = h.ToString();

                for (int i = 0; i < lines.Count; i++)
                {
                    string t = lines[i].TrimStart();
                    if (t.StartsWith(";") || t.StartsWith("#")) continue;
                    int eq = lines[i].IndexOf('=');
                    if (eq <= 0) continue;
                    string key = lines[i].Substring(0, eq).Trim();
                    string val;
                    if (!want.TryGetValue(key, out val)) continue;
                    if (lines[i].Substring(eq + 1).Trim() == val) continue;
                    lines[i] = key + "=" + val;
                    changed = true;
                }
                if (changed) File.WriteAllLines(file, lines.ToArray());
                return changed;
            }
            catch { return false; }
        }

        // ---- what the screen is actually set to -------------------------------
        //
        // Not SystemParameters, and not Screen.Bounds. Both of those report the
        // size in device independent units, so a 3440x1440 monitor running at
        // 150% comes back as 2293x960 and the game gets told to run at a
        // resolution the screen does not have. EnumDisplaySettings asks the
        // display driver what mode it is in and answers in real pixels, whatever
        // the scaling is set to.

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
        struct DEVMODE
        {
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
            public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
            public int dmFields;
            public short dmOrientation, dmPaperSize, dmPaperLength, dmPaperWidth,
                         dmScale, dmCopies, dmDefaultSource, dmPrintQuality;
            public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
            public short dmLogPixels;
            public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
            public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType,
                       dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
        }

        [DllImport("user32.dll", CharSet = CharSet.Ansi)]
        static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);

        const int ENUM_CURRENT_SETTINGS = -1;

        public class ScreenMode
        {
            public int Width, Height, Hz;
            public override string ToString() { return Width + "x" + Height; }
        }

        /// <summary>The primary display's current mode, or null if it cannot be read.</summary>
        public static ScreenMode Detect()
        {
            try
            {
                var dm = new DEVMODE();
                dm.dmDeviceName = "";
                dm.dmFormName = "";
                dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
                if (!EnumDisplaySettings(null, ENUM_CURRENT_SETTINGS, ref dm)) return null;

                // Anything outside this is a driver answering nonsense, and a
                // nonsense resolution in the ini is worse than none at all.
                if (dm.dmPelsWidth < 800 || dm.dmPelsHeight < 600) return null;
                if (dm.dmPelsWidth > 16384 || dm.dmPelsHeight > 16384) return null;

                return new ScreenMode {
                    Width = dm.dmPelsWidth,
                    Height = dm.dmPelsHeight,
                    Hz = dm.dmDisplayFrequency
                };
            }
            catch { return null; }
        }
    }
}
