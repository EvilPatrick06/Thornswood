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
how hard the thing was, by the race the server says the body is. A
person killed by a person is still nothing.

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

The strength table wins over the hunter list on
[Hunter](../classes/hunter.md) where the two disagree (Patrick, 4 Oct).
A bull netch or a betty netch is a grown netch, 8, though the hunter
list calls them advanced. A vale sabre cat and a snowy sabre cat are
sabre cats, 2. An ice wolf is a wolf, 1. Karhu is a bear, 4. A named
animal uses the rank of its kind: a pit wolf is still a wolf. A
body's own hunter rank counts only when no line on this page names
its race.

One kill is that many pieces, all on the half you hold. The party
bonus is 15% of that total, banked the same way as any other work, and
only if somebody from the party is in the same cell.

### Bodies neither table names

Patrick, 4 Oct: each is placed against the lines above by how hard it
is in vanilla Skyrim.

| Pieces | What died |
| --- | --- |
| 1, with the novice line | Riekling of Solstheim, ash hopper, slaughterfish, nix-hound, shade, witchlight, soul wisp, swarm, mannequin |
| 2, with the advanced line | Spriggan, dwarven spider, ice wraith, death hound, bristleback, riekling on a bristleback, ash spawn, magic anomaly, boneman, the afflicted, a riekling of the riekling people |
| 4, with the draugr and the falmer | Atronach, dwarven sphere, dwarven ballista, gargoyle, dremora, snow elf, ash guardian, seeker, wispmother, spriggan matron, keeper |
| 8, with the giants | Werewolf, werebear, vampire lord, Miraak |

A burnt spriggan is a spriggan, a spriggan earth mother is a spriggan
matron, and Karstaag's ice wraiths are ice wraiths. A riekling of the
riekling people is one of the peoples (see [Races](../races.md)), so it
counts on the people's line, as a bandit does. A creature a spell
conjures, from any of the magic mods, is 1: the world never places one.
Every race in the load order is on one of these three tables. A race a
new plugin brings is 1 until it is placed here.

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
| Berserker | Expert | Break | The next hit within 8 seconds staggers | 25 | 60 seconds |
| Berserker | Master | Wreck | The next power attack within 8 seconds deals 50% more and staggers | 40 | 2 minutes |

You have the rows at your rank and below, on your half. Stamina is
spent when the maneuver starts. If you do not have it, nothing happens.

The maneuver key opens a small panel with yours, and says whether each
one's wait is over. It is 9 unless you change it on the launcher's
Controls page. Press a maneuver's number, or click it, and it starts.
The key again, or Escape, closes the panel. Nobody types a maneuver
(Patrick, 4 Oct: no chat commands for what people do). A pick reaches
the server the way the trade and party keys do, so it starts within a
second or two, and the answer comes back in the chat.

Set, Plant, Cover, Wall, Rush and Heavy last as long as the row says.
Break and Wreck wait 8 seconds for the blow they name, the window Heavy
has (Patrick, 4 Oct). Cover is for the one person nearest you, within
3 metres, when you start it.

What the server does with each, and what the game still has to do on
somebody's own machine:

| Maneuver | In the server | Not yet |
| --- | --- | --- |
| Set | The stamina and the wait. A block you make while it runs costs half the stamina | A block only the server sees, which is every block against a creature or a character the server runs, costs nothing until the next engine build (below) |
| Plant | The stamina and the wait. A Break or a Wreck does not stagger you, and your own game refuses every other stagger while it runs | Nothing |
| Cover | While you block and they stay within 3 metres, a fifth of what each hit took is given back | A hit that kills outright is not softened |
| Wall | You, and your party within 3 metres of you, get a fifth of what each hit took back | A hit that kills outright is not softened |
| Rush | +4 speed, through the same hand that puts your skill tree on your character | Nothing |
| Heavy | The power attack takes a quarter again of what it took | Nothing |
| Break | The hit staggers a person | Staggering a creature |
| Wreck | The power attack takes a half again of what it took, and staggers a person | Staggering a creature |

A block costs stamina (Patrick, 12 Oct). It is the game's own rule:
a quarter of the damage the block stopped. A blocked blow lets a tenth
of its damage through, so a blow that takes 2 health off you through
your block stopped 18, and costs 4.5 stamina. It comes off your real
most, the way a maneuver's stamina does (below), and a block with no
stamina left still blocks, as in the game. Set halves it. Only a
person pays for a block, and a spell is never blocked. The engine on
the servers now tells the server only the blocks the attacker's own
game saw, so a block against a creature or a character the server
runs costs nothing yet; the next engine build sends the server's own
decision (issue #1386).

Two of them on one person is still 20% less, not 40%, and Cover and
Wall work as the table says (Patrick, 4 Oct). The stamina is taken
from your real most: what your race starts with, what your skill tree
adds (Endurance is +10 a point), and what hunger, thirst, tiredness and
cold take off it (Patrick, 4 Oct). So 15 stamina is 15 off the bar you
see. Stamina a potion or a piece of enchanted gear adds is not counted,
because the server does not see it. The waits are kept in memory, so a
restart of the server clears them. A restart ends a running Rush too, and
when you come back into the world the server sends your K panel as it
stands at that moment, so the speed is not left on you (issue #1642).

## Warlord

At master. Master-tier combat maneuvers, and you can teach novice
combat to people who are not warriors. That teaching is one of their
two outside apprenticeships. It never goes past novice, and it does
not make them a warrior.

The maneuvers are the table above. At master you hold all four rows
of your half.

## Where this is

The profession, the two halves, the placed points, the strength
table with every body placed, and the maneuver table are in the
server, and the maneuver key and its panel are in the game. A chicken
is 1 piece and a dragon is 16. A kill between people counts for
nothing. The stamina scales with the skill tree. What the game still
has to do for the maneuvers is the second table under Maneuvers. A
sister half's novice maneuver opens when a Master of that half takes
you on, and stays once that half is past novice.
See [Masters and apprentices](../apprenticeship.md).
