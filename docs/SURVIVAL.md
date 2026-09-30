# Survival on Thornswood

A plan for how a body works here. It is written against the server as it runs,
and against the public pages on thornswood.net. An earlier draft used another
name for the server. This page does not.

This is planning only. It does not change `game/gamemode.js`, the rules on the
site, or any number that is already live. Where a later build would touch a
running rule, the line says so and stops. Building any of it is a separate ask.

## How to read it

**Running.** In the server now. This plan leaves it alone.

**Public, not wired.** thornswood.net already says it. The gamemode does not
do that part yet.

**Planned.** Wanted, and not built. Described here so a later pass has
something to build from.

## What already runs

Thornswood is a shared Skyrim on SkyMP, in alpha, eighteen and over, open by
application. Skyrim's own levelling is off. Fast travel is off. The difficulty
is fixed at Expert. Carriages and ferries are the way between holds
(`site/data/help.md`, `scripts/mods/Add-CartTravel.ps1`).

Hunger, thirst, rest and warmth are four bars in the bottom left. `/needs`
prints the numbers. SunHelm Survival is out because it wrote health, stamina,
magicka and carry weight against a server that already owns those. SunHelm
Diseases is out with it, and diseases have not been rebuilt
(`site/data/known.md`).

A death writes a temple spawn and the person wakes there
(`resolveArrival` in `game/gamemode.js`, preferred slot `temple`). The rules
on the site already say what that means: if nobody agreed to the death, you
woke up in a temple and you move on. Permanent harm, and vampirism or
lycanthropy, need the same kind of agreement as a death. Staff can end a
character. That page stays as it is until somebody asks to change it
(`site/data/site/rules.md`).

## Where the old draft and the server disagree

| What the draft described | What runs | What this plan does |
| --- | --- | --- |
| Hunger and thirst fall faster while you work or fight | They fall on a clock. Work costs rest, per swing | Leave the clocks. A cold link is described under weather and is not applied |
| Dirty water causes disease | Water class only changes temperature, and only while you are in it | Planned under disease. Swimming stays as it is |
| Too tired to work at 30% | Crafting stops under 15 rest. Other work still costs rest | Leave the gate |
| Five tiers of each job | Four ranks, eight professions, five classes | Leave it. The public page is the rule |
| Sleeping outside gives a partial rest and a chill | `/rest` is a word: sit, campfire, inn, or bed | A real bed check is under housing. Chill is under disease |
| Tea and skooma hold off sleep | Not built | Planned under rest |
| A bodily need | Not built | Planned |
| Raw, burnt and cooked as different meals | A swallowed thing is food, drink, ale, potion or poison | Planned under food |
| Ale as a buff, then blurred vision and a hangover | Ale quenches less each time and costs food and rest | Leave those numbers. Vision and a hangover are planned on top |
| Potion sickness, restoration strain, a withered pool | A potion is a small drink toward thirst | Planned |
| Weather as one line about cold and clothing | A full warmth model: place, wind, sky, night, height, fire, water, clothes | Written out below. The gaps are planned, the numbers stay |
| Injury as an extra | No wound on the character | Planned, and it includes lasting harm and going down |
| Disease as an extra | Taken out with SunHelm and not replaced | Planned as server-owned diseases, not that mod |
| Housing as an extra | Claims, deeds, locks, rent, coffers and notice boards already exist | Planned as what a home is for. Not a second housing system |
| A hardcore death toggle | Temple wake, plus the rules page | Folded into injury. No toggle |

## Hunger and thirst

Running, in the needs block of `game/gamemode.js`.

Both start full. Food empties in about two hours and twenty four minutes of
real time. Drink empties in about an hour and twelve. They do not speed up
because you sprinted or fought. The comment on the drain says a session is
about two hours, and the old six-hour food clock never moved enough to matter.

Above 50 there is no penalty. Then weary, bad, and spent.

