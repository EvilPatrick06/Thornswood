# Help

## Getting in

<!-- alpha -->
Thornswood is in alpha and is eighteen and over, and the world is open by
application. Anyone can install it. Come into the Discord, open a ticket and
pick **Apply to be an alpha playtester**. It asks whether you are eighteen or
over and whether you accept the [rules](/rules). When you are accepted you are
given the Playtester role, and that role is what unlocks Play. The
[join](/join) page says more.
<!-- /alpha -->
<!-- open -->
Thornswood is open and is eighteen and over. Anyone can install it, and
anyone in the Discord can play. Being there means accepting the
[rules](/rules). The [join](/join) page has the whole of it.
<!-- /open -->

## Installing it the first time

You need **Skyrim Special Edition** on Steam, on build **1.6.1170**, and
**Vortex** with a free Nexus Mods account. Nothing else has to be installed
first. Anniversary Edition is not required.

Thornswood leaves the Skyrim you already have alone. The launcher builds a
game folder of its own, `C:\Thornswood\Game`, out of your Steam copy and what
Vortex put into it. Most of it is hard links to your own files, which take no
extra space, and the few files other programs rewrite are real copies. Vortex keeps the mods in a profile of their own, so
switching back to your usual profile and running Purge Mods leaves your own
Skyrim the way it was.

1. From the [Downloads](/downloads) page take the installer. One file. Run it.
   It fetches Thornswood's own content while you watch, about half a gigabyte,
   and puts the launcher, the script extender and Thornswood's content into
   your Skyrim.
2. Open Thornswood from the desktop shortcut. If your Skyrim is newer than
   1.6.1170, which most copies are, a card on the front page says so. Press
   **Downgrade** and Steam downloads that build under your own account. It is
   a few gigabytes, so give it a while.
3. Install the collection in Vortex. The link is on the Downloads page and on
   the launcher's Diagnostics page. Not optional: without it you have a launcher
   and no mods, and the server turns you away when you press Play.
4. Press **Connect Discord** on the launcher's front page. Your browser opens,
   you say yes, and it closes itself. You never do this again.
<!-- alpha -->
   It works once your application has been accepted; before that it says
   your account has not been accepted into the alpha yet, and applying is the
   fix.
<!-- /alpha -->

## Updating to collection revision 2

Close the game, select the Thornswood profile in Vortex, and update the
collection to **revision 2**. Let Vortex finish installing and deploying it.
Then open the Thornswood launcher and let its update finish before pressing
Play. The collection supplies the mod baseline; the launcher supplies
Thornswood's newer content and generated behavior and covered body files.

Keep **CBBE.esp** and **RaceMenuMorphsCBBE.esp** switched off. In the 3BA
installer use the Nevernude body, leave prebuilt meshes off, choose Full SMP
and No SOS, and do not install the optional CBPC configuration. The mandatory
base component can remain selected; the separate CBPC physics mod is absent
from this revision.

If the launcher reports a plugin mismatch, open **Diagnostics**, press
**Scan**, then **Fix**. Use the Thornswood shortcut for the main world and the
Dev shortcut for testing. Each has its own game folder and update source, so
updating one keeps the other separate.

<a id='defender'></a>

## Why does Windows or Defender warn about the installer?

The installer is Authenticode-signed (Azure Artifact Signing). Most of the
time Windows lets it through without a fuss.

A brand-new build can still get a soft SmartScreen ask once in a while,
because reputation follows the file hash and a fresh hash has none yet. If
Windows shows a blue **Windows protected your PC** box, press **More info**
and then **Run anyway**. The publisher should not show as Unknown.

Do not turn Defender off and do not add an exclusion for the installer. Check
the file instead: every build's SHA-256 is printed on the
[Downloads](/downloads) page next to the button.

## Starting it after that

Open Thornswood from the desktop shortcut. Not Skyrim, not Steam, not SKSE.
The launcher checks for updates, patches anything that changed, and the Play
button starts the game and connects you. There is no password to type and no
address to enter.

