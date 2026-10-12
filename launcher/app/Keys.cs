using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text.RegularExpressions;

namespace Thornswood
{
    /// <summary>
    /// Every key this build binds that lives in a file, which turns out to be
    /// most of them.
    ///
    /// The Controls page used to be a table typed out by hand, which drifted
    /// the moment anything was rebound and then quietly lied. Now the page is
    /// built from these, read out of the real files at the moment you look, so
    /// it can only ever show what is actually set.
    ///
    /// Three families of key code, unfortunately. SKSE Menu Framework uses
    /// Windows virtual key codes; True Directional Movement, SkyUI and Better
    /// Third Person Selection use DirectInput scan
    /// codes, where the same letter is a different number; the minimap uses
    /// DirectInput too but writes it as a decimal. Each binding says which it
    /// speaks, and the translation happens by key name so a rebind cannot land
    /// on the wrong letter.
    /// </summary>
    static class Keys
    {
        public enum Codes { VirtualKey, VirtualKeyHex, ByName, DirectInput, DirectInputDecimal, JsonName }

        public class Binding
        {
            public string Id, Label, What, Group;
            public string Value;        // as shown: "F2"
            public Codes How;
            public string File, Key;
            public string Key2;         // a few settings carry a second copy
            public bool Hex { get { return How == Codes.VirtualKeyHex; } }
        }

        static string MenuIni   { get { return Path.Combine(Paths.Game, "Data\\SKSE\\Plugins\\SKSEMenuFramework.ini"); } }
        static string TdmIni    { get { return Path.Combine(Paths.Game, "Data\\MCM\\Config\\TrueDirectionalMovement\\settings.ini"); } }
        static string SkyUiIni  { get { return Path.Combine(Paths.Game, "Data\\MCM\\Config\\SkyUI_SE\\settings.ini"); } }
        static string BtpsIni   { get { return Path.Combine(Paths.Game, "Data\\MCM\\Config\\BetterThirdPersonSelection\\settings.ini"); } }
        static string ThornIni  { get { return Path.Combine(Paths.Game, "Data\\SKSE\\Plugins\\Thornswood.ini"); } }
        static string MpJson    { get { return Path.Combine(Paths.Game, "Data\\Platform\\Plugins\\skymp5-client-settings.txt"); } }

        // Windows virtual key codes, for the two settings written as hex. Only
        // keys that make sense as a menu toggle are here: a bind to a movement
        // key would be a hard mistake to undo from inside the game.
        static readonly Dictionary<string, int> ByName = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        static readonly Dictionary<int, string> ByCode = new Dictionary<int, string>();

        static Keys()
        {
            for (int i = 1; i <= 12; i++) Add("F" + i, 0x70 + i - 1);
            for (char c = 'A'; c <= 'Z'; c++) Add(c.ToString(), c);
            for (char c = '0'; c <= '9'; c++) Add(c.ToString(), c);
            Add("Insert", 0x2D); Add("Delete", 0x2E); Add("Home", 0x24); Add("End", 0x23);
            Add("Page up", 0x21); Add("Page down", 0x22);
            Add("Right Ctrl", 0xA3); Add("Right Shift", 0xA1); Add("Right Alt", 0xA5);
            Add("Backspace", 0x08); Add("Tab", 0x09); Add("Caps Lock", 0x14);
            Add("Num lock", 0x90); Add("Scroll lock", 0x91); Add("Pause", 0x13);
            Add("`", 0xC0); Add("-", 0xBD); Add("=", 0xBB);
            Add("[", 0xDB); Add("]", 0xDD); Add("\\", 0xDC);
            Add(";", 0xBA); Add("'", 0xDE); Add(",", 0xBC); Add(".", 0xBE); Add("/", 0xBF);

            // THE TWO THUMB BUTTONS, and they were the only thing missing.
            //
            // Grim Reefer, 21 September: "When in the launcher trying to change
            // controls for voice to mouse 4 or 5 it doesn't work. It registers
            // for other keys but not for mouse 4 or 5." Other keys worked,
            // which was the useful half of the report: the binding machinery
            // was fine and the CAPTURE never saw these.
            //
            // Nothing else had to change. BuildDik has bound Mouse 4 to 259 and
            // Mouse 5 to 260 all along, the client's own DxScanCode enum calls
            // those MouseButton3 and MouseButton4, and the Controls page
            // already binds 265, the wheel, for another mod. The only gap was
            // here: Set refuses a code Known does not hold, and these two were
            // not in this table, so even a capture that saw them would have
            // been turned away.
            //
            // THE NAMES MATCH THE DIK TABLE ON PURPOSE. Set translates by NAME
            // rather than by number, because the two numberings disagree, so
            // "Mouse 4" here and "Mouse 4" there are what make DikOf resolve.
            //
            // The left, right and middle buttons are deliberately absent. They
            // are in the DIK table because a mod may already be bound to one,
            // and DikName has to be able to say so; offering them on the
            // Controls page is different, and binding push to talk to the
            // attack button is not a thing to make one click away.
            Add("Mouse 4", 0x05);   // VK_XBUTTON1
            Add("Mouse 5", 0x06);   // VK_XBUTTON2

            BuildDik();
        }

