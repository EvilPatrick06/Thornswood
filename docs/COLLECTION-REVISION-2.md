# Collection revision 2: installation and shipping

Patrick published revision 2 on 3 October 2026. It uses Pandora Behaviour
Engine+ 5.0.0-beta and Dynamic FNIS AA functions 3.1.1. Runtime stays 1.0.0.
Styles of Skyrim Mashups is excluded. The remaining authoring history below
is being replaced by the published revision's verification and release steps.

Before either channel ships, close its launcher and game, refresh its own
folder from the Thornswood Vortex profile, then run
`scripts\\mods\\Build-Generated.ps1 -Root <own-install> -NoPause`.
Pandora builds with Precision and the three True Directional Movement
patches. BodySlide builds the women's NeverNude body, the men's Nevernude
body, and the collection's burned Astrid body at their recorded defaults.
The generated record must be current and `Check-CoveredBodies.ps1` must pass.
The generator refuses a Vortex deployment folder; use a separate own folder.

One pass in Vortex on the shipping machine, in the Thornswood profile, then
one upload to Nexus. It carries the changes we made after revision 1 to the
Thornswood collection (`7essxf`) and gives it the plugin rules that make a
clean install land exactly where the server expects. Every step here is done
by hand in Vortex or on Nexus; nothing in the repository does them.

## Who wins where the collection and the servers differ

Patrick, 29 September: make the servers match the published collection,
"as it was supposed to have been done already", except "for the CBBE because
we made changes to that so that doesn't count and anything else we
specifically than later made changes on will overwrite what the collection
says everything else needs to adapt."

Measured on 29 September against revision 1 (the only published revision,
27 September, 113 mods), the plugins it installs on the shipping machine
(checked against the file hashes the collection itself records) and both
servers' manifests. Live and dev hand out the same 48 plugins in the same
order, byte for byte the same manifest.

