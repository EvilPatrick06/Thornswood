# Drink and ale

Water is thirst. Ale is thirst, hunger and rest, and then a drunk.

## Ale

Inside 45 real minutes, each ale is worse than the last.

| Which | Thirst back | Rest | Hunger |
| --- | --- | --- | --- |
| 1st | 30 | -8 | -6 |
| 2nd | 22 | -13 | -10 |
| 3rd | 15 | -18 | -13 |
| 4th | 7 | -22 | -17 |
| 5th and on | 0 | keeps climbing by the same step | the same |

The step is 0.6 more cost each time, and 0.25 less thirst each time.
After 45 minutes with none, the count starts over.

The first two also give +0.05 melee damage for 5 real minutes. The
third and after do not. There is no speech check to hang a bonus on.

Drunk, from the third ale until you sleep or the 45 minutes pass: the
client draws a sway and a soft edge. Chat is not garbled for you. If
you drank three or more and log out without a bed, the next time you
are in the world before you have slept you are hung over: rest is
treated as weary even if the meter is higher, until you sleep or drink
a remedy an alchemist made. The game clock runs about twenty times real
time, so "the next morning" is about an hour of real time after a
night's drinking, not the next real day.

## Water

| Source | Thirst | Risk |
| --- | --- | --- |
| Well, inn, a filled skin | 20 | None |
| River, unboiled | 20 | 15% fouled water. Boiled, none |
| Marsh, puddle, standing water | 15 | 80% fouled water. See [Disease](disease.md) |
| The sea | 10 | Salt. 40% fouled water |

Boiling is a cook fire, a minute at it, and it clears the risk. It is
not a new station.

## Where this is

The ale curve, the 45 minutes, and the chat line that says which drink
it was are in the server, and so are the damage help of the first two
and the hangover, which a night in a bed ends. The sway is not, and a
remedy does not yet end a hangover. Water is not yet tagged by where you filled it. Every
non-ale drink is 20.
