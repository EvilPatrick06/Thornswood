# Confectioner

Desserts. 28 recipes, all of them reach the server, all of them the
oven, all of them the kind Desserts. Worth is 6 or 14 gold. None are
race locked. None are master.

The full table: [lists/cook-confectioner.md](../../lists/cook-confectioner.md).

| Rank | Recipes |
| --- | --- |
| Novice | 8 |
| Advanced | 12 |
| Expert | 8 |
| Master | 0 |

The novice eight were moved down so the rung was not empty. Every
one of them wants a sack of flour and butter. Flour is the Hearthcook
mill recipe, and wheat is advanced farm work. A novice confectioner
is buying flour, not growing it.

All 28 used to want two vanilla food perks as well, which nobody here
can hold, so the crafting menu hid every row the server allowed. The
perks come off every recipe in Thornswood-Last.esp (#4826), so the
server's answer is the only one.

## The novice eight

Boiled Creme Treat, Honey Nut Treat, Jazbay Dumpling, Jelly Dumpling,
Juniper Berry Dumpling, Snowberry Dumpling, Sweet Roll. Boiled Creme
Treat is in the table twice, one portion and two, which is the eighth
row.

## Above novice

Advanced is the crostatas and the two-portion dumplings. Expert is
the apple dumplings and the last of the richer plates. The names are
the list. There is no master dessert, so Grand Chef at master doubles
the expert batch rather than opening a new dish.

## What you are handed

The half places 1 in Fortitude. The profession already placed 1 in
Fortitude, so a Confectioner starts at 2: +20% health recovery.

The oven is your bench from novice. The mill is not. The cookpot is
the Hearthcook's, and it opens for you as your sister half, so you
stop at that half's novice list.

## What you cannot do

You cannot skip the flour. You cannot make a master-ranked dessert,
because there isn't one. You cannot hunt the eggs. A chicken nest is
the farmer's.

<!-- detail:begin -->

## Every recipe

Generated from `game/data/recipes.json` by `scripts/dev/Write-SystemLists.js`. 12 recipes. 12 reach the server. None of them are tempering. The same rows, with ids, are in [cook-confectioner](../../lists/cook-confectioner.md).

The rank on the row is the rank. It is the dearest ingredient a class produces. An item has no gold price.

### Names that reach the server

**Novice** (1 name). Apple Dumpling.

**Advanced** (10 names). Boiled Creme Treat. Honey Nut Treat. Jazbay Crostata. Jazbay Dumpling. Jelly Dumpling. Juniper Berry Crostata. Juniper Berry Dumpling. Snowberry Crostata. Snowberry Dumpling. Sweet Roll.

**Expert** (1 name). Apple Pie.

**Master.** None.

| Item | Makes | Rank | Kind | Bench | Asks for | Race | Server asked | Id |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Apple Dumpling | 1 | novice | Desserts | BYOHCraftingOven | 1 Red Apple, 1 Sack of Flour, 1 Butter |  | yes | `117f9:HearthFires.esm` |
| Boiled Creme Treat | 1 | advanced | Desserts | BYOHCraftingOven | 1 Chicken's Egg, 1 Sack of Flour, 1 Butter |  | yes | `8a4:Gourmet.esp` |
| Honey Nut Treat | 1 | advanced | Desserts | BYOHCraftingOven | 1 Honey, 1 Sack of Flour, 1 Butter |  | yes | `8a6:Gourmet.esp` |
| Jazbay Crostata | 1 | advanced | Desserts | BYOHCraftingOven | 1 Chicken's Egg, 2 Jazbay Grapes, 1 Sack of Flour, 1 Butter |  | yes | `117fa:HearthFires.esm` |
| Jazbay Dumpling | 1 | advanced | Desserts | BYOHCraftingOven | 1 Jazbay Grapes, 1 Sack of Flour, 1 Butter |  | yes | `11800:HearthFires.esm` |
| Jelly Dumpling | 1 | advanced | Desserts | BYOHCraftingOven | 1 Sack of Flour, 1 Butter, 1 Netch Jelly |  | yes | `98b:Gourmet.esp` |
| Juniper Berry Crostata | 1 | advanced | Desserts | BYOHCraftingOven | 1 Chicken's Egg, 2 Juniper Berries, 1 Sack of Flour, 1 Butter |  | yes | `117fc:HearthFires.esm` |
| Juniper Berry Dumpling | 1 | advanced | Desserts | BYOHCraftingOven | 1 Juniper Berries, 1 Sack of Flour, 1 Butter |  | yes | `80f:Gourmet.esp` |
| Snowberry Crostata | 1 | advanced | Desserts | BYOHCraftingOven | 2 Snowberries, 1 Chicken's Egg, 1 Sack of Flour, 1 Butter |  | yes | `117fd:HearthFires.esm` |
| Snowberry Dumpling | 1 | advanced | Desserts | BYOHCraftingOven | 1 Snowberries, 1 Sack of Flour, 1 Butter |  | yes | `11802:HearthFires.esm` |
| Sweet Roll | 1 | advanced | Desserts | BYOHCraftingOven | 1 Sack of Flour, 1 Butter, 1 Jug of Milk |  | yes | `117fb:HearthFires.esm` |
| Apple Pie | 1 | expert | Desserts | BYOHCraftingOven | 1 Chicken's Egg, 2 Red Apple, 1 Sack of Flour, 1 Butter |  | yes | `117fe:HearthFires.esm` |

<!-- detail:end -->

## Where this is

The 28 rows and the oven gate are in the server. The vanilla perk
lines come off the menu with the first release built after #4826. Grand Chef's second portion is in
the server.
