# Hunter

Only a hunter loots an animal body. Everyone else walks past it.
People, bandits, draugr and dragons are not this list. A bandit and
a draugr are a warrior's kill, not a carcass to dress. See
[Warrior](../professions/warrior.md) and [Death](../death.md).

112 names, 361 placed bodies. Every name, every part, every yield:
[lists/hunter.md](../lists/hunter.md).

## The rank of a body

The rank on the row. A part has no gold price. What it sells for is
the price a person posts.

A pair of zeroes on the list means that rank may not work the body.
The yield is the least and the most of each part, novice first, then
advanced, expert, master. A novice rabbit is 1 to 2. A master on the
same body is 1 to 5. The same four pairs are on every row the table
allows that rank to touch.

## The body

An animal in the hunt table lies for 5 minutes. That is long enough
to dress it. Then it stands back up, which is the engine. A bandit,
a guard, a draugr and a dragon stand back up after 25 seconds, and
no hunter has a verb for them.

A 0-0 yield on your rank means you may not dress that body. You are
told the rank. The parts stay on the corpse for someone who has it.

## Hanging game

A pheasant on a hook is not a corpse. It is a plant-shaped record in
a camp, and loot does not see it. Press E. This is still the hunter,
and it is a different yield and a different wait from dressing a body.

| What hangs | Records | Rank of the rack |
| --- | --- | --- |
| Pheasant, gives Pheasant Breast | 2 (`38b0c`, `38b0d`, both Skyrim.esm) | Novice |
| Rabbit, gives Raw Rabbit Leg | 2 (`38b0e`, `38b0f`, both Skyrim.esm) | Novice |
| Charred skeever, gives Cooked Skeever | 1 advanced (`775fe:Skyrim.esm`), 2 expert (`52185`, `52189`, both Skyrim.esm) | The record's own rank |

The wait is the rack's rank, not yours, and it is your own wait:

| Rack's rank | Wait |
| --- | --- |
| Novice | 10 minutes |
| Advanced | 30 minutes |
| Expert | 1 hour |
| Master | 4 hours |

What you take depends on your hunter rank, least and most: novice 1,
advanced 1 to 2, expert 1 to 3, master 2 to 4. A novice can take the
pheasant and the rabbit. A novice cannot take an expert skeever. One
press is one piece of work, whatever the count.

A restart clears the wait. The carcass clock of 5 minutes does not
apply to a rack, and the rack's wait does not apply to a wolf on the
ground.

One successful dressing is one piece of work. 100 to advanced, then
the count starts again at 250, then at 600. Rest costs 1.5, 1.2,
0.9, 0.6 by your rank. A party member in the same cell banks 15%
toward an extra piece, paid on the seventh.

## What you are handed

1 in Precision (+2 critical chance). The game may ignore it. You do
not get a profession's points from this class. If you are also a
smith, those are the smith page.

## What you cannot do

You cannot pull a flower, mine a seam, fish, or sow a plot. Leather
you did not dress yourself is somebody's, or it is a hide you were
given. Tanning the hide is anybody's work. Making the armour is a
platewright or a tailor.

You cannot loot a person's body for the hunter verb. Theft of what
they carried is the property rule, not this class.

<!-- detail:begin -->

## Every record

Generated from the work tables by `scripts/dev/Write-SystemLists.js`. The same rows are in [hunter](../lists/hunter.md).

