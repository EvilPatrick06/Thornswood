# Where every item comes from

Generated from `game/data/item-sources.json` by `scripts/dev/Write-SystemLists.js`. 1047 items: everything somebody can come to hold, and every input a live recipe asks for. Each is marked with every way it comes into the world. `scripts/dev/Build-ItemSources.js` builds the table; run it, then this script, after a recipe, work, quest or dungeon table changes. Balance is what a thing takes to make or get plus its stats, never gold.

| Kind | What it means | Items | Only this |
| --- | --- | --- | --- |
| crafted | made at a bench by a profession, by anybody where no profession owns the recipe, or made by the server in place of a recipe's output (fine and burnt dishes, hair dye) | 709 | 652 |
| race | a recipe only the named race may make | 38 | 25 |
| company | a Free Skyrim Trading Company ware (cut-items.json rieklingKept) | 13 | 0 |
| faction | a recipe only the embassy roll or the remnant roll may make | 24 | 24 |
| quest | drawn only while a merchant's scarce work is open, a rare seam its quest opens, or a retrieval token | 21 | 11 |
| gathered | a class's work: picked, grown, fished, hunted, mined or pressed | 137 | 112 |
| found | created by a dungeon chest or a body | 180 | 112 |
| start | handed to a new character: first clothes, a class's tool, a farmer's first seeds | 11 | 0 |

Not a source: a cut recipe, a tempering row (grindstone, armour table), a Hearthfire building row, a deed, key or key mold (named claim papers), and gold.

## Nothing hands these out

17 items a live recipe asks for, or a hair dye or a bottle of water needs, that no recipe, class, quest, dungeon or starting kit hands out. Every recipe that asks for one of them cannot be made.

| Item | Asked for by | Id |
| --- | --- | --- |
| Boar Meat | Boar Stew, Cooked Boar Meat | `3bd14:Dragonborn.esm` |
| Drum | Drum | `daba9:Skyrim.esm` |
| Dwarven Oil | Dwemer Fire Paste | `f11c0:Skyrim.esm` |
| Eidar Cheese Wheel | Eidar Cheese Fondue | `64b34:Skyrim.esm` |
| Empty Wine Bottle | a hair dye or a bottle of water | `f2012:Skyrim.esm` |
| Flute | Flute | `daba7:Skyrim.esm` |
| Honey | Honey Nut Treat | `10394d:Skyrim.esm` |
| Linen Wrap | Apotheus Scarf, Bandana, Bandana, Tied, College of Winterhold Cloak, Dark Brotherhood Cloak, Dawngaurd Cloak and 40 more | `34cd6:Skyrim.esm` |
| Lute | Lute | `dabab:Skyrim.esm` |
| Mammoth Cheese Bowl | Mammoth Cheese Fondue | `669a3:Skyrim.esm` |
| Sliced Goat Cheese Wheel | Goat Cheese Fondue | `64b35:Skyrim.esm` |
| Small Antlers | Forsworn Headdress | `6bc0b:Skyrim.esm` |
| Spider Egg | Bosmer Engraved Shoulder Cape, Bosmer Full Cape, Bosmer Mask, Bosmer Shoulder Cape | `9151b:Skyrim.esm` |
| Unenchanted Conjuration Staff | Staff of Soul Trapping | `7e647:Skyrim.esm` |
| Unenchanted Destruction Staff | Staff of Firebolts, Staff of Flames, Staff of Frostbite, Staff of Ice Spikes, Staff of Ice Storms, Staff of Icy Spear and 4 more | `be11f:Skyrim.esm` |
| Unenchanted Restoration Staff | Grand Staff of Turning, Staff of Turning | `51b0c:Skyrim.esm` |
| White Wine | Eidar Cheese Fondue, Goat Cheese Fondue, Mammoth Cheese Fondue | `3133c:Skyrim.esm` |

## Only from a quest

11 items. Drawn only while a merchant's scarce work is open, a rare seam its quest opens, or a retrieval token.

