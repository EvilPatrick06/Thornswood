namespace Thornswood
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
            // ===================================================== joining
            new HelpItem("Joining", "1.  You pick your character at the game's main menu",
                "Press Play and Skyrim opens on its own menu with your characters listed, and New character under them. Name a new one after yourself: the multiplayer client reads the name off your character when you connect, and that is what everyone else sees floating above you. It is set when you create the character, so changing it later means starting a new one."),

            new HelpItem("Joining", "2.  Three choices and nothing else",
                "There is no cart ride and no Helgen. You wake in a shut room, the creation hall, with nothing in it but you and whoever else is being made that day. The appearance menu opens on its own: build your face and close it. A moment later the character panel opens on its own: your class, your profession and the half of it you will make your own, and the town you wake up in. Take them in any order and confirm each. The third one sends you to your inn, wearing the shift and carrying nothing. Nothing else is decided in the hall."),

            new HelpItem("Joining", "2a.  The world options are set for everyone",
                "Dragons, the main quest, the clock and the season belong to the server, not to you, so they are not on offer. What is yours to pick still is: one of five classes, one of eight professions, nine towns, and a face of your own."),

            new HelpItem("Joining", "2b.  If the panel does not appear",
                "Press K. That is the same panel you use for the rest of your character's life, for the skill tree, and the server reminds you in chat every half minute while the choices are still open. If K does nothing, the chat may have the keyboard: press Enter to close it and try again. A refusal from the server shows under the panel and in the chat, with the reason."),

            new HelpItem("Joining", "3.  You do not need to save first",
                "Skyrim Together would not accept a connection from an unsaved game and this one does not care. The client loads you into the world itself. Saving is still worth doing out of habit, but nothing here depends on it."),

            new HelpItem("Joining", "4.  It connects on its own",
                "The launcher writes the server address into the client settings before it starts the game, and the client connects on its own. You do not type an address, and there is no join screen to press anything on. There is a switch for it in Settings."),

            new HelpItem("Joining", "5.  Connecting by hand, if you have to",
                "There is no connect screen to open. The address lives in Data\\Platform\\Plugins\\skymp5-client-settings.txt, as server-ip and server-port, and the launcher rewrites both every time you press Play. If you need to point somewhere else, change it in Settings rather than in the file, or the next launch will put it back."),

            // ====================================================== emotes
new HelpItem("Emotes", "The wheel",
                "The key on the Controls page under Thornswood, B unless you have moved it, opens a wheel of twelve gestures: wave, applaud, salute, laugh, cheer, point, come here, pray, warm hands, examine, surrender, dance. Click one, or press 1 to 9 and 0. Tab turns to a second ring of working animations: drink, eat, lean, sweep, chop wood, write, read, flute, lute, drum, nervous, cough."),
new HelpItem("Emotes", "Everyone else sees them",
                "An emote you play is sent to everybody, the same way your movement is. They do not need to have picked the same thing, or to be looking at the wheel, or to have the wheel at all."),
new HelpItem("Emotes", "Getting out of one",
                "Some of them have no natural end, particularly the sitting and leaning ones. The stop key, N by default, breaks you out of whatever you are stuck in, and it works whether or not the wheel is open, because that is usually why you want it."),
