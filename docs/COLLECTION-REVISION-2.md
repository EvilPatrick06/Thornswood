# Collection revision 2: the Vortex pass

One pass in Vortex on the shipping machine, in the Thornswood profile, then
one upload to Nexus. It carries five changes to the Thornswood collection
(`7essxf`) and fixes its plugin order so that a clean install lands exactly
where the server expects. Every step here is done by hand in Vortex or on
Nexus; nothing in the repository does them.

Measured on 29 September against revision 1 (the only published revision,
27 September, 113 mods) and both servers' manifests. Live and dev hand out
the same 48 plugins in the same order, byte for byte the same manifest, and
the built server settings on the shipping machine say the same.

What a clean install of revision 1 gets wrong today:

- It installs Elysium Estate 5.0.1, whose plugin is `ElysiumEstate.esp`. The
  server loads `ElysiumEstateSSE.esp`, which only Elysium Estate 4.3.5 has.
  The launcher carries that file itself for now (`game\required-data`,
  issue #690), so nobody is locked out, but the collection is wrong.
- It switches on `CBBE.esp`, a full plugin the server does not load. One
  extra full plugin moves every plugin after it by one place.
- Its rules leave two gaps, so LOOT may put Elysium Estate anywhere among
  positions 9 to 21, and may mix the plugins from AHZmoreHUD down with the
  ones from Thornswood-Content.esp to Immersive Patrols II.
- A rule in this machine's Vortex, "ElysiumEstateSSE.esp loads after
  Immersive Patrols II.esp", goes round in a circle with the rest of the
  chain. Revision 1 left it out only because no mod in it had that plugin.
  Once Elysium Estate 4.3.5 is in, the upload would carry it and LOOT would
  refuse to sort anybody's list. Step 6 replaces it.

## Before you start

- Vortex open, the Thornswood profile active.
- The rebuilt `Thornswood-Content.esp` from step 3 ready, or step 3 done first.
- None of this changes the server's order, so no world wipe, no
  `Sync-LoadOrder.ps1`, and nobody needs a new character.

## 1. The covered body (#405)

Nobody can be seen nude, men or women, people or NPCs. The female body
becomes the covered CBBE body that is already in the collection.

1. Mods page, **CBBE 3BA (3BBB) 2.48**: Reinstall.
2. First page, "CBBE 3BA Base": keep "Base install" and "Nevernude", untick
   **"Pre-built Body mesh"**.
3. Every later page as it was, except the bounce pages if you are doing
   step 4: then leave the CBPC pages unticked.
4. Deploy. Vortex should report no file conflict on `femalebody_0.nif` or
   `femalebody_1.nif` any more.
5. Check, read only: `.\scripts\mods\Check-CoveredBodies.ps1` should end
   "Every body is covered".
6. Collections, Thornswood, Mods tab: CBBE 3BA (3BBB) installs with "Same
   Installer Choices", so everybody gets the new choices.

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

## 4. The bounce physics come out (#993, optional)

The launcher already keeps the physics out of its own game folder, so this is
tidying. Neither has a plugin.

1. Mods page: disable **CBPC - Physics with Collisions** (Nexus 21224, the
   main file) and its **3B Breast-Butt Bounce Configs** file.

## 5. Elysium Estate: the file the server loads (#690)

The collection installs Elysium Estate 5.0.1 (Nexus file 45193), whose
plugin is `ElysiumEstate.esp`, 956,423 bytes. The server loads
`ElysiumEstateSSE.esp`, 980,322 bytes, and the only Elysium Estate file with
that plugin is 4.3.5 (Nexus file 24701, under Old files; Nexus's own file
preview lists `Data/ElysiumEstateSSE.esp`, 980.3 kB). Going back to 4.3.5
keeps the world as it is. Moving the server to 5.0.1 instead would change
the plugin every saved Elysium Estate record points into.

1. Mods page, **Elysium Estate** (the entry reads 4.3.5, and it is really
   5.0.1): Remove, and let Vortex delete its files.
2. Nexus, Elysium Estate (mod 4119), Files, Old files, **Elysium Estate
   4.3.5**: Mod Manager Download, then install and enable it.
3. Deploy. If Vortex says `ElysiumEstateSSE.esp` in Data was put there
   outside Vortex (the hand copy from 27 September), let Vortex's copy win;
   it is the same file.
4. Plugins page: `ElysiumEstate.esp` is gone and `ElysiumEstateSSE.esp` is
   there and switched on.

Once revision 2 is live, `game\required-data\ElysiumEstateSSE.esp` can come
out of the repository (#690).

## 6. The plugin order

Three changes on the Plugins page. For each, click the plugin, and in its
details on the right use **Load After** (the same rules show under the
plugin's Dependencies column).

| Plugin | Rule to remove | Rule to add |
| --- | --- | --- |
| ElysiumEstateSSE.esp | load after Immersive Patrols II.esp | load after aaaGraniteHill.esp |
| AHZmoreHUD.esp | none | load after Immersive Patrols II.esp |

And switch **CBBE.esp** off. It is not on the server, no plugin in the game
names it as a master, and its own description says it only adds a rim light
texture to vanilla outfits.

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
| 22 | ElysiumEstateSSE.esp | **Change.** From Elysium Estate 4.3.5 (step 5). Loads after aaaGraniteHill.esp and nothing else. |
| 23 | Triumvirate - Mage Archetypes.esp | Keep. |
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

Proved before writing this: revision 1's rules with these two changes, read
against this machine's own list by `Check-CollectionRules.ps1`, hold every
one of the 42 pairs of neighbouring full plugins, where revision 1 alone
leaves two free.

Six links of the chain pass through light plugins (LSFX-SSE-Audiosettings,
MoreCraftableEquipment, the three RaceMenu plugins, XPMSE, DeadlySpellImpacts,
BetterContainerControls and SkyHUD). They hold while those stay in the
collection. If one of them ever comes out, give the plugin after the gap a
rule straight onto the plugin before it in the table above;
`Check-CollectionRules.ps1` names the exact rule.

## 7. Check, then upload

1. `.\scripts\mods\Check-CleanInstall.ps1 -Server dev`. It reads the plugin
   list Skyrim reads and the Steam copy's Data folder, and should say PASS
   (or only the step 3 line, until the dev server has the new file).
2. Collections, Thornswood, workshop: the mod list has no Start On Save, no
   CBPC if you did step 4, Elysium Estate 4.3.5, and the new Thornswood
   Content. Upload New Revision.
3. `.\scripts\mods\Check-CollectionRules.ps1` reads the upload's own copy of
   the rules against the list and should say HELD.

A note for Nexus, in the words people read: "Bodies are covered for
everybody, Start On Save is gone, Elysium Estate is the version the server
runs, and the plugin order now installs exactly as the server expects."

## 8. The proof: a clean install (#476)

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

## Keeping this page true

`tests\test-collection-revision-2.ps1` reads the table above against both
servers' manifests and the built server settings, whichever it can reach,
and fails the moment the server's order and this table part. Change the
order, change this table in the same pull request. A plugin added to the
collection later needs a rule loading it after Playable Rieklings.esp, the
end of the chain, or it floats.
