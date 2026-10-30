using System;
using System.Collections.Generic;
using System.IO;
using System.Text.RegularExpressions;

namespace Thornswood
{
    /// <summary>
    /// The few Thornswood keys the launcher names: five on the Play page's
    /// card for somebody who has played, and push to talk on the voice line.
    /// Read out of Data\SKSE\Plugins\Thornswood.ini at the moment they are
    /// shown, so each says the key it is really bound to.
    ///
    /// Only read here. Every key is changed in the game, on Settings at the
    /// foot of the help panel and of the K, P and J panels (#3126), where it
    /// takes effect at once; game\ui\thornswood-settings.js has the rows and
    /// game\plugins\thornswood-front.js writes them. The launcher's Controls
    /// page, which wrote them with Skyrim closed, went with that, and with it
    /// the virtual key table, the capture and the writers for the other mods'
    /// files.
    /// </summary>
    static class Keys
    {
        public class Binding
        {
            public string Id, Key;
            public string Value;        // as shown: "G"
        }

        static string ThornIni  { get { return Path.Combine(Paths.Game, "Data\\SKSE\\Plugins\\Thornswood.ini"); } }

        static Keys()
        {
            BuildDik();
        }

        // DirectInput scan codes, the numbering Thornswood.ini speaks, with
        // the names the in-game Settings panel gives them.
        static readonly Dictionary<int, string> DikByCode = new Dictionary<int, string>();

        static void Dik(string name, int code)
        {
            if (!DikByCode.ContainsKey(code)) DikByCode[code] = name;
        }

        static void BuildDik()
        {
            string row1 = "QWERTYUIOP";
            for (int i = 0; i < row1.Length; i++) Dik(row1[i].ToString(), 16 + i);
            string row2 = "ASDFGHJKL";
            for (int i = 0; i < row2.Length; i++) Dik(row2[i].ToString(), 30 + i);
            string row3 = "ZXCVBNM";
            for (int i = 0; i < row3.Length; i++) Dik(row3[i].ToString(), 44 + i);
            for (int i = 1; i <= 9; i++) Dik(i.ToString(), 1 + i);
            Dik("0", 11);
            for (int i = 1; i <= 10; i++) Dik("F" + i, 58 + i);
            Dik("F11", 87); Dik("F12", 88);

            Dik("Esc", 1); Dik("-", 12); Dik("=", 13); Dik("Backspace", 14); Dik("Tab", 15);
            Dik("[", 26); Dik("]", 27); Dik("Enter", 28); Dik("Left Ctrl", 29);
            Dik(";", 39); Dik("'", 40); Dik("`", 41);
            Dik("Left Shift", 42); Dik("\\", 43); Dik(",", 51); Dik(".", 52); Dik("/", 53);
            Dik("Right Shift", 54);
            Dik("Num *", 55); Dik("Left Alt", 56); Dik("Space", 57); Dik("Caps Lock", 58);
            Dik("Num Lock", 69); Dik("Scroll Lock", 70);
            Dik("Num 7", 71); Dik("Num 8", 72); Dik("Num 9", 73); Dik("Num -", 74);
            Dik("Num 4", 75); Dik("Num 5", 76); Dik("Num 6", 77); Dik("Num +", 78);
            Dik("Num 1", 79); Dik("Num 2", 80); Dik("Num 3", 81); Dik("Num 0", 82); Dik("Num .", 83);
            Dik("Num Enter", 156); Dik("Right Ctrl", 157); Dik("Num /", 181);
            Dik("Print Screen", 183); Dik("Right Alt", 184); Dik("Pause", 197);
            Dik("Home", 199); Dik("Up", 200); Dik("Page up", 201); Dik("Left", 203);
            Dik("Right", 205); Dik("End", 207); Dik("Down", 208); Dik("Page down", 209);
            Dik("Insert", 210); Dik("Delete", 211);

            // Mouse rides on the same numbering, offset past the keyboard.
            Dik("Left mouse", 256); Dik("Right mouse", 257); Dik("Middle mouse", 258);
            Dik("Mouse 4", 259); Dik("Mouse 5", 260);
            Dik("Wheel up", 264); Dik("Wheel down", 265);
        }

        public static string DikName(int code)
        {
            if (code < 0) return "not bound";
            string n;
            return DikByCode.TryGetValue(code, out n) ? n : ("code " + code);
        }

        static string ReadIni(string file, string key)
        {
            try
            {
                if (!File.Exists(file)) return null;
                var rx = new Regex("^\\s*" + Regex.Escape(key) + "\\s*=\\s*(.*?)\\s*$", RegexOptions.IgnoreCase);
                foreach (string line in File.ReadAllLines(file))
                {
                    string t = line.TrimStart();
                    if (t.StartsWith(";") || t.StartsWith("#")) continue;
                    Match m = rx.Match(line);
                    if (m.Success) return m.Groups[1].Value;
                }
            }
            catch (Exception ex) { Swallow.Note("Keys.ReadIni", ex); }
            return null;
        }

        static Binding Dx(string id, string key, int fallback)
        {
            string raw = ReadIni(ThornIni, key);
            return new Binding { Id = id, Key = key, Value = DikName(ParseCode(raw, fallback)) };
        }

        /// <summary>
        /// The keys named on the launcher, as set. The defaults are the
        /// template's (launcher\Thornswood.ini), the same as the KEYS rows in
        /// thornswood-settings.js, and a harness in tests holds them together
        /// (test-thornswood-keys). Nothing when there is no Thornswood.ini yet: no key is
        /// pressed in a game that has not been installed.
        /// </summary>
        public static List<Binding> All()
        {
            var l = new List<Binding>();
            try { if (!File.Exists(ThornIni)) return l; } catch (Exception ex) { Swallow.Note("Keys.All, checking Thornswood.ini", ex); return l; }
            l.Add(Dx("emotewheel", "WheelKey", 34));
            l.Add(Dx("tradewith", "TradeWithKey", 35));
            l.Add(Dx("party", "PartyKey", 25));
            l.Add(Dx("friendkey", "FriendKey", 21));
            l.Add(Dx("journal", "JournalKey", 36));
            l.Add(Dx("ptt", "PushToTalk", 47));
            return l;
        }

        static int ParseCode(string raw, int fallback)
        {
            int n;
            if (!string.IsNullOrEmpty(raw) && int.TryParse(raw.Trim(), out n)) return n;
            return fallback;
        }
    }
}