| Item | Sources | Id |
| --- | --- | --- |
| Crimson Nirnroot | quest crimson (game/data/merchant-scarce-harvest.json) | `b701a:Skyrim.esm` |
| Guild Ledger | quest ledger (game/data/merchant-retrievals.json) | `17001:Thornswood-Content.esp` |
| Guild Locket | quest locket (game/data/merchant-retrievals.json) | `17003:Thornswood-Content.esp` |
| Guild Satchel | quest satchel (game/data/merchant-retrievals.json) | `17000:Thornswood-Content.esp` |
| Guild Seal | quest seal (game/data/merchant-retrievals.json) | `17006:Thornswood-Content.esp` |
| Guild Signet | quest signet (game/data/merchant-retrievals.json) | `17002:Thornswood-Content.esp` |
| Heart Stone | quest miner heartstone master (ores.json, the rare seams of game/gamemode.js custom quests) | `17749:Dragonborn.esm` |
| Petty Soul Gem | quest geode (game/data/merchant-scarce-geodes.json) | `2e4e2:Skyrim.esm` |
| Sealed Guild Case | quest case (game/data/merchant-retrievals.json) | `17004:Thornswood-Content.esp` |
| Sealed Guild Dispatch | quest dispatch (game/data/merchant-retrievals.json) | `17005:Thornswood-Content.esp` |
| Stalhrim | quest miner stalhrim master (ores.json, the rare seams of game/gamemode.js custom quests) | `2b06b:Dragonborn.esm` |

## Only found

112 items. Created only by a dungeon chest or a body.

