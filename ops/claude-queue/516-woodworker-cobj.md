# 516 woodworker COBJ / bench

## Why Claude

Live placement of furniture in the world, collection Nexus upload, and recipe table rebuild against the full Data folder are Claude steps. Wyrd landed the Content.esp records, the 26 overrides, the trail ESP generator, and the trail ESP binary in repo.

## Done in PR (Wyrd)

- Thornswood-Content.esp: KYWD ThornswoodCraftingWoodworking, FURN ThornswoodCraftingWoodworkingWorkbench (Hearthfire carpenter mesh), 22 master COBJ overrides (Skyrim/Dawnguard/Dragonborn) plus our 4 poles/trap BNAM flipped to the woodworking keyword.
- scripts/mods/Add-ContentRecords.py extended for the above (idempotent, --check round-trips).
- scripts/mods/woodworker-trail-recipes.json (53 late-load rows) and Build-WoodworkerTrailOverrides.py; game/content/Thornswood-WoodworkerTrail.esp built from the collection plugins on One.
- BENCH_OWNER entry for ThornswoodCraftingWoodworking in Build-RecipeTable.ps1.
- Placement brief: docs/systems/woodworker-bench-placement.md

## Claude still does

1. DONE IN A PULL REQUEST (16 Oct, #2567, branch claude/516-benches, see 516-benches.md): the server stands the bench beside the forge in Whiterun, Solitude, Windhelm, Markarth, Riften, Falkreath, Dawnstar, Morthal and Riverwood, read from the plugins by scripts/dev/Build-WoodworkingBenches.py (game/data/woodworking-benches.json). Winterhold, Rorikstead, Ivarstead and Dragon Bridge have none, each with its measured reason.
2. DONE IN THE SAME PULL REQUEST: recipes.json rebuilt (exactly the 26 rows name the woodworking bench), BENCH_BY_BASE and BENCH_ACCESS, the fuel table, the item names and the Woodwright's lists.
3. Next collection revision: ship Thornswood-WoodworkerTrail.esp, pin it after Immersive Weapons / PlayFluteLuteDrum / Playable Rieklings / MoreCraftableEquipment / FishingInSkyrim, masters include RaceCompatibility.esm and Thornswood-Content.esp.
4. Dev Ship / Deploy for the Content.esp size change (clients re-download). Run it once with 516-benches.md, which carries the commands (Deploy-DevGamemode.ps1 -LoadOrder, then Ship.ps1 -Channel dev).

## Do not

- Do not use the charcoal kiln until #2337 is fixed.
- Do not move Thornswood-Content.esp to the end of the load order.
- Do not flip public playtest mode.

## Refs

Issue #516. PR uses Refs #516 until placement + collection land; then Test-task + close.

## Ran
- Dev release 20261016-010446-dev at 1:04 AM 16 Oct (Claude), from ops-batch at 7a02caa0, after Publish-Server dev (engine 3bdf3d3c, 10:45 PM 15 Oct), dev voice (-long-command-1) and Deploy-DevGamemode -LoadOrder (103 plugins, 10:48 PM). Step 4 done. Left: step 3, the next collection revision with Thornswood-WoodworkerTrail.esp.
