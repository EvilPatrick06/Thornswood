# Alchemist

Poisons and medicine. Skyrim has no alchemy recipe records. A potion
is whatever the ingredients share, worked out in the alchemy menu.
The server cannot hold you to a row that does not exist. It holds you
to the bench.

- [Blightbrewer](alchemist/blightbrewer.md) makes poisons.
- [Physicker](alchemist/physicker.md) makes medicine.

The lab is closed furniture. Blightbrewer or Physicker, from novice.
Anyone else is turned away, including a cook and a mage, unless a
master alchemist has taught them this as one of their two outside
trades. That teaching is novice and stops there.

Both halves may use the lab. The split is what you are for, not a
second door on the furniture. The day bench recipes exist, the poison
rows go to Blightbrewer and the medicine rows go to Physicker. Until
then the menu is the work.

A batch is two or more ingredients that share an effect on the short
list. The effects that are allowed, and the rank each one asks for,
are [Mixtures](../mixtures.md). An effect that is not on that list is
refused, even if the ingredients share it. This repo does not have a
table of which ingredient carries which effect, so this page cannot
honestly list "nightshade makes this poison" as if that row had been
measured.
The ingredients you can take out of the world are the gatherer's
plants, the hunter's parts, and the salts a miner can pull from the
quarry at expert and master. See [Gatherer](../classes/gatherer.md)
and [Miner](../classes/miner.md). Buying them is the other way.

A bottle the lab creates is not a record in the food table. It is
still a potion for thirst: the sip of 5 on
[Potions and restoration](../potions.md). It is not a meal. The food
table's poison and potion names are not usable as a catalogue. Most
of them did not survive as words. They are not repeated here.

Learned ingredient effects live on the character the game saved.
This server does not keep that list. A relog can forget what the lab
had revealed. Do not treat a revealed effect as a rank.

## Master Chemist

At master, either half. Every batch yields two instead of one. One
craft is still one piece of work.

## What you are handed

1 in Toughness (+10 poison resistance and +10 disease resistance) and
1 in Clarity (+10% magicka recovery). The half places one more.

## The ladder

100, then 250, then 600, the count resetting. A successful batch is
one piece. There is no recipe list to climb by, so the work has to be
the batch the server sees. See the bottom of each half.

## Where this is

The lab gate is in the server. A batch is one piece of work, and
Master Chemist's second bottle goes on the same stack once the first
is in the pack. The mixtures list is in the server and is asked once
the engine says which effects a brew carries, which it does not yet
(see [Mixtures](../mixtures.md)). There is no item list, because
there are no recipe rows.