| Band | Hunger | Thirst |
| --- | --- | --- |
| Fine, 50 and up | Nothing | Nothing |
| Weary | Less stamina, a little less melee damage | Less magicka, a little slower |
| Bad | Worse of the same | Worse of the same |
| Spent | Those, and less health | Those, and magicka comes back slowly |

An unlisted food is worth 15. An unlisted drink is worth 20. A potion or a
poison is worth 5 toward thirst, because it is a mouthful, and the server
cannot tell drinking a poison from putting it on a blade. Ale is its own
case, below.

Planned, and not a retune of those figures:

- While you are badly cold, both clocks run faster. The rule is under
  weather. The current drain stays until that link is asked for on its own.
- A dirty drink can start a disease. It does not change what a clean drink
  is worth.
- A meal's state (raw, burnt, cooked) changes how much it fills and whether
  it sickens. The fallback of 15 stays for anything the table does not know.

## Rest

Running. Rest empties in about eight hours. It is still about sleeping.

You recover by saying where you are resting:

| Place | Per real hour |
| --- | --- |
| Sitting | 20 |
| A campfire | 35 |
| An inn | 50 |
| A bed | 80 |

Somebody who has said `/bard` in the same cell adds 25 on top of whatever
place you are already in. There is no bard profession. Bard is a roleplay
name. The check is whether someone nearby said they are playing.

Logging out while resting in a bed fills rest when you come back, and puts
25 back on food and drink. The reason, written on the bonus: a stat for
logging out at the right time of day would be a rule about when to play.
This is a rule about where you sleep.

Doing your work costs rest on the swing. A novice pays 1.5, an advanced hand
1.2, an expert 0.9, a master 0.6. Under 15 rest, crafting is refused. That
gate is crafting only.

Planned:

- The bed has to be a bed. Saying the word in the street stops counting.
  Housing has the check. The recover numbers above stay.
- Sleeping on open ground is no better than sitting, and it can start a
  chill. That chill is a disease, not a second rest meter.
- A mild stimulant (a tea) holds the rest drain off for a short while and
  then costs more rest than it saved. Skooma does the same and costs more,
  and it is a poor idea twice. Neither replaces a bed.
- The draft's lock at 30%, on every job, is not this plan. The gate at 15
  for crafting stays. Extending it to mining, chopping and every other verb
  would be a change to a running rule.

## Food

Running. `scripts/dev/Build-FoodTable.js` reads the alchemy records and marks
each edible thing as food, drink, ale, potion or poison. Cooking's results
are plugin records, so they land in that table as food. The server does not
know raw from burnt from cooked.

Planned states, on top of the hunger number:

- **Raw meat or fish.** Edible. Fills less than a cooked meal. Can start
  food sickness. It is what you eat when you have no fire.
- **Burnt.** Fills less, and stamina comes back a little slower for a short
  time. Burnt food already exists as items. Eating one is the state. A
  cooking failure that produces a burnt meal waits until cooking itself is
  being changed. This plan does not add a timing minigame.
- **Cooked.** The normal meal. A cook's meal can carry a small timed help:
  stamina coming back faster, a shift toward warm, or a lower chance of
  disease, from what went into it. The help is not a heal. Potions stay
  useful because a stew is not a potion.
- **A feast.** A high-rank cook's meal, stronger and shorter, meant to be
  eaten before a hunt or a fight. Grand Chef already makes two of a batch
  instead of one. This plan does not change that.

Eating takes time. You do not clear a stack in a second to stack the help.
Once food is full, another meal sickens you instead of adding more help.
That is the limit that stops food replacing potions.

A cook and a hunter already depend on each other: the hunter is the only one
who can take a carcass, and the cook is the one who turns meat into a meal
that is worth eating. This plan does not move either verb.

## Drink and ale

Running. The first ale is a strong drink (30 thirst) and costs 8 rest and 6
food. Each further ale within 45 real minutes costs more and quenches less.
The fourth barely counts as a drink. The line in chat says which one it was.
Ale does not blur the screen, sway the camera, or leave a hangover the next
morning.

