# Potions and restoration

A potion is a mouthful. It is not a meal and it is not a way to live.

## The sip

Every potion and every poison moves thirst by 5, including one you
brewed at the lab. Brewed potions are not in a plugin. They still count.

## Diminishing potions

Inside 60 seconds, the first potion does what it says. The second heals
or buffs at 50%. The third at 25%. The fourth and after do the sip of
thirst and nothing else. The window is from the first swallow.

## Restoration strain

Inside 30 seconds, each restoration spell after the first costs 25%
more magicka than the last. The fifth in that window is refused for 20
seconds, and stamina recovery and health recovery are at the weary
cold numbers from [Temperature](temperature.md) for those 20 seconds.

## Withered

Five potions in an hour, or ten restoration casts in an hour, sets
withered for 30 real minutes. Max health and max magicka are 80% of
what they were. Eating a cooked meal and resting in a bed, or waiting
the 30 minutes, clears it. A potion does not clear it.

## Where this is

The sip of 5 and restoration strain are in the server. The server hears
every restoration spell a person casts. It cannot refuse a cast,
because the game casts it before the server hears of it, so the strain
is the price: the second costs 25% more, the third 25% more again, and
after the fourth the price is past any magicka for 20 seconds, with
stamina and health recovery at -20%. The price moves through the value
the game's own Fortify Restoration moves. Nobody has yet cast five in a
row in the game to read the magicka each one asked for. The strain is
kept in memory, so a restart ends it, and when you come back into the
world the server sends your K panel as it stands at that moment, so
none of it is left on you (issue #1642).

The diminishing potions and withered are not in the server. Potions
currently stack as the game allows, plus thirst. Withered waits for
the cooked meal on [Food](food.md), and its 80% of max health and
magicka needs the client to apply a share, where what the server sends
today is amounts.
