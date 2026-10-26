# Gatherer

Reagents out of the world. Food plants are the farmer's. 46 names,
105 placed plants.

Every name: [lists/gatherer.md](../lists/gatherer.md).

## The rank of a plant

The rank on the row. A plant has no gold price. What it sells for is
the price a person posts.

A plant above your rank is refused by name. You are told the rank it
takes. You keep standing there. Nothing is picked.

## What one pick gives

One. The rank does not grow the handful. It only opens the plant.
A master and a novice both take 1 blue mountain flower off a plant
the novice is allowed to touch. The extra yield pairs on a carcass,
a seam, a fish and a plot are not this verb.

One successful pick is one piece of work. There is no deposit of 20
the way a seam has, so a hillside of flowers is more pieces per hour
than one iron vein. The ladder is still 100, then 250, then 600. If
gatherers climb faster than miners, the cause is the hillside, not a
different ladder.

## The wait

Ten minutes after a pick, that plant, for everybody. The key is the
plant, not the person. The flower beside it is a different plant.

A press from someone who is not a gatherer does not pick it. The
plant stays. They are told it is not their work. A gatherer below
the plant's rank is the same: nothing is taken.

## Wheat, nirnroot, and the hive

Wheat (`bb953:Skyrim.esm`, TreeFloraWheat01) is in the reagent table
at advanced, gold 5, and it is also a crop with a 135 minute grow.
The crop wins. A gatherer who presses it is not handed the wheat.
See [Farmer](farmer.md).

Nirnroot that the plant table ranked is expert, because the produce
sells above 12 gold. Red nirnroot (`b6fb9:Skyrim.esm`) is an activator
the plant pass does not read. It is answered by hand, with no rank:
any gatherer, 1 red nirnroot, the same ten minutes. The ordinary
nirnroot activator (`e1fb2:Skyrim.esm`) is the same kind of record.
If the generated table already has that base, the table's rank is
the one that applies. If it does not, the hand row has no rank and
any gatherer may take it.

The beehive this server placed (`dbf8b3:Thornswood-Content.esp`) is
the farmer's, the same as a world beehive on the harvest list. See
[Farmer](farmer.md). A press from a gatherer does not take the comb.

## What you are handed

1 in Burden (+15 carry weight).

## What you cannot do

You cannot take a cabbage, a leek, a potato, wheat, or an apple off
a farm plot. Those are [Farmer](farmer.md). You cannot pick a flower
and have it be cooking. The cook buys or is given what you picked.

Some world records were filed with no rank:
[lists/unranked.md](../lists/unranked.md). A record whose produce is
already on this ladder takes that produce's rank. Blue mountain
flower, purple mountain flower, and red mountain flower are advanced.
Lavender, juniper, jazbay, thistle, tundra cotton, spiky grass, imp
stool, creep cluster, namira's rot, and white cap are novice. Canis root,
deathbell, dragon's tongue, fly amanita, giant lichen, glowing
mushroom, mora tapinella, scaly pholiota, snowberry, and swamp fungal
pod are advanced. Bleeding
crown, blisterwort, and nightshade are expert. Rot scale, screaming
maw and thorn hook are Creation Club plants, and Thornswood is Special
Edition only, so nobody gathers them.

Cabbage, carrot, gourds, leek, potato, and wheat are the farmer's
crops. A chickens' nest and a churn are farmer verbs. A beehive is
the farmer's. See [Farmer](farmer.md). A clam and a fish are the
fisher's. A coin purse and an estate key are not a harvest. Mammoth
cheese and a mead barrel stay off every ladder.

## Plants that grow only in their own hold