Planned on top of those numbers, not instead of them:

- The first drink or two can grant a small, short help, using actor values
  the needs system already writes (a little damage resistance, or stamina).
  After that the existing costs are the whole of it. There is no persuasion
  minigame to hang a speech bonus on, so this plan does not invent one.
- Drunk is a flag the client can draw: a sway, a soft edge on the screen.
  Slurred talk stays roleplay. Chat is not rewritten to garble lines.
- A hangover arrives on the in-game morning if you drank enough and did not
  sleep. The game clock runs about twenty times real time, so a night is a
  bit over an hour of real time, not a real day. It feels like a mild
  sickness and a weary rest until you sleep or take a remedy an alchemist
  made. One ale does not do this.

Water you meant to drink is under disease. Swimming is under weather. They
are not the same act.

## Potions and restoration

Running. Swallowing a potion or a poison moves thirst by 5. A potion brewed
at a lab is not in any plugin. The server treats that runtime record as a
potion so it does not count as a meal. Nothing here makes the second potion
weaker, and nothing makes the tenth healing spell cost more.

Planned:

- The server counts potions in a short window. The first does what it says.
  Each one after heals for less. The thirst sip still happens every time.
- Restoration in a short window costs more magicka on each cast. Past a
  count, restoration is refused for a brief while, and stamina and health
  come back more slowly. That is the strain.
- A stretch of either, tracked on the character, can leave them withered: a
  lower health or magicka ceiling until they have rested and eaten. Food, a
  bed, and a person who heals for a living are the way back. Potions are
  still worth having. They are a poor way to live.

The window and the counts belong in a table next to the needs balance when
this is built. They are not picked here, because a guessed number would get
treated as the decision.

## The body

Planned. Not built.

A slow meter, filled by what you eat and drink. Ale and a heavy meal fill it
faster than water and bread. It should matter in a long ruin or across a
long evening, and it should not ask for a trip every few minutes. If it does, it
is too fast.

Leave it too long and you are uncomfortable: a small penalty, the sort the
other meters already use. Longer than that and you have an accident. For a
while after, trading in town can be refused. That refusal has to be the
server answering the trade, because most NPC scripts do not run and a guard
will not comment on his own. In the woods nobody is there to refuse you. You
are still uncomfortable.

Relief is an outhouse, a pot in a home, or stepping away from the road. A
proper place is worth a little comfort, which helps rest slightly. The woods
works and gives nothing extra.

This exists so a home and an inn have a use past a bed, and so a siege or a
deep ruin is a different day from a walk to the well. It is not a joke, and
it is not the meter anyone should be watching most.

## Work

Running, and this plan does not rewrite it. The public page is
`site/data/site/classes.md`.

Eight professions, each with two halves: Warrior, Mage, Alchemist, Cook,
Smith, Enchanter, Tailor, Woodworker. Four ranks: novice, advanced, expert,
master. You climb by doing the work. Your own half is what you can make. Your
sister half stops at novice unless a master teaches you. Two trades outside
your profession, novice only, is the ceiling.

Five classes, separate from the profession: Hunter, Fisher, Gatherer, Miner,
Farmer. Each owns a verb. Bard, merchant, priest, scholar and thief are names
you may roleplay. They are not picked on K and they grant no verb.

Two public lines are not in the warmth math yet:

- **Master Weaver.** Clothing that keeps the weather off, and still weighs
  what clothing weighs. Also hidden armour. The armour half is not a
  temperature rule. The weather half is planned under weather.
- **Master Carver.** Fires and kilns they build or work give the most warmth
  there is. Every fire is the same curve today. Planned under weather.

Smith's Mastercraft (temper to legendary) is on the page and not yet in the
world. That gap is the classes page's own note. This plan does not take it.

## Weather and temperature

This is the warmth meter. It is running. The draft had it as one sentence.
The sentence is already behind the server. What follows is what the server
does, then the pieces that are still only a promise.

