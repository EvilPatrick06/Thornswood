# Woodworking benches for #516 (placement brief)

Patrick, 12 Oct 2026: our own woodworking bench, at least one in every major hold and some minor towns, placed by Claude.

## Base records (this PR)

- KYWD `ThornswoodCraftingWoodworking` (0x050154E1) in `Thornswood-Content.esp`
- FURN `ThornswoodCraftingWoodworkingWorkbench` (0x050154E2), mesh `_BYOH\Furniture\CraftingWorkbench01.nif` (Hearthfire carpenter workbench), create-object bench, carries the keyword above

## Where they stand (#516, 16 Oct)

The server stands the benches, once, when it starts, beside a fixed forge read out of the plugins: the same way the notice boards stand (#2516). No plugin places them, and nothing on a timer moves them back.

- `scripts/dev/Build-WoodworkingBenches.py` reads each forge's winning record over the whole load order in `game/data/last-plugin.json`, and works out the bench's point, height and angle from an offset in that forge's own frame. It stops on a site whose spot is not clear: the bench and the place its woodworker stands must lie on the town's navmesh, on ground flat to 16 units and within 60 of the forge's own height, touch no furniture, container, door, item or small static, and keep 30 units from the nearest of them.
- `game/data/woodworking-benches.json` is what it measured at each spot: the forge and every plugin that touches it, the point and angle, the ground under the bench, the nearest solid thing and why the spot was chosen.
- The gamemode's `WOODWORKING_BENCHES` block is that table; `standBenches()` in the property block stands them at start.
- `tests/test-516-woodworking-benches.js` holds all of it together, and on a machine with the game reads the plugins again.

| Town | Forge | Bench from the forge | Nearest solid thing |
| --- | --- | --- | --- |
| Whiterun | Warmaiden's, `c430a:Skyrim.esm` (not the Skyforge) | 668 units, north of Warmaiden's shop by its wall, on the forge's floor | a decorative shield, 30 units |
| Solitude | Beirand's, `4e3e9:Skyrim.esm` | 201 units, behind the smith in the open yard | the smelter, 34 units |
| Windhelm | the blacksmith yard by the gate, `f7798:Skyrim.esm` | 260 units, behind the smith | the grindstone, 53 units |
| Markarth | Ghorza's, `514d8:Skyrim.esm` | 743 units, on the walk a step below the forge | a fern, 34 units |
| Riften | The Scorched Hammer, `53481:Skyrim.esm` | 260 units, to the smith's right on the same boards | a signpost, 70 units |
| Falkreath | Lod's, `99b8a:Skyrim.esm` | 388 units, to the smith's left | a lean spot on the wall, 40 units |
| Dawnstar | Rustleif's, `cadf6:Skyrim.esm` | 449 units, behind the smith | a barrel, 31 units |
| Morthal | JK's Skyrim's anvil, `24588:JKs Skyrim.esp` (Morthal has no forge of Skyrim's own) | 418 units, to the smith's left | a fire pit, 53 units |
| Riverwood | Alvor's, `d6987:Skyrim.esm` | 400 units, to the smith's left, nowhere near the kiln | a lean spot on the wall, 44 units |

Three sites moved on 16 Oct (#2553). Until then the other server's records in Thornswood-Content.esp moved and turned Whiterun's and Riften's forges and shrank and moved Windhelm's tanning rack. With those records gone, Skyrim's own forges and rack stand where Skyrim puts them: Whiterun's bench keeps its spot, measured from the forge where it now stands; Riften's forge stands on the old spot, so the bench is beside it; Windhelm's rack is back beside the old spot, so the bench is behind the smith.

No bench, and why, measured over the same load order:

- Winterhold: no forge. JK's Skyrim's anvil stands inside a shack of its own, with no clear flat ground of the bench's size beside it.
- Rorikstead: no forge of Skyrim's own. JK's Skyrim's anvil yard sits on a raised ledge with no clear flat ground of the bench's size on it.
- Ivarstead: no forge and no anvil at all.
- Dragon Bridge: its forge stands on sloping ground; the nearest clear flat spot is 725 units away out in the field.

Never at the charcoal kiln (#2337): the harness refuses any bench within 1,000 units of one.

To move one: `python scripts/dev/Build-WoodworkingBenches.py --search <town>` lists the clear spots round its forge, nearest first. Change the town's offset or turn in SITES, run the builder without `--search`, and run the harness.

## Still to do

1. Ship `Thornswood-WoodworkerTrail.esp` in the next collection revision (see `scripts/mods/woodworker-trail-recipes.json` and `Build-WoodworkerTrailOverrides.py`).
2. Pin the trail plugin last among Thornswood plugins in the collection load order.