| Item | Sources | Id |
| --- | --- | --- |
| Ale | found tier 1 (dungeon goods) | `34c5e:Skyrim.esm` |
| Ancient Nord Amulet | found tier 1 (dungeon exclusive) | `cc842:Skyrim.esm` |
| Ancient Nord Arrow | found tier 2 (dungeon exclusive) | `34182:Skyrim.esm` |
| Ancient Nord Battleaxe | found tier 4 (dungeon exclusive) | `1cb64:Skyrim.esm` |
| Ancient Nord Bow | found tier 3 (dungeon exclusive) | `302ca:Skyrim.esm` |
| Ancient Nord Greatsword | found tier 4 (dungeon exclusive) | `236a5:Skyrim.esm` |
| Ancient Nord Sword | found tier 2 (dungeon exclusive) | `2c66f:Skyrim.esm` |
| Ancient Nord War Axe | found tier 2 (dungeon exclusive) | `2c672:Skyrim.esm` |
| Black Soul Gem | found tier 4 (dungeon exclusive) | `2e500:Skyrim.esm` |
| Bone Meal | found tier 1 (dungeon goods) | `34cdd:Skyrim.esm` |
| Bread | found tier 1 (dungeon goods) | `65c98:Skyrim.esm` |
| Common Soul Gem | found tier 3 (dungeon goods) | `2e4e6:Skyrim.esm` |
| Diamond | found tier 4 (dungeon goods) | `63b47:Skyrim.esm` |
| Eidar Cheese Wedge | found tier 1 (dungeon goods) | `64b32:Skyrim.esm` |
| Flawless Diamond | found tier 4 (dungeon goods) | `6851f:Skyrim.esm` |
| Flawless Garnet | found tier 4 (dungeon goods) | `68521:Skyrim.esm` |
| Garnet | found tier 2 (dungeon goods) | `63b45:Skyrim.esm` |
| Goat Cheese Wedge | found tier 1 (dungeon goods) | `64b31:Skyrim.esm` |
| Grand Soul Gem | found tier 4 (dungeon goods) | `2e4fc:Skyrim.esm` |
| Greater Soul Gem | found tier 4 (dungeon goods) | `2e4f4:Skyrim.esm` |
| Hunting Bow | found tier 1 (dungeon goods) | `13985:Skyrim.esm` |
| Lesser Soul Gem | found tier 2 (dungeon goods) | `2e4e4:Skyrim.esm` |
| Lockpick | found tier 1 (dungeon goods) | `a:Skyrim.esm` |
| Long Bow | found tier 1 (dungeon goods) | `3b562:Skyrim.esm` |
| Orichalcum Ingot | found tier 4 (dungeon goods) | `43e27:Skyrim.esm` |
| Petty Soul Gem | found tier 1 (dungeon goods) | `1fe9b:Skyrim.esm` |
| Potion of Healing | found tier 2 (dungeon goods) | `3eade:Skyrim.esm` |
| Potion of Magicka | found tier 2 (dungeon goods) | `3eae1:Skyrim.esm` |
| Potion of Minor Healing | found tier 1 (dungeon goods) | `3eadd:Skyrim.esm` |
| Potion of Minor Magicka | found tier 1 (dungeon goods) | `3eae0:Skyrim.esm` |
| Potion of Minor Stamina | found tier 1 (dungeon goods) | `3eae5:Skyrim.esm` |
| Potion of Plentiful Healing | found tier 3 (dungeon goods) | `3eadf:Skyrim.esm` |
| Potion of Resist Fire | found tier 2 (dungeon goods) | `39b4a:Skyrim.esm` |
| Potion of Resist Shock | found tier 2 (dungeon goods) | `39be1:Skyrim.esm` |
| Potion of Stamina | found tier 2 (dungeon goods) | `39be8:Skyrim.esm` |
| Potion of Vigorous Healing | found tier 4 (dungeon goods) | `3eae3:Skyrim.esm` |
| Spell Tome: Bane of the Undead | found (dungeon tomes master) | `dd647:Skyrim.esm` |
| Spell Tome: Blizzard | found (dungeon tomes master) | `a270d:Skyrim.esm` |
| Spell Tome: Bound Battleaxe | found (dungeon tomes adept) | `a26ed:Skyrim.esm` |
| Spell Tome: Bound Bow | found (dungeon tomes expert) | `a26f1:Skyrim.esm` |
| Spell Tome: Bound Sword | found (dungeon tomes apprentice) | `9e2a9:Skyrim.esm` |
| Spell Tome: Call To Arms | found (dungeon tomes master) | `a271b:Skyrim.esm` |
| Spell Tome: Calm | found (dungeon tomes apprentice) | `a2711:Skyrim.esm` |
| Spell Tome: Candlelight | found (dungeon tomes novice) | `9e2a7:Skyrim.esm` |
| Spell Tome: Chain Lightning | found (dungeon tomes adept) | `a2708:Skyrim.esm` |
| Spell Tome: Clairvoyance | found (dungeon tomes novice) | `ff7d1:Skyrim.esm` |
| Spell Tome: Conjure Familiar | found (dungeon tomes novice) | `9e2ab:Skyrim.esm` |
| Spell Tome: Conjure Flame Atronach | found (dungeon tomes apprentice) | `a26ec:Skyrim.esm` |
| Spell Tome: Conjure Frost Atronach | found (dungeon tomes adept) | `a26ef:Skyrim.esm` |
| Spell Tome: Conjure Storm Atronach | found (dungeon tomes expert) | `a26f0:Skyrim.esm` |
| Spell Tome: Courage | found (dungeon tomes novice) | `9e2ad:Skyrim.esm` |
| Spell Tome: Dead Thrall | found (dungeon tomes master) | `a26f9:Skyrim.esm` |
| Spell Tome: Detect Life | found (dungeon tomes adept) | `a26e7:Skyrim.esm` |
| Spell Tome: Detect Undead | found (dungeon tomes expert) | `a26ea:Skyrim.esm` |
| Spell Tome: Dragonhide | found (dungeon tomes master) | `d2b4e:Skyrim.esm` |
| Spell Tome: Dread Zombie | found (dungeon tomes expert) | `a26f7:Skyrim.esm` |
| Spell Tome: Ebonyflesh | found (dungeon tomes expert) | `a26e9:Skyrim.esm` |
| Spell Tome: Expel Daedra | found (dungeon tomes expert) | `a26f8:Skyrim.esm` |
| Spell Tome: Fast Healing | found (dungeon tomes apprentice) | `a271d:Skyrim.esm` |
| Spell Tome: Fear | found (dungeon tomes apprentice) | `a2712:Skyrim.esm` |
| Spell Tome: Fire Rune | found (dungeon tomes adept) | `a2700:Skyrim.esm` |
| Spell Tome: Fire Storm | found (dungeon tomes master) | `a270c:Skyrim.esm` |
| Spell Tome: Fireball | found (dungeon tomes adept) | `a2706:Skyrim.esm` |
| Spell Tome: Firebolt | found (dungeon tomes apprentice) | `a26fd:Skyrim.esm` |
| Spell Tome: Flame Cloak | found (dungeon tomes adept) | `a2703:Skyrim.esm` |
| Spell Tome: Flame Thrall | found (dungeon tomes master) | `a26fa:Skyrim.esm` |
| Spell Tome: Flames | found (dungeon tomes novice) | `9cd51:Skyrim.esm` |
| Spell Tome: Frenzy | found (dungeon tomes adept) | `a2714:Skyrim.esm` |
| Spell Tome: Frost Cloak | found (dungeon tomes adept) | `a2704:Skyrim.esm` |
| Spell Tome: Frost Rune | found (dungeon tomes adept) | `a2701:Skyrim.esm` |
| Spell Tome: Frost Thrall | found (dungeon tomes master) | `a26fb:Skyrim.esm` |
| Spell Tome: Frostbite | found (dungeon tomes novice) | `9cd52:Skyrim.esm` |
| Spell Tome: Fury | found (dungeon tomes novice) | `9e2ac:Skyrim.esm` |
| Spell Tome: Grand Healing | found (dungeon tomes expert) | `dd643:Skyrim.esm` |
| Spell Tome: Harmony | found (dungeon tomes master) | `a271a:Skyrim.esm` |
| Spell Tome: Heal Other | found (dungeon tomes adept) | `a2727:Skyrim.esm` |
| Spell Tome: Healing | found (dungeon tomes novice) | `9e2af:Skyrim.esm` |
| Spell Tome: Healing Hands | found (dungeon tomes apprentice) | `a271e:Skyrim.esm` |
| Spell Tome: Hysteria | found (dungeon tomes master) | `a271c:Skyrim.esm` |
| Spell Tome: Ice Spike | found (dungeon tomes apprentice) | `a26fe:Skyrim.esm` |
| Spell Tome: Ice Storm | found (dungeon tomes adept) | `a2707:Skyrim.esm` |
| Spell Tome: Invisibility | found (dungeon tomes expert) | `a2715:Skyrim.esm` |
| Spell Tome: Ironflesh | found (dungeon tomes adept) | `a26e4:Skyrim.esm` |
| Spell Tome: Lesser Ward | found (dungeon tomes novice) | `9e2ae:Skyrim.esm` |
| Spell Tome: Lightning Bolt | found (dungeon tomes apprentice) | `a26ff:Skyrim.esm` |
| Spell Tome: Lightning Cloak | found (dungeon tomes adept) | `a2705:Skyrim.esm` |
| Spell Tome: Lightning Rune | found (dungeon tomes adept) | `a2702:Skyrim.esm` |
| Spell Tome: Lightning Storm | found (dungeon tomes master) | `a270e:Skyrim.esm` |
| Spell Tome: Magelight | found (dungeon tomes apprentice) | `a26e2:Skyrim.esm` |
| Spell Tome: Mara's Embrace | found (dungeon tomes master) | `fde7b:Skyrim.esm` |
| Spell Tome: Mass Paralysis | found (dungeon tomes master) | `dd646:Skyrim.esm` |
| Spell Tome: Mayhem | found (dungeon tomes master) | `a2719:Skyrim.esm` |
| Spell Tome: Muffle | found (dungeon tomes apprentice) | `a270f:Skyrim.esm` |
| Spell Tome: Oakflesh | found (dungeon tomes novice) | `9e2a8:Skyrim.esm` |
| Spell Tome: Pacify | found (dungeon tomes adept) | `a2717:Skyrim.esm` |
| Spell Tome: Paralyze | found (dungeon tomes expert) | `a26e8:Skyrim.esm` |
| Spell Tome: Rally | found (dungeon tomes adept) | `a2713:Skyrim.esm` |
| Spell Tome: Reanimate Corpse | found (dungeon tomes apprentice) | `a26eb:Skyrim.esm` |
| Spell Tome: Rout | found (dungeon tomes expert) | `a2718:Skyrim.esm` |
| Spell Tome: Soul Trap | found (dungeon tomes apprentice) | `9cd54:Skyrim.esm` |
| Spell Tome: Sparks | found (dungeon tomes novice) | `9cd53:Skyrim.esm` |
| Spell Tome: Steadfast Ward | found (dungeon tomes adept) | `a2720:Skyrim.esm` |
| Spell Tome: Stoneflesh | found (dungeon tomes apprentice) | `a26e3:Skyrim.esm` |
| Spell Tome: Storm Thrall | found (dungeon tomes master) | `a26fc:Skyrim.esm` |
| Spell Tome: Telekinesis | found (dungeon tomes adept) | `a26e5:Skyrim.esm` |
| Spell Tome: Turn Greater Undead | found (dungeon tomes expert) | `a2729:Skyrim.esm` |
| Spell Tome: Turn Lesser Undead | found (dungeon tomes apprentice) | `a271f:Skyrim.esm` |
| Spell Tome: Turn Undead | found (dungeon tomes adept) | `a2721:Skyrim.esm` |
| Spell Tome: Wall of Flames | found (dungeon tomes expert) | `a2709:Skyrim.esm` |
| Spell Tome: Wall of Frost | found (dungeon tomes expert) | `a270a:Skyrim.esm` |
| Spell Tome: Wall of Storms | found (dungeon tomes expert) | `a270b:Skyrim.esm` |
| Spell Tome: Waterbreathing | found (dungeon tomes adept) | `a26e6:Skyrim.esm` |

