"""
Add-ContentRecords.py

Adds records to Thornswood-Content.esp, and edits the subrecords of ones already
in it.

WHY

Patrick, 21 September: "the woodworker should be able to make handles that the
smith needs for Pickaxes, Shovels, Axes and other items that have wooden handles
like that", on top of "axes, pickaxes and shovels can eventually break and you
have to get a new one from a smith making them".

A tool that breaks has to be replaceable, and the only honest replacement is one
somebody made. Two of the three already are: ThornswoodRecipeWeaponPickaxe and
ThornswoodRecipeWeaponAxe ship in this plugin, both Smith/Edgewright, one iron
ingot each at a forge. The shovel had no recipe at all, so the sentence a farmer
reads when their shovel snaps was not true for them. And nothing anywhere needed
a woodworker, so a smith could make every tool in the game on their own.

So this adds:

    ThornswoodRecipeKeyMold       one iron ingot into a blank key mold.
    ThornswoodRecipeKey           one iron ingot into a key, named server side
                                  for whichever stamped mold is in the pack.

                                  Both added 23 September, at a forge. The
                                  property system's two items had no maker:
                                  the only mold in the world was conjured by
                                  /mold at a door, so the ceremony had to
                                  happen before the object existed and a smith
                                  on their own could never reach a key.
                                  Patrick: "you make a mold, mold gets used on
                                  door to assign mold to the door, than key
                                  uses that mold during crafting to make a key
                                  to specifically that house and it can be
                                  reused".

    ThornswoodMiscToolHandle      the handle itself. A MISC, cloned from the
                                  charcoal, which already uses
                                  Clutter\\Quest\\TG06CharcoalStick.nif: a stick,
                                  which is what a handle looks like. No new mesh
                                  has to ship.
    ThornswoodRecipeToolHandle    the woodworker turns firewood into handles.
    ThornswoodRecipeToolShovel    the smith makes the shovel that had no recipe.

and edits ThornswoodRecipeWeaponPickaxe and ThornswoodRecipeWeaponAxe so that
both of them want a handle as well as the ingot. After this, no tool in the game
exists without a woodworker and a smith between them.

WHICH BENCH THE HANDLE IS MADE AT, AND THE ONE THAT WAS TRIED FIRST

The handle is made at the charcoal kiln, which is a bench woodworkers already
stand at. The sister half rule means a Woodwright gets the novice work of the
Charburner for nothing, so both halves can cut handles.

WHAT WAS TRIED AND TAKEN BACK OUT, because it is worth somebody not trying it
again. The first attempt overrode all three of Skyrim's chopping block FURN
records, turning WBDT from 00ff, not a bench, to 01ff, the create-object bench
the cooking pot and the tanning rack use, so that every chopping block in the
province became a crafting table. Patrick, the same day: "The chopping block
shouldn't be a bench just for getting the firewood and not usable by non
woodworkers and also have the animation script". So the records are Bethesda's
and untouched, and the chopping block is answered server side in gamemode.js by
chopWood instead: the Woodwright's verb, axe required, firewood out.

THE EXECUTION BLOCK, TAKEN OUT OF SOLITUDE (issue #400)

The plugin came from another server, and the last trace of that server's name
in it was a script: FURN 0x05DF7B34, ThornswoodExecutionerChoppingBlock, the
headsman's block placed once in Solitude (REFR 0x05DFCC75), carried a VMAD
attaching the other server's chopping script, named with its prefix, with one
property pointing at Skyrim.esm's executioner swing, IDLE 0x0F95BE. That
script was never in C:\\Thornswood\\Game, the
Steam copy or any pack, measured 20 and 24 September, so it has never run for
anybody here. It is the headsman's block, not a woodcutting one: firewood comes
from the three vanilla chopping blocks, answered server side by chopWood.

Patrick, 28 September, given scenery, the executioner's swing, or removal:
"3. Take it out of Solitude." So this takes the placed reference out of its
cell and, because nothing else points at it, the block's base record as well.
The script goes with it.

WHY REMOVED AND NOT FLAGGED INITIALLY DISABLED AND DELETED. The usual way to
take a reference out of the world is to mark it Initially Disabled, and the
xEdit habit of "undelete and disable" exists for one case: a reference that
belongs to a MASTER, which other plugins may point at, where removing the
override would bring the master's copy back and deleting it outright crashes
anything that still names it. Neither applies here. Both records belong to
this plugin (the 05 at the front of both ids is this file, after its five
masters), no plugin in the game folder lists this one as a master (104 read,
28 September), and nothing in this file or the gamemode names either id. So
the records simply stop existing, which is what Skyrim sees for a form that
was never added, and what an editor does when it removes a record a plugin
itself added. The server's reader (engine\\skymp, WorldState::AttachEspmRecord)
would skip a reference flagged 0x800 or 0x20 as well; it walks groups by their
size fields, which this rewrites, so it reads the smaller file the same way. A
change form the server may have saved for that reference is kept aside and
never loaded (LoadChangeForm defers a form id the plugin does not create, and
skips one whose base is gone), so nothing has to be cleaned out of a save.

THE HEADER'S DESCRIPTION (issue #400, Patrick, 12 October)

The plugin's header carries a description (SNAM), which Vortex and other mod
tools show beside the plugin. Until 12 October it still said the content was
salvaged from the other server, by that server's full name, and was out of
date besides. Patrick's answer B on #400: the description says what the plugin
is for Thornswood, the salvaged records stay, and the other server's name is
mentioned nowhere. So this writes DESCRIPTION into the header, changing only
that subrecord and the header's size, and refuses to write a file whose
header or any record still carries the other server's full name.

If something ever does point at the base record, the tool keeps the base,
takes only its script off as before, says what points at it, and still takes
the placed reference out. If something points at the placed reference, it
stops and writes nothing.

WHAT IT PROVES BEFORE IT WRITES

The same discipline as Remove-DeadRecords.ps1 and Remove-DeadConditions.py,
whose parser this shares. It serialises the file back
byte for byte before it edits anything. Afterwards it checks that every record
that was there is still there, apart from the ones it was asked to take out, in
the same order, with the same form id, type and flags; that the ones taken out
are gone; that every record it was not asked to touch has the bytes it started with;
that the new records parse back to exactly what was built; that no form id it
allocates is already taken; that the header's record count matches what is
actually in the file; that neither the other server's full name nor either of
its short forms is in the header or in any record's editor id, attached script
or text, and its full name and longer short form in no record's bytes at all,
compressed records included; and that the header changed in its description
and its record count and nowhere else.

It will not touch a compressed record, and it refuses to add a record whose
editor id is already in the file, because two records with one name is the kind
of thing that is found months later.

THE THREE REPAIR KITS (issue #1384)

docs/systems/durability.md: a worn piece is mended with a kit, not at the
grindstone and not at the armour table. Patrick, 4 October, asked for a
suggested recipe for each, written on that page. Cheap, every input from
Skyrim.esm, and every input something a class already supplies at novice,
so the half that makes the kit can get its makings on day one:

    ThornswoodMiscWeaponKit       the Weapon Kit, a MISC.
    ThornswoodMiscArmorKit        the Armor Kit, a MISC.
    ThornswoodMiscSewingKit       the Sewing Kit, a MISC.
    ThornswoodRecipeWeaponKit     1 iron ingot and 1 leather strips, at a forge.
                                  Smith, Edgewright.
    ThornswoodRecipeArmorKit      1 iron ingot and 1 leather, at a forge.
                                  Smith, Platewright.
    ThornswoodRecipeSewingKit     1 tundra cotton and 1 leather strips, at a
                                  tanning rack. Tailor, Haberdasher.

The owner and the half are not readable off a MISC at a forge or a tanning
rack, so all three are named in $RECIPE_OWNER in
scripts/dev/Build-RecipeTable.ps1, the same as the key mold. The rank is the
dearest input, which is novice for all three.

The Sewing Kit was offered as linen wrap and leather strips. Linen wrap is
supplied by no class in this world (game/data/recipes.json says suppliedBy
null for it, measured 4 October), so a Haberdasher could never get one.
Tundra cotton is a gatherer's at novice and is already on the crude pole.
The tanning rack, not the loom, because the loom's keyword is a mod's record
(MCE_CraftingLoom, 6ce000:Update.esm) and these recipes name only Skyrim.esm.

All three MISC records are cloned from the charcoal, like the handle, so no
new mesh has to ship.

THE FOUR TREATMENTS (issue #1383)

docs/systems/injury.md: a bandage stops a bleed, a splint holds a break, a
poultice cuts the wound fever chance, and a physicker's remedy closes a cut
and clears one ordinary disease. Patrick, 4 October, settled who makes each:
a bandage is a Haberdasher novice recipe at the loom, a splint a Woodwright
novice recipe at the kiln, and the poultice and the remedy Physicker recipes,
novice and advanced. What each one asks for was not said, so these are the
suggested recipes on #1383, every input something a class supplies, the rank
the dearest of them:

    ThornswoodMiscBandage         the Bandage, a MISC.
    ThornswoodMiscSplint          the Splint, a MISC.
    ThornswoodMiscPoultice        the Poultice, a MISC.
    ThornswoodMiscRemedy          the Physicker's Remedy, a MISC.
    ThornswoodRecipeBandage       1 tundra cotton, at the loom. Tailor,
                                  Haberdasher. Novice: a gatherer's cotton.
    ThornswoodRecipeSplint        1 firewood and 1 leather strips, at the kiln.
                                  Woodworker, Woodwright. Novice: the
                                  woodworker's firewood, the hunter's leather.
    ThornswoodRecipePoultice      1 tundra cotton and 1 garlic, at the alchemy
                                  lab. Alchemist, Physicker. Novice: both a
                                  gatherer's at novice.
    ThornswoodRecipeRemedy        1 mudcrab chitin and 1 blue mountain flower,
                                  at the alchemy lab. Alchemist, Physicker.
                                  Advanced: the flower is a gatherer's at
                                  advanced, and the chitin cures disease.

THE LOOM IS A MOD'S BENCH, AND THIS PLUGIN CAN STILL NAME IT. The loom's
keyword is MCE_CraftingLoom, which MoreCraftableEquipment.esp injects into
Update.esm's own numbering as 0x6CE000 (game/data/recipes.json reads it as
6ce000:Update.esm, and the gamemode's TWO_HANDS and BENCH_ACCESS key it the
same way). Update.esm is this plugin's master 01, so 0x016CE000 here is that
keyword, with no new master. The repair kits stayed off the loom because
they named only Skyrim.esm; Patrick asked for the bandage at the loom.

THE ALCHEMY LAB IS THIS PLUGIN'S OWN. ThornswoodCraftingAlchemyWorkbench
(FURN 0x5042E69) is a create-object bench, WBDT 01 10, placed 25 times, and
carries ThornswoodCraftingAlchemy (KYWD 0x5042E6B), which no recipe named
until now. Skyrim's own alchemy lab cannot show a recipe at all: it brews from
the effects ingredients share. So the physicker's two are made at this one.

The owner and the half are named in $RECIPE_OWNER in
scripts/dev/Build-RecipeTable.ps1, because none of the four can be read off a
MISC at these benches. All four MISC records are cloned from the charcoal,
like the kits, so no new mesh has to ship.

THE HEARTHFIRE HOUSE PARTS, TAKEN OFF THE FORGE (issue #2258)

Patrick, 25 September: house parts show as craftable "instead of not
existing". Nobody builds a Hearthfire house here: property is a deed and a key
cut from a mold. The server already refuses the four (the 'nobody' rows of
$NOBODY_MAKES in scripts/dev/Build-RecipeTable.ps1, carried into the gamemode's
recipe table), but the forge menu still lists them, because a menu entry is
read on the machine in front of the person from the record, and no server code
reaches it.

So this plugin overrides the four HearthFires.esm recipes, BYOHRecipeNails,
BYOHRecipeHinge, BYOHRecipeLock and BYOHRecipeFittings, and gives each a
condition that is never true: GetItemCount of gold, on the person at the bench,
less than 0. Nobody carries less than no gold, so Skyrim's crafting menu never
lists them, and the server, which has GetItemCount (condition_functions in the
fork), turns the craft down on its own account too if a client ever asks.
Nothing else on the records changes: the same inputs, output, bench and count,
so the override is the record Bethesda wrote plus one line.

The first time, the records are read out of HearthFires.esm in the game's Data
folder (--masters), and their form ids are written in this plugin's numbering
(HearthFires.esm is its master 03 and its own records are 02 in its own file).
Once they are in this plugin, a later run edits them where they are and needs
no game. No later plugin in the load order overrides them (read 11 October
across the main install's load order), so this override is the one that wins.

The other way, the one Collapse-DwarvenIngots.py took for #613, is to drop the
BNAM so no bench lists the recipe. The condition is used here because it keeps
the bench on the record, which is what recipes.json and the gamemode read as
the recipe's bench, and because the server then refuses it too.

THE MASTER KEY (issue #2254)

    ThornswoodMiscMasterKey       one MISC, named per instance in the pack:
                                  "Master key to Breezehome, no. 12". Handed
                                  with the deed at a claim and cut again at a
                                  forge by the server, so no recipe. On the
                                  key's mesh, weightless, worth nothing.

THIS IS A SHIPPED FILE, so its size changing means a release and every client
downloading it again.

THE WOODWORKING BENCH (#516)

Patrick, 12 October 2026: bows, arrows, instruments and fishing poles listed at
the forge are a woodworker's job. Trade ownership was already correct; the forge
menu is wrong because each COBJ's BNAM is still CraftingSmithingForge.

(A) This plugin gets its own woodworking bench: keyword
ThornswoodCraftingWoodworking and furniture ThornswoodCraftingWoodworkingWorkbench,
wearing Hearthfire's carpenter workbench mesh so no new art ships. The 26 recipes
this plugin can already reach (six Skyrim bows, twelve Dawnguard bows/arrows/bolts,
four Dragonborn bows/arrows, and our own three poles plus the fish trap) have their
BNAM pointed at that keyword. The charcoal kiln is not used until #2337 is fixed.

(i) The other 53 rows live in plugins that load after this one (or that would force
a master renumber if added here). scripts/mods/Build-WoodworkerTrailOverrides.py
and woodworker-trail-recipes.json prepare a small trailing plugin for the next
collection revision. Until that ships, the server refusal stays the gate for those.

Placements of the furniture in the world are Claude's: at least one beside a forge
in every major hold and some minor towns. This script only adds the base records.


Usage (both default to game\\content\\Thornswood-Content.esp in this repo):
    python scripts/mods/Add-ContentRecords.py --check
    python scripts/mods/Add-ContentRecords.py
    python scripts/mods/Add-ContentRecords.py --masters C:\\Thornswood\\Game\\Data

Exit code 1 if the parse does not round trip, if the result does not verify, or
if anything it was asked to add is already there.
"""

