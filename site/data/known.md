# Known Issues

What is limited or broken right now, and why. Worth reading before you report
something, because a lot of what looks like a bug is how a shared Skyrim has
to work.

Not all of it is permanent. The first group follows from SkyMP itself, and
none of it is settled for good. Everything after it is where things stand
today, and some of that is being worked on.

## Limits of a shared Skyrim

These follow from the server owning the world instead of your own machine.
This table is being looked at.
Report one of these only if it does something this table does not describe.

| Behaviour | Reason |
|---|---|
| A few mod settings menus still reset every session | Your character lives on the server rather than in a save file, so there is no co-save for a mod to write its settings into. Menus built on MCM Helper, such as TrueHUD and Precision, keep theirs in a file on your machine. The server keeps the settings of Apocalypse, moreHUD, Atlas Map Markers, Skyrim Unbound and chfshVariousActions for each character and puts them back when you come in. QuickLoot, the instrument menu, MCM Recorder and SkyUI's favourite group and unequip options still start from their defaults |
| Most mod scripts never fire | All Papyrus events except OnUpdate are blocked. Records still work, scripted behaviour does not |
| Killmoves and stagger do not show on other people | Those animation events are blanked |
| Fishing in Skyrim's rods, nets and fishing powers do nothing | They run on mod scripts, which never fire here. Fishing is the Fisher's trade instead: press E at salmon, clams, pearl oysters, horker meat and slaughterfish egg nests in the water, no rod needed. See the Classes page |

## What is decided about NPCs

The cast has been cut. The traders you buy from and sell to stay, and so do
the people who work the carriages and ferries. Wildlife, bandit camps and
dungeon enemies stay where they belong. Guards, courts, priests, townsfolk and
named creatures were taken out. The server now runs the NPCs that are left, so
they keep moving when nobody is nearby. The roadmap lists what comes next under
**NPCs with their own work**. Report an NPC only if it does something
this table does not describe.

| Behaviour | Reason |
|---|---|
| NPC behaviour differs between people near the same enemy | Hosting changes every 2 seconds, so whoever is simulating decides the outcome |

## What the collection took out

Revision 5 of the collection, from 22 September, took out four mods that
worked against the server and a patch that needs one of them, and swapped
Immersive Armors for a version that does without a script. Each one is named
by its plugin file as well, because that is what your plugin list shows.
Immersive Armors, for one, is Hothtrooper44_ArmorCompilation.esp, and a
search for the words Immersive Armors finds nothing.

If a file marked Out is still in your plugin list, your collection is out of
date. Update it in Vortex.

| Mod | Plugin file | Where it stands |
|---|---|---|
| SunHelm Survival | SunHelmSurvival.esp | Out. It polled on a timer, the one script type still running, and wrote health, stamina, magicka and carry weight against a server that crops and corrects them. Hunger, thirst, rest and warmth run on the server instead: they are the four bars in the bottom left corner, and the Body page on K gives the numbers |
| SunHelm Diseases | SunHelmDiseases.esp | Out. It did the same as SunHelm Survival, and it depends on SunHelm. Diseases have not been rebuilt on the server |
| Embers XD, SunHelm patch | Embers XD - Patch - SunHelm Survival.esp | Out. It patches SunHelm and cannot load without it. Embers XD itself stays |
| Respawn - Death Overhaul | Respawn - Death Overhaul.esp | Out. It set you essential and ran its own death handler. Death cannot complete on your own machine and the server owns respawn, so it could only fight the server |
| Tavern Games | TavernGames.esp | Out. It created gold on your own machine, which the server does not accept. The games ran and the coin never arrived |
| Immersive Armors | Hothtrooper44_ArmorCompilation.esp, Hothtrooper44_Armor_Ecksstra.esp, AZ_IADistribution.esp | In, as the script free version. The standard one handed out its armour through a script whose settings do not persist here. Immersive Armors - Script Free and Skypatched replaces its plugins and does without that script. The armour itself still comes from Immersive Armors 8.1 |

## What the server owns

Anything a mod changes in this list on your own machine is overwritten or ignored.

Position and cell. Health, magicka and stamina. Death and respawn, including where. Inventory contents. Equipment. Container contents and open state. Door open state. Harvested state of plants. Actor values.

## Around Play

| Behaviour | Reason |
|---|---|
| The creation hall is a bare stone room | Nothing in the room itself does anything. Every choice about a new character is on the panel behind K, which opens by itself once your face is made and keeps coming back until you have picked a town |
| You can leave the hall with no class or profession | Only the town you wake up in has to be chosen before you leave. Your class, your profession and the half of it can wait, and are picked later in the world from the same panel on K |
| A launcher last opened before 26 September says it cannot read the update source, or never offers an update | Updates come only from thornswood.net now. A launcher that old still looks for them in the place they used to come from, which has closed, so it cannot find its way to the new one by itself. Take the installer again from the [Downloads](/downloads) page and run it over your install. Your characters live on the server and nothing is lost |

## The load order rule

The server and every machine must carry the same plugins in the same order with the same bytes. The launcher compares every plugin's size and checksum with the server's list when it starts, and the game runs the same comparison at login. One machine out of step gets LOAD ORDER ERROR and cannot connect.

If the launcher says a plugin differs, press **Fix**. When it is Thornswood's own plugin, Fix downloads the server's copy and puts it in place, and **Scan** runs the comparison again. When it is another author's mod, the server does not hand it out: Scan and Fix name the mod, and updating the Thornswood collection or reinstalling that mod in Vortex puts it right.

If the game turns you away with LOAD ORDER ERROR, quit it and press **Scan**, then **Fix**. The launcher compares your order with the server's position by position, names the first place they differ, and Fix puts the server's order into this build's plugin list. That one downloads nothing. Do not play on and do not report anything else from that session: your machine is resolving objects to different things from everybody else's, so whatever you see next is not evidence.

Scan also sees the plugins the game loads on its own. Skyrim.ccc names the Creation Club content, and the game loads any of it that is sitting in Data whether or not a list asks for it, which puts everything after it out of step. Those are named too, and Fix moves them aside rather than deleting them.

This is why mods are added in batches rather than one at a time: every addition moves the load order for everybody at once.
