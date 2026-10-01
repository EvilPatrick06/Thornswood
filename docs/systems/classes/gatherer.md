# Gatherer

Reagents out of the world. Food plants are the farmer's. 46 names,
105 placed plants.

Every name: [lists/gatherer.md](../lists/gatherer.md).

## The rank of a plant

What the reagent sells for.

| Price | Rank |
| --- | --- |
| 1 gold | Novice |
| Up to 5 | Advanced |
| Up to 12 | Expert |
| Above 12 | Master |

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

The beehive this server placed (`dbf8b3:Thornswood-Content.esp`) is a
station, not a reagent. Pressing it is the engine handing over
honeycomb to whoever is standing there. It is not gatherer work and
it is not woodworker work. A hive the plant pass ranked as a wild
flower is a different record, and it is in the unranked list until
somebody names a rank for it.

## What you are handed

1 in Burden (+15 carry weight).

## What you cannot do

You cannot take a cabbage, a leek, a potato, wheat, or an apple off
a farm plot. Those are [Farmer](farmer.md). You cannot pick a flower
and have it be cooking. The cook buys or is given what you picked.

Unranked plants, 45 names, are not on this ladder:
[lists/unranked.md](../lists/unranked.md). They are in the harvest
table and they are not a rank. The plan for them is that they stay
off the ladder until somebody names a rank. They are not a sixth class.

<!-- detail:begin -->

## Every record

Generated from the work tables by `scripts/dev/Write-SystemLists.js`. The same rows are in [gatherer](../lists/gatherer.md).

| Name | Rank | Records | You receive | In the world | Gold |
| --- | --- | --- | --- | --- | --- |
| Ashen Grass Pod | novice | 2 | Ashen Grass Pod | Spiky Grass | 1 |
| Canticle Bark | novice | 1 | Canticle Bark | This should not be visible | 0 |
| Creep Cluster | novice | 2 | Creep Cluster | Creep Cluster | 1 |
| Emperor Parasol Moss | novice | 3 | Emperor Parasol Moss | Emperor Parasol Moss | 1 |
| Frost Mirriam | novice | 1 | Frost Mirriam | Dried Frost Mirriam | 1 |
| Garlic | novice | 1 | Garlic | Garlic Braid | 1 |
| Grass Pod | novice | 2 | Grass Pod | Spiky Grass | 1 |
| Hanging Moss | novice | 3 | Hanging Moss | Hanging Moss | 1 |
| Imp Stool | novice | 4 | Imp Stool | Imp Stool | 0 |
| Jazbay Grapes | novice | 1 | Jazbay Grapes | Jazbay | 1 |
| Juniper Berries | novice | 1 | Juniper Berries | Juniper | 1 |
| Lavender | novice | 1 | Lavender | Lavender | 1 |
| Namira's Rot | novice | 5 | Namira's Rot | Namira's Rot | 0 |
| Scathecraw | novice | 2 | Scathecraw | Scathecraw | 1 |
| Soul Husk | novice | 2 | Soul Husk | Soul Husk | 1 |
| Thistle Branch | novice | 1 | Thistle Branch | Thistle | 1 |
| Trama Root | novice | 3 | Trama Root | Trama Root | 1 |
| Tundra Cotton | novice | 1 | Tundra Cotton | Tundra Cotton | 1 |
| White Cap | novice | 6 | White Cap | White Cap | 0 |
| Blue Mountain Flower | advanced | 3 | Blue Mountain Flower | Mountain Flower | 2 |
| Canis Root | advanced | 1 | Canis Root | Canis Root | 5 |
| Deathbell | advanced | 2 | Deathbell | Deathbell | 4 |
| Dragon's Tongue | advanced | 2 | Dragon's Tongue | Dragon's Tongue | 5 |
| Fly Amanita | advanced | 5 | Fly Amanita | Fly Amanita | 2 |
| Giant Lichen | advanced | 1 | Giant Lichen | Giant Lichen | 5 |
| Gleamblossom | advanced | 2 | Gleamblossom | Gleamblossom | 5 |
| Glowing Mushroom | advanced | 2 | Glowing Mushroom | Glowing Mushrooms | 5 |
| Hawk's Egg | advanced | 1 | Hawk's Egg | Hawks' Nest | 5 |
| Mora Tapinella | advanced | 6 | Mora Tapinella | Mora Tapinella | 4 |
| Nordic Barnacle | advanced | 1 | Nordic Barnacle | Nordic Barnacle Cluster | 5 |
| Pine Thrush Egg | advanced | 1 | Pine Thrush Egg | Birds' Nest | 2 |
| Purple Mountain Flower | advanced | 2 | Purple Mountain Flower | Mountain Flower | 2 |
| Red Mountain Flower | advanced | 2 | Red Mountain Flower | Mountain Flower | 2 |
| Rock Warbler Egg | advanced | 1 | Rock Warbler Egg | Birds' Nest | 2 |
| Scaly Pholiota | advanced | 2 | Scaly Pholiota | Scaly Pholiota | 4 |
| Snowberries | advanced | 3 | Snowberries | Snowberry | 4 |
| Swamp Fungal Pod | advanced | 1 | Swamp Fungal Pod | Swamp Fungal Pod | 5 |
| Wheat | advanced | 1 | Wheat | Wheat | 5 |
| Yellow Mountain Flower | advanced | 2 | Yellow Mountain Flower | Mountain Flower | 2 |
| Bleeding Crown | expert | 8 | Bleeding Crown | Bleeding Crown | 10 |
| Blisterwort | expert | 5 | Blisterwort | Blisterwort | 12 |
| Chaurus Eggs | expert | 3 | Chaurus Eggs | Egg Sacs | 10 |
| Elves Ear | expert | 1 | Elves Ear | Dried Elves Ear | 10 |
| Nightshade | expert | 2 | Nightshade | Nightshade | 8 |
| Nirnroot | expert | 1 | Nirnroot | Nirnroot | 10 |
| Ash Creep Cluster | master | 2 | Ash Creep Cluster | Creep Cluster | 20 |

<!-- detail:end -->

## Where this is

The verb, the prices, the ten minutes, and the list are in the server.
The wait is still per person: someone else can take the same flower
while you wait. A press from someone who is not a gatherer is not
specially refused before the plant is consumed.