import argparse
import os
import struct
import sys
import zlib

COMPRESSED = 0x00040000

# The headsman's block in Solitude, whose VMAD attached the other server's
# script, and its one placed reference. Both come out (see the top).
EXECUTION_BLOCK = 0x5DF7B34
EXECUTION_BLOCK_REF = 0x5DFCC75

# The other server's full name, lower case. Written as its code points so that
# this file does not carry the name either: it goes from everywhere in the
# repository (Patrick, 12 October, #400), and tests\test-other-server-name-gone.js
# refuses it in any file git tracks.
OTHER_SERVER_NAME = bytes([107, 101, 105, 122, 97, 97, 108])

# Its two short forms, lower case and written the same way (Patrick, 15
# October, decision C on #400): the three letter prefix that was on 33 of this
# plugin's editor ids, its script and its folders, and the six letter one that
# was on its board and, with two letters in front, on its records. The longer
# one is looked for in every byte of a record. The three letter one only in
# text (an editor id, an attached script, a string), where it would be a name;
# among a record's numbers any three letters can turn up by chance.
OTHER_SERVER_SHORT = bytes([107, 122, 108])
OTHER_SERVER_LONGER = bytes([111, 108, 105, 118, 97, 114])

# What the header says the plugin is (SNAM), written by this tool (#400).
DESCRIPTION = (b"Thornswood's crafting and gathering content: stations, salt, ore, "
               b"charcoal kilns, skill manuals, tools, keys, fishing, repair kits, "
               b"treatments, the notice board and drop box, house parts, and their "
               b"recipes.")

# Form ids for the three new records. The plugin's own records all sit in the
# 0x05______ space; 0x501548E is the highest of the 0x0501____ family in use, so
# these follow it with a gap rather than butting against it.
HANDLE = 0x5015490
RECIPE_HANDLE = 0x5015491
RECIPE_SHOVEL = 0x5015492

# ONE DEED RECORD FOR EVERY PROPERTY IN THE GAME.
#
# Patrick settled the property system on 21 September and this is the measurement
# that made "every building in the game is claimable" affordable: Inventory::Entry
# in the fork carries an optional per-instance name, serialised by name in
# Inventory.h, so one BOOK becomes "Deed to Breezehome" or "Deed to Honeyside" in
# the pack without a record per building. There are 852 claimable buildings and
# this is one record rather than 852.
#
# It is cloned from a passage book, which is a BOOK this plugin already ships and
# already reads as a plain document rather than a spell tome or a skill book.
DEED = 0x5015493

# A KEY AND A KEY MOLD, AND WHY BOTH ARE MISC RATHER THAN KEYM.
#
# Skyrim has a record type for keys and this does not use it. A KEYM lands in the
# Keys tab, which is a list the game treats as yours: a vanilla key is weightless,
# is not dropped, and is not what a pickpocket takes.
#
# Patrick, 21 September, on what a key is for here: it "can be given to people
# used by you or pickpocketed or taken out of unlocked chests or lockpicked", and
# "a stolen key only gets you in". Every one of those is a thing a MISC does and a
# KEYM does not. So a key here is an object somebody carries and can lose, which
# is the whole point of it, and the Keys tab is the wrong home for it.
#
# Both are one record for the whole game, named per instance in the pack exactly
# as the deed is: "Key to Breezehome", "Key mold for Honeyside".
KEY = 0x5015494
MOLD = 0x5015495

# WHAT THEY LOOK LIKE (#2255). Both were cloned from the charcoal MISC and kept
# its mesh, so a key and a mold were the same stick of charcoal in the pack and
# on the ground: "the key item isn't a key and is the same block log item as the
# mold". Both now wear vanilla meshes from Skyrim.esm, so still no new art ships:
# the key the 191 KEYM records in Skyrim.esm use most, and the silver mold the
# Thieves Guild quest uses (MISC TGTQ01SilverMold). The MODT that came with the
# charcoal is texture data for the charcoal's mesh, so it goes with it.
KEY_MODEL = 'Clutter\\Key01.nif'
MOLD_MODEL = 'Clutter\\SilverMold01.nif'
RECIPE_MOLD = 0x5015496
RECIPE_KEY = 0x5015497

# THE MASTER KEY (#2254). Patrick, 12 Oct 2026: a "Master key to" one building,
# handed with the deed when the building is claimed, which opens it and turns
# its lock, works only while the person it was cut for holds the building, and
# is re-cut from the mold for 2 iron ingots. One MISC for every building, named
# per instance in the pack like the key ("Master key to Breezehome, no. 12"),
# a MISC for the reasons the key is one, on the key's own mesh. It has no
# recipe: it is handed at the claim and cut at a forge by the server, never
# made in the crafting menu, because a master key nobody cut for a holder
# opens nothing. 0x50154D0 is the drop box (#2298), so after a gap from it.
MASTER_KEY = 0x50154E0

# Poles, the trap, and the pressable catches. fisher.md ingredients.
# The master pole does not take dragon bone. A trap is not a pole.
# The catches are one FLOR base each, cloned from Clam01 so they carry a
# PFIG. Spots in the world are somebody else's job. FISH_BY_BASE is not
# written here.
POLE_CRUDE = 0x5015498
POLE_FINE = 0x5015499
POLE_MASTER = 0x501549A
FISH_TRAP = 0x501549B
RECIPE_POLE_CRUDE = 0x501549C
RECIPE_POLE_FINE = 0x501549D
RECIPE_POLE_MASTER = 0x501549E
RECIPE_TRAP = 0x501549F
CATCH_HISTCARP = 0x50154A0
CATCH_RIVER_BETTY = 0x50154A1
CATCH_SCALES = 0x50154A2
CATCH_PERCH = 0x50154A3
CATCH_SPADETAIL = 0x50154A4
CATCH_LONGFIN = 0x50154A5

# The three repair kits and the recipes that make them (#1384). After a gap
# from the catches, so somebody else adding the next record after 0x50154A5
# does not land on these.
WEAPON_KIT = 0x50154B0
ARMOR_KIT = 0x50154B1
SEWING_KIT = 0x50154B2
RECIPE_WEAPON_KIT = 0x50154B3
RECIPE_ARMOR_KIT = 0x50154B4
RECIPE_SEWING_KIT = 0x50154B5

# The four treatments and the recipes that make them (#1383). After a gap from
# the kits, for the same reason the kits left one after the catches.
BANDAGE = 0x50154C0
SPLINT = 0x50154C1
POULTICE = 0x50154C2
REMEDY = 0x50154C3
RECIPE_BANDAGE = 0x50154C4
RECIPE_SPLINT = 0x50154C5
RECIPE_POULTICE = 0x50154C6
RECIPE_REMEDY = 0x50154C7

# THE NOTICE BOARD AND THE HOLD'S DROP BOX (#2298).
#
# ThornswoodMessageBoard, the activator every board in the world is, named a
# reworked copy of the board in Missives (Nexus 111375) that came with the other
# server's records, MissiveBoardCOTND.nif in a folder named with that server's
# prefix. Patrick, 12 Oct,
# chose Thornswood's own board built from vanilla pieces, with the hold's drop
# box on a shelf on its right post, as two objects placed together: "when they
# click on the Notice Board it does the Notice Board and when they click on the
# dropbox it does just the dropbox". scripts/mods/Build-NoticeBoard.py builds
# both meshes, and they ship as ours from game/ours.
#
# So the board's MODL moves to the new mesh, its OBND to the new mesh's bounds
# (the old one's were Missives' board), and the box is an activator of its own,
# ThornswoodDropBox, cloned from the board.
#
# WHY AN ACTIVATOR AND NOT A CONTAINER. Patrick, 12 Oct: a person sees only what
# they put in, gold included, and only the hold's officers see everything. A
# Skyrim container shows whoever opens it everything in it, and the server sends
# a container's whole inventory to every client that has it in view. So what is
# in the box is the server's record, the server stands the box beside its board
# (standBoard in game/gamemode.js, #2516), and E on it opens the box's own
# panel, never a container.
BOARD = 0x500593B
BOARD_MODEL = 'thornswood\\noticeboard01.nif'
BOARD_BOUNDS = (-168, -71, 0, 140, 71, 246)     # the mesh's, rounded outward
DROP_BOX = 0x50154D0
DROP_BOX_MODEL = 'thornswood\\dropbox01.nif'
DROP_BOX_BOUNDS = (-26, -18, 0, 26, 18, 37)

