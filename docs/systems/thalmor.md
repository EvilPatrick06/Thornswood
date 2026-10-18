# The Thalmor

Outlaws. The Expulsion was 4E 209. It is 4E 252. They have been
illegal in Skyrim for 43 years. There is no embassy for them to run
to, no immunity, and no order from home. The Dominion is an enemy of
the Accord, and so is anyone carrying a Justiciar's work.

The history is on the site, in the world page. This page is what that
means when somebody is standing in it.

The Empire's house in Solitude is not theirs. See
[The Imperial Embassy](embassy.md).

## A person who is Thalmor

It is a life, not a class and not a profession. You still pick those
on K. The robes are not a race lock. An Altmer, a Bosmer, or anyone
else the race page allows can wear them. Wearing them does not change
your race.

Thalmor robes, Thalmor armour, and Justiciar weapons are not found in
the world. They are not in a chest and not on a body. A person on the
remnant roll may craft them. The roll is an application, the same
kind as a Jarl, not a button on K. The references are on
[Cut items](cut-items.md), marked thalmor, so they can come back for
an event.

Wearing Justiciar robes, Thalmor armour, or carrying a Dominion flag
in a hold is a hostile marker. A guard, and any person acting as one,
may start a fight on sight. Starting the fight does not need a yes.
Ending the character, a hand, an eye, or a scar they did not choose
still does. See [Death](death.md).

They do not enforce the law. Talos is lawful everywhere in Skyrim.
A Thalmor who punishes that worship is committing the crime, not
judging one. Magic is not their business. See
[Magic and the College](magic.md).

There is no Thalmor faction the server will set on a character to
make the world friendly. The old embassy in Haafingar was emptied.
Claiming a ruin's door does not found a new one. A claim is still a
claim, and the court can take it. See [Property](property.md).

## Patrols

A small cast, not every Thalmor the game placed.

A patrol is 2 to 4. They are on the roads between holds. They do not
spawn inside a walled city. At most 3 patrols in the province at
once, and only one on a given road.

They are not people. They do not wake in a temple. Killing one is a
warrior's work if the killer is a warrior, the same as a bandit. See
[Warrior](professions/warrior.md).

They drop no coin and no world weapon the spoils rule would have to
strip. The fight is the point. A robe left on the ground is still
world gear, and world gear is not a mint and not a free armoury. See
[Gold](gold.md).

They are quiet when nobody is near. The machine of a nearby person
is what moves them, and that host can change every 2 seconds. That
is the limit of shared Skyrim, written on the known-issues page, and
it applies to these patrols the same as to a wolf.

## What you cannot do

You cannot be a Justiciar in the open and also be under the King's
peace. Article the Fifth of the Accord is the law: neither side
harbours, funds, employs, or carries one.

You cannot use the embassy as a door. The Ambassador hands a Thalmor
over as readily as a Jarl does.

You cannot be the Dominion's official voice. There is no official
voice. The Remnant runs gold and poison under other names. That is
roleplay on top of this page, and it does not turn the coin they
spend into a second mint.

## Where this is

The lore is on the site. An admin writes the remnant roll with
`/remnant add` once the application is accepted, and `/remnant remove`.
Those are staff commands, and the person named is told in their own
chat. Only somebody on the roll makes the Thalmor robes, boots, gloves
and hood and the Justiciar weapons, and the world does not hand them
out. The robes are not race locked, as the race page says.

A character wearing any of those pieces, or the game's own Thalmor
robes, reads Thalmor to the server. Nothing acts on that yet: guards do
not attack on sight, because most of them are still the game's own
actors and the server does not run their AI. The server knows no item
that is a Dominion flag, so a flag is not read yet.

The patrols are staff settings in `game/data/thalmor-patrols.json`:
whether any patrol is out at all, the most roads with one at once (and,
if staff set one, a different most for a world stage, read at each start
from the world stage the staff confirmed), and
for each road its points (one member each, 2 to 4), the record each
member is made from, how long a dead one takes to come back, and how far
one strays. It ships off, with three candidate roads from the cut
Immersive Patrols II Justiciar placements in the Pale, Haafingar and
Hjaalmarch. A road off Tamriel's ground, with fewer than 2 or more than
4 points, or with a point beside a walled town or village is refused.
At each start the server stands up any member that is missing, at its
own point, and takes down the members of a road staff turned off. A dead
member comes back at its point after the return time; nothing stacks a
second group. A member keeps to its stretch of road, inside its leash;
there is no route between holds. A body cannot be opened, so it gives no
coin. The known-issues page still says the cast that stays is traders
and the carriage workers. This page adds the patrols to that cast. See
[People who are not people](npcs.md).