### What you see

The bar is labelled Temp. It is not a percentage. 0 is freezing and 100 is
as hot as the meter goes. The word beside it:

| Reading | Word |
| --- | --- |
| Under 15 | Freezing |
| Under 30 | Cold |
| Under 42 | Chilly |
| 42 to 58 | Fine |
| Up to 70 | Warm |
| Up to 85 | Hot |
| Above 85 | Burning |

`/needs` says the reading, the band, whether you are warming or cooling, the
target, whether the server thinks you have a roof, whether it is night,
how far the nearest fire is and what it is worth, what weather and height
are worth, and what it thinks you are wearing. That second line exists
because a number on its way somewhere looks exactly like a broken number.

The bands that cost you something are a distance from 50, not a level:

| Distance from 50 | Band | On the meter |
| --- | --- | --- |
| Under 20 | Fine | About 30 to 70 |
| 20 | Weary | About 30, or 70 |
| 30 | Bad | About 20, or 80 |
| 40 | Spent | 10 or below, or 90 or above |

Cold takes stamina recovery, speed, then stamina and health. Heat takes
stamina recovery, then magicka recovery and stamina. Heat does not take
health. Being too warm is a nuisance. Freezing can hurt you. The middle,
roughly 30 to 70, costs nothing.

### How it moves

50 is comfortable. The meter moves toward whatever the place is worth. It
moves both ways, unlike hunger, thirst and rest, which only fall.

Warming covers half the gap in about 30 seconds. Cooling covers half the gap
in about 90 seconds. A fire is obvious while you stand in it. Stepping into
snow is not an emergency in the first five seconds. Crossing a bridge in the
rain is not a meter event. Going indoors out of a blizzard is felt while you
are still dealing with the door.

Anything the server does not understand is comfortable. A room nobody has
classified is not a trap.

### Where you are standing

The client reports this, because the server cannot see it. It has a position
and a cell. It does not know if snow is falling on you, if you are swimming,
if there is a roof, or if a fire is in front of you. That was measured: the
meter sat on 50 in a fire pit because nothing had ever sent a place.

| Place | Target before clothes, fire, and weather |
| --- | --- |
| Indoors, a roof | 58 |
| Outdoors, nothing falling on you | 40 |
| Rain | 34 |
| Wading | 26 |
| Snow | 16 |
| Swimming | 8 |

A roof is the whole point of a roof. Wind, night, height and the sky stop at
the door. A campfire is not a roof, so a campfire in a blizzard still gets
the blizzard.

### Weather, wind, night and height

`scripts/dev/Build-WeatherTable.js` reads every weather record in the load
order. The client sends which weather it is. The server looks up the wind
and the kind. The kind flags are the game's own: pleasant, cloudy, rainy,
snow, and an aurora bit that this system ignores.

These are degrees on or off the place, and only with no roof:

| Factor | Worth |
| --- | --- |
| A full gale | Up to 14 colder, scaled by how hard that weather's wind is |
| Snow falling on you | 6 colder, on top of the snow place |
| Rain falling on you | 4 colder |
| Overcast | 1 colder |
| A clear day | 4 warmer. Not at night |
| Night | 6 colder |
| Height | Colder above 6,000 units, 1.2 per thousand, and no more than 14 |

The wind is scaled against this load order, not against 255. Cathedral
Weathers sets a clear day high enough that a raw 0-to-255 scale would call
ordinary weather a storm. The middle and the maximum of the table are the
scale. The check that the bytes are still the wind is Skyrim's own blizzard,
`SkyrimStormSnow`.

Height: the tundra is near zero, Ivarstead is about 3,000, High Hrothgar is
about 12,000, the Throat of the World is past 25,000. The cap at 14 means
the summit is as cold as this part gets, and then no worse.

Standing in the open in a blizzard is meant to be the worst dry place in the
game. Snow's 16, minus a full gale's 14, is 2 before clothes. Swimming is
the thing that beats it.

