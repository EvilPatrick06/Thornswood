# Woodworking benches for #516 (placement brief)

Patrick, 12 Oct 2026: our own woodworking bench, at least one in every major hold and some minor towns, placed by Claude.

## Base records (this PR)

- KYWD `ThornswoodCraftingWoodworking` (0x050154E0) in `Thornswood-Content.esp`
- FURN `ThornswoodCraftingWoodworkingWorkbench` (0x050154E1), mesh `_BYOH\Furniture\CraftingWorkbench01.nif` (Hearthfire carpenter workbench), create-object bench, carries the keyword above

## Where to place

Place one REFR of `ThornswoodCraftingWoodworkingWorkbench` beside the public forge in each major hold capital, and in some minor towns that already have a forge people use:

Major holds (required):
- Whiterun (Warmaiden's / Skyforge area: prefer Warmaiden's outdoor forge side, not inside the Skyforge ritual space unless Patrick says otherwise)
- Solitude (Blacksmith area)
- Windhelm (blacksmith yard)
- Markarth (Understone / forge court)
- Riften (The Scorched Hammer yard)
- Falkreath (blacksmith)
- Morthal (if a forge is present for people)
- Dawnstar (blacksmith)
- Winterhold (if a usable forge exists for people; otherwise skip)

Minor towns (some, not all): Riverwood, Rorikstead, Ivarstead, Dragon Bridge, where a forge already sits in the open.

## How

Coordinates are not invented here. Open the live world (or the collection install on One), stand beside each forge, and drop the furniture so a woodworker can walk up to it the same way they walk up to the forge. Match the forge's angle so the bench does not block the forge animation.

Do not place at the charcoal kiln. Do not use the kiln keyword until #2337 is fixed.

## After placement

1. Rebuild `game/data/recipes.json` (and bench tables if the build asks) so the 26 Content overrides show the woodworking bench.
2. Ship `Thornswood-WoodworkerTrail.esp` in the next collection revision (see `scripts/mods/woodworker-trail-recipes.json` and `Build-WoodworkerTrailOverrides.py`).
3. Pin the trail plugin last among Thornswood plugins in the collection load order.
