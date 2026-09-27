using System;
using System.Collections.Generic;
using System.IO;

namespace Thornswood
{
    // Where each mod in this build came from.
    //
    // The mod list shows plugin and DLL file names, which are not what anyone
    // searches for. This maps those file names onto the page the mod was
    // downloaded from, so a row can be clicked and land somewhere useful.
    //
    // Every entry here was looked up and confirmed against the page itself. If
    // a name is not in the table, the row falls back to a Nexus search for that
    // name rather than guessing at an address that might be the wrong mod.
    //
    // Only mods this build ships belong here. A mod that leaves the collection
    // loses its entry in the same change, so the launcher never sends anybody
    // to a page for something they cannot have. Revision 5 of the collection
    // took out Tavern Games, SunHelm Survival and SunHelm Diseases, and their
    // entries came out with them.
    static class Links
    {
        const string N = "https://www.nexusmods.com/skyrimspecialedition/mods/";

        static readonly Dictionary<string, string> Map =
            new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        // Names that have no page to go to: the two another server plugins are private
        // to that server, and the Bethesda masters are the game itself.
        static readonly Dictionary<string, bool> None =
            new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);

        // Checked in order, only after the exact name and its trimmed forms
        // have missed. Patch plugins are named after the mod they patch, so a
        // prefix catches the whole family without listing every one.
        static readonly List<string[]> Prefixes = new List<string[]>();

        static void A(string key, int id) { Map[key] = N + id; }
        static void P(string prefix, int id) { Prefixes.Add(new string[] { prefix, N + id }); }

        static Links()
        {
            // ---------------------------------------------------- interface
            A("SkyUI_SE", 12604);
            A("SkyHUD", 463);
            A("UIExtensions", 17561);
            A("TrueHUD", 62775);
            A("AHZmoreHUD", 12688);
            A("AHZmoreHUDPlugin", 12688);
            A("AHZmoreHUDInventory", 18619);
            A("InfinityUI", 74483);
            A("InventoryInjector", 85702);
            A("I4IconAddon", 85702);
            A("QuickLootIE", 120075);
            A("BetterContainerControls", 25271);
            A("BetterThirdPersonSelection", 64339);
            A("CompassNavigationOverhaul", 74484);
            A("LocalMapUpgrade", 129756);
            A("MapMarkerFramework", 56123);
            A("atlas map markers", 24104);
            A("IcePenguinWorldMap", 5804);
            A("MCMHelper", 53000);
            A("McmRecorder", 61719);
            A("SKSEMenuFramework", 120352);
            A("dmenu", 97221);
            A("StayAtSystemPageSE", 18397);
            A("YesImSure", 24898);
            A("SkyrimSoulsRE", 27859);
            A("SurvivalControlPanel", 41891);
            A("CraftingCategories", 81409);

            // ---------------------------------------------------- gameplay
            A("TrueDirectionalMovement", 51614);
            A("Precision", 72347);
            A("AnimationMotionRevolution", 50258);
            A("SimpleDualSheath", 50049);
            A("Apocalypse", 1090);
            A("Odin", 46000);
            A("Triumvirate", 39170);
            A("FishingInSkyrim", 47618);
            A("Gourmet", 96876);
            A("Skyrim Unbound", 27962);
            A("SkyrimUnbound", 27962);
            A("Guard Dialogue Overhaul", 22075);
            A("Immersive Patrols II", 718);

            // ---------------------------------------------------- gear
            A("Sentinel", 100985);
            A("MoreCraftableEquipment", 44666);
            A("Hothtrooper44_ArmorCompilation", 3479);
            A("Hothtrooper44_Armor_Ecksstra", 3479);
            A("Immersive Weapons", 16788);
            A("YokuWeapons", 150208);
            A("ZIA_Complete Pack", 9138);
            A("Cloaks&Capes", 2019);
            A("CommonClothes", 21305);
            A("Common Clothing Expanded", 134088);
            A("Mage Clothing Expansion", 128173);
            A("Kad_MoonMonkRobes", 82495);
            A("DIS_Heavy_Legion", 30468);
            A("evgnnsmpaccessories", 112481);

            // ---------------------------------------------------- character
            A("RaceMenu", 19080);
            A("RaceMenuPlugin", 19080);
            A("skee64", 19080);
            A("Expressive Facegen Morphs", 35785);
            A("KhisartinBeards", 122879);
            A("HammerHair", 156562);
            A("AwBaldandShavedHair", 101315);

            // ---------------------------------------------------- world
            A("JKs Whiterun", 2259);
            A("JK's Riverwood", 2013);
            A("JK's Whiterun's Outskirts", 78351);
            A("The Great Cities", 20272);
            A("The Great City of Solitude", 22243);
            A("WindhelmSSE", 42990);
            A("SkyrimSewers", 9320);
            A("Solitude Arena", 18692);
            A("Arena - Markarth Side", 114252);
            A("AnotherOakwood", 61007);
            A("aaaGraniteHill", 14658);
            A("OarsRest", 41812);
            A("ElysiumEstateSSE", 4119);
            A("Populated Cities Towns Villages Legendary", 2005);

            // ---------------------------------------------------- looks
            A("Embers XD", 37085);
            A("Water for ENB", 37061);
            A("Cathedral Weathers", 24791);
            A("HappyLittleTrees", 50961);
            A("DeadlySpellImpacts", 12939);
            A("Immersive Sounds - Compendium", 523);
            A("Immersive Sounds", 523);
            A("LSFX-SSE-Audiosettings", 1841);

            // ---------------------------------------------------- under the hood
            A("PapyrusUtil", 13048);
            A("po3_PapyrusExtender", 22854);
            A("po3_Tweaks", 51073);
            A("SkyPatcher", 106659);
            A("EngineFixes", 17230);
            A("SSEDisplayTweaks", 34705);
            A("CrashLogger", 59818);
            A("msdia140", 59818);
            A("ActorLimitFix", 32349);
            A("BarterLimitFix", 77173);
            A("AltTabFix", 148466);
            A("AnimationQueueFix", 82395);
            A("BugFixesSSE", 33261);
            A("MediaKeysFix", 92948);
            A("NativeEditorIDFix", 85260);
            A("PriorityMod", 50129);
            A("imgui-vr-helper", 183466);

            // ---------------------------------------------------- multiplayer
            Map["SkyrimTogether"] = "https://github.com/tiltedphoques/TiltedEvolution";
            A("SkyrimTogetherTweaks", 135782);
            A("MorphSyncTogether", 188240);
            A("TradeTogether", 188710);
            A("TradeTogetherMCM", 188710);
            A("STRPluginMessagingAPI", 188907);
            A("STRPluginMessagingBridge", 188907);

            // Patch and add-on plugins are named after their parent mod.
            P("Gourmet", 96876);
            P("Skyrim Unbound", 27962);
            P("Embers XD", 37085);
            P("Water for ENB", 37061);
            P("Sentinel", 100985);
            P("MoreCraftableEquipment", 44666);
            P("Hothtrooper44", 3479);
            P("KhisartinBeards", 122879);
            P("RaceMenu", 19080);
            P("TradeTogether", 188710);
            P("STRPluginMessaging", 188907);
            P("AHZmoreHUD", 12688);

            None["Skyrim"] = true;
            None["Update"] = true;
            None["Dawnguard"] = true;
            None["HearthFires"] = true;
            None["Dragonborn"] = true;
            None["_ResourcePack"] = true;
        }