### Fire

A fire is a distance, not a switch. At your feet it adds 34 to the target.
At 300 units it adds nothing. The client scans the same 300. Forges,
smelters, cooking spits and campfires are in the fire list, built from the
records, including Embers XD. Unlit versions are dropped.

Indoors at a hearth is the indoor place plus the fire. The same campfire in
a blizzard is the snow place plus the fire. Walking away slides you back to
the place on its own. You do not have to stand in the coals.

Standing in the coals burns you, about 7 health a second. That is the fire
itself, not the warmth meter. Warmth can read Burning while you are also
actually on fire. They are different.

Fire spreads. The client says it is burning. The server looks for anyone in
the same cell within about two paces, and tells their client to catch. The
burn lasts about five seconds unless they are still next to the person who
is alight, in which case it keeps refreshing. It cannot run away through a
whole town: the radius is small and the clock is short. A crowd in a bonfire
is the worst of it, and they are standing in a bonfire.

### Water

Only if you are swimming or wading. Walking past a forge's lava does nothing.

| Class | On top of the water place |
| --- | --- |
| Lava | 90 warmer. It is not water |
| Puddle | 12 warmer |
| Still water | 10 warmer |
| Marsh | 6 warmer |
| Deep water, the sea and most lakes | 0 |
| A river | 5 colder |
| Ice | 8 colder |

There is no general ice water in the province. The records named for cold
water are Dawnguard's Frostreach. The sea off Dawnstar is the same default
water as the sea off Riften. A freezing swim off the north coast comes from
the weather, the hour and the height, which already apply to anyone in the
water. Wading is the client's word, from how deep you are, not from the
water record. About waist deep is the line. Deeper than that you are
swimming.

The server knows the water class. The client does not report it. The cell
descriptor is the server's, and the water table is keyed by that descriptor.

### Clothing

Every worn piece counts on its own: body, legs, feet, hands, head, cloak,
scarf, hood, and the other slots the table names. A shirt is about a quarter
of the answer. Boots are about a fourteenth. Bare feet in the snow cost
exactly that.

Material, from best at keeping weather out to worst: fur, leather, light
armour, cloth, heavy armour, and nothing. Metal is a poor coat. An
unclassified piece counts as cloth, so a mod item is neither a gift nor a
punishment. The total is capped so a cuirass and a cloak on the same torso
cannot add up past a fully dressed person.

It cuts both ways. Warm clothes pull a cold place back toward 50. In a hot
place they push further from 50. Full kit at a forge is worse than a shirt.
There is no outfit that wins in a blizzard and at a smelter.

The server reads equipment, not a worn flag left behind in the inventory. If
it has no record of a piece, that piece was handed to the client inside its
own game and never reached the server. `/needs` says so. Those pieces cannot
count.

### What is public and not in this math

**Master Weaver.** Planned: garments a master tailor made add a further step
of insulation, and they do not weigh more than clothing. They do not replace
fur, leather and cloth. A cloak you found in the world still works. The
tailor's best work works better. Hidden armour on that clothing is the other
half of the perk and is not part of warmth.

**Master Carver.** Planned: a fire or a kiln credited to a master woodworker
adds more than 34 at your feet, and still fades to nothing at the same
reach. A campfire in a blizzard is still a campfire plus a blizzard. The
blizzard does not get deleted because a master lit the fire.

Neither of these reads tailor rank or woodworker rank today. Wiring them is
a change to how warmth is computed. It waits until it is asked for. The
public page is ahead of the server, and this paragraph is the record of that
gap.

### What else is planned

- **Cold and the other meters.** While the cold band is weary or worse,
  hunger and thirst drain faster. Heat does not get the same link. Heat
  already taxes recovery. The multiplier sits beside the drain figures when
  it is built. Until then the clocks are the clocks above.
- **A meal against the cold.** A cooked meal that grants cold resistance
  shifts the temperature target a little for a while. It is not a new meter.
