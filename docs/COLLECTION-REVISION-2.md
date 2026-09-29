# Collection revision 2: the checklist

One pass in Vortex on the shipping machine, in the Thornswood profile, then
uploads to Nexus Mods: a new version of each of our two Nexus mods and
revision 2 of the Thornswood collection (`7essxf`). It is written for Claude
Cowork, the desktop agent that works on Patrick's PC, to follow step by step.
Each step says what to click or type, what the screen should show after it,
and a check to pass before the next step.

Nothing here is done by the repository, and nothing here deploys a server,
ships a release or touches the live game. Those are the last section, and they
are done afterwards by Patrick with Claude Code.

## How to use this page

- **PATRICK** on a step means Patrick does it himself: signing in to Nexus
  Mods, anything that costs money, and pressing Publish on the collection.
  Stop there, tell him what the step is, and wait.
- **COWORK** is everything else.
- Work only in Vortex's **Thornswood** profile. Never switch Vortex's game,
  never change another profile, and never remove a mod that the step does not
  name.
- A check that does not come out as written stops the pass. Write down what
  it printed and ask Patrick; do not work around it.
- Checks are PowerShell commands, run from the repository folder named in
  "Before you start". Type them exactly. They only read; none of them changes
  anything.
- Do not use Vortex's INI tweaks for anything. The Thornswood launcher gives
  the game its own settings files, so a tweak made in Vortex never reaches the
  game.

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
| CBBE.esp | Switched on, a full plugin (10,512 bytes) | Not loaded | Ours | Patrick: the CBBE is ours. The collection switches it off (step 3). |
| The covered body (#405) | CBBE 3BA installs the pre-built body mesh, which is nude | Nobody can be seen nude | Ours | Decided 28 September. The collection changes (step 2). |
| Start On Save (#394, #490) | Installed | Taken out; the launcher already leaves it out of its game folder | Ours | It crashed a fresh install at the main menu. The collection removes it (step 4). |
| The bounce physics (#993) | CBPC and its 3B bounce configs installed | No jiggle; the launcher already keeps the physics out of its game folder | Ours | Body shape is height and weight only (#1004). The collection removes them (step 5). |
| Thornswood-Content.esp (#400) | Thornswood Content 1.2, 141,442 bytes, the same file the servers load | 141,442 bytes | Ours, once rebuilt | The plugin without the Execution Block goes to Nexus, the collection and both servers together (step 9). |
| Other people's loose files (#1178) | Not in revision 1 | Packs, the installer and the release records carried 424 of them as ours | The collection | Patrick, 29 September: anything on Nexus goes into the collection, anything else is dropped from our packs. Four mods come in (step 11); the rest never ship again. |
| Thornswood Client Runtime (#421) | Version 1.0, with a script nothing loads and an older licence text | Not on the servers | Ours | The next version drops the unused script and carries ICU 71's own licence (step 10). |
| The plugin order | The order it was exported in is the server's order, position for position, once the lines above are applied | The same order | Both agree | Nothing moves but the name at position 22. |
| The plugin rules | "Triumvirate loads after ElysiumEstateSSE.esp" names a plugin revision 1 does not have, so Elysium Estate and everything from Triumvirate to FishingInSkyrim are tied to nothing; AHZmoreHUD is not tied to Immersive Patrols II | No rules | The collection's own order | The rules are what hold the collection's order on a clean install, and these three do not (step 7). |
| The other 47 plugins | Every one the same size and crc32 as the server's | | Both agree | Measured file by file. |
| Light plugins | Anywhere LOOT puts them | Not counted | Both agree | A light plugin takes no position. |

What the dev deploy resets, which is fine during the alpha: anything the dev
world saved inside Elysium Estate. Version 5.0.1 has no guest house, no loft
and no note at the start, so the doors, buildings and names that pointed at
them are gone from the gamemode. It has its own new doors, a caretaker, a
shield, and its staff enchanter under a new record, and the gamemode knows
those instead. Every record the gamemode names in it was checked against the
collection's file.

## Everything that reaches a game folder outside the collection

Audited on 29 September (#476, #1152) so that this revision carries
everything that belongs in it. The dev release record the feed named that day
(`20260929-0259-dev`) lists 2,515 files as ours; the table groups them with
the installer, the packs, the launcher's own game folder rules and the scripts
that touch mods.

| Item | Reaches people through | Where it belongs | Why |
| --- | --- | --- | --- |
| Bethesda's Creation Kit (CreationKit.exe and its settings, Tools, Papyrus Compiler, lex, Data\DialogueViews, Data\Scripts.zip, three of its DLLs), SkyrimSE.exe.bak-1160-for-369 | Main and dev packs since 26 September, and every release record | Nowhere: it must go | Bethesda's files, never ours to hand out. Kept out of every pack, installer and record, and taken out of the launcher's own game folder (#1152). |
| Backups (SkyrimPlatform.ini.bak and a dated copy, VERSION.bak) and one person's RaceMenu face export | Dev packs and the record | Nowhere: they must go | One machine's files (#1152). |
| Our plugins and interface (game\plugins, game\ui), the front's build, the menu music | Packs and the installer | Ours | Our code, tied to the server's version; updates must be as fast as a release. |
| The SkyMP client runtime, the six recorded files | Packs, the installer, the feed's client runtime download | Ours | Built from our fork, checked by hash, GPL and AGPL notice. |
| The main menu backdrop (game\menu, 22 MB) | Packs and the installer | Ours for now | Could go in the Thornswood Content mod; it changes with menu work, so a pack is the faster road. |
| Elysium Estate's old plugin (game\required-data) | Packs and the installer since 27 September | The collection (5.0.1) | #1146 takes it out and every pack deletes it, held until the servers move. |
| Thornswood-Content.esp | The collection on main; dev packs carry the repository's copy for testing | The collection | Step 9 puts the rebuilt plugin in it. The dev exception stays for testing later changes. |
| Start On Save, CBPC's cbp.dll, the three RaceMenu body slider scripts | The collection; the launcher leaves them out of its folder | Out of the collection | Steps 4 and 5. The launcher rules stay: a machine a step behind must still be safe. |
| The covered female body | The collection's CBBE 3BA installer choices | The collection | Step 2. |
| Load order rules | The launcher's Fix puts plugins in the server's order | The collection's plugin rules | Step 7; the launcher keeps the check because LOOT and people can still move plugins. |
| SkyHUD's settings (skyhud.txt) | Packs | Ours for now | Could be a file in the Thornswood Content mod, like its two INIs already are; packs change it faster. Not in this revision. |
| The saved mod menu settings for Precision, True Directional Movement and TrueHUD (Data\MCM\Settings), Community Shaders' and ImGuiVRHelper's settings, TrueHUD\RP_Bosses.ini | Dev packs and the records until 29 September | Nowhere | Another server's (Daedric Online's, by their own first lines) or one machine's. No pack or record carries them since #1239 and #1253. |
| SkyrimSoulsRE and Open Animation Replacer settings | The Thornswood Content mod, and the launcher writes them on every Play | Both, as now | The mods write their own files back on exit, which is why the launcher holds them. |
| Other people's loose files, 424 of them: RaceMenu's menus, IED, MCM and other mods' loose scripts, BodySlide builds, retextures, leftovers of mods no longer installed | Packs, the installer and the records until 29 September | Their own Nexus mods through the collection, or nowhere | Traced file by file in the next section (#1178). The four mods on Nexus come in with this revision (step 11), 140 BodySlide builds stay ours until #1259, and the rest never ship again. |
| Nemesis and FNIS behaviour output | Packs | Ours | Generated for this exact mod list; a collection cannot run the generator. Where it is made from now on is #1247 (its steps go after step 11). |
| Plugins the launcher's Fix downloads from our server when a size or checksum differs | The server | The collection | Filed: the collection already pins each file; serving mod plugins ourselves is a permissions question. |
| Scripts that install or patch mods by hand (Add-Accuracy, Add-CartTravel, Add-McmShortcut, Enable-MCM, Fix-QuickLoot, Fix-MaleBody, Remove-Plugin, Set-UnboundMenu, Add-SkyrimUnbound, Fix-PluginProblems, Run-Everything, Install-Thornswood, Install-ThornswoodContent, Install-SkyMPClient) | Only if somebody runs one | The collection | Filed: each should stop at its first line the way the retired ones do. |

Could move to the collection and does in this revision: the covered body,
CBBE.esp off, Start On Save and the bounce physics out, the plugin rules, the
rebuilt Thornswood Content plugin, the new Client Runtime version. Could move
and is left for Patrick to decide later: the menu backdrop, the mod settings
files, and taking Inventory Interface Information Injector (Nexus 85702) out
of the collection (the launcher already leaves its DLL out; its plugin is
light, so the order would not move, but the next release's plugin list must
stop naming it in the same sitting).

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
| The message board Thornswood-Content.esp places (`olivar-messageboard\missiveboardcotnd.nif`, dev packs only) | 1 | No mod at this path; kept from the other server's kzolivar records | **Held**: the rebuilt Thornswood Content (step 9) must point its board at a mesh the collection installs first |
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

Not part of this revision: Thornswood building the outfits itself from the
collection's own BodySlide projects, with a recorded body and preset, and
shipping the output as ours the way Nemesis's is (#1259, Patrick's choice of
29 September). Until then the 140 built meshes above keep shipping. The
Windhelm and Riften townsfolk refits are not among them and show their mods'
own meshes.

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

1. **PATRICK**: sign in to Nexus Mods in the browser and in Vortex (Vortex,
   top right, the profile picture shows his account). Cowork cannot sign in
   for him.
2. **COWORK**: Claude Code has built the rebuilt `Thornswood-Content.esp`
   (issue #400) and says where it is and its size. Without it, do steps 1 to
   8, stop, and ask for it.
3. **COWORK**: open Windows PowerShell and go to the repository folder
   Patrick or Claude Code names for the checks. Unless told otherwise:

   ```
   cd "C:\ThornswoodTemps&Worktrees\worktrees\rev2-checklist"
   ```

   Check: `Test-Path .\scripts\mods\Check-CleanInstall.ps1` prints `True`.
4. **COWORK**: close the Thornswood launcher and the game if either is open.

## 1. Vortex on the Thornswood profile

1. Open Vortex. Left menu, **Profiles**.
2. On the **Thornswood** card, press **Enable** if it is not the active one.

After: the Thornswood card says Active, and the top bar shows Skyrim Special
Edition.

Check: left menu, **Plugins**. The list has about a hundred entries and
`Thornswood-Content.esp` is among them, switched on.

## 2. The covered body (#405)

Nobody can be seen nude, men or women, people or NPCs. The female body
becomes the covered CBBE body that is already in the collection.

1. Left menu, **Mods**. In the Name filter type `CBBE 3BA`.
2. Right click **CBBE 3BA (3BBB)** (version 2.48), choose **Reinstall**.
3. First installer page, "CBBE 3BA Base": keep **Base install** and
   **Nevernude** ticked, untick **Pre-built Body mesh**.
4. On every page about CBPC (physics), leave everything unticked. Every other
   page as it already is. Finish the installer.
5. Top bar, **Deploy Mods**.

After: Vortex reports no file conflict on `femalebody_0.nif` or
`femalebody_1.nif`.

Check:

```
pwsh -NoProfile -File .\scripts\mods\Check-CoveredBodies.ps1 -Game "C:\Program Files (x86)\Steam\steamapps\common\Skyrim Special Edition"
```

It must end `Every body is covered.` A line saying a body mesh would show
somebody nude stops the pass.

## 3. CBBE.esp off

1. Left menu, **Plugins**. Filter `CBBE`.
2. **CBBE.esp**: click its switch so it reads Disabled. Leave the mod
   installed; only the plugin goes off.

After: CBBE.esp shows Disabled. It is not on the server, no plugin names it
as a master, and it only adds a rim light texture to vanilla outfits.

Check: the Plugins page shows no warning about a missing master.

## 4. Start On Save comes out (#394, #490)

1. **Mods**, filter `Start On Save`.
2. Right click **Start On Save** (2.8.0, Nexus mod 50054), **Remove**. In the
   dialog, let Vortex remove the mod's files.
3. **Deploy Mods**.

After: the filter shows nothing. It has no plugin, so the order does not
move.

Check:

```
Test-Path "C:\Program Files (x86)\Steam\steamapps\common\Skyrim Special Edition\Data\SKSE\Plugins\po3_StartOnSave.dll"
```

prints `False`.

## 5. The bounce physics come out (#993)

1. **Mods**, filter `CBPC`.
2. Remove **CBPC - Physics with Collisions** (Nexus 21224) and its **3-Bone
   Breast Body Breast-Butt Bounce Configs** file, the same way as step 4.
3. **Deploy Mods**.

After: no mod named CBPC is left. Neither had a plugin.

Check:

```
Test-Path "C:\Program Files (x86)\Steam\steamapps\common\Skyrim Special Edition\Data\SKSE\Plugins\cbp.dll"
```

prints `False`.

## 6. Elysium Estate stays 5.0.1

Elysium Estate stays the version the collection installs, 5.0.1 (Nexus file
45193), whose plugin is `ElysiumEstate.esp`. Nothing to download.

1. **Plugins**, filter `Elysium`.
2. **ElysiumEstate.esp**: switch it on. On the shipping machine it has been
   off since 27 September, when the old plugin was copied in by hand; an
   upload with it off would ship it off.
3. If **ElysiumEstateSSE.esp** is listed, switch it off, then delete that one
   file from the Steam copy:

   ```
   Remove-Item "C:\Program Files (x86)\Steam\steamapps\common\Skyrim Special Edition\Data\ElysiumEstateSSE.esp"
   ```

   No mod in the collection has it.

After: the filter shows `ElysiumEstate.esp` enabled and no `ElysiumEstateSSE.esp`.

## 7. The plugin rules

For each plugin in the table, click it on the **Plugins** page, and in its
details on the right, under **Load After**, remove and add exactly these (the
same rules show in the plugin's Dependencies column).

| Plugin | Rule to remove | Rule to add |
| --- | --- | --- |
| ElysiumEstate.esp | none | load after aaaGraniteHill.esp |
| Triumvirate - Mage Archetypes.esp | load after ElysiumEstateSSE.esp | load after ElysiumEstate.esp |
| AHZmoreHUD.esp | none | load after Immersive Patrols II.esp |

Also remove the rule "ElysiumEstateSSE.esp loads after Immersive Patrols
II.esp" if Vortex shows it. It goes round in a circle with the rest of the
chain, and LOOT would refuse to sort anybody's list the day a plugin of that
name turns up again.

After: each of the three plugins shows only its new rule for these names.

## 8. Sort, deploy, and the order

1. **Plugins**, top bar, **Sort Now**. Then **Deploy Mods**.
2. Do not drag anything on the Plugins page.

Every full plugin must then sit in exactly this order. Light plugins are left
out of this table because they take no position, so LOOT may put them
anywhere.

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
| 22 | ElysiumEstate.esp | **Switch on** (step 6). Elysium Estate 5.0.1, as the collection installs it; loads after aaaGraniteHill.esp. The servers had ElysiumEstateSSE.esp here until the deploy. |
| 23 | Triumvirate - Mage Archetypes.esp | **Change.** Loads after ElysiumEstate.esp. |
| 24 | Apocalypse - Magic of Skyrim.esp | Keep. |
| 25 | CommonClothes.esp | Keep. |
| 26 | Cloaks&Capes.esp | Keep. |
| 27 | UIExtensions.esp | Keep. |
| 28 | chfshVariousActions.esp | Keep. |
| 29 | Cathedral Weathers.esp | Keep. |
| 30 | FishingInSkyrim.esp | Keep. |
| 31 | Thornswood-Content.esp | **New file** (step 9). Same place. |
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

Check:

```
pwsh -NoProfile -File .\scripts\mods\Check-CleanInstall.ps1 -Server dev
```

It reads the plugin list Skyrim reads and the Steam copy's Data folder against
the dev server. Until the dev server is moved (last section) it prints a line
for position 22 (the server still has ElysiumEstateSSE.esp). Any other line
stops the pass: it names the plugin, where it is, and what to do.

## 9. Thornswood Content, the rebuilt plugin (#400)

The plugin without the other server's Execution Block in Solitude. Same name,
same place in the order (position 31), new bytes. Nexus has version 1.2 today
(141,442 bytes, the same as the servers).

1. Claude Code builds it and commits it (`python
   scripts/mods/Add-ContentRecords.py`, then `node tests/test-content-names.js`),
   and gives Cowork the file and its size. Cowork does not build it.
2. **COWORK**: Vortex, **Mods**, right click **Thornswood Content**, **Open in
   File Manager**. Copy that folder to
   `C:\ThornswoodTemps&Worktrees\temp\thornswood-content-1.3`, put the new
   `Thornswood-Content.esp` over the old one in the copy, and zip the copy's
   contents (the plugin and the `meshes`, `textures` and `SKSE` folders at the
   top of the zip).
3. **COWORK**, on nexusmods.com: Skyrim Special Edition, mod 192001
   (Thornswood Content), **Manage**, **Files**, **Add a file**. Name
   Thornswood Content, version 1.3, category Main Files, description "The
   Execution Block in Solitude is gone." Move 1.2 to Old files if Nexus
   offers it. Upload and save.
4. Vortex, **Mods**, **Thornswood Content**: install the update when Vortex
   shows it (or use **Mod Manager Download** on the mod page). **Deploy
   Mods**.

After: Vortex lists Thornswood Content 1.3.

Check:

```
(Get-Item "C:\Program Files (x86)\Steam\steamapps\common\Skyrim Special Edition\Data\Thornswood-Content.esp").Length
```

prints the size Claude Code gave for the rebuilt plugin. From here the check
of step 8 also prints a wrong file line for `Thornswood-Content.esp` until the
dev server has the new file; that is expected.

## 10. Thornswood Client Runtime, the next version (#421)

1. Before anything, write down what this prints:

   ```
   (Get-ChildItem "C:\Program Files (x86)\Steam\steamapps\common\Skyrim Special Edition\Data\Platform\Distribution" -Recurse -File).Count
   ```

2. Vortex, **Mods**, right click **Thornswood Client Runtime** (1.0), **Open
   in File Manager**. Copy the whole folder to
   `C:\ThornswoodTemps&Worktrees\temp\client-runtime-1.1`.
3. In that copy:
   - delete `Platform\Distribution\___systemPolyfill.js` (nothing in the
     client loads it);
   - delete `Docs\Thornswood Client Runtime\licences\SkyrimPlatform-LICENSE.txt`
     (it covered only that script);
   - replace `Docs\Thornswood Client Runtime\README.txt` and
     `Docs\Thornswood Client Runtime\licences\ICU-LICENSE.txt` with the two
     files of the same names in
     `C:\ThornswoodTemps&Worktrees\temp\421\nexus-client-runtime`.
4. Zip the contents of the copy (the `Docs` and `Platform` folders at the top
   of the zip, not the folder around them).
5. On nexusmods.com, mod 192762 (Thornswood Client Runtime), **Manage**,
   **Files**, **Add a file**: version 1.1, Main Files, description "Licence
   texts brought up to date; one unused file removed." Move 1.0 to Old files
   if Nexus offers it. Upload and save.
6. Vortex: update Thornswood Client Runtime to 1.1, **Deploy Mods**.

After: Vortex lists Thornswood Client Runtime 1.1.

Check:

```
Test-Path "C:\Program Files (x86)\Steam\steamapps\common\Skyrim Special Edition\Data\Platform\Distribution\___systemPolyfill.js"
```

prints `False`, and the count of item 1 is one lower when run again.

## 11. Mods revision 2 adds (#1178)

Four mods whose files Thornswood's packs carried loose until now (the
**Held** rows in "Other people's loose files" above). A release built against
revision 2 stops carrying those files, so the collection must install them
first. Each is meshes only by its file list on Nexus.

<!-- adds:start -->
| Mod | Nexus id | File to install | Replaces |
| --- | --- | --- | --- |
| Expressive Facial Animation - Male Edition | 19532 | Main file, 1.21 | The male face and beard morphs |
| CBBE 3BA Vanilla Outfits Redone | 109194 | VOR Prebuilt Meshes - Vanilla and VOR Prebuilt Meshes - CC | The fitted hoods and robes |
| Styles of Skyrim Mashups - Children Clothes Variations and Mesh Fixes | 154063 | Vanilla Mesh Fixes Standalone | The children's clothes |
| Assorted Mesh Fixes | 32117 | Main file | The noble end table |
<!-- adds:end -->

1. **COWORK**: on nexusmods.com open each mod by its Nexus id
   (`https://www.nexusmods.com/skyrimspecialedition/mods/` and the id), the
   **Files** tab, and press **Mod Manager Download** on the file the table
   names. CBBE 3BA Vanilla Outfits Redone is two files. If a mod page shows a
   file of that name more than once, or no such file, stop and ask Patrick.
2. Vortex, **Mods**: each download shows as not installed. **Install**, then
   **Enable**. If an installer asks anything, stop and ask Patrick.
3. **Deploy Mods**. If Vortex reports a file conflict with another mod, stop
   and ask Patrick; do not choose a winner.
4. **Plugins**: nothing new is listed. A plugin from any of the four stops the
   pass: ask Patrick, because a plugin moves the load order.

After: the four mods show Enabled on the Mods page, and the Plugins page lists
no plugin it did not list before step 1.

Check:

```
$d = Get-Content -Raw "C:\Program Files (x86)\Steam\steamapps\common\Skyrim Special Edition\Data\vortex.deployment.json" | ConvertFrom-Json
foreach ($id in 19532, 109194, 154063, 32117) { $f = @($d.files | Where-Object { $_.source -match "-$id-" }); "{0}: {1} files, {2} plugins" -f $id, $f.Count, @($f | Where-Object { $_.relPath -match '\.es[mpl]$' }).Count }
```

Four lines, one per mod, each with more than 0 files and 0 plugins.

5. **PATRICK**, in game: the male faces and beards, the vanilla hoods, the
   fishing and apprentice robes and the children's clothes look as they did
   before this step. Cowork stops here, tells Patrick, and waits for his yes.

<!-- 1247:start -->
### Pandora and Nemesis (#1247): steps to come

**Not written yet.** The steps that make Thornswood's behaviour output
(Pandora and Nemesis) for this revision are being written under #1247 and go
here: after the mod list above is final and before the collection's mod list
is checked, so the output is made from the mods revision 2 carries. Until they
are here, **stop at this point and ask Patrick** whether this pass waits for
them.
<!-- 1247:end -->

## 12. The collection's mod list

1. Left menu, **Collections**, the **Thornswood** collection (7essxf), open it
   for editing (the workshop).
2. **Mods** tab. Check each of these and change what is not so:
   - no **Start On Save**, no **CBPC - Physics with Collisions**, no bounce
     configs (select, **Remove from collection**, if they are still listed);
   - **CBBE 3BA (3BBB)** installs with **Same Installer Choices**, so
     everybody gets the choices of step 2;
   - **Elysium Estate** is 5.0.1;
   - **Thornswood Content** is 1.3 and **Thornswood Client Runtime** is 1.1;
   - the four mods of step 11 are listed, each with the file its table names.
3. The collection's plugin rules (the **Plugins** or **Rules** tab, as this
   Vortex names it): the rules of step 7 are there.

After: the mod list matches the five points above.

Checks, all three:

```
pwsh -NoProfile -File .\scripts\mods\Check-CoveredBodies.ps1 -Game "C:\Program Files (x86)\Steam\steamapps\common\Skyrim Special Edition"
pwsh -NoProfile -File .\scripts\mods\Check-CollectionRules.ps1
pwsh -NoProfile -File .\scripts\mods\Check-CleanInstall.ps1 -Server dev
```

The first ends `Every body is covered.`, the second `HELD.`, and the third as
in steps 8 and 9.

## 13. Upload revision 2

1. **COWORK**: in the collection workshop, **Upload New Revision**. Revision
   notes, in the words people read:

   "Bodies are covered for everybody, Start On Save and the bounce physics
   are gone, the Thornswood mods are brought up to date, four mesh fixes for
   faces, hoods, robes and children's clothes come from their own mods, and
   the plugin order now installs exactly as the server expects."

2. Vortex opens the revision on nexusmods.com as a draft.
3. **PATRICK**: read the draft and press **Publish**. Nothing reaches anybody
   until he does.

After: the collection page on Nexus shows revision 2 as the latest.

## 14. The proof: a clean install (#476)

1. Vortex, **Profiles**: add a new profile named `Clean check`, switch to it.
2. Install the Thornswood collection, revision 2, from Nexus. Leave **"Skip
   plugin rules" off**. Deploy, and Sort if Vortex offers it. Do not drag
   anything on the Plugins page.
3. Run:

   ```
   pwsh -NoProfile -File .\scripts\mods\Check-CleanInstall.ps1 -Server dev
   ```

   and, once live has been deployed, the same without `-Server dev`.
4. PASS on each closes #476. Anything else prints one line per difference,
   saying which plugin, where, and what to do. A Skyrim with the Anniversary
   upgrade passes too: none of the 48 needs it (#479), and its Creation Club
   plugins are not counted, because Thornswood's own game folder leaves them
   out.
5. Switch back to the **Thornswood** profile and Deploy.

## 15. Hand back

Tell Patrick and Claude Code: the revision number Nexus shows, the new Nexus
file ids and sizes of Thornswood Content 1.3 and Thornswood Client Runtime
1.1, the four lines of step 11's check, and every check's last line. Claude
Code then updates `THIRD-PARTY.md` and the tests that name the old Client
Runtime file, and does the server steps below with Patrick. The first release
built against revision 2 stops carrying the **Held** files by itself.

After: Patrick has the revision number, the four file numbers and every
check's last line in one message.

## Moving the servers (#690)

Dev first; live only when Patrick says so. Patrick with Claude Code, not
Cowork. The files the dev server needs are already on the shipping machine:
Vortex has Elysium Estate 5.0.1 deployed, and
`C:\Thornswood\Game\Data\ElysiumEstate.esp` is the same 956,423 bytes the
collection records.

1. Steps 6 to 8 in Vortex (switch ElysiumEstate.esp on, the three rules,
   Sort, Deploy), so the plugin list Vortex writes has it at position 22 with
   CBBE.esp off.
2. Merge #1146, then `.\scripts\deploy\Deploy-Gamemode.ps1 -Vortex -NewOrder`.
   It writes the built server's load order from that list. `-NewOrder` is
   needed because the build otherwise keeps its old list and would put a
   plugin it has not seen on the end.
   `pwsh -NoProfile -File .\tests\test-collection-revision-2.ps1` then says the
   built server settings are this page's order.
3. `.\scripts\deploy\Deploy-DevGamemode.ps1 -LoadOrder`. It sends
   ElysiumEstate.esp from `C:\Thornswood\Game\Data` and the new gamemode, and
   restarts the dev server.
4. A dev Ship, so the launcher's own plugin list names ElysiumEstate.esp, its
   game folder loses the old file, and the feed records the collection
   revision Vortex has.
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