new HelpItem("Emotes", "It will not open over a menu",
                "The wheel stays shut during loading screens, conversations, the appearance menu, and anything else the game is showing, and it closes itself if one of those opens while it is up. It also refuses to open while you are still in the creation room."),

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
                "Each profile tile has an Enable button underneath it. Press it and Vortex deploys that profile's mods and takes the other one's out. Close Skyrim first. Switching while the game is running is how you get a save that expects mods which are no longer there."),

            new HelpItem("The mods", "Play the right one",
                "The launcher checks. If the mods it can see do not match what the server has, it says so rather than letting you load in and get turned away at the door. Almost every time, the fix is that a different profile is enabled in Vortex."),

            new HelpItem("The mods", "Putting your Skyrim back to normal",
                "Purge Mods in Vortex, under the Mods page. It takes every deployed mod out and leaves the game as it was before Vortex touched it. Nothing is deleted: the mods stay in Vortex and go back with one press of Deploy. That is the answer to \"how do I undo all of this\", and it is worth knowing before you start rather than after."),

            new HelpItem("The mods", "Removing Thornswood without losing the mods",
                "Uninstall in Settings has a box for it. Leave it unticked and the mods stay where they are, so another server that wants the same ones does not cost you the download again. The mods belong to Vortex either way, and Vortex is where they go from."),

            // ================================================ starting out
            new HelpItem("Starting out", "Pick the city, the trade decides the rest",
                "Where you wake up and what you do for a living are two separate choices and they do not constrain each other. Any of the nine hold capitals is open to every trade, and Raven Rock as well. You are asked the trade first and the place second, and you arrive the moment you have answered both."),

            new HelpItem("Starting out", "What everyone gets, whatever they do",
                "A full waterskin and two bottles of water, a torch, a meal or two, something to drink, and two minor potions. Fifty to a hundred and fifty gold. Nobody starts with a bounty, nobody starts with a standing stone, and nobody starts as a werewolf or a vampire unless they go looking."),

            new HelpItem("Starting out", "Everyone starts poor except one",
                "Everybody begins on the poor purse: fifty to a hundred and fifty gold, cheap food, cheap drink. Nobody is meant to start comfortable, and nothing you pick at the start changes that."),

            new HelpItem("Starting out", "Profession and class are two choices, not one",
                "You pick both, and they do not overlap. The profession, and which half of it, decides what you are able to make: an Edgewright cannot make armour however long they have been at it. The class decides where raw material comes from: only a Hunter loots an animal, only a Miner mines. So a Smith who took Miner digs their own ore, and a Smith who took Hunter has to know somebody who did. Neither one locks a skill or a perk. What they decide is what you can make and where the material for it comes from."),

            new HelpItem("Starting out", "Alchemist",
                "Robed and stocked. The one trade that starts able to brew something worth selling.  Monk robes and boots, an iron dagger.  50 to 150 gold.  Carried: Blue Mountain Flower x3, Red Mountain Flower x3, Purple Mountain Flower x2, Lavender x3, Deathbell x2, Nirnroot x2, Thistle Branch x3, Snowberries x3, Elves Ear x3, Juniper Berries x3, Tundra Cotton x3, Frost Mirriam x2, Salt Pile x5, Alchemy skill book, Alchemy skill book II, Potion of Minor Healing x2, Potion of Minor Magicka x2, Potion of Minor Stamina x2, Potion of Cure Disease.  Plus what everyone gets: a full waterskin, two bottles of water, a torch, a meal or two and something to drink, and two minor potions."),

            new HelpItem("Starting out", "Bard",
                "Fine clothes and an instrument you can actually play. Poor in coin, rich in welcome.  Fine clothes and boots, an iron dagger.  50 to 150 gold.  Carried: Flute, Speech skill book, Apple x3.  Plus what everyone gets: a full waterskin, two bottles of water, a torch, a meal or two and something to drink, and two minor potions.  The flute is a real instrument rather than a prop. Equip it the way you would a weapon, and A, S, D, F and the arrow keys each play a note. Lutes and drums work the same way and can be forged from the ordinary ones at any blacksmith. The keys can be changed in the instrument menu in the MCM. You will always hear your own playing; whether the rest of the table hears it depends on how Together carries sound, so do not plan a duet around it."),

            new HelpItem("Starting out", "Cook",
                "A full larder and three recipes. Nobody else starts able to feed a party.  Merchant's clothes and boots, an iron dagger.  50 to 150 gold.  Carried: Raw Beef x2, Raw Venison x2, Raw Chicken Breast x2, Salmon Steak x2, Raw Goat Leg x2, Raw Rabbit Leg x2, Leek x3, Potato x3, Cabbage x2, Carrot x3, Cheese Wedge x2, Bread x2, Garlic x3, Salt Pile x5, Wheat x3, Apple x3, Recipe: Beef Stew, Recipe: Cabbage Soup, Recipe: Bread Loaf.  Plus what everyone gets: a full waterskin, two bottles of water, a torch, a meal or two and something to drink, and two minor potions."),

            new HelpItem("Starting out", "Enchanter",
                "Gems full and empty, and the scrolls to fill the rest.  College robes and boots, an iron dagger.  50 to 150 gold.  Carried: Petty Soul Gem, filled x3, Lesser Soul Gem, filled x2, Common Soul Gem, filled, Petty Soul Gem x3, Lesser Soul Gem x2, Common Soul Gem, Greater Soul Gem, Scroll of Soul Trap x2, Enchanting skill book, Enchanting skill book II.  Plus what everyone gets: a full waterskin, two bottles of water, a torch, a meal or two and something to drink, and two minor potions."),

            new HelpItem("Starting out", "Farmer",
                "Tools and seed crops. The quiet start, and the one with the most to build on.  Farm clothes and boots, an iron mace, a woodcutter's axe.  50 to 150 gold.  Carried: Pitchfork, Shovel, Wheat x3, Potato x3, Cabbage x2, Carrot x3, Leek x3.  Plus what everyone gets: a full waterskin, two bottles of water, a torch, a meal or two and something to drink, and two minor potions."),

            new HelpItem("Starting out", "Fisher",
                "Pole, net and filet kit. Water and food solve themselves.  Farm clothes and boots, an iron dagger.  50 to 150 gold.  Carried: Fishing Pole, Fishing Net, Filet Kit, Salmon Steak x2, Salt Pile x5.  Plus what everyone gets: a full waterskin, two bottles of water, a torch, a meal or two and something to drink, and two minor potions."),

            new HelpItem("Starting out", "Hunter",
                "The only trade that starts able to kill at range.  Hunter's leathers, light armour, an iron war axe, a hunting bow with arrows, a woodcutter's axe.  50 to 150 gold.  Carried: Archery skill book, Deer Hide, Wolf Pelt, Raw Venison x2.  Plus what everyone gets: a full waterskin, two bottles of water, a torch, a meal or two and something to drink, and two minor potions."),

            new HelpItem("Starting out", "Merchant",
                "The one purse a tier above everyone else. Starts able to buy rather than scavenge.  Merchant's clothes and boots, an iron dagger.  150 to 400 gold.  Carried: Large coin purse, Small coin purse, Blank book x2, Speech skill book, Cheese Wedge x2.  Plus what everyone gets: a full waterskin, two bottles of water, a torch, up to three meals and up to three drinks, and two or three minor potions."),

            new HelpItem("Starting out", "Miner",
                "A pickaxe and the first load already out of the rock.  Miner's clothes and boots, an iron mace, a pickaxe.  50 to 150 gold.  Carried: Iron Ore x3, Corundum Ore, Iron Ingot x3, Bread x2.  Plus what everyone gets: a full waterskin, two bottles of water, a torch, a meal or two and something to drink, and two minor potions."),

            new HelpItem("Starting out", "Priest",
                "The only trade that starts with a spell: Restoration, and the scrolls to cover what it cannot.  Monk robes and boots, an iron mace.  50 to 150 gold.  Carried: Restoration skill book, Scroll of Turn Undead x2, Scroll of Fast Healing x2, Potion of Cure Disease, Lavender x3.  Plus what everyone gets: a full waterskin, two bottles of water, a torch, a meal or two and something to drink, and two minor potions."),

            new HelpItem("Starting out", "Scholar",
                "Blank books, scrolls and three skill books. Starts knowing things rather than owning them.  Fine clothes and boots, an iron dagger.  50 to 150 gold.  Carried: Blank book x2, Scroll of Candlelight x2, Scroll of Magelight x2, Alchemy skill book, Enchanting skill book, Alteration skill book.  Plus what everyone gets: a full waterskin, two bottles of water, a torch, a meal or two and something to drink, and two minor potions."),

            new HelpItem("Starting out", "Smith",
                "Ingots, leather and ore. Starts able to make a weapon rather than carry one.  Farm clothes and boots, an iron mace, a pickaxe.  50 to 150 gold.  Carried: Smithing skill book, Iron Ingot x3, Steel Ingot, Leather Strips x5, Leather x2, Iron Ore x3.  Plus what everyone gets: a full waterskin, two bottles of water, a torch, a meal or two and something to drink, and two minor potions."),

            new HelpItem("Starting out", "Thief",
                "Light armour, eight picks and the three books that matter.  Leather armour, light, an iron dagger.  50 to 150 gold.  Carried: Lockpick x8, Small coin purse, Lockpicking skill book, Sneak skill book, Pickpocket skill book.  Plus what everyone gets: a full waterskin, two bottles of water, a torch, a meal or two and something to drink, and two minor potions."),

            new HelpItem("Starting out", "Warrior",
                "The only trade in heavy armour with a shield on the arm.  Steel armour, heavy, a steel sword and a shield.  50 to 150 gold.  Carried: One-Handed skill book, Block skill book, Heavy Armor skill book, Beef Stew, Potion of Minor Healing x2.  Plus what everyone gets: a full waterskin, two bottles of water, a torch, a meal or two and something to drink, and two minor potions."),

            new HelpItem("Starting out", "Woodworker",
                "The two handed start. A battleaxe, firewood and the makings.  Farm clothes and boots, an iron battleaxe, held two handed, a woodcutter's axe.  50 to 150 gold.  Carried: Firewood x5, Charcoal x2, Leather Strips x5, Bread x2.  Plus what everyone gets: a full waterskin, two bottles of water, a torch, a meal or two and something to drink, and two minor potions."),

            // ===================================================== parties
            new HelpItem("Playing together", "There is no party system",
                "Skyrim Together had parties, a leader, and teleporting to each other. SkyMP does not, and this build's gamemode adds none of it. There is nobody to invite and no leader to hand over: everyone connected is simply in the same world. Meet up by walking, or by starting in the same hold."),

            new HelpItem("Playing together", "Quests are the rough edge",
                "Quest state is per person here, so two people running the same quest are each running their own copy of it. Expect dialogue and stages to disagree. That is what the layer does today rather than a bug worth reporting. Treat quests as something you do alone and the shared world as the thing you do together."),

            // ===================================================== in game
            new HelpItem("In game", "Sleeping and waiting do nothing",
                "Time is shared across the server, so nobody can skip ahead alone. Plan around it, especially for anything that wants a particular time of day. There is no command to set the clock: it runs at the server's pace for everybody."),

            new HelpItem("In game", "Menus do not pause the world",
                "Inventory, favourites, crafting and the map all keep the world running. Do not sort your bags mid fight."),

            // The needs run on the server now. This used to send people to the
            // SunHelm MCM, which left the collection with SunHelm (To Do List
            // entry 133), and to promise that a bedroll or a hot drink warms
            // you, which nothing on the server counts. What it names instead
            // is what is there: the four bars hudScript in gamemode.js draws
            // bottom left, /needs, and the fire, roof and clothes the
            // temperature is worked out from. tools\test-sunhelm-gone.js
            // checks each of those against the gamemode.
            new HelpItem("In game", "You will get hungry, thirsty and cold",
                "Eat, drink, rest and stay warm. Cold bites hardest in the north, up high and at night. A fire warms you and standing in one burns you, a roof keeps the weather off, and what you wear counts: fur is the warmest thing there is and metal the worst. The four bars in the bottom left corner are Hunger, Thirst, Rest and Temp, and /needs gives the numbers and says where your warmth is heading."),

            new HelpItem("In game", "What dying costs you",
                "You keep everything you were carrying. Nothing is taken off your body and nobody loots you, whatever the mod's own defaults said: those are set to zero in this build. What you do lose is up to two fifths of the gold on you, a quarter of your progress toward the next level, and a quarter of your progress in whatever skills you were part way through. You wake up at the nearest temple. It is meant to sting rather than set you back a night."),

            new HelpItem("In game", "Talking to people",
                "Proximity voice runs in the launcher rather than in the game, so whoever is near you hears you and nobody else does. There is no text chat box, because the client is compiled without the overlay both would live in. For anything out of character there is a command: type /ooc and then what you meant to say. It reaches whoever is standing near you, comes out in brackets with your name on it, and /ooc can we not ends any scene immediately with no explanation owed."),

            new HelpItem("In game", "Where your saves are",
                "C:\\Thornswood\\Profile\\MyGames\\Saves, deliberately separate from your other Skyrim saves so nothing here can overwrite another playthrough. Settings, Folders, Open saves takes you straight there."),

            // ===================================================== breakage
            new HelpItem("If it breaks", "\"Could not connect to the specified server\"",
                "Nine times out of ten the port is missing. The address has to be 192.135.119.166:25565 in full. If it is already right, check the launcher says the server is responding, and that Steam is running."),

            new HelpItem("If it breaks", "\"The password you entered is incorrect\"",
                "The build carries the password, so this usually means yours is out of date. Take the update the launcher is offering and it fixes itself. Settings shows the one your copy is using, and it is case sensitive if you are typing it in by hand."),

            new HelpItem("If it breaks", "The server refuses you over mods",
                "Your plugin list does not match. Open Mods in the launcher and press Scan, which names exactly which plugin is extra, missing or out of order, then Fix. Restart the game afterwards, the list is read at startup."),

            new HelpItem("If it breaks", "The launcher will not let you press Play",
                "Same cause, caught earlier. The Mod list row on the Play page has gone red because your plugins no longer match what this build shipped with, and joining like that desyncs everyone. Mods, Scan, Fix. It re-checks the moment you press Play, so nothing slips through."),

            new HelpItem("If it breaks", "The game will not start",
                "Check the Play page first. A red row is the actual problem and the usual one is Steam not running, because the game still verifies ownership through it."),

            new HelpItem("If it breaks", "A pink error box on startup",
                "A script extender plugin failed to load and named itself in the title bar. Usually a file went missing or got overwritten. Mods, Scan, then Fix."),

            new HelpItem("If it breaks", "You crash in the same place every time",
                "Note where, then send it on. Crash logs are written under Profile, MyGames, SKSE in this build's own folder, and the newest crash file is the one worth sending."),

            new HelpItem("If it breaks", "Something says Skyrim is open and it is not on screen",
                "It is not wrong, and there is nothing to find. Skyrim does not always exit when the window goes away, and the multiplayer client leaves browser helper processes behind more often than not. They keep running with no window at all. The launcher clears those when it starts and again when you press Play, and the installer does the same before it unpacks, so this should sort itself out. If something still says it after a restart of the launcher, restart the PC."),

            new HelpItem("If it breaks", "You connect but nobody moves",
                "Usually one person's connection rather than the server. The Server page shows the round trip and whether the server is actually serving, which tells you which end to blame. If it is only you, restart the game before restarting anything else."),

            new HelpItem("If it breaks", "Your settings look wrong",
                "Settings, Repair. It puts the game settings and load order back to exactly what shipped, without touching your saves."),

            new HelpItem("If it breaks", "Updates stopped arriving",
                "Updates come from a public feed and need no key on your machine, so there is nothing here that can expire. If the launcher says the access token was refused it is running a build from before that changed: take the newest installer from thornswood.net and it sorts itself. Anything else means the feed itself is not answering, which is not your end."),

            // ===================================================== tips
            new HelpItem("Tips", "A few settings are held in place for you",
                "Some of these mods rewrite their own settings file when Skyrim closes, which is how a fix can appear to undo itself overnight. The launcher writes those back every time you press Play. It is a short list, only the ones that cause real faults: the favourites menu, and the Tab menu staying paused. Everything else is yours."),

            new HelpItem("Tips", "Every key this adds is on the Controls page, and most of them change from there",
                "Talking, the emote wheel, the overlay, mod settings, locking on, the inventory search box and the favourites groups. Press Change, press the key you want, done. Close Skyrim first, because these mods write their own settings files back when the game exits and would undo it. That page is built from the files themselves at the moment you open it, so a mod that is no longer in the build has no rows on it and nothing there can be out of date."),

            new HelpItem("Tips", "Add your own textures, never your own plugins",
                "Mods, Your own. Anything in that folder is copied into the game every time you press Play. Textures, meshes, sounds and music are invisible to the server. A plugin is not, and the launcher will stop you before you get refused."),

            new HelpItem("Tips", "Every mod in the list links to where it came from",
                "Mods. Click any row and its page opens in your browser, so you can read what a mod actually does, or find its own settings and requirements. Server plugins and script extender plugins go to the mod page. Your own files open in Explorer instead. A handful of rows have no page, because the Bethesda masters are the game itself."),

            new HelpItem("Tips", "Do not verify Skyrim in Steam",
                "It drags your Steam copy up to the current version and puts the Creation Club files back. It cannot touch this folder, since Steam does not know it exists, but there is no reason to build the habit."),

            new HelpItem("Tips", "Take updates when they are offered",
                "When the mod list changes you get only the files that changed, not the whole build again, verified by checksum before anything is written. Lists that do not match cannot play together, so there is no upside to putting it off."),

            new HelpItem("If it breaks", "You loaded into single player with no character creation",
                "A long wait, a black screen, and then you are standing in Skyrim on your own with no menus and nobody else about. That is not a crash. Nothing was answering at the server address, so nothing ever created a character for you. The launcher checks before it starts the game now and says so rather than letting you find out twenty minutes in. If the server runs on your own machine, press Play and it starts it for you."),

            new HelpItem("If it breaks", "You keep getting yesterday's character",
                "Your character is not a save file here. It lives on the server, and which one you get is decided by what you pick at the game's main menu, so loading a save from Skyrim's own load menu hands you the same body, the same inventory and the same face back. A genuinely new character is New character on that menu, and creation runs from the top.")
        };
    }
}