| What | The collection (revision 1) | The servers until the deploy | Wins | Why |
| --- | --- | --- | --- | --- |
| Elysium Estate | 5.0.1 (Nexus file 45193), `ElysiumEstate.esp`, 956,423 bytes | 4.3.5, `ElysiumEstateSSE.esp`, 980,322 bytes, at position 22 | The collection | No decision chose 4.3.5. The server kept the plugin name from the old collection, and the hand copy of 27 September (#689) only covered for it. The servers move to 5.0.1 at the same position 22 (#690). |
| CBBE.esp | Switched on, a full plugin (10,512 bytes) | Not loaded | Ours | Patrick: the CBBE is ours. The collection switches it off (step 1). |
| The covered body (#405) | CBBE 3BA installs the pre-built body mesh, which is nude | Nobody can be seen nude | Ours | Decided 28 September. The collection changes (step 1). |
| Start On Save (#394, #490) | Installed | Taken out; the launcher already leaves it out of its game folder | Ours | It crashed a fresh install at the main menu. The collection removes it (step 2). |
| Thornswood-Content.esp (#400) | 141,442 bytes, the same file the servers load | 141,442 bytes | Ours, once rebuilt | Today they are the same file. When the plugin without the Execution Block is rebuilt, the new file goes to both (step 3). |
| The bounce physics (#993) | CBPC and its 3B bounce configs installed | No jiggle; the launcher already keeps the physics out of its game folder | Ours | Body shape is height and weight only (#1004). The collection removes them (step 4). |
| The plugin order | The order it was exported in is the server's order, position for position, once the two lines above are applied | The same order | Both agree | Nothing moves but the name at position 22. |
| The plugin rules | "Triumvirate loads after ElysiumEstateSSE.esp" names a plugin revision 1 does not have, so Elysium Estate and everything from Triumvirate to FishingInSkyrim are tied to nothing; AHZmoreHUD is not tied to Immersive Patrols II | No rules | The collection's own order | The rules are what hold the collection's order on a clean install, and these three do not (step 5). |
| The other 47 plugins | Every one the same size and crc32 as the server's | | Both agree | Measured file by file. |
| Light plugins | Anywhere LOOT puts them | Not counted | Both agree | A light plugin takes no position. |

What the dev deploy resets, which is fine during the alpha: anything the dev
world saved inside Elysium Estate. Version 5.0.1 has no guest house, no loft
and no note at the start, so the doors, buildings and names that pointed at
them are gone from the gamemode. It has its own new doors, a caretaker, a
shield, and its staff enchanter under a new record, and the gamemode knows
those instead. Every record the gamemode names in it was checked against the
collection's file.

## The server side, done in the repository (#690)

- The gamemode's tables name `ElysiumEstate.esp` and only the records it has:
  doors, buildings, water, warmth, races, hunts, harvests, benches, the cast
  and the admin names, worked out again by their own scripts against the
  collection's file. Only what the plugin changes moved; the rest of each
  table is as it was.
- The launcher links Elysium Estate by its new plugin name.
- `game\required-data` no longer carries `ElysiumEstateSSE.esp`, and every
  pack deletes that file, so nobody keeps the old plugin in their game folder.
- The order table below and `tests\test-collection-revision-2.ps1` hold
  `ElysiumEstate.esp` at position 22.

The deploy that moves the servers is in "Moving the servers" at the end.

## Before you start

- Vortex open, the Thornswood profile active.
- The rebuilt `Thornswood-Content.esp` from step 3 ready, or step 3 done first.
- The dev server already runs `ElysiumEstate.esp` ("Moving the servers"),
  or the check in step 6 names it until it does.

## 1. The covered body and CBBE.esp (#405)

Nobody can be seen nude, men or women, people or NPCs. The female body
becomes the covered CBBE body that is already in the collection.

1. Mods page, **CBBE 3BA (3BBB) 2.48**: Reinstall.
2. First page, "CBBE 3BA Base": keep "Base install" and "Nevernude", untick
   **"Pre-built Body mesh"**.
3. Every later page as it was, leaving the CBPC pages unticked (step 4).
4. Deploy. Vortex should report no file conflict on `femalebody_0.nif` or
   `femalebody_1.nif` any more.
5. Check, read only: `.\scripts\mods\Check-CoveredBodies.ps1` should end
   "Every body is covered".
6. Collections, Thornswood, Mods tab: CBBE 3BA (3BBB) installs with "Same
   Installer Choices", so everybody gets the new choices.
7. Plugins page: **CBBE.esp** switched off. It is not on the server, no plugin
   in the game names it as a master, and its own description says it only
   adds a rim light texture to vanilla outfits.

## 2. Start On Save comes out (#394, #490)

It never loads a save for Thornswood and could crash a fresh install at the
main menu. It has no plugin, so the order does not move.

1. Mods page, **Start On Save** 2.8.0 (Nexus mod 50054): Remove, and let
   Vortex delete its files.

## 3. Thornswood-Content.esp without the Execution Block (#400)

The rebuilt plugin, with the other server's Execution Block and its script
taken out of Solitude. Same name, same place in the order (position 31), new
bytes.

1. Build it from the repository as #400 says (`python
   scripts/mods/Add-ContentRecords.py`, then `node tests/test-content-names.js`),
   and commit it with its new size in `THIRD-PARTY.md`.
2. Upload that file to the Thornswood Content mod on Nexus (mod 192001) as a
   new version, and update the mod to it in Vortex.
3. Deploy both servers with the same file, dev first
   (`.\scripts\deploy\Deploy-DevGamemode.ps1`). Until the server has it, the
   check at the end names this one file as a wrong file, and that is
   expected.

## 4. The bounce physics come out (#993)

The launcher already keeps the physics out of its own game folder, so a clean
install through the launcher has none. The collection still installs them,
and this takes them out. Neither has a plugin.

1. Mods page: remove **CBPC - Physics with Collisions** (Nexus 21224, the
   main file) and its **3B Breast-Butt Bounce Configs** file.

## 5. Elysium Estate stays 5.0.1, and the plugin rules

Elysium Estate stays the version the collection installs, 5.0.1 (Nexus file
45193), whose plugin is `ElysiumEstate.esp`. Nothing to download.

1. Plugins page: **ElysiumEstate.esp** switched on. On the shipping machine
   it has been switched off since 27 September, when the old plugin was
   copied in by hand; an upload with it off would ship it off.
2. If `ElysiumEstateSSE.esp` shows on the Plugins page, it is the hand copy of
   27 September. Switch it off and delete the file from the Steam copy's
   Data folder; no mod in the collection has it.
3. The rules. For each plugin in the table, click it, and in its details on
   the right use **Load After** (the same rules show under the plugin's
   Dependencies column).

| Plugin | Rule to remove | Rule to add |
| --- | --- | --- |
| ElysiumEstate.esp | none | load after aaaGraniteHill.esp |
| Triumvirate - Mage Archetypes.esp | load after ElysiumEstateSSE.esp | load after ElysiumEstate.esp |
| AHZmoreHUD.esp | none | load after Immersive Patrols II.esp |

4. On the shipping machine Vortex also holds "ElysiumEstateSSE.esp loads after
   Immersive Patrols II.esp". Remove it too: it goes round in a circle with
   the rest of the chain, and LOOT refuses to sort anybody's list the day a
   plugin of that name turns up again.

Then Sort Now and Deploy. Every full plugin must then sit in exactly this
order. Light plugins are left out of this table because they take no
position, so LOOT may put them anywhere.

<!-- order:start -->
| Position | Plugin | What to do |
| --- | --- | --- |
| 1 | Skyrim.esm | The game loads the five base masters itself. |
| 2 | Update.esm | Base master. |
| 3 | Dawnguard.esm | Base master. |
| 4 | HearthFires.esm | Base master. |
| 5 | Dragonborn.esm | Base master. |
| 6 | Water for ENB.esm | Keep. |
| 7 | Embers XD.esm | Keep. |
| 8 | RaceCompatibility.esm | Keep. |
| 9 | Immersive Sounds - Compendium.esp | Keep. |
| 10 | IcePenguinWorldMap.esp | Keep. |
| 11 | JKs Skyrim.esp | Keep. |
| 12 | WindhelmSSE.esp | Keep. |
| 13 | CWE - JK - United.esp | Keep. |
| 14 | JK's Whiterun's Outskirts.esp | Keep. |
| 15 | The Great City of Solitude.esp | Keep. |
| 16 | Embers XD.esp | Keep. |
| 17 | Riften Expansion.esp | Keep. |
| 18 | Odin - Skyrim Magic Overhaul.esp | Keep. |
| 19 | Hothtrooper44_ArmorCompilation.esp | Keep. |
| 20 | AnotherOakwood.esp | Keep. |
| 21 | aaaGraniteHill.esp | Keep. |
| 22 | ElysiumEstate.esp | **Switch on** (step 5). Elysium Estate 5.0.1, as the collection installs it; loads after aaaGraniteHill.esp. The servers had ElysiumEstateSSE.esp here until the deploy. |
| 23 | Triumvirate - Mage Archetypes.esp | **Change.** Loads after ElysiumEstate.esp. |
| 24 | Apocalypse - Magic of Skyrim.esp | Keep. |
| 25 | CommonClothes.esp | Keep. |
| 26 | Cloaks&Capes.esp | Keep. |
| 27 | UIExtensions.esp | Keep. |
| 28 | chfshVariousActions.esp | Keep. |
| 29 | Cathedral Weathers.esp | Keep. |
| 30 | FishingInSkyrim.esp | Keep. |
| 31 | Thornswood-Content.esp | **New file** (step 3). Same place. |
| 32 | Populated Cities Towns Villages Legendary.esp | Keep. |
| 33 | SkyrimSewers.esp | Keep. |
| 34 | Solitude Arena.esp | Keep. |
| 35 | ZIA_Complete Pack.esp | Keep. |
| 36 | CFTO.esp | Keep. |
| 37 | Arena - Markarth Side.esp | Keep. |
| 38 | Immersive Weapons.esp | Keep. |
| 39 | DIS_Heavy_Legion.esp | Keep. |
| 40 | OarsRest.esp | Keep. |
| 41 | North Keep.esp | Keep. |
| 42 | Immersive Patrols II.esp | Keep. |
| 43 | AHZmoreHUD.esp | **Change.** Add: loads after Immersive Patrols II.esp. |
| 44 | HappyLittleTrees.esp | Keep. |
| 45 | PlayFluteLuteDrum.esp | Keep. |
| 46 | Skyrim Unbound.esp | Keep. |
| 47 | Water for ENB (Shades of Skyrim).esp | Keep. |
| 48 | Playable Rieklings.esp | Keep. |
<!-- order:end -->

Proved before writing this: revision 1's own rules, read against this order
by `Check-CollectionRules.ps1`, leave ElysiumEstate.esp named by no rule and
two pairs free (aaaGraniteHill.esp then Triumvirate, Immersive Patrols II.esp
then AHZmoreHUD.esp). With the three changes above they hold all 42 pairs of
neighbouring full plugins.

Six links of the chain pass through light plugins (LSFX-SSE-Audiosettings,
MoreCraftableEquipment, the three RaceMenu plugins, XPMSE, DeadlySpellImpacts,
BetterContainerControls and SkyHUD). They hold while those stay in the
collection. If one of them ever comes out, give the plugin after the gap a
rule straight onto the plugin before it in the table above;
`Check-CollectionRules.ps1` names the exact rule.

## 6. Check, then upload

1. `.\scripts\mods\Check-CleanInstall.ps1 -Server dev`. It reads the plugin
   list Skyrim reads and the Steam copy's Data folder, and should say PASS
   (or only the step 3 line, until the dev server has the new file).
2. Collections, Thornswood, workshop: the mod list has no Start On Save, no
   CBPC, Elysium Estate 5.0.1, and the new Thornswood Content. Upload New
   Revision.
3. `.\scripts\mods\Check-CollectionRules.ps1` reads the upload's own copy of
   the rules against the list and should say HELD.

A note for Nexus, in the words people read: "Bodies are covered for
everybody, Start On Save and the bounce physics are gone, and the plugin
order now installs exactly as the server expects."

## 7. The proof: a clean install (#476)

1. Vortex, Profiles: add a new profile ("Clean check"), switch to it.
2. Install the Thornswood collection, revision 2, from Nexus. Leave **"Skip
   plugin rules" off**. Deploy, and Sort if Vortex offers it. Do not drag
   anything on the Plugins page.
3. `.\scripts\mods\Check-CleanInstall.ps1 -Server dev`, and once live has
   been deployed, `.\scripts\mods\Check-CleanInstall.ps1`.
4. PASS on each closes #476. Anything else prints one line per difference,
   saying which plugin, where, and what to do. A Skyrim with the Anniversary
   upgrade passes too: none of the 48 needs it (#479), and its Creation Club
   plugins are not counted, because Thornswood's own game folder leaves them
   out.
5. Switch back to the Thornswood profile.

## Other people's loose files: what the collection takes over (#1178)

Measured on 29 September: the installer, the dev build, the dev record
`20260929-140118-dev` and the last main record carried 424 loose files of
other people's mods (124.7 MB) as if they were Thornswood's. Each was matched
by path and file hash against every mod in this machine's Vortex, loose and
inside its archives, and against the game's own archives; the rest were traced
by path against each mod's file list on Nexus. Patrick, 29 September: anything
on Nexus goes into the collection, anything else is dropped from our packs and
the installer.

Since #1178 `scripts\release\Ship-Rules.ps1` names what is Thornswood's
outside `Data\Platform` and nothing else ships (`Test-ShipNotOurs`). The rows
marked **Held** still ship until a release is built against revision 2 of the
collection, then leave by themselves. The rows marked **Ours for now (#1259)**
are the 140 outfit meshes built in BodySlide on some other machine: Patrick,
29 September, Thornswood builds the outfits itself from the collection's
BodySlide projects (#1259), and until that build replaces them they keep
shipping so nothing looks broken (`scripts\release\built-until-1259.txt`
lists them). Nothing here is deleted from anybody's game.

<!-- loose:start -->
| Files | Count | Where they come from | What happens |
| --- | --- | --- | --- |
| RaceMenu's menus and translations (`Interface\racesex_menu.swf`, `racemenu\`, `vr\`, `Translations\racemenu_*`) | 18 | RaceMenu (19080), in the collection: the same bytes are inside its RaceMenu.bsa | Out now; the collection installs them |
| Travel clothes, the same bytes as Common Clothes' archive | 30 | Common Clothes (5063), in the collection | Out now; the collection installs them |
| Skyrim Sewers' countess dress, an Elysium Estate book texture | 2 | Skyrim Sewers (9320), Elysium Estate (4119), in the collection, same bytes | Out now |
| Male face expressions and beards (`character assets\MaleHead.tri`, `EyesMale.tri`, `faceparts\`, `mouth\`, `beards\`) | 77 | Expressive Facial Animation - Male Edition (19532) | **Held**: revision 2 adds the mod |
| Fitted vanilla hoods, and the fishing and apprentice robes (`clothes\robemythicdawn\`, `clothes\thalmor\`, `creationclub\bgssse001\clothes\`) | 14 | CBBE 3BA Vanilla Outfits Redone (109194), its prebuilt meshes | **Held**: revision 2 adds the mod |
| Children's clothes (`clothes\childrenclothes\`, `_byoh\clothes\childrenclothesvariants\`) | 10 | Styles of Skyrim Mashups - Children Clothes Variations and Mesh Fixes (154063), Vanilla Mesh Fixes Standalone | **Held**: revision 2 adds the mod |
| A noble end table (`furniture\noble\nobleendtable04.nif`) | 1 | Assorted Mesh Fixes (32117) | **Held**: revision 2 adds the mod |
| The message board Thornswood-Content.esp places (`olivar-messageboard\missiveboardcotnd.nif`, dev packs only) | 1 | No mod at this path; kept from the other server's kzolivar records | **Held**: the rebuilt Thornswood Content (step 3) must point its board at a mesh the collection installs first |
| Travel clothes built in BodySlide | 120 | Built on some other machine from Common Clothes and Armors 3BA BodySlide (83980), for a body and preset nothing records | **Ours for now (#1259)**: still ships until Thornswood builds the outfits itself from the collection's BodySlide projects |
| Bosmer armour built in BodySlide (`armor\bosmerarmormaty743\`) | 18 | Built from Immersive Armours SSE CBBE 3BA BodySlide (22382, in the collection) | **Ours for now (#1259)**, as above |
| More Craftable Equipment's executioner built in BodySlide (`MCE\clothes\executioner\f\`) | 2 | Built from its CBBE BodySlide file (44666) | **Ours for now (#1259)**, as above |
| Capital Windhelm's and Crossed Daggers' outfits, refitted (`surarmorcustommeshes\`, `clothes\saviik\`) | 15 | A refit of Capital Windhelm Expansion (42990) and The City of Crossed Daggers (168629) outfits that is not on Nexus | Out now; their own meshes, from the collection, show instead |
| Vanilla outfits refitted by nobody traced (`clothes\farmclothes03\`, `monk\`, `sheogorath\`, `dlc02\clothes\`), women's tails | 12 | Not found on Nexus | Out now |
| Leftovers nothing loads: `MCE\Clothing\`, `0CCE\`, `armor\dragon priests\`, `pulcharmsolis\`, `Armor_Replacer\` (3 files), `surwhiterunmeshes\` | 59 | Mage Clothing Expansion (128173), Common Clothing Expansion (134088), Armory of the Dragon Cult (94244), Armors of the Velothi (62752), NordwarUA's compilation (61423), Capital Whiterun Expansion (37982): none of their plugins is on the server, so nothing uses these | Out now. Adding any of them would add a plugin and move the load order |
| Bethesda's own meshes, notes and a Creation Club script, loose | 23 | The same bytes as the game's own archives | Out now; everybody's game has them |
| Scripts of mods nobody has: `IED.pex`, `MCM.pex`, `MCM_ConfigBase.pex`, `dlc1vcmoondial*.pex`, `wbptlight*.pex` | 7 | Immersive Equipment Displays (62001) without its program, an old MCM Helper that overrides the collection's newer one (53000), the Unofficial Skyrim Special Edition Patch (266) without its plugin, interior mods' light switches | Out now |
| Another server's: `weapons\kzl\kzl_haybale.nif`, `TrueHUD\RP_Bosses.ini` | 2 | Keizaal Online; the boss list's own first line says "Daedric Online boss health bars" (#1253, Patrick: it goes) | Out now |
| Retextures with no mod found: `riftencanalwood01.dds`, Windhelm wood (dev only) | 5 | Not found on Nexus | Out now |
| The Creation Kit's face tint export for FishingInSkyrim.esp | 2 | Made here by the Creation Kit; Thornswood Content already carries the `.dds` the game reads | Out now |
| Settings written on one machine: SkyUI's `config.shipped.txt` (the launcher's copy of SkyUI's own), the ImGui window files, Community Shaders' settings and ImGuiVRHelper's (neither mod is in the collection) | 6 | Written on the machine that built the pack | Out now |
<!-- loose:end -->

Thornswood's own, and still shipping: our main menu (`startmenu.swf`, the empty
`loadwaitspinner.swf`, the silent `mus_maintheme.xwm`, the backdrop), SkyHUD's
settings, the SkyMP client's files, and Nemesis's output. The saved mod menu
settings for Precision, True Directional Movement and TrueHUD
(`Data\MCM\Settings`) are Daedric Online's by their own first lines and never
ship as one machine's files (#1239). Nemesis's output is ours
because we generate it from the collection: its own record
(`Data\Nemesis_Engine\cache\mod settings`) names only Precision (72347) and
True Directional Movement (51614), both in the collection, run by Nemesis
(60033), also in it, on 10 September. No collection can run the generator.

### Mods revision 2 adds

Each is meshes only by its file list on Nexus. If Vortex shows a plugin for any
of them on the Plugins page after installing it, stop and ask Patrick: a
plugin moves the load order.

<!-- adds:start -->
| Mod | Nexus id | File to install | Replaces |
| --- | --- | --- | --- |
| Expressive Facial Animation - Male Edition | 19532 | Main file, 1.21 | The male face and beard morphs |
| CBBE 3BA Vanilla Outfits Redone | 109194 | VOR Prebuilt Meshes - Vanilla and VOR Prebuilt Meshes - CC | The fitted hoods and robes |
| Styles of Skyrim Mashups - Children Clothes Variations and Mesh Fixes | 154063 | Vanilla Mesh Fixes Standalone | The children's clothes |
| Assorted Mesh Fixes | 32117 | Main file | The noble end table |
<!-- adds:end -->

1. Nexus, each mod above: Mod Manager Download of the file named, then in
   Vortex install and enable it. Deploy.
2. Collections, Thornswood, workshop, Mods tab: each of the four is listed.
3. Check in game, before the upload, that the faces, hoods, robes and
   children's clothes look as they do today.

Not part of this revision: Thornswood building the outfits itself from the
collection's own BodySlide projects, with a recorded body and preset, and
shipping the output as ours the way Nemesis's is (#1259, Patrick's choice of
29 September). Until then the 140 built meshes above keep shipping. The
Windhelm and Riften townsfolk refits are not among them and show their mods'
own meshes.

## Moving the servers (#690)

Dev first; live only when Patrick says so. The files the dev server needs are
already on the shipping machine: Vortex has Elysium Estate 5.0.1 deployed,
and `C:\Thornswood\Game\Data\ElysiumEstate.esp` is the same 956,423 bytes
the collection records.

1. Step 5 in Vortex (switch ElysiumEstate.esp on, the three rules, Sort,
   Deploy), so the plugin list Vortex writes has it at position 22 with
   CBBE.esp off.
2. `.\scripts\deploy\Deploy-Gamemode.ps1 -Vortex -NewOrder`. It writes the
   built server's load order from that list. `-NewOrder` is needed because
   the build otherwise keeps its old list and would put a plugin it has not
   seen on the end. `pwsh -NoProfile -File .\tests\test-collection-revision-2.ps1`
   then says the built server settings are this page's order.
3. `.\scripts\deploy\Deploy-DevGamemode.ps1 -LoadOrder`. It sends
   ElysiumEstate.esp from `C:\Thornswood\Game\Data` and the new gamemode, and
   restarts the dev server.
4. A dev Ship, so the launcher's own plugin list names ElysiumEstate.esp and
   its game folder loses the old file.
5. `.\scripts\mods\Check-CleanInstall.ps1 -Server dev` says PASS for the
   shipping machine's list.

Live is `Deploy-Gamemode.ps1` then `Deploy-Server.ps1` and a main Ship, the
day Patrick says Main. Until then the live server keeps ElysiumEstateSSE.esp,
and the built server on the shipping machine already has the new order, so
nobody runs `Deploy-Server.ps1` before that day.

## Keeping this page true

`tests\test-collection-revision-2.ps1` reads the table above against both
servers' manifests and the built server settings, whichever it can reach,
and fails the moment the server's order and this table part. A server that
still has the plugin a row says it had "until the deploy" is a wait, not a
failure; take those words out of the row once both servers have moved.
Change the order, change this table in the same pull request. A plugin added
to the collection later needs a rule loading it after Playable Rieklings.esp,
the end of the chain, or it floats.
