# Charburner

The kiln. Five recipes, every one reaches the server, every one is
the charcoal kiln, and the kiln is closed to anyone who is not this
half from novice.

The full table: [lists/woodworker-charburner.md](../../lists/woodworker-charburner.md).

| Item | Rank | Asks for | Makes |
| --- | --- | --- | --- |
| Poor Charcoal | Novice | 2 firewood | 1 |
| Tool Handle | Novice | 1 firewood | 1 |
| Charcoal | Advanced | 4 firewood | 1 |
| Charcoal Briquette | Expert | 7 firewood | 1 |
| Coke | Master | 12 firewood | 1 |

A forge and a skyforge burn one charcoal per piece. The four grades
are how hot the fire is. A higher metal needs a hotter grade. The
table is on [Smith](../smith.md). A skyforge asks for one grade
poorer, and Poor Charcoal does not get poorer. The server still
burns the cheapest grade in the pack first, and Poor Charcoal is
what it eats if you have it. No charcoal of the grade the metal asks
for, the forge refuses the piece, including a smith's.

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

You cannot chop without the axe. 50 uses, then a smith.

<!-- detail:begin -->

## Every recipe

Generated from `game/data/recipes.json` by `scripts/dev/Write-SystemLists.js`. 5 recipes. 5 reach the server. None of them are tempering. The same rows, with ids, are in [woodworker-charburner](../../lists/woodworker-charburner.md).

The rank on the row is the rank. It is the dearest ingredient a class produces. An item has no gold price.

### Names that reach the server

**Novice** (2 names). Poor Charcoal. Tool Handle.

**Advanced** (1 name). Charcoal.

**Expert** (1 name). Charcoal Briquette.

**Master** (1 name). Coke.

| Item | Makes | Rank | Kind | Bench | Asks for | Race | Server asked | Id |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Poor Charcoal | 1 | novice | Other goods | ThornswoodCraftingCharcoalKiln | 2 Firewood |  | yes | `15480:Thornswood-Content.esp` |
| Tool Handle | 1 | novice | Other goods | ThornswoodCraftingCharcoalKiln | 1 Firewood |  | yes | `15491:Thornswood-Content.esp` |
| Charcoal | 1 | advanced | Other goods | ThornswoodCraftingCharcoalKiln | 4 Firewood |  | yes | `15486:Thornswood-Content.esp` |
| Charcoal Briquette | 1 | expert | Other goods | ThornswoodCraftingCharcoalKiln | 7 Firewood |  | yes | `15487:Thornswood-Content.esp` |
| Coke | 1 | master | Other goods | ThornswoodCraftingCharcoalKiln | 12 Firewood |  | yes | `15488:Thornswood-Content.esp` |

<!-- detail:end -->

## Where this is

All five rows and the closed kiln are in the server. The forge's
charcoal take is in the server. The hotter kiln is not.
