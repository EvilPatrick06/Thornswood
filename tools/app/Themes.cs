using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Media;

namespace SkyrimTogether
{
    class Theme
    {
        public string Name;
        public string Swatch;          // the colour shown on its button
        public Dictionary<string, string> Colors = new Dictionary<string, string>();
    }

    static class Themes
    {
        static Theme Make(string name, string swatch, string[] pairs)
        {
            var t = new Theme();
            t.Name = name;
            t.Swatch = swatch;
            for (int i = 0; i < pairs.Length; i += 2) t.Colors[pairs[i]] = pairs[i + 1];
            return t;
        }

        public static readonly Theme[] All = new Theme[]
        {
            Make("Nightfall", "#C8763A", new string[] {
                "Bg","#0E1216", "Panel","#141A20", "Card","#182028", "CardHover","#1E2830",
                "Line","#232E36", "Ink","#E4EAEE", "Muted","#7E8D97", "Faint","#4E5A63",
                "Accent","#C8763A", "AccentInk","#FFF3E8",
                "Ok","#5C9C66", "Warn","#B9903F", "Bad","#B8483C" }),

            Make("Slate", "#5B8FB9", new string[] {
                "Bg","#0F1113", "Panel","#16191C", "Card","#1B1F23", "CardHover","#22272C",
                "Line","#262C31", "Ink","#E6E9EC", "Muted","#858E96", "Faint","#545C63",
                "Accent","#5B8FB9", "AccentInk","#F2F8FC",
                "Ok","#5C9C66", "Warn","#B9903F", "Bad","#B8483C" }),

            Make("Ember", "#C04A2E", new string[] {
                "Bg","#12100F", "Panel","#1A1614", "Card","#201B18", "CardHover","#29221E",
                "Line","#2E2724", "Ink","#EDE7E3", "Muted","#96877F", "Faint","#5E524C",
                "Accent","#C04A2E", "AccentInk","#FFF0EA",
                "Ok","#6E9457", "Warn","#C09440", "Bad","#C0463A" }),

            Make("Moss", "#5E8E5A", new string[] {
                "Bg","#0D1210", "Panel","#131A16", "Card","#18211C", "CardHover","#1E2922",
                "Line","#232F28", "Ink","#E2EAE4", "Muted","#7E9088", "Faint","#4D5C54",
                "Accent","#5E8E5A", "AccentInk","#F1F8EF",
                "Ok","#5E8E5A", "Warn","#B9903F", "Bad","#B8483C" }),

            Make("Parchment", "#A2572A", new string[] {
                "Bg","#F1EFEA", "Panel","#FAF8F4", "Card","#FFFFFF", "CardHover","#F4F1EB",
                "Line","#DCD7CC", "Ink","#1D2023", "Muted","#5E6670", "Faint","#8C939B",
                "Accent","#A2572A", "AccentInk","#FFF6EF",
                "Ok","#4A7D52", "Warn","#94702B", "Bad","#A03A2E" })
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