# THE WOODWORKING BENCH (#516). Keyword + furniture, then the 26 COBJ overrides.
# Mesh is Hearthfire's carpenter workbench (_BYOH\Furniture\CraftingWorkbench01.nif),
# measured from BYOHHouseCarpentersWorkbench in HearthFires.esm. Bounds are that
# furniture's OBND. Form ids follow MASTER_KEY (#2254), same pattern as the kits.
WOODWORKING_KEYWORD = 0x50154E1
WOODWORKING_BENCH = 0x50154E2
WOODWORKING_MODEL = r'_BYOH\Furniture\CraftingWorkbench01.nif'
WOODWORKING_BOUNDS = (-72, -10, -34, 81, 75, 64)
WOODWORKING_FULL = 'Woodworking Bench'

# Master recipes this plugin overrides onto the woodworking bench. Form ids are
# already in this plugin's numbering (Skyrim 00, Dawnguard 02, Dragonborn 04).
WOODWORKER_MASTER_RECIPES = (
    # Skyrim.esm bows
    (0x00108CF7, 'RecipeWeaponDaedricBow', 'Skyrim.esm'),
    (0x00108CF8, 'RecipeWeaponDwarvenBow', 'Skyrim.esm'),
    (0x00108CF9, 'RecipeWeaponEbonyBow', 'Skyrim.esm'),
    (0x00108CFA, 'RecipeWeaponElvenBow', 'Skyrim.esm'),
    (0x00108CFB, 'RecipeWeaponGlassBow', 'Skyrim.esm'),
    (0x00108CFC, 'RecipeWeaponOrcishBow', 'Skyrim.esm'),
    # Dawnguard.esm
    (0x02019824, 'DLC1RecipeWeaponDragonboneBow', 'Dawnguard.esm'),
    (0x02003987, 'DLC1RecipeArrowDaedric', 'Dawnguard.esm'),
    (0x02006928, 'DLC1RecipeArrowDragonbone', 'Dawnguard.esm'),
    (0x0200B64F, 'DLC1RecipeArrowIron', 'Dawnguard.esm'),
    (0x0200B650, 'DLC1RecipeArrowSteel', 'Dawnguard.esm'),
    (0x0200B651, 'DLC1RecipeArrowEbony', 'Dawnguard.esm'),
    (0x0200B652, 'DLC1RecipeArrowDwarven', 'Dawnguard.esm'),
    (0x0200B653, 'DLC1RecipeArrowGlass', 'Dawnguard.esm'),
    (0x0200B654, 'DLC1RecipeArrowOrcish', 'Dawnguard.esm'),
    (0x0200B655, 'DLC1RecipeArrowElven', 'Dawnguard.esm'),
    (0x0200F813, 'DLC1RecipeTechBoltSteel', 'Dawnguard.esm'),
    (0x0200F814, 'DLC1RecipeTechBoltDwarven', 'Dawnguard.esm'),
    # Dragonborn.esm
    (0x0402B077, 'DLC2RecipeWeaponStalhrimBow', 'Dragonborn.esm'),
    (0x0402B07F, 'DLC2RecipeWeaponNordicBow', 'Dragonborn.esm'),
    (0x0403CF53, 'DLC2RecipeArrowNordic', 'Dragonborn.esm'),
    (0x0403CF54, 'DLC2RecipeArrowStalhrim', 'Dragonborn.esm'),
)

# Our own poles and trap: already in this plugin, BNAM flipped from the forge.
WOODWORKER_OWN_RECIPES = (
    RECIPE_POLE_CRUDE,
    RECIPE_POLE_FINE,
    RECIPE_POLE_MASTER,
    RECIPE_TRAP,
)

LEATHER_STRIPS = 0x000800E4
TUNDRA_COTTON = 0x0003F7F8
STEEL_INGOT = 0x0005ACE5
REFINED_MOONSTONE = 0x0005AD9F
HISTCARP = 0x000106E18
RIVER_BETTY = 0x000106E1A
SLAUGHTERFISH_SCALES = 0x00003AD70
SILVERSIDE_PERCH = 0x000106E1C
CYRODILIC_SPADETAIL = 0x000106E19
ABECEAN_LONGFIN = 0x000106E1B
LEATHER = 0x000DB5D2         # Leather01, what the tanning rack makes from a hide
TANNING_KEYWORD = 0x007866A  # CraftingTanningRack
GARLIC = 0x00034D22          # a gatherer's at novice (game/data/harvests.json)
MUDCRAB_CHITIN = 0x0006BC00  # a hunter's off a mudcrab, novice (HUNTS_BY_BASE)
BLUE_MOUNTAIN_FLOWER = 0x00077E1C  # a gatherer's at advanced (game/data/harvests.json)
# MCE_CraftingLoom: MoreCraftableEquipment.esp's keyword, injected as Update.esm's
# 0x6CE000. Update.esm is this plugin's master 01. See THE LOOM at the top.
LOOM_KEYWORD = 0x016CE000
ALCHEMY_KEYWORD = 0x5042E6B  # ThornswoodCraftingAlchemy, this plugin's own lab

# The four Hearthfire house part recipes (#2258), in this plugin's numbering:
# HearthFires.esm is master 03. Each with the editor id the master gives it,
# which the override keeps and this checks.
HOUSE_PARTS = (
    (0x0300306D, 'BYOHRecipeNails'),
    (0x0300306E, 'BYOHRecipeHinge'),
    (0x0300306F, 'BYOHRecipeLock'),
    (0x03003036, 'BYOHRecipeFittings'),
)
HOUSE_PARTS_MASTER = 'HearthFires.esm'

# A condition that is never true (#2258). A CTDA is 32 bytes: the operator in
# the top three bits of the first byte (4 is '<', the enum in libespm CTDA.h),
# three bytes of nothing, the value to compare with (0.0), the function (47,
# GetItemCount, which the fork's server evaluates as well as Skyrim), two bytes
# of nothing, the first parameter (Gold001, 0xF in Skyrim.esm, master 00), the
# second (none), run on the subject (0, the person at the bench), no reference,
# and the third parameter, -1 for none. GetItemCount is never below 0.
GOLD = 0x0000000F
NEVER_TRUE = struct.pack('<B3sfHHIIIIi', 4 << 5, b'\x00\x00\x00', 0.0, 47, 0,
                         GOLD, 0, 0, 0, -1)

# Where the masters are read from, the first time a master record is copied in.
MASTERS_DIR = 'C:\\Thornswood\\Game\\Data'

# The subrecords a COBJ carries, and which hold form ids. A record copied in
# from a master with anything else in it stops the tool, because a form id in
# a field this does not know would keep the master's numbering.
COBJ_FORM_FIELDS = {b'CNTO': (0,), b'COED': (0,), b'CNAM': (0,), b'BNAM': (0,),
                    b'CTDA': (12, 16, 24)}
COBJ_PLAIN_FIELDS = (b'EDID', b'COCT', b'NAM1', b'CIS1', b'CIS2')

DEED_WORDS = (
    '<p align="center"><font size="30">Deed</font></p>'
    '<br><br>'
    'This deed sets out the holding of the property written on its cover.'
    '<br><br>'
    '<font size="18">Whoever carries it holds the place. There is no copy and no '
    'register but this. Keep it somewhere a thief will not look, or do not keep it '
    'at all.</font>')

# What the recipes are made of and what they make. Every one of these was read
# out of a record already in this file or out of TOOLS in gamemode.js, never
# remembered.
FIREWOOD = 0x0006F993        # the CNTO of ThornswoodRecipeCharcoalTier1
IRON_INGOT = 0x0005ACE4      # the CNTO of ThornswoodRecipeWeaponPickaxe
SHOVEL = 0x000F5D05          # TOOLS.farmer.give in gamemode.js
KILN_KEYWORD = 0x501547F     # the BNAM of every charcoal recipe
FORGE_KEYWORD = 0x0088105    # the BNAM of the pickaxe and axe recipes

# A handle is worth a little more than the firewood it came from and weighs the
# same as a charcoal stick. Nothing in the rulebook sets either number.
HANDLE_VALUE = 5
HANDLE_WEIGHT = 0.5

# What a kit is worth and weighs. Nothing in the rulebook sets either number;
# an item has no gold price here, and these are cheap so the rank stays the
# dearest input's.
METAL_KIT_VALUE = 15
METAL_KIT_WEIGHT = 1.0
SEWING_KIT_VALUE = 10
SEWING_KIT_WEIGHT = 0.5

# What each treatment is worth and weighs (#1383). The rulebook sets neither;
# an item has no gold price here, and a bandage is light.
BANDAGE_VALUE, BANDAGE_WEIGHT = 2, 0.1
SPLINT_VALUE, SPLINT_WEIGHT = 5, 1.0
POULTICE_VALUE, POULTICE_WEIGHT = 5, 0.2
REMEDY_VALUE, REMEDY_WEIGHT = 15, 0.2


def cnto(base, count):
    return struct.pack('<II', base, count)


class Rec(object):
    def __init__(self, tag, flags, fid, extra, data):
        self.tag, self.flags, self.fid = tag, flags, fid
        self.extra, self.data = extra, data

    def bytes(self):
        return (self.tag + struct.pack('<III', len(self.data), self.flags, self.fid)
                + self.extra + self.data)

    @property
    def compressed(self):
        return (self.flags & COMPRESSED) != 0

    def editor_id(self):
        if self.compressed:
            return ''
        for tag, body in subrecords(self.data):
            if tag == b'EDID':
                return body.rstrip(b'\x00').decode('ascii', 'replace')
        return ''


class Grup(object):
    def __init__(self, label, kids):
        self.label, self.kids = label, kids

    def bytes(self):
        body = b''.join(k.bytes() for k in self.kids)
        return b'GRUP' + struct.pack('<I', len(body) + 24) + self.label + body


def subrecords(data):
    out, i = [], 0
    while i + 6 <= len(data):
        tag = data[i:i + 4]
        size = struct.unpack_from('<H', data, i + 4)[0]
        if i + 6 + size > len(data):
            break
        out.append((tag, data[i + 6:i + 6 + size]))
        i += 6 + size
    return out


def pack_subrecords(pairs):
    return b''.join(t + struct.pack('<H', len(b)) + b for t, b in pairs)


def zstr(s):
    return s.encode('ascii') + b'\x00'


