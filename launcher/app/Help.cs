namespace Thornswood
{
    class HelpItem
    {
        public string Section, Title, Body;
        public HelpItem(string s, string t, string b) { Section = s; Title = t; Body = b; }
    }

    /*
      THE HELP PAGE, WRITTEN FROM WHAT THIS BUILD DOES.

      Issue #418 (To Do List entry 164): "The launcher Help page is the old
      project's help page with edits: a dead address, a password box that does
      not exist, and an explanation of parties." The first rebuild (24 Sep)
      took out the old engine's address and password, the kits, SunHelm and the
      "no party system" line. The second (28 Sep) put in how people get in now
      (alpha, a ticket in the Discord, the Playtester role unlocks Play), the
      site's address, one list of the keys as a fresh install has them, /helpme
      and /report, where the logs are and how to send them, and what Fix does.
      It also took out every page this page used to send people to that the
      rail no longer shows (Logs, Server, Mods, Saves, What is installed: see
      hiddenNav in Shell.cs, #599), and the GitHub update token, which went
      with the Releases repository.

      Every sentence below traces to the code that does the thing, and
      tests/test-launcher-help.js reads those same files: the command words
      against the gamemode's list, the keys against Thornswood.ini and
      Keys.cs, the ranges against the numbers that set them, the classes,
      professions and towns against the tables, the join gate against the
      site. When one of those changes and this page does not, that harness
      fails. site/data/help.md says the same things for the site.

      No server address is written here, and none should be. It arrives with
      the update (OnVersionDoc in Shell.cs), so moving the server needs no
      reinstall and no edit to this page.
    */
    static class Help
    {
        public static readonly HelpItem[] Items = new HelpItem[]
        {
            // ===================================================== joining
            new HelpItem("Joining", "Thornswood is in alpha",
                "Anyone can install it, but Play stays locked until you have been let in. Come into the Discord, open a ticket and say a few lines about who you are. When you are accepted you are given the Playtester role, and that role is what unlocks Play. Thornswood is eighteen and over."),

            new HelpItem("Joining", "The site",
                "thornswood.net has the installer, the rules, the known issues and a copy of this help. Updates come from there too."),

            new HelpItem("Joining", "Open Thornswood, not Skyrim",
                "Start from the Thornswood shortcut every time: not Skyrim, not Steam, not SKSE. The launcher takes any update that is waiting, compares every plugin with the server's copy, and Play starts the game and connects you."),

            new HelpItem("Joining", "Connect Discord once",
                "Press Connect Discord on the Play page. Your browser opens, you say yes, and it closes itself. Every time you press Play the launcher asks the site whether your Discord account is let in. If it says your account has no role that lets it in yet, you have not been accepted yet: ask in your ticket."),

            new HelpItem("Joining", "There is nothing to type",
                "No address, no password and no join screen. The server's address arrives with the launcher's updates, and the launcher writes it into the game's settings every time you press Play, so the game connects on its own."),

            // The name rule is here, in the same words as the first-run card on
            // the Play page (entry 163), and test-first-run-words.js holds the
            // two to each other.
            new HelpItem("Joining", "You pick your character at the game's main menu",
                "When the game loads it lists your characters, with an empty slot for a new one. Click a character to go in as them, or an empty slot to make a new one. Give a new one a name that belongs in Skyrim: a first name and a family name or a byname, and not your own. That name is what everybody sees above your head, and changing it later means making a new character."),

            new HelpItem("Joining", "There is no saving",
                "The server holds your character, not a save file on your machine. What you carry, what you wear and where you stand are handed back when you connect, so there is nothing to save and nothing lost when you quit."),

            // =================================================== character
            new HelpItem("Character", "The creation hall",
                "A new character wakes in a shut room and the appearance menu opens on its own: make your face, give it its name, and close it. The character panel then opens. Choose the town you will start in and you are sent there, in a plain shift. Your class and profession are on the same panel, and can be chosen there or later in the world."),

            new HelpItem("Character", "Where you start",
                "Whiterun, Riften, Solitude, Windhelm, Markarth, Falkreath, Morthal, Dawnstar or Winterhold. You arrive at a quiet spot in or near the town, not in its inn: the stables at Whiterun, Solitude, Windhelm and Riften, and Understone Keep in Markarth. The town is the choice that ends creation, and it cannot be changed afterwards."),

            new HelpItem("Character", "What you start with",
                "The shift you stand in, and 40 gold, once. Weapons, armour, tools and coin come from other people, who make them or pay them to you."),

            new HelpItem("Character", "Profession and class are two choices, not one",
                "The profession, and which half of it you work, decides what you can make. The eight are Warrior, Mage, Alchemist, Cook, Smith, Enchanter, Tailor and Woodworker. The class decides where raw material comes from: only a Hunter loots an animal, only a Fisher fishes, only a Gatherer gathers, only a Miner mines and only a Farmer farms. You get one of each, for the life of the character."),

            new HelpItem("Character", "The tools come with the pick",
                "A Miner is handed a pickaxe, a Farmer a shovel and a few crops to sow, a Fisher a crude fishing pole, and a Woodworker a woodcutter's axe, the moment they choose. The bench trades get theirs the same way: a Smith a hammer, a Tailor a pair of shears, a Cook a wooden ladle, an Alchemist an alembic and an Enchanter a rune knife, and the bench turns away somebody without one. A tool wears out. When it breaks or is lost, a smith forges the next one, and a woodwright makes the next pole or ladle: nothing in the world hands one out. A smith with no hammer can forge their own."),

            new HelpItem("Character", "K is your character",
                "K opens your profession, your class, the recipe book and the skill tree. Skyrim's own levelling is off: rank comes from doing the work of your trade. The panel does not pause the world."),

            new HelpItem("Character", "If the panel does not appear",
                "Press K. While your town is still to choose, the server puts the panel back on your screen every 30 seconds, and only says so in the chat if it could not. Closed on purpose, it waits 10 minutes before it comes back by itself. If K does nothing, the chat may have the keyboard: press Escape and try again."),

            // ======================================================== keys
            // Every letter here is the one a fresh install has: the value in
            // launcher\Thornswood.ini, which Keys.cs falls back to as well.
            // test-launcher-help.js reads both and fails when one moves.
            new HelpItem("Keys", "The keys on a fresh install",
                "Enter opens the chat, and / opens it with the slash already typed. K is your character panel, P your friends and party, J your journals. Looking at somebody, Y asks them to be friends, H offers a trade and L stops you hearing them. Hold V to talk, O keeps the microphone open, and B steps between a whisper, your normal voice and a yell. G opens the emote wheel and N stands you up out of one. U presses a blank key mold into the lock of the door you are looking at. F7 opens the help in the game. F1 turns the names over heads off and on, and F2 hides and shows everything the game's overlay draws."),

            new HelpItem("Keys", "The Controls page changes them",
                "Controls in the launcher lists every key, read from the files themselves. Press Change, then the key you want. Close Skyrim first, because the game writes its settings back when it exits and would undo it. F1 and F2 belong to the game client and cannot be moved."),

            // =========================================== chat and commands
            // Local is how chat ships since 4 Oct: Install-Voice.ps1 sets
            // THORNSWOOD_CHAT_RANGE on (the same cell and 4000 units) for live
            // and dev. Whoever turns it off changes this item in the same
            // release; test-launcher-help.js ties the two together.
            new HelpItem("Chat and commands", "The chat box",
                "Enter opens it and Escape gives the keyboard back to the game. / opens it with the slash already typed, for the few lines still typed there, which this section names. A line typed there reaches the people near you, in the same place and within about 60 metres, the same as the line over your head, so treat it as the room rather than the whole server. A line that starts with a slash is a command for the server and is not shown to anybody else. Text chat is kept, with the name and the time. Voice is not recorded."),

            // How a line is said stays typed, with no buttons (Patrick,
            // 4 Oct, #1639), and the help names it. The voice service says
            // these itself; docs\systems\chat.md has the ranges.
            new HelpItem("Chat and commands", "How a line is said",
                "Start a line with /me and what your character does, or /do and what there is to see. /w whispers it to the people closest to you, and /s or /y shouts it further. /me draws a sword is an attempt: whether it lands is the other person's."),

            new HelpItem("Chat and commands", "Out of character",
                "Type /ooc and then what you meant. It goes only to people in the same place as you and within about 60 metres, in double brackets with your name on it. /ooc can we not ends any scene at once, from anybody in it, with no reason owed."),

            new HelpItem("Chat and commands", "Dice",
                "/roll 20 rolls one twenty sided die, and /roll 6x3 rolls three six sided ones. The server rolls it, and the same people /ooc reaches see the result. Up to 1000 sides and 100 dice."),

            new HelpItem("Chat and commands", "Voice",
                "Hold V to talk, or press O to keep the microphone open until you press O again, for a song or a long speech. Voice runs in the launcher rather than in the game, so leave the launcher open while you play; it minimises by itself. B steps your voice between a whisper, which carries about 7 metres, your normal voice, about 30 metres, and a yell, about 85 metres. The further away somebody is standing, the quieter you are to them. If nobody can hear you, check that the launcher is still open and that Windows has not given your microphone to something else."),

            new HelpItem("Chat and commands", "Friends and trading",
                "Look at somebody and press Y to ask them to be friends, H to offer a trade, or L to stop hearing them. Those three only work with somebody under your crosshair. Carrying a letter off a notice board for the person you look at, the prompt also shows E, Hand over the letter. A request shows on their screen with Accept and Refuse, and it stands for forty five seconds. Your friends are on the P panel, and friends are kept. On that panel, Mute stops their voice, Text stops their lines in the chat, and Name hides the name above their head. Hide every name does that for everyone. P also lists the people near you, with Add friend, Trade, Mute, Text and Name beside each, and everybody you have muted or hidden, friend or not, to turn them back on."),

            // The two party items came from main (entry 336, #281).
            // tests\test-help-parties.js finds them by what they are about
            // and holds every number, key and button in them to the gamemode,
            // the plugin and the P panel. Nothing here tells anybody to type
            // /party: P on somebody asks, and the P panel does the rest (#1629).
            new HelpItem("Chat and commands", "Parties",
                "P, unless you have moved it on the Controls page, opens your friends and your party. To bring somebody in, look at them and press P, or press Ask to party beside a friend who is online. They have forty five seconds to press Accept or Refuse on the prompt. A party holds up to six. The P panel says who is in yours and how many of them are in the same place as you, and Leave there takes you out. Logging out takes you out too, and every party ends when the server restarts. The leader also sees Kick and Lead beside each other person, and Disband."),

            new HelpItem("Chat and commands", "Finding your party",
                "Everybody in your party has their name in green above their head, a marker on your map, and an arrow on a strip under your compass with how far away they are. Green on the strip means the same place as you, gold means somewhere else. You cannot fast travel to the marker. Work done with somebody from your party in the same place counts 15 per cent more."),

            new HelpItem("Chat and commands", "Journals",
                "J opens your journals and their pages. You can type a title and a page. You can share a whole journal, or one page of it, with a friend, including one who is not online. They see a shared page while you are in the world. Under Boards, J also shows any town's notice board, read only, and the jobs you have taken."),

            // Issue #414: the asking staff block at the end of gamemode.js.
            new HelpItem("Chat and commands", "Getting staff: /helpme and /report",
                "/helpme and a few words about what is wrong reaches staff: anybody from staff in the world is told at once, with where you are, and it goes to the staff channel in the Discord. /report, the person's name and what they did, reaches staff and nobody else. The game tells you whether it got through. If it did not, open a ticket in the Discord."),

            new HelpItem("Chat and commands", "Stuck in the world: /stuck",
                "Wedged in a wall or a rock and cannot walk out? /stuck takes you back a few steps to where you last stood safely, or to the nearest temple when there is no such spot. It works once every 5 minutes and not while you are dead, and in a fight it waits 15 seconds first, which moving or being hit cancels. It is only for being truly stuck: every use is logged for staff."),

            // The help in the game is a panel since #1633, and nobody is told
            // to type /help. test-launcher-help.js holds the key to the ini
            // and the topics to the panel.
            new HelpItem("Chat and commands", "Everything else is on the help panel",
                "F7, unless you have moved it on the Controls page, opens the help in the game without the chat: talking, people, living, work, land and getting help, each with the keys and panels for it as your keys are set. Help on the K, P and J panels opens it too. Everything else you do in the world is a key, a prompt or a panel, and nothing else is typed. A word the server does not know is answered with where the help is."),

            new HelpItem("Chat and commands", "The console is switched off",
                "Skyrim's console opens for a moment and shuts again, with a line in the chat saying so. It is the same rule for everybody."),

            // ====================================================== emotes
            new HelpItem("Emotes", "The wheel",
                "G opens a wheel of 60 emotes. Eight quick slots sit in the middle: click one, or press 1 to 8 while the wheel is open. With the wheel shut, 1 to 8 are Skyrim's own favourites hotkeys. The rest of the list is on the right, in alphabetical order, with a search. Tab moves to that search. The middle stands you up, and Escape closes the wheel. Everybody else sees what you play."),

            new HelpItem("Emotes", "Getting out of one",
                "Some have no natural end, particularly the kneeling and leaning ones. N stands you up out of whatever you are stuck in, with the wheel shut. With the wheel open, the middle of it stands you up as well."),

            // ================================================== the mods
            new HelpItem("The mods", "Where they come from",
                "Thornswood's mods are not in the installer. They come from a collection on Nexus, which Vortex downloads and installs for you, from each mod's own author."),

            new HelpItem("The mods", "Vortex keeps them in a profile of their own",
                "Installing the collection makes a Vortex profile for it and switches to it, so your own Skyrim setup is left as it was. To switch back, press Enable under your own profile on Vortex's Profiles page (if there is no Profiles page, turn it on under Settings, Interface). Thornswood runs from a game folder of its own, so switching away takes nothing from it. Switch back when the collection updates."),

            new HelpItem("The mods", "Putting your Skyrim back to normal",
                "Press Purge Mods in Vortex, in its own list of mods. It takes every deployed mod out and leaves the game as it was before Vortex touched it. Nothing is deleted: the mods stay in Vortex and go back with one press of Deploy."),

            new HelpItem("The mods", "Removing Thornswood",
                "Uninstall in Settings. It never touches the mods: they belong to Vortex, and taking them off is Purge in Vortex. The box under it decides whether Thornswood's own game folder goes as well."),

            // ===================================================== in game
            new HelpItem("In game", "Sleeping and waiting do nothing",
                "Time is shared across the server, so nobody can skip ahead alone. There is no command to set the clock: it runs at the server's pace for everybody."),

            new HelpItem("In game", "Menus do not pause the world",
                "Inventory, favourites, crafting and the map all keep the world running. Do not sort your bags mid fight."),

            // The needs run on the server. tools\test-sunhelm-gone.js checks
            // every bar, command and source of warmth here against the gamemode.
            new HelpItem("In game", "You will get hungry, thirsty and cold",
                "Eat, drink, rest and stay warm. Cold bites hardest in the north, up high and at night. A fire warms you and standing in one burns you, a roof keeps the weather off, and what you wear counts: fur is the warmest thing there is and metal the worst. The four bars in the bottom left corner are Hunger, Thirst, Rest and Temp, and the Body page on K says what is behind them. With the bars hidden in Settings, /needs in the chat says all four as a line of text. Eat or drink something from your pack. Sit down or lie down and the rest counts by itself, on a seat, on the ground with Sit on the emote wheel, or in a bed: a seat by a fire beats a bare one, a bedroll by a fire beats both, an inn or temple bed beats the road, and your own bed is best. A bed in somebody else's building counts when they let you sleep there or you carry its key. Log out lying in a bed indoors, your own, one you may use, or an inn or temple bed, and nothing runs down while you are away and you come back rested; anywhere else the bars fall at half the pace while you are gone, and never below 25. A lute, flute or drum played from the wheel, with it in your pack, or Sing there, helps everybody resting in the same place."),

            new HelpItem("In game", "When you die",
                "You wake at the temple of the hold you died in. A hold with no temple of its own sends you to the nearest temple or Hall of the Dead, and anywhere on Solstheim sends you to Raven Rock."),

            new HelpItem("In game", "Restarts and updates are announced",
                "A countdown in the chat and on screen comes first. A notice means the world freezes for a few seconds and your game does not close. For an update, your launcher closes the game when the count runs out, installs it and puts you back in, unless it already has it, in which case nothing happens to you. A restart means the server is going down: get somewhere safe and log out before then."),

            // ===================================================== breakage
            // Scan and Fix are on the Diagnostics page since #607. Fix is
            // Verify.Fix for the plugins: the server's order, other servers'
            // files and Creation Club plugins moved aside, missing plugins
            // back from Vortex, the server's copy of Thornswood's own plugins
            // when their bytes differ or they are missing, and the mod to put
            // right in Vortex when another author's differs (#1180: the server
            // hands out only its own). Since #2627 Scan looks at the whole
            // install (Upkeep.cs) and Fix puts right everything it can, then
            // says what is left (ShellScanFix.cs).
            new HelpItem("If it breaks", "What Scan and Fix do",
                "Both are on the Diagnostics page. Scan looks for everything wrong with this install. It compares your plugins with the server's: the same names, in the same order, with the same bytes. It also looks for an update waiting, Thornswood's own game folder behind what Vortex has deployed or missing files, this build's own files changed, Windows' Skyrim folders left pointed at Thornswood after a crash, an out of date shortcut icon, the multiplayer client, Steam not running and the wrong Skyrim build. Fix puts right everything it can. It puts your plugin list in the server's order, puts back plugins Vortex has that the game folder lost, downloads the server's copy of Thornswood's own plugin when its bytes differ, names the mod to update or reinstall in Vortex when another author's plugin differs, and moves another server's files and stray Creation Club plugins aside, never deleting them. It brings the game folder up to date from Vortex first and takes a waiting update last. Then it scans again and says what is still wrong, why, and what will put it right. Close Skyrim first. Fix cannot install a mod Vortex never installed: if Scan says a plugin is not installed, the collection is not fully installed or the wrong Vortex profile is on."),

            new HelpItem("If it breaks", "\"LOAD ORDER ERROR\", or Play is refused",
                "A plugin differs from the server's, and joining like that would desync everyone. Close the game, open Diagnostics, press Scan and then Fix, and press Play again. When the plugin that differs is another author's mod, Scan names the mod to update or reinstall in Vortex, because the server hands out only Thornswood's own."),

            new HelpItem("If it breaks", "The game will not start",
                "Check the Play page first. A red row is the actual problem, and the usual one is Steam not running, because the game still checks ownership through it."),

            new HelpItem("If it breaks", "You loaded into Skyrim alone, with no character creation",
                "A long wait, a black screen, and then you are standing in Skyrim on your own. That is not a crash: nothing was answering at the server's address. The launcher checks before it starts the game and says so when the server is not answering. Watch the Discord and try again later."),

            new HelpItem("If it breaks", "Sending your logs",
                "Diagnostics, then Build the report, makes one zip with the newest crash log, the script extender log, your plugin list, the launcher log and a short summary of your machine, and opens the folder it is in. Drag that zip into your ticket in the Discord, and say what you were doing. The files themselves: the launcher log is C:\\Thornswood\\Profile\\launcher.log (Settings, Open log), and crash logs are in C:\\Thornswood\\Profile\\MyGames\\SKSE."),

            new HelpItem("If it breaks", "Something says Skyrim is open and it is not on screen",
                "Skyrim does not always exit when the window goes away, and the game's own browser often leaves helper processes behind. The launcher clears those when it starts and again when you press Play. If something still says it after the launcher restarts, restart the PC."),

            new HelpItem("If it breaks", "You connect but nobody moves",
                "Usually one person's connection rather than the server. Restart the game before restarting anything else."),

            new HelpItem("If it breaks", "Your settings look wrong",
                "Diagnostics, then Scan, then Fix, with Skyrim closed. Fix puts back this build's own files that are missing or changed, the settings files it shipped, and the load order the server expects. Your character is not touched, because it lives on the server."),

            new HelpItem("If it breaks", "Updates stopped arriving",
                "Updates come from thornswood.net and need nothing on your machine. If the launcher says it could not check, see whether thornswood.net opens in your browser. If it does not, the site is down and it is not your end. If it does, send your logs."),

            // ===================================================== tips
            new HelpItem("Tips", "A few settings are held in place for you",
                "Some of these mods rewrite their own settings file when Skyrim closes, which is how a fix can appear to undo itself overnight. The launcher writes those back every time you press Play: the favourites menu pausing the world, the Tab menu locking up, and two banners the animation replacer puts over the main menu. Everything else is yours."),

            new HelpItem("Tips", "Do not verify Skyrim in Steam",
                "It moves your Steam copy to the newest Skyrim, which is not the build the server runs, and puts back the Creation Club files that throw the load order out."),

            new HelpItem("Tips", "Updates bring only what changed",
                "When the mod list changes you get only the files that changed, not the whole build again, and each one is checked before anything is written.")
        };
    }
}