| Name | Rank | Records | You receive | Yield novice, advanced, expert, master |
| --- | --- | --- | --- | --- |
| Chicken | novice | 2 | Chicken Breast | 1-2, 1-3, 1-4, 1-5 |
| Cow | novice | 1 | Cow Hide, Raw Beef | 1-2, 1-3, 1-4, 1-5 |
| Deer | novice | 7 | Deer Hide, Venison | 1-2, 1-3, 1-4, 1-5 |
| Dog | novice | 2 | Dog Meat | 1-2, 1-3, 1-4, 1-5 |
| Elk | novice | 3 | Deer Hide, Venison | 1-2, 1-3, 1-4, 1-5 |
| Fox | novice | 1 | Fox Pelt | 1-2, 1-3, 1-4, 1-5 |
| Goat | novice | 5 | Goat Hide, Leg of Goat | 1-2, 1-3, 1-4, 1-5 |
| Husky | novice | 1 | Dog Meat | 1-2, 1-3, 1-4, 1-5 |
| Mudcrab | novice | 4 | Mudcrab Chitin, Mudcrab Legs | 1-2, 1-3, 1-4, 1-5 |
| Pit Wolf | novice | 3 | Wolf Pelt | 1-2, 1-3, 1-4, 1-5 |
| Rabbit | novice | 2 | Raw Rabbit Leg | 1-2, 1-3, 1-4, 1-5 |
| Skeever | novice | 11 | Skeever Tail | 1-2, 1-3, 1-4, 1-5 |
| Slaughterfish | novice | 1 | Slaughterfish Scales | 1-2, 1-3, 1-4, 1-5 |
| Snow Fox | novice | 1 | Snow Fox Pelt | 1-2, 1-3, 1-4, 1-5 |
| Vale Deer | novice | 1 | Vale Deer Hide, Venison | 1-2, 1-3, 1-4, 1-5 |
| Vale Sabre Cat | novice | 2 | Eye of Sabre Cat, Sabre Cat Tooth, Vale Sabre Cat Hide | 1-2, 1-3, 1-4, 1-5 |
| Wolf | novice | 9 | Wolf Pelt | 1-2, 1-3, 1-4, 1-5 |
| Betty Netch | advanced | 1 | Netch Jelly, Netch Leather | 0-0, 1-3, 1-4, 1-5 |
| Bull Netch | advanced | 1 | Netch Jelly, Netch Leather | 0-0, 1-3, 1-4, 1-5 |
| Frost Troll | advanced | 2 | Troll Fat | 0-0, 1-3, 1-4, 1-5 |
| Frostbite Spider | advanced | 17 | Frostbite Venom | 0-0, 1-3, 1-4, 1-5 |
| Horker | advanced | 1 | Horker Meat, Horker Tusk | 0-0, 1-3, 1-4, 1-5 |
| Horse | advanced | 13 | Horse Hide, Horse Meat | 0-0, 1-3, 1-4, 1-5 |
| Ice Wolf | advanced | 2 | Ice Wolf Pelt | 0-0, 1-3, 1-4, 1-5 |
| Netch Calf | advanced | 1 | Netch Jelly | 0-0, 1-3, 1-4, 1-5 |
| Sabre Cat | advanced | 3 | Eye of Sabre Cat, Sabre Cat Pelt, Sabre Cat Tooth | 0-0, 1-3, 1-4, 1-5 |
| Spectral Warhound | advanced | 1 | Ectoplasm | 0-0, 1-3, 1-4, 1-5 |
| Troll | advanced | 3 | Troll Fat | 0-0, 1-3, 1-4, 1-5 |
| Wolf | advanced | 1 | Ice Wolf Pelt | 0-0, 1-3, 1-4, 1-5 |
| Cave Bear | expert | 2 | Bear Claws, Bear Pelt | 0-0, 0-0, 1-4, 1-5 |
| Chaurus | expert | 5 | Chaurus Chitin | 0-0, 0-0, 1-4, 1-5 |
| Chaurus Reaper | expert | 1 | Chaurus Chitin | 0-0, 0-0, 1-4, 1-5 |
| Chaurusflyer | expert | 3 | Chaurus Chitin, Chaurus Hunter Antennae | 0-0, 0-0, 1-4, 1-5 |
| Snow Bear | expert | 1 | Bear Claws, Snow Bear Pelt | 0-0, 0-0, 1-4, 1-5 |
| Snowy Sabre Cat | expert | 1 | Eye of Sabre Cat, Sabre Cat Snow Pelt, Sabre Cat Tooth | 0-0, 0-0, 1-4, 1-5 |
| Mammoth | master | 4 | Mammoth Snout, Mammoth Tusk | 0-0, 0-0, 0-0, 1-5 |

<!-- detail:end -->

## Where this is

The verb, the 5 minutes, the rank on the row, and the yields are in the
server. The list is that table.
