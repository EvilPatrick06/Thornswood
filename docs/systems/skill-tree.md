# Skill tree

The tree is the body and the magicka. It is not the profession. Everybody
has the same fifteen sub-skills. A profession decides what you can make.
The tree decides what a point in the body is worth.

Five points fill a sub-skill. Filling it grants its perk. Points past
five in one sub-skill are refused.

## What one point is worth

| Sub-skill | One point | Filled, the perk |
| --- | --- | --- |
| Vitality | +10 health | Cheat Death. Once a day, the blow that would kill you leaves you at 1 health |
| Fortitude | +10% health recovery | Troll's Blood. During a fight, health returns at 2 a second |
| Might | +0.05 melee damage | Devastating Blow. A power attack deals 25% more |
| Resilience | +10 armour | Unshakeable. A block cannot stagger you |
| Toughness | +10 poison resistance and +10 disease resistance | Purified Blood. Disease does not take. Poison deals 25% |
| Capacity | +10 magicka | Archmage's Vessel. Drop below a tenth of magicka and it returns to half, once a day |
| Clarity | +10% magicka recovery | Leyline Attunement. Magicka still returns while you cast, at half the usual rate |
| Potency | +5 spell power, in the schools you hold | Overcharge. One spell in five deals double, or holds twice as long |
| Ward | +5 magic resistance | Spellbreaker. 20% of the magicka in a spell that hits you is added to yours |
| Efficiency | -3 spell cost, in the schools you hold | Font of Magic. Once a day, 15 seconds where a spell costs nothing |
| Endurance | +10 stamina | Tireless. Running and swinging cost half stamina |
| Vigor | +10% stamina recovery | Second Wind. When stamina hits 0 it fills, once every 5 minutes |
| Agility | +2 speed | Windwalker. +4 speed, and a fall deals no damage |
| Burden | +15 carry weight | Pack Mule. Being overloaded does not slow you |
| Precision | +2 critical chance | Lethal Aim. An arrow ignores half the armour it hits |

Might is a fraction added to a multiplier whose base is 1. Five points is
a quarter more melee damage, not five times. Potency and Efficiency do
nothing for someone who holds no school. They spread across the schools
that character has, under that school's own power and skill, because the
game has no single "spell damage" value.

Critical chance is promised by Precision. The game has no clean actor
value for it. The point is still recorded.

## Where the points come from

Choosing places points. They cannot be moved.

| Pick | Points placed |
| --- | --- |
| Hunter | Precision 1 |
| Fisher | Vigor 1 |
| Gatherer | Burden 1 |
| Miner | Might 1 |
| Farmer | Endurance 1 |
| Warrior | Vitality 1, Might 1 |
| Mage | Capacity 1, Clarity 1 |
| Alchemist | Toughness 1, Clarity 1 |
| Cook | Fortitude 1, Endurance 1 |
| Smith | Might 1, Burden 1 |
| Enchanter | Capacity 1, Ward 1 |
| Tailor | Agility 1, Efficiency 1 |
| Woodworker | Endurance 1, Burden 1 |
| Bulwark | Resilience 1 |
| Berserker | Might 1 |
| Blightbrewer | Potency 1 |
| Physicker | Clarity 1 |
| Hearthcook | Vitality 1 |
| Confectioner | Fortitude 1 |
| Platewright | Resilience 1 |
| Edgewright | Precision 1 |
| Bladebinder | Potency 1 |
| Wardweaver | Ward 1 |
| Liverywright | Efficiency 1 |
| Haberdasher | Agility 1 |
| Charburner | Toughness 1 |
| Woodwright | Precision 1 |
| Each mage school | 1 in that school's placed sub-skill: Destruction potency, Restoration clarity, Alteration ward, Conjuration capacity, Illusion efficiency |

A class places 1, a profession 2, a half 1. A mage also places 1 per
school they took. Nobody starts with more than a handful, and no
sub-skill starts near the cap of 5.

Every rank after that gives 1 free point. It goes in any sub-skill that
is not full. Rank comes from work, not from gold and not from being here
a long time. See [Professions](professions.md) for how a rank is earned.

## Where this is

The fifteen sub-skills, the cap of 5, the per-point numbers, the placed
points and the free point per rank are in the server and on the K panel.
Cheat Death, Troll's Blood and the other filled perks are named. The ones
that are a once-a-day effect are not all wired as a daily power yet. The
bottom of a later pass should tick each perk when it actually fires.
Precision's critical chance is recorded and the game may ignore it.
