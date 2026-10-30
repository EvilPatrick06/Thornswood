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
at 90 hunger or above catches it. Spoiled food always catches it
([Spoilage](spoilage.md)). Lasts 30 minutes. Weakness: the
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

The five are in the server, on the character, with the chances, the
caught window, ill, bad and the durations above. Food sickness and
fouled water last their 30 and 45 minutes from when they show. While a
disease shows, its meter counts as at least weary, or at least bad, so
a hungry person with food sickness does not pay the same penalty twice.
A bad one refuses every craft: a bench's own menu, the kiln's included,
and a key cut at a forge, before anything is taken. A potion of
cure disease clears one, the one furthest along, and is still the sip
of 5. A physicker's remedy
clears one too, wound fever first, used from the wounds panel (see
[Injury](injury.md)). A shrine pressed inside
one of the temples the wake uses clears them all. A fire, a bed, warmth
back to fine after being cold, or 2 hours clears a chill. An hour asleep
on open ground (on a seat, with no roof over you and no fire in reach)
or an hour at spent cold starts one. Toughness takes 10% off each chance a
point, and Purified Blood stops every one. The old disease mod is out
on purpose.

Raw meat, a full stomach and the water sources start food sickness and
fouled water through the meal and drink work (#1382).

A potion of cure disease somebody brews cures the same way. The lab
tells the server which bottle a Cure Disease brew made, from the
ingredients, and drinking that bottle clears one disease. The server
hears a brewed bottle being drunk from engine fork PR #78 on (#1383).

A cooked meal's help against disease halves every chance for 20
minutes, and a feast's quarters it for 10. That half is in the server.
The guard comes only from a dish seasoned at the cooking pot with garlic
(Patrick, 18 October, #2682). A cooked meal on its own gives only its
temperature help, and there is no second guard. A later meal's warmth or
stamina takes the guard off.
