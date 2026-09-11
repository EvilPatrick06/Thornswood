namespace SkyrimTogether
{
    class HelpItem
    {
        public string Section, Title, Body;
        public HelpItem(string s, string t, string b) { Section = s; Title = t; Body = b; }
    }

    static class Help
    {
        public static readonly HelpItem[] Items = new HelpItem[]
        {
            // ----------------------------------------------------- controls
            new HelpItem("Controls", "F2   or   Right Ctrl",
                "Opens the Skyrim Together menu: party, the player list, teleport to a party member, and text chat. Remap it in Data\\SKSE\\Plugins\\SkyrimTogetherTweaks.ini."),
            new HelpItem("Controls", "F3",
                "Skyrim Together's connection and sync readout. Worth a look if movement gets choppy, ignore it otherwise. Same file to remap."),
            new HelpItem("Controls", "F1",
                "The mod settings menu. Minimap, TrueHUD, Precision and the other newer mods are configured here rather than in the old MCM. Remap it in Data\\SKSE\\Plugins\\SKSEMenuFramework.ini."),
            new HelpItem("Controls", "Esc,  Mod Configuration",
                "The classic SkyUI settings pages. SunHelm, True Directional Movement and Trade Together live here, and this is where their keys get rebound."),
            new HelpItem("Controls", "Middle mouse",
                "Lock on to whatever you are aiming at. Mouse wheel switches target while locked. Default from True Directional Movement, rebindable in its MCM page."),
            new HelpItem("Controls", "T",
                "Starts a trade with the player under your crosshair. They have 30 seconds to accept. Rebindable in the Trade Together MCM page."),
            new HelpItem("Controls", "Insert   /   Delete",
                "Inside a trade: put the selected item into your offer, or take it back out. Rebindable in the same MCM page."),
            new HelpItem("Controls", "Numpad +   /   Numpad -",
                "Inside a trade: add or remove gold."),
            new HelpItem("Controls", "Tab",
                "Cancels an open trade."),
            new HelpItem("Controls", "E   /   R  at a container",
                "Loot without opening anything. Your Activate key takes the highlighted item, R takes the lot. Rebindable in the QuickLoot MCM page."),

            // ----------------------------------------------------- if it breaks
            new HelpItem("If it breaks", "The game will not start",
                "Look at the Play page first. A red row is the actual cause and the usual one is Steam not running, because the game still checks ownership through it. If every row is green, open Mods and press Scan."),
            new HelpItem("If it breaks", "A pink error box on startup",
                "A script extender plugin failed to load and named itself in the title bar. That normally means a file went missing or got overwritten. Mods, Scan, then Fix."),
            new HelpItem("If it breaks", "The launcher will not let you press Play",
                "Your plugin list does not match what this build shipped with, and joining like that desyncs everyone, so it stops you rather than letting it happen. Open Mods, the card at the top names exactly what is wrong, and Fix puts the shipped list back. It re-checks the moment you press Play, so nothing can slip through in between."),
            new HelpItem("If it breaks", "The server refuses your connection",
                "Your plugin list does not match. Mods, Scan tells you exactly which plugin is extra, missing or out of order, and Fix puts the shipped list back. Restart the game afterwards, the list is read at startup."),
            new HelpItem("If it breaks", "You crash at the same place every time",
                "Note where, then send it on. Crash logs are written to this build's own folder, under Profile, MyGames, SKSE, and the newest crash file is the one worth sending."),
            new HelpItem("If it breaks", "You connect but nobody moves",
                "Usually one player's connection, not the server. Press F3 to see your latency. If it is only you, restart the game before restarting anything else."),
            new HelpItem("If it breaks", "Your settings look wrong",
                "Settings, Repair. It puts the game settings and load order back to exactly what shipped, without touching your saves."),

            // ----------------------------------------------------- in game
            new HelpItem("In game", "Sleeping and waiting do nothing",
                "Time is shared across the server, so no one can skip ahead on their own. Plan around it, especially for anything that wants a specific time of day."),
            new HelpItem("In game", "Menus do not pause the world",
                "Inventory, favourites, crafting and the map all keep the world running. Do not sort your bags mid fight."),
            new HelpItem("In game", "You will get hungry, thirsty and cold",
                "Eat, drink and stay warm. Cold hits hardest in the north and at night, and a fire, a bedroll or a warm drink all help. The needs display is configurable in the SunHelm MCM."),
            new HelpItem("In game", "Quests run off the party leader",
                "Party up before starting a quest and let one person lead it. Everyone running the same quest separately is the fastest way to break its progress."),
            new HelpItem("In game", "There is no voice chat",
                "Nothing in this build carries voice, and no working proximity voice mod exists for Skyrim Together. Use Discord. Text chat is in the F2 menu and reaches everyone on the server."),
            new HelpItem("In game", "Loot and containers",
                "Look at a container to see its contents without opening it. In a group, take turns on quest items, two people grabbing the same one at the same moment is the usual cause of a stuck quest."),

            // ----------------------------------------------------- tips
            new HelpItem("Tips", "Name your character after yourself",
                "It is read off your character when you connect and it is what everyone sees above your head. Changing it later means a new character."),
            new HelpItem("Tips", "Save before you connect",
                "Joining from an unsaved game drops you back to the menu. Make one save, then connect."),
            new HelpItem("Tips", "Teleport instead of walking",
                "F2, Party, then pick a player. It beats running across a hold to regroup."),
            new HelpItem("Tips", "Add your own textures, never your own plugins",
                "Mods, Your own. Anything you drop in that folder is copied in when you press Play. Textures, meshes, sounds and music are invisible to the server. A plugin is not, and will get you refused."),
            new HelpItem("Tips", "Do not verify Skyrim in Steam",
                "It drags your Steam copy up to the current version. It cannot hurt this folder, since Steam does not know it exists, but there is no reason to risk the habit."),
            new HelpItem("Tips", "Updates are small",
                "When the mod list changes you get only the files that changed, not the whole build again. Take them when the launcher offers, mismatched lists cannot connect to each other.")
        };
    }
}