Each hold has plants of its own (Patrick, 22 Oct 2026, #3150). They
grow only in that hold. Pick them there, or trade for them anywhere
else. Outside their hold they are not in the world at all: nobody
sees them and nothing is refused.

| Hold | Its own plants |
| --- | --- |
| Whiterun | Tundra cotton, lavender |
| Haafingar | Grass pod, garlic |
| The Rift | Scaly pholiota, canis root, pine thrush egg |
| The Reach | Juniper berries, rock warbler egg |
| Eastmarch | Dragon's tongue, jazbay grapes, creep cluster |
| Falkreath | Thistle branch, mora tapinella |
| Hjaalmarch | Swamp fungal pod, giant lichen, deathbell |
| Winterhold | Chaurus eggs, Nordic barnacle |

The Pale's are ores (see [Miner](miner.md)). Each one is the plant
whose placements already stood mostly in that hold, so the fewest
were taken out. The list and what was measured for each are
`holdOnly` in `game/data/last-plugin-policy.json`, and
`scripts/mods/Build-LastPlugin.py` switches the rest off.

<!-- detail:begin -->

## Every record

Generated from the work tables by `scripts/dev/Write-SystemLists.js`. The same rows are in [gatherer](../lists/gatherer.md).

| Name | Rank | Records | You receive | In the world |
| --- | --- | --- | --- | --- |
| Ashen Grass Pod | novice | 2 | Ashen Grass Pod | Spiky Grass |
| Canticle Bark | novice | 1 | Canticle Bark | This should not be visible |
| Creep Cluster | novice | 2 | Creep Cluster | Creep Cluster |
| Emperor Parasol Moss | novice | 3 | Emperor Parasol Moss | Emperor Parasol Moss |
| Frost Mirriam | novice | 1 | Frost Mirriam | Dried Frost Mirriam |
| Garlic | novice | 1 | Garlic | Garlic Braid |
| Grass Pod | novice | 2 | Grass Pod | Spiky Grass |
| Hanging Moss | novice | 3 | Hanging Moss | Hanging Moss |
| Imp Stool | novice | 4 | Imp Stool | Imp Stool |
| Jazbay Grapes | novice | 1 | Jazbay Grapes | Jazbay |
| Juniper Berries | novice | 1 | Juniper Berries | Juniper |
| Lavender | novice | 1 | Lavender | Lavender |
| Namira's Rot | novice | 5 | Namira's Rot | Namira's Rot |
| Scathecraw | novice | 2 | Scathecraw | Scathecraw |
| Soul Husk | novice | 2 | Soul Husk | Soul Husk |
| Thistle Branch | novice | 1 | Thistle Branch | Thistle |
| Trama Root | novice | 3 | Trama Root | Trama Root |
| Tundra Cotton | novice | 1 | Tundra Cotton | Tundra Cotton |
| White Cap | novice | 6 | White Cap | White Cap |
| Blue Mountain Flower | advanced | 3 | Blue Mountain Flower | Mountain Flower |
| Canis Root | advanced | 1 | Canis Root | Canis Root |
| Deathbell | advanced | 2 | Deathbell | Deathbell |
| Dragon's Tongue | advanced | 2 | Dragon's Tongue | Dragon's Tongue |
| Fly Amanita | advanced | 5 | Fly Amanita | Fly Amanita |
| Giant Lichen | advanced | 1 | Giant Lichen | Giant Lichen |
| Gleamblossom | advanced | 2 | Gleamblossom | Gleamblossom |
| Glowing Mushroom | advanced | 2 | Glowing Mushroom | Glowing Mushrooms |
| Hawk's Egg | advanced | 1 | Hawk's Egg | Hawks' Nest |
| Mora Tapinella | advanced | 6 | Mora Tapinella | Mora Tapinella |
| Nordic Barnacle | advanced | 1 | Nordic Barnacle | Nordic Barnacle Cluster |
| Pine Thrush Egg | advanced | 1 | Pine Thrush Egg | Birds' Nest |
| Purple Mountain Flower | advanced | 2 | Purple Mountain Flower | Mountain Flower |
| Red Mountain Flower | advanced | 2 | Red Mountain Flower | Mountain Flower |
| Rock Warbler Egg | advanced | 1 | Rock Warbler Egg | Birds' Nest |
| Scaly Pholiota | advanced | 2 | Scaly Pholiota | Scaly Pholiota |
| Snowberries | advanced | 3 | Snowberries | Snowberry |
| Swamp Fungal Pod | advanced | 1 | Swamp Fungal Pod | Swamp Fungal Pod |
| Wheat | advanced | 1 | Wheat | Wheat |
| Yellow Mountain Flower | advanced | 2 | Yellow Mountain Flower | Mountain Flower |
| Bleeding Crown | expert | 8 | Bleeding Crown | Bleeding Crown |
| Blisterwort | expert | 5 | Blisterwort | Blisterwort |
| Chaurus Eggs | expert | 3 | Chaurus Eggs | Egg Sacs |
| Elves Ear | expert | 1 | Elves Ear | Dried Elves Ear |
| Nightshade | expert | 2 | Nightshade | Nightshade |
| Nirnroot | expert | 1 | Nirnroot | Nirnroot |
| Ash Creep Cluster | master | 2 | Ash Creep Cluster | Creep Cluster |

<!-- detail:end -->

## Where this is

The verb, the ranks, the ten minutes, and the list are in the server.
The wait is the plant, for everybody: the next person cannot take it
early. A press from someone who is not a gatherer is refused before
the plant is consumed, and a gatherer below the plant's rank takes
nothing either. World records filed with no rank take the ranks under
"What you cannot do" when the record is a gatherer's plant.