## Faction work

24 items. Only the embassy roll or the remnant roll may make these.

| Item | Sources | Id |
| --- | --- | --- |
| Hooded Thalmor Robes | faction Tailor/Liverywright remnant novice | `820:MoreCraftableEquipment.esp` |
| Imperial Boots | faction Smith/Platewright embassy advanced | `136d6:Skyrim.esm` |
| Imperial Bracers | faction Smith/Platewright embassy advanced | `136d4:Skyrim.esm` |
| Imperial Heavy Shield | faction Smith/Platewright embassy advanced | `135ba:Skyrim.esm` |
| Imperial Helmet | faction Smith/Platewright embassy advanced | `13edc:Skyrim.esm` |
| Imperial Knight Cape | faction Tailor/Liverywright embassy expert | `6aa04:Hothtrooper44_ArmorCompilation.esp` |
| Imperial Light Armor | faction Smith/Platewright embassy advanced | `13ed9:Skyrim.esm` |
| Imperial Light Boots | faction Smith/Platewright embassy advanced | `13ed7:Skyrim.esm` |
| Imperial Light Bracers | faction Smith/Platewright embassy advanced | `13eda:Skyrim.esm` |
| Imperial Light Helmet | faction Smith/Platewright embassy advanced | `13edb:Skyrim.esm` |
| Imperial Light Shield | faction Smith/Platewright embassy advanced | `13ab2:Skyrim.esm` |
| Imperial Soldier's Armor | faction Smith/Platewright embassy advanced | `136d5:Skyrim.esm` |
| Justiciar Arrow | faction Woodworker/Woodwright remnant advanced | `4d72:Immersive Weapons.esp` |
| Justiciar Changdao | faction Smith/Edgewright remnant expert | `1dc3:Immersive Weapons.esp` |
| Justiciar Knife | faction Smith/Edgewright remnant expert | `1dbf:Immersive Weapons.esp` |
| Justiciar Saber | faction Smith/Edgewright remnant expert | `1859:Immersive Weapons.esp` |
| Penitus Oculatus Armor | faction Smith/Platewright embassy advanced | `d3ea0:Skyrim.esm` |
| Penitus Oculatus Boots | faction Smith/Platewright embassy advanced | `d3ea7:Skyrim.esm` |
| Penitus Oculatus Bracers | faction Smith/Platewright embassy advanced | `d3eab:Skyrim.esm` |
| Penitus Oculatus Helmet | faction Smith/Platewright embassy advanced | `d3eaa:Skyrim.esm` |
| Thalmor Boots | faction Tailor/Haberdasher remnant novice | `65bac:Skyrim.esm` |
| Thalmor Gloves | faction Tailor/Haberdasher remnant novice | `65bb3:Skyrim.esm` |
| Thalmor Hood | faction Tailor/Haberdasher remnant novice | `821:MoreCraftableEquipment.esp` |
| Thalmor Robes | faction Tailor/Liverywright remnant novice | `81f:MoreCraftableEquipment.esp` |