def parse(buf, start, end):
    kids, p = [], start
    while p + 24 <= end:
        tag = buf[p:p + 4]
        size = struct.unpack_from('<I', buf, p + 4)[0]
        if tag == b'GRUP':
            kids.append(Grup(buf[p + 8:p + 24], parse(buf, p + 24, p + size)))
            p += size
        else:
            flags, fid = struct.unpack_from('<II', buf, p + 8)
            kids.append(Rec(tag, flags, fid, buf[p + 16:p + 24],
                            buf[p + 24:p + 24 + size]))
            p += 24 + size
    return kids


def every_record(kids):
    for k in kids:
        if isinstance(k, Grup):
            for r in every_record(k.kids):
                yield r
        else:
            yield k


def top_group(tree, tag):
    for k in tree:
        if isinstance(k, Grup) and k.label[:4] == tag:
            return k
    raise SystemExit('no top level %s group in this plugin' % tag.decode())


def clone(src, fid, editor_id, sets=None, after=None, drop=None):
    """A copy of src with a new id and editor id, and named subrecords changed.

    sets    tag -> bytes, replacing the first subrecord with that tag.
    after   tag -> list of (tag, bytes) to insert after the last one with that tag.
    drop    tags to leave out.
    """
    sets, after, drop = sets or {}, after or {}, set(drop or ())
    pairs = [(t, b) for t, b in subrecords(src.data) if t not in drop]
    pairs = [(t, sets.pop(t, b)) if t in sets else (t, b) for t, b in pairs]
    if sets:
        raise SystemExit('nothing to replace for ' + ','.join(t.decode() for t in sets))
    out = []
    for i, (t, b) in enumerate(pairs):
        out.append((t, b))
        last = max(j for j, (tt, _) in enumerate(pairs) if tt == t) if t in after else -1
        if t in after and i == last:
            out.extend(after[t])
    out = [(t, zstr(editor_id)) if t == b'EDID' else (t, b) for t, b in out]
    return Rec(src.tag, src.flags, fid, src.extra, pack_subrecords(out))


def set_model(rec, model):
    """The record's MODL set to model and the old mesh's MODT/MODS dropped.
    True when that changed anything, so a second run is not an edit."""
    pairs = subrecords(rec.data)
    want = zstr(model)
    out = []
    for t, b in pairs:
        if t in (b'MODT', b'MODS'):
            continue
        out.append((t, want) if t == b'MODL' else (t, b))
    if not any(t == b'MODL' for t, _ in pairs):
        raise SystemExit('0x%07X has no MODL to set' % rec.fid)
    if out == pairs:
        return False
    rec.data = pack_subrecords(out)
    return True


def set_bounds(rec, bounds):
    """The record's OBND set to bounds (six whole numbers). True when that changed
    anything, so a second run is not an edit."""
    pairs = subrecords(rec.data)
    want = struct.pack('<6h', *bounds)
    if not any(t == b'OBND' for t, _ in pairs):
        raise SystemExit('0x%07X has no OBND to set' % rec.fid)
    out = [(t, want) if t == b'OBND' else (t, b) for t, b in pairs]
    if out == pairs:
        return False
    rec.data = pack_subrecords(out)
    return True


def set_inputs(rec, items):
    """Replace every CNTO and set COCT to match. items is (formid, count)."""
    pairs = subrecords(rec.data)
    out = []
    placed = False
    for t, b in pairs:
        if t == b'COCT':
            out.append((t, struct.pack('<I', len(items))))
            continue
        if t == b'CNTO':
            if not placed:
                for base, count in items:
                    out.append((b'CNTO', cnto(base, count)))
                placed = True
            continue
        out.append((t, b))
    if not placed:
        raise SystemExit('recipe had no CNTO to replace')
    rec.data = pack_subrecords(out)


def set_bnam(rec, keyword):
    """The recipe's BNAM set to keyword. True when that changed anything."""
    pairs = subrecords(rec.data)
    want = struct.pack('<I', keyword)
    if not any(t == b'BNAM' for t, _ in pairs):
        raise SystemExit('0x%07X has no BNAM to set' % rec.fid)
    out = [(t, want) if t == b'BNAM' else (t, b) for t, b in pairs]
    if out == pairs:
        return False
    rec.data = pack_subrecords(out)
    return True


def kwda_swap(kwda, old_fid, new_fid):
    """KWDA bytes with one form id replaced. Raises if old_fid is not there."""
    if len(kwda) % 4:
        raise SystemExit('KWDA length %d is not a multiple of 4' % len(kwda))
    out = bytearray(kwda)
    found = False
    for o in range(0, len(out), 4):
        if struct.unpack_from('<I', out, o)[0] == old_fid:
            struct.pack_into('<I', out, o, new_fid)
            found = True
    if not found:
        raise SystemExit('KWDA does not carry 0x%08X to swap' % old_fid)
    return bytes(out)


def ensure_top_group(tree, tag):
    """The top GRUP for tag, made if this plugin has never had one."""
    for k in tree:
        if isinstance(k, Grup) and k.label[:4] == tag:
            return k
    sample = next(k for k in tree if isinstance(k, Grup))
    stamp = sample.label[12:16] if len(sample.label) >= 16 else b'\x00' * 4
    g = Grup(tag + b'\x00' * 8 + stamp, [])
    tree.append(g)
    return g


def wants_handle(rec):
    """One more input on a recipe that already has one, and the count bumped."""
    pairs = subrecords(rec.data)
    have = sum(1 for t, _ in pairs if t == b'CNTO')
    out = []
    for i, (t, b) in enumerate(pairs):
        if t == b'COCT':
            out.append((t, struct.pack('<I', have + 1)))
            continue
        out.append((t, b))
        if t == b'CNTO' and i == max(j for j, (tt, _) in enumerate(pairs) if tt == b'CNTO'):
            out.append((b'CNTO', cnto(HANDLE, 1)))
    rec.data = pack_subrecords(out)


def drop_script(rec):
    """Takes the VMAD off a record and leaves every other subrecord as it was.

    True when there was one to take. Refuses (SystemExit) when the record's
    subrecords do not pack back to its own bytes, because then dropping one of
    them would be a guess about the rest."""
    pairs = subrecords(rec.data)
    if pack_subrecords(pairs) != rec.data:
        raise SystemExit('STOP. 0x%07X does not read back as its own subrecords. '
                         'Nothing was written.' % rec.fid)
    kept = [(t, b) for t, b in pairs if t != b'VMAD']
    if len(kept) == len(pairs):
        return False
    rec.data = pack_subrecords(kept)
    return True


def plain(rec):
    """A record's subrecord bytes, inflated when it is compressed."""
    return zlib.decompress(rec.data[4:]) if rec.compressed else rec.data


def pointing_at(records, fid, besides):
    """Every record, other than those whose ids are in besides, whose bytes hold
    fid as a form id. A byte search rather than a field by field read, so it can
    only find too much, never too little: a false hit keeps a record in."""
    needle = struct.pack('<I', fid)
    return [r for r in records if r.fid not in besides and needle in plain(r)]


def take_out(kids, fids):
    """kids without the records whose ids are in fids. A group that held
    records and is left with none goes as well; one that was empty already
    stays, so nothing else in the file moves."""
    out = []
    for k in kids:
        if isinstance(k, Grup):
            had = len(k.kids)
            k.kids = take_out(k.kids, fids)
            if had and not k.kids:
                continue
        elif k.fid in fids:
            continue
        out.append(k)
    return out


def is_text(body):
    """A subrecord that is one string: printable ASCII ending in a zero, the
    way an editor id, a model path or a description is written."""
    return (len(body) > 1 and body.endswith(b'\x00') and
            all(32 <= b < 127 for b in body[:-1]))


def other_server_names(rec):
    """Where the other server's name or one of its short forms is in one
    record: its editor id, a script its VMAD attaches, any other string, or,
    for the full name and the longer short form, any byte. A compressed record
    is inflated to be read, and never written back from here."""
    data = rec.data
    if rec.compressed:
        data = zlib.decompress(data[4:])
    found = []
    for tag, body in subrecords(data):
        low = body.lower()
        short = OTHER_SERVER_SHORT in low or OTHER_SERVER_LONGER in low
        if OTHER_SERVER_NAME in low:
            found.append('its full name, in ' + tag.decode('ascii', 'replace'))
        elif tag == b'EDID' and short:
            found.append('editor id ' + body.rstrip(b'\x00').decode('ascii', 'replace'))
        elif tag == b'VMAD' and short:
            found.append('a script it attaches')
        elif short and (is_text(body) or OTHER_SERVER_LONGER in low):
            found.append('a short form, in ' + tag.decode('ascii', 'replace'))
    return found


def other_server_in_header(head):
    """Whether the header carries the other server's full name or either short
    form, anywhere. It is a description, the masters' names and a handful of
    numbers, and every run reads it, so a chance hit among the numbers would
    be seen at once and not months later."""
    low = bytes(head).lower()
    return any(n in low for n in (OTHER_SERVER_NAME, OTHER_SERVER_SHORT, OTHER_SERVER_LONGER))


def described(head):
    """The header with DESCRIPTION as its SNAM, its size field set to match,
    and whether that changed anything. A header with no SNAM gains one after
    CNAM, where the Creation Kit writes it."""
    pairs = subrecords(bytes(head[24:]))
    want = DESCRIPTION + b'\x00'
    out, put = [], False
    for tag, body in pairs:
        if tag == b'SNAM':
            out.append((tag, want))
            put = True
        else:
            out.append((tag, body))
    if not put:
        at = next((i + 1 for i, (t, _) in enumerate(out) if t == b'CNAM'), 1)
        out.insert(at, (b'SNAM', want))
    body = pack_subrecords(out)
    new = bytearray(head[:24]) + body
    struct.pack_into('<I', new, 4, len(body))
    return new, bytes(new) != bytes(head)


def masters_of(buf):
    """The MAST names in a plugin's header, in order."""
    hs = struct.unpack_from('<I', buf, 4)[0]
    return [b.rstrip(b'\x00').decode('ascii', 'replace')
            for t, b in subrecords(buf[24:24 + hs]) if t == b'MAST']


def record_in(buf, tag, fid):
    """The record of that type and form id (the file's own numbering), or None.
    Only the top group of that type is walked."""
    hs = struct.unpack_from('<I', buf, 4)[0]
    p = 24 + hs
    while p + 24 <= len(buf):
        size = struct.unpack_from('<I', buf, p + 4)[0]
        if buf[p:p + 4] == b'GRUP' and buf[p + 8:p + 12] == tag:
            for r in every_record(parse(buf, p + 24, p + size)):
                if r.fid == fid and r.tag == tag:
                    return r
            return None
        p += size if buf[p:p + 4] == b'GRUP' else 24 + size
    return None


def renumbered(v, mapping, what):
    """A form id moved from the master's numbering into this plugin's."""
    idx = v >> 24
    if idx >= len(mapping):
        raise SystemExit('STOP. %s names 0x%08X, outside its file\'s masters. '
                         'Nothing was written.' % (what, v))
    return (mapping[idx] << 24) | (v & 0xFFFFFF)


