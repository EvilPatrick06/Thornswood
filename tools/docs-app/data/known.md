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
| Respawn - Death Overhaul | Sets you essential and runs its own death handler. Death cannot complete locally and the server owns respawn |
| Tavern Games | Creates gold client side |
| Immersive Armors, standard version | Distributes through a script with settings that do not persist. A script free version exists |

## What the server owns

Anything a mod changes in this list on your own machine is overwritten or ignored.

Position and cell. Health, magicka and stamina. Death and respawn, including where. Inventory contents. Equipment. Container contents and open state. Door open state. Harvested state of plants. Actor values.

## The load order rule

The server and every machine must carry the same plugins in the same order with the same files. The check compares position, file size and checksum. One machine out of step and everyone gets a red error at login.

This is why mods are added in batches rather than one at a time.