## Race work

38 items. Only the named race may make these. An item also made by another source shows it.

| Item | Sources | Id |
| --- | --- | --- |
| Alik'r Hood | race Tailor/Haberdasher redguard novice | `7bc1a:Skyrim.esm` |
| Bosmer Boots | race Smith/Platewright woodelf expert | `238e0:Hothtrooper44_ArmorCompilation.esp` |
| Bosmer Bracers | race Smith/Platewright woodelf expert | `238eb:Hothtrooper44_ArmorCompilation.esp` |
| Bosmer Cuirass | race Smith/Platewright woodelf expert | `238e2:Hothtrooper44_ArmorCompilation.esp` |
| Bosmer Engraved Shoulder Cape | race Tailor/Haberdasher woodelf master | `238e9:Hothtrooper44_ArmorCompilation.esp` |
| Bosmer Full Cape | race Tailor/Haberdasher woodelf master | `238ea:Hothtrooper44_ArmorCompilation.esp` |
| Bosmer Helmet | race Smith/Platewright woodelf expert | `238f1:Hothtrooper44_ArmorCompilation.esp` |
| Bosmer Mask | race Tailor/Haberdasher woodelf expert | `238fb:Hothtrooper44_ArmorCompilation.esp` |
| Bosmer Shoulder Cape | race Tailor/Haberdasher woodelf master | `238fc:Hothtrooper44_ArmorCompilation.esp` |
| Dark Alik'r Hood | race Tailor/Haberdasher redguard novice | `e0dd2:Skyrim.esm` |
| Dark Hammerfell Garb | race Tailor/Haberdasher redguard novice | `e0dd0:Skyrim.esm` |
| Dark Redguard Boots | race Tailor/Haberdasher redguard novice | `e0dd4:Skyrim.esm` |
| Dunmer Hooded Outfit | race Tailor/Haberdasher darkelf novice | `82c:MoreCraftableEquipment.esp` |
| Dunmer Hooded Outfit | race Tailor/Haberdasher darkelf novice | `82d:MoreCraftableEquipment.esp` |
| Dunmer Hooded Outfit | race Tailor/Haberdasher darkelf novice | `831:MoreCraftableEquipment.esp` |
| Dunmer Outfit | race Tailor/Haberdasher darkelf novice | `82f:MoreCraftableEquipment.esp` |
| Dunmer Outfit | race Tailor/Haberdasher darkelf novice | `830:MoreCraftableEquipment.esp` |
| Dunmer Outfit | race Tailor/Haberdasher darkelf novice | `832:MoreCraftableEquipment.esp` |
| Dunmer Shoes | race Tailor/Haberdasher darkelf novice | `3705a:Dragonborn.esm` |
| Hammerfell Garb | race Tailor/Haberdasher redguard novice | `7bc19:Skyrim.esm` |
| Redguard Boots | race Tailor/Haberdasher redguard novice | `7bc15:Skyrim.esm` |
| Redguard Knight Cape | race Tailor/Haberdasher redguard advanced | `f74c:Hothtrooper44_ArmorCompilation.esp` |
| Riekling Belted Tunic | race Tailor/Haberdasher riekling novice; company; start (chargen.json rieklingShift) | `bfd98:Playable Rieklings.esp` |
| Riekling Bone Club | race Smith/Edgewright riekling novice; company | `9b8a4:Playable Rieklings.esp` |
| Riekling Chief Fur Iron Armour | race Smith/Platewright riekling novice; company | `19f71:Playable Rieklings.esp` |
| Riekling Chief Helmet | race Smith/Platewright riekling novice; company | `19f6a:Playable Rieklings.esp` |
| Riekling Footwraps | race Tailor/Haberdasher riekling novice; company; start (chargen.json rieklingShift) | `bfdb1:Playable Rieklings.esp` |
| Riekling Fur Armour | race Smith/Platewright riekling novice; company | `19f5f:Playable Rieklings.esp` |
| Riekling Fur Boots | race Smith/Platewright riekling novice; company | `19f60:Playable Rieklings.esp` |
| Riekling Fur Cloak | race Tailor/Haberdasher riekling novice; company | `23a09:Playable Rieklings.esp` |
| Riekling Fur Gauntlets | race Smith/Platewright riekling novice; company | `19f61:Playable Rieklings.esp` |
| Riekling Horned Helmet | race Smith/Platewright riekling novice; company | `19f62:Playable Rieklings.esp` |
| Riekling Spear | race Woodworker/Woodwright riekling advanced; company | `17720:Dragonborn.esm` |
| Riekling Spear | race Woodworker/Woodwright riekling advanced; company | `1b935:Dragonborn.esm` |
| Riekling Spear | race Woodworker/Woodwright riekling advanced; company | `3c337:Dragonborn.esm` |
| Telvanni Robes | race Tailor/Liverywright darkelf novice | `834:MoreCraftableEquipment.esp` |
| Telvanni Robes | race Tailor/Liverywright darkelf novice | `9f3:MoreCraftableEquipment.esp` |
| Telvanni Shoes | race Tailor/Haberdasher darkelf novice | `835:MoreCraftableEquipment.esp` |

