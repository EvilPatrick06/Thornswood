# Help

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
   the launcher's Add-ons page. Not optional: without it you have a launcher
   and no mods, and the server turns you away when you press Play.
4. Press **Connect Discord** on the launcher's front page. Your browser opens,
   you say yes, and it closes itself. You never do this again.

<a id='defender'></a>

## Why does Windows or Defender warn about the installer?

The Alpha installer is not code-signed yet. Two things follow from that, and
neither is a virus finding.

Windows SmartScreen soft-blocks a download it does not recognise, with a blue
**Windows protected your PC** box. Defender's machine-learning engines flag
generic unsigned downloaders like ours on sight, whatever is inside them. Both
are reacting to the file being new and unsigned, not to anything in it.

If SmartScreen stops it, press **More info** and then **Run anyway**. That is
all it takes.

Do not turn Defender off and do not add an exclusion for the installer. You do
not need to, and it is not worth doing for one file. Check the file instead:
every build's SHA-256 is printed on the [Downloads](/downloads) page next to the
button, so you can compare it with the file you have before you run it. When a
build has been sent to VirusTotal, that page links its report on the same hash;
until then it says there is no report yet rather than pointing you at an empty
one.

The real fix is code signing, which is being worked on. Once the installer is
signed the warning goes on its own, and none of this is needed.

Setup may also show as **Thornswood Setup** with publisher **Unknown** in the
User Account Control prompt. That is the same unsigned state as the Defender
line above, not a different problem, and it clears with Authenticode signing
(#390).

## Starting it after that

Open Thornswood from the desktop shortcut. Not Skyrim, not Steam, not SKSE.
The launcher checks for updates, patches anything that changed, and the Play
button starts the game and connects you. There is no password to type and no
address to enter.

If an update is waiting, the launcher takes it before it lets you play. That is
on purpose: everybody has to be running the same files or nobody can connect.

The launcher also compares every plugin with the server's copy, byte for byte,
when it starts. If one differs it says so, and **Fix** downloads the server's
copy of that plugin. See LOAD ORDER ERROR below.

## Your first character

The game loads to its main menu and asks who you are today. Pick an empty slot
to make a new character. Nothing about a character is chosen in the launcher.

You arrive in a quiet stone hall and the race menu opens, and that is where you
make your face. When you are done you are dressed in a plain tunic and boots,
and the panel behind **K** opens by itself. That panel is where the rest is
chosen: your profession and the half of it you will make your own, your class,
and your Home, which is the town you wake up in. Those are the choices on the
[Professions](/classes) page.

Only the town has to be chosen before you leave the hall. Your class and
profession can wait, and can be picked later in the world from the same panel.
Press **Confirm** on the Review page and you wake up at the inn in the town you
chose.

Nothing else is handed out at the start, except a tool to the three picks whose
work needs one: a Miner is handed a pickaxe, a Woodworker a woodcutter's axe
and a Farmer a shovel and seed to sow, at the moment each one is picked.

## Voice

Voice runs in the launcher, not in the game. Leave the launcher open while you
play.

Push to talk is the default. The indicator in the launcher says whether you are
being heard. Whisper and yell change how far your voice carries in the world.

If nobody can hear you, check that the launcher is still open and that Windows
has not handed your microphone to something else.

## When something goes wrong

1. Look at [Known Issues](/known) first. A lot of what looks like a bug is a
   limit of how a shared Skyrim works, and it is written down there with the
   reason.
2. If it is not there, [report it](/report). One line about what happened is
   enough to start with.
3. If you have a screenshot or a crash log, drag it into the Discord channel
   with the report, or say in the report that you have one.

## LOAD ORDER ERROR

The game compares every plugin with the server's at login: the same names, in
the same order, with the same bytes. If one differs you are turned away with
that message.

Close the game, and in the launcher press **Scan**. It names the plugin that
differs. Press **Fix** and the launcher downloads the server's copy and puts
it in place. Then press Play again. Nothing in Vortex has to change.

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

The launcher's Logs page lists both and opens them. They are plain text and
they are usually the difference between a fix and a guess.

## Things that are normal here

- No saving. The server holds your character. Quitting is safe.
- Mod settings menus forget themselves every session, because there is no save
  to write them to.
- No levelling, no fast travel, and the difficulty is fixed at Expert.
- Start On Save is in the mod list but never loads a save. The launcher points
  it at a character that does not exist, on purpose: an ordinary Skyrim save
  cannot be loaded under Thornswood.
- The creation hall is a bare room. Your face is made there, and everything
  else is chosen on the panel that opens by itself once it is done.

All of that is deliberate. None of it is worth reporting. [Known Issues](/known)
covers the rest of what a shared Skyrim cannot do, and which of it is going to
change.

## Restart warnings

When an update is going out, a warning appears in the game before anything
happens. A notice means the server might stutter for a moment and you can keep
playing. An update or a restart counts down and then puts you back to the
launcher, where the Play button will pick the new version up.
