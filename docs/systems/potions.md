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

The sip of 5 is in the server. The windows, the falling heal, the
strain and withered are not. Potions currently stack as the game
allows, plus thirst.
