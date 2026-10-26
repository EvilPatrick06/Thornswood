# 3163 Spoilage and preserving: engine pin, then the gamemode and a dev Ship

- **Lane:** Claude (cloud thread), 26 Oct
- **Issue:** #3163
- **PRs:**
  - Fork: EvilPatrick06/skymp #118 (branch `claude/project-thread-to9q6n`), into `thornswood/engine-changes`. Needs Patrick's own line to merge
  - Thornswood: the pull request this note is in (branch `claude/project-thread-to9q6n`). Held as a draft until it carries the pin
- **Channel:** dev first, then main in the next main Ship
- **Who runs it:** Claude

## What changed

1. **Fork #118.** `Inventory::ResolveRemoval` takes a removal from the plain stack first and then from a stack that differs only in its name. Eating (`MpActor::OnEquip`) and a craft's inputs (`CraftService`) use it, and the craft's seventh argument names an input taken off a named stack. Catch2 cases in `unit/InventoryTest.cpp`, `unit/CraftTest.cpp` and `unit/HealthRestorationTest.cpp`.
2. **Thornswood.** The spoilage block in `game\gamemode.js`, the `spoil` table in `game\data\food-groups.json`, the preserving panel `game\ui\thornswood-preserve.js`, the friend key and its line in the inventory in `game\plugins\thornswood-front.js`, and `docs\systems\spoilage.md`. New harness: `tests\test-3163-spoilage.js`.

## Run

1. After fork #118 merges, move the `engine/skymp` pin in the Thornswood pull request to that merge commit (it must be feac4a29 or later, fork #107), let `Launcher builds` go green, mark it ready, and merge it. Never merge the Thornswood half without the pin: on the old engine eating a named steak throws after the meal lands and the server keeps the steak, which is free food.
2. Deploy-DevGamemode at the merge, then a dev Ship (`Ship.ps1 -Channel dev`), since the panel page and the front plugin are in the pack and the engine moved.
3. Health check: the dev server's log has no `[spoilage]` line with `threw`, and a fresh character's raw venison reads "Venison (7 days left)" within a minute.
4. The main side goes out in the next main Ship, never right after the dev one.

## Order and risk

- Order: fork #118, then the pin in the Thornswood pull request, then its merge, then the dev runs.
- Risk: food in every pack and chest is renamed with its days the first time the server looks at it. Nothing is taken away until a piece's days run out, which is a week at the soonest.
- Undo: revert the Thornswood merge and redeploy. Names already written stay on food; on the reverted server they are only names, and that food eats and cooks as long as the pin stays on fork #118.

## Draft release note

Food spoils now, gently. Raw meat, fish, fruit and vegetables keep a week, a cooked dish two, and you can read how many days a piece has left on its name. Food in your pack only spoils while you are online; a chest keeps counting. A chest in Winterhold, the Pale or high in the mountains keeps food cold. A Hearthcook or a Confectioner can salt raw meat and fish with a Salt Pile, or smoke it at a fire with firewood, so it never spoils: press Y in the inventory.
