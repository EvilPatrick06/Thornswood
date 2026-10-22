# 2264 Improved Eyes Skyrim into the collection

- **Lane:** Wyrd (Vortex/collection)
- **Issue / PR:** #2264 (evaluation: https://github.com/EvilPatrick06/Thornswood/issues/2264#issuecomment-6208389972), no PR
- **Channel:** Vortex (collection revision), then the dev load order
- **Staff status updates:** #staff-updates (1549254991082946570)
- **Needs first:** Patrick's approval of 12 Oct (on the issue). **Do it in the SAME Vortex revision as #2454** (2454-ccaa-3ba-mce-bodyslide.md): one publish, one record refresh. Those two add BodySlide projects only (no plugins), so they don't affect where IES goes in the load order.

## Run
1. In Vortex, add Improved Eyes Skyrim (Nexus SE 9141, v1.6) to the collection.
   FOMOD: Complete Set (all races, default replacers) plus the Dawnguard add-on. NOT the Serana blue eyes optional. Vampire and werewolf add-ons are fine either way.
2. Load order: put its plugin AFTER every current full plugin and before Thornswood-Last.esp. Do not let LOOT sort it into the middle. A mid-list full plugin renumbers everything after it, and stored headpartIds (hair) on existing characters would break.
3. Publish the collection revision.
4. Refresh the record: .\scripts\mods\New-CollectionPluginRecord.ps1, then commit records\collection-plugins.json (Refs #2264).
5. Deploy-DevGamemode.ps1 -LoadOrder -Note "Improved Eyes Skyrim in the load order (#2264)", so the dev server's load order matches.

## Check afterwards
- records\collection-plugins.json gains the IES plugin, and every plugin above it keeps its place.
- On dev: an existing character keeps its hair and eyes after updating (no bald heads, no missing eyes).
- In character creation, a Nord or Breton shows the new eye options, and the default eyes look sharper.
- Someone else sees the eyes you chose.

## Risks and how to put it back
- If an existing character's hair or eyes break, the load order shifted: move IES to the end and republish.
- To revert, drop it from the collection, refresh the record, and run Deploy-DevGamemode -LoadOrder again.
- Licence: link only. Never repack its textures into our packs or the Content mod (author's terms).

## With Cheddar's Mashups (#2265)
No interaction (armour vs eyes). The order between them doesn't matter. Cheddar's goes in as an ESL, so it doesn't move IES's late slot either. See 2265-cheddars-mashups.md.

## Release notes (draft)
Eyes are sharper for every race, and character creation has many more eye colours to pick from (Improved Eyes Skyrim by missjennabee and Nazenn).

## News post (draft)
none

## Test task (draft)
Test task: after updating, check that your existing character's hair and eyes look right. Then make a new character, open the eye options in character creation, check there are new colours, pick one, and ask someone nearby whether they see the same eyes.