## Company wares

13 items. The Free Skyrim Trading Company's wares.

| Item | Sources | Id |
| --- | --- | --- |
| Riekling Belted Tunic | race Tailor/Haberdasher riekling novice; company; start (chargen.json rieklingShift) | `bfd98:Playable Rieklings.esp` |
| Riekling Bone Club | race Smith/Edgewright riekling novice; company | `9b8a4:Playable Rieklings.esp` |
| Riekling Chief Fur Iron Armour | race Smith/Platewright riekling novice; company | `19f71:Playable Rieklings.esp` |
| Riekling Chief Helmet | race Smith/Platewright riekling novice; company | `19f6a:Playable Rieklings.esp` |
| Riekling Footwraps | race Tailor/Haberdasher riekling novice; company; start (chargen.json rieklingShift) | `bfdb1:Playable Rieklings.esp` |
| Riekling Fur Armour | race Smith/Platewright riekling novice; company | `19f5f:Playable Rieklings.esp` |
| Riekling Fur Boots | race Smith/Platewright riekling novice; company | `19f60:Playable Rieklings.esp` |
| Riekling Fur Cloak | race Tailor/Haberdasher riekling novice; company | `23a09:Playable Rieklings.esp` |
| Riekling Fur Gauntlets | race Smith/Platewright riekling novice; company | `19f61:Playable Rieklings.esp` |
| Riekling Horned Helmet | race Smith/Platewright riekling novice; company | `19f62:Playable Rieklings.esp` |
| Riekling Spear | race Woodworker/Woodwright riekling advanced; company | `17720:Dragonborn.esm` |
| Riekling Spear | race Woodworker/Woodwright riekling advanced; company | `1b935:Dragonborn.esm` |
| Riekling Spear | race Woodworker/Woodwright riekling advanced; company | `3c337:Dragonborn.esm` |

