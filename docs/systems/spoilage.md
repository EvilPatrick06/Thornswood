# Spoilage

Food spoils gently. Raw food keeps 1 real week, a dish keeps 2, and
salted or smoked food never spoils. Patrick decided this on his report
page on 22 October, on
[#3163](https://github.com/EvilPatrick06/Thornswood/issues/3163). See
[Decided](../DECIDED.md).

| Food | Keeps |
| --- | --- |
| Raw meat and fish | 7 days |
| Fruit, vegetables and milk | 7 days |
| Cooked dishes, soups, stews and chowders | 14 days |
| Bread, sweets, butter and the Burnt Meal | 14 days |
| A fine dish | As its plain dish |
| Salted or smoked food | Never spoils |
| Honey, flour, cheese, spiced beef, Nord chocolate, taffy | Never spoils |
| Drink, ale, tea, potions and drugs | Never spoils |

## Where the days are

The days are on the food's name, the way a piece's condition is on
its name ([Durability](durability.md)). A steak reads
"Venison (6 days left)". When it is salted it reads
"Venison (salted)".

The name goes everywhere the food goes: into a chest, out of it,
through a trade and across a restart. Two steaks bought a day apart
are two lines in the inventory, and a buyer can read how fresh the
meat is before paying for it.

Food that has no days on it yet gets its full life the first time
the server looks at it. That is a steak just cut from a deer, an
apple just picked, or bread off a shelf. A dish comes off the pot
with its full life already on it.

When the last day runs out, the food is gone. Its owner is told what
went off. For a chest, the person who opens it is told.

## Two clocks

**A pack counts only while its owner is online.** Every minute the
server looks at every pack that is online. Time between two looks
counts. A gap of more than 5 minutes was time away, or a server that
was down, and counts nothing. Each time a whole day of play has
gathered, every piece in the pack has a day fewer left. Nothing
spoils in a pack while its owner is offline.

**A chest counts real days.** Its clock starts the first time it is
opened. After that, the real days since its last opening come off
the food inside when it is next opened, before what is in it is
shown. Opening it again never resets the clock. Every container
counts, a shop chest, a house chest and a cave's chest alike.

A day comes off when its place's day turns. A steak put in a chest an
hour before that chest's day turns loses that day. A day is always a
whole day, never a share of one.

## Cold storage

A chest in a snowy climate keeps food. That is Winterhold, the Pale,
and outdoors high in the mountains (the same places
[Temperature](temperature.md) calls snowy and high). The chest's days
still turn, so nothing is owed when the food leaves it, but none of
them come off the food. A pack is never cold storage.

Cold storage is open on Patrick's report page
(q-3163-cold-storage). This is the recommended answer.

## Preserving

Salting and smoking is a cook's work. A Hearthcook or a Confectioner
can do it from novice, and so can somebody taught that half under a
master ([Masters and apprentices](apprenticeship.md)). Only raw meat
and fish are preserved.

| Way | Takes |
| --- | --- |
| Salt | 1 Salt Pile a piece |
| Smoke | A lit fire nearby, and 1 Firewood for every 5 pieces |

One press preserves as much of the stack as the salt or the firewood
carried covers. The rest of the stack is left as it was. Nothing is
used when anything is refused.

Who may preserve is open on Patrick's report page
(q-3163-preserve-who). This is the recommended answer.

### The key and the panel

There is no command to type (Patrick, 4 October). When a cook opens
the inventory carrying raw food that is not preserved yet, a line at
the bottom reads "Salt or smoke your food" and names the friend key,
Y. Y closes the inventory and opens the preserving panel. The panel
lists each stack of raw food, nearest to spoiling first, with a Salt
button and a Smoke button. A button that cannot work says why: no
salt, no fire, or no firewood.

## Crafting with food that has days on it

Food with its days on it cooks like plain food. Since fork PR #118 the
engine takes a craft's food from the plain stack first and then from
a stack that differs only in its name. A craft refuses any other named
input. A worn "Iron Sword (85%)", a house's mold or a woven garment's
mark is never spent by a craft, because the craft would give back a
plain piece and lose what the name said.

Eating takes the same way: plain stack first, then a stack that
differs only in its name.

## Where this is

The spoilage block in the server, after the durability block. The
table is the `spoil` block of game/data/food-groups.json: days by
group, `keeps`, `extra`, `preserve`, the salt and firewood records,
and `names`. The names come from game/data/food.json, because the
server cannot read the game's string files.
scripts/dev/Build-SpoilNames.js fills them and rewrites the
`FOOD_GROUPS` line of the server. Run it after either JSON file
changes:

    node scripts/dev/Build-SpoilNames.js

The panel is game/ui/thornswood-preserve.js. The key and the line are
in game/plugins/thornswood-front.js. tests/test-3163-spoilage.js
checks all of it.