If an update is waiting, the launcher takes it before it lets you play. That is
on purpose: everybody has to be running the same files or nobody can connect.

The launcher also compares every plugin with the server's copy, byte for byte,
when it starts. If one differs it says so. See LOAD ORDER ERROR below.

## Your first character

The game loads to its main menu and asks who you are today. Pick an empty slot
to make a new character. Nothing about a character is chosen in the launcher.

You arrive dressed in a plain tunic and boots in a quiet stone hall.
The race menu opens there to make your face, with your clothes kept on as you
change race. When you are done, the panel behind **K** opens by itself.
That panel is where the rest is
chosen: your profession and the half of it you will make your own, your class,
and your Home, which is the town you wake up in. Those are the choices on the
[Professions](/classes) page.

Only the town has to be chosen before you leave the hall. Your class and
profession can wait, and can be picked later in the world from the same panel.
Press **Confirm** on the Review page and you wake up at the inn in the town you
chose.

Nothing else is handed out at the start, except a tool to the four picks whose
work needs one: a Miner is handed a pickaxe, a Woodworker a woodcutter's axe
and a Farmer a shovel and seed to sow. A Fisher is handed a crude fishing pole.
Each tool is supplied at the moment its pick is made.

## Keys

These are the keys a fresh install has. The launcher's **Controls** page lists
every key and changes them: press Change, then the key you want, with Skyrim
closed.

- **Enter** opens the chat, and **/** opens it with the slash already typed.
- **K** your character panel, **P** your friends and party, **J** your journals.
- Looking at somebody: **Y** asks them to be friends, **H** offers a trade, **L**
  stops you hearing them. A friend request, a party invite, or a trade offer
  shows on their screen with Accept and Refuse.
- **V** held to talk, **O** keeps the microphone open until you press it again,
  **B** steps between a whisper, your normal voice and a yell.
- **G** opens the emote wheel. Eight quick slots sit in the middle, and the
  rest of the emotes are a list you can search. **Tab** moves to that search.
  **N** stands you up out of an emote. While the wheel is open, **1** to **8**
  play a slot. With it shut they are Skyrim's own favourites hotkeys.
- **U** presses a blank key mold into the lock of the door you are looking at.
- **F7** opens the help in the game, without the chat: talking, people, living,
  work, land and getting help, with the keys as you have them set. Help on the
  K, P and J panels opens it too.
- **F1** turns the names over heads off and on, and **F2** hides and shows the
  overlay.

## Dyeing your hair

A Tailor (Haberdasher or Liverywright) steeps hair dye at a cooking spot.
Anyone can use one: on yourself from the **K** panel, or on someone else once
they accept.

If you are a Tailor, carry a bottle of water and what the dye needs, press
**E** on the cooking spot, and stay by the fire until the dye is done. Walk
away before then and nothing is made or used. The dye goes into your pack,
named for its colour. Anyone who is not a Haberdasher or Liverywright and
tries it is turned away and keeps everything they carry. They are told:
"Steeping hair dye is work for a Haberdasher or Liverywright. Nothing was
taken from your pack."

To dye your own hair, open the Hair dye page of the **K** panel and press Dye
my hair. To dye somebody else's, look at them and press **K**, then Offer to
dye, or press Dye hair beside them under Near you on the **P** panel. With
more than one dye in your pack, that button names the dye. They get Accept
and Refuse, and nothing is used or changed until they press Accept. Hair,
beard and brows take the one colour, and it stays until it is dyed again.

## Voice

Voice runs in the launcher, not in the game. Leave the launcher open while you
play.

Hold **V** to talk, or press **O** to keep the microphone open for a song or a
long speech. **B** steps between a whisper, about 7 metres, your normal voice,
about 30, and a yell, about 85. The voice card on the launcher's Play page
says whether it is working.

If nobody can hear you, check that the launcher is still open and that Windows
has not handed your microphone to something else.

## Getting staff in game

Type **/helpme** and a few words about what is wrong. Anybody from staff in the
world is told at once, with where you are, and it goes to the staff channel in
the Discord. **/report**, the person's name and what they did, reaches staff and
nobody else. The game tells you whether it got through; if it did not, open a
ticket in the Discord.