- **Wet lingers.** Today a roof zeroes weather the moment the client says
  you are under one. Planned: rain and swimming leave you wet for a few
  minutes, so a doorway is not an instant dry. New. Not running.
- **Chill.** A night in the open, or sleep on the ground in snow, can start
  the chill under disease. Warmth does not grow a second "you have a cold"
  flag of its own.

### What stays out

- No separate heat meter and cold meter. One number, both ends.
- No temperature drawn on a map by hold. The Pale is cold because it is
  high, it is night, and it is snowing, not because the hold has a label.
- The aurora bit on a weather stays ignored.
- An unknown cell stays comfortable.

`scripts/dev/Audit-Temperature.js` runs the shipped needs block and prints
where the meter sits after 10 seconds, 30 seconds, a minute and three
minutes in a list of real places. Any later change to a warmth number should
be read there before it is believed.

## Injury and wounds

Planned. Not built. This includes what the draft split off as a separate
hardcore death switch. There is no switch. A wound is a wound, and dying is
the far end of the same track. Everyone is on it.

### What runs

Health is the game's health. At zero the engine kills the actor. For a
person, death writes the nearest temple (or Hall of the Dead) as the wake
point. Solstheim is left out of that distance check because its coordinates
are not in the same frame. Animals in the hunt table stay down long enough
for a hunter to work the carcass. Bandits, guards, draugr and dragons keep
the engine's short delay. A kill between people does not count as a
warrior's work. A warrior climbs by killing what is not a person.

The Respawn death-overhaul mod is out. It set a character essential and ran
its own death on the client. Death cannot finish on one machine. The server
owns respawn (`site/data/known.md`).

There is no wound record. A broken leg today is something people agree to
say. The rules page already covers the serious end of that: death, a lasting
loss someone did not choose, vampirism and lycanthropy.

### The track

1. **Sound.** No wound, or only old ones that have healed.
2. **Hurt.** One or more wounds on the character. They survive a restart,
   the same way hunger does.
3. **Down.** Health would have hit zero. You cannot fight or cast. You can
   talk. A clock is running.
4. **Wake.** The temple, with the wounds you already had. This is today's
   death, with a step in front of it.
5. **Ended.** The character is done. Only the ways the rules page already
   allows: the people in the scene agreed, or staff ended them.

Going down is not dying. Waking in a temple is not "the wounds are gone."
Ending a character is not something another person can force.

### Down

When a person's health would reach zero, they go down instead of the death
event firing.

If the cause is the world (a draugr, a fall, a fire with no killer), the
clock is there so someone nearby can stabilize them. If nobody does, the
temple wake happens, as it does now. The rules already say the world is
allowed to kill you. You come back with the wounds you had when you went
down. The temple stopped the death. It did not wash the cuts.

If the cause is another person, the clock is the moment the rules page
already asks for. Out of character, in plain words: is this death, or a
lasting loss, or neither?

- They agree to death. The character ends, the way an agreed death already
  ends. Staff still do that when it is theirs to do. This plan does not add
  a button that deletes someone.
- They agree to a named loss (a hand, an eye, a scar they will be known by).
  That loss is written on the wound record and ordinary medicine does not
  clear it. They wake, alive, with that loss.
- They do not agree, or nobody answers. Temple wake. The wounds they already
  had come with them. No new loss is added in the silence.

The clock is long enough to be a scene: a few minutes of real time. Not a
twitch window, and not the rest of the evening.

Stabilize with a bandage, a healing spell, or a potion. They get up hurt.
Health returns to a low number, not to full. A potion used this way still
counts as the small drink it already is.

### The wounds

Each wound records where it is, how bad, when it happened, and whether it
has been treated.

**Cut.** It bleeds. Untreated, health ticks down. Torn cloth slows it.
A tailor's bandage stops it and lowers the chance it becomes a fever. A
healing spell can close it. Left open, it can become the wound fever under
disease.

