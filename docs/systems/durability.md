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
[Cut items](cut-items.md). The recipe book still lists them. The
server is not asked about them. They are held so a temper can come
back for an event. `recipes.json` is not edited by that list.

Mastercraft was the smith's master perk for tempering past the metal.
The 120% repair is that idea now: the right half can put a piece past
a plain repair. The perk is not a second system on top of the kit.

## Where this is

Not in the server. Nothing tracks a condition on a piece, and no kit
exists as a recipe. The grindstone and the armour table still appear
in the crafting menu. A temper does not reach the server, so it is
not refused and it is not counted as work.
