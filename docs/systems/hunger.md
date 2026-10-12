# Hunger

Hunger is a meter from 0 to 100. It starts at 100. It only falls,
except when you eat or when a night in a real bed puts a little back.

## The clock

It empties in 2 hours and 24 minutes of real time. That is 41.67 points
an hour. Work and combat do not speed it. Cold does.

While the cold band in [Temperature](temperature.md) is weary, the clock
runs at 1.25. At bad, 1.5. At spent, 2. Heat does not speed it.

## The bands

| Meter | Band | What it does |
| --- | --- | --- |
| 50 and up | Fine | Nothing |
| 25 to 49 | Weary | -20 stamina, -0.05 melee damage |
| 10 to 24 | Bad | -40 stamina, -0.10 melee damage |
| 0 to 9 | Spent | -60 stamina, -0.20 melee damage, -20 health |

A band is said when it gets worse, and when it comes all the way back
to fine. The steps in between on the way up are quiet.

## What food is worth

An ordinary meal is 15. A drink is not hunger. Ale costs hunger: 6 on
the first, and more with each one. See [Drink](drink.md).

Raw, burnt, cooked and a feast change the 15. See [Food](food.md).
Anything the food table does not know is 15, so a pie nobody classified
is a small meal rather than nothing.

Eating when the meter is already full does not add past 100. It sickens.
See [Disease](disease.md).

## Sleep

Logging out in a bed adds 25 hunger when you return, and fills rest.
The bed has to be a bed. See [Property](property.md) and
[Exhaustion](exhaustion.md).

## Where this is

The clock, the four bands, the 15, the ale cost and the 25 from a bed
are in the server. So are the cold multipliers, and a meal at 90 or above
starts food sickness instead of raising the meter. Food states are not on
the meal.

A bed counts only when the server saw the person press it and they are
still beside it. Lying down tells the server by itself, and nobody
types anything. The 25 comes with the logout fill: log out lying in
your own bed or one you are allowed in, stay away at least 24 minutes,
and the time away is settled first, then 25 goes back on hunger and on
thirst and rest is full. A bed or bedroll nobody can lend you gives no
fill. Which beds give it and the 24 minutes are the suggested answers
on #1606. See [Exhaustion](exhaustion.md) and [Property](property.md).