**Break.** An arm or a leg. An arm hits attack and block, and refuses
crafting that needs both hands, the same shape as the rest gate and only
for that break. A leg slows you. Sleep does not set a bone. A splint on the
road holds it. A physicker or a temple finishes the setting. Looked after,
it heals over days. Ignored, it heals crooked: a limp or a weak arm until
a master physicker or a temple rite clears it.

**Burn.** Standing in a fire already deals damage. A bad burn is the wound
after you step out. Until it heals, the clothing on that part of the body
counts for less warmth. That link waits until wounds exist. It is not a
retune of fur and metal.

**Bite.** A wound, and a chance of disease. Higher if it stays open. It is
not vampirism and not lycanthropy.

### Lasting harm

Two kinds, one record.

**Ordinary.** The crooked heal, the limp, the weak arm, a scar that is a
small lasting penalty. It comes from a wound that was not treated. It does
not need a separate agreement. Medicine can undo it. This is the permanence
that is simply how healing works. No switch turns it off.

**Agreed.** A hand, an eye, a scar they will be known by, vampirism,
lycanthropy. The rules page already requires a yes before any of these.
This plan does not move that line. Once the yes is given, the record is
flagged and a potion does not clear it. Staff can still end a character
the way they already can.

There is no mode where some people keep their wounds and others do not.

### Who treats what

| Treatment | Who | What it does |
| --- | --- | --- |
| Torn cloth | Anyone | Slows a bleed. Does not stop a fever |
| Bandage | A tailor's work, used by anyone | Stops a bleed, lowers infection |
| Splint | A woodworker or a tailor | Holds a break until it can be set |
| Healing potion | Anyone who has one | Health. Does not set a bone. Still a sip of thirst |
| Poultice | A physicker | Cuts the chance of wound fever |
| Restoration, low rank | A mage, or anyone who has the spell | Stops a bleed |
| Restoration, higher rank | As the school allows | Closes a cut. Later, helps a break |
| Temple | The place. Priest is not a class | Wake, and treatment for the living. Clears ordinary disease. Does not clear an agreed loss |

Master Chemist and the alchemy bench stay as they are. A cure is a recipe
and a rank, not a new profession. Priest stays roleplay. The temple works
because it is the temple, not because someone picked Priest on K.

### What this will not do

- No essential flag, and no client-side death handler. That fight is why
  the old respawn mod is gone.
- No wound that exists only on one machine. The server owns death and
  respawn already.
- People and animals do not share a rule. The hunter's carcass timer stays.
- The rates (how fast a cut bleeds, how many minutes down lasts, how many
  days a break takes) are chosen when this is built, in one table, the way
  the needs balance is one table. They are not invented here.

## Disease

Planned. Not built. SunHelm Diseases is out on purpose. It wrote the same
actor values the server owns, and it depended on SunHelm. This is not that
mod coming back. It is a short list on the character, ticked by the server,
the same shape as hunger.

Most mod scripts do not fire here. A disease that lives in Papyrus will not
be reliable. The list has to be the server's.

### The kinds

**Chill.** From sleeping on open ground, or from staying at a spent cold for
a long time. Mild. Warmth, a fire, a bed, or time clears it. Being cold for
a minute does not.

**Food sickness.** Raw meat or fish, or eating again when you are already
full. Weakness, and if the body meter exists it fills faster. Cooked food
does not do this.

**Fouled water.** Drinking bad water. Marsh, a puddle, or standing water you
did not boil. A well, an inn, or a skin you bought or filled at a well is
clean. A river is drinkable and safer boiled. The sea is salt: it quenches
poorly and can sicken. Boiling is a cook's fire, not a new station.

This does not change what swimming in that water does to temperature. A
marsh is slightly less cold to swim in than a river, and that stays. Drinking
it is the new part.

**Wound fever.** An open cut or an untreated burn, left too long. This is
the handoff from injury. A bandage or a closing spell in time stops it.

