namespace Thornswood
{
    class HelpItem
    {
        public string Section, Title, Body;
        public HelpItem(string s, string t, string b) { Section = s; Title = t; Body = b; }
    }

    /*
      THE HELP PAGE, REBUILT FROM WHAT THIS BUILD DOES.

      From the To Do List, entry 164: "The launcher Help page is the old
      project's help page with edits: a dead address, a password box that does
      not exist, and an explanation of parties." And what to do about it:
      "Delete every entry that starts from the old engine."

      What was here on 24 September, read against the code rather than
      remembered: an address and a password error from the old engine's join
      screen, which this client does not have; "There is no party system" while
      /party ran in the gamemode; "There is no text chat box" while Enter opened
      one; sixteen starting kits and "50 to 150 gold" four days after the kits
      went and the purse became forty gold, once; the SunHelm MCM with SunHelm
      out of the load order; a flute played on A, S, D and F; a death penalty
      from Respawn, which is out as well; twelve gestures on a wheel that has
      six groups; a Settings switch and address box that Settings no longer
      has; and "If it breaks" printed twice, because the page draws a heading
      every time the section changes and two items had been added after Tips.

      Every sentence below traces to the code that does the thing, and
      tools/test-launcher-help.js reads those same files: the command words
      against the gamemode's list, the emote groups against the wheel, the
      voice and /ooc ranges against the numbers that set them, the classes,
      professions and towns against the tables. When one of those changes and
      this page does not, that harness fails.

      The site's help.md and known.md were the sources the entry named, and
      they were not safe ones: both still said the launcher asks for the
      profession, the half, the class and the town, which stopped being true on
      20 September. Where they agree with the code, the wording follows them.

      No server address is written here, and none should be. It arrives with
      the update (OnVersionDoc in Shell.cs), so moving the server needs no
      reinstall and no edit to this page.
    */
    static class Help
    {
        public static readonly HelpItem[] Items = new HelpItem[]
        {
            // ===================================================== joining
            new HelpItem("Joining", "Open Thornswood, not Skyrim",
                "Start from the Thornswood shortcut every time: not Skyrim, not Steam, not SKSE. The launcher takes any update that is waiting, compares every plugin with the server's copy, and Play starts the game and connects you. An update that is waiting is taken before Play is allowed, because everybody has to be running the same files or nobody can connect."),

            new HelpItem("Joining", "Connect Discord once",
                "Press Connect Discord on the Play page. Your browser opens, you say yes, and it closes itself. Your Discord account is what lets you in: the launcher asks the site about it when you press Play, and the game does not start without it."),

            new HelpItem("Joining", "There is nothing to type",
                "No address, no password and no join screen. The server's address arrives with the launcher's updates, and the launcher writes it into the game's settings every time you press Play, so the game connects on its own. If the server ever moves, the next update carries the new address and nothing has to be reinstalled."),

            // =================================================== character
            new HelpItem("Character", "You pick your character at the game's main menu",
                "When the game loads it lists your characters, with an empty slot for a new one. Click a character and you go straight in as them. Click an empty slot to make a new one. A character lives on the server, not in a save file: what you carry, what you wear and where you stand are handed back when you connect, so there is nothing to save first and quitting is safe."),

            new HelpItem("Character", "A name that belongs in Skyrim",
                "You name your character when you make its face, and that name is what everybody else sees above your head. Give it a first name and a family name or a byname that would not look out of place in Skyrim, not your own name. It cannot be changed afterwards without making a new character."),

            new HelpItem("Character", "The creation hall",
                "A new character wakes in a shut room with nothing in it, and the appearance menu opens on its own: make your face and close it. The character panel then opens on its own. Choose the town you will wake up in and you are sent to its inn, in a plain shift. Your class and your profession are on the same panel, and can be chosen there or later in the world. Nothing else is decided in the hall."),

            new HelpItem("Character", "Where you wake up",
                "Whiterun, Riften, Solitude, Windhelm, Markarth, Falkreath, Morthal, Dawnstar or Winterhold, each at its inn. The town is the choice that ends creation, and it cannot be changed afterwards, so choose your class and profession first if you want them settled before you arrive."),

            new HelpItem("Character", "What you start with",
                "The shift you stand in, and 40 gold, once. Weapons, armour, arrows, tools and coin do not come out of chests or up off the ground here: they come from other people, who make them or pay them to you. The tool your work needs is handed to you as well, below."),

            new HelpItem("Character", "Profession and class are two choices, not one",
                "The profession, and which half of it you work, decides what you are able to make. The eight are Warrior, Mage, Alchemist, Cook, Smith, Enchanter, Tailor and Woodworker. An Edgewright makes weapons, and gets the novice work of the other half, armour, for nothing and no further. A Mage picks two schools of magic instead of a half. The class decides where raw material comes from: only a Hunter loots an animal, only a Fisher fishes, only a Gatherer gathers, only a Miner mines and only a Farmer farms. So a Smith who took Miner digs their own ore, and a Smith who took Hunter has to know somebody who did. You get one of each, for the life of the character."),

            new HelpItem("Character", "The tools come with the pick",
                "A Miner is handed a pickaxe, a Farmer a shovel and a few crops to sow, and a Woodworker a woodcutter's axe, the moment they choose. In the pack is enough; nothing has to be equipped. A tool wears out with use, and a smith forges the next one. If you have none at all, the seam, the plot or the kiln hands you one, no more often than once every 12 hours."),

            new HelpItem("Character", "K is your character",
                "K opens your profession, your class, the recipe book and the skill tree, for the rest of your character's life. The recipe book says what your half can make at the rank you have reached. The skill tree is fifteen sub-skills under Health, Magicka and Stamina. Skyrim's own levelling is switched off: rank comes from doing the work of your trade, and nothing else moves it. The panel does not pause the world."),

            new HelpItem("Character", "If the panel does not appear",
                "Press K. While your town is still to choose, the server puts the panel back on your screen every 30 seconds, and only says so in the chat if it could not. Closing it on purpose is fine: nothing is chosen, and it waits 10 minutes before it comes back by itself. If K does nothing, the chat may have the keyboard: press Escape and try again. A refusal shows on the panel and in the chat, with the reason."),

            // =========================================== chat and commands
            new HelpItem("Chat and commands", "The chat box",
                "Enter opens it and Escape gives the keyboard back to the game. A line typed there goes to everybody connected, wherever they are in Skyrim, so treat it as the whole server rather than the room. A line that starts with a slash is a command for the server and is not shown to anybody else. Text chat is kept, with the name and the time. Voice is not recorded."),

            new HelpItem("Chat and commands", "Out of character",
                "Type /ooc and then what you meant. It goes only to people in the same place as you and within about 60 metres, in double brackets with your name on it, so nobody wonders whether your character said it. If nobody is near enough to hear it, the server tells you. /ooc can we not ends any scene at once, from anybody in it, with no reason owed."),

            new HelpItem("Chat and commands", "Dice",
                "/roll 20 rolls one twenty sided die, and /roll 6x3 rolls three six sided ones. The server rolls it, so nobody can make a number up, and the same people /ooc reaches see the result. Up to 1000 sides and 100 dice."),

            new HelpItem("Chat and commands", "Voice",
                "Hold V to talk. Voice runs in the launcher rather than in the game, so leave the launcher open while you play; it minimises by itself. B steps your voice between a whisper, which carries about 7 metres, your normal voice, about 30 metres, and a yell, about 85 metres. The further away somebody is standing, the quieter you are to them."),

            new HelpItem("Chat and commands", "Friends, parties and trading",
                "Look at somebody and press G to ask them to be friends, H to offer a trade, or L to stop hearing them. Those three only work with somebody under your crosshair. P opens your friends and your party: Ask to party is beside every friend who is online, or type /party and their name, and /party leave to go. Everybody in your party has their name in green, a marker on your map and an arrow on the strip under your compass. Work done with your party in the same place counts for more. /yes and /no answer whatever somebody has asked you. Friends are kept; a party lasts until the server restarts."),

            new HelpItem("Chat and commands", "Journals",
                "J opens your journals and their pages. You can share a whole journal, or one page of it, with a friend."),

            new HelpItem("Chat and commands", "Everything else is on /help",
                "Type /help in the chat for a short menu, then /help talking, /help people, /help living, /help work, /help land or /help staff for one topic each. A word the server does not know is answered with the list of words it does."),

            new HelpItem("Chat and commands", "The console is switched off",
                "Skyrim's console opens for a moment and shuts again, with a line in the chat saying so. It is the same rule for everybody, and the rules page says why."),

            // ====================================================== emotes
            new HelpItem("Emotes", "The wheel",
                "The emote wheel key on the Controls page opens a wheel of six groups: Greeting, Praise, Gesture, Devotion, Labour and Revelry, 34 emotes between them. Click a group or press its number, then click an emote or press its number. Tab moves to the next group, and Escape or the middle of the wheel steps back out."),
            new HelpItem("Emotes", "Everyone else sees them",
                "An emote you play is sent to everybody, the same way your movement is. They do not need to have picked the same thing, or to be looking at the wheel, or to have the wheel at all."),
            new HelpItem("Emotes", "Getting out of one",
                "Some of them have no natural end, particularly the kneeling and leaning ones. N stands you up out of whatever you are stuck in, and lowers hands that are stuck with a weapon drawn. With the wheel open on its groups, the middle of it stands you up as well."),
            new HelpItem("Emotes", "It will not open over a menu",
                "The wheel stays shut during loading screens, conversations, the appearance menu, and anything else the game is showing, and it closes itself if one of those opens while it is up. It also refuses to open while you are still in the creation hall."),

            // ================================================== the mods
            new HelpItem("The mods", "Where they come from",
                "Thornswood's mods are not in the installer. They come from a collection on Nexus, which Vortex downloads and installs for you. That is why the download is small, why a mod update does not mean reinstalling everything, and why the mods are the real ones from their own authors rather than copies."),

            new HelpItem("The mods", "Installing the collection makes its own profile",
                "You do not have to make one by hand. Vortex installs a collection into a profile of its own and switches to it, so your existing Skyrim setup is left as it was. If you have never used profiles, that is the moment they appear."),

            new HelpItem("The mods", "If you do not see Profiles in Vortex",
                "They are hidden until you turn them on. Settings, then Interface, then the Profiles switch. A Profiles entry appears in the list down the left side. Nothing about your mods changes when you turn it on."),

            new HelpItem("The mods", "Making a profile for your own Skyrim",
                "On the Profiles page, the button under the tiles makes a new one. Give it a name you will recognise, and tick both boxes: this profile has its own save games, and this profile has its own game settings. Those two are what keep Thornswood's saves and inis from mixing with your own. The icon in the bottom right of a tile copies the enabled mod list from one profile to another, which is the quick way to build a profile that matches what you already had."),

            new HelpItem("The mods", "Switching between them",
                "Each profile tile has an Enable button underneath it. Press it and Vortex deploys that profile's mods and takes the other one's out. Close Skyrim first. Thornswood runs from a game folder of its own, built from what Vortex deployed while the Thornswood profile was on, so switching to your own profile afterwards takes nothing away from it. Switch back when the collection updates, and the launcher brings the new version in the next time it starts."),

            new HelpItem("The mods", "Play the right one",
                "The launcher checks. If the mods it can see do not match what the server has, it says so rather than letting you load in and get turned away at the door. Almost every time, the fix is that a different profile is enabled in Vortex."),

            new HelpItem("The mods", "Putting your Skyrim back to normal",
                "Purge Mods in Vortex, under the Mods page. It takes every deployed mod out and leaves the game as it was before Vortex touched it. Nothing is deleted: the mods stay in Vortex and go back with one press of Deploy. That is the answer to \"how do I undo all of this\", and it is worth knowing before you start rather than after."),

            new HelpItem("The mods", "Removing Thornswood without losing the mods",
                "Uninstall in Settings never touches the mods: they belong to Vortex, and taking them off is Purge in Vortex. The box under it decides whether Thornswood's own game folder goes as well. Untick it and the folder stays, so a reinstall picks it up again instead of building it from Vortex."),

            // ===================================================== in game
            new HelpItem("In game", "Sleeping and waiting do nothing",
                "Time is shared across the server, so nobody can skip ahead alone. Plan around it, especially for anything that wants a particular time of day. There is no command to set the clock: it runs at the server's pace for everybody."),

            new HelpItem("In game", "Menus do not pause the world",
                "Inventory, favourites, crafting and the map all keep the world running. Do not sort your bags mid fight."),

            new HelpItem("In game", "Food, water, rest and warmth",
                "Four bars: food, water, rest and how warm you are. /eat and /drink when you have something, /rest sit, /rest campfire, /rest inn or /rest bed, and /rest up to get going again. /needs says where each one stands and why. Fires warm you and standing in one burns you. What you are wearing matters: fur is the warmest thing there is and metal is the worst."),

            new HelpItem("In game", "When you die",
                "You wake at the temple of the hold you died in. A hold with no temple of its own sends you to the nearest temple or Hall of the Dead, and anywhere on Solstheim sends you to Raven Rock."),

            new HelpItem("In game", "Restarts and updates are announced",
                "A countdown in the chat and on screen comes first. A notice means the world freezes for a few seconds and your game does not close. For an update, your launcher closes the game when the count runs out, installs it and puts you back in, unless it already has it, in which case nothing happens to you. A restart means the server is going down: get somewhere safe and log out before then."),

            // ===================================================== breakage
            new HelpItem("If it breaks", "\"LOAD ORDER ERROR\"",
                "The game compares every plugin with the server's when you connect: the same names, in the same order, with the same bytes. One that differs turns you away with that message. Close the game, open Mods in the launcher and press Scan, which names the plugin that differs, then Fix, then Play again. Nothing in Vortex has to change. If Scan says a plugin is missing rather than different, the collection is not fully installed or the wrong Vortex profile is on, and the launcher says which."),

            new HelpItem("If it breaks", "The launcher will not let you press Play",
                "Same cause, caught earlier. The Mod list row on the Play page has gone red because your plugins no longer match what this build shipped with, and joining like that desyncs everyone. Mods, Scan, Fix. It re-checks the moment you press Play, so nothing slips through."),

            new HelpItem("If it breaks", "The game will not start",
                "Check the Play page first. A red row is the actual problem and the usual one is Steam not running, because the game still verifies ownership through it."),

            new HelpItem("If it breaks", "You loaded into Skyrim alone, with no character creation",
                "A long wait, a black screen, and then you are standing in Skyrim on your own with no menus and nobody else about. That is not a crash. Nothing was answering at the server's address, so nothing ever made a character for you. The launcher checks before it starts the game and says so when the server is not answering, and the Server page shows whether it is back."),

            new HelpItem("If it breaks", "A pink error box on startup",
                "A script extender plugin failed to load and named itself in the title bar. Usually a file went missing or got overwritten. Mods, Scan, then Fix."),

            new HelpItem("If it breaks", "The game closed itself",
                "Send the crash log. The Logs page lists them, and Copy newest puts the most recent one on your clipboard, ready to paste into Discord. Diagnostics packs it up with everything else worth having in one file. If it happens in the same place every time, say where."),

            new HelpItem("If it breaks", "Something says Skyrim is open and it is not on screen",
                "It is not wrong, and there is nothing to find. Skyrim does not always exit when the window goes away, and the game's own browser leaves helper processes behind more often than not. They keep running with no window at all. The launcher clears those when it starts and again when you press Play, and the installer does the same before it unpacks, so this should sort itself out. If something still says it after a restart of the launcher, restart the PC."),

            new HelpItem("If it breaks", "You connect but nobody moves",
                "Usually one person's connection rather than the server. The Server page shows the round trip and whether the server is actually serving, which tells you which end to blame. If it is only you, restart the game before restarting anything else."),

            new HelpItem("If it breaks", "The chat, the wheel and the panels have gone",
                "F2 hides everything the game's overlay draws, and pressing it again brings it all back. The key belongs to the game client and cannot be moved."),

            new HelpItem("If it breaks", "The names over people's heads have gone",
                "F1 turns them off and on again. Like F2, it belongs to the game client and cannot be moved."),

            new HelpItem("If it breaks", "Your settings look wrong",
                "Settings, Repair, with Skyrim closed. It puts this build's own settings and load order back to exactly what shipped. Your character is not touched, because it lives on the server."),

            new HelpItem("If it breaks", "Updates stopped arriving",
                "Updates come from a public feed and need no key on your machine. If the launcher says too many update checks have come from your connection, that clears by itself, usually within the hour. If it says the access token was refused, take the newest installer from thornswood.net. Anything else means the feed itself is not answering, which is not your end."),

            new HelpItem("If it breaks", "You keep getting yesterday's character",
                "That is the one you clicked. Your character is not a save file here: it lives on the server, and which one you get is decided by what you pick at the game's main menu, so loading a save from Skyrim's own menu hands you the same body, the same pack and the same face back. A new character is an empty slot on that menu, and creation runs from the top."),

            // ===================================================== tips
            new HelpItem("Tips", "A few settings are held in place for you",
                "Some of these mods rewrite their own settings file when Skyrim closes, which is how a fix can appear to undo itself overnight. The launcher writes those back every time you press Play. It is a short list, only the ones that cause real faults: the favourites menu pausing the world, the Tab menu locking up, and two banners the animation replacer puts over the main menu. Everything else is yours."),

            new HelpItem("Tips", "The Controls page has the keys, and changes most of them",
                "The chat, the emote wheel, the K panel, friends, party and journals, voice, mod settings, locking on, the inventory search box and the favourites groups. Press Change, press the key you want, done. Close Skyrim first, because these mods write their own settings files back when the game exits and would undo it. That page is built from the files themselves at the moment you open it, so a mod that is no longer in the build has no rows on it and nothing there can be out of date."),

            new HelpItem("Tips", "Add your own textures, never your own plugins",
                "Mods, Your own. Anything in that folder is copied into the game every time you press Play. Textures, meshes, sounds and music are invisible to the server. A plugin is not, and the launcher will stop you before you get refused."),

            new HelpItem("Tips", "Every mod in the list links to where it came from",
                "Mods. Click any row and its page opens in your browser, so you can read what a mod actually does, or find its own settings and requirements. Server plugins and script extender plugins go to the mod page. Your own files open in Explorer instead. A handful of rows have no page, because the Bethesda masters are the game itself."),

            new HelpItem("Tips", "Do not verify Skyrim in Steam",
                "It moves your Steam copy to the newest Skyrim, which is not the build the server runs, and puts back the Creation Club files that throw the load order out. There is no reason to build the habit."),

            new HelpItem("Tips", "Updates bring only what changed",
                "When the mod list changes you get only the files that changed, not the whole build again, and each one is checked against its checksum before anything is written.")
        };
    }
}