## Handed to a new character

11 items. The first clothes, a class's tool and a farmer's first seeds, with whatever else makes them.

| Item | Sources | Id |
| --- | --- | --- |
| Belted Tunic | crafted Tailor/Haberdasher novice; start (chargen.json shift) | `1be1a:Skyrim.esm` |
| Boots | crafted Tailor/Haberdasher novice; start (chargen.json shift) | `1be1b:Skyrim.esm` |
| Cabbage | gathered farmer novice (harvests.json crops); found tier 1 (dungeon goods); start farmer (game/gamemode.js startingCrops) | `64b3f:Skyrim.esm` |
| Crude Fishing Pole | crafted Woodworker/Woodwright novice; start fisher (game/gamemode.js TOOLS) | `15498:Thornswood-Content.esp` |
| Leek | gathered farmer novice (harvests.json crops); found tier 1 (dungeon goods); start farmer (game/gamemode.js startingCrops) | `669a5:Skyrim.esm` |
| Pickaxe | crafted Smith/Edgewright novice; start miner (game/gamemode.js TOOLS) | `e3c16:Skyrim.esm` |
| Potato | gathered farmer novice (harvests.json crops); found tier 1 (dungeon goods); start farmer (game/gamemode.js startingCrops) | `64b41:Skyrim.esm` |
| Riekling Belted Tunic | race Tailor/Haberdasher riekling novice; company; start (chargen.json rieklingShift) | `bfd98:Playable Rieklings.esp` |
| Riekling Footwraps | race Tailor/Haberdasher riekling novice; company; start (chargen.json rieklingShift) | `bfdb1:Playable Rieklings.esp` |
| Shovel | crafted Smith/Edgewright novice; start farmer (game/gamemode.js TOOLS) | `f5d05:Skyrim.esm` |
| Woodcutter's Axe | crafted Smith/Edgewright novice; start woodworker (game/gamemode.js TOOLS) | `2f2f4:Skyrim.esm` |
