# Collection revision 3: the Unofficial Skyrim Special Edition Patch

Issue #1262. Patrick, 29 September: add the Unofficial Skyrim Special Edition
Patch (USSEP, Nexus 266) to the collection. #1257 took out two Dawnguard moon
dial scripts that had shipped loose from it without its plugin. USSEP is a
full plugin, so every full plugin after the five base masters moves down one
position and the full plugin count goes from 48 to 49. During the alpha a
world reset from that is acceptable.

This page is the local side only. Nothing here has been published, deployed
or checked on a server. Steps 3 to 7 need Patrick's Vortex upload and a dev
deploy, and they wait for Smeagle to ask.

## 1. Start from revision 2

Revision 2 (docs\COLLECTION-REVISION-2.md) stays as it is: its removals,
exclusions, installer choices, Estate and Runtime versions, Content base and
generated files carry over unchanged. Leave **Skip plugin rules** off.

Check: Vortex's **Thornswood** profile is on revision 2 with 115 packages.

## 2. Add USSEP at the version for Skyrim 1.6.1170

Install USSEP **4.3.8a** (20 March 2026), the last release that supports
SSE 1.6.1130 and later. 4.3.9 (21 August 2026) and newer require SSE 1.7.99
and do not run on 1.6.1170. On Nexus it is under Old files; pin that file in
the collection rather than "latest". Its plugin is
Unofficial Skyrim Special Edition Patch.esp; it also installs its own BSA.

| Plugin | Rule to remove | Rule to add |
| --- | --- | --- |
| Unofficial Skyrim Special Edition Patch.esp | none | load after Dragonborn.esm |
| Water for ENB.esm | none | load after Unofficial Skyrim Special Edition Patch.esp |

Sort Now and Deploy; do not drag the list. Light plugins are not counted.

Check: the collection is 7essxf revision 3 with 116 packages, USSEP pinned at
4.3.8a, and every full plugin matches this order.

<!-- order:start -->
| Position | Plugin | What to do |
| --- | --- | --- |
| 1 | Skyrim.esm | The game loads the five base masters itself. |
| 2 | Update.esm | Base master. |
| 3 | Dawnguard.esm | Base master. |
| 4 | HearthFires.esm | Base master. |
| 5 | Dragonborn.esm | Base master. |
| 6 | Unofficial Skyrim Special Edition Patch.esp | **New** (step 2). USSEP 4.3.8a, Nexus 266; loads after Dragonborn.esm. |
| 7 | Water for ENB.esm | **Change.** Loads after Unofficial Skyrim Special Edition Patch.esp; was position 6. |
| 8 | Embers XD.esm | Keep. Was position 7. |
| 9 | RaceCompatibility.esm | Keep. Was position 8. |
| 10 | Immersive Sounds - Compendium.esp | Keep. Was position 9. |
| 11 | IcePenguinWorldMap.esp | Keep. Was position 10. |
| 12 | JKs Skyrim.esp | Keep. Was position 11. |
| 13 | WindhelmSSE.esp | Keep. Was position 12. |
| 14 | CWE - JK - United.esp | Keep. Was position 13. |
| 15 | JK's Whiterun's Outskirts.esp | Keep. Was position 14. |
| 16 | The Great City of Solitude.esp | Keep. Was position 15. |
| 17 | Embers XD.esp | Keep. Was position 16. |
| 18 | Riften Expansion.esp | Keep. Was position 17. |
| 19 | Odin - Skyrim Magic Overhaul.esp | Keep. Was position 18. |
| 20 | Hothtrooper44_ArmorCompilation.esp | Keep. Was position 19. |
| 21 | AnotherOakwood.esp | Keep. Was position 20. |
| 22 | aaaGraniteHill.esp | Keep. Was position 21. |
| 23 | ElysiumEstate.esp | Keep. Was position 22. |
| 24 | Triumvirate - Mage Archetypes.esp | Keep. Was position 23. |
| 25 | Apocalypse - Magic of Skyrim.esp | Keep. Was position 24. |
| 26 | CommonClothes.esp | Keep. Was position 25. |
| 27 | Cloaks&Capes.esp | Keep. Was position 26. |
| 28 | UIExtensions.esp | Keep. Was position 27. |
| 29 | chfshVariousActions.esp | Keep. Was position 28. |
| 30 | Cathedral Weathers.esp | Keep. Was position 29. |
| 31 | FishingInSkyrim.esp | Keep. Was position 30. |
| 32 | Thornswood-Content.esp | Keep. Was position 31. |
| 33 | Populated Cities Towns Villages Legendary.esp | Keep. Was position 32. |
| 34 | SkyrimSewers.esp | Keep. Was position 33. |
| 35 | Solitude Arena.esp | Keep. Was position 34. |
| 36 | ZIA_Complete Pack.esp | Keep. Was position 35. |
| 37 | CFTO.esp | Keep. Was position 36. |
| 38 | Arena - Markarth Side.esp | Keep. Was position 37. |
| 39 | Immersive Weapons.esp | Keep. Was position 38. |
| 40 | DIS_Heavy_Legion.esp | Keep. Was position 39. |
| 41 | OarsRest.esp | Keep. Was position 40. |
| 42 | North Keep.esp | Keep. Was position 41. |
| 43 | Immersive Patrols II.esp | Keep. Was position 42. |
| 44 | AHZmoreHUD.esp | Keep. Was position 43. |
| 45 | HappyLittleTrees.esp | Keep. Was position 44. |
| 46 | PlayFluteLuteDrum.esp | Keep. Was position 45. |
| 47 | Skyrim Unbound.esp | Keep. Was position 46. |
| 48 | Water for ENB (Shades of Skyrim).esp | Keep. Was position 47. |
| 49 | Playable Rieklings.esp | Keep. Was position 48. |
<!-- order:end -->

## 3. Publish revision 3 (Patrick, on Nexus)

Patrick uploads revision 3 from Vortex with the pinned file and the two rules
above. Nothing in this repository does that.

## 4. Regenerate what is read from the installed game

USSEP edits vanilla records and placements, and every full plugin's load
order index moves by one. Each channel's own folder is refreshed from the new
deployment (revision 2 step 8), then the server's plugin list and the game
data tables built from the installed plugins (game\data\npc-population.json,
resource-locations.json, fires.json, waters.json and the NPC population block
in game\gamemode.js) are rebuilt from it, with their tests, in one PR.

## 5. Dev first

Deploy-DevGamemode.ps1 -LoadOrder -Dist, with the dist\server folder
Deploy-Gamemode.ps1 wrote, sends Dev the 49-position list, with the world
reset that the moved indexes need. Without -Dist it keeps Dev's own order
(#2309). Ship -Channel dev from Dev's own folder.

## 6. Check the clean install on Dev

Run scripts\mods\Check-CleanInstall.ps1 against Dev, pointing its Data and
plugin list parameters at Dev's own folder, and compare Dev's manifest with
the table above. tests\test-collection-revision-3.ps1 keeps this page true to
revision 2's order with USSEP added.

## 7. Main

Main follows Dev only when Patrick asks, through revision 2's steps 12 to 14.