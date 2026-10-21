# Food

A swallowed thing is hunger, thirst, or both. The food table says which
kind it is. The state says how good a meal it is.

## States

| State | Hunger | Also |
| --- | --- | --- |
| Raw meat or fish | 8 | Can start food sickness. What you eat with no fire |
| Burnt | 8 | Stamina recovery -10% for 10 real minutes |
| Ordinary food the table does not special-case | 15 | Nothing else |
| Cooked | 25 | A small help for 20 real minutes, from what went in it (below) |
| A feast | 40 | A stronger help for 10 real minutes |

A cooked meal's help is one of these, not all of them: stamina recovery
+10%, or the temperature target 4 degrees warmer, or the chance of
catching a disease cut in half while it lasts. A feast is the same
list at double the help and half the time, so the disease chance is
a quarter. It is not a heal. A potion still does the healing.

Which help a meal gives (Patrick, 18 October 2026, #2682):

- A soup, a stew or a chowder warms. That is the only help a meal gives
  on its own. Any other cooked dish gives none.
- Stamina recovery or the disease guard comes only when the cook adds
  one extra ingredient at the pot: garlic for the disease guard, a salt
  pile for stamina recovery. The seasoned dish gives that help instead of
  warmth.
- The latest meal's help is the one that counts. A meal with no help
  leaves the one you have alone. A meal refused inside the 8 seconds, or
  eaten on a full stomach, gives no help.

## Food's own magic

Food does not carry its own magic. The regeneration boosts the game's
food records came with are gone, so the help above and the alchemist's
potions are what a meal or a bottle is for (Patrick, 18 October 2026).
Hunger and thirst are not touched.

Temperature is the exception. Frostwheat Bread, the Sack of Frostwheat
Flour and Snowberry Juice keep their frost resistance, and for now the
small heal that rides with it, because the game applies a record's
effects all together or not at all. Drugs, ale and potions are not
food here and keep their own effects.

A soup, a stew or a chowder counts as cooked: 25 hunger and 10 thirst
(Patrick, 12 Oct 2026), so cooking a stew is never worse than cooking
a chop. A dry ration is food only.

## Time and a full stomach

Eating takes 8 seconds. Another meal in that window does nothing. At
90 hunger or above, another meal does not raise the meter and starts
food sickness instead. That is what stops a stack of stews replacing
potions.

## Who cooks

Hearthcook and Confectioner own the recipes. The rows are
[lists/cook-hearthcook.md](lists/cook-hearthcook.md) and
[lists/cook-confectioner.md](lists/cook-confectioner.md). Grand Chef
makes two of a batch. A hunter is who brings the meat. This page does
not move either verb.

Burnt food is an item that already exists, eaten as burnt. A failed
recipe does not yet become a burnt item. There is no timing minigame.

## Where this is

The table that marks food, drink, ale, potion and poison is in the server, and an unknown edible is 15 hunger. The 8 seconds and the full-stomach sickness are in it too. The groups are in the server too (#1382), by record in game/data/food-groups.json: raw meat or fish is 8 and can start food sickness, cooked is 25 (the Homecooked Meal is cooked), a soup, stew or chowder counts as cooked and is 25 hunger and 10 thirst, and ingredients (vegetables, fruit, honey, butter, flour), prepared food (bread, cheese, sweets, spiced beef) and the six drugs are 15. The six drugs also take the stimulant in [Exhaustion](exhaustion.md). The Bee and Barb's mixed drinks, the Battle-Brew meads and Red Eagle's Rye are ale, milk and snowberry juice are drink, and Goodberry is a potion. Tea is a group of its own: the three teas are drinks, 20 thirst, and take the tea stimulant in [Exhaustion](exhaustion.md). There is no feast group: no item is one. Burnt is a cooking quality level, not a group; a failed cook does not yet make burnt food. The cooked help and food's own magic are in the server too (#2682), in the same file: which groups lose their own magic and the three records kept whole (`strip`), which group warms on its own and which extra ingredient gives which help (`season`). The disease guard is the injury system's, from [Disease](disease.md). The seasoned dishes are not in the content plugin yet, so until they are, only the warmth and the taking away of food's own magic are live.
