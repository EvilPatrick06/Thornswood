# Charburner

The kiln. Five recipes, every one reaches the server, every one is
the charcoal kiln, and the kiln is closed to anyone who is not this
half from novice.

The full table: [lists/woodworker-charburner.md](../../lists/woodworker-charburner.md).

| Item | Rank | Asks for | Gold | Makes |
| --- | --- | --- | --- | --- |
| Poor Charcoal | Novice | 2 firewood | 2 | 1 |
| Tool Handle | Novice | 1 firewood | 5 | 1 |
| Charcoal | Advanced | 4 firewood | 2 | 1 |
| Charcoal Briquette | Expert | 7 firewood | 2 | 1 |
| Coke | Master | 12 firewood | 2 | 1 |

A forge and a skyforge burn one charcoal per piece, cheapest grade in
the pack first. Poor Charcoal is what they eat if you have it. A
better grade is saved. No charcoal of any grade, the forge refuses
the piece, including a smith's.

A hafted weapon takes one tool handle on top of its own ingredients.
The handle was not in those ingredients when the weapon's rank was
set.

## What you are handed

The half places 1 in Toughness (+10 poison and +10 disease
resistance), on top of the woodworker's Endurance and Burden.

## Fire

Master Carver's +48 is this half's kiln as well as a Woodwright's
fire. It is not applied. The kiln warms like any other fire: +34 at
your feet.

## What you cannot do

You cannot make a bow. That is Woodwright, and your sister half is
their novice 20 only.

You cannot chop without the axe. 100 uses, then a smith.

<!-- detail:begin -->

## Every recipe

Generated from `game/data/recipes.json` by `scripts/dev/Write-SystemLists.js`. 5 recipes. 5 reach the server. None of them are tempering. The same rows, with ids, are in [woodworker-charburner](../../lists/woodworker-charburner.md).

A rank is the dearest ingredient a class produces. If an ingredient is produced by nobody, the rank stays at what the finished piece sells for, and it is not allowed to drop below that. The sell price alone is not the rank when something in the row is produced.

### Names that reach the server

**Novice** (2 names). Poor Charcoal. Tool Handle.

**Advanced** (1 name). Charcoal.

**Expert** (1 name). Charcoal Briquette.

**Master** (1 name). Coke.

| Item | Makes | Rank | Kind | Bench | Asks for | Gold | Race | Server asked | Id |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Poor Charcoal | 1 | novice | Other goods | ThornswoodCraftingCharcoalKiln | 2 Firewood | 2 |  | yes | `15480:Thornswood-Content.esp` |
| Tool Handle | 1 | novice | Other goods | ThornswoodCraftingCharcoalKiln | 1 Firewood | 5 |  | yes | `15491:Thornswood-Content.esp` |
| Charcoal | 1 | advanced | Other goods | ThornswoodCraftingCharcoalKiln | 4 Firewood | 2 |  | yes | `15486:Thornswood-Content.esp` |
| Charcoal Briquette | 1 | expert | Other goods | ThornswoodCraftingCharcoalKiln | 7 Firewood | 2 |  | yes | `15487:Thornswood-Content.esp` |
| Coke | 1 | master | Other goods | ThornswoodCraftingCharcoalKiln | 12 Firewood | 2 |  | yes | `15488:Thornswood-Content.esp` |

<!-- detail:end -->

## Where this is

All five rows and the closed kiln are in the server. The forge's
charcoal take is in the server. The hotter kiln is not.
