# Physicker

Medicine. The half that closes a cut, breaks a fever, and sets a
bone. The half places 1 in Clarity. The profession also places 1 in
Clarity, so a Physicker starts at 2: +20% magicka recovery.

## What you can do

Use the alchemy lab from novice. Cure disease potions you make are
still the thirst sip of 5, and they clear one ordinary disease when
the disease list is in. See [Disease](../../disease.md).

A remedy you make is what [Injury](../../injury.md) means by a
physicker's remedy: it closes a cut the way a bandage does, and it
is the better answer to wound fever. A temple rite is not this half.
You are not a priest because you picked it. Priest is roleplay.

Your sister half is Blightbrewer at novice, same lab.

## What you cannot do

You cannot clear an agreed loss, a missing hand, or a missing eye.
Those need the yes, and a potion does not wash them off.

You cannot set a crooked heal that the plan reserves for a master
physicker or a temple until you are master. At master, Master
Chemist is the double batch. The master treatment of a crooked bone
is the injury page, and it is not a separate recipe.

Your recipes are two, made at the alchemy lab Thornswood places: the
poultice at novice and the remedy at advanced. Everything else you
make is brewed.

<!-- detail:begin -->

## Every recipe

Generated from `game/data/recipes.json` by `scripts/dev/Write-SystemLists.js`. 2 recipes. 2 reach the server. None of them are tempering. The same rows, with ids, are in [alchemist-physicker](../../lists/alchemist-physicker.md).

The rank on the row is the rank. It is the dearest ingredient a class produces. An item has no gold price.

### Names that reach the server

**Novice** (1 name). Poultice.

**Advanced** (1 name). Physicker's Remedy.

**Expert.** None.

**Master.** None.

| Item | Makes | Rank | Kind | Bench | Asks for | Race | Server asked | Id |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Poultice | 1 | novice | Other goods | ThornswoodCraftingAlchemy | 1 Tundra Cotton, 1 Garlic |  | yes | `154c6:Thornswood-Content.esp` |
| Physicker's Remedy | 1 | advanced | Other goods | ThornswoodCraftingAlchemy | 1 Mudcrab Chitin, 1 Blue Mountain Flower |  | yes | `154c7:Thornswood-Content.esp` |

<!-- detail:end -->

## Where this is

The lab gate, the double batch and the disease list are in the
server. A cure disease potion you brew is still only the sip, because
the server cannot read what a brewed potion does. The poultice and the
remedy are in Thornswood-Content.esp, and the recipe table names them
yours (#1622). The lab Thornswood places, where they are made, is in
the bench table since #1713: it opens for anyone who can work this
half at novice, so a Physicker, a Blightbrewer by the sister half,
and anyone a master has taught it. Setting a bone is a button on the
wounds panel: X on somebody hurt, or H in your inventory for your own
(see [Injury](../../injury.md)). At master the same button clears a
crooked heal.
Toughness on the tree already writes disease
resistance. This half's Clarity point already lands.