        static void Add(string name, int code)
        {
            ByName[name] = code;
            if (!ByCode.ContainsKey(code)) ByCode[code] = name;
        }

        // DirectInput scan codes. A different numbering to the one above, used
        // by most of the mods here, and the reason a key cannot simply be
        // copied from one setting to another.
        static readonly Dictionary<string, int> DikByName = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        static readonly Dictionary<int, string> DikByCode = new Dictionary<int, string>();

        static void Dik(string name, int code)
        {
            DikByName[name] = code;
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

        /// <summary>
        /// The same key as a browser's KeyboardEvent.code, for the voice
        /// window. It runs in a browser rather than in the game, so it speaks
        /// neither DirectInput nor Windows virtual keys, and the launcher is
        /// the only thing that knows what a binding is actually set to.
        /// Translating by name rather than by number means a rebind cannot
        /// land on a different letter than the one on the page.
        /// </summary>
        public static string JsCode(string id)
        {
            string name = null;
            foreach (Binding b in All())
            {
                if (string.Equals(b.Id, id, StringComparison.Ordinal)) { name = b.Value; break; }
            }
            if (string.IsNullOrEmpty(name)) return null;
            name = name.Trim();

            if (name.Length == 1)
            {
                char c = char.ToUpperInvariant(name[0]);
                if (c >= 'A' && c <= 'Z') return "Key" + c;
                if (c >= '0' && c <= '9') return "Digit" + c;
            }
            switch (name.ToLowerInvariant())
            {
                case "space": return "Space";
                case "tab": return "Tab";
                case "escape": case "esc": return "Escape";
                case "enter": case "return": return "Enter";
                case "left shift": return "ShiftLeft";
                case "right shift": return "ShiftRight";
                case "left ctrl": case "left control": return "ControlLeft";
                case "right ctrl": case "right control": return "ControlRight";
                case "left alt": return "AltLeft";
                case "right alt": return "AltRight";
                case "caps lock": return "CapsLock";
                case "backspace": return "Backspace";
            }
            if (name.Length >= 2 && (name[0] == 'F' || name[0] == 'f'))
            {
                int fn;
                if (int.TryParse(name.Substring(1), out fn) && fn >= 1 && fn <= 12) return "F" + fn;
            }
            // Anything this does not know about is better left unbound in the
            // voice window than guessed at: the window falls back to its own
            // default and the Controls page still shows the truth.
            return null;
        }

        public static string DikName(int code)
        {
            if (code < 0) return "not bound";
            string n;
            return DikByCode.TryGetValue(code, out n) ? n : ("code " + code);
        }

        public static bool DikKnown(int code) { return DikByCode.ContainsKey(code); }
        public static int DikOf(string name) { int c; return DikByName.TryGetValue(name, out c) ? c : -1; }

        public static bool Known(int code) { return ByCode.ContainsKey(code); }
        public static string Name(int code) { string n; return ByCode.TryGetValue(code, out n) ? n : ""; }

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

        /// <summary>
        /// Rewrites one key in place, leaving every comment and every other
        /// line alone, and keeping the file's own spacing around the equals.
        /// SkyUI writes iSearchKey=57 with no spaces and reads its own file
        /// back strictly, so reformatting it is how a settings file gets
        /// silently ignored.
        ///
        /// A key that is not in the file is only added to Thornswood.ini
        /// (#529). The template is written once, on a machine with no file,
        /// so every key added to it later is missing on every older install,
        /// and those rows failed with "Could not write Thornswood.ini". Our
        /// plugins read a key wherever it is in the file, so it goes on the
        /// end. Another mod's file is never added to: that is its own format.
        /// </summary>
        static bool WriteIni(string file, string key, string value)
        {
            try
            {
                if (string.IsNullOrEmpty(key)) return true;
                if (!File.Exists(file)) return false;
                var lines = new List<string>(File.ReadAllLines(file));
                var rx = new Regex("^(\\s*)(" + Regex.Escape(key) + ")(\\s*=\\s*)", RegexOptions.IgnoreCase);
                for (int i = 0; i < lines.Count; i++)
                {
                    string t = lines[i].TrimStart();
                    if (t.StartsWith(";") || t.StartsWith("#")) continue;
                    Match m = rx.Match(lines[i]);
                    if (!m.Success) continue;
                    lines[i] = m.Groups[1].Value + m.Groups[2].Value + m.Groups[3].Value + value;
                    File.WriteAllLines(file, lines.ToArray());
                    return true;
                }
                if (!string.Equals(Path.GetFullPath(file), Path.GetFullPath(ThornIni), StringComparison.OrdinalIgnoreCase))
                    return false;
                if (lines.Count > 0 && lines[lines.Count - 1].Trim().Length > 0) lines.Add("");
                lines.Add(key + " = " + value);
                File.WriteAllLines(file, lines.ToArray());
                return true;
            }
            catch (Exception ex) { Swallow.Note("Keys.WriteIni", ex); }
            return false;
        }

        /// <summary>
        /// SkyMP keeps its own keys in skymp5-client-settings.txt, as names
        /// rather than codes, under "keybinds". The block is optional: the
        /// client falls back to its built in defaults when it is absent, which
        /// is why a fresh install has no keybinds section at all and the voice
        /// key still works. So a missing value is not an error here, it is the
        /// default, and writing one creates the block.
        /// </summary>
        static string ReadJsonKey(string file, string key)
        {
            try
            {
                if (!File.Exists(file)) return null;
                string t = File.ReadAllText(file);
                var m = Regex.Match(t, "\"" + Regex.Escape(key) + "\"\\s*:\\s*\"([^\"]*)\"");
                return m.Success ? m.Groups[1].Value : null;
            }
            catch { return null; }
        }

        static bool WriteJsonKey(string file, string key, string value)
        {
            try
            {
                if (!File.Exists(file)) return false;
                string t = File.ReadAllText(file);

                if (Regex.IsMatch(t, "\"" + Regex.Escape(key) + "\"\\s*:\\s*\"[^\"]*\""))
                {
                    t = Regex.Replace(t, "(\"" + Regex.Escape(key) + "\"\\s*:\\s*)\"[^\"]*\"",
                                      "$1\"" + value.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("$", "$$") + "\"");
                }
                else if (Regex.IsMatch(t, "\"keybinds\"\\s*:\\s*\\{"))
                {
                    t = Regex.Replace(t, "(\"keybinds\"\\s*:\\s*\\{)",
                                      "$1\n    \"" + key + "\": \"" + value + "\",");
                }
                else
                {
                    // No block yet. Put one in right after the opening brace.
                    int brace = t.IndexOf('{');
                    if (brace < 0) return false;
                    t = t.Substring(0, brace + 1) +
                        "\n  \"keybinds\": {\n    \"" + key + "\": \"" + value + "\"\n  }," +
                        t.Substring(brace + 1);
                }

                // No byte order mark. The client's JSON reader stops on one.
                // Through Hold, because this file is held while the game runs.
                string written = t;
                Hold.Around(file, delegate { File.WriteAllText(file, written, new System.Text.UTF8Encoding(false)); });
                return true;
            }
            catch { return false; }
        }

        static Binding Mp(string id, string group, string label, string what, string key, string fallback)
        {
            string got = ReadJsonKey(MpJson, key);
            return new Binding {
                Id = id, Group = group, Label = label, What = what,
                How = Codes.JsonName, File = MpJson, Key = key,
                Value = string.IsNullOrEmpty(got) ? fallback : got };
        }

        static Binding Vk(string id, string group, string label, string what, string file, string key, int fallback)
        {
            string raw = ReadIni(file, key);
            return new Binding {
                Id = id, Group = group, Label = label, What = what,
                How = Codes.VirtualKeyHex, File = file, Key = key,
                Value = Name(ParseCode(raw, fallback)) };
        }

        static Binding Dx(string id, string group, string label, string what, string file, string key, int fallback)
        {
            string raw = ReadIni(file, key);
            return new Binding {
                Id = id, Group = group, Label = label, What = what,
                How = Codes.DirectInput, File = file, Key = key,
                Value = DikName(ParseCode(raw, fallback)) };
        }

        static Binding Dxd(string id, string group, string label, string what, string file, string key, string key2, int fallback)
        {
            string raw = ReadIni(file, key);
            return new Binding {
                Id = id, Group = group, Label = label, What = what,
                How = Codes.DirectInputDecimal, File = file, Key = key, Key2 = key2,
                Value = DikName(ParseCode(raw, fallback)) };
        }

        public static List<Binding> All()
        {
            var l = new List<Binding>();

            /*
              THE TWO ROWS FROM THE OLD MULTIPLAYER MOD THAT USED TO BE HERE
              ARE GONE.

              "The party menu" and "The connection readout" wrote into that
              mod's own settings file under Data\SKSE\Plugins, which is not in
              this build and has not been for as long as anybody has looked. The
              filter at the bottom of All() drops a binding whose file is
              missing, so neither row has appeared on the page; what they were
              costing was a reader's time and the belief that this server had
              a party menu already.

              It has one now, and it is Thornswood's own: see the party and
              journal rows further down. Checked on 23 September, with the
              trade rows below.
            */

            // Not F1, which is what this shipped as. skymp5-client binds F1
            // to toggling the names above people's heads, and that binding is
            // compiled in: it cannot be moved from here. Every press of F1 to
            // open mod settings also turned everybody's name off, and the next
            // press turned them back on, which reads as names flickering at
            // random rather than as a key doing two things.
            //
            // The same client also holds F2 (hides the overlay, so the chat and
            // the wheel with it) and F6 (takes its focus). Those are worth
            // knowing about before binding anything near them.
            string menu = ReadIni(MenuIni, "ToggleKey");
            l.Add(new Binding {
                Id = "menu", Group = "Settings", Label = "Mod settings",
                What = "TrueHUD, Precision and the rest of the newer mods live here rather than in the old MCM.",
                How = Codes.ByName, File = MenuIni, Key = "ToggleKey",
                Value = string.IsNullOrEmpty(menu) ? "F4" : menu.Trim() });

            /*
              AND THE SIX TRADING ROWS, WHICH ARE WHY LOOKING AT SOMEBODY DID
              NOTHING.

              They were an old trade mod's, an add-on of the old multiplayer
              mod, writing into its own ini under Data\SKSE\Plugins. Neither the
              ini nor the DLL
              is in this build; checked 23 September. Patrick, 22 September:
              "Currently the looking at people doesnt have the trade menu and
              when it did you had to use youyr cursor and a bunch of other bs
              I just want to press a key while looking at them." The cursor he
              remembers was that mod's mouse menu, and the reason the key did
              nothing is that it was setting a value in a file nobody reads.

              Thornswood has its own trading now, in the gamemode and in
              thornswood-trade.js, and its key is in the ThornsWood group
              below with the rest of ours.
            */

            // The two minimap binds that used to sit here, L to show it and K
            // for its settings panel, are gone with the mod. Confirmed on 20
            // September: no minimap plugin in the load order, and neither
            // Luckycheech_MiniMapMenu.ini nor MiniMap.dll is anywhere in the
            // game folder. They were writing settings into a file that does
            // not exist and putting two rows on the launcher's key page for a
            // mod nobody has. K is now the profession menu below.
            //
            // The rest of it went on 23 September: two saved settings in
            // Config.cs that nothing read, a comment in Display.cs about a
            // corner that is no longer worked out anywhere, and the nth
            // occurrence machinery in Enforce.cs that only the minimap's
            // position ever needed. Nothing writes to a minimap ini now.

            l.Add(Dx("search", "Inventory", "Search",
                     "Types into the search box at the top of any inventory, container or barter list.",
                     SkyUiIni, "iSearchKey", 57));
            l.Add(Dx("switchtab", "Inventory", "Switch column",
                     "Jumps between the two halves of a container or a trade without reaching for the mouse.",
                     SkyUiIni, "iSwitchTabKey", 56));
            l.Add(Dx("equipmode", "Inventory", "Equip mode",
                     "Held down, equips to the other hand instead of the usual one.",
                     SkyUiIni, "iEquipModeKey", 42));
            l.Add(Dx("favadd", "Favourites", "Add to a group",
                     "In the favourites menu, puts the highlighted item into one of the eight groups.",
                     SkyUiIni, "iFavoriteGroupAddKey", 33));
            l.Add(Dx("favuse", "Favourites", "Equip a whole group",
                     "In the favourites menu, equips everything in the highlighted group at once.",
                     SkyUiIni, "iFavoriteGroupUseKey", 19));
            l.Add(Dx("favicon", "Favourites", "Set a group's icon",
                     "In the favourites menu, changes the icon shown against a group.",
                     SkyUiIni, "iFavoriteSetIconKey", 56));
            l.Add(Dx("favstate", "Favourites", "Change how a group equips",
                     "In the favourites menu, switches an item between equip, unequip and toggle.",
                     SkyUiIni, "iFavoriteEquipStateKey", 20));
            l.Add(Dx("favfocus", "Favourites", "Move between items and groups",
                     "In the favourites menu, moves the cursor between the item list and the group list.",
                     SkyUiIni, "iFavoriteToggleFocusKey", 57));
            l.Add(Dx("favhot1", "Favourites", "Group 1 in the world",
                     "Out in the world, equips favourites group one without opening anything.",
                     SkyUiIni, "iFavoriteGroupUseHotkey1", 59));
            l.Add(Dx("favhot2", "Favourites", "Group 2 in the world",
                     "Out in the world, equips favourites group two.",
                     SkyUiIni, "iFavoriteGroupUseHotkey2", 60));
            l.Add(Dx("favhot3", "Favourites", "Group 3 in the world",
                     "Out in the world, equips favourites group three.",
                     SkyUiIni, "iFavoriteGroupUseHotkey3", 61));
            l.Add(Dx("favhot4", "Favourites", "Group 4 in the world",
                     "Out in the world, equips favourites group four.",
                     SkyUiIni, "iFavoriteGroupUseHotkey4", 62));

            l.Add(Dx("lock", "Combat", "Lock on",
                     "Holds the camera on whatever you are aiming at.",
                     TdmIni, "uTargetLockKey", 258));
            l.Add(Dx("lockleft", "Combat", "Switch target left",
                     "Moves the lock to the next thing on your left. Unbound by default, the mouse wheel does it.",
                     TdmIni, "uSwitchTargetLeftKey", -1));
            l.Add(Dx("lockright", "Combat", "Switch target right",
                     "Moves the lock to the next thing on your right. Unbound by default.",
                     TdmIni, "uSwitchTargetRightKey", -1));
            l.Add(Dx("lockbehind", "Combat", "Look past your target",
                     "Swings the camera behind whatever you are locked on to. Unbound by default.",
                     TdmIni, "uTargetLockBehindTargetKey", -1));

            // Thornswood's own. These are read by the SkyrimPlatform plugins out
            // of the same file, in the same DirectInput numbering, so a rebind
            // here is a rebind in game with nothing to regenerate.
            l.Add(Dx("emotewheel", "ThornsWood", "The emote wheel",
                     "Eight quick slots in the middle, and every emote in a list you can search. Everyone else sees what you play. While the wheel is open, 1 to 8 play a slot; with it shut they are Skyrim's favourites hotkeys.",
                     ThornIni, "WheelKey", 34));
            l.Add(Dx("emotepage", "ThornsWood", "Search the wheel",
                     "With the wheel open, moves to the search so you can type a name.",
                     ThornIni, "PageKey", 15));
            l.Add(Dx("emoteclose", "ThornsWood", "Close the wheel",
                     "Shuts the wheel without playing anything.",
                     ThornIni, "CloseKey", 1));
            l.Add(Dx("emotestop", "ThornsWood", "Stand up",
                     "Breaks you out of an idle that has no natural end. Works whether or not the wheel is open, because that is usually why you want it.",
                     ThornIni, "StopKey", 49));

            l.Add(Dx("chat", "ThornsWood", "Talk in chat",
                     "Hands the keyboard to the chat box and puts the cursor in it. Escape gives it back to the game. Nothing in Skyrim uses Enter while you are playing, which is why it is here.",
                     ThornIni, "ChatKey", 28));
            l.Add(Dx("command", "ThornsWood", "Type a command",
                     "Opens the chat with a slash already typed, for what is still typed there: /stuck, /helpme and /report, how a line is said (/me, /do, /w, /s, /y and /ooc), /roll, /needs for the needs bars as text, and staff and dev commands. The game's skill tree, also on this key, stays shut.",
                     ThornIni, "CommandKey", 53));
            // The help panel (#1633): what /help used to say, as the keys and
            // panels it is now, opened without the chat. F7: every letter is
            // already Skyrim's or ours, F1 to F4 are SkyUI's favourite groups
            // (F1 and F2 the client's as well), F5 and F9 are quicksave and
            // quickload, F6 is the client's, F8 the mark and F10 closing Skyrim
            // at creation. tests\test-1633-help-panel.js checks that nothing
            // else of ours, the mods' or Skyrim's answers to it.
            l.Add(Dx("help", "ThornsWood", "Help",
                     "Opens the help panel: talking, people, living, work, land and getting help, with every key named as it is bound here. Help on the K, P and J panels opens it too. This key or Escape closes it.",
                     ThornIni, "HelpKey", 65));


            l.Add(Dx("skills", "ThornsWood", "Profession, class and skill tree",
                     "Your profession and which half of it you work, your class, and the fifteen sub-skills under Health, Magicka and Stamina. Opens over the world without pausing it. Escape closes it too. A Master looking at somebody they could take on as an apprentice sees this key named under the crosshair, and it opens on that person.",
                     ThornIni, "SkillsKey", 37));

            // ------------------------------------------------ the people keys
            // Three of these only mean anything while somebody is under your
            // crosshair, which is what makes them safe on plain letters: with
            // nobody in front of you the key falls through to whatever else
            // wants it. P and J open their panels either way.
            //
            // MuteThemKey is deliberately not MuteKey, the microphone's old
            // name, so one row can never set two different things.
            l.Add(Dx("party", "ThornsWood", "Friends and party",
                     "Who your friends are, who is online, your party, and the bonus for working together. Escape closes it.",
                     ThornIni, "PartyKey", 25));
            l.Add(Dx("journal", "ThornsWood", "Journals",
                     "Your journals and their pages, and sharing a journal or one page with a friend.",
                     ThornIni, "JournalKey", 36));
            l.Add(Dx("friendkey", "ThornsWood", "Add or remove a friend",
                     "While you are looking at somebody, asks them to be friends. Pressed on somebody already on your list, takes them off it.",
                     ThornIni, "FriendKey", 21));
            l.Add(Dx("tradewith", "ThornsWood", "Offer a trade",
                     "While you are looking at somebody, offers to trade. They have forty five seconds to take it, and nothing moves until you have both agreed to what is on the table. In your inventory, while you have a wound to tend, the same key opens the panel that tends it.",
                     ThornIni, "TradeWithKey", 35));
            l.Add(Dx("mutethem", "ThornsWood", "Mute somebody",
                     "While you are looking at somebody, stops hearing them. Yours only: they are not told, and nobody else is affected. Press again to hear them.",
                     ThornIni, "MuteThemKey", 38));
            l.Add(Dx("moldkey", "ThornsWood", "Press a key mold into a lock",
                     "While you are looking at a building's door with a blank key mold in your pack, presses it into the lock so it becomes that building's mold. The holder has to be you or be standing there. The same key, while you are looking at somebody inside a building you hold, lets them sleep there for a night, or ends their night. In your inventory, with a repair kit in your pack, the same key opens the repair panel.",
                     ThornIni, "MoldKey", 22));
            l.Add(Dx("lockkey", "ThornsWood", "Claim, lock or unlock a door",
                     "While you are looking at a door of the building you just opened, a line names what this key does there: claims the building when nobody holds it, and locks or unlocks it when it is yours. At a forge, carrying a key mold that has been pressed into a door, it cuts a key from the mold. At a crop, it claims the farm around it when the line says so. While you are looking at somebody with a wound to tend, it opens the panel that tends it.",
                     ThornIni, "LockKey", 45));
            l.Add(Dx("maneuvers", "ThornsWood", "A warrior's maneuvers",
                     "Opens a small panel with the maneuvers you hold. Press a number or click one to start it. This key or Escape closes the panel.",
                     ThornIni, "ManeuverKey", 10));

            l.Add(Dx("cyclehold", "Reaching things", "Cycle modifier",
                     "Held down, the two keys below step through everything you could reach instead of the game picking for you.",
                     BtpsIni, "iObjectCycleModifierKey", 42));
            l.Add(Dx("cycleup", "Reaching things", "Next thing",
                     "With the modifier held, moves the activate prompt to the next thing in range.",
                     BtpsIni, "iCycleUpKey", 264));
            l.Add(Dx("cycledown", "Reaching things", "Previous thing",
                     "With the modifier held, moves the activate prompt back one.",
                     BtpsIni, "iCycleDownKey", 265));

            // ------------------------------------------------------- voice
            // These live in Thornswood.ini beside the emote keys, in the same
            // scan codes, so they rebind from this page like everything else.
            // The plugin reads them and forwards the state into the page
            // drawing the overlay. It has to work that way round: voice needs a
            // browser and the game's own browser does not hold the keyboard
            // while you are playing, so a key pressed in the game would never
            // reach it. There is no second window any more, and nothing to
            // alt-tab to.
            l.Add(Dx("ptt", "Voice", "Hold to talk",
                     "Everyone near you hears you while it is held. Voice is positional: the further away somebody is standing the quieter you are, and past thirty metres they hear nothing.",
                     ThornIni, "PushToTalk", 47));
            // There was a "Mute the microphone" row here, MuteKey, Y. Nothing
            // has read MuteKey since the voice plugin dropped its mute (push to
            // talk already keeps the microphone shut), so the row wrote a
            // setting nothing read, and Y went to FriendKey (#529).
            l.Add(Dx("voicemode", "Voice", "Whisper, talk or yell",
                     "Steps your voice from a whisper to your normal voice to a yell and round again.",
                     ThornIni, "VoiceModeKey", 48));
            l.Add(Dx("voicelock", "Voice", "Keep talking",
                     "Locks the microphone open until you press it again, for a song or a long speech without holding the talk key. The corner of the screen says when it opens and when it shuts.",
                     ThornIni, "VoiceLockKey", 24));

            // No SkyMP client keys here, deliberately. that server's build reads a
            // "keybinds" block out of skymp5-client-settings.txt with voice,
            // nicknames, an overlay and an animation menu in it. This build's
            // client does not: the only things it reads out of that file are
            // server-ip, server-port, server-master-key and profileId. Listing
            // a talk key here would put a row on the Controls page for a
            // feature that is not compiled in, with a Change button that writes
            // a setting nothing reads. If voice is ever built into the client,
            // this is where it goes.

            // Anything whose file is not on this machine is not a key anybody
            // can press, and listing it is worse than listing nothing: the
            // minimap sat on this page for weeks after the mod came out of the
            // build, with a Change button that wrote to a file that was not
            // there. The page is generated from the real files, so it should
            // be generated from the ones that exist.
            var live = new List<Binding>();
            foreach (Binding b in l)
            {
                if (string.IsNullOrEmpty(b.File)) { live.Add(b); continue; }
                try { if (File.Exists(b.File)) live.Add(b); } catch (Exception ex) { Swallow.Note("Keys.All, checking binding file", ex); }
            }
            return live;
        }

        static int ParseCode(string raw, int fallback)
        {
            if (string.IsNullOrEmpty(raw)) return fallback;
            raw = raw.Trim();
            try
            {
                if (raw.StartsWith("0x", StringComparison.OrdinalIgnoreCase))
                    return Convert.ToInt32(raw.Substring(2), 16);
                int n;
                if (int.TryParse(raw, out n)) return n;
                // The minimap writes its buttons as 38.000000.
                double d;
                if (double.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out d))
                    return (int)Math.Round(d);
            }
            catch (Exception ex) { Swallow.Note("Keys.ParseCode", ex); }
            return fallback;
        }

