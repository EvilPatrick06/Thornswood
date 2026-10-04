# Durability

Worn gear has a condition, from 0% to 120%. Repair is a kit. It is
not the grindstone and it is not the armour table.

Three kits. Smiths and tailors make them.

| Kit | Who makes it | What it repairs |
| --- | --- | --- |
| Weapon Kit | Edgewright | Weapons |
| Armor Kit | Platewright | Armour |
| Sewing Kit | Haberdasher | Clothing, robes, cloaks, capes |

Liverywright is the Haberdasher's sister half. Novice livery is
already theirs. A Sewing Kit is the Haberdasher's recipe. A
Liverywright makes one when the sister-half rules on
[Masters and apprentices](apprenticeship.md) say they may do
Haberdasher work.

The person holding the kit can use it on a piece they are repairing.
The result depends on who they are.

| Who uses the kit | Condition after |
| --- | --- |
| The half that makes that kit | 120% |
| Anyone else, including the other half of the same profession | 100% |

120% is what allows a buff. 100% is a sound repair and nothing more.

| Piece | At 120% |
| --- | --- |
| Weapon | 5% more damage |
| Armour | 5% more of that piece's armour rating |
| Clothing, robes, cloaks, capes | The higher condition, and no buff |

At 0%, a piece that is being worn has a 10% chance to break on a hit.
An hour of standing around does not roll it. A piece at 0% that is
sitting in a chest is not worn, and this chance does not apply to it.

Glass, ebony, and stalhrim take the same kits as iron. They are
scarce to make. They are not a different repair.

Condition on a piece that was made or bought, and then left in a
container, is the Dull rule on [Gold](gold.md). 5% per real day, in
a shop chest or a house container. A pack does not dull. Worn gear
uses the hit rule above, not this clock.

## What this replaces

Tempering, the armour table and the sharpening wheel, is not how a
piece is repaired. Those 1809 rows are in
[Cut items](cut-items.md). The recipe book still lists them. A temper
at either bench is refused, the ingot stays in the pack, and it is not
counted as work. They are held so a temper can come back for an
event. `recipes.json` is not edited by that list.

Mastercraft was the smith's master perk for tempering past the metal.
The 120% repair is that idea now: the right half can put a piece past
a plain repair. The perk is not a second system on top of the kit.

## Where this is

In the server. A piece's condition is written on its name when it is
not 100%: Iron Sword (85%). A plain piece is at 100%, and so is every
piece as it is made. Rings, amulets and circlets carry no condition.
The pickaxe, the woodcutter's axe and the shovel wear out by use
instead.

`/repair` lists what you carry that is not at 100%, and the kits you
hold. `/repair <name>` mends one piece with the kit that fits it, to
120% for the half that makes that kit and to 100% for anyone else, and
the kit is used up. A piece already at or above that number is not
touched.

At 0%, a worn piece has the 10% chance on each hit: armour and
clothing on the person hit, and the weapon the hit was landed with. A
broken piece is gone.

A chest or container in a claimed building keeps its own day from the
first time it is opened. Each day that turns takes 5% off everything
in it with a condition, and the loss is written when it is next
opened. Opening it does not move its day.

A temper at the grindstone or the armour table is refused, and it is
not counted as work.

Not yet. The three kits are not records in the plugin, so no kit can
be made, and `/repair` says so. The 5% more damage and armour at 120%
is not applied, because the engine works damage out on its own.
Nothing on this page lowers the condition of worn gear, except the
chest it sat in before. A trade hands a piece over at 100% (issue
#1594). A piece that is not at 100% cannot be enchanted, because the
engine takes a plain piece for an enchantment. The grindstone and the
armour table still appear in the crafting menu.
