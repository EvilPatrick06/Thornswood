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

You cannot mine the heart stone until you are a miner of advanced
rank. The profession does not include the class.

<!-- detail:begin -->

## Every recipe

Generated from `game/data/recipes.json` by `scripts/dev/Write-SystemLists.js`. 161 recipes. 161 reach the server. None of them are tempering. The same rows, with ids, are in [enchanter-bladebinder](../../lists/enchanter-bladebinder.md).

The rank on the row is the rank. It is the dearest ingredient a class produces. An item has no gold price.

### Names that reach the server

**Novice** (66 names). Greater Staff of Vipers. Minor Staff of Turning. Minor Staff of the Sun. Staff of Arctic Blast. Staff of Atronach Marks. Staff of Banishing. Staff of Blaze. Staff of Calm. Staff of Chain Lightning. Staff of Command. Staff of Courage. Staff of Crackling. Staff of Crying Eyes. Staff of Dragon's Teeth. Staff of Fear. Staff of Fireballs. Staff of Firebolts. Staff of Flames. Staff of Flesh. Staff of Fractures. Staff of Frenzy. Staff of Frostbite. Staff of Fury. Staff of Greater Reanimation. Staff of Hailstones. Staff of Horsemanship. Staff of Hush. Staff of Ice Spikes. Staff of Ice Storms. Staff of Illusions. Staff of Illusory Flames. Staff of Incendiary Flows. Staff of Inspiration. Staff of Lesser Reanimation. Staff of Lightning Bolts. Staff of Lightning Grasp. Staff of Magelight. Staff of Mending. Staff of Mind Vision. Staff of Necroplagues. Staff of Perilous Paths. Staff of Reanimation. Staff of Rift Bolts. Staff of Shadows. Staff of Silvery Barbs. Staff of Skyfall. Staff of Slaying. Staff of Soul Trapping. Staff of Sparks. Staff of Taldam's Scorcher. Staff of Thundercracks. Staff of Vipers. Staff of Welling Blood. Staff of Withering. Staff of the Cat Totem. Staff of the Creeping Cold. Staff of the Deadeye Captain. Staff of the Dremora Churl. Staff of the Familiar. Staff of the Flame Atronach. Staff of the Frost Atronach. Staff of the Healing Hand. Staff of the Lamb. Staff of the Leech Seed. Staff of the Minor Daedra. Staff of the Silent.

**Advanced** (55 names). Grand Staff of Corrosion. Grand Staff of Turning. Grand Staff of Vipers. Grand Staff of Vulnerability. Grand Staff of the Damned. Greater Staff of the Sun. Staff of Arctic Frost. Staff of Bombardment. Staff of Bravery. Staff of Command. Staff of Daedric Command. Staff of Decomposition. Staff of Domination. Staff of Dread Zombies. Staff of Empathic Agony. Staff of Entombing. Staff of Expulsion. Staff of Fireblooms. Staff of Frostblooms. Staff of Hrormir's Misdirection. Staff of Ice Prisms. Staff of Icy Spear. Staff of Incineration. Staff of Lockblasting. Staff of Monarch Mark. Staff of Mourning. Staff of Nature's Balance. Staff of Paralysis. Staff of Poisoned Chalice. Staff of Purge Magic. Staff of Rage. Staff of Scorching Hands. Staff of Shockblooms. Staff of Sleet Storms. Staff of Tears. Staff of Thunderbolts. Staff of Thundering Grasp. Staff of Vanquishment. Staff of Wildfire. Staff of Wizard Rend. Staff of the Avenging Wraith. Staff of the Clouds. Staff of the Dremora Champion. Staff of the Dremora Honor Guard. Staff of the Flame Wall. Staff of the Frost Wall. Staff of the Herne. Staff of the Major Daedra. Staff of the Oathbound. Staff of the Seidkona. Staff of the Shadow Legion. Staff of the Storm Atronach. Staff of the Storm Wall. Staff of the Ursine Familiar. Staff of the Xivilai Lord.

**Expert** (39 names). Grand Staff of Illusions. Staff of Automaton Breaking. Staff of Bolides. Staff of Charged Storms. Staff of Corpse Explosion. Staff of Corrosion. Staff of Death. Staff of Disintegration. Staff of Electrospheres. Staff of Firehand. Staff of Flame Darts. Staff of Frosthand. Staff of Ganking. Staff of Ice Shards. Staff of Ice Shivs. Staff of Illusory Pyres. Staff of Imprisonment. Staff of Mute. Staff of Pain. Staff of Panic. Staff of Ruin. Staff of Scattershocks. Staff of Shadowbond. Staff of Soothe. Staff of Stormhand. Staff of Subjugation. Staff of Summoning Runes. Staff of Turning. Staff of Undermining. Staff of Vulnerability. Staff of Whispers. Staff of Wilting. Staff of the Ancestors. Staff of the Daedra. Staff of the Damned. Staff of the Dremora Pit Fighter. Staff of the Feline Familiar. Staff of the Sun. Staff of the Xivilai Sorcerer.

