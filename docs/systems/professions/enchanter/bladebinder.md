# Bladebinder

Staves whose spell is in the college book. Thirteen of them. The
other 147, and the Aetherial Staff, are held in
[Cut items](../../cut-items.md) and are not made.

The thirteen that stay:

| Staff | Spell in the book |
| --- | --- |
| Staff of Flames | Flames |
| Staff of Frostbite | Frostbite |
| Staff of Sparks | Sparks |
| Staff of Firebolts | Firebolt |
| Staff of Ice Spikes | Ice Spike |
| Staff of Lightning Bolts | Lightning Bolt |
| Staff of Ice Storms | Ice Storm |
| Staff of Soul Trapping | Soul Trap |
| Staff of Turning | Turn Undead |
| Grand Staff of Turning | Turn Greater Undead |
| Staff of Incineration | Incinerate |
| Staff of Icy Spear | Icy Spear |
| Staff of Thunderbolts | Thunderbolt |

Heart stone is master mining, one place, because the book no longer
needs a novice to pull it. See [Miner](../../classes/miner.md).

The table under Every recipe is the server book, all 161 rows. The
column that says whether the spell is in the college book is how a
row is told apart from the thirteen above.

The Aetherial Staff is cut with the Aetherium. It wanted an aetherium
crest, 2 dwarven metal ingots, 2 ebony ingots and 1 gold ingot. Worth
1250. The reference stays in the cut file.

## The spell the menu asks for

Every staff except the Aetherial Staff has a HasSpell condition. The
crafting menu will not show the row unless that spell is on you.
Unlocking it on K puts the spell on you for that reason.

13 of the 160 staves that ask for a spell name a spell in the college
book. The other 147 name a mod spell, Odin or Apocalypse, that the
book does not contain. The recipe can be novice and still be
unmakeable, because nothing grants that spell. Knowing the book's
Calm does not satisfy a condition that names the Odin spell of the
same idea. The plan is that only the college book is granted. Those
staves stay in the table so they can be marked wrong: either the book
grows, or the row should not be a staff we expect anyone to make.
The table below says which spell, and whether it is in the book.

## Staff spells

You start with 2 points. Each rank before master gives 1. Master gives
2. The spell's rank cannot pass your Bladebinder rank. A novice spell
needs none below it.

The schools those spells belong to are the mage book:
[Destruction](../mage/destruction.md),
[Restoration](../mage/restoration.md),
[Alteration](../mage/alteration.md),
[Conjuration](../mage/conjuration.md),
[Illusion](../mage/illusion.md).
A staff does not give you the school. It gives you that one spell on
a stick, and only if you unlocked it.

## What you are handed

The half places 1 in Potency. With no school held, that point does
not change a spell. A Bladebinder who is also a mage feels it in the
schools they hold.

## What you cannot do

You cannot enchant a cuirass here. That is Wardweaver, and your sister
half is that menu at novice, which means you may use the arcane
enchanter. It does not hand you Wardweaver's extra Ward point.

You cannot mine the heart stone until you are a miner of master
rank. The profession does not include the class.

<!-- detail:begin -->

## Every recipe

Generated from `game/data/recipes.json` by `scripts/dev/Write-SystemLists.js`. 13 recipes. 13 reach the server. None of them are tempering. The same rows, with ids, are in [enchanter-bladebinder](../../lists/enchanter-bladebinder.md).

The rank on the row is the rank. It is the dearest ingredient a class produces. An item has no gold price.

### Names that reach the server

**Novice** (8 names). Staff of Firebolts. Staff of Flames. Staff of Frostbite. Staff of Ice Spikes. Staff of Ice Storms. Staff of Lightning Bolts. Staff of Soul Trapping. Staff of Sparks.

**Advanced** (4 names). Grand Staff of Turning. Staff of Icy Spear. Staff of Incineration. Staff of Thunderbolts.

**Expert** (1 name). Staff of Turning.

**Master.** None.

The spell column is the HasSpell the crafting menu asks for. In the college book means that editor id is one of the spells on the mage pages. 13 of 13 staves ask for a spell that is in that book. The rest name a mod spell. A staff whose spell is not in the book can sit at novice in this table and still be unmakeable, because the menu will not list it for someone who was never granted the spell.

| Item | Rank | Bench | Asks for | Spell the menu asks for | In the college book |
| --- | --- | --- | --- | --- | --- |
| Staff of Firebolts | novice | DLC2StaffEnchanter | 2 Heart Stone, 1 Unenchanted Destruction Staff | Firebolt | yes, Firebolt |
| Staff of Flames | novice | DLC2StaffEnchanter | 1 Heart Stone, 1 Unenchanted Destruction Staff | Flames | yes, Flames |
| Staff of Frostbite | novice | DLC2StaffEnchanter | 1 Heart Stone, 1 Unenchanted Destruction Staff | Frostbite | yes, Frostbite |
| Staff of Ice Spikes | novice | DLC2StaffEnchanter | 2 Heart Stone, 1 Unenchanted Destruction Staff | IceSpike | yes, Ice Spike |
| Staff of Ice Storms | novice | DLC2StaffEnchanter | 3 Heart Stone, 1 Unenchanted Destruction Staff | IceStorm | yes, Ice Storm |
| Staff of Lightning Bolts | novice | DLC2StaffEnchanter | 2 Heart Stone, 1 Unenchanted Destruction Staff | LightningBolt | yes, Lightning Bolt |
| Staff of Soul Trapping | novice | DLC2StaffEnchanter | 2 Heart Stone, 1 Unenchanted Conjuration Staff | SoulTrap | yes, Soul Trap |
| Staff of Sparks | novice | DLC2StaffEnchanter | 1 Heart Stone, 1 Unenchanted Destruction Staff | Sparks | yes, Sparks |
| Grand Staff of Turning | advanced | DLC2StaffEnchanter | 4 Heart Stone, 1 Unenchanted Restoration Staff | TurnGreaterUndead | yes, Turn Greater Undead |
| Staff of Icy Spear | advanced | DLC2StaffEnchanter | 4 Heart Stone, 1 Unenchanted Destruction Staff | IcySpear | yes, Icy Spear |
| Staff of Incineration | advanced | DLC2StaffEnchanter | 4 Heart Stone, 1 Unenchanted Destruction Staff | Incinerate | yes, Incinerate |
| Staff of Thunderbolts | advanced | DLC2StaffEnchanter | 4 Heart Stone, 1 Unenchanted Destruction Staff | Thunderbolt | yes, Thunderbolt |
| Staff of Turning | expert | DLC2StaffEnchanter | 3 Heart Stone, 1 Unenchanted Restoration Staff | TurnUndead | yes, Turn Undead |

<!-- detail:end -->

## Where this is

The 161 rows, the staff enchanter, and the unlock points are in the
server. Heart stone is master in the ore table. Cut staves are out of the open recipe book. The references stay in the cut file.