def from_master(masters_dir, master, local_fid, plugin_masters, tag=b'COBJ'):
    """A copy of a master's record, in this plugin's numbering.

    local_fid is the id as this plugin writes it (the master's index here in
    the top byte). The master is read from masters_dir; its own records carry
    its own master count in the top byte, and every form id in the copy is
    moved from its numbering to this plugin's. Refuses a compressed record and
    a subrecord this does not know, rather than guess at what is in it."""
    path = os.path.join(masters_dir, master)
    if not os.path.isfile(path):
        raise SystemExit('STOP. %s is not in %s, and this needs it the first time. '
                         'Give --masters the game\'s Data folder. Nothing was written.'
                         % (master, masters_dir))
    buf = open(path, 'rb').read()
    src_masters = masters_of(buf)
    own = len(src_masters)
    rec = record_in(buf, tag, (own << 24) | (local_fid & 0xFFFFFF))
    if rec is None:
        raise SystemExit('STOP. %s has no %s 0x%06X. Nothing was written.'
                         % (master, tag.decode(), local_fid & 0xFFFFFF))
    if rec.compressed:
        raise SystemExit('STOP. %s %s 0x%06X is compressed. Nothing was written.'
                         % (master, tag.decode(), local_fid & 0xFFFFFF))
    names = [m.lower() for m in plugin_masters]
    mapping = []
    for m in src_masters + [master]:
        if m.lower() not in names:
            raise SystemExit('STOP. %s names %s, which is not a master of this plugin. '
                             'Nothing was written.' % (master, m))
        mapping.append(names.index(m.lower()))
    pairs = subrecords(rec.data)
    if pack_subrecords(pairs) != rec.data:
        raise SystemExit('STOP. %s 0x%06X does not read back as its own subrecords. '
                         'Nothing was written.' % (master, local_fid & 0xFFFFFF))
    out = []
    for t, b in pairs:
        if t in COBJ_FORM_FIELDS:
            b = bytearray(b)
            offsets = list(COBJ_FORM_FIELDS[t])
            # A CTDA whose flags say "use global" compares with a GLOB, not a number.
            if t == b'CTDA' and b[0] & 0x04:
                offsets.append(4)
            for o in offsets:
                v = struct.unpack_from('<I', b, o)[0]
                if v:
                    struct.pack_into('<I', b, o, renumbered(v, mapping, '%s %s' % (master, t.decode())))
            b = bytes(b)
        elif t not in COBJ_PLAIN_FIELDS:
            raise SystemExit('STOP. %s 0x%06X carries %s, which this does not know how to '
                             'renumber. Nothing was written.'
                             % (master, local_fid & 0xFFFFFF, t.decode()))
        out.append((t, b))
    return Rec(rec.tag, rec.flags, renumbered(rec.fid, mapping, master), rec.extra,
               pack_subrecords(out))


