# Miner

A pickaxe in the pack, not necessarily equipped. Any pickaxe except a
war pick. 100 uses. When it breaks, a smith makes the next one.
Nothing hands you another.

18 names, 581 veins. Every name:
[lists/miner.md](../lists/miner.md).

| Ore | Rank | Veins | Yield if you may work it |
| --- | --- | --- | --- |
| Clay | Novice | 5 | 1-2, 1-3, 1-4, 1-5 |
| Iron | Novice | 82 | 1-2, 1-3, 1-4, 1-5 |
| Quarried stone | Novice | 1 | 1-2, 1-3, 1-4, 1-5 |
| Corundum | Advanced | 81 | 0-0, 1-3, 1-4, 1-5 |
| Heart stone | Advanced | 4 | 0-0, 1-3, 1-4, 1-5 |
| Orichalcum | Advanced | 76 | 0-0, 1-3, 1-4, 1-5 |
| Quicksilver | Advanced | 76 | 0-0, 1-3, 1-4, 1-5 |
| Shellbug chitin | Advanced | 1 | 0-0, 1-3, 1-4, 1-5 |
| Silver | Advanced | 76 | 0-0, 1-3, 1-4, 1-5 |
| Gold | Expert | 76 | 0-0, 0-0, 1-4, 1-5 |
| Malachite | Expert | 7 | 0-0, 0-0, 1-4, 1-5 |
| Moonstone | Expert | 76 | 0-0, 0-0, 1-4, 1-5 |
| Amethyst | Master | 3 | 0-0, 0-0, 0-0, 1-5 |
| Ebony | Master | 6 | 0-0, 0-0, 0-0, 1-5 |
| Emerald | Master | 3 | 0-0, 0-0, 0-0, 1-5 |
| Ruby | Master | 3 | 0-0, 0-0, 0-0, 1-5 |
| Sapphire | Master | 3 | 0-0, 0-0, 0-0, 1-5 |
| Stalhrim | Master | 2 | 0-0, 0-0, 0-0, 1-5 |

The four pairs are novice, advanced, expert, master. A 0-0 means that
rank cannot work the seam. The pair that is open is the least and the
most taken off the seam in one swing.

Heart stone would be master by its price. It is advanced anyway, so a
[Bladebinder](../professions/enchanter/bladebinder.md) can buy it from
someone who is not a master miner. 160 of the 161 staves ask for one.

The price bands, for anything added later: up to 14 gold novice, up
to 29 advanced, up to 59 expert, otherwise master. Heart stone is the
exception already made.

## The seam

A seam holds 20. One swing takes the yield and is one piece of work,
not one per piece of ore. A novice taking 2 empties the seam in fewer
swings than a novice taking 1, and climbs more slowly off that seam
because the work is the swing.

Five full seams of 20, if every swing took 1, is the 100 to advanced.
A swing that takes more finishes the seam early. Expert is 250 swings
after that, master 600 after that.

The seam comes back for everybody at once, not per person.

| Seams | Back in |
| --- | --- |
| Iron, gold, corundum, silver | 10 minutes |
| Everything else, including heart stone, ebony, the gems, stalhrim, moonstone, quicksilver | 30 minutes |

Clicking again while the pick is still in the air is not a second
swing. Nothing is said. The ore is not given twice.

Smelting the ore into an ingot is anybody's work, at a forge, and the
forge burns a charcoal. See [Smith](../professions/smith.md).

## The salt quarry

One quarry this server placed, `dde4ef:Thornswood-Content.esp`. It is
not one of the 581 veins and it does not use the deposit of 20.

Any miner, from novice. A pickaxe, the same 100 uses. One swing is
one piece of work.

| Your rank | Salt |
| --- | --- |
| Novice | 1 to 2 |
| Advanced | 1 to 3 |
| Expert | 1 to 4 |
| Master | 1 to 5 |

From expert up, a swing can also bring 1 Fire Salts, Frost Salts, or
Void Salts. The chance is 12% at expert and 24% at master. Advanced
and novice bring salt only.

The quarry's own wait is 20 seconds, not 10 minutes and not 30. It
is stamped when the swing starts. A click during the swing is not a
second strike. A restart clears it. The salt is `34cdf:Skyrim.esm`.

## What you are handed

1 in Might (+0.05 melee). A smith who is also a miner stacks this on
the smith's Might.

<!-- detail:begin -->

## Every record

Generated from the work tables by `scripts/dev/Write-SystemLists.js`. The same rows are in [miner](../lists/miner.md).

| Name | Rank | Records | You receive | Gold | Yield novice, advanced, expert, master |
| --- | --- | --- | --- | --- | --- |
| Clay | novice | 5 | Clay | 1 | 1-2, 1-3, 1-4, 1-5 |
| Iron Ore | novice | 82 | Iron Ore | 2 | 1-2, 1-3, 1-4, 1-5 |
| Quarried Stone | novice | 1 | Quarried Stone | 2 | 1-2, 1-3, 1-4, 1-5 |
| Corundum Ore | advanced | 81 | Corundum Ore | 20 | 0-0, 1-3, 1-4, 1-5 |
| Heart Stone | advanced | 4 | Heart Stone | 100 | 0-0, 1-3, 1-4, 1-5 |
| Orichalcum Ore | advanced | 76 | Orichalcum Ore | 20 | 0-0, 1-3, 1-4, 1-5 |
| Quicksilver Ore | advanced | 76 | Quicksilver Ore | 25 | 0-0, 1-3, 1-4, 1-5 |
| Shellbug Chitin | advanced | 1 | Shellbug Chitin | 25 | 0-0, 1-3, 1-4, 1-5 |
| Silver Ore | advanced | 76 | Silver Ore | 25 | 0-0, 1-3, 1-4, 1-5 |
| Gold Ore | expert | 76 | Gold Ore | 50 | 0-0, 0-0, 1-4, 1-5 |
| Malachite Ore | expert | 7 | Malachite Ore | 30 | 0-0, 0-0, 1-4, 1-5 |
| Moonstone Ore | expert | 76 | Moonstone Ore | 30 | 0-0, 0-0, 1-4, 1-5 |
| Amethyst | master | 3 | Amethyst | 120 | 0-0, 0-0, 0-0, 1-5 |
| Ebony Ore | master | 6 | Ebony Ore | 60 | 0-0, 0-0, 0-0, 1-5 |
| Emerald | master | 3 | Emerald | 600 | 0-0, 0-0, 0-0, 1-5 |
| Ruby | master | 3 | Ruby | 200 | 0-0, 0-0, 0-0, 1-5 |
| Sapphire | master | 3 | Sapphire | 400 | 0-0, 0-0, 0-0, 1-5 |
| Stalhrim | master | 2 | Stalhrim | 200 | 0-0, 0-0, 0-0, 1-5 |

<!-- detail:end -->

## Where this is

The 581 veins, the 20, the two clocks, the heart-stone exception, and
the pickaxe wear are in the server.
