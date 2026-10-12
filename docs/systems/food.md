# Food

A swallowed thing is hunger, thirst, or both. The food table says which
kind it is. The state says how good a meal it is.

## States

| State | Hunger | Also |
| --- | --- | --- |
| Raw meat or fish | 8 | Can start food sickness. What you eat with no fire |
| Burnt | 8 | Stamina recovery -10% for 10 real minutes |
| Ordinary food the table does not special-case | 15 | Nothing else |
| Cooked | 25 | A small help for 20 real minutes, from what went in it |
| A feast | 40 | A stronger help for 10 real minutes |

A cooked meal's help is one of these, not all of them: stamina recovery
+10%, or the temperature target 4 degrees warmer, or the chance of
catching a disease cut in half while it lasts. A feast is the same
list at double the help and half the time, so the disease chance is
a quarter. It is not a heal. A potion still does the healing.

A soup, a stew or a chowder is food and 10 thirst. A dry ration is food
only.

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

The table that marks food, drink, ale, potion and poison is in the server, and an unknown edible is 15 hunger. The 8 seconds and the full-stomach sickness are in it too. The groups are in the server too (#1382), by record in game/data/food-groups.json: raw meat or fish is 8 and can start food sickness, cooked is 25 (the Homecooked Meal is cooked), a soup, stew or chowder is 15 hunger and 10 thirst, and ingredients (vegetables, fruit, honey, butter, flour), prepared food (bread, cheese, sweets, spiced beef) and the six drugs are 15. The six drugs get their effect next. The Bee and Barb's mixed drinks, the Battle-Brew meads and Red Eagle's Rye are ale, milk and snowberry juice are drink, and Goodberry is a potion. There is no feast or tea group: no item is one. Burnt is a cooking quality level, not a group; a failed cook does not yet make burnt food. The cooked help is not in yet.
