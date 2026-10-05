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
| Albino Spider | novice | 1 | Albino Spider Pod, Damaged Albino Spider Pod | 1-2, 1-3, 1-4, 1-5 |
| Alpha Wolf | novice | 1 | Wolf Pelt | 1-2, 1-3, 1-4, 1-5 |
| Animal Gladiator | novice | 1 | Wolf Pelt | 1-2, 1-3, 1-4, 1-5 |
| Aska | novice | 1 | Dog Meat | 1-2, 1-3, 1-4, 1-5 |
| Barnaby | novice | 1 | Dog Meat | 1-2, 1-3, 1-4, 1-5 |
| Biter | novice | 1 | Skeever Meat, Skeever Tail | 1-2, 1-3, 1-4, 1-5 |
| Bran | novice | 1 | Dog Meat | 1-2, 1-3, 1-4, 1-5 |
| Buried Storage | novice | 1 | Chicken Breast | 1-2, 1-3, 1-4, 1-5 |
| Chicken | novice | 6 | Chicken Breast | 1-2, 1-3, 1-4, 1-5 |
| Chloe | novice | 1 | Goat Hide, Goat Meat | 1-2, 1-3, 1-4, 1-5 |
| Constipated Chicken | novice | 1 | Chicken Breast | 1-2, 1-3, 1-4, 1-5 |
| Cotton | novice | 1 | Raw Rabbit Leg | 1-2, 1-3, 1-4, 1-5 |
| Cow | novice | 6 | Cow Hide, Raw Beef | 1-2, 1-3, 1-4, 1-5 |
| Dawnguard Husky | novice | 1 | Dog Meat | 1-2, 1-3, 1-4, 1-5 |
| Deer | novice | 10 | Deer Hide, Venison | 1-2, 1-3, 1-4, 1-5 |
| Dog | novice | 6 | Dog Meat | 1-2, 1-3, 1-4, 1-5 |
| Elk | novice | 4 | Deer Hide, Venison | 1-2, 1-3, 1-4, 1-5 |
| Fire Storm | novice | 1 | Wolf Pelt | 1-2, 1-3, 1-4, 1-5 |
| FishingNetSlaughterfish | novice | 1 | Slaughterfish Meat, Slaughterfish Scales | 1-2, 1-3, 1-4, 1-5 |
| Flaming Thrall | novice | 1 | Wolf Pelt | 1-2, 1-3, 1-4, 1-5 |
| Fox | novice | 2 | Fox Pelt | 1-2, 1-3, 1-4, 1-5 |
| Giant Mudcrab | novice | 1 | Mudcrab Chitin, Mudcrab Legs | 1-2, 1-3, 1-4, 1-5 |
| Gleda the Goat | novice | 1 | Goat Hide, Goat Meat | 1-2, 1-3, 1-4, 1-5 |
| Goat | novice | 9 | Goat Hide, Goat Meat | 1-2, 1-3, 1-4, 1-5 |
| Hund | novice | 1 | Dog Meat | 1-2, 1-3, 1-4, 1-5 |
| Husky | novice | 2 | Dog Meat | 1-2, 1-3, 1-4, 1-5 |
| Jar Bomb | novice | 1 | Wolf Pelt | 1-2, 1-3, 1-4, 1-5 |
| Kit | novice | 1 | Fox Pelt | 1-2, 1-3, 1-4, 1-5 |
| Loki | novice | 1 | Dog Meat | 1-2, 1-3, 1-4, 1-5 |
| Meeko | novice | 1 | Dog Meat | 1-2, 1-3, 1-4, 1-5 |
| Mudcrab | novice | 8 | Mudcrab Chitin, Mudcrab Legs | 1-2, 1-3, 1-4, 1-5 |
| Old Salty | novice | 1 | Mudcrab Chitin, Mudcrab Legs | 1-2, 1-3, 1-4, 1-5 |
| Pack Member | novice | 1 | Wolf Pelt | 1-2, 1-3, 1-4, 1-5 |
| Pincer | novice | 1 | Mudcrab Chitin, Mudcrab Legs | 1-2, 1-3, 1-4, 1-5 |
| Pit Wolf | novice | 3 | Wolf Pelt | 1-2, 1-3, 1-4, 1-5 |
| Pumpkin | novice | 1 | Fox Pelt | 1-2, 1-3, 1-4, 1-5 |
| Rabbit | novice | 6 | Raw Rabbit Leg | 1-2, 1-3, 1-4, 1-5 |
| Sceolang | novice | 1 | Dog Meat | 1-2, 1-3, 1-4, 1-5 |
| Sigyn | novice | 1 | Dog Meat | 1-2, 1-3, 1-4, 1-5 |
| Skeever | novice | 22 | Skeever Meat, Skeever Tail | 1-2, 1-3, 1-4, 1-5 |
| Skeever Guardian Spirit | novice | 1 | Skeever Meat, Skeever Tail | 1-2, 1-3, 1-4, 1-5 |
| Slaughterfish | novice | 2 | Slaughterfish Meat, Slaughterfish Scales | 1-2, 1-3, 1-4, 1-5 |
| Snow Fox | novice | 2 | Snow Fox Pelt | 1-2, 1-3, 1-4, 1-5 |
| Solstheim Mudcrab | novice | 1 | Mudcrab Chitin, Mudcrab Legs | 1-2, 1-3, 1-4, 1-5 |
| Stray Dog | novice | 2 | Dog Meat | 1-2, 1-3, 1-4, 1-5 |
| Stump | novice | 1 | Dog Meat | 1-2, 1-3, 1-4, 1-5 |
| Sulvar's Dog | novice | 1 | Dog Meat | 1-2, 1-3, 1-4, 1-5 |
| Tiber | novice | 1 | Dog Meat | 1-2, 1-3, 1-4, 1-5 |
| Torom | novice | 1 | Dog Meat | 1-2, 1-3, 1-4, 1-5 |
| Vale Deer | novice | 2 | Vale Deer Hide, Venison | 1-2, 1-3, 1-4, 1-5 |
| Vale Sabre Cat | novice | 4 | Eye of Sabre Cat, Sabre Cat Tooth, Vale Sabre Cat Hide | 1-2, 1-3, 1-4, 1-5 |
| Venomfang Skeever | novice | 1 | Skeever Meat, Skeever Tail | 1-2, 1-3, 1-4, 1-5 |
| Vigilance | novice | 1 | Dog Meat | 1-2, 1-3, 1-4, 1-5 |
| Vix | novice | 1 | Snow Fox Pelt | 1-2, 1-3, 1-4, 1-5 |
| White Stag | novice | 2 | Deer Hide, Venison | 1-2, 1-3, 1-4, 1-5 |
| Wolf | novice | 19 | Wolf Pelt | 1-2, 1-3, 1-4, 1-5 |
| Wolf Guardian Spirit | novice | 1 | Wolf Pelt | 1-2, 1-3, 1-4, 1-5 |
| Ysgramor | novice | 1 | Dog Meat | 1-2, 1-3, 1-4, 1-5 |
| Aldhissla | advanced | 1 | Troll Fat | 0-0, 1-3, 1-4, 1-5 |
| Animal Gladiator | advanced | 1 | Eye of Sabre Cat, Sabre Cat Pelt, Sabre Cat Tooth | 0-0, 1-3, 1-4, 1-5 |
| Armored Frost Troll | advanced | 2 | Troll Fat | 0-0, 1-3, 1-4, 1-5 |
| Armored Troll | advanced | 2 | Troll Fat | 0-0, 1-3, 1-4, 1-5 |
| Arvak | advanced | 1 | Horse Hide, Horse Meat | 0-0, 1-3, 1-4, 1-5 |
| Ash Hopper | advanced | 4 | Ash Hopper Jelly, Ash Hopper Leg, Ash Hopper Meat, Chitin Plate | 0-0, 1-3, 1-4, 1-5 |
| Betty Netch | advanced | 1 | Netch Jelly, Netch Leather | 0-0, 1-3, 1-4, 1-5 |
| Bull Netch | advanced | 1 | Netch Jelly, Netch Leather | 0-0, 1-3, 1-4, 1-5 |
| Cave Troll | advanced | 1 | Troll Fat | 0-0, 1-3, 1-4, 1-5 |
| Farkas's Wolf Spirit | advanced | 1 | Ice Wolf Pelt | 0-0, 1-3, 1-4, 1-5 |
| Frost | advanced | 1 | Horse Hide, Horse Meat | 0-0, 1-3, 1-4, 1-5 |
| Frost Troll | advanced | 7 | Troll Fat | 0-0, 1-3, 1-4, 1-5 |
| Frostbite Spider | advanced | 31 | Frostbite Venom | 0-0, 1-3, 1-4, 1-5 |
| Giant Frostbite Spider | advanced | 6 | Frostbite Venom | 0-0, 1-3, 1-4, 1-5 |
| Guardian Troll Spirit | advanced | 1 | Troll Fat | 0-0, 1-3, 1-4, 1-5 |
| Horker | advanced | 3 | Horker Meat, Horker Tusk | 0-0, 1-3, 1-4, 1-5 |
| Horker Youngling | advanced | 1 | Horker Meat, Horker Tusk | 0-0, 1-3, 1-4, 1-5 |
| Horse | advanced | 49 | Horse Hide, Horse Meat | 0-0, 1-3, 1-4, 1-5 |
| Hugo | advanced | 1 | Troll Fat | 0-0, 1-3, 1-4, 1-5 |
| Ice Wolf | advanced | 4 | Ice Wolf Pelt | 0-0, 1-3, 1-4, 1-5 |
| Karinda | advanced | 1 | Horse Hide, Horse Meat | 0-0, 1-3, 1-4, 1-5 |
| Kodlak's Wolf Spirit | advanced | 1 | Ice Wolf Pelt | 0-0, 1-3, 1-4, 1-5 |
| Lis | advanced | 2 | Frostbite Venom | 0-0, 1-3, 1-4, 1-5 |
| Lord Tusk | advanced | 1 | Horker Meat, Horker Tusk | 0-0, 1-3, 1-4, 1-5 |
| Netch Calf | advanced | 1 | Netch Jelly | 0-0, 1-3, 1-4, 1-5 |
| Pack Member | advanced | 1 | Ice Wolf Pelt | 0-0, 1-3, 1-4, 1-5 |
| Sabre Cat | advanced | 6 | Eye of Sabre Cat, Sabre Cat Pelt, Sabre Cat Tooth | 0-0, 1-3, 1-4, 1-5 |
| Shadowmere | advanced | 1 | Horse Hide, Horse Meat | 0-0, 1-3, 1-4, 1-5 |
| Snow Troll | advanced | 3 | Troll Fat | 0-0, 1-3, 1-4, 1-5 |
| Spectral Warhound | advanced | 1 | Ectoplasm | 0-0, 1-3, 1-4, 1-5 |
| Spider | advanced | 1 | Frostbite Venom | 0-0, 1-3, 1-4, 1-5 |
| The Enchanted Woman | advanced | 1 | Troll Fat | 0-0, 1-3, 1-4, 1-5 |
| Troll | advanced | 5 | Troll Fat | 0-0, 1-3, 1-4, 1-5 |
| Udefrykte | advanced | 1 | Troll Fat | 0-0, 1-3, 1-4, 1-5 |
| Vilkas's Wolf Spirit | advanced | 1 | Ice Wolf Pelt | 0-0, 1-3, 1-4, 1-5 |
| Wolf | advanced | 1 | Ice Wolf Pelt | 0-0, 1-3, 1-4, 1-5 |
| Wolf Spirit | advanced | 1 | Ice Wolf Pelt | 0-0, 1-3, 1-4, 1-5 |
| Wounded Frostbite Spider | advanced | 2 | Frostbite Venom | 0-0, 1-3, 1-4, 1-5 |
| Animal Gladiator | expert | 1 | Bear Claws, Bear Pelt | 0-0, 0-0, 1-4, 1-5 |
| Bear | expert | 4 | Bear Claws, Bear Pelt | 0-0, 0-0, 1-4, 1-5 |
| Bear Avatar | expert | 1 | Bear Claws, Bear Pelt | 0-0, 0-0, 1-4, 1-5 |
| Big Bear | expert | 1 | Bear Claws, Bear Pelt | 0-0, 0-0, 1-4, 1-5 |
| Cave Bear | expert | 5 | Bear Claws, Bear Pelt, Cave Bear Pelt | 0-0, 0-0, 1-4, 1-5 |
| Chaurus | expert | 7 | Chaurus Chitin | 0-0, 0-0, 1-4, 1-5 |
| Chaurus Hunter | expert | 4 | Chaurus Chitin, Chaurus Hunter Antennae | 0-0, 0-0, 1-4, 1-5 |
| Chaurus Hunter Fledgling | expert | 2 | Chaurus Chitin, Chaurus Hunter Antennae | 0-0, 0-0, 1-4, 1-5 |
| Chaurus Reaper | expert | 2 | Chaurus Chitin | 0-0, 0-0, 1-4, 1-5 |
| Chaurusflyer | expert | 4 | Chaurus Chitin, Chaurus Hunter Antennae | 0-0, 0-0, 1-4, 1-5 |
| Familiar | expert | 1 | Bear Claws, Bear Pelt | 0-0, 0-0, 1-4, 1-5 |
| Frozen Chaurus | expert | 7 | Chaurus Chitin | 0-0, 0-0, 1-4, 1-5 |
| Sabre Cat Guardian Spirit | expert | 1 | Eye of Sabre Cat, Sabre Cat Snow Pelt, Sabre Cat Tooth | 0-0, 0-0, 1-4, 1-5 |
| Snow Bear | expert | 3 | Bear Claws, Snow Bear Pelt | 0-0, 0-0, 1-4, 1-5 |
| Snowy Sabre Cat | expert | 3 | Eye of Sabre Cat, Sabre Cat Snow Pelt, Sabre Cat Tooth | 0-0, 0-0, 1-4, 1-5 |
| Ursine Guardian | expert | 1 | Bear Claws, Snow Bear Pelt | 0-0, 0-0, 1-4, 1-5 |
| Karhu | master | 1 | Bear Claws, Pelt of Karhu, Skull | 0-0, 0-0, 0-0, 1-5 |
| Mammoth | master | 5 | Mammoth Snout, Mammoth Tusk | 0-0, 0-0, 0-0, 1-5 |
| Mammoth Guardian Spirit | master | 1 | Mammoth Snout, Mammoth Tusk | 0-0, 0-0, 0-0, 1-5 |
| Netch | master | 1 | Mammoth Snout, Mammoth Tusk | 0-0, 0-0, 0-0, 1-5 |

<!-- detail:end -->

## Where this is

The verb, the 5 minutes, the rank on the row, and the yields are in the
server. The list is that table. A rack's wait is kept on the rack and
shared by every hunter (#1413), and a picked-clean rack says how long
is left in minutes and hours (#1826).
