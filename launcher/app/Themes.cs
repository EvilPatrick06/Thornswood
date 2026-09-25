using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Media;

namespace Thornswood
{
    class Theme
    {
        public string Name;
        public string Note;            // one line, shown under the swatch row
        public string Swatch;          // the colour on its button
        public bool Light;             // lets anything that draws its own graphics pick a side
        public Dictionary<string, string> Colors = new Dictionary<string, string>();
    }

    // Every colour in the window comes from here, by name, through DynamicResource.
    // Nothing in the XAML holds a literal, which is the whole reason a theme can be
    // swapped while the launcher is open.
    //
    // The sixteen names below are the complete set. A theme that leaves one out
    // would leave the old theme's colour on screen next to the new one, so each
    // is written out in full rather than inherited from a base.
    //
    //   Bg          the ground the window sits on
    //   Panel       header, nav rail and status bar
    //   Card        a raised surface on the ground
    //   CardHover   the same surface under the pointer
    //   Deep        recessed: text fields, code, wells
    //   Line        hairline borders
    //   Edge        a lighter hairline, for a lit top edge
    //   Ink         body text
    //   Muted       secondary text
    //   Faint       labels, counts, anything incidental
    //   Accent      one colour, used sparingly
    //   AccentSoft  the accent at low alpha, for a selected row
    //   AccentInk   text that sits on the accent
    //   Ok/Warn/Bad state, and never the accent
    static class Themes
    {
        static Theme Make(string name, string note, bool light, string[] pairs)
        {
            var t = new Theme();
            t.Name = name;
            t.Note = note;
            t.Light = light;
            for (int i = 0; i < pairs.Length; i += 2) t.Colors[pairs[i]] = pairs[i + 1];
            t.Swatch = t.Colors["Accent"];
            return t;
        }