        /// <summary>
        /// Returns an empty string on success, or why it refused.
        /// </summary>
        public static string Set(Binding b, int virtualKey)
        {
            if (!Known(virtualKey))
                return "That key cannot be used here. Try a function key, a letter, or something like Insert.";

            string name = Name(virtualKey);

            // The DirectInput settings speak a different numbering, so the key
            // has to be translated by name rather than by number. A key the two
            // tables do not share cannot be used for those.
            int dik = -1;
            bool isDik = b.How == Codes.DirectInput || b.How == Codes.DirectInputDecimal;
            if (isDik)
            {
                dik = DikOf(name);
                if (dik < 0) return name + " is not a key that mod can bind. Try a letter or a function key.";
            }

            // Two things on the same key leaves one of them unreachable with no
            // way to tell which. Only within the same file and the same group,
            // though: SkyUI deliberately reuses Space and Left Alt between the
            // inventory and the favourites menu, and those never fire together.
            foreach (Binding other in All())
            {
                if (other.Id == b.Id) continue;
                if (!string.Equals(other.File, b.File, StringComparison.OrdinalIgnoreCase)) continue;
                if (!string.Equals(other.Group, b.Group, StringComparison.OrdinalIgnoreCase)) continue;
                string mine = isDik ? DikName(dik) : name;
                if (string.Equals(other.Value, mine, StringComparison.OrdinalIgnoreCase))
                    return mine + " is already " + other.Label.ToLowerInvariant() + ".";
            }

            bool ok;
            if (b.How == Codes.DirectInputDecimal)
            {
                string v = dik.ToString("0.000000", CultureInfo.InvariantCulture);
                ok = WriteIni(b.File, b.Key, v);
                if (ok && !string.IsNullOrEmpty(b.Key2)) WriteIni(b.File, b.Key2, v);
            }
            else if (b.How == Codes.DirectInput) ok = WriteIni(b.File, b.Key, dik.ToString());
            else if (b.How == Codes.VirtualKeyHex) ok = WriteIni(b.File, b.Key, "0x" + virtualKey.ToString("X2"));
            else if (b.How == Codes.JsonName) ok = WriteJsonKey(b.File, b.Key, name);
            else ok = WriteIni(b.File, b.Key, name);

            if (!ok) return "Could not write " + Path.GetFileName(b.File) + ".";
            return "";
        }
    }
}
