# Known Issues, Not Being Fixed

Permanent limits of how this server works. None are bugs, none are changing. Not worth reporting.

## Engine and architecture

| Behaviour | Reason |
|---|---|
| NPCs stand still when nobody is nearby | SkyMP has no server side AI. An NPC is simulated by a nearby machine or not at all |
| NPC behaviour differs between people near the same enemy | Hosting changes every 2 seconds, so whoever is simulating decides the outcome |
| No saving, manual or auto | Switched off deliberately. Characters live on the server |
| Mod settings menus reset every session | Follows from no saves. There is no co-save to write to |
| Most mod scripts never fire | All Papyrus events except OnUpdate are blocked. Records still work, scripted behaviour does not |
| No levelling or skill gain | Skill experience is zeroed |
| Difficulty locked to Expert | The client writes it back every 60 updates, so the slider does nothing |
| Fast travel off | Re-disabled within one frame if anything turns it on |
| Game time follows the real clock | Written every 2 seconds, so anything scheduled by game hour drifts |
| Killmoves and stagger do not show on other people | Those animation events are blanked |

## Mods that cannot work as installed

| Mod | Reason |
|---|---|
| SunHelm Survival | Polls on a timer, the one script type still running. Writes health, stamina, magicka and carry weight against a server that crops and corrects them |
| SunHelm Diseases | Same, and depends on SunHelm |
| Immersive Armors, standard version | Distributes through a script with settings that do not persist. A script free version exists |

## Taken out

These were in the list and are not any more. They were added before it was clear they could not work here, and leaving them in meant the release notes advertised them while this page said they did nothing.

| Mod | Why it went |
|---|---|
| Respawn - Death Overhaul | Sets you essential and runs its own death handler. Death cannot complete on your own machine and the server owns respawn, so it could only ever fight the server |
| Tavern Games | Creates gold on your own machine, which the server does not accept. The games ran and the coin never arrived |

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

This is why mods are added in batches rather than one at a time: every addition moves the load order for everybody at once.
