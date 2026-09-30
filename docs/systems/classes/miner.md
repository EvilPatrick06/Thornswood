# Miner

A pickaxe in the pack, not necessarily equipped. Any pickaxe except a
war pick. 50 uses. When it breaks, a smith makes the next one.
Nothing hands you another.

18 names, 581 veins. Every name:
[lists/miner.md](../lists/miner.md).

| Ore | Rank | Veins | One swing, if you may work it |
| --- | --- | --- | --- |
| Clay | Novice | 5 | 1, and a chance of one more |
| Iron | Novice | 82 | 1, and a chance of one more |
| Quarried stone | Novice | 1 | 1, and a chance of one more |
| Corundum | Advanced | 81 | 1, and a chance of one more |
| Orichalcum | Advanced | 76 | 1, and a chance of one more |
| Quicksilver | Advanced | 76 | 1, and a chance of one more |
| Shellbug chitin | Advanced | 1 | 1, and a chance of one more |
| Silver | Advanced | 76 | 1, and a chance of one more |
| Gold | Expert | 76 | 1, and a chance of one more |
| Malachite | Expert | 7 | 1, and a chance of one more |
| Moonstone | Expert | 76 | 1, and a chance of one more |
| Amethyst | Master | One place | 1, and a chance of one more |
| Ebony | Master | One place | 1, and a chance of one more |
| Emerald | Master | One place | 1, and a chance of one more |
| Ruby | Master | One place | 1, and a chance of one more |
| Sapphire | Master | One place | 1, and a chance of one more |
| Stalhrim | Master | One place | 1, and a chance of one more |
| Heart stone | Master | One place | 1, and a chance of one more |

A rank below the row cannot work that seam. The swing, when it is
allowed, takes 1 ore of that seam. It is one piece of work, not one
per piece of ore.

Each rank above novice spends less rest on the swing, and has a
higher chance that the same swing also drops one extra ore. The extra
can be a different metal. An iron seam can hand you an iron ore and a
gold ore. The chances are not set. The rest costs are the ones on
[Professions](../professions.md): 1.5, 1.2, 0.9, 0.6. A further cut
was not named.

Heart stone is master, by its price. The staves that still ask for it
are the ones left in the college book. See
[Bladebinder](../professions/enchanter/bladebinder.md).

The price bands, for anything added later: up to 14 gold novice, up
to 29 advanced, up to 59 expert, otherwise master.

## The seam

A seam holds 20. One swing takes 1, and sometimes 1 more, and is one
piece of work. Five full seams of 20 is the 100 to advanced. Expert
is 250 swings after that, master 600 after that.

The seam comes back for everybody at once, not per person.

| Seams | Back in |
| --- | --- |
| Iron | 15 minutes |
| Gold | 20 minutes |
| Corundum, silver | 10 minutes |
| Clay, quarried stone, orichalcum, quicksilver, moonstone, malachite, shellbug | 30 minutes |
| Ebony, the gems, stalhrim, heart stone | One place. A custom steward stands on it. Someone who has not been let in takes nothing, and the place does not refill for them. |

Clicking again while the pick is still in the air is not a second
swing. Nothing is said. The ore is not given twice.

Smelting the ore into an ingot is anybody's work, at a forge, and the
forge burns a charcoal. See [Smith](../professions/smith.md).

## The salt quarry

One quarry this server placed, `dde4ef:Thornswood-Content.esp`. It is
not one of the 581 veins and it does not use the deposit of 20.

Any miner, from novice. A pickaxe, the same 50 uses. One swing is
one piece of work. The "always 1" rule above is the ore seams. This
quarry still uses the pairs in the table.

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

The server still has 581 veins, a deposit of 20, yields that climb
from 1-2 up to 1-5, heart stone forced to advanced, and a pickaxe of
100 uses. Iron, gold, corundum and silver all come back in 10
minutes. Ebony is 6 veins, the gems are 3 each, stalhrim is 2, heart
stone is 4. There is no steward on a single place. The table under
Every record is that server book. The numbers above it are the plan.