        /// <summary>Strips the extension, any trailing bracketed note, and the surrounding space.</summary>
        static string Norm(string name)
        {
            if (name == null) return "";
            string k = name.Trim().TrimStart('*');
            string ext = Path.GetExtension(k).ToLowerInvariant();
            if (ext == ".esp" || ext == ".esm" || ext == ".esl" || ext == ".dll")
                k = k.Substring(0, k.Length - ext.Length);
            int par = k.IndexOf('(');
            if (par > 0) k = k.Substring(0, par);
            return k.Trim();
        }

        /// <summary>True for the Bethesda masters, Creation Club content, and the two private another server plugins.</summary>
        public static bool NoPage(string name)
        {
            string k = Norm(name);
            if (k.Length == 0) return true;
            if (None.ContainsKey(k)) return true;
            // ccBGSSSE001, ccQDRSSE002 and the rest of the Creation Club.
            if (k.Length > 8 && k.StartsWith("cc", StringComparison.OrdinalIgnoreCase)
                && k.Substring(5, 3).Equals("sse", StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }

        /// <summary>The mod's own page, or null when this build has no confirmed address for it.</summary>
        public static string Page(string name)
        {
            string k = Norm(name);
            if (k.Length == 0) return null;

            // "Embers XD - Patch - Gourmet Tables" narrows to "Embers XD - Patch",
            // then to "Embers XD", which is in the table.
            string probe = k;
            while (true)
            {
                string hit;
                if (Map.TryGetValue(probe, out hit)) return hit;
                int cut = probe.LastIndexOf(" - ", StringComparison.Ordinal);
                if (cut <= 0) break;
                probe = probe.Substring(0, cut).Trim();
            }

            foreach (string[] p in Prefixes)
                if (k.StartsWith(p[0], StringComparison.OrdinalIgnoreCase)) return p[1];

            return null;
        }

        /// <summary>Nexus search for the name, used when there is no confirmed page.</summary>
        public static string Search(string name)
        {
            string k = Norm(name);
            int cut = k.LastIndexOf(" - ", StringComparison.Ordinal);
            if (cut > 0) k = k.Substring(0, cut).Trim();
            return "https://www.nexusmods.com/skyrimspecialedition/search/?gsearch="
                 + Uri.EscapeDataString(k) + "&gsearchtype=mods";
        }

        /// <summary>Where a row should go when it is clicked, or null if it should not be clickable.</summary>
        public static string Target(string name)
        {
            if (NoPage(name)) return null;
            string p = Page(name);
            return p != null ? p : Search(name);
        }

        /// <summary>True when Target came from the table rather than falling back to a search.</summary>
        public static bool Exact(string name)
        {
            return !NoPage(name) && Page(name) != null;
        }
    }
}
