# Farmer

A shovel in the pack, 100 uses. Skyrim has no hoe. The shovel is what
a smith forges, and it is what this class asks for.

10 crops, 14 placed records:
[lists/farmer.md](../lists/farmer.md).

| Rank | Crops |
| --- | --- |
| Novice | Cabbage, leek, potato, gourd, carrot |
| Advanced | Wheat, ash yam, tomato |
| Expert | Green apple, red apple |
| Master | Everything on that list |

Ranked by how hard it is to grow, not by the price. A novice can carry
an apple and eat it. A novice cannot sow one or bring one in.

## A plot

A plot is one crop in a field. The first time anyone touches it, it is
empty. There is no startup sweep that fills the farms. Emptiness is
the absence of a record.

Stand within 200 of the plot. `/plant` with the crop in your pack. The
crop is its own seed: a cabbage plants a cabbage. `/plot` says what is
in the ground. Bringing it in is the press when it is ripe. The plot
is empty again. It does not grow back. Sow another.

One sow or one bring-in is one piece of work. 100, then 250, then 600.

## How long, and how many

The base wait is on the crop, for a novice multiplier of 1. Cabbage,
leek, potato, gourd, carrot, ash yam, tomato, and both apples are 75
minutes. Wheat is 135 minutes. The rank shortens it, once, at sowing,
and the answer is kept on the plot:

| Rank | Multiplier | A 75 minute crop | Wheat |
| --- | --- | --- | --- |
| Novice | 1 | 75 minutes | 135, and a novice cannot sow it |
| Advanced | 0.85 | 63.75 minutes | 114.75 minutes |
| Expert | 0.7 | 52.5 minutes | 94.5 minutes |
| Master | 0.55 | 41.25 minutes | 74.25 minutes |

What you bring in is more than the one you sowed:

| Rank | Back from one plot |
| --- | --- |
| Novice | 2 |
| Advanced | 3 |
| Expert | 4 |
| Master | 5 |

## The claim

`/claim` at a plot. One farm at a time, a circle 1200 units out from
that plot, same cell. That is 2400 across, a farm and not the village
behind it. Claims do not overlap. A plot is never in two.

14 real days with nothing sown and nothing brought in, and the claim
is gone. Work refreshes it. Anyone with the class may use a farm
nobody holds. That is where a new farmer starts.

This circle is not the building claim. A house and its field can be
two records. See [Property](../property.md). The 14 days is the same
number.

## Butter, milk, and the nest

These are farmer verbs. They have no rank gate. A novice does them.
Each successful press is one piece of work on the farm ladder, and
each waits 10 minutes, the same wait as a picked reagent, keyed to
you and that object. A restart clears it.

| What | Where | You receive | Who else |
| --- | --- | --- | --- |
| Butter churn | `bc0:HearthFires.esm` | 1 Butter (`353c:HearthFires.esm`) | Told it is farm work |
| Living cow | Six bases: `6681e`, `c39f1`, `9da4b`, `23a90` in Skyrim.esm, `f9a9:Dawnguard.esm`, `ea867:ZIA_Complete Pack.esp` | 1 Jug of Milk (`3534:HearthFires.esm`) | The press does nothing. A dead cow is a hunter carcass, not a milking |
| Chicken nest | `1062d1:Skyrim.esm` | 1 Chicken's Egg (`23d77:Skyrim.esm`) | Told it is farm work, so the engine cannot hand the egg to anyone else |

Goats are not milked. A mammoth cheese bowl is not a farmer verb.
Whoever presses it gets the bowl, because no class answers it.

Wild eggs are not this nest. Pine thrush, rock warbler, and hawk
eggs are reagents on the gatherer list. A chicken nest that the
harvest pass filed as unranked is this verb, not a sixth plant.

Butter is an ingredient on a large share of the cook's rows. The
farmer is who makes it. See [Hearthcook](../professions/cook/hearthcook.md).

## Seed

At the moment you pick the class: 3 cabbage, 3 leek, 3 potato. All
novice, all the base game's own records.

If the pack holds no crop at all, standing at a plot hands a few of
those three again, and not more often than every 12 hours. It is a
way back. It is not a wage. Nine vegetables against an empty pack,
while one ripe plot pays more than that.

After the first handout, seed is a crop you kept, or one you were
given. Barrels in a hold are not a shop. Another farmer is the usual
answer for wheat and apples.

## What you are handed

1 in Endurance (+10 stamina). The shovel. The nine vegetables.

## What you cannot do

You cannot mill flour. That is a Hearthcook, one sack, novice, at the
grain mill. Your wheat is advanced, so a novice farmer cannot even
grow what the flour is made of. See
[Hearthcook](../professions/cook/hearthcook.md).

You cannot treat a wild reagent as a crop. That is the gatherer.

The emote of sweeping is not farm work.

<!-- detail:begin -->

## Every record

Generated from the work tables by `scripts/dev/Write-SystemLists.js`. The same rows are in [farmer](../lists/farmer.md).

| Name | Rank | Records | You receive | Gold | Grow minutes |
| --- | --- | --- | --- | --- | --- |
| Cabbage | novice | 1 | Cabbage | 1 | 75 |
| Carrot | novice | 2 | Carrot | 1 | 75 |
| Gourd | novice | 1 | Gourd | 1 | 75 |
| Leek | novice | 2 | Leek | 1 | 75 |
| Potato | novice | 1 | Potato | 1 | 75 |
| Ash Yam | advanced | 1 | Ash Yam | 1 | 75 |
| Tomato | advanced | 1 | Tomato | 1 | 75 |
| Wheat | advanced | 1 | Wheat | 5 | 135 |
| Green Apple | expert | 2 | Green Apple | 1 | 75 |
| Red Apple | expert | 2 | Red Apple | 1 | 75 |

<!-- detail:end -->

## Where this is

Empty plots, the claim circle, the 14 days, the waits, the yields,
the shovel, and the starter seed are in the server. The first-harvest
story on the public classes page, a world already standing full, is
not what the server does. The server starts empty, on purpose.