**Master** (1 name). Aetherial Staff.

The spell column is the HasSpell the crafting menu asks for. In the college book means that editor id is one of the spells on the mage pages. 13 of 160 staves ask for a spell that is in that book. The rest name a mod spell. A staff whose spell is not in the book can sit at novice in this table and still be unmakeable, because the menu will not list it for someone who was never granted the spell.

| Item | Rank | Bench | Asks for | Spell the menu asks for | In the college book |
| --- | --- | --- | --- | --- | --- |
| Greater Staff of Vipers | novice | DLC2StaffEnchanter | 3 Heart Stone, 1 Unenchanted Restoration Staff | ODN_Res_Poison3_Spell_BlackHand | no |
| Minor Staff of Turning | novice | DLC2StaffEnchanter | 2 Heart Stone, 1 Unenchanted Restoration Staff | TurnLesserUndead | no |
| Minor Staff of the Sun | novice | DLC2StaffEnchanter | 1 Unenchanted Restoration Staff, 2 Heart Stone | DLC1SunFire | no |
| Staff of Arctic Blast | novice | DLC2StaffEnchanter | 1 Unenchanted Destruction Staff, 2 Heart Stone | ODN_Des_Frost2_Spell_ArcticBlast | no |
| Staff of Atronach Marks | novice | DLC2StaffEnchanter | 1 Unenchanted Conjuration Staff, 2 Heart Stone | WB_Con_Curse2_Spell_AtronachMark | no |
| Staff of Banishing | novice | DLC2StaffEnchanter | 3 Heart Stone, 1 Unenchanted Conjuration Staff | ODN_Con_Banish3_Spell_BanishDaedra | no |
| Staff of Blaze | novice | DLC2StaffEnchanter | 1 Unenchanted Destruction Staff, 1 Heart Stone | WB_Des_Fire1_Spell_Blaze_NPC | no |
| Staff of Calm | novice | DLC2StaffEnchanter | 2 Heart Stone, 1 Unenchanted Illusion Staff | ODN_Ill_Calm2_Spell_Calm | no |
| Staff of Chain Lightning | novice | DLC2StaffEnchanter | 3 Heart Stone, 1 Unenchanted Destruction Staff | ODN_Des_Shock3_Spell_ChainLightning | no |
| Staff of Command | novice | DLC2StaffEnchanter | 1 Unenchanted Illusion Staff, 2 Heart Stone | ODN_Ill_Command2_Spell_Command | no |
| Staff of Courage | novice | DLC2StaffEnchanter | 1 Heart Stone, 1 Unenchanted Illusion Staff | ODN_Ill_Rally1_Spell_Courage | no |
| Staff of Crackling | novice | DLC2StaffEnchanter | 1 Unenchanted Destruction Staff, 1 Heart Stone | WB_Des_Shock1_Spell_Crackle_NPC | no |
| Staff of Crying Eyes | novice | DLC2StaffEnchanter | 1 Unenchanted Illusion Staff, 1 Heart Stone | ODN_Ill_Shadow1_Spell_CryingEye | no |
| Staff of Dragon's Teeth | novice | DLC2StaffEnchanter | 1 Unenchanted Destruction Staff, 2 Heart Stone | WB_Des_Fire2_Spell_DragonsTeeth_NPC | no |
| Staff of Fear | novice | DLC2StaffEnchanter | 2 Heart Stone, 1 Unenchanted Illusion Staff | ODN_Ill_Fear2_Spell_Fear | no |
| Staff of Fireballs | novice | DLC2StaffEnchanter | 3 Heart Stone, 1 Unenchanted Destruction Staff | ODN_Des_Fire3_Spell_Fireball | no |
| Staff of Firebolts | novice | DLC2StaffEnchanter | 2 Heart Stone, 1 Unenchanted Destruction Staff | Firebolt | yes, Firebolt |
| Staff of Flames | novice | DLC2StaffEnchanter | 1 Heart Stone, 1 Unenchanted Destruction Staff | Flames | yes, Flames |
| Staff of Flesh | novice | DLC2StaffEnchanter | 1 Unenchanted Conjuration Staff, 1 Heart Stone | WB_Con_Heal1_Spell_AzureReconstruction | no |
| Staff of Fractures | novice | DLC2StaffEnchanter | 1 Unenchanted Destruction Staff, 2 Heart Stone | WB_Des_Frost2_Spell_Fracture_NPC | no |
| Staff of Frenzy | novice | DLC2StaffEnchanter | 3 Heart Stone, 1 Unenchanted Illusion Staff | ODN_Ill_Fury3_Spell_Frenzy | no |
| Staff of Frostbite | novice | DLC2StaffEnchanter | 1 Heart Stone, 1 Unenchanted Destruction Staff | Frostbite | yes, Frostbite |
| Staff of Fury | novice | DLC2StaffEnchanter | 2 Heart Stone, 1 Unenchanted Illusion Staff | ODN_Ill_Fury1_Spell_Fury | no |
| Staff of Greater Reanimation | novice | DLC2StaffEnchanter | 3 Heart Stone, 1 Unenchanted Conjuration Staff | ODN_Con_Reanimate3_Spell | no |
| Staff of Hailstones | novice | DLC2StaffEnchanter | 1 Unenchanted Destruction Staff, 1 Heart Stone | WB_Des_Frost1_Spell_Hailstone_NPC | no |
| Staff of Horsemanship | novice | DLC2StaffEnchanter | 1 Unenchanted Alteration Staff, 2 Heart Stone | ODN_Alt_BuffOther2_Spell_HasteMount | no |
| Staff of Hush | novice | DLC2StaffEnchanter | 1 Unenchanted Illusion Staff, 2 Heart Stone | ODN_Ill_Antimage2_Spell_Hush | no |
| Staff of Ice Spikes | novice | DLC2StaffEnchanter | 2 Heart Stone, 1 Unenchanted Destruction Staff | IceSpike | yes, Ice Spike |
| Staff of Ice Storms | novice | DLC2StaffEnchanter | 3 Heart Stone, 1 Unenchanted Destruction Staff | IceStorm | yes, Ice Storm |
| Staff of Illusions | novice | DLC2StaffEnchanter | 1 Unenchanted Illusion Staff, 2 Heart Stone | ODN_Ill_Simulacrum2_Spell_Simulacrum | no |
| Staff of Illusory Flames | novice | DLC2StaffEnchanter | 1 Unenchanted Illusion Staff, 2 Heart Stone | WB_Ill_TempDmg2_Spell_IllusoryFlames | no |
| Staff of Incendiary Flows | novice | DLC2StaffEnchanter | 1 Unenchanted Destruction Staff, 3 Heart Stone | WB_Des_Fire3_Spell_IncendiaryFlow_NPC | no |
| Staff of Inspiration | novice | DLC2StaffEnchanter | 3 Heart Stone, 1 Unenchanted Illusion Staff | ODN_Ill_Rally3_Spell_Rally | no |
| Staff of Lesser Reanimation | novice | DLC2StaffEnchanter | 1 Heart Stone, 1 Unenchanted Conjuration Staff | ODN_Con_Reanimate1_Spell | no |
| Staff of Lightning Bolts | novice | DLC2StaffEnchanter | 2 Heart Stone, 1 Unenchanted Destruction Staff | LightningBolt | yes, Lightning Bolt |
| Staff of Lightning Grasp | novice | DLC2StaffEnchanter | 1 Unenchanted Destruction Staff, 2 Heart Stone | ODN_Des_Shock2_Spell_LightningGrasp | no |
| Staff of Magelight | novice | DLC2StaffEnchanter | 2 Heart Stone, 1 Unenchanted Alteration Staff | ODN_Alt_Light2_Spell_Magelight | no |
| Staff of Mending | novice | DLC2StaffEnchanter | 3 Heart Stone, 1 Unenchanted Restoration Staff | ODN_Res_HealOther3_Spell | no |
| Staff of Mind Vision | novice | DLC2StaffEnchanter | 1 Unenchanted Illusion Staff, 2 Heart Stone | WB_Ill_Vision2_Spell_MindVision | no |
| Staff of Necroplagues | novice | DLC2StaffEnchanter | 1 Unenchanted Restoration Staff, 2 Heart Stone | WB_Res_Disease2_Spell_Necroplague | no |
| Staff of Perilous Paths | novice | DLC2StaffEnchanter | 1 Unenchanted Alteration Staff, 2 Heart Stone | WB_Alt_CrowdControl2_Spell_PerilousPath | no |
| Staff of Reanimation | novice | DLC2StaffEnchanter | 2 Heart Stone, 1 Unenchanted Conjuration Staff | ODN_Con_Reanimate2_Spell | no |
| Staff of Rift Bolts | novice | DLC2StaffEnchanter | 1 Unenchanted Destruction Staff, 2 Heart Stone | WB_Des_Shock2_Spell_RiftBolt_NPC | no |
| Staff of Shadows | novice | DLC2StaffEnchanter | 1 Unenchanted Illusion Staff, 2 Heart Stone | WB_Ill_Simulacrum1_Spell_PaleShadow | no |
| Staff of Silvery Barbs | novice | DLC2StaffEnchanter | 1 Unenchanted Illusion Staff, 2 Heart Stone | WB_Ill_Antimage1_Spell_SilveryBarbs | no |
| Staff of Skyfall | novice | DLC2StaffEnchanter | 1 Unenchanted Alteration Staff, 2 Heart Stone | WB_Alt_Telekinesis2_Spell_DropZone | no |
| Staff of Slaying | novice | DLC2StaffEnchanter | 1 Unenchanted Restoration Staff, 2 Heart Stone | WB_Res_Necro2_Spell_SlayLiving | no |
| Staff of Soul Trapping | novice | DLC2StaffEnchanter | 2 Heart Stone, 1 Unenchanted Conjuration Staff | SoulTrap | yes, Soul Trap |
| Staff of Sparks | novice | DLC2StaffEnchanter | 1 Heart Stone, 1 Unenchanted Destruction Staff | Sparks | yes, Sparks |
| Staff of Taldam's Scorcher | novice | DLC2StaffEnchanter | 1 Unenchanted Destruction Staff, 2 Heart Stone | ODN_Des_Fire2_Spell_TaldamsScorcher | no |
| Staff of Thundercracks | novice | DLC2StaffEnchanter | 1 Unenchanted Destruction Staff, 2 Heart Stone | WB_Des_Shock2_Spell_Thundercrack_NPC | no |
| Staff of Vipers | novice | DLC2StaffEnchanter | 1 Unenchanted Restoration Staff, 2 Heart Stone | ODN_Res_Poison2_Spell_Viperbolt | no |
| Staff of Welling Blood | novice | DLC2StaffEnchanter | 1 Unenchanted Restoration Staff, 2 Heart Stone | WB_Res_Blood2_Spell_WellingBlood | no |
| Staff of Withering | novice | DLC2StaffEnchanter | 1 Unenchanted Alteration Staff, 2 Heart Stone | WB_Alt_CrowdControl2_Spell_Wither | no |
| Staff of the Cat Totem | novice | DLC2StaffEnchanter | 1 Unenchanted Conjuration Staff, 2 Heart Stone | WB_Con_Spirit2_Spell_ConjureCatTotem | no |
| Staff of the Creeping Cold | novice | DLC2StaffEnchanter | 1 Unenchanted Destruction Staff, 2 Heart Stone | WB_Des_Frost2_Spell_CreepingCold_NPC | no |
| Staff of the Deadeye Captain | novice | DLC2StaffEnchanter | 1 Unenchanted Conjuration Staff, 2 Heart Stone | WB_Con_Undead2_Spell_ConjureDeadeyeCaptain | no |
| Staff of the Dremora Churl | novice | DLC2StaffEnchanter | 1 Unenchanted Conjuration Staff, 2 Heart Stone | WB_Con_Dremora2_Spell_ConjureDremoraChurl_NPC | no |
| Staff of the Familiar | novice | DLC2StaffEnchanter | 1 Heart Stone, 1 Unenchanted Conjuration Staff | ODN_Con_Familiar1_Spell_ConjureFamiliar | no |
| Staff of the Flame Atronach | novice | DLC2StaffEnchanter | 2 Heart Stone, 1 Unenchanted Conjuration Staff | ODN_Con_Atronach2_Spell_ConjureFlameAtronach | no |
| Staff of the Frost Atronach | novice | DLC2StaffEnchanter | 3 Heart Stone, 1 Unenchanted Conjuration Staff | ODN_Con_Atronach3_Spell_ConjureFrostAtronach | no |
| Staff of the Healing Hand | novice | DLC2StaffEnchanter | 2 Heart Stone, 1 Unenchanted Restoration Staff | ODN_Res_HealOther2_Spell | no |
| Staff of the Lamb | novice | DLC2StaffEnchanter | 1 Unenchanted Restoration Staff, 2 Heart Stone | WB_Res_HealCurse2_Spell_LambOfMara | no |
| Staff of the Leech Seed | novice | DLC2StaffEnchanter | 1 Unenchanted Restoration Staff, 2 Heart Stone | WB_Res_Poison2_Spell_LeechSeed | no |
| Staff of the Minor Daedra | novice | DLC2StaffEnchanter | 1 Unenchanted Conjuration Staff, 2 Heart Stone | ODN_Con_Daedra2_Spell_ConjureClannfear | no |
| Staff of the Silent | novice | DLC2StaffEnchanter | 1 Unenchanted Illusion Staff, 2 Heart Stone | WB_Ill_Antimage2_Spell_CurseOfTheSilent | no |
| Grand Staff of Corrosion | advanced | DLC2StaffEnchanter | 1 Unenchanted Alteration Staff, 4 Heart Stone | ODN_Alt_Baleful4_Spell_DireDamageEquipment | no |
| Grand Staff of Turning | advanced | DLC2StaffEnchanter | 4 Heart Stone, 1 Unenchanted Restoration Staff | TurnGreaterUndead | yes, Turn Greater Undead |
| Grand Staff of Vipers | advanced | DLC2StaffEnchanter | 4 Heart Stone, 1 Unenchanted Restoration Staff | ODN_Res_Poison4_Spell_ToxicCloud | no |
| Grand Staff of Vulnerability | advanced | DLC2StaffEnchanter | 1 Unenchanted Alteration Staff, 4 Heart Stone | ODN_Alt_Breach4_Spell_DireWeaknessToElements | no |
| Grand Staff of the Damned | advanced | DLC2StaffEnchanter | 1 Unenchanted Illusion Staff, 4 Heart Stone | ODN_Ill_TempDamage4_Spell_Dirge | no |
| Greater Staff of the Sun | advanced | DLC2StaffEnchanter | 1 Unenchanted Restoration Staff, 4 Heart Stone | ODN_Res_Sun4_Spell_Sunstorm | no |
| Staff of Arctic Frost | advanced | DLC2StaffEnchanter | 1 Unenchanted Destruction Staff, 4 Heart Stone | ODN_Des_Frost4_Spell_ArcticFrost | no |
| Staff of Bombardment | advanced | DLC2StaffEnchanter | 1 Unenchanted Destruction Staff, 4 Heart Stone | WB_Des_Fire4_Spell_Bombardment_NPC | no |
| Staff of Bravery | advanced | DLC2StaffEnchanter | 1 Unenchanted Illusion Staff, 4 Heart Stone | ODN_Ill_Rally4_Spell_Bravery | no |
| Staff of Command | advanced | DLC2StaffEnchanter | 1 Unenchanted Illusion Staff, 4 Heart Stone | WB_Ill_Command4_Spell_MindControl | no |
| Staff of Daedric Command | advanced | DLC2StaffEnchanter | 4 Heart Stone, 1 Unenchanted Conjuration Staff | ODN_Con_Banish4_Spell_CommandDaedra | no |
| Staff of Decomposition | advanced | DLC2StaffEnchanter | 1 Unenchanted Restoration Staff, 4 Heart Stone | WB_Res_Necro4_Spell_Decompose | no |
| Staff of Domination | advanced | DLC2StaffEnchanter | 1 Unenchanted Illusion Staff, 4 Heart Stone | ODN_Ill_Command4_Spell_Dominate | no |
| Staff of Dread Zombies | advanced | DLC2StaffEnchanter | 4 Heart Stone, 1 Unenchanted Conjuration Staff | ODN_Con_Reanimate4_Spell | no |
| Staff of Empathic Agony | advanced | DLC2StaffEnchanter | 1 Unenchanted Illusion Staff, 4 Heart Stone | WB_Ill_PassthroughDmg4_Spell_EmpathicAgony | no |
| Staff of Entombing | advanced | DLC2StaffEnchanter | 1 Unenchanted Alteration Staff, 4 Heart Stone | WB_Alt_CrowdControl4_Spell_Entomb | no |
| Staff of Expulsion | advanced | DLC2StaffEnchanter | 4 Heart Stone, 1 Unenchanted Conjuration Staff | ODN_Con_Banish4_Spell_ExpelDaedra | no |
| Staff of Fireblooms | advanced | DLC2StaffEnchanter | 1 Unenchanted Destruction Staff, 4 Heart Stone | ODN_Des_Fire4_Spell_Firebloom | no |
| Staff of Frostblooms | advanced | DLC2StaffEnchanter | 1 Unenchanted Destruction Staff, 4 Heart Stone | ODN_Des_Frost4_Spell_Frostbloom | no |
| Staff of Hrormir's Misdirection | advanced | DLC2StaffEnchanter | 1 Unenchanted Illusion Staff, 4 Heart Stone | WB_Ill_Invis4_Spell_HrormirsMisdirection | no |
| Staff of Ice Prisms | advanced | DLC2StaffEnchanter | 1 Unenchanted Destruction Staff, 4 Heart Stone | WB_Des_Frost4_Spell_IcePrism_NPC | no |
| Staff of Icy Spear | advanced | DLC2StaffEnchanter | 4 Heart Stone, 1 Unenchanted Destruction Staff | IcySpear | yes, Icy Spear |
| Staff of Incineration | advanced | DLC2StaffEnchanter | 4 Heart Stone, 1 Unenchanted Destruction Staff | Incinerate | yes, Incinerate |
| Staff of Lockblasting | advanced | DLC2StaffEnchanter | 1 Unenchanted Alteration Staff, 4 Heart Stone | WB_Alt_Unlock4_Spell_DetonateLock | no |
| Staff of Monarch Mark | advanced | DLC2StaffEnchanter | 1 Unenchanted Conjuration Staff, 4 Heart Stone | WB_Con_Curse4_Spell_MonarchMark | no |
| Staff of Mourning | advanced | DLC2StaffEnchanter | 1 Unenchanted Conjuration Staff, 4 Heart Stone | ODN_Con_Undead4_Spell_ConjureDreadShade | no |
| Staff of Nature's Balance | advanced | DLC2StaffEnchanter | 1 Unenchanted Restoration Staff, 4 Heart Stone | WB_Res_Peace4_Spell_NaturesBalance | no |
| Staff of Paralysis | advanced | DLC2StaffEnchanter | 4 Heart Stone, 1 Unenchanted Alteration Staff | ODN_Alt_Paralyze4_Spell_Paralyze | no |
| Staff of Poisoned Chalice | advanced | DLC2StaffEnchanter | 1 Unenchanted Restoration Staff, 4 Heart Stone | WB_Res_HealCurse4_Spell_PoisonedChalice | no |
| Staff of Purge Magic | advanced | DLC2StaffEnchanter | 1 Unenchanted Illusion Staff, 4 Heart Stone | ODN_Ill_Antimage4_Spell_PurgeMagic | no |
| Staff of Rage | advanced | DLC2StaffEnchanter | 1 Unenchanted Illusion Staff, 4 Heart Stone | ODN_Ill_Fury4_Spell_Rage | no |
| Staff of Scorching Hands | advanced | DLC2StaffEnchanter | 1 Unenchanted Destruction Staff, 4 Heart Stone | WB_Des_Fire4_Spell_ScorchingHands_NPC | no |
| Staff of Shockblooms | advanced | DLC2StaffEnchanter | 1 Unenchanted Destruction Staff, 4 Heart Stone | ODN_Des_Shock4_Spell_Shockbloom | no |
| Staff of Sleet Storms | advanced | DLC2StaffEnchanter | 1 Unenchanted Destruction Staff, 4 Heart Stone | WB_Des_Frost4_Spell_SleetStorm_NPC | no |
| Staff of Tears | advanced | DLC2StaffEnchanter | 1 Unenchanted Restoration Staff, 4 Heart Stone | ODN_Res_Tap4_Spell_Enervate | no |
| Staff of Thunderbolts | advanced | DLC2StaffEnchanter | 4 Heart Stone, 1 Unenchanted Destruction Staff | Thunderbolt | yes, Thunderbolt |
| Staff of Thundering Grasp | advanced | DLC2StaffEnchanter | 1 Unenchanted Destruction Staff, 4 Heart Stone | ODN_Des_Shock4_Spell_ThunderingGrasp | no |
| Staff of Vanquishment | advanced | DLC2StaffEnchanter | 4 Heart Stone, 1 Unenchanted Illusion Staff | ODN_Ill_Fear4_Spell_Rout | no |
| Staff of Wildfire | advanced | DLC2StaffEnchanter | 1 Unenchanted Destruction Staff, 4 Heart Stone | ODN_Des_Fire4_Spell_Wildfire | no |
| Staff of Wizard Rend | advanced | DLC2StaffEnchanter | 1 Unenchanted Illusion Staff, 4 Heart Stone | ODN_Ill_Antimage4_Spell_WizardRend | no |
| Staff of the Avenging Wraith | advanced | DLC2StaffEnchanter | 1 Unenchanted Conjuration Staff, 4 Heart Stone | WB_Con_Ghost4_Spell_ConjureAvengingWraith | no |
| Staff of the Clouds | advanced | DLC2StaffEnchanter | 1 Unenchanted Destruction Staff, 4 Heart Stone | WB_Des_Shock4_Spell_LightningStrike | no |
| Staff of the Dremora Champion | advanced | DLC2StaffEnchanter | 1 Unenchanted Conjuration Staff, 4 Heart Stone | WB_Con_Dremora4_Spell_ConjureDremoraChampion_NPC | no |
| Staff of the Dremora Honor Guard | advanced | DLC2StaffEnchanter | 1 Unenchanted Conjuration Staff, 4 Heart Stone | WB_Con_Dremora4_Spell_ConjureDremoraHonorGuard_NPC | no |
| Staff of the Flame Wall | advanced | DLC2StaffEnchanter | 4 Heart Stone, 1 Unenchanted Destruction Staff | ODN_Des_Fire4_Spell_WallOfFlames | no |
| Staff of the Frost Wall | advanced | DLC2StaffEnchanter | 4 Heart Stone, 1 Unenchanted Destruction Staff | ODN_Des_Frost4_Spell_WallOfFrost | no |
| Staff of the Herne | advanced | DLC2StaffEnchanter | 1 Unenchanted Conjuration Staff, 4 Heart Stone | WB_Con_Dremora4_Spell_ConjureHerne_NPC | no |
| Staff of the Major Daedra | advanced | DLC2StaffEnchanter | 1 Unenchanted Conjuration Staff, 4 Heart Stone | ODN_Con_Daedra4_Spell_ConjureXivilaiHoundmaster | no |
| Staff of the Oathbound | advanced | DLC2StaffEnchanter | 1 Unenchanted Conjuration Staff, 4 Heart Stone | WB_Con_Ghost4_Spell_OathboundGuardian | no |
| Staff of the Seidkona | advanced | DLC2StaffEnchanter | 1 Unenchanted Illusion Staff, 4 Heart Stone | WB_Ill_Simulacrum4_Spell_Seidstone | no |
| Staff of the Shadow Legion | advanced | DLC2StaffEnchanter | 1 Unenchanted Illusion Staff, 4 Heart Stone | ODN_Ill_Simulacrum4_Spell_ShadowLegion | no |
| Staff of the Storm Atronach | advanced | DLC2StaffEnchanter | 4 Heart Stone, 1 Unenchanted Conjuration Staff | ODN_Con_Atronach4_Spell_ConjureStormAtronach | no |
| Staff of the Storm Wall | advanced | DLC2StaffEnchanter | 4 Heart Stone, 1 Unenchanted Destruction Staff | ODN_Des_Shock4_Spell_WallOfStorms | no |
| Staff of the Ursine Familiar | advanced | DLC2StaffEnchanter | 1 Unenchanted Conjuration Staff, 4 Heart Stone | ODN_Con_Familiar4_Spell_ConjureUrsineFamiliar | no |
| Staff of the Xivilai Lord | advanced | DLC2StaffEnchanter | 1 Unenchanted Conjuration Staff, 4 Heart Stone | WB_Con_Xivilai4_Spell_ConjureXivilaiLord_NPC | no |
| Grand Staff of Illusions | expert | DLC2StaffEnchanter | 1 Unenchanted Illusion Staff, 3 Heart Stone | ODN_Ill_Simulacrum3_Spell_GreaterSimulacrum | no |
| Staff of Automaton Breaking | expert | DLC2StaffEnchanter | 1 Unenchanted Restoration Staff, 3 Heart Stone | WB_Res_Peace3_Spell_DustInTheClockwork | no |
| Staff of Bolides | expert | DLC2StaffEnchanter | 1 Unenchanted Destruction Staff, 3 Heart Stone | WB_Des_Fire3_Spell_Bolide_NPC | no |
| Staff of Charged Storms | expert | DLC2StaffEnchanter | 1 Unenchanted Destruction Staff, 3 Heart Stone | ODN_Des_Shock3_Spell_ChargedStorm | no |
| Staff of Corpse Explosion | expert | DLC2StaffEnchanter | 1 Unenchanted Conjuration Staff, 3 Heart Stone | WB_Con_Corpse3_Spell_CorpseExplosion | no |
| Staff of Corrosion | expert | DLC2StaffEnchanter | 1 Unenchanted Alteration Staff, 3 Heart Stone | ODN_Alt_Baleful3_Spell_DamageEquipment | no |
| Staff of Death | expert | DLC2StaffEnchanter | 1 Unenchanted Restoration Staff, 3 Heart Stone | WB_Res_Necro3_Spell_FingerOfDeath | no |
| Staff of Disintegration | expert | DLC2StaffEnchanter | 1 Unenchanted Restoration Staff, 3 Heart Stone | ODN_Res_Necro3_Spell_DestroyLiving | no |
| Staff of Electrospheres | expert | DLC2StaffEnchanter | 1 Unenchanted Destruction Staff, 3 Heart Stone | WB_Des_Shock3_Spell_Electrosphere_NPC | no |
| Staff of Firehand | expert | DLC2StaffEnchanter | 1 Unenchanted Destruction Staff, 3 Heart Stone | ODN_Des_Fire3_Spell_Firehand | no |
| Staff of Flame Darts | expert | DLC2StaffEnchanter | 1 Unenchanted Destruction Staff, 3 Heart Stone | ODN_Des_Fire3_Spell_FlameDarts | no |
| Staff of Frosthand | expert | DLC2StaffEnchanter | 1 Unenchanted Destruction Staff, 3 Heart Stone | ODN_Des_Frost3_Spell_Frosthand | no |
| Staff of Ganking | expert | DLC2StaffEnchanter | 1 Unenchanted Conjuration Staff, 3 Heart Stone | WB_Con_Summon3_Spell_Gank | no |
| Staff of Ice Shards | expert | DLC2StaffEnchanter | 1 Unenchanted Destruction Staff, 3 Heart Stone | ODN_Des_Frost3_Spell_IceShards | no |
| Staff of Ice Shivs | expert | DLC2StaffEnchanter | 1 Unenchanted Destruction Staff, 3 Heart Stone | WB_Des_Frost3_Spell_IceShiv_NPC | no |
| Staff of Illusory Pyres | expert | DLC2StaffEnchanter | 1 Unenchanted Illusion Staff, 3 Heart Stone | WB_Ill_TempDmg3_Spell_IllusoryPyre | no |
| Staff of Imprisonment | expert | DLC2StaffEnchanter | 1 Unenchanted Alteration Staff, 3 Heart Stone | WB_Alt_CrowdControl3_Spell_TharnsPrison | no |
| Staff of Mute | expert | DLC2StaffEnchanter | 1 Unenchanted Illusion Staff, 3 Heart Stone | ODN_Ill_Antimage3_Spell_Mute | no |
| Staff of Pain | expert | DLC2StaffEnchanter | 1 Unenchanted Illusion Staff, 3 Heart Stone | WB_Ill_PassthroughDmg3_Spell_FigmentOfPain | no |
| Staff of Panic | expert | DLC2StaffEnchanter | 1 Unenchanted Illusion Staff, 3 Heart Stone | ODN_Ill_Fear3_Spell_Panic | no |
| Staff of Ruin | expert | DLC2StaffEnchanter | 1 Unenchanted Restoration Staff, 3 Heart Stone | WB_Res_Tap3_Spell_Ruin | no |
| Staff of Scattershocks | expert | DLC2StaffEnchanter | 1 Unenchanted Destruction Staff, 3 Heart Stone | WB_Des_Shock3_Spell_Scattershock_NPC | no |
| Staff of Shadowbond | expert | DLC2StaffEnchanter | 1 Unenchanted Illusion Staff, 3 Heart Stone | WB_Ill_Invis3_Spell_Shadowbond | no |
| Staff of Soothe | expert | DLC2StaffEnchanter | 1 Unenchanted Illusion Staff, 3 Heart Stone | ODN_Ill_Calm3_Spell_Soothe | no |
| Staff of Stormhand | expert | DLC2StaffEnchanter | 1 Unenchanted Destruction Staff, 3 Heart Stone | ODN_Des_Shock3_Spell_Stormhand | no |
| Staff of Subjugation | expert | DLC2StaffEnchanter | 1 Unenchanted Illusion Staff, 3 Heart Stone | ODN_Ill_Command3_Spell_Subjugate | no |
| Staff of Summoning Runes | expert | DLC2StaffEnchanter | 1 Unenchanted Conjuration Staff, 3 Heart Stone | WB_Con_Summon3_Spell_SummoningRune | no |
| Staff of Turning | expert | DLC2StaffEnchanter | 3 Heart Stone, 1 Unenchanted Restoration Staff | TurnUndead | yes, Turn Undead |
| Staff of Undermining | expert | DLC2StaffEnchanter | 1 Unenchanted Alteration Staff, 3 Heart Stone | WB_Alt_CrowdControl3_Spell_Undermine | no |
| Staff of Vulnerability | expert | DLC2StaffEnchanter | 1 Unenchanted Alteration Staff, 3 Heart Stone | ODN_Alt_Breach3_Spell_WeaknessToElements | no |
| Staff of Whispers | expert | DLC2StaffEnchanter | 1 Unenchanted Illusion Staff, 3 Heart Stone | WB_Ill_Command3_Spell_CompellingWhispers | no |
| Staff of Wilting | expert | DLC2StaffEnchanter | 1 Unenchanted Restoration Staff, 3 Heart Stone | WB_Res_Disease3_Spell_HorridWilting | no |
| Staff of the Ancestors | expert | DLC2StaffEnchanter | 1 Unenchanted Conjuration Staff, 3 Heart Stone | ODN_Con_Undead3_Spell_ConjureGloomWraith | no |
| Staff of the Daedra | expert | DLC2StaffEnchanter | 1 Unenchanted Conjuration Staff, 3 Heart Stone | ODN_Con_Daedra3_Spell_ConjureDaedroth | no |
| Staff of the Damned | expert | DLC2StaffEnchanter | 1 Unenchanted Illusion Staff, 3 Heart Stone | ODN_Ill_TempDamage3_Spell_DiscordantWail | no |
| Staff of the Dremora Pit Fighter | expert | DLC2StaffEnchanter | 1 Unenchanted Conjuration Staff, 3 Heart Stone | WB_Con_Dremora3_Spell_ConjureDremoraPitFighter_NPC | no |
| Staff of the Feline Familiar | expert | DLC2StaffEnchanter | 1 Unenchanted Conjuration Staff, 3 Heart Stone | ODN_Con_Familiar3_Spell_ConjureFelineFamiliar | no |
| Staff of the Sun | expert | DLC2StaffEnchanter | 3 Heart Stone, 1 Unenchanted Restoration Staff | ODN_Res_Sun3_Spell_VampiresBane | no |
| Staff of the Xivilai Sorcerer | expert | DLC2StaffEnchanter | 1 Unenchanted Conjuration Staff, 3 Heart Stone | WB_Con_Xivilai3_Spell_ConjureXivilaiSorcerer_NPC | no |
| Aetherial Staff | master | DLC1LD_CraftingForgeAetherium | 1 Aetherium Crest, 2 Dwarven Metal Ingot, 2 Ebony Ingot, 1 Gold Ingot |  |  |

<!-- detail:end -->

## Where this is

The 161 rows, the staff enchanter, and the unlock points are in the
server. Heart stone is still advanced in the ore table. Nothing has
been removed from the recipe file.