Wedged in a wall or a rock and cannot walk out? Type **/stuck**. It takes you
back a few steps to where you were last standing safely, or to the nearest
temple when there is no such spot. It works once every 5 minutes, not while you
are dead, and in a fight it waits 15 seconds first, which moving or being hit
cancels. It is only for being truly stuck: every use is logged for staff, and
using it to get out of a fight or to travel can mean a warning or a ban.

## When something goes wrong

1. Look at [Known Issues](/known) first. A lot of what looks like a bug is a
   limit of how a shared Skyrim works, and it is written down there with the
   reason.
2. If it is not there, [report it](/report). One line about what happened is
   enough to start with.
3. If you have a screenshot or a crash log, drag it into your ticket in the
   Discord, or say in the report that you have one. Where the logs are is below.

## LOAD ORDER ERROR

The game compares every plugin with the server's at login: the same names, in
the same order, with the same bytes. If one differs you are turned away with
that message.

Close the game, open **Diagnostics** in the launcher and press **Scan**. It
names the plugin that differs. Then press **Fix**, and press Play again. When
the plugin that differs is another author's mod, Scan and Fix name the mod to
update or reinstall in Vortex: the server hands out Thornswood's own plugin
and nobody else's.

What Fix does: it puts your plugin list in the server's order, puts back
plugins Vortex has that the game folder lost, downloads the server's copy of
Thornswood's own plugin when its bytes differ, names the mod to update or
reinstall in Vortex when another author's plugin differs, and moves another
server's files and stray Creation Club plugins aside, never deleting them.

Scan also looks at the rest of the install: an update waiting, Thornswood's
game folder behind what Vortex has deployed or missing files, this build's own
files changed, Windows' Skyrim folders left pointed at Thornswood after a
crash, the shortcut icon, the multiplayer client, Steam and the Skyrim build.
Fix puts right everything it can, bringing the game folder up to date from
Vortex first and taking a waiting update last. Then it looks again and says
only what is still wrong, why, and what will put it right.

If Scan says a plugin is missing rather than different, the collection is not
fully installed or the wrong Vortex profile is active. The launcher says which.

## Where the logs are

The launcher's own log, for anything that went wrong before the game started:

```
C:\Thornswood\Profile\launcher.log
```

Crash logs, if the game closed itself, are in Thornswood's own My Games
folder:

```
C:\Thornswood\Profile\MyGames\SKSE\
```

The easy way to send them: in the launcher open **Diagnostics** and press
**Build the report**. It makes one zip with the newest crash log, the script
extender log, your plugin list and the launcher log, and opens the folder it
is in. Drag that zip into your ticket in the Discord. **Settings**, **Open log**
opens the launcher log on its own.

## Things that are normal here

- No saving. The server holds your character. Quitting is safe.
- Most mod settings menus keep your choices: MCM Helper menus in a file on
  your machine, and Apocalypse, moreHUD, Atlas Map Markers, Skyrim Unbound and
  chfshVariousActions on the server, with your character. QuickLoot, the
  instrument menu, MCM Recorder and SkyUI's favourite group and unequip options
  still forget themselves every session, because there is no save to write
  them to.
- No levelling, no fast travel, and the difficulty is fixed at Expert.
- The creation hall is a bare room. Your face is made there, and everything
  else is chosen on the panel that opens by itself once it is done.

All of that is deliberate. None of it is worth reporting. [Known Issues](/known)
covers the rest of what a shared Skyrim cannot do, and which of it is going to
change.

## Restart warnings

A countdown in the chat comes first. A notice means the world freezes for a few
seconds and your game does not close. For an update, your launcher closes the
game when the count runs out, installs it and puts you back in, unless it
already has it. A restart means the server is going down: get somewhere safe
and log out before then.
