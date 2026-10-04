# Warrior

You do not make things. Bulwark and Berserker are how you fight, and
there is nothing at a workbench for either of them to own.

- [Bulwark](warrior/bulwark.md) holds the line.
- [Berserker](warrior/berserker.md) breaks it.

The sister half is still novice and no further, unless a Warlord
teaches it. There is no recipe for that teaching to unlock. What it
changes is the placed point and which maneuvers you are allowed.

## How a warrior climbs

A kill of something that is not a person. An animal, a draugr, a
bandit the world placed. The killer has to be a person, and not
themselves. A fall or a fire is not a fight.

A person killing a person counts for nothing. See [Death](../death.md).

No other profession is credited for a kill. Killing is not a way to
become a tailor.

The ladder is still 100, then 250, then 600, and the count starts
again at each rank. The same rest cost as a swing of a pick: 1.5,
1.2, 0.9, 0.6.

## How much one kill is worth

A chicken and a dragon are not the same fight. The piece count follows
how hard the thing was. A person killed by a person is still nothing.

When the body is on the hunter list, the piece count is that body's
own hunter rank, on
[Hunter](../classes/hunter.md). A named body uses its own row. Karhu
is master on that list, so Karhu is 8, even though a bear is 4.

| Strength | What that is | Pieces |
| --- | --- | --- |
| Novice | Chicken, rabbit, fox, deer, wolf, skeever, mudcrab, goat, cow, dog | 1 |
| Advanced | Sabre cat, troll, spider, horse, horker, netch calf | 2 |
| Expert | Bear, chaurus | 4 |
| Master animal | Mammoth, a grown netch | 8 |

A hunter does not dress a person-shaped body. Those still count for a
warrior, on their own line:

| What died | Pieces |
| --- | --- |
| Bandit, guard, forsworn, skeleton | 2 |
| Draugr, falmer, hagraven | 4 |
| Giant, dragon priest, centurion, lurker | 8 |
| Dragon | 16 |

A named animal uses the rank of its kind. A pit wolf is still a wolf.
A body neither table names, such as an atronach or a spriggan, is 1.
One kill is that many pieces, all on the half you hold. The party
bonus is 15% of that total, banked the same way as any other work, and
only if somebody from the party is in the same cell.

## What you are handed

The profession places 1 in Vitality (+10 health) and 1 in Might
(+0.05 melee damage). The half places one more, on its own page.
A class places one on top of those. See [Skill tree](../skill-tree.md).

## Maneuvers

The half you picked. A sister half at novice does not have them until
a Warlord has taken you on, and then only the novice row. An outside
trade is the same: the novice row, and no further.

| Half | Rank | Maneuver | What it does | Stamina | Cooldown |
| --- | --- | --- | --- | --- | --- |
| Bulwark | Novice | Set | Block costs half stamina for 8 seconds | 15 | 45 seconds |
| Bulwark | Advanced | Plant | You are not staggered for 8 seconds | 20 | 60 seconds |
| Bulwark | Expert | Cover | One person within 3 metres takes 20% less damage while you block, for 8 seconds | 25 | 90 seconds |
| Bulwark | Master | Wall | You and your party within 3 metres take 20% less damage for 10 seconds | 40 | 3 minutes |
| Berserker | Novice | Rush | +4 speed for 5 seconds | 15 | 30 seconds |
| Berserker | Advanced | Heavy | The next power attack within 8 seconds deals 25% more | 20 | 45 seconds |
| Berserker | Expert | Break | The next hit staggers | 25 | 60 seconds |
| Berserker | Master | Wreck | The next power attack deals 50% more and staggers | 40 | 2 minutes |

You have the rows at your rank and below, on your half. Stamina is
spent when the maneuver starts. If you do not have it, nothing happens.

`/maneuver` lists yours and when each is ready again. `/maneuver rush`
starts one. Set, Plant, Cover, Wall, Rush and Heavy last as long as
the row says. Break and Wreck wait for the blow they name. Cover is for
the one person nearest you, within 3 metres, when you start it.

What the server does with each, and what the game still has to do on
somebody's own machine:

| Maneuver | In the server | Not yet |
| --- | --- | --- |
| Set | The stamina and the wait | Halving what a block costs. The game works that out on the blocker's machine |
| Plant | The stamina and the wait. A Break or a Wreck does not stagger you | Any other stagger |
| Cover | While you block and they stay within 3 metres, a fifth of what each hit took is given back | A hit that kills outright is not softened |
| Wall | You, and your party within 3 metres of you, get a fifth of what each hit took back | A hit that kills outright is not softened |
| Rush | +4 speed, through the same hand that puts your skill tree on your character | Nothing |
| Heavy | The power attack takes a quarter again of what it took | Nothing |
| Break | The hit staggers a person | Staggering a creature |
| Wreck | The power attack takes a half again of what it took, and staggers a person | Staggering a creature |

Two of them on one person is still 20% less, not 40%. The stamina is
taken as a share of the most your race has, which is the number the
server knows. Stamina the skill tree adds is not in that share. The
waits are kept in memory, so a restart of the server clears them.

## Warlord

At master. Master-tier combat maneuvers, and you can teach novice
combat to people who are not warriors. That teaching is one of their
two outside apprenticeships. It never goes past novice, and it does
not make them a warrior.

The maneuvers are the table above. At master you hold all four rows
of your half.

## Where this is

The profession, the two halves, the placed points, the strength
table and the maneuver table are in the server. A chicken is 1 piece
and a dragon is 16. A kill between people counts for nothing. What
the game still has to do for the maneuvers is the second table under
Maneuvers. A Warlord taking somebody on is not recorded yet (see
[Masters and apprentices](../apprenticeship.md)), so a sister half's
novice maneuver opens once that half is past novice.
