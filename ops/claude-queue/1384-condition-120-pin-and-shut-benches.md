# 1384 Condition at 120% and the shut temper benches: pin bump, then a release

- **Lane:** Anvil (Installer), 17 Oct
- **Issue:** #1384 (closed "Needs playtest."). Part 2 was split to #2692, "Blocked: Claude engine work", and is not in this note
- **PRs:**
  - Fork: EvilPatrick06/skymp #82 (branch `anvil/1384-condition-120`, tip `5b5a5d8d4e520c53722d0f49a0588b4f170aaddf`). HELD 1.2.4. Codex merges it after 1.2.4
  - Thornswood: #2691 (branch `anvil/1384-shut-temper-benches`, tip `22c989a6a4815cfc5de1626cb78d95e74bd467d3`). Green held draft, because it touches `game\gamemode.js`
- **Channel:** dev first, then the main server and the launcher's files in the release after 1.2.4
- **Who runs it:** Claude. Lanes do not bump the engine pin, Ship or Deploy

## What changed

1. **Fork #82.** `TES5DamageFormula` reads a worn piece's condition from its name (` (NN%)`, held to 0..120).
   - **Weapon.** At 120% the weapon the hit was landed with does 5% more base damage. With two of the same weapon worn, both must be at 120%, because HitData names no hand.
   - **Armour.** A worn armour piece at 120% gives 5% more of its own rating. Clothing gives nothing.
   - **Tests.** Catch2 cases are in `unit/TES5DamageFormulaTest.cpp`.
2. **Thornswood #2691.** `scripts\dev\Build-BenchTable.py` writes the sharpening wheel (`88108:Skyrim.esm`) and the armour table (`adb78:Skyrim.esm`) shut for everybody, with a `shut` sentence. `benchGate` answers that sentence first, so pressing either never opens the crafting menu.
   - The temper refusal in `recipelessCraft` stays behind it.
   - Docs: professions, durability and smith pages.
   - New harness: `tests\test-1384-shut-benches.js`.

## Run

1. When the freeze lifts, mark #2691 ready and squash-merge it once its CI is green (rebase on main first if the generated blocks conflict). If `game\gamemode.js` conflicts inside the generated BENCH_ACCESS block, regenerate it, don't hand edit. Use `python scripts\dev\Build-BenchTable.py --data <a Data folder whose Thornswood-Content.esp is the repo's game\content copy>`. The live `C:\Thornswood\Game\Data` copy on One is older and drops the woodworking bench `154e1`.
2. After Codex merges fork #82 into `thornswood/engine-changes`, bump the Thornswood `engine/skymp` submodule pin to that merge commit, in a PR with the usual engine build.
3. In the same pin bump PR, update `docs\systems\durability.md`:
   - Take the "Not yet" bullet "The 5% more damage and armour at 120% is not applied, because the engine works damage out on its own." out.
   - Say under "Where this is" that the server's damage formula applies the 120% buff. The weapon buff needs both hands at 120% when the same weapon is in each hand, and an enchantment is not raised.
4. Also take out the durability.md bullet "The shut grindstone and armour table are on main and not in a release yet." once a release carries #2691.
5. Ship the release that carries both (dev first), then the live server and the launcher's files as usual.
6. **Check in game.**
   - A Platewright and an Edgewright pressing the armour table and the sharpening wheel get the repair kit sentence, and no menu opens.
   - A worn weapon at 120% hits a target in plain armour slightly harder than the same weapon at 100%.

## Order and risk

- Order: #2691 does not wait on the fork and can ship on its own after the freeze. The pin bump waits on Codex merging fork #82 after 1.2.4.
- Risk, #2691: low. Only the two temper benches change, and nothing could be made at either.
- Risk, #82: low. Only a piece named at 120% changes a number, by 5%.
- Undo, #2691: revert it.
- Undo, #82: move the pin back.

## Draft release note

The grindstone and the armour table no longer open: tempering is cut, and a piece is mended with a repair kit. A weapon or armour piece repaired to 120% by the half that makes the kit now really hits or holds 5% harder. Clothing gets no buff.

## Ran (Claude)
- 19 Oct 2026, 5:58 to 6:05 PM: dev, Deploy-DevGamemode at 490f4d85 and dev Ship 20261019-180339-dev (SHIP EXIT 0). In-game checks are the Test task at main.
