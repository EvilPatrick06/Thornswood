# Known Issues

What is limited or broken right now, and why. Worth reading before you report
something, because a lot of what looks like a bug is how a shared Skyrim has
to work.

Not all of it is permanent. The first group follows from SkyMP itself, and
none of it is settled for good. Everything after it is where things stand
today, and some of that is being worked on.

## Limits of a shared Skyrim

These follow from the server owning the world instead of your own machine.
What NPCs do is on the roadmap: **Thinning the crowd** and
**NPCs with their own work**. The rest of this table is being looked at.
Report one of these only if it does something this table does not describe.

| Behaviour | Reason |
|---|---|
| NPCs stand still when nobody is nearby | SkyMP has no server side AI. An NPC is simulated by a nearby machine or not at all |
| NPC behaviour differs between people near the same enemy | Hosting changes every 2 seconds, so whoever is simulating decides the outcome |
| Mod settings menus reset every session | Your character lives on the server rather than in a save file, so there is no co-save for a mod to write its settings into |
| Most mod scripts never fire | All Papyrus events except OnUpdate are blocked. Records still work, scripted behaviour does not |
| Killmoves and stagger do not show on other people | Those animation events are blanked |

## Mods that do not work as installed

These are in the collection and do nothing useful. Whether each one is
replaced with a version that works here, or comes out of the list, is not
settled yet.

| Mod | What happens |
|---|---|
| SunHelm Survival | Polls on a timer, the one script type still running. Writes health, stamina, magicka and carry weight against a server that crops and corrects them |
| SunHelm Diseases | Same, and depends on SunHelm |
| Respawn - Death Overhaul | Sets you essential and runs its own death handler. Death cannot complete on your own machine and the server owns respawn, so it can only fight the server |
| Tavern Games | Creates gold on your own machine, which the server does not accept. The games run and the coin never arrives |
| Immersive Armors, standard version | Distributes through a script with settings that do not persist. A script free version exists |

## What the server owns

Anything a mod changes in this list on your own machine is overwritten or ignored.

Position and cell. Health, magicka and stamina. Death and respawn, including where. Inventory contents. Equipment. Container contents and open state. Door open state. Harvested state of plants. Actor values.

## Around Play

| Behaviour | Reason |
|---|---|
| Nothing in the creation hall is a choice | Your profession, half, class and town are chosen in the launcher before Play, and the hall holds nothing to pick up or read |
| Start On Save is in the mod list but never loads a save | The launcher points it at a character that does not exist. A single player save cannot be loaded under Thornswood, and loading one crashed the game on a fresh install |
| Your face is made in the hall, not in the launcher | The race menu opens once the game has loaded. Everything else about a new character is decided in the launcher |

## The load order rule

The server and every machine must carry the same plugins in the same order with the same bytes. The launcher compares every plugin's size and checksum with the server's list when it starts, and the game runs the same comparison at login. One machine out of step gets LOAD ORDER ERROR and cannot connect.

If the launcher says a plugin differs, press **Fix**. It downloads the server's copy of that plugin and puts it in place, and **Scan** runs the comparison again. Nothing in your Vortex profile has to change for that.

If the game turns you away with LOAD ORDER ERROR, quit it and press **Scan**, then **Fix**. The launcher compares your order with the server's position by position, names the first place they differ, and Fix puts the server's order into this build's plugin list. That one downloads nothing. Do not play on and do not report anything else from that session: your machine is resolving objects to different things from everybody else's, so whatever you see next is not evidence.

Scan also sees the plugins the game loads on its own. Skyrim.ccc names the Creation Club content, and the game loads any of it that is sitting in Data whether or not a list asks for it, which puts everything after it out of step. Those are named too, and Fix moves them aside rather than deleting them.

This is why mods are added in batches rather than one at a time: every addition moves the load order for everybody at once.
