# Disease

A short list on the character, ticked by the server. Not a mod script,
and not the survival mod that used to write health and stamina on its
own. Most mod scripts do not run here. A disease that lives in one
would not be reliable.

Vampirism and lycanthropy are not on this list. They sit with death.
See [Death](death.md).

## The kinds

**Chill.** An hour of sleep on open ground, or an hour of real time at
spent cold. Shorter than an hour does not catch it. A fire, a bed,
warmth back to fine, or 2 hours clears it.

**Food sickness.** Raw meat or fish catches it 40% of the time. Eating
at 90 hunger or above catches it. Lasts 30 minutes. Weakness: the
weary hunger penalties. The optional meter on [The body](body.md)
is not part of this sickness unless a later vote adds that meter.
See [Food](food.md).

**Fouled water.** Marsh, a puddle, or standing water you did not boil
catches it 80% of the time. The sea catches it 40%. A river, unboiled,
catches it 15%. See [Thirst](thirst.md) and [Drink](drink.md). Lasts
45 minutes at the weary thirst penalties. Boiling for a minute at a
cook fire clears the risk before you drink.

**Wound fever.** An open cut or an untreated burn. The chance is on
[Injury](injury.md): 40%, or 10% with a bandage, or 5% with a poultice.
Lasts until cured.

**Bite sickness.** 25% if the bite is closed inside 10 minutes. 60% if
it stays open. Lasts until cured. Ordinary disease.

## How sick

**Caught.** No penalty for 10 minutes. A cure in that window and it
never shows.

**Ill.** The weary penalties of the closest meter: cold for a chill,
hunger for food sickness, thirst for fouled water, and both hunger and
rest for a fever.

**Bad.** Wound fever and bite sickness reach this after another 20
minutes untreated. The bad penalties, and crafting is refused while it
lasts. A chill and a mild food sickness do not reach this step. Waiting
does not clear a bad one.

## Cures

A potion of cure disease clears one ordinary disease. It is still the
thirst sip of 5. A physicker's remedy does the same and is the better
answer to wound fever. A temple rite clears ordinary disease and does
not clear vampirism, lycanthropy, or an agreed loss. Rest and warmth
clear a chill without a potion.

Toughness on the skill tree adds disease resistance per point. Filled,
Purified Blood means no disease takes. See [Skill tree](skill-tree.md).

## Where this is

Not in the server. The old disease mod is out on purpose. Cure disease
potions exist as items and currently count only as a sip of thirst.
Toughness writes disease resistance onto the actor. Nothing in the
needs block reads a disease.