        public static readonly Theme[] All = new Theme[]
        {
            Make("Forge", "Warm iron and ember. The default.", false, new string[] {
                "Bg","#100D0A", "Panel","#171310", "Card","#1D1813",
                "CardHover","#262019", "Deep","#0A0807", "Line","#2C251D",
                "Edge","#3A3126", "Ink","#EDE5D8", "Muted","#9C8D79",
                "Faint","#66594A", "Accent","#C8763A", "AccentSoft","#3CC8763A",
                "AccentInk","#1B1205", "Ok","#7A9A55", "Warn","#C79A3E",
                "Bad","#BC5039" }),

            Make("Nightfall", "Blue grey, the launcher's first look.", false, new string[] {
                "Bg","#0E1216", "Panel","#141A20", "Card","#182028",
                "CardHover","#1E2830", "Deep","#090C0F", "Line","#232E36",
                "Edge","#2F3D47", "Ink","#E4EAEE", "Muted","#7E8D97",
                "Faint","#4E5A63", "Accent","#C8763A", "AccentSoft","#3CC8763A",
                "AccentInk","#1B1205", "Ok","#5C9C66", "Warn","#B9903F",
                "Bad","#B8483C" }),

            Make("Slate", "Neutral graphite with a cold accent.", false, new string[] {
                "Bg","#0F1113", "Panel","#16191C", "Card","#1B1F23",
                "CardHover","#22272C", "Deep","#0A0B0D", "Line","#262C31",
                "Edge","#333A41", "Ink","#E6E9EC", "Muted","#858E96",
                "Faint","#545C63", "Accent","#5B8FB9", "AccentSoft","#3C5B8FB9",
                "AccentInk","#06131D", "Ok","#5C9C66", "Warn","#B9903F",
                "Bad","#B8483C" }),

            Make("Ember", "Banked coals.", false, new string[] {
                "Bg","#12100F", "Panel","#1A1614", "Card","#201B18",
                "CardHover","#29221E", "Deep","#0C0A09", "Line","#2E2724",
                "Edge","#3D342F", "Ink","#EDE7E3", "Muted","#96877F",
                "Faint","#5E524C", "Accent","#C04A2E", "AccentSoft","#3CC04A2E",
                "AccentInk","#FFEDE6", "Ok","#6E9457", "Warn","#C99A46",
                "Bad","#E0765E" }),

            Make("Moss", "Damp stone and pine.", false, new string[] {
                "Bg","#0D1210", "Panel","#131A16", "Card","#18211C",
                "CardHover","#1E2922", "Deep","#080C0A", "Line","#232F28",
                "Edge","#2F3E35", "Ink","#E2EAE4", "Muted","#7E9088",
                "Faint","#4D5C54", "Accent","#94B86B", "AccentSoft","#3C94B86B",
                "AccentInk","#0B1406", "Ok","#5C9C7A", "Warn","#B9903F",
                "Bad","#B8483C" }),

            Make("Frostfall", "The Pale, after dark.", false, new string[] {
                "Bg","#0B0F14", "Panel","#111721", "Card","#161E2A",
                "CardHover","#1C2634", "Deep","#070A0E", "Line","#223047",
                "Edge","#2E4056", "Ink","#E2EBF5", "Muted","#7D8DA3",
                "Faint","#4D5B6D", "Accent","#6FB7D8", "AccentSoft","#3C6FB7D8",
                "AccentInk","#04161E", "Ok","#5C9C8A", "Warn","#B9903F",
                "Bad","#C05C50" }),

            Make("Nightingale", "Violet and shadow.", false, new string[] {
                "Bg","#100D15", "Panel","#16121E", "Card","#1C1726",
                "CardHover","#241D30", "Deep","#0A0810", "Line","#2A2237",
                "Edge","#372D48", "Ink","#E8E2F0", "Muted","#8C7FA3",
                "Faint","#574C6B", "Accent","#9A6FD0", "AccentSoft","#3C9A6FD0",
                "AccentInk","#100522", "Ok","#5C9C66", "Warn","#B9903F",
                "Bad","#C04E63" }),

            Make("Dwemer", "Brass on old bronze.", false, new string[] {
                "Bg","#0F0D0A", "Panel","#15120D", "Card","#1B1710",
                "CardHover","#241E15", "Deep","#090705", "Line","#2B2418",
                "Edge","#3B3320", "Ink","#EFE6CE", "Muted","#9C8E6C",
                "Faint","#645A42", "Accent","#C9A227", "AccentSoft","#3CC9A227",
                "AccentInk","#171200", "Ok","#7D9A4A", "Warn","#D2762A",
                "Bad","#BF4436" }),

            Make("Parchment", "Ink on warm paper. Light.", true, new string[] {
                "Bg","#EFEAE0", "Panel","#F8F4EC", "Card","#FFFDF8",
                "CardHover","#F2ECE0", "Deep","#E4DDD0", "Line","#D8CFBE",
                "Edge","#FFFFFF", "Ink","#221D16", "Muted","#5E5546",
                "Faint","#8C8372", "Accent","#A2572A", "AccentSoft","#28A2572A",
                "AccentInk","#FFF6EF", "Ok","#4A7D52", "Warn","#94702B",
                "Bad","#A03A2E" }),

            Make("Snow", "Cold daylight. Light.", true, new string[] {
                "Bg","#EEF1F4", "Panel","#F8FAFC", "Card","#FFFFFF",
                "CardHover","#EFF3F7", "Deep","#E2E7EC", "Line","#D3DAE1",
                "Edge","#FFFFFF", "Ink","#1A1F24", "Muted","#55606B",
                "Faint","#8794A0", "Accent","#2F6FA8", "AccentSoft","#282F6FA8",
                "AccentInk","#F2F8FC", "Ok","#3C7D4E", "Warn","#8A6A20",
                "Bad","#A33A2E" }),

        };

        public static Theme Find(string name)
        {
            foreach (Theme t in All)
                if (string.Equals(t.Name, name, StringComparison.OrdinalIgnoreCase)) return t;
            return All[0];
        }

        public static void Apply(Window w, string name)
        {
            Theme t = Find(name);
            foreach (KeyValuePair<string, string> kv in t.Colors)
                w.Resources[kv.Key] = new SolidColorBrush((Color)ColorConverter.ConvertFromString(kv.Value));
        }
    }
}
