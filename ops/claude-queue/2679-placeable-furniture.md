# 2679 placeable furniture in held buildings

Issue: https://github.com/EvilPatrick06/Thornswood/issues/2679
Design: https://github.com/EvilPatrick06/Thornswood/issues/2679#issuecomment-6246616411
Lane: Anvil. PR: https://github.com/EvilPatrick06/Thornswood/pull/2693 (HELD draft, branch anvil/2679-furniture).

## Why this is in the queue

The PR touches game\ (gamemode, front plugin, a new UI panel, the content plugin, game\data) and records\asset-provenance.json, so it is a held draft under the freeze. Lanes do not run Ship, Deploy or live steps.

## Steps for Claude

1. After the freeze lifts, squash-merge the held draft once its CI is green on the current main. If main moved, rebuild the generated parts on the branch first:
   - python scripts\mods\Add-ContentRecords.py
   - scripts\dev\Build-RecipeTable.ps1 against a Data folder that has the repo copy of Thornswood-Content.esp (the copy in C:\Thornswood\Game\Data is stale), then node scripts\dev\Write-SystemLists.js, node scripts\dev\Write-CutItems.js and node scripts\dev\Build-FuelTable.js
   - update the sha256 of game/content/Thornswood-Content.esp in records\asset-provenance.json
   - python scripts\dev\Build-MerchantRoleTables.py, and with --data on that same Data folder: scripts\dev\Build-WoodworkingBenches.py, scripts\dev\Build-BuildingHolds.py and scripts\mods\Build-LastPlugin.py (they pin the content plugin's sha256)
2. Ship to dev. Thornswood-Content.esp changed size (110,915 to 114,252 bytes), so every client downloads it again and the server needs the same plugin (Deploy-Server -GamemodeOnly sends it with the gamemode). game\data\furniture.json must reach the server folder next to gamemode.js, the way guild-sites.json does.
3. Dev playtest:
   - Make a Wooden Chair and a Chest at a woodworking bench as a Woodwright.
   - In a building you hold, open the inventory: X shows Arrange furniture. Place a chair and a chest from the panel.
   - Look at the chair: U Move, X Pick up. Move it, turn it with X, set it down with U.
   - Put an item in the chest, try Pick up (refused), empty it, pick it up.
   - A friend with only a plain key sees no line; one carrying the deed or master key can arrange.
   - Restart the dev server: the pieces stand where they were, at the same angle, and the chest keeps its contents.
4. Dev check for statics (STAT). The server does not load STAT records from plugins, so it is not known whether a placed table or shelf is kept and streamed. On dev, set limits.types.STAT to true in game\data\furniture.json, rerun Add-ContentRecords.py and the recipe table steps, place a Round Table, restart, and see whether it is still there. If it is, keep STAT on and ship. If it is not, leave STAT off and file "Blocked: Claude engine work: placing a static (STAT) in the world from the server" for the fork.
5. Ship to main after the dev playtest passes.

## Release and wipe

Pieces belong to the building, and private\furniture.json names no person. Lapse, eviction and a deed changing hands leave them for the next holder. Character delete and reset (#2651, #2670, Release-List.ps1) need nothing for furniture. Wipe-Saves.ps1 now moves private\furniture.json aside with the world.

## Numbers

Every number is staff data in game\data\furniture.json: perBuilding 40, per-building overrides, reach 120, pickReach 400, carryMs 60000, turnStep 45, and the catalog of pieces, recipes, values and weights.