**Bite sickness.** From an animal bite, more likely if the wound stays open.
Ordinary disease. Vampirism and lycanthropy are not on this list. They stay
on the rules page, with death.

### How sick

**Caught.** No penalty yet. A cure now and it never shows.

**Ill.** The weary penalties the needs system already uses: slower, less
stamina or magicka, depending on the disease.

**Bad.** The bad penalties. Crafting is refused while it lasts, the same
shape as the rest gate, and only for the duration of this fever. The rest
gate itself stays at 15. A mild chill never reaches this step. A bad fever
does not fade because you waited. You treat it or you stay ill.

### Cures

- A potion of cure disease clears one ordinary disease. Swallowing it is
  still the small thirst sip.
- A physicker's remedy does the same and is the better answer to wound fever.
- A temple rite clears ordinary disease. It does not clear an agreed loss,
  vampirism, or lycanthropy.
- Rest and warmth clear a chill without a potion.
- Time can clear a mild one. It does not clear a bad one.

A disease is not a wound. A wound is not a disease. Fever is where they meet.

## Housing, beds and storage

Planned on top of a property system that already runs. This is not a new way
to own a house.

### What runs

A claim is made at the door and carried by the deed. Locks and keys, stewards
named by a jarl, rent and board paid into the hold's box, notice boards.
`docs/GAMEMODE.md` maps that block. The server owns container contents, door
state, and inventories (`site/data/known.md`). The theft rule on the site is
the limit on a stranger: take something, leave the rest, leave a trace. Do
not empty a house because the owner is offline.

`/rest bed` is a word. The server believes you if you say it. Logging out
in that state is the full sleep bonus.

### What a home is for, once this is built

**A bed that is a bed.** The inn rate and the logout bonus apply when you
are using a bed in a place you own, a place you rent, an inn room you have
paid for, or a bed the owner has allowed. A bedroll on the road is campfire
rest, not the full sleep. Saying bed in the street no longer counts. The
recover numbers stay. The check is the new part, so it waits for its own ask.

**A hearth.** Already a fire, if the client can see the flame. A roof plus
that fire is the warmth of a home. No second warmth system. A master
woodworker's kiln is the fire rule under weather, not a property rule.

**A cook fire.** The spit and the oven that already exist. A home with one
is a place a cook can work. Recipe gates do not move.

**Storage.** The containers in the claimed cell. The server already keeps
their contents. This plan does not add a chest that holds more than the
world has, and it does not add a pocket store that follows you. A stranger
is still under the theft rule.

**A shop.** A counter in a claimed place, and the notice boards that already
take work. Rank does not mint a vendor. A master is someone people come
looking for, which the classes page already says. No new shop menu in this
plan.

**A pot and an outhouse.** Only if the body meter is built. Furniture, not
a profession. An inn that has one is a better inn. A camp does not need one
for a night.

**Rent.** Already exists. A paid inn room counts as a bed for that night.
Board fees stay board fees.

### What this plan will not take on

Hearthfire's house-building is a quest and a set of scripts. Most mod
scripts do not run here. This plan does not promise that a building plot
works. A home is a place that can already be claimed. If a built house is
a normal cell with a door, the claim covers it. If it is a script, it is
out of scope until somebody measures that script.

No second claim system. No change to who a steward is, what rent costs, or
how a key is cut.

## What this plan leaves alone

So the page is not read as a patch:

- The drain on hunger, thirst and rest, and the recover rates for sit,
  campfire, inn and bed.
- What ale costs, and that it gets worse with each one.
- Clothing materials, slot weights, and the cap.
- Fire reach, fire warmth, and fire spreading between people.
- Water classes and what they do to a swimmer.
- The four ranks, the five classes, and the craft gate at 15 rest.
- The temple wake, and the rules on agreed death and agreed lasting harm.
- Deeds, locks, rent, coffers, and the single place coin enters the world.

Any one planned section can be built on its own later. None of them is
started by this page.