def never_listed(rec):
    """The recipe with NEVER_TRUE among its conditions, after any it has and
    before its output. True when that changed anything, so a second run is not
    an edit."""
    pairs = subrecords(rec.data)
    if any(t == b'CTDA' and b == NEVER_TRUE for t, b in pairs):
        return False
    at = max([i + 1 for i, (t, _) in enumerate(pairs) if t in (b'CTDA', b'CIS1', b'CIS2')] or
             [i for i, (t, _) in enumerate(pairs) if t == b'CNAM'] or [len(pairs)])
    pairs.insert(at, (b'CTDA', NEVER_TRUE))
    rec.data = pack_subrecords(pairs)
    return True


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', default=os.path.normpath(
        os.path.join(here, '..', '..', 'game', 'content')))
    ap.add_argument('--plugin', default='Thornswood-Content.esp')
    ap.add_argument('--check', action='store_true', help='say what would happen, write nothing')
    ap.add_argument('--masters', default=MASTERS_DIR,
                    help="the game's Data folder, read when a master's record is first copied in")
    args = ap.parse_args()

    path = os.path.join(args.data, args.plugin)
    raw = open(path, 'rb').read()
    print('The file')
    print('  %s' % path)
    print('  %s bytes' % format(len(raw), ','))

    header_size = struct.unpack_from('<I', raw, 4)[0]
    head = bytearray(raw[:24 + header_size])
    tree = parse(raw, 24 + header_size, len(raw))

    print('')
    print('Can the parser reproduce the file it was given')
    if bytes(head) + b''.join(k.bytes() for k in tree) != raw:
        print('STOP. the parse does not round trip. Nothing was written.')
        return 1
    print('  ok    parsed and written back byte for byte, %s bytes' % format(len(raw), ','))

    records = list(every_record(tree))
    by_edid = {}
    for r in records:
        e = r.editor_id()
        if e:
            by_edid[e] = r
    taken = set(r.fid for r in records)
    before = {r.fid: r.data for r in records}

    # ALREADY THERE IS NOT AN ERROR, BUT A DIFFERENT RECORD UNDER THE SAME NAME
    # IS. This script is run again every time the plugin grows another record, so
    # it says what is already in place and adds what is not. What it will not do
    # is write a second record with an editor id the file already uses: two
    # records under one name is the kind of thing that is found months later.
    already = set()
    for name, fid in (('ThornswoodMiscToolHandle', HANDLE),
                      ('ThornswoodRecipeToolHandle', RECIPE_HANDLE),
                      ('ThornswoodRecipeToolShovel', RECIPE_SHOVEL),
                      ('ThornswoodBookDeed', DEED),
                      ('ThornswoodMiscKey', KEY),
                      ('ThornswoodMiscKeyMold', MOLD),
                      ('ThornswoodRecipeKeyMold', RECIPE_MOLD),
                      ('ThornswoodRecipeKey', RECIPE_KEY),
                      ('ThornswoodMiscPoleCrude', POLE_CRUDE),
                      ('ThornswoodMiscPoleFine', POLE_FINE),
                      ('ThornswoodMiscPoleMaster', POLE_MASTER),
                      ('ThornswoodMiscFishTrap', FISH_TRAP),
                      ('ThornswoodRecipePoleCrude', RECIPE_POLE_CRUDE),
                      ('ThornswoodRecipePoleFine', RECIPE_POLE_FINE),
                      ('ThornswoodRecipePoleMaster', RECIPE_POLE_MASTER),
                      ('ThornswoodRecipeFishTrap', RECIPE_TRAP),
                      ('ThornswoodFishHistcarp', CATCH_HISTCARP),
                      ('ThornswoodFishRiverBetty', CATCH_RIVER_BETTY),
                      ('ThornswoodFishSlaughterfishScales', CATCH_SCALES),
                      ('ThornswoodFishSilversidePerch', CATCH_PERCH),
                      ('ThornswoodFishCyrodilicSpadetail', CATCH_SPADETAIL),
                      ('ThornswoodFishAbeceanLongfin', CATCH_LONGFIN),
                      ('ThornswoodMiscWeaponKit', WEAPON_KIT),
                      ('ThornswoodMiscArmorKit', ARMOR_KIT),
                      ('ThornswoodMiscSewingKit', SEWING_KIT),
                      ('ThornswoodRecipeWeaponKit', RECIPE_WEAPON_KIT),
                      ('ThornswoodRecipeArmorKit', RECIPE_ARMOR_KIT),
                      ('ThornswoodRecipeSewingKit', RECIPE_SEWING_KIT),
                      ('ThornswoodMiscBandage', BANDAGE),
                      ('ThornswoodMiscSplint', SPLINT),
                      ('ThornswoodMiscPoultice', POULTICE),
                      ('ThornswoodMiscRemedy', REMEDY),
                      ('ThornswoodRecipeBandage', RECIPE_BANDAGE),
                      ('ThornswoodRecipeSplint', RECIPE_SPLINT),
                      ('ThornswoodRecipePoultice', RECIPE_POULTICE),
                      ('ThornswoodRecipeRemedy', RECIPE_REMEDY),
                      ('ThornswoodDropBox', DROP_BOX),
                      ('ThornswoodMiscMasterKey', MASTER_KEY),
                      ('ThornswoodCraftingWoodworking', WOODWORKING_KEYWORD),
                      ('ThornswoodCraftingWoodworkingWorkbench', WOODWORKING_BENCH)):
        here_already = name in by_edid
        if here_already and by_edid[name].fid != fid:
            print('')
            print('STOP. %s is already in this plugin as 0x%07X and this would add it as '
                  '0x%07X. Nothing was written.' % (name, by_edid[name].fid, fid))
            return 1
        if here_already:
            already.add(name)
        elif fid in taken:
            print('')
            print('STOP. 0x%07X is already taken. Nothing was written.' % fid)
            return 1
    if already:
        print('')
        print('Already in the plugin, so not added again')
        for name in sorted(already):
            print('  %s' % name)
    misc_src = by_edid['ThornswoodCharcoalTier1']
    cobj_charcoal = by_edid['ThornswoodRecipeCharcoalTier1']
    cobj_pickaxe = by_edid['ThornswoodRecipeWeaponPickaxe']
    cobj_axe = by_edid['ThornswoodRecipeWeaponAxe']
    # Looked up by form id, which is what the gamemode and the load order use.
    # Absent is not an error: once they are out, a second run finds neither.
    block = next((r for r in records if r.fid == EXECUTION_BLOCK and r.tag == b'FURN'), None)
    block_ref = next((r for r in records
                      if r.fid == EXECUTION_BLOCK_REF and r.tag == b'REFR'), None)
    removing = set()
    if block_ref is not None:
        if (block_ref.compressed or
                not any(t == b'NAME' and b == struct.pack('<I', EXECUTION_BLOCK)
                        for t, b in subrecords(block_ref.data))):
            print('')
            print('STOP. REFR 0x%07X is not the placed Execution Block any more. '
                  'Nothing was written.' % EXECUTION_BLOCK_REF)
            return 1
        on_ref = pointing_at(records, EXECUTION_BLOCK_REF, {EXECUTION_BLOCK_REF})
        if on_ref:
            print('')
            for r in on_ref:
                print('STOP. %s 0x%07X %s points at the placed block 0x%07X.'
                      % (r.tag.decode(), r.fid, r.editor_id(), EXECUTION_BLOCK_REF))
            print('  Nothing was written.')
            return 1
        removing.add(EXECUTION_BLOCK_REF)
    # The base goes too, unless something other than its one placed reference
    # names it. Then it stays, and only its script comes off.
    on_block = []
    if block is not None:
        on_block = pointing_at(records, EXECUTION_BLOCK,
                               {EXECUTION_BLOCK, EXECUTION_BLOCK_REF})
        if not on_block:
            removing.add(EXECUTION_BLOCK)
    block_scripted = (block is not None and EXECUTION_BLOCK not in removing and
                      any(t == b'VMAD' for t, _ in subrecords(block.data)))

    handle = clone(misc_src, HANDLE, 'ThornswoodMiscToolHandle', sets={
        b'FULL': zstr('Tool Handle'),
        b'DATA': struct.pack('<If', HANDLE_VALUE, HANDLE_WEIGHT),
    })
    make_handle = clone(cobj_charcoal, RECIPE_HANDLE, 'ThornswoodRecipeToolHandle', sets={
        b'CNTO': cnto(FIREWOOD, 1),
        b'CNAM': struct.pack('<I', HANDLE),
        b'BNAM': struct.pack('<I', KILN_KEYWORD),
    })
    # The body is the same on every deed, because there is only one record. What
    # property it is, is the per-instance name in the pack, and the words below
    # are why a stolen one is worth stealing: whoever carries it holds the place.
    deed = clone(by_edid['ThornswoodPassageWhiterun'], DEED, 'ThornswoodBookDeed', sets={
        b'FULL': zstr('Deed'),
        b'DESC': zstr(DEED_WORDS),
    })
    # A key and its mold, both cloned from the charcoal MISC for the same reason
    # the handle was: it already uses a small clutter mesh, so no new art ships.
    key = clone(misc_src, KEY, 'ThornswoodMiscKey', sets={
        b'FULL': zstr('Key'),
        b'DATA': struct.pack('<If', 0, 0.0),
    })
    set_model(key, KEY_MODEL)
    mold = clone(misc_src, MOLD, 'ThornswoodMiscKeyMold', sets={
        b'FULL': zstr('Key Mold'),
        b'DATA': struct.pack('<If', 25, 1.0),
    })
    set_model(mold, MOLD_MODEL)
    # The master key (#2254), the key's twin: weightless and worth nothing to a
    # merchant, on the key's mesh. See MASTER_KEY at the top.
    master_key = clone(misc_src, MASTER_KEY, 'ThornswoodMiscMasterKey', sets={
        b'FULL': zstr('Master Key'),
        b'DATA': struct.pack('<If', 0, 0.0),
    })
    set_model(master_key, KEY_MODEL)
    # THE MOLD AND THE KEY ARE BOTH MADE BY A SMITH, WHICH IS WHAT MAKES THE
    # CHAIN START AT ALL.
    #
    # Patrick, 23 September: "Wait how tf does someone use a mold if you can't
    # make a key to own the building make this shit make sense make a fucking
    # mold item craftable dude this would solve alot", and then the whole
    # shape: "The key should be too what should happen is you make a mold,
    # mold gets used on door to assign mold to the door, than key uses that
    # mold during crafting to make a key to specifically that house and it can
    # be reused".
    #
    # He is right and it was circular. Both records have been in this plugin
    # since the property system was built and nothing in the game made either
    # one: the only mold in the world was conjured out of nothing by /mold at
    # a door, so the ceremony had to happen before the object existed, and a
    # smith on their own could never reach a key at all.
    #
    # ONE IRON INGOT EACH, at a forge, the same shape as the pickaxe and the
    # axe beside them. The mold is the blank; the door stamps it; the key
    # recipe is answered server side by which stamped mold is in the pack, so
    # the key comes out named for that house and THE MOLD IS NOT CONSUMED.
    # That is why the mold is not an input here: a CNTO is taken away by the
    # engine before the server is asked, and he asked for it to be reusable.
    #
    # Both cloned from the charcoal recipe rather than the pickaxe, because
    # the pickaxe wants a handle as well and carries COCT 2. These take one
    # input each.
    make_mold = clone(cobj_charcoal, RECIPE_MOLD, 'ThornswoodRecipeKeyMold', sets={
        b'CNTO': cnto(IRON_INGOT, 1),
        b'CNAM': struct.pack('<I', MOLD),
        b'BNAM': struct.pack('<I', FORGE_KEYWORD),
    })
    make_key = clone(cobj_charcoal, RECIPE_KEY, 'ThornswoodRecipeKey', sets={
        b'CNTO': cnto(IRON_INGOT, 1),
        b'CNAM': struct.pack('<I', KEY),
        b'BNAM': struct.pack('<I', FORGE_KEYWORD),
    })
    make_shovel = clone(cobj_pickaxe, RECIPE_SHOVEL, 'ThornswoodRecipeToolShovel', sets={
        b'CNAM': struct.pack('<I', SHOVEL),
    }, after={b'CNTO': [(b'CNTO', cnto(HANDLE, 1))]})
    # The clone copied COCT 1 from the pickaxe and the shovel now has two inputs.
    make_shovel.data = pack_subrecords(
        [(t, struct.pack('<I', 2)) if t == b'COCT' else (t, b)
         for t, b in subrecords(make_shovel.data)])


    # Clam01 from Skyrim.esm, uncompressed, PFIG present. Kept here so this
    # script does not need the master open. FULL is replaced with a plain name.
    clam_raw = bytes.fromhex(
        '464c4f52bd00000000000000805f08002f301e002c000b00454449440700436c616d303100'
        '4f424e440c00eeffe8fffeff12001800210046554c4c04001fdc00004d4f444c1200506c61'
        '6e74735c436c616d30312e6e6966004d4f44543c00020000000400000000000000aa2dbb27'
        '64647300f64c4bb969221e8664647300f64c4bb9b807509764647300262c333bd373171f64'
        '647300f64c4bb9504e414d040000000000524e414d0400dc070100464e414d020000005046'
        '4947040003ba0e00534e414d04002605100050465043040064646464')
    clam = Rec(b'FLOR', 0, 0x85F80, clam_raw[16:24], clam_raw[24:])

    pole_crude = clone(misc_src, POLE_CRUDE, 'ThornswoodMiscPoleCrude', sets={
        b'FULL': zstr('Crude Fishing Pole'),
        b'DATA': struct.pack('<If', 25, 1.0),
    })
    pole_fine = clone(misc_src, POLE_FINE, 'ThornswoodMiscPoleFine', sets={
        b'FULL': zstr('Fine Fishing Pole'),
        b'DATA': struct.pack('<If', 80, 1.0),
    })
    pole_master = clone(misc_src, POLE_MASTER, 'ThornswoodMiscPoleMaster', sets={
        b'FULL': zstr('Master Fishing Pole'),
        b'DATA': struct.pack('<If', 200, 1.0),
    })
    fish_trap = clone(misc_src, FISH_TRAP, 'ThornswoodMiscFishTrap', sets={
        b'FULL': zstr('Fish Trap'),
        b'DATA': struct.pack('<If', 10, 0.5),
    })
    make_pole_crude = clone(cobj_charcoal, RECIPE_POLE_CRUDE, 'ThornswoodRecipePoleCrude', sets={
        b'CNAM': struct.pack('<I', POLE_CRUDE),
        b'BNAM': struct.pack('<I', WOODWORKING_KEYWORD),
    })
    set_inputs(make_pole_crude, [(FIREWOOD, 2), (LEATHER_STRIPS, 1), (TUNDRA_COTTON, 2)])
    make_pole_fine = clone(cobj_charcoal, RECIPE_POLE_FINE, 'ThornswoodRecipePoleFine', sets={
        b'CNAM': struct.pack('<I', POLE_FINE),
        b'BNAM': struct.pack('<I', WOODWORKING_KEYWORD),
    })
    set_inputs(make_pole_fine, [(FIREWOOD, 2), (LEATHER_STRIPS, 1), (STEEL_INGOT, 1), (TUNDRA_COTTON, 3)])
    make_pole_master = clone(cobj_charcoal, RECIPE_POLE_MASTER, 'ThornswoodRecipePoleMaster', sets={
        b'CNAM': struct.pack('<I', POLE_MASTER),
        b'BNAM': struct.pack('<I', WOODWORKING_KEYWORD),
    })
    set_inputs(make_pole_master, [
        (FIREWOOD, 3), (LEATHER_STRIPS, 2), (STEEL_INGOT, 1), (REFINED_MOONSTONE, 1)])
    make_trap = clone(cobj_charcoal, RECIPE_TRAP, 'ThornswoodRecipeFishTrap', sets={
        b'CNAM': struct.pack('<I', FISH_TRAP),
        b'BNAM': struct.pack('<I', WOODWORKING_KEYWORD),
    })
    set_inputs(make_trap, [(FIREWOOD, 3), (LEATHER_STRIPS, 2), (IRON_INGOT, 1)])

    def catch(fid, edid, name, produce):
        return clone(clam, fid, edid, sets={
            b'FULL': zstr(name),
            b'PFIG': struct.pack('<I', produce),
        })

    catch_histcarp = catch(CATCH_HISTCARP, 'ThornswoodFishHistcarp', 'Histcarp', HISTCARP)
    catch_betty = catch(CATCH_RIVER_BETTY, 'ThornswoodFishRiverBetty', 'River Betty', RIVER_BETTY)
    catch_scales = catch(CATCH_SCALES, 'ThornswoodFishSlaughterfishScales', 'Slaughterfish Scales', SLAUGHTERFISH_SCALES)
    catch_perch = catch(CATCH_PERCH, 'ThornswoodFishSilversidePerch', 'Silverside Perch', SILVERSIDE_PERCH)
    catch_spadetail = catch(CATCH_SPADETAIL, 'ThornswoodFishCyrodilicSpadetail', 'Cyrodilic Spadetail', CYRODILIC_SPADETAIL)
    catch_longfin = catch(CATCH_LONGFIN, 'ThornswoodFishAbeceanLongfin', 'Abecean Longfin', ABECEAN_LONGFIN)

    # The three repair kits (#1384), and what makes each. See the top.
    weapon_kit = clone(misc_src, WEAPON_KIT, 'ThornswoodMiscWeaponKit', sets={
        b'FULL': zstr('Weapon Kit'),
        b'DATA': struct.pack('<If', METAL_KIT_VALUE, METAL_KIT_WEIGHT),
    })
    armor_kit = clone(misc_src, ARMOR_KIT, 'ThornswoodMiscArmorKit', sets={
        b'FULL': zstr('Armor Kit'),
        b'DATA': struct.pack('<If', METAL_KIT_VALUE, METAL_KIT_WEIGHT),
    })
    sewing_kit = clone(misc_src, SEWING_KIT, 'ThornswoodMiscSewingKit', sets={
        b'FULL': zstr('Sewing Kit'),
        b'DATA': struct.pack('<If', SEWING_KIT_VALUE, SEWING_KIT_WEIGHT),
    })
    make_weapon_kit = clone(cobj_charcoal, RECIPE_WEAPON_KIT, 'ThornswoodRecipeWeaponKit', sets={
        b'CNAM': struct.pack('<I', WEAPON_KIT),
        b'BNAM': struct.pack('<I', FORGE_KEYWORD),
    })
    set_inputs(make_weapon_kit, [(IRON_INGOT, 1), (LEATHER_STRIPS, 1)])
    make_armor_kit = clone(cobj_charcoal, RECIPE_ARMOR_KIT, 'ThornswoodRecipeArmorKit', sets={
        b'CNAM': struct.pack('<I', ARMOR_KIT),
        b'BNAM': struct.pack('<I', FORGE_KEYWORD),
    })
    set_inputs(make_armor_kit, [(IRON_INGOT, 1), (LEATHER, 1)])
    make_sewing_kit = clone(cobj_charcoal, RECIPE_SEWING_KIT, 'ThornswoodRecipeSewingKit', sets={
        b'CNAM': struct.pack('<I', SEWING_KIT),
        b'BNAM': struct.pack('<I', TANNING_KEYWORD),
    })
    set_inputs(make_sewing_kit, [(TUNDRA_COTTON, 1), (LEATHER_STRIPS, 1)])

    # The four treatments (#1383), and what makes each. See the top.
    def treatment(fid, edid, name, value, weight):
        return clone(misc_src, fid, edid, sets={
            b'FULL': zstr(name),
            b'DATA': struct.pack('<If', value, weight),
        })

    def recipe(fid, edid, out, bench, inputs):
        r = clone(cobj_charcoal, fid, edid, sets={
            b'CNAM': struct.pack('<I', out),
            b'BNAM': struct.pack('<I', bench),
        })
        set_inputs(r, inputs)
        return r

    bandage = treatment(BANDAGE, 'ThornswoodMiscBandage', 'Bandage', BANDAGE_VALUE, BANDAGE_WEIGHT)
    splint = treatment(SPLINT, 'ThornswoodMiscSplint', 'Splint', SPLINT_VALUE, SPLINT_WEIGHT)
    poultice = treatment(POULTICE, 'ThornswoodMiscPoultice', 'Poultice', POULTICE_VALUE, POULTICE_WEIGHT)
    remedy = treatment(REMEDY, 'ThornswoodMiscRemedy', "Physicker's Remedy", REMEDY_VALUE, REMEDY_WEIGHT)
    make_bandage = recipe(RECIPE_BANDAGE, 'ThornswoodRecipeBandage', BANDAGE, LOOM_KEYWORD,
                          [(TUNDRA_COTTON, 1)])
    make_splint = recipe(RECIPE_SPLINT, 'ThornswoodRecipeSplint', SPLINT, KILN_KEYWORD,
                         [(FIREWOOD, 1), (LEATHER_STRIPS, 1)])
    make_poultice = recipe(RECIPE_POULTICE, 'ThornswoodRecipePoultice', POULTICE, ALCHEMY_KEYWORD,
                           [(TUNDRA_COTTON, 1), (GARLIC, 1)])
    make_remedy = recipe(RECIPE_REMEDY, 'ThornswoodRecipeRemedy', REMEDY, ALCHEMY_KEYWORD,
                         [(MUDCRAB_CHITIN, 1), (BLUE_MOUNTAIN_FLOWER, 1)])

    board = next((r for r in records if r.fid == BOARD and r.tag == b'ACTI'), None)
    if board is None or board.compressed or board.editor_id() != 'ThornswoodMessageBoard':
        print('')
        print('STOP. ACTI 0x%07X is not ThornswoodMessageBoard as it should be. '
              'Nothing was written.' % BOARD)
        return 1
    # The hold's drop box (#2298): an activator of its own on its own mesh,
    # cloned from the board, so E on it is the box's and never the board's.
    drop_box = clone(board, DROP_BOX, 'ThornswoodDropBox', sets={
        b'OBND': struct.pack('<6h', *DROP_BOX_BOUNDS),
        b'FULL': zstr('Drop Box'),
        b'MODL': zstr(DROP_BOX_MODEL),
    }, drop=(b'MODT',))

    # The Hearthfire house parts (#2258), overrides of a master's records. One
    # already in this plugin is edited where it is; one that is not is copied
    # in from HearthFires.esm. See the top.
    plugin_masters = masters_of(raw)
    house_new, house_have = [], []
    for fid, edid in HOUSE_PARTS:
        have = next((r for r in records if r.fid == fid and r.tag == b'COBJ'), None)
        if have is not None:
            if have.compressed or have.editor_id() != edid:
                print('')
                print('STOP. COBJ 0x%08X in this plugin is not %s as it should be. '
                      'Nothing was written.' % (fid, edid))
                return 1
            house_have.append(have)
            continue
        if fid in taken:
            print('')
            print('STOP. 0x%08X is already taken by something that is not a recipe. '
                  'Nothing was written.' % fid)
            return 1
        made_here = from_master(args.masters, HOUSE_PARTS_MASTER, fid, plugin_masters)
        if made_here.editor_id() != edid:
            print('')
            print('STOP. %s 0x%06X is %s, not %s. Nothing was written.'
                  % (HOUSE_PARTS_MASTER, fid & 0xFFFFFF, made_here.editor_id(), edid))
            return 1
        never_listed(made_here)
        house_new.append(made_here)
    house_bare = [r for r in house_have
                  if not any(t == b'CTDA' and b == NEVER_TRUE for t, b in subrecords(r.data))]

    # Woodworking bench (#516): keyword + furniture cloned from the alchemy lab,
    # mesh and bounds from Hearthfire's carpenter workbench.
    alchemy_kw = next((r for r in records if r.fid == ALCHEMY_KEYWORD and r.tag == b'KYWD'), None)
    alchemy_furn = next((r for r in records
                         if r.fid == 0x5042E69 and r.tag == b'FURN'), None)
    if alchemy_kw is None or alchemy_kw.compressed or alchemy_kw.editor_id() != 'ThornswoodCraftingAlchemy':
        print('')
        print('STOP. KYWD 0x%07X is not ThornswoodCraftingAlchemy as it should be. '
              'Nothing was written.' % ALCHEMY_KEYWORD)
        return 1
    if (alchemy_furn is None or alchemy_furn.compressed or
            alchemy_furn.editor_id() != 'ThornswoodCraftingAlchemyWorkbench'):
        print('')
        print('STOP. FURN 0x%07X is not ThornswoodCraftingAlchemyWorkbench as it should be. '
              'Nothing was written.' % 0x5042E69)
        return 1
    old_kwda = next((b for t, b in subrecords(alchemy_furn.data) if t == b'KWDA'), None)
    if old_kwda is None:
        print('')
        print('STOP. alchemy workbench has no KWDA. Nothing was written.')
        return 1
    wood_kw = clone(alchemy_kw, WOODWORKING_KEYWORD, 'ThornswoodCraftingWoodworking')
    wood_furn = clone(alchemy_furn, WOODWORKING_BENCH, 'ThornswoodCraftingWoodworkingWorkbench',
                      sets={
                          b'FULL': zstr(WOODWORKING_FULL),
                          b'MODL': zstr(WOODWORKING_MODEL),
                          b'OBND': struct.pack('<6h', *WOODWORKING_BOUNDS),
                          b'KWDA': kwda_swap(old_kwda, ALCHEMY_KEYWORD, WOODWORKING_KEYWORD),
                          b'WBDT': b'\x01\xff',
                      }, drop=(b'MODT', b'MODS'))

    # Master recipe overrides onto the woodworking bench (#516).
    wood_new, wood_have = [], []
    for fid, edid, master in WOODWORKER_MASTER_RECIPES:
        have = next((r for r in records if r.fid == fid and r.tag == b'COBJ'), None)
        if have is not None:
            if have.compressed or have.editor_id() != edid:
                print('')
                print('STOP. COBJ 0x%08X in this plugin is not %s as it should be. '
                      'Nothing was written.' % (fid, edid))
                return 1
            wood_have.append(have)
            continue
        if fid in taken:
            print('')
            print('STOP. 0x%08X is already taken by something that is not a recipe. '
                  'Nothing was written.' % fid)
            return 1
        made_here = from_master(args.masters, master, fid, plugin_masters)
        if made_here.editor_id() != edid:
            print('')
            print('STOP. %s 0x%06X is %s, not %s. Nothing was written.'
                  % (master, fid & 0xFFFFFF, made_here.editor_id(), edid))
            return 1
        set_bnam(made_here, WOODWORKING_KEYWORD)
        wood_new.append(made_here)
    wood_bare = [r for r in wood_have
                 if not any(t == b'BNAM' and struct.unpack_from('<I', b, 0)[0] == WOODWORKING_KEYWORD
                            for t, b in subrecords(r.data))]

    print('')
    print('What goes in')
    print('  MISC 0x%07X ThornswoodMiscToolHandle      Tool Handle, %d gold, %s weight'
          % (HANDLE, HANDLE_VALUE, HANDLE_WEIGHT))
    print('  COBJ 0x%07X ThornswoodRecipeToolHandle    1 firewood -> 1 handle, at the kiln'
          % RECIPE_HANDLE)
    print('  COBJ 0x%07X ThornswoodRecipeToolShovel    1 iron ingot + 1 handle -> 1 shovel, at a forge'
          % RECIPE_SHOVEL)
    print('  BOOK 0x%07X ThornswoodBookDeed            one record, named per instance in the pack'
          % DEED)
    print('  MISC 0x%07X ThornswoodMiscKey             a key somebody can lose, so MISC and not KEYM'
          % KEY)
    print('  MISC 0x%07X ThornswoodMiscKeyMold         the mold a smith cuts keys from'
          % MOLD)
    print('  MISC 0x%07X ThornswoodMiscMasterKey       one building\'s master key, named per instance, '
          'no recipe' % MASTER_KEY)
    print('  COBJ 0x%07X ThornswoodRecipeKeyMold       1 iron ingot -> 1 blank mold, at a forge'
          % RECIPE_MOLD)
    print('  COBJ 0x%07X ThornswoodRecipeKey           1 iron ingot -> 1 key, at a forge, named '
          'by the stamped mold in the pack'
          % RECIPE_KEY)
    print('  MISC/COBJ poles and fish trap, fisher.md ingredients, no dragon bone')
    print('  FLOR ThornswoodFishHistcarp')
    print('  FLOR ThornswoodFishRiverBetty')
    print('  FLOR ThornswoodFishSlaughterfishScales')
    print('  FLOR ThornswoodFishSilversidePerch')
    print('  FLOR ThornswoodFishCyrodilicSpadetail')
    print('  FLOR ThornswoodFishAbeceanLongfin')
    print('  MISC 0x%07X ThornswoodMiscWeaponKit       Weapon Kit, %d gold, %s weight'
          % (WEAPON_KIT, METAL_KIT_VALUE, METAL_KIT_WEIGHT))
    print('  MISC 0x%07X ThornswoodMiscArmorKit        Armor Kit, %d gold, %s weight'
          % (ARMOR_KIT, METAL_KIT_VALUE, METAL_KIT_WEIGHT))
    print('  MISC 0x%07X ThornswoodMiscSewingKit       Sewing Kit, %d gold, %s weight'
          % (SEWING_KIT, SEWING_KIT_VALUE, SEWING_KIT_WEIGHT))
    print('  COBJ 0x%07X ThornswoodRecipeWeaponKit     1 iron ingot + 1 leather strips -> 1 Weapon Kit, at a forge'
          % RECIPE_WEAPON_KIT)
    print('  COBJ 0x%07X ThornswoodRecipeArmorKit      1 iron ingot + 1 leather -> 1 Armor Kit, at a forge'
          % RECIPE_ARMOR_KIT)
    print('  COBJ 0x%07X ThornswoodRecipeSewingKit     1 tundra cotton + 1 leather strips -> 1 Sewing Kit, '
          'at a tanning rack' % RECIPE_SEWING_KIT)
    print('  MISC 0x%07X ThornswoodMiscBandage         Bandage, %d gold, %s weight'
          % (BANDAGE, BANDAGE_VALUE, BANDAGE_WEIGHT))
    print('  MISC 0x%07X ThornswoodMiscSplint          Splint, %d gold, %s weight'
          % (SPLINT, SPLINT_VALUE, SPLINT_WEIGHT))
    print('  MISC 0x%07X ThornswoodMiscPoultice        Poultice, %d gold, %s weight'
          % (POULTICE, POULTICE_VALUE, POULTICE_WEIGHT))
    print("  MISC 0x%07X ThornswoodMiscRemedy          Physicker's Remedy, %d gold, %s weight"
          % (REMEDY, REMEDY_VALUE, REMEDY_WEIGHT))
    print('  COBJ 0x%07X ThornswoodRecipeBandage       1 tundra cotton -> 1 Bandage, at the loom'
          % RECIPE_BANDAGE)
    print('  COBJ 0x%07X ThornswoodRecipeSplint        1 firewood + 1 leather strips -> 1 Splint, at the kiln'
          % RECIPE_SPLINT)
    print('  COBJ 0x%07X ThornswoodRecipePoultice      1 tundra cotton + 1 garlic -> 1 Poultice, at the alchemy lab'
          % RECIPE_POULTICE)
    print("  COBJ 0x%07X ThornswoodRecipeRemedy        1 mudcrab chitin + 1 blue mountain flower -> 1 Physicker's "
          'Remedy, at the alchemy lab' % RECIPE_REMEDY)
    for r in house_new:
        print("  COBJ 0x%08X %-30s HearthFires.esm's, never listed: GetItemCount(gold) < 0"
              % (r.fid, r.editor_id()))
    print('  ACTI 0x%07X ThornswoodDropBox             the hold\'s drop box, %s'
          % (DROP_BOX, DROP_BOX_MODEL))
    print('  KYWD 0x%07X ThornswoodCraftingWoodworking  the woodworker\'s bench keyword (#516)'
          % WOODWORKING_KEYWORD)
    print('  FURN 0x%07X ThornswoodCraftingWoodworkingWorkbench  %s, mesh %s'
          % (WOODWORKING_BENCH, WOODWORKING_FULL, WOODWORKING_MODEL))
    for r in wood_new:
        print('  COBJ 0x%08X %-30s %s override, BNAM -> woodworking bench'
              % (r.fid, r.editor_id(), next(m for f, e, m in WOODWORKER_MASTER_RECIPES if f == r.fid)))
    print('')
    print('What changes')
    for r in house_bare:
        print('  COBJ 0x%08X %-30s gains the condition that is never true' % (r.fid, r.editor_id()))
    for r in wood_bare:
        print('  COBJ 0x%08X %-30s BNAM -> woodworking bench' % (r.fid, r.editor_id()))
    for fid in WOODWORKER_OWN_RECIPES:
        have = next((r for r in records if r.fid == fid and r.tag == b'COBJ'), None)
        if have is None:
            continue
        if any(t == b'BNAM' and struct.unpack_from('<I', b, 0)[0] == WOODWORKING_KEYWORD
               for t, b in subrecords(have.data)):
            continue
        print('  COBJ 0x%07X %-30s BNAM forge -> woodworking bench' % (have.fid, have.editor_id()))
    print('  ACTI 0x%07X ThornswoodMessageBoard        its mesh is %s' % (BOARD, BOARD_MODEL))
    print('  COBJ 0x%07X ThornswoodRecipeWeaponPickaxe now wants a handle as well as the ingot'
          % cobj_pickaxe.fid)
    print('  COBJ 0x%07X ThornswoodRecipeWeaponAxe     now wants a handle as well as the ingot'
          % cobj_axe.fid)
    if block_scripted:
        print('  FURN 0x%07X %s loses the script it named, which never shipped'
              % (block.fid, block.editor_id()))
    if removing:
        print('')
        print('What comes out')
    if EXECUTION_BLOCK_REF in removing:
        print('  REFR 0x%07X the Execution Block placed in Solitude' % EXECUTION_BLOCK_REF)
    if EXECUTION_BLOCK in removing:
        print('  FURN 0x%07X %s, its base, named by nothing else'
              % (EXECUTION_BLOCK, block.editor_id()))
    for r in on_block:
        print('  kept: FURN 0x%07X stays, because %s 0x%07X %s names it'
              % (EXECUTION_BLOCK, r.tag.decode(), r.fid, r.editor_id()))

    new_head, head_changed = described(head)
    print('')
    print('The header')
    if head_changed:
        print('  its description becomes: %s' % DESCRIPTION.decode('ascii'))
    else:
        print('  its description already reads as this tool writes it')

    if args.check:
        print('')
        print('  --check, so nothing was written.')
        return 0

    built = [r for r in (handle, make_handle, make_shovel, deed, key, mold,
                         make_mold, make_key,
                         pole_crude, pole_fine, pole_master, fish_trap,
                         make_pole_crude, make_pole_fine, make_pole_master, make_trap,
                         catch_histcarp, catch_betty, catch_scales, catch_perch,
                         catch_spadetail, catch_longfin,
                         weapon_kit, armor_kit, sewing_kit,
                         make_weapon_kit, make_armor_kit, make_sewing_kit,
                         bandage, splint, poultice, remedy,
                         make_bandage, make_splint, make_poultice, make_remedy,
                         drop_box, master_key, wood_kw, wood_furn)
             if r.editor_id() not in already] + house_new + wood_new
    # An edit that has already been made is not made twice. A recipe that already
    # asks for a handle would otherwise gain a second one on every run.
    edited = set()
    for rec in (cobj_pickaxe, cobj_axe):
        if any(t == b'CNTO' and len(b) >= 4 and
               struct.unpack_from('<I', b, 0)[0] == HANDLE
               for t, b in subrecords(rec.data)):
            continue
        wants_handle(rec)
        edited.add(rec.fid)
    if block is not None and EXECUTION_BLOCK not in removing and drop_script(block):
        edited.add(block.fid)
    # A house part already overridden here keeps or gains the condition (#2258).
    for r in house_have:
        if never_listed(r):
            edited.add(r.fid)
    # Woodworking bench overrides and our poles/trap (#516).
    for r in wood_have:
        if set_bnam(r, WOODWORKING_KEYWORD):
            edited.add(r.fid)
    for fid in WOODWORKER_OWN_RECIPES:
        have = next((r for r in records if r.fid == fid and r.tag == b'COBJ'), None)
        if have is not None and set_bnam(have, WOODWORKING_KEYWORD):
            edited.add(have.fid)
    # A key and a mold already in the plugin get their own meshes (#2255).
    for name, model in (('ThornswoodMiscKey', KEY_MODEL), ('ThornswoodMiscKeyMold', MOLD_MODEL)):
        if name in already and set_model(by_edid[name], model):
            edited.add(by_edid[name].fid)
    # The notice board's own mesh and its bounds (#2298).
    board_moved = set_model(board, BOARD_MODEL)
    if set_bounds(board, BOARD_BOUNDS) or board_moved:
        edited.add(board.fid)
    if not built and not edited and not removing and not head_changed:
        print('')
        print('  Everything this adds is already in the plugin. Nothing was written.')
        return 0
    old_head = bytes(head)
    head = new_head
    tree = take_out(tree, removing)
    for r in built:
        ensure_top_group(tree, r.tag).kids.append(r)
    kept = [r for r in records if r.fid not in removing]

    # The header's record count, which sits in HEDR after the version float.
    #
    # IT IS SET TO THE TRUE COUNT RATHER THAN ADDED TO, because the number in
    # the file is wrong and has been for as long as this repo has had the file.
    # Measured 21 September across three copies: before the conditions edit,
    # before the manual trim, and after, the header said 408 every time, while
    # the file actually held 392, 392 and 376. So neither the editor id rename
    # of 21 September nor Remove-DeadRecords.ps1 has ever touched it,
    # and the plugin has been shipping and working at 408 against 392, which is
    # the evidence that the engine does not read it. Adding three to a wrong
    # number would keep it wrong; this writes what is actually there.
    hedr = head.find(b'HEDR')
    if hedr < 0:
        print('STOP. no HEDR in the header. Nothing was written.')
        return 1
    claimed = struct.unpack_from('<i', head, hedr + 6 + 4)[0]
    struct.pack_into('<i', head, hedr + 6 + 4, len(kept) + len(built))
    if claimed != len(records):
        print('')
        print('The header record count was wrong before this ran')
        print('  it said %d and the file held %d. Setting it to %d.'
              % (claimed, len(records), len(kept) + len(built)))

    out = bytes(head) + b''.join(k.bytes() for k in tree)

    print('')
    print('Does the result verify')
    after_records = list(every_record(parse(out, len(head), len(out))))
    # The header: the other server's name and short forms nowhere in it, and
    # nothing changed but the description and the record count.
    out_head = out[:len(head)]
    if other_server_in_header(out_head):
        print('  STOP. the header still carries the other server\'s name or a short form of it. '
              'Nothing was written.')
        return 1
    def header_rest(h):
        return [(t, b) for t, b in subrecords(h[24:]) if t not in (b'SNAM', b'HEDR')]
    if header_rest(out_head) != header_rest(old_head) or out_head[8:24] != old_head[8:24]:
        print('  STOP. the header changed in more than its description and record count. '
              'Nothing was written.')
        return 1
    if struct.unpack_from('<I', out_head, 4)[0] != len(out_head) - 24:
        print('  STOP. the header\'s size field does not match the header. Nothing was written.')
        return 1
    if len(after_records) != len(kept) + len(built):
        print('  STOP. %d records in, %d out, expected %d. Nothing was written.'
              % (len(records), len(after_records), len(kept) + len(built)))
        return 1
    back = [r for r in after_records if r.fid in removing]
    if back:
        print('  STOP. 0x%07X was to come out and is still there. Nothing was written.'
              % back[0].fid)
        return 1
    added = set(r.fid for r in built)
    seen = []
    for r in after_records:
        if r.fid in added:
            continue
        seen.append(r)
    for was_r, now in zip(kept, seen):
        if was_r.fid != now.fid or was_r.tag != now.tag or was_r.flags != now.flags:
            print('  STOP. 0x%07X changed identity. Nothing was written.' % was_r.fid)
            return 1
        if now.fid not in edited and now.data != before[was_r.fid]:
            print('  STOP. 0x%07X was not on the list and its bytes changed. '
                  'Nothing was written.' % now.fid)
            return 1
    made = dict((r.fid, r) for r in after_records if r.fid in added)
    for b in built:
        if made[b.fid].data != b.data:
            print('  STOP. 0x%07X did not come back as it was built. Nothing was written.'
                  % b.fid)
            return 1
    if block is not None and block.fid in edited:
        now = next(r for r in after_records if r.fid == block.fid)
        want = [(t, b) for t, b in subrecords(before[block.fid]) if t != b'VMAD']
        if subrecords(now.data) != want:
            print('  STOP. 0x%07X lost more than its script. Nothing was written.' % block.fid)
            return 1
    left = [(r, w) for r in after_records for w in other_server_names(r)]
    if left:
        for r, w in left:
            print('  STOP. %s 0x%07X still carries the other server\'s name: %s'
                  % (r.tag.decode(), r.fid, w))
        print('  Nothing was written.')
        return 1
    count = struct.unpack_from('<i', out, hedr + 6 + 4)[0]
    if count != len(after_records):
        print('  STOP. the header says %d records and there are %d. Nothing was written.'
              % (count, len(after_records)))
        return 1
    print('  ok    %d records in, %d out, same order, same ids, same flags'
          % (len(records), len(after_records)))
    print('  ok    %d added, %d edited, %d taken out, every other byte untouched'
          % (len(built), len(edited), len(removing)))
    print('  ok    the header record count reads %d, which is what is in the file' % count)
    print('  ok    no record carries the other server\'s name or its short forms, '
          'compressed ones included')
    print('  ok    the header carries Thornswood\'s description and not that name, '
          'and nothing else in it moved')

    open(path, 'wb').write(out)
    print('')
    print('  %s bytes -> %s bytes' % (format(len(raw), ','), format(len(out), ',')))
    print('  THIS IS A SHIPPED FILE. Its size changed, so this needs a release and')
    print('  every client will download it again.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
