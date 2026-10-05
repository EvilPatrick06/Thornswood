# Exhaustion

The bar is labelled Rest. 100 is rested. 0 is spent. It is about
sleeping, not about a single fight.

## The clock

It empties in 8 hours of real time. That is 12.5 points an hour, before
work.

A swing of your own work costs rest on the swing:

| Rank | Cost |
| --- | --- |
| Novice | 1.5 |
| Advanced | 1.2 |
| Expert | 0.9 |
| Master | 0.6 |

Under 15, crafting is refused. Mining, chopping, fishing and the other
class verbs still happen, and they still cost the swing.

## The bands

| Meter | Band | What it does |
| --- | --- | --- |
| 50 and up | Fine | Nothing |
| 25 to 49 | Weary | -10 stamina, -10 magicka, -2 speed |
| 10 to 24 | Bad | -15 health, -25 stamina, -25 magicka, -5 speed, -0.05 melee damage |
| 0 to 9 | Spent | -30 health, -45 stamina, -45 magicka, -10 speed, -0.15 melee damage |

## Where you rest

You are resting only while the place is true. Saying it in the street
does not count. Sitting down or lying down is how you rest, and there
is nothing to type.

| Place | Per real hour |
| --- | --- |
| A seat | 20 |
| A bed or bedroll nobody can lend you | 25 |
| A seat with a fire in reach | 35 |
| A bed or bedroll nobody can lend you, with a fire in reach | 45 |
| A bed you are allowed in: an inn, a night the holder gave you, or its key or deed carried | 50 |
| Your own bed | 80 |

Patrick, 4 Oct: "use some common sense". A bed is better than a
campfire. A bed or bedroll nobody lends you is a little better than
sitting. A campfire with a bedroll is better than a campfire alone. And
so on up to your own bed. Whose bed it is decides the rate, not whether
it is a bed or a bedroll. A fire in reach is one close enough to warm
you, the way [Temperature and weather](temperature.md) measures it. A
bed in a building somebody else holds, who has not let you sleep there,
is no rest at all. See [Property](property.md).

Someone who has said `/bard` in the same cell within the last 5 minutes
adds 25 on top of whatever place you are already in. There is no bard
profession. The check is that they said they are playing.

Logging out in a real bed fills rest to 100 when you come back, and
puts 25 back on hunger and on thirst. It is not a stat bonus for
logging out at a clever hour. It is a rule about the bed.

Sleeping on open ground is sitting, 20 an hour, and it can start a
chill. See [Disease](disease.md).

## A stimulant

A tea holds the rest drain at half for 20 real minutes, then costs 15
rest more than those 20 minutes would have. Skooma holds the drain at
zero for 10 minutes, then costs 30 rest and 10 hunger. Neither replaces
a bed. A second dose inside the window does not stack. It refreshes the
clock and adds the crash again.

## Where this is

The 8 hour clock, the per-swing costs, the craft gate at 15, the six
rest rates, the bard's +25, and the logout bonus are in the server.
Sitting down and lying down tell the server by themselves, and nobody
types anything. The server counts only furniture it saw the person
press and that they are still beside. A chair, bench, stool or throne
is a seat. A bed or bedroll is a bed, and whose it is decides the rate.
Any other furniture, such as a forge or a chopping block, is not a
rest. The fire is the distance the game already reports for warmth.
All of it is measured again every 5 seconds, so walking away, losing a
key, a night running out or moving away from the fire stops the rest
or changes its rate. See [Property](property.md). Tea and skooma are
not items the needs block knows. Sleeping on open ground, an hour on a
seat with no roof over you and no fire in reach, starts a chill. See
[Disease](disease.md).
The craft gate has not been extended to mining or chopping, and this
plan does not extend it.
