# 2265 Cheddar's Mashups into the collection

- **Lane:** Wyrd (Vortex/collection)
- **Issue / PR:** #2265 (evaluation: https://github.com/EvilPatrick06/Thornswood/issues/2265#issuecomment-6208412354), no PR yet. A recipe-table PR follows this step.
- **Channel:** Vortex (collection revision), then the dev load order
- **Staff status updates:** #staff-updates (1549254991082946570)
- **Needs first:** Patrick's approval of 12 Oct (on the issue). Can ride in the same revision as #2264 + #2454 (`2264-improved-eyes.md`, `2454-ccaa-3ba-mce-bodyslide.md`), or the next one.

## Run
1. In Vortex, add Cheddar's Mashups (Nexus SE 182534). Take TWO files: the main "Cheddar's Mashups V1.8.8" (meshes and textures, about 337 MB) and "Cheddars Mashups ESL" (v1.8.9). NOT the ESP (download only one), and NOT "Cheddars Mashups Keizaal" (another server's patch). Xavbio's Retextures is optional, so leave it out.
2. Load order: anywhere late. As an ESL it takes no full slot and renumbers nothing. Put it after Immersive Weapons, Hothtrooper44 and ZIA so its vendor leveled-list entries win. This doesn't affect #2264's rule (IES after every current full plugin).
3. Pin this version. 1.9.0 is due at the end of October, so take it in a later revision on purpose, not by auto-update.
4. Publish. Run .\scripts\mods\New-CollectionPluginRecord.ps1 and commit records\collection-plugins.json (Refs #2265).
5. Deploy-DevGamemode.ps1 -LoadOrder -Note "Cheddar's Mashups in the load order (#2265)".
6. Post on #2265 that it's in. Wyrd then rebuilds game\data\recipes.json (Build-RecipeTable) on the build machine and assigns the new forge recipes to a smith (a held PR, game\ path).

## Check afterwards
- records\collection-plugins.json gains Cheddar's ESL only. Every full plugin keeps its index.
- On dev, an existing character keeps its hair, eyes and gear.
- A few sets on a CBBE woman and a HIMBO man: look for seams at the neck, wrists and legs (the meshes are vanilla-body mashups).

## Risks and how to put it back
- Body seams are cosmetic. If they're bad, raise it on #2265 before release.
- Until the recipe PR lands, its forge recipes sit outside the trade rules.
- To revert, drop it from the collection, refresh the record, and run Deploy-DevGamemode -LoadOrder.

## Permissions (never repack)
Link only. Its assets need the author's permission and some are Xavbio's. Never put its meshes or textures into our packs or the Content mod.

## With Improved Eyes (#2264)
No interaction. Armour, COBJ and leveled lists here; eye textures and eye HDPTs there. No shared records or files, so the order between the two doesn't matter.

## Release notes (draft)
About forty new armour sets mashed up from Skyrim's own (Cheddar's Mashups by CheddarBread), made by the smiths.

## News post (draft)
none

## Test task (draft)
Test task: as a smith, find one of the new mashup sets at the forge, make it, and wear it. Check from a few angles, on a woman and a man, that nothing is missing or gapped.
Repo half follow-up: #2660 (rebuild recipes.json and assign owners after this revision).
