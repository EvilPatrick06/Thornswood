# Cut items

What leaves the open craft book. Nothing in `game/data/recipes.json` is deleted by this page. Every reference listed here can be put back for an event, or if the cut was wrong, without hunting the plugin for the form id.

The same rows are in [cut-items.json](cut-items.json), one object per reference.

An item in this file is not found in the world and not made at a public bench. The test server is wiped, so what is already sitting in chests does not have to be stripped by hand. After that, a thing that is no longer made simply stops appearing.

## How a row is marked

| Mark | Meaning |
| --- | --- |
| cut | Not found and not made. Held here. |
| embassy | Not found in Skyrim. The embassy roll may craft it. |
| thalmor | Not found. Someone on the Thalmor remnant roll may craft it. |

Counts in this file: cut 1509, embassy 15, thalmor 9. Rows this pass left in the open book, or on a lock that is not a cut: 596.

## Rules that built the lists

One suit per material. Where a material has a heavy set and a light set, both stay. A suit is body, head, hands, and feet. Shields are fewer than suits: one shield named Shield, not the buckler and not the painted variants.

One weapon per type per metal. The type is sword, greatsword, dagger, war axe, battleaxe, mace, warhammer, or bow. The name that stays is the plain one, such as Iron Sword. Cutlass, katana, scimitar, and the other shapes of that same metal are cut. Which of those shapes should be company wares instead of a cut has not been named, so they are all held here until one is.

One set per culture. Bosmer keeps the plain set, not the engraved or the reinforced. Stormcloak keeps the plain cuirass and helmet. Forsworn keeps one set, a sword and an axe. Dawnguard keeps one light set and one heavy set. Tribunal keeps the black heavy set and the black light set. Wolf keeps the wolf set and the Wolf Sword. The other colors and the officer and heroic variants are cut.

Named uniques, Chillrend and Dawnbreaker and the rest, are cut. They are not found either. A piece named for a Daedric prince is cut with the Daedric.

The kiln stays: poor charcoal, the tool handle, charcoal, briquette, and coke. The woodcutter's axe, the shovel, the fishing poles, and the drum, flute and lute stay.

Dragonbone, dragonscale, dragonplate, dragonsteel, Alduin scale, Daedric, and Aetherium are cut, including the ingots.

Glass, ebony, and stalhrim stay craftable. They are the scarce metals. Stalhrim keeps both the heavy set and the light set.

Cloaks and capes stay, all of them. A second plugin row of the same cloak is a duplicate and is cut. Clothing, robes, hats, shoes, gloves and aprons stay with the tailor. They are not extra armour. That includes the five colors of Tribunal unarmored clothes. Those are garments, not a second suit of plate.

Arrows and bolts stay when they are the plain stack for a metal that stays. Exploding bolts are cut. A woodwright still makes ammunition. That is the job.

Cook dishes stay. A second row of the same dish, the two-portion copy, is cut.

Staves stay only when the spell the menu asks for is in the college book. The others are cut. The Aetherial Staff is cut with the Aetherium.

Riekling gear that is a copy of a human suit is cut. What stays is one light fur set, one chief set, a spear, and a bone club. Those stay race locked, and they are company wares: the company may haul them, and a riekling may make them.

Imperial and Penitus pieces are not in the open book. One heavy set and one light set, plus Penitus pieces, are embassy craft. The knight, legate, and captain variants are cut.

Thalmor robes and Justiciar weapons are not found. The remnant roll may craft them.

Smelting and tanning are not anybody's work. One row per ingot and one row for leather stay, and they belong to the smith halves. Duplicate ingot rows are cut. House walls, roofs, and furniture in the anybody list are not in this file yet.

Tempering rows, the grindstone and the armour table, are not in this file. Repair is the kit system on [Durability](durability.md), and whether those old temper recipes leave the menu is still a question.

## Riekling pieces that stay

Race locked, and company wares. Not cut.

- Riekling Fur Armour
- Riekling Fur Boots
- Riekling Fur Gauntlets
- Riekling Fur Cloak
- Riekling Horned Helmet
- Riekling Chief Fur Iron Armour
- Riekling Chief Helmet
- Riekling Spear
- Riekling Bone Club

## Embassy craft

Not found on a body, in a chest, or at a public forge. The embassy roll is who may make them.

15 references.

| Item | Id | Half | Why |
| --- | --- | --- | --- |
| Imperial Boots | `dc9f5:Skyrim.esm` | Platewright | Empire gear. Not found in Skyrim. Only the embassy roll may craft it. |
| Imperial Bracers | `dc9f7:Skyrim.esm` | Platewright | Empire gear. Not found in Skyrim. Only the embassy roll may craft it. |
| Imperial Heavy Shield | `dc9f9:Skyrim.esm` | Platewright | Empire gear. Not found in Skyrim. Only the embassy roll may craft it. |
| Imperial Helmet | `dc9f8:Skyrim.esm` | Platewright | Empire gear. Not found in Skyrim. Only the embassy roll may craft it. |
| Imperial Knight Cape | `6aa09:Hothtrooper44_ArmorCompilation.esp` | Liverywright | Empire gear. Not found in Skyrim. Only the embassy roll may craft it. |
| Imperial Light Armor | `9cf:Update.esm` | Platewright | Empire gear. Not found in Skyrim. Only the embassy roll may craft it. |
| Imperial Light Boots | `9d0:Update.esm` | Platewright | Empire gear. Not found in Skyrim. Only the embassy roll may craft it. |
| Imperial Light Bracers | `9d1:Update.esm` | Platewright | Empire gear. Not found in Skyrim. Only the embassy roll may craft it. |
| Imperial Light Helmet | `9d2:Update.esm` | Platewright | Empire gear. Not found in Skyrim. Only the embassy roll may craft it. |
| Imperial Light Shield | `9d3:Update.esm` | Platewright | Empire gear. Not found in Skyrim. Only the embassy roll may craft it. |
| Imperial Soldier's Armor | `dc9f6:Skyrim.esm` | Platewright | Empire gear. Not found in Skyrim. Only the embassy roll may craft it. |
| Penitus Oculatus Armor | `8d1:MoreCraftableEquipment.esp` | Platewright | Empire gear. Not found in Skyrim. Only the embassy roll may craft it. |
| Penitus Oculatus Boots | `8d0:MoreCraftableEquipment.esp` | Platewright | Empire gear. Not found in Skyrim. Only the embassy roll may craft it. |
| Penitus Oculatus Bracers | `8d2:MoreCraftableEquipment.esp` | Platewright | Empire gear. Not found in Skyrim. Only the embassy roll may craft it. |
| Penitus Oculatus Helmet | `8d3:MoreCraftableEquipment.esp` | Platewright | Empire gear. Not found in Skyrim. Only the embassy roll may craft it. |

## Thalmor remnant craft

Not found. A person on the remnant roll may make them. Wearing them is still the hostile marker.

9 references.

| Item | Id | Half | Why |
| --- | --- | --- | --- |
| Hooded Thalmor Robes | `9ce:MoreCraftableEquipment.esp` | Liverywright | Thalmor or Justiciar. Not found in the world. Only someone on the remnant roll may craft it. |
| Justiciar Arrow | `490d86:Immersive Weapons.esp` | Woodwright | Thalmor or Justiciar. Not found in the world. Only someone on the remnant roll may craft it. |
| Justiciar Changdao | `491dc4:Immersive Weapons.esp` | Edgewright | Thalmor or Justiciar. Not found in the world. Only someone on the remnant roll may craft it. |
| Justiciar Knife | `491dc0:Immersive Weapons.esp` | Edgewright | Thalmor or Justiciar. Not found in the world. Only someone on the remnant roll may craft it. |
| Justiciar Saber | `94185a:Immersive Weapons.esp` | Edgewright | Thalmor or Justiciar. Not found in the world. Only someone on the remnant roll may craft it. |
| Thalmor Boots | `9ca:MoreCraftableEquipment.esp` | Haberdasher | Thalmor or Justiciar. Not found in the world. Only someone on the remnant roll may craft it. |
| Thalmor Gloves | `9cb:MoreCraftableEquipment.esp` | Haberdasher | Thalmor or Justiciar. Not found in the world. Only someone on the remnant roll may craft it. |
| Thalmor Hood | `9cc:MoreCraftableEquipment.esp` | Haberdasher | Thalmor or Justiciar. Not found in the world. Only someone on the remnant roll may craft it. |
| Thalmor Robes | `9cd:MoreCraftableEquipment.esp` | Liverywright | Thalmor or Justiciar. Not found in the world. Only someone on the remnant roll may craft it. |

## Cut

Not found and not made. Held here so the reference can come back.

1509 references.

| Item | Id | Half | Why |
| --- | --- | --- | --- |
| Dragon Bone | `2731d:Immersive Weapons.esp` |  | Dragon or Daedric material. Not smelted. Not found and not made. |
| Dragon Bone | `2731e:Immersive Weapons.esp` |  | Dragon or Daedric material. Not smelted. Not found and not made. |
| Dragon Bone | `2731f:Immersive Weapons.esp` |  | Dragon or Daedric material. Not smelted. Not found and not made. |
| Dragon Bone | `27320:Immersive Weapons.esp` |  | Dragon or Daedric material. Not smelted. Not found and not made. |
| Dragon Bone | `27321:Immersive Weapons.esp` |  | Dragon or Daedric material. Not smelted. Not found and not made. |
| Dragon Bone | `27322:Immersive Weapons.esp` |  | Dragon or Daedric material. Not smelted. Not found and not made. |
| Dragon Bone | `27323:Immersive Weapons.esp` |  | Dragon or Daedric material. Not smelted. Not found and not made. |
| Dragon Bone | `27324:Immersive Weapons.esp` |  | Dragon or Daedric material. Not smelted. Not found and not made. |
| Dragon Bone | `27325:Immersive Weapons.esp` |  | Dragon or Daedric material. Not smelted. Not found and not made. |
| Dragon Bone | `44847:Immersive Weapons.esp` |  | Dragon or Daedric material. Not smelted. Not found and not made. |
| Dragon Bone | `802:IA CBBE Patch.esp` |  | Dragon or Daedric material. Not smelted. Not found and not made. |
| Aetherial Shield | `5761:Dawnguard.esm` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Aetherial Staff | `5762:Dawnguard.esm` | Bladebinder | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Alduin Scale Armor | `2328e:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Alduin Scale Boots | `2328d:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Alduin Scale Gauntlets | `2328f:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Alduin Scale Helmet | `23290:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Antique Daedric Sword | `c7470e:Immersive Weapons.esp` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Azura's Moon | `3bbfa:Immersive Weapons.esp` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Daedric Armor | `dd993:Skyrim.esm` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Daedric Arrow | `3987:Dawnguard.esm` | Woodwright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Daedric Battle Staff | `c74707:Immersive Weapons.esp` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Daedric Battleaxe | `db8bf:Skyrim.esm` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Daedric Boots | `dd992:Skyrim.esm` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Daedric Bow | `108cf7:Skyrim.esm` | Woodwright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Daedric Buckler | `21470:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Daedric Crescent | `216db:Immersive Weapons.esp` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Daedric Dagger | `db8c0:Skyrim.esm` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Daedric Double Axe | `441024:Immersive Weapons.esp` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Daedric Gauntlets | `dd994:Skyrim.esm` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Daedric Greatsword | `db8c1:Skyrim.esm` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Daedric Halberd | `216b7:Immersive Weapons.esp` | Woodwright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Daedric Helmet | `dd995:Skyrim.esm` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Daedric Katana | `c74720:Immersive Weapons.esp` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Daedric Longsword | `c74701:Immersive Weapons.esp` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Daedric Lord Boots | `2393d:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Daedric Lord Cuirass | `2393e:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Daedric Lord Gauntlets | `2393f:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Daedric Mace | `db8c2:Skyrim.esm` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Daedric Nodachi | `c7471f:Immersive Weapons.esp` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Daedric Quarterstaff | `a438:Immersive Weapons.esp` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Daedric Shield | `dd996:Skyrim.esm` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Daedric Sword | `db8c3:Skyrim.esm` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Daedric Tanto | `c74722:Immersive Weapons.esp` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Daedric Wakizashi | `c74721:Immersive Weapons.esp` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Daedric War Axe | `db8c4:Skyrim.esm` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Daedric Warhammer | `db8c5:Skyrim.esm` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonbone Arrow | `6928:Dawnguard.esm` | Woodwright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonbone Battleaxe | `19823:Dawnguard.esm` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonbone Bow | `19824:Dawnguard.esm` | Woodwright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonbone Crown | `854:MoreCraftableEquipment.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonbone Dagger | `19825:Dawnguard.esm` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonbone Ebonsteel Boots | `21ff5:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonbone Ebonsteel Breastplate | `21ff7:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonbone Ebonsteel Classic Helm | `22001:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonbone Ebonsteel Classic Veiled Helm | `22002:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonbone Ebonsteel Claw Helm | `22003:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonbone Ebonsteel Claw Veiled Helm | `22004:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonbone Ebonsteel Gauntlets | `21ff9:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonbone Ebonsteel Grand Helm | `21ffd:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonbone Ebonsteel Grand Veiled Helm | `21ffe:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonbone Ebonsteel Hood | `22005:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonbone Ebonsteel Horned Helm | `21fff:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonbone Ebonsteel Horned Veiled Helm | `22000:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonbone Ebonsteel Shield | `22006:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonbone Ebonsteel Stout Helm | `21ffb:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonbone Ebonsteel Stout Veiled Helm | `21ffc:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonbone Greatsword | `19826:Dawnguard.esm` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonbone Mace | `19827:Dawnguard.esm` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonbone Sword | `19828:Dawnguard.esm` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonbone War Axe | `19829:Dawnguard.esm` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonbone Warhammer | `1982a:Dawnguard.esm` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonhide Buckler | `21471:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonhide Heavy Boots | `4f3d:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonhide Heavy Gauntlets | `4f3f:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonhide Heavy Hood | `4f41:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonhide Heavy Robe | `4f3e:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonhide Light Boots | `232a1:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonhide Light Gauntlets | `232a2:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonhide Light Hood | `232a3:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonhide Light Robe | `232a4:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonhide Unarmored Boots | `37311:Hothtrooper44_ArmorCompilation.esp` | Haberdasher | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonhide Unarmored Gauntlets | `37310:Hothtrooper44_ArmorCompilation.esp` | Haberdasher | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonhide Unarmored Hood | `3730f:Hothtrooper44_ArmorCompilation.esp` | Haberdasher | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonhide Unarmored Robe | `3730b:Hothtrooper44_ArmorCompilation.esp` | Liverywright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonplate Armor | `dd98e:Skyrim.esm` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonplate Boots | `dd98d:Skyrim.esm` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonplate Gauntlets | `dd98f:Skyrim.esm` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonplate Helmet | `dd990:Skyrim.esm` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonplate Shield | `dd991:Skyrim.esm` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonscale Armor | `dca14:Skyrim.esm` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonscale Boots | `dca13:Skyrim.esm` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonscale Ebonsteel Boots | `21ff6:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonscale Ebonsteel Classic Helm | `84f20:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonscale Ebonsteel Classic Veiled Helm | `84f3a:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonscale Ebonsteel Claw Helm | `84f3b:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonscale Ebonsteel Claw Veiled Helm | `84f3c:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonscale Ebonsteel Cuirass | `21ff8:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonscale Ebonsteel Gloves | `21ffa:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonscale Ebonsteel Grand Helm | `84f3d:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonscale Ebonsteel Grand Veiled Helm | `84f3e:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonscale Ebonsteel Hood | `84f43:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonscale Ebonsteel Horned Helm | `84f3f:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonscale Ebonsteel Horned Veiled Helm | `84f40:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonscale Ebonsteel Shield | `84f44:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonscale Ebonsteel Stout Helm | `84f41:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonscale Ebonsteel Stout Veiled Helm | `84f42:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonscale Gauntlets | `dca15:Skyrim.esm` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonscale Helmet | `dca16:Skyrim.esm` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonscale Shield | `dca17:Skyrim.esm` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonsteel Anlace | `910:Immersive Weapons.esp` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonsteel Arrow | `6908:Immersive Weapons.esp` | Woodwright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonsteel Battleaxe | `af29:Immersive Weapons.esp` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonsteel Bow | `4915:Immersive Weapons.esp` | Woodwright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonsteel Dagger | `911:Immersive Weapons.esp` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonsteel Greatsword | `a455:Immersive Weapons.esp` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonsteel Katana | `8963:Immersive Weapons.esp` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonsteel Mace | `998d:Immersive Weapons.esp` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonsteel Nodachi | `7914:Immersive Weapons.esp` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonsteel Saber | `904:Immersive Weapons.esp` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonsteel Scythe | `b48f:Immersive Weapons.esp` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonsteel Sword | `83fc:Immersive Weapons.esp` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonsteel Tanto | `906:Immersive Weapons.esp` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonsteel War Axe | `1909:Immersive Weapons.esp` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Dragonsteel Warhammer | `2901:Immersive Weapons.esp` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Great Daedric Crescent | `216d9:Immersive Weapons.esp` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Mace of Molag Bal | `478de:Immersive Weapons.esp` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Masque of Clavicus Vile | `37664:ZIA_Complete Pack.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Masque of Clavicus Vile | `37665:ZIA_Complete Pack.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Masque of Clavicus Vile | `37666:ZIA_Complete Pack.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Masque of Clavicus Vile | `37667:ZIA_Complete Pack.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Masque of Clavicus Vile | `37668:ZIA_Complete Pack.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Masque of Clavicus Vile | `37669:ZIA_Complete Pack.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Masque of Clavicus Vile | `3766a:ZIA_Complete Pack.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Masque of Clavicus Vile | `3766b:ZIA_Complete Pack.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Masque of Clavicus Vile | `3766c:ZIA_Complete Pack.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Masque of Clavicus Vile | `3766d:ZIA_Complete Pack.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Masque of Clavicus Vile | `3766e:ZIA_Complete Pack.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Masque of Clavicus Vile | `3766f:ZIA_Complete Pack.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Mehrunes' Razor | `478e1:Immersive Weapons.esp` | Edgewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Ritual Armor of Boethiah | `21f93:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Ritual Boots of Boethiah | `21f92:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Ritual Gauntlets of Boethiah | `21f94:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Ritual Helm of Boethiah | `21f95:Hothtrooper44_ArmorCompilation.esp` | Platewright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Ritual Mask of Boethiah | `21f96:Hothtrooper44_ArmorCompilation.esp` | Haberdasher | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Ritual Shroud of Boethiah | `21f97:Hothtrooper44_ArmorCompilation.esp` | Haberdasher | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Staff of Daedric Command | `1774d:Dragonborn.esm` | Bladebinder | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Staff of the Daedra | `2a816a:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Staff of the Major Daedra | `2a816b:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Staff of the Minor Daedra | `2a8168:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Vaermina Robes | `9dc:MoreCraftableEquipment.esp` | Liverywright | Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event. |
| Apple Dumpling | `80e:Gourmet.esp` | Confectioner | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Apple Dumpling | `994:Gourmet.esp` | Confectioner | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Apple Dumpling | `995:Gourmet.esp` | Confectioner | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Apple Pie | `820:Gourmet.esp` | Confectioner | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Apple Pie | `996:Gourmet.esp` | Confectioner | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Apple Pie | `997:Gourmet.esp` | Confectioner | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Ash Hopper Stew | `998:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Ash Yam Soup | `99a:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Baked Potatoes | `9c8:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Beef Stew | `99c:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Boar Stew | `99e:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Boiled Creme Treat | `99f:Gourmet.esp` | Confectioner | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Braided Bread | `9a0:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Bread Loaf | `9a1:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Cabbage Potato Soup | `9a2:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Cabbage Soup | `9a3:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Cabbage and Tomato Soup | `9a4:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Carrot Soup | `9a6:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Clam Chowder | `9a8:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Cooked Beef | `99b:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Cooked Boar Meat | `99d:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Cooked Dog | `9a9:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Cooked Skeever | `9ce:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Eidar Cheese Fondue | `814:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Eidar Cheese Fondue | `8b5:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Eidar Cheese Fondue | `9ae:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Eidar Cheese Fondue | `9af:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Eidar Cheese Fondue | `9b0:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Garlic Bread | `a12:HearthFires.esm` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Glowing Mushroom Stew | `9c5:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Goat Cheese Fondue | `8b4:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Goat Cheese Fondue | `9aa:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Goat Cheese Fondue | `9ab:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Goat Cheese Fondue | `9ac:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Goat Cheese Fondue | `f431f:Skyrim.esm` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Goat Roast | `9b1:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Goat Stew | `9b2:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Gourd Soup | `9b3:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Grilled Chicken Breast | `9a7:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Grilled Leeks | `9bb:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Honey Nut Treat | `9b4:Gourmet.esp` | Confectioner | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Horker Loaf | `9b5:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Horker Stew | `9eb:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Horse Haunch | `a09:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Jazbay Crostata | `9b6:Gourmet.esp` | Confectioner | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Jazbay Dumpling | `9b7:Gourmet.esp` | Confectioner | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Jelly Dumpling | `9b8:Gourmet.esp` | Confectioner | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Juniper Berry Crostata | `9b9:Gourmet.esp` | Confectioner | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Juniper Berry Dumpling | `9ba:Gourmet.esp` | Confectioner | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Mammoth Cheese Fondue | `9bc:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Mammoth Steak | `9bd:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Mammoth Stew | `9be:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Mushroom Stew | `9c3:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Pheasant Roast | `9c6:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Pheasant Stew | `9c7:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Potato Bread | `9c9:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Potato Soup | `9ca:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Rabbit Haunch | `9cb:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Rabbit Stew | `9cc:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Roasted Carrots | `9a5:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Roasted Glowing Mushroom | `9c2:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Roasted Mushrooms | `9c0:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Roasted Wild Mushrooms | `9c1:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Roasted Yams | `999:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Salmon Steak | `9cd:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Slaughterfish Steak | `9cf:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Snowberry Crostata | `9d0:Gourmet.esp` | Confectioner | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Snowberry Dumpling | `9d1:Gourmet.esp` | Confectioner | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Steamed Mudcrab Legs | `9bf:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Sweet Roll | `9d2:Gourmet.esp` | Confectioner | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Tomato Soup | `9d3:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Vegetable Soup | `9d4:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Venison Chop | `9d5:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Venison Stew | `9d6:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| Wild Mushroom Stew | `9c4:Gourmet.esp` | Hearthcook | Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back. |
| College of Winterhold Cloak | `816:MoreCraftableEquipment_CloaksandCapes.esp` | Haberdasher | Duplicate row of College of Winterhold Cloak. One row stays. This reference is here if the second copy is wanted back. |
| Dark Brotherhood Cloak | `817:MoreCraftableEquipment_CloaksandCapes.esp` | Liverywright | Duplicate row of Dark Brotherhood Cloak. One row stays. This reference is here if the second copy is wanted back. |
| Dawngaurd Cloak | `815:MoreCraftableEquipment_CloaksandCapes.esp` | Liverywright | Duplicate row of Dawngaurd Cloak. One row stays. This reference is here if the second copy is wanted back. |
| Dawnguard Armor | `864:MoreCraftableEquipment.esp` | Platewright | Duplicate row of Dawnguard Armor. One row stays. This reference is here if the second copy is wanted back. |
| Dawnguard Armor | `865:MoreCraftableEquipment.esp` | Platewright | Duplicate row of Dawnguard Armor. One row stays. This reference is here if the second copy is wanted back. |
| Dawnguard Heavy Armor | `862:MoreCraftableEquipment.esp` | Platewright | Duplicate row of Dawnguard Heavy Armor. One row stays. This reference is here if the second copy is wanted back. |
| Fur Armor | `845:MoreCraftableEquipment.esp` | Platewright | Duplicate row of Fur Armor. One row stays. This reference is here if the second copy is wanted back. |
| Fur Armor | `846:MoreCraftableEquipment.esp` | Platewright | Duplicate row of Fur Armor. One row stays. This reference is here if the second copy is wanted back. |
| Fur Armor | `847:MoreCraftableEquipment.esp` | Platewright | Duplicate row of Fur Armor. One row stays. This reference is here if the second copy is wanted back. |
| Fur Cloak (Black) | `808:MoreCraftableEquipment_CloaksandCapes.esp` | Haberdasher | Duplicate row of Fur Cloak (Black). One row stays. This reference is here if the second copy is wanted back. |
| Fur Cloak (Brown) | `809:MoreCraftableEquipment_CloaksandCapes.esp` | Haberdasher | Duplicate row of Fur Cloak (Brown). One row stays. This reference is here if the second copy is wanted back. |
| Fur Cloak (Snowy Sabre) | `80a:MoreCraftableEquipment_CloaksandCapes.esp` | Haberdasher | Duplicate row of Fur Cloak (Snowy Sabre). One row stays. This reference is here if the second copy is wanted back. |
| Fur Cloak (Vale Sabre) | `80b:MoreCraftableEquipment_CloaksandCapes.esp` | Haberdasher | Duplicate row of Fur Cloak (Vale Sabre). One row stays. This reference is here if the second copy is wanted back. |
| Fur Cloak (White) | `807:MoreCraftableEquipment_CloaksandCapes.esp` | Haberdasher | Duplicate row of Fur Cloak (White). One row stays. This reference is here if the second copy is wanted back. |
| Hjaalmarch Guard Cloak | `80e:MoreCraftableEquipment_CloaksandCapes.esp` | Liverywright | Duplicate row of Hjaalmarch Guard Cloak. One row stays. This reference is here if the second copy is wanted back. |
| Leather Cape | `818:MoreCraftableEquipment_CloaksandCapes.esp` | Haberdasher | Duplicate row of Leather Cape. One row stays. This reference is here if the second copy is wanted back. |
| Linen Cape (Black) | `805:MoreCraftableEquipment_CloaksandCapes.esp` | Haberdasher | Duplicate row of Linen Cape (Black). One row stays. This reference is here if the second copy is wanted back. |
| Linen Cape (Blue) | `801:MoreCraftableEquipment_CloaksandCapes.esp` | Haberdasher | Duplicate row of Linen Cape (Blue). One row stays. This reference is here if the second copy is wanted back. |
| Linen Cape (Green) | `802:MoreCraftableEquipment_CloaksandCapes.esp` | Haberdasher | Duplicate row of Linen Cape (Green). One row stays. This reference is here if the second copy is wanted back. |
| Linen Cape (Purple) | `803:MoreCraftableEquipment_CloaksandCapes.esp` | Haberdasher | Duplicate row of Linen Cape (Purple). One row stays. This reference is here if the second copy is wanted back. |
| Linen Cape (Red) | `800:MoreCraftableEquipment_CloaksandCapes.esp` | Haberdasher | Duplicate row of Linen Cape (Red). One row stays. This reference is here if the second copy is wanted back. |
| Linen Cape (White) | `806:MoreCraftableEquipment_CloaksandCapes.esp` | Haberdasher | Duplicate row of Linen Cape (White). One row stays. This reference is here if the second copy is wanted back. |
| Linen Cape (Yellow) | `804:MoreCraftableEquipment_CloaksandCapes.esp` | Haberdasher | Duplicate row of Linen Cape (Yellow). One row stays. This reference is here if the second copy is wanted back. |
| Markarth Guard Cloak | `80f:MoreCraftableEquipment_CloaksandCapes.esp` | Liverywright | Duplicate row of Markarth Guard Cloak. One row stays. This reference is here if the second copy is wanted back. |
| Pale Guard Cloak | `80c:MoreCraftableEquipment_CloaksandCapes.esp` | Liverywright | Duplicate row of Pale Guard Cloak. One row stays. This reference is here if the second copy is wanted back. |
| Riften Guard Cloak | `810:MoreCraftableEquipment_CloaksandCapes.esp` | Liverywright | Duplicate row of Riften Guard Cloak. One row stays. This reference is here if the second copy is wanted back. |
| Solitude Guard Cloak | `811:MoreCraftableEquipment_CloaksandCapes.esp` | Liverywright | Duplicate row of Solitude Guard Cloak. One row stays. This reference is here if the second copy is wanted back. |
| Steel Armor | `f6f2c:Skyrim.esm` | Platewright | Duplicate row of Steel Armor. One row stays. This reference is here if the second copy is wanted back. |
| Stormcloak Cloak | `813:MoreCraftableEquipment_CloaksandCapes.esp` | Liverywright | Duplicate row of Stormcloak Cloak. One row stays. This reference is here if the second copy is wanted back. |
| Whiterun Guard Cloak | `812:MoreCraftableEquipment_CloaksandCapes.esp` | Liverywright | Duplicate row of Whiterun Guard Cloak. One row stays. This reference is here if the second copy is wanted back. |
| Winterhold Guard Cloak | `814:MoreCraftableEquipment_CloaksandCapes.esp` | Liverywright | Duplicate row of Winterhold Guard Cloak. One row stays. This reference is here if the second copy is wanted back. |
| Corundum Ingot | `26d4d:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Corundum Ingot. One row stays. |
| Corundum Ingot | `272bf:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Corundum Ingot. One row stays. |
| Corundum Ingot | `272cb:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Corundum Ingot. One row stays. |
| Corundum Ingot | `272d6:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Corundum Ingot. One row stays. |
| Corundum Ingot | `272e7:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Corundum Ingot. One row stays. |
| Corundum Ingot | `272f2:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Corundum Ingot. One row stays. |
| Corundum Ingot | `2733c:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Corundum Ingot. One row stays. |
| Corundum Ingot | `2734a:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Corundum Ingot. One row stays. |
| Corundum Ingot | `27358:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Corundum Ingot. One row stays. |
| Corundum Ingot | `3ec84:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Corundum Ingot. One row stays. |
| Dwarven Metal Ingot | `10dd2a:Skyrim.esm` |  | Duplicate smelt or tan row for Dwarven Metal Ingot. One row stays. |
| Dwarven Metal Ingot | `10dd2b:Skyrim.esm` |  | Duplicate smelt or tan row for Dwarven Metal Ingot. One row stays. |
| Dwarven Metal Ingot | `10dd2c:Skyrim.esm` |  | Duplicate smelt or tan row for Dwarven Metal Ingot. One row stays. |
| Dwarven Metal Ingot | `10dd2d:Skyrim.esm` |  | Duplicate smelt or tan row for Dwarven Metal Ingot. One row stays. |
| Dwarven Metal Ingot | `10fbd9:Skyrim.esm` |  | Duplicate smelt or tan row for Dwarven Metal Ingot. One row stays. |
| Dwarven Metal Ingot | `272cd:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Dwarven Metal Ingot. One row stays. |
| Dwarven Metal Ingot | `2730c:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Dwarven Metal Ingot. One row stays. |
| Dwarven Metal Ingot | `2733b:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Dwarven Metal Ingot. One row stays. |
| Dwarven Metal Ingot | `2cef2:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Dwarven Metal Ingot. One row stays. |
| Ebony Ingot | `272b4:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `272ba:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `272bc:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `272bd:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `272c8:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `272cc:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `272ce:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `272d3:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `272d7:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `272dd:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `272de:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `272e6:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `272e8:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `272f9:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `272fb:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `27315:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `27316:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `27317:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `27318:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `27319:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `2731c:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `27326:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `27330:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `27331:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `27335:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `27337:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `27338:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `2733e:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `27340:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `2734d:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `2734e:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `27356:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `2735a:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `2735b:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `2735e:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `2735f:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `2cef5:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `2cef6:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `3ec7e:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `3ec81:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `3ec87:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `3ec88:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `3ec8a:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `42290:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `44dab:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `478d4:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `478dc:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `478e0:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `478e3:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `478e6:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `478e8:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `478ec:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Ebony Ingot | `478ef:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Ebony Ingot. One row stays. |
| Gold Ingot | `2734f:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Gold Ingot. One row stays. |
| Iron Ingot | `18cb0:Dragonborn.esm` |  | Duplicate smelt or tan row for Iron Ingot. One row stays. |
| Iron Ingot | `272c4:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Iron Ingot. One row stays. |
| Iron Ingot | `272c7:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Iron Ingot. One row stays. |
| Iron Ingot | `272d9:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Iron Ingot. One row stays. |
| Iron Ingot | `272e3:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Iron Ingot. One row stays. |
| Iron Ingot | `272e4:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Iron Ingot. One row stays. |
| Iron Ingot | `272eb:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Iron Ingot. One row stays. |
| Iron Ingot | `2732c:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Iron Ingot. One row stays. |
| Iron Ingot | `2734b:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Iron Ingot. One row stays. |
| Iron Ingot | `2b403:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Iron Ingot. One row stays. |
| Iron Ingot | `3ec7c:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Iron Ingot. One row stays. |
| Iron Ingot | `3ec82:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Iron Ingot. One row stays. |
| Iron Ingot | `42d57:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Iron Ingot. One row stays. |
| Leather | `10cc6b:Skyrim.esm` |  | Duplicate smelt or tan row for Leather. One row stays. |
| Leather | `10d159:Skyrim.esm` |  | Duplicate smelt or tan row for Leather. One row stays. |
| Leather | `14636:Dawnguard.esm` |  | Duplicate smelt or tan row for Leather. One row stays. |
| Leather | `14637:Dawnguard.esm` |  | Duplicate smelt or tan row for Leather. One row stays. |
| Leather | `7866b:Skyrim.esm` |  | Duplicate smelt or tan row for Leather. One row stays. |
| Leather | `78b48:Skyrim.esm` |  | Duplicate smelt or tan row for Leather. One row stays. |
| Leather | `78b49:Skyrim.esm` |  | Duplicate smelt or tan row for Leather. One row stays. |
| Leather | `78b54:Skyrim.esm` |  | Duplicate smelt or tan row for Leather. One row stays. |
| Leather | `da0c06:Update.esm` |  | Duplicate smelt or tan row for Leather. One row stays. |
| Leather | `da0c07:Update.esm` |  | Duplicate smelt or tan row for Leather. One row stays. |
| Leather | `da0c09:Update.esm` |  | Duplicate smelt or tan row for Leather. One row stays. |
| Leather | `eb0ac:Skyrim.esm` |  | Duplicate smelt or tan row for Leather. One row stays. |
| Leather | `eb0ad:Skyrim.esm` |  | Duplicate smelt or tan row for Leather. One row stays. |
| Leather | `eb0ae:Skyrim.esm` |  | Duplicate smelt or tan row for Leather. One row stays. |
| Leather | `eb0af:Skyrim.esm` |  | Duplicate smelt or tan row for Leather. One row stays. |
| Leather | `eb0b0:Skyrim.esm` |  | Duplicate smelt or tan row for Leather. One row stays. |
| Leather | `eb0b1:Skyrim.esm` |  | Duplicate smelt or tan row for Leather. One row stays. |
| Leather | `eb0b2:Skyrim.esm` |  | Duplicate smelt or tan row for Leather. One row stays. |
| Orichalcum Ingot | `272cf:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Orichalcum Ingot. One row stays. |
| Orichalcum Ingot | `27313:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Orichalcum Ingot. One row stays. |
| Orichalcum Ingot | `27351:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Orichalcum Ingot. One row stays. |
| Orichalcum Ingot | `27355:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Orichalcum Ingot. One row stays. |
| Orichalcum Ingot | `27360:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Orichalcum Ingot. One row stays. |
| Orichalcum Ingot | `2780f:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Orichalcum Ingot. One row stays. |
| Orichalcum Ingot | `2b405:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Orichalcum Ingot. One row stays. |
| Orichalcum Ingot | `2cef1:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Orichalcum Ingot. One row stays. |
| Orichalcum Ingot | `3ec89:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Orichalcum Ingot. One row stays. |
| Quicksilver Ingot | `272b0:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Quicksilver Ingot. One row stays. |
| Quicksilver Ingot | `272c0:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Quicksilver Ingot. One row stays. |
| Quicksilver Ingot | `272c2:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Quicksilver Ingot. One row stays. |
| Quicksilver Ingot | `272d0:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Quicksilver Ingot. One row stays. |
| Quicksilver Ingot | `272da:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Quicksilver Ingot. One row stays. |
| Quicksilver Ingot | `272ed:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Quicksilver Ingot. One row stays. |
| Quicksilver Ingot | `2730d:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Quicksilver Ingot. One row stays. |
| Quicksilver Ingot | `27310:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Quicksilver Ingot. One row stays. |
| Quicksilver Ingot | `27349:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Quicksilver Ingot. One row stays. |
| Quicksilver Ingot | `27352:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Quicksilver Ingot. One row stays. |
| Quicksilver Ingot | `27361:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Quicksilver Ingot. One row stays. |
| Quicksilver Ingot | `27362:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Quicksilver Ingot. One row stays. |
| Quicksilver Ingot | `27363:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Quicksilver Ingot. One row stays. |
| Quicksilver Ingot | `27364:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Quicksilver Ingot. One row stays. |
| Quicksilver Ingot | `27365:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Quicksilver Ingot. One row stays. |
| Quicksilver Ingot | `27366:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Quicksilver Ingot. One row stays. |
| Quicksilver Ingot | `46dfe:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Quicksilver Ingot. One row stays. |
| Refined Malachite | `272b5:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Malachite. One row stays. |
| Refined Malachite | `272b6:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Malachite. One row stays. |
| Refined Malachite | `272d8:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Malachite. One row stays. |
| Refined Malachite | `272df:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Malachite. One row stays. |
| Refined Malachite | `272ea:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Malachite. One row stays. |
| Refined Malachite | `27300:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Malachite. One row stays. |
| Refined Malachite | `27303:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Malachite. One row stays. |
| Refined Malachite | `27304:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Malachite. One row stays. |
| Refined Malachite | `2730e:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Malachite. One row stays. |
| Refined Malachite | `2730f:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Malachite. One row stays. |
| Refined Malachite | `27314:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Malachite. One row stays. |
| Refined Malachite | `2731a:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Malachite. One row stays. |
| Refined Malachite | `27328:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Malachite. One row stays. |
| Refined Malachite | `27329:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Malachite. One row stays. |
| Refined Malachite | `2732a:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Malachite. One row stays. |
| Refined Malachite | `2732b:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Malachite. One row stays. |
| Refined Malachite | `2732e:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Malachite. One row stays. |
| Refined Malachite | `27339:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Malachite. One row stays. |
| Refined Malachite | `2733f:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Malachite. One row stays. |
| Refined Malachite | `27359:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Malachite. One row stays. |
| Refined Malachite | `2cef4:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Malachite. One row stays. |
| Refined Malachite | `3ec86:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Malachite. One row stays. |
| Refined Malachite | `42292:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Malachite. One row stays. |
| Refined Malachite | `478d6:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Malachite. One row stays. |
| Refined Malachite | `478d9:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Malachite. One row stays. |
| Refined Moonstone | `272be:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Moonstone. One row stays. |
| Refined Moonstone | `272e9:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Moonstone. One row stays. |
| Refined Moonstone | `272f0:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Moonstone. One row stays. |
| Refined Moonstone | `272f1:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Moonstone. One row stays. |
| Refined Moonstone | `272f8:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Moonstone. One row stays. |
| Refined Moonstone | `272fa:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Moonstone. One row stays. |
| Refined Moonstone | `27306:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Moonstone. One row stays. |
| Refined Moonstone | `27309:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Moonstone. One row stays. |
| Refined Moonstone | `2730a:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Moonstone. One row stays. |
| Refined Moonstone | `2730b:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Moonstone. One row stays. |
| Refined Moonstone | `27327:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Moonstone. One row stays. |
| Refined Moonstone | `2733a:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Moonstone. One row stays. |
| Refined Moonstone | `2cef3:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Moonstone. One row stays. |
| Refined Moonstone | `3ec7d:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Moonstone. One row stays. |
| Refined Moonstone | `3ec85:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Moonstone. One row stays. |
| Refined Moonstone | `4228f:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Moonstone. One row stays. |
| Refined Moonstone | `42291:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Moonstone. One row stays. |
| Refined Moonstone | `44848:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Moonstone. One row stays. |
| Refined Moonstone | `46dfd:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Refined Moonstone. One row stays. |
| Silver Ingot | `272c1:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Silver Ingot. One row stays. |
| Silver Ingot | `272c3:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Silver Ingot. One row stays. |
| Silver Ingot | `272ca:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Silver Ingot. One row stays. |
| Silver Ingot | `272d1:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Silver Ingot. One row stays. |
| Silver Ingot | `272d5:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Silver Ingot. One row stays. |
| Silver Ingot | `272db:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Silver Ingot. One row stays. |
| Silver Ingot | `272e0:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Silver Ingot. One row stays. |
| Silver Ingot | `272e1:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Silver Ingot. One row stays. |
| Silver Ingot | `272ee:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Silver Ingot. One row stays. |
| Silver Ingot | `3ec7f:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Silver Ingot. One row stays. |
| Silver Ingot | `3ec83:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Silver Ingot. One row stays. |
| Steel Ingot | `26d4c:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Steel Ingot. One row stays. |
| Steel Ingot | `272b3:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Steel Ingot. One row stays. |
| Steel Ingot | `272b7:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Steel Ingot. One row stays. |
| Steel Ingot | `272b8:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Steel Ingot. One row stays. |
| Steel Ingot | `272bb:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Steel Ingot. One row stays. |
| Steel Ingot | `272c5:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Steel Ingot. One row stays. |
| Steel Ingot | `272c9:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Steel Ingot. One row stays. |
| Steel Ingot | `272d2:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Steel Ingot. One row stays. |
| Steel Ingot | `272d4:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Steel Ingot. One row stays. |
| Steel Ingot | `272dc:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Steel Ingot. One row stays. |
| Steel Ingot | `272e2:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Steel Ingot. One row stays. |
| Steel Ingot | `272e5:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Steel Ingot. One row stays. |
| Steel Ingot | `272ef:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Steel Ingot. One row stays. |
| Steel Ingot | `2732f:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Steel Ingot. One row stays. |
| Steel Ingot | `27332:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Steel Ingot. One row stays. |
| Steel Ingot | `27333:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Steel Ingot. One row stays. |
| Steel Ingot | `27334:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Steel Ingot. One row stays. |
| Steel Ingot | `27341:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Steel Ingot. One row stays. |
| Steel Ingot | `27342:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Steel Ingot. One row stays. |
| Steel Ingot | `27343:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Steel Ingot. One row stays. |
| Steel Ingot | `27344:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Steel Ingot. One row stays. |
| Steel Ingot | `27347:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Steel Ingot. One row stays. |
| Steel Ingot | `27348:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Steel Ingot. One row stays. |
| Steel Ingot | `27350:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Steel Ingot. One row stays. |
| Steel Ingot | `27353:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Steel Ingot. One row stays. |
| Steel Ingot | `27354:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Steel Ingot. One row stays. |
| Steel Ingot | `2735c:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Steel Ingot. One row stays. |
| Steel Ingot | `2735d:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Steel Ingot. One row stays. |
| Steel Ingot | `2b404:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Steel Ingot. One row stays. |
| Steel Ingot | `2cef0:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Steel Ingot. One row stays. |
| Steel Ingot | `3a106:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Steel Ingot. One row stays. |
| Steel Ingot | `3abcd:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Steel Ingot. One row stays. |
| Steel Ingot | `3ec80:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Steel Ingot. One row stays. |
| Steel Ingot | `3ec8b:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Steel Ingot. One row stays. |
| Steel Ingot | `46dff:Immersive Weapons.esp` |  | Duplicate smelt or tan row for Steel Ingot. One row stays. |
| Heroic Imperial Armor | `5a1d:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra Imperial shape beyond one heavy set and one light set. Not found and not made. |
| Heroic Imperial Boots | `5a1c:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra Imperial shape beyond one heavy set and one light set. Not found and not made. |
| Heroic Imperial Bracers | `5a1e:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra Imperial shape beyond one heavy set and one light set. Not found and not made. |
| Heroic Imperial Helmet | `8c651:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra Imperial shape beyond one heavy set and one light set. Not found and not made. |
| Imperial Bow | `8fd:MoreCraftableEquipment.esp` | Woodwright | Extra Imperial shape beyond one heavy set and one light set. Not found and not made. |
| Imperial Bracer | `5939:DIS_Heavy_Legion.esp` | Platewright | Extra Imperial shape beyond one heavy set and one light set. Not found and not made. |
| Imperial Buckler | `21476:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra Imperial shape beyond one heavy set and one light set. Not found and not made. |
| Imperial Captain's Helmet | `8cb:MoreCraftableEquipment.esp` | Platewright | Extra Imperial shape beyond one heavy set and one light set. Not found and not made. |
| Imperial Chainmail | `53c7:DIS_Heavy_Legion.esp` | Platewright | Extra Imperial shape beyond one heavy set and one light set. Not found and not made. |
| Imperial Chainmail | `8c9:MoreCraftableEquipment.esp` | Platewright | Extra Imperial shape beyond one heavy set and one light set. Not found and not made. |
| Imperial Ebony Sword | `c7472d:Immersive Weapons.esp` | Edgewright | Extra Imperial shape beyond one heavy set and one light set. Not found and not made. |
| Imperial Helmet Medium | `5941:DIS_Heavy_Legion.esp` | Platewright | Extra Imperial shape beyond one heavy set and one light set. Not found and not made. |
| Imperial Knight Cuirass | `6aa0a:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra Imperial shape beyond one heavy set and one light set. Not found and not made. |
| Imperial Knight Greaves | `6aa0b:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra Imperial shape beyond one heavy set and one light set. Not found and not made. |
| Imperial Knight Helmet | `6aa0c:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra Imperial shape beyond one heavy set and one light set. Not found and not made. |
| Imperial Knight Vambraces | `6aa0d:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra Imperial shape beyond one heavy set and one light set. Not found and not made. |
| Imperial Legate Helmet | `8ca:MoreCraftableEquipment.esp` | Platewright | Extra Imperial shape beyond one heavy set and one light set. Not found and not made. |
| Imperial Sword | `8fe:MoreCraftableEquipment.esp` | Edgewright | Extra Imperial shape beyond one heavy set and one light set. Not found and not made. |
| Steel Imperial Gauntlets | `f6f2e:Skyrim.esm` | Platewright | Extra Imperial shape beyond one heavy set and one light set. Not found and not made. |
| Riekling Ancient Falmer Cuirass | `bfed2:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Ancient Falmer Cuirass Alternate | `bfed4:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Ancient Nord Armor | `bff08:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Ancient Nord Gauntlets | `bff0a:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Bandages Arms | `bfedb:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Bandages Head | `bfeed:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Bandit Fur Armor Sleeves | `bff32:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Bandit Fur Armour, Sleeveless | `bfe6d:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Bandit Fur Bracers | `bfe63:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Bandit Fur Cloak | `bfe6c:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Bandit Fur Kilt | `bfe6b:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Bandit Fur Kilt&Cloak | `bff34:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Bandit Fur Shoes | `bff38:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Belted Tunic | `bfee5:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Blacksmith's Apron | `bfee0:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Blacksmith's Apron | `bfee1:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Bone Helmet | `9e776:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Bone Helmet | `9e777:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Chef's Tunic | `bfee2:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Chief Fur Armour | `19f96:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Chief Fur Cloak | `659f:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Chief Grassless Helmet | `19f9e:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Claws | `c33c:Playable Rieklings.esp` | Edgewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Cloth Foot Wraps | `19f91:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Cloth Hand Wraps | `19f90:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Clothes | `bfedc:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Clothes | `bfede:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Clothes | `bfee6:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Clothes | `bfee7:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Clothes | `bfee8:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Clothes | `bfee9:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Clothes | `bfeea:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Clothes | `bfeeb:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Clothes | `bfeec:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Clothes | `bfef3:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Clothes | `bfef4:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Curved Horns Skull Grassless Helmet | `19f9c:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Curved Horns Skull Helmet | `19f9b:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Dawnguard Armor | `bfeca:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Dawnguard Armor | `bfecc:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Dawnguard Armor | `bfece:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Dawnguard Armor | `bfed0:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Dawnguard Heavy Armor | `bfec6:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Dawnguard Heavy Armor | `bfec8:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Embellished Robes | `bfef1:Playable Rieklings.esp` | Liverywright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Execution Hood | `bff05:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Execution Hood | `bff06:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Executioner's Hood | `bfee3:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Executioner's Robes | `bfee4:Playable Rieklings.esp` | Liverywright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Falmer Armour | `bfe67:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Falmer Boots | `bfe68:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Falmer Bracers | `bfe69:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Fine Armguards | `bfef0:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Footwraps | `bfefb:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Footwraps Bloody | `bfef8:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Forsworn Armour | `bfe65:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Forsworn Boots | `bfe6a:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Forsworn Bracers | `bfe66:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Fur Iron Armour | `19f95:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling General Carius' Armor | `bfed6:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling General Tullius' Armor | `bfed8:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Gilded Wristguards | `bfeef:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Guard's Armor Falkreath | `bfe6e:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Guard's Armor Hjaalmarch | `bfe70:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Guard's Armor Markarth | `bfe72:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Guard's Armor Pale | `bfe78:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Guard's Armor Riften | `bfe74:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Guard's Armor Solitude | `bfe76:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Guard's Armor Whiterun | `bfe7a:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Guard's Armor Winterhold | `bfe7c:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Hide Armor | `bfe7e:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Hide Bracers | `bfe80:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Hornless Helmet | `19f98:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Imperial Armor | `bfe82:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Imperial Bracers | `bfe84:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Imperial Light Armor | `bfe86:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Imperial Light Bracers | `bfe88:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Imperial Steel Gauntlets | `bfea4:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Imperial Studded Armor | `bfe8a:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Iron Armor | `bfe8e:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Iron Armour | `19f93:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Iron Banded Armor | `bfe8c:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Leather Armor | `bfe90:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Leather Bracers | `bfe92:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling LoinCloth 1 | `19f92:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling LoinCloth 1a | `babbc:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling LoinCloth 2 | `19f94:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling LoinCloth 2a | `babbd:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Long Spear | `40e0a:Playable Rieklings.esp` | Woodwright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Miner's Clothes | `bfef5:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Miner's Clothes | `bfef6:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Moth Priest Blindfold | `bff03:Playable Rieklings.esp` | Liverywright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Moth Priest Sandals | `bff04:Playable Rieklings.esp` | Liverywright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Mourner's Clothes | `bfef7:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Noble Clothes | `bfeee:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Penitus Oculatus Armor | `bfe94:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Penitus Oculatus Bracers | `bfe96:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Prisoner's Cuffs | `bff07:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Ragged Bloody Trousers | `bfefa:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Ragged Robes | `bfedf:Playable Rieklings.esp` | Liverywright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Ragged Trousers | `bfef9:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Refined Tunic | `bfef2:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Roughspun Bloody Tunic | `bfefd:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Roughspun Tunic | `bfefc:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Savior's Hide | `bfebc:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Scaled Armor | `bfe98:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Scaled Bracers | `bfe9c:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Scaled Horn Armor | `bfe9a:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Shoes | `bfedd:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Short Spear | `bab90:Playable Rieklings.esp` | Woodwright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Shrouded Armor | `bfebe:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Shrouded Armor Sleeveless | `bfec4:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Shrouded Cowl | `bfec0:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Shrouded Cowl Maskless | `bfec2:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Shrouded Shoes | `c0374:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Skull Grassless Helmet | `19f9a:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Skull Helmet | `19f99:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Spear Thrower | `bab8c:Playable Rieklings.esp` | Woodwright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Steel Armor | `bfe9e:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Steel Armor | `bfea0:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Steel Nordic Gauntlets | `bfea2:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Stormcloak Cuirass | `bfea8:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Stormcloak Cuirass | `bfeaa:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Stormcloak Officer Armor | `bfea6:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Studded Armor | `bfeac:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Tavern Clothes | `bff00:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Thieves Guild Armor | `bfeae:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Thieves Guild Gauntlets | `bfeb0:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Thieves Guild Gray Armor | `bfeb6:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Thieves Guild Gray Gauntlets | `bfeb8:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Thieves Guild Master's Armor | `bfeb2:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Thieves Guild Master's Gauntlets | `bfeb4:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Tsun's Armor | `bfeba:Playable Rieklings.esp` | Platewright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Ulfric's Bracers | `bfefe:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Vampire Robes | `bff02:Playable Rieklings.esp` | Liverywright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Riekling Wedding Sandals | `bfeff:Playable Rieklings.esp` | Haberdasher | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Spell Tome: Riekling Spear Missle | `bff27:Playable Rieklings.esp` | Woodwright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| Spell Tome: Riekling Spear Spray | `bff26:Playable Rieklings.esp` | Woodwright | Extra Riekling copy of someone else's gear, or a spare piece. Not found and not made. |
| An-Xileel Arrow | `285e:Immersive Weapons.esp` | Woodwright | Extra ammunition or an extra crossbow. Plain arrows, plain bolts, and one crossbow per metal stay. |
| Dariit Arrow | `490d87:Immersive Weapons.esp` | Woodwright | Extra ammunition or an extra crossbow. Plain arrows, plain bolts, and one crossbow per metal stay. |
| Exotic Arrow | `216c7:Immersive Weapons.esp` | Woodwright | Extra ammunition or an extra crossbow. Plain arrows, plain bolts, and one crossbow per metal stay. |
| Exploding Dwarven Bolt of Fire | `f80a:Dawnguard.esm` | Woodwright | Extra ammunition or an extra crossbow. Plain arrows, plain bolts, and one crossbow per metal stay. |
| Exploding Dwarven Bolt of Ice | `f80b:Dawnguard.esm` | Woodwright | Extra ammunition or an extra crossbow. Plain arrows, plain bolts, and one crossbow per metal stay. |
| Exploding Dwarven Bolt of Shock | `f80c:Dawnguard.esm` | Woodwright | Extra ammunition or an extra crossbow. Plain arrows, plain bolts, and one crossbow per metal stay. |
| Exploding Steel Bolt of Fire | `f807:Dawnguard.esm` | Woodwright | Extra ammunition or an extra crossbow. Plain arrows, plain bolts, and one crossbow per metal stay. |
| Exploding Steel Bolt of Ice | `f808:Dawnguard.esm` | Woodwright | Extra ammunition or an extra crossbow. Plain arrows, plain bolts, and one crossbow per metal stay. |
| Exploding Steel Bolt of Shock | `f809:Dawnguard.esm` | Woodwright | Extra ammunition or an extra crossbow. Plain arrows, plain bolts, and one crossbow per metal stay. |
| Forsworn Arrow | `3f1ef:Immersive Weapons.esp` | Woodwright | Extra ammunition or an extra crossbow. Plain arrows, plain bolts, and one crossbow per metal stay. |
| Forsworn Arrow | `8f1:MoreCraftableEquipment.esp` | Woodwright | Extra ammunition or an extra crossbow. Plain arrows, plain bolts, and one crossbow per metal stay. |
| Practice Arrow | `3f1ee:Immersive Weapons.esp` | Woodwright | Extra ammunition or an extra crossbow. Plain arrows, plain bolts, and one crossbow per metal stay. |
| Seeker Arrow | `49232a:Immersive Weapons.esp` | Woodwright | Extra ammunition or an extra crossbow. Plain arrows, plain bolts, and one crossbow per metal stay. |
| Afterslash | `216cc:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Akaviri Samurai Armor | `4f26:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Akaviri Samurai Boots | `4f25:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Akaviri Samurai Gauntlets | `4f27:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Akaviri Samurai Helmet | `4f28:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Aldmeri Axestaff | `3949:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Alik'r Crown Scimitar | `940d78:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Alik'r Hat | `850:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Alik'r Hat(No Hood) | `85d:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Alik'r Nomad Turban | `945:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Alik'r Red Nomad Robes | `944:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Alik'r Red Nomad Turban | `946:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Alinor Saber | `942331:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| An-Xileel War Bow | `d64:Immersive Weapons.esp` | Woodwright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ancient Falmer Boots | `8cc:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ancient Falmer Cuirass | `8ce:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ancient Falmer Gauntlets | `8cf:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Antique Glass Sword | `c74710:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Antique Honed Silver Sword | `216c2:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Antique Iron Sword | `216c0:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Antique Silver Sword | `216c3:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Antique Steel Sword | `c74713:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Apotheus Armor | `b653:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Apotheus Boots | `b654:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Apotheus Gloves | `b652:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Apotheus Helm | `b651:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Apotheus Hood | `48b9:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Aries Ceremonial Greatsword | `90d64:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Arming Sword | `216d0:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Armored Fur Hood | `bc99c:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Armored Fur Hood - Black | `22f8:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Armored Fur Hood - White | `182a:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Armored Fur Mantle | `4e4e:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Armored Fur Mantle - Black | `53b1:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Armored Fur Mantle - White | `53b2:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Armsman's Sword | `285b:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Arrow-Scale Armor | `935:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Assassin Sword | `216d2:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Asuma Trench Knife | `216d4:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ayleid Greatsword | `1dff:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Bado Gedhay Armlets | `90e:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Bado Gedhay Boots | `90f:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Bado Gedhay Helmet | `90d:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Bado Gedhay Robes | `910:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Bado Gedhay Robes(Gray) | `919:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Bado Gedhay Robes(Green) | `91a:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Bado Gedhay Robes(Purple) | `91b:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Bado Gedhay Robes(White) | `91c:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Barbarian Armor | `5a60:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Barbarian Boots | `5a5f:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Barbarian Gauntlets | `5a61:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Barbarian Great Axe | `22c9c:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Barbarian Helmet | `5a62:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Barbarian Hero Armor | `230ee:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Barbarian Hero Boots | `230eb:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Barbarian Hero Bracers | `230ec:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Barbarian Hero Circlet | `230ed:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| BiPolar Blade | `32523:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Black Dragon Ninjato | `216c5:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Black Mammoth Recurve Bow | `4341:Immersive Weapons.esp` | Woodwright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Black Sting | `216cb:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Black Sting Dagger | `216c9:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Black Sting Greatsword | `216ca:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Blade of Woe | `478d2:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Blades Armor | `850:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Blades Boots | `84f:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Blades Gauntlets | `851:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Blades Helmet | `852:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Blades Shield | `853:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Blades Sword | `8f3:MoreCraftableEquipment.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Blue Dragon Ninjato | `216c4:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Boiled Chitin Heavy Armor | `23301:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Boiled Chitin Heavy Boots | `23300:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Boiled Chitin Heavy Gauntlets | `23302:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Boiled Chitin Heavy Helmet | `23303:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Boiled Chitin Heavy Shield | `23304:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Boiled Chitin Light Armor | `84f5d:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Boiled Chitin Light Boots | `84f5c:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Boiled Chitin Light Gauntlets | `84f5e:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Boiled Chitin Light Helmet | `84f5f:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Boiled Chitin Light Shield | `84f60:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Boiled Leather Cuirass | `3383:CommonClothes.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Bonemold Guard Armor | `3d581:Dragonborn.esm` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Bonemold Pauldron Armor | `2b059:Dragonborn.esm` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Bosmer Coif | `238ff:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Bosmer Coif | `25a35:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Bosmer Engraved Boots | `23901:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Bosmer Engraved Bracers | `23904:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Bosmer Engraved Coif | `23902:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Bosmer Engraved Coif | `25a36:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Bosmer Engraved Cuirass | `23903:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Bosmer Engraved Helmet | `23905:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Bosmer Engraved Hood | `23906:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Bosmer Hood | `2390f:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Bosmer Reinforced Boots | `23909:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Bosmer Reinforced Coif | `2390a:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Bosmer Reinforced Coif | `25a37:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Bosmer Reinforced Cuirass | `2390b:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Bosmer Reinforced Gauntlets | `2390c:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Bosmer Reinforced Helmet | `2390d:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Brigand Dwemer Breastplate | `2327e:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Brigand Plate Harness | `23280:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Buckler of Ysgramor | `2147c:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Camoran Saber | `492335:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Captain's Cutlass | `12c6:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Captain's Sword | `3325:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Cavalry Broadsword | `48ba:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ceymallari | `14d64:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Chakram | `446d64:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Chillrend | `478d5:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Colovian Composite Bow | `58d4:Immersive Weapons.esp` | Woodwright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Colovian Dark Composite Bow | `58d0:Immersive Weapons.esp` | Woodwright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Corsair Armor | `84e:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Corsair Hood | `84f:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Crimson Archer Boots | `230fb:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Crimson Archer Cuirass | `230fc:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Crimson Archer Gloves | `230fd:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Crow Greatsword | `22ca3:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Crow Sword | `22ca5:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Crowns' Sword | `84c:YokuWeapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Dawnbreaker | `478d8:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Dawnguard War Axe | `8f4:MoreCraftableEquipment.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Dawnguard Warhammer | `8f5:MoreCraftableEquipment.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Dragon Knight Gauntlets | `230d3:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Dragon Knight Heavy Armor | `230ce:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Dragon Knight Heavy Boots | `230cd:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Dragon Knight Heavy Helmet | `230d4:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Dragon Knight Heavy Shield | `230d5:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Dragon Knight Light Armor | `230cf:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Dragon Knight Light Boots | `85fd7:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Dragon Knight Light Gauntlets | `230d1:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Dragon Knight Light Helmet | `85fd8:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Dragon Knight Light Shield | `85fd9:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Dragon Knight Shield Bearer's Gauntlets | `230d2:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Dragonguard Katana | `25d24:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Dremora Halberd | `216b6:Immersive Weapons.esp` | Woodwright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Duke's Longsword | `7406:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Duke's Sword | `740f:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Dwarven Buckler | `21472:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Dwarven Mage Heavy Boots | `5a2a:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Dwarven Mage Heavy Gauntlets | `5a2c:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Dwarven Mage Heavy Hood | `5a2d:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Dwarven Mage Heavy Robe | `5a2b:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Dwarven Mage Light Boots | `2329d:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Dwarven Mage Light Gauntlets | `2329e:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Dwarven Mage Light Hood | `2329f:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Dwarven Mage Light Robe | `232a0:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Dwarven Quarterstaff | `940c:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Eastern Dwemer Longsword | `216be:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Eastern Dwemer Sword | `216bd:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Eastern Dwemer War Axe | `216bc:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ebon-Scale Armor | `93b:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ebon-Scale Bezubands | `93d:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ebon-Scale Boots | `93c:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ebon-Scale Helmet | `93e:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ebony Battle Staff | `c74708:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ebony Blade | `478db:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ebony Buckler | `21473:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ebony Cutlass | `c7472c:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ebony Dadao | `2414:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ebony Double Axe | `22ca0:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ebony Hammer | `216e6:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ebony Longsword | `c74703:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ebony Mage Heavy Boots | `2394f:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ebony Mage Heavy Gloves | `23951:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ebony Mage Heavy Hood | `23952:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ebony Mage Heavy Robe | `23950:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ebony Mage Light Boots | `23953:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ebony Mage Light Gloves | `23955:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ebony Mage Light Hood | `23956:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ebony Mage Light Robe | `23954:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ebony Quarterstaff | `940a:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ebony Scimitar | `1246:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Einherjar Brigandine Dark Boots | `3e39:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Einherjar Brigandine Dark Cuirass | `3e50:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Einherjar Brigandine Dark Gauntlets | `3e3f:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Einherjar Brigandine Dark Hood | `3e49:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Einherjar Brigandine Light Boots | `3e3a:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Einherjar Brigandine Light Bracers | `3e40:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Einherjar Brigandine Light Cuirass | `3e51:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Einherjar Brigandine Light Hood | `3e4a:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Einherjar Plate Dark Boots | `12e2:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Einherjar Plate Dark Cuirass | `8042:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Einherjar Plate Dark Gauntlets | `8044:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Einherjar Plate Dark Hood | `8043:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Einherjar Plate Light Boots | `8045:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Einherjar Plate Light Cuirass | `12e7:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Einherjar Plate Light Gauntlets | `12e1:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Einherjar Plate Light Hood | `12e5:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Elven Double Axe | `441013:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Elven Gilded Armor | `dca0a:Skyrim.esm` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Elven Great Blade | `22c93:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Elven Great Blood Blade | `22c91:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Elven Great Wings Blade | `22c8f:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Elven Hawk Bow | `9eda:Immersive Weapons.esp` | Woodwright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Elven Quarterstaff | `9408:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Elven Steel Sword | `216bf:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Emerald Gemstone Bow | `2acb:Immersive Weapons.esp` | Woodwright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Enhanced Crossbow | `f80d:Dawnguard.esm` | Woodwright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Enhanced Dwarven Crossbow | `f80f:Dawnguard.esm` | Woodwright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ethereal Axestaff | `394a:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Executioner Double Axe | `441011:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Executioner's Hook | `96d64:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Exotic Bow | `216c6:Immersive Weapons.esp` | Woodwright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Falkreath Armor | `d9d:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Falkreath Blade | `216e3:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Falkreath Boots | `d9a:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Falkreath Crown | `d9c:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Falkreath Gauntlets | `d9e:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Falkreath Guard's Armor | `8b1:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Falkreath Guard's Helmet | `8b9:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Falkreath Guard's Shield | `8c1:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Falkreath Helmet | `d9f:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Falkreath Shield | `da0:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Falkreath Warhammer | `216c8:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Falmer Double Axe | `44014:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Falmer Hardened Armor | `882:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Falmer Hardened Boots | `87d:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Falmer Hardened Gauntlets | `883:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Falmer Hardened Helm | `884:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Fleur De Lys | `216dd:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Forebears' Saber | `84b:YokuWeapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Forsworn Bow | `8fb:MoreCraftableEquipment.esp` | Woodwright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Fur Gauntlets | `8da:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Fur Shoes | `843:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| General Tullius' Armor | `9dd:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Giant Boots | `8ae:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Giant Bracers | `8b0:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Giant Clothes | `8af:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Gildergreen Heavy Aegis | `8b10:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Gildergreen Light Aegis | `85a53:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Glacial Crystal Heavy Armor | `23306:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Glacial Crystal Heavy Boots | `23305:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Glacial Crystal Heavy Gauntlets | `23307:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Glacial Crystal Heavy Helmet | `23308:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Glacial Crystal Heavy Shield | `23309:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Glacial Crystal Light Armor | `84f62:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Glacial Crystal Light Boots | `84f61:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Glacial Crystal Light Gauntlets | `84f63:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Glacial Crystal Light Helmet | `84f64:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Glacial Crystal Light Shield | `84f65:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Glass Battle Staff | `c74709:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Glass Buckler | `21474:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Glass Double Axe | `441016:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Glass Quarterstaff | `a43a:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Glass Scimitar | `c7471e:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Gray-Scale Armor | `929:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Gray-Scale Armor | `943:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Gray-Scale Bezubands | `92b:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Gray-Scale Boots | `92a:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Gray-Scale Helmet | `92c:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Great Riders Blade | `216f2:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Greyblade | `216df:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Guardian's Longsword | `388c:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Guardian's Sword | `4e22:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Guild Master's Armor | `8e5:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Guild Master's Boots | `8e4:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Guild Master's Gloves | `8e6:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Guild Master's Hood | `8e7:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Halendo Armor | `859:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Headsman's Axe | `8f6:MoreCraftableEquipment.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Heavy Jorrvaskr Shield | `590d4:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Heavy Painted Body Shield | `20dd5:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Heavy Painted Kite Shield | `20dd6:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Heavy Painted Round Shield | `20dd8:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Heavy Skyforge Shield | `214a9:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Heavy Spiked Body Shield | `5f8f0:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Heavy Spiked Kite Shield | `5f8f1:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Heavy Spiked Round Shield | `5f8ef:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Heavy Splinted Body Shield | `5f8ed:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Heavy Splinted Kite Shield | `5f8ee:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Heavy Splinted Round Shield | `5f8ea:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Heavy Target Shield | `5f8eb:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Hedge Knight Armor | `da2:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Hedge Knight Boots | `da1:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Hedge Knight Gauntlets | `da3:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Hedge Knight Helmet | `da4:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Hide Buckler | `21475:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Highwayman Mail | `2327f:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Hjaalmarch Guard's Armor | `8b2:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Hjaalmarch Guard's Helmet | `8bb:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Hjaalmarch Guard's Shield | `8c2:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Hollow Blade | `216e1:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Honed Falmer Double Axe | `3abd0:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Honed Nordic War Pick | `3a104:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Honed Silver Battle Staff | `c7470a:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Honed Silver Battleaxe | `c74715:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Honed Silver Longsword | `c74704:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Honed Silver Scimitar | `c7471b:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Honed Silver War Axe | `c74714:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Honed Steel Nordic Spear | `3abcf:Immersive Weapons.esp` | Woodwright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Hot Blood | `22c8d:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Housecarl's Greatsword | `216e8:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Hunter Armor | `3888:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Hunter Boots | `3886:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Hunter Bracers | `3889:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Improved Bonemold Armor | `3ab29:Dragonborn.esm` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Improved Bonemold Boots | `3ab28:Dragonborn.esm` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Improved Bonemold Gauntlets | `3ab2a:Dragonborn.esm` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Improved Bonemold Helmet | `3ab2b:Dragonborn.esm` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Improved Bonemold Shield | `3ab2c:Dragonborn.esm` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Iron Buckler | `21477:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Iron Club | `c74719:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Iron Cutlass | `c74717:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Iron Double Axe | `441017:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Iron Hunter's Spear | `22f0:Immersive Weapons.esp` | Woodwright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Iron Katana | `c74728:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Iron Nodachi | `c74727:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Iron Scimitar | `c7471d:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Iron Tanto | `c7472a:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Iron Wakizashi | `c74729:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Karliah's Armor | `8e1:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Karliah's Boots | `8e0:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Karliah's Gloves | `8e2:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Karliah's Hood | `8e3:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Knight's Broadsword | `21700:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Knight's Claymore | `21701:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Kumakumi Armor | `8c6:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Kumakumi Helmet | `884:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Leather Doublet | `3388:CommonClothes.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Leather Doublet | `3389:CommonClothes.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Leather Doublet | `338a:CommonClothes.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Lifida Armor | `88c:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Light Jorrvaskr Shield | `5d7a7:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Light Mercenary Shield | `94f:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Light Painted Body Shield | `20dd7:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Light Painted Kite Shield | `20ddc:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Light Painted Round Shield | `20dd9:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Light Skyforge Shield | `214a8:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Light Spiked Body Shield | `5f8f7:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Light Spiked Kite Shield | `5f8f3:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Light Spiked Round Shield | `5f8f6:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Light Splinted Body Shield | `5f8f5:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Light Splinted Kite Shield | `5f8f2:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Light Splinted Round Shield | `5f8f4:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Light Target Shield | `5f8ec:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Mahayi Armor | `851:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Mahayi Armor(NoCoat) | `f19:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Mahayi Bezubands | `89a:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Mahayi Boots | `89b:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Mahayi Helmet | `852:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Mail Tunic | `3385:CommonClothes.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Mail and Hide Armor | `1d5bb:CommonClothes.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Mail and Jacket | `3387:CommonClothes.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Mail and Surcoat | `3386:CommonClothes.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Mantle of the Silver Hand | `2854b:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Mantle of the Silver Hand | `2854c:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Markarth Guard's Armor | `8b3:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Markarth Guard's Helmet | `8bd:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Markarth Guard's Shield | `8c3:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Memnos Shield | `950:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Mercenary Armor | `5a0d:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Mercenary Boots | `5a0c:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Mercenary Cutlass | `849:YokuWeapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Mercenary Gauntlets | `5a0e:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Mighty Steel Greatsword | `a1113:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Mirror Armor | `921:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Mirror Bezubands | `923:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Mirror Boots | `922:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Mirror Helmet | `924:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Morag Tong Armor | `871:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Morag Tong Boots | `870:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Morag Tong Bracers | `872:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Morag Tong Hood | `873:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Nightingale Blade | `478e4:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Nightingale Bow | `478e7:Immersive Weapons.esp` | Woodwright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Noble Claymore | `96101c:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Noble Sword | `96101d:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Nord Heavy Spectacle Helmet | `3ed1:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Nord Hero Axestaff | `394b:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Nord Hero Battleaxe | `f46c8:Skyrim.esm` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Nord Hero Bow | `108cfd:Skyrim.esm` | Woodwright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Nord Hero Double Axe | `441025:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Nord Hero Greatsword | `f46c9:Skyrim.esm` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Nord Hero Sword | `f46ca:Skyrim.esm` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Nord Hero War Axe | `f46cb:Skyrim.esm` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Nord Light Spectacle Helmet | `3ed7:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Nord Mail Hauberk | `3ecd:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Nord Mail Heavy Boots | `3ecc:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Nord Mail Heavy Bracers | `3ece:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Nord Mail Heavy Coif | `3ecf:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Nord Mail Light Boots | `3ed2:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Nord Mail Light Bracers | `3ed4:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Nord Mail Light Helmet | `3ed5:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Nord Mail Shirt | `3ed3:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Nordic Dwemer Blade | `490d76:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Nordic Dwemer Shield | `214a2:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Nordic Ebony Light Shield | `214a3:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Nordic Ebony Shield | `214a4:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Nordic Moonstone Shield | `214a5:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Nordic Orichalcum Light Shield | `214a6:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Nordic Orichalcum Shield | `214a7:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Nordic Scrimshaw Bow | `2ac2:Immersive Weapons.esp` | Woodwright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Nordic War Pick | `23771:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Oiled Mail Hauberk | `338b:CommonClothes.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Oiled Mail and Hide Armor | `1d5bc:CommonClothes.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Oiled Mail and Jacket | `338c:CommonClothes.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Old Armor | `5ec5:DIS_Heavy_Legion.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Old Boots | `5ec3:DIS_Heavy_Legion.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Old Captain Helmet | `6eff:DIS_Heavy_Legion.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Old Gauntlets | `5ec8:DIS_Heavy_Legion.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Old Helmet | `5eca:DIS_Heavy_Legion.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Old Helmet | `6f00:DIS_Heavy_Legion.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Old Shield | `5ecc:DIS_Heavy_Legion.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Orcish Buckler | `21478:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Orcish Crippler Spear | `2857:Immersive Weapons.esp` | Woodwright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Orcish Longsword | `c74705:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Orcish Masked Helmet | `21f7f:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Orcish Quarterstaff | `9406:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Orcish Saber | `20d64:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Orgnum's Dagger | `33d66:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ornate Alik'r Scimitar | `940d79:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ornate Khajiit Bow | `b473:Immersive Weapons.esp` | Woodwright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ornate Maul | `216ea:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Orsimer Cheiftan Bow | `ca05:Immersive Weapons.esp` | Woodwright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Outrunner Armor | `853:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Outrunner Boots | `8a1:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Outrunner Cannons | `8a0:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Outrunner Helm | `854:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Padded Fur Hood | `bc99b:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Padded Fur Hood - Black | `22ff:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Padded Fur Hood - White | `1d91:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Padded Fur Mantle | `53b4:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Padded Fur Mantle - Black | `53b6:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Padded Fur Mantle - White | `53b8:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Painted Hide Shield | `62fff:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Painted Iron Shield | `63000:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Painted Spiked Targe | `62ffe:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Paladin Armor | `ab6d:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Paladin Barbut | `22fa:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Paladin Boots | `22f7:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Paladin Gauntlets | `22f9:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Paladin Great Helm | `3dee:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Paladin Shield | `22fb:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Pale Guard's Armor | `8b6:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Pale Guard's Helmet | `8bc:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Pale Guard's Shield | `8c4:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Pelt of Karhu | `2ba5f3:WindhelmSSE.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Phoenix Ninjato | `79d64:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Pokeblade | `216ee:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Primitive Nord Heavy Boots | `5a45:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Primitive Nord Heavy Cuirass | `5a46:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Primitive Nord Heavy Gauntlets | `5a47:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Primitive Nord Heavy Helmet | `5a48:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Primitive Nord Light Boots | `5a49:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Primitive Nord Light Cuirass | `5a4a:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Primitive Nord Light Gauntlets | `5a4b:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Primitive Nord Light Hood | `5a4c:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Quarterstaff | `58c1:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ra-Gada Armor | `855:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ra-Gada Bezubands | `857:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ra-Gada Boots | `858:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ra-Gada Helmet | `856:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ranger Armor | `5a73:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ranger Boots | `5a72:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ranger Bracers | `5a74:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ranger Hood | `5a75:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Redguard Knight Heavy Boots | `da5:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Redguard Knight Heavy Coif | `da7:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Redguard Knight Heavy Gauntlets | `da9:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Redguard Knight Heavy Mail | `dad:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Redguard Knight Light Boots | `da6:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Redguard Knight Light Coif | `da8:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Redguard Knight Light Gauntlets | `daa:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Redguard Knight Light Mail | `dae:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Regent's Longsword | `12c8:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Riders Blade | `216f0:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Riften Guard's Armor | `8b4:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Riften Guard's Helmet | `8be:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Riften Guard's Shield | `8c5:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ringmail Armor | `2331a:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ringmail Boots | `23319:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ringmail Bracers | `2331b:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ringmail Hood | `2331c:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Robed Iron Armor | `3384:CommonClothes.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Robed Iron Armor | `43e8:CommonClothes.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Ruby Gemstone Bow | `2acc:Immersive Weapons.esp` | Woodwright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Rueful Axe | `478ea:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Sapphire Gemstone Bow | `2aca:Immersive Weapons.esp` | Woodwright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Scimitar | `8ff:MoreCraftableEquipment.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Seadog Armor | `2864:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Seadog Boots | `2863:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Seadog Feathered Tricorne | `2867:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Seadog Gauntlets | `2865:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Seadog Tricorne | `2866:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Seeker Changdao | `940d7c:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Seeker Knife | `940d7d:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Seeker Saber | `9412f4:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Sentinelese Nimcha | `84a:YokuWeapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Serpent-Scale Armor | `931:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Serpent-Scale Bezubands | `933:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Serpent-Scale Boots | `932:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Serpent-Scale Helmet | `934:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Shaman Light Boots | `230b4:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Shaman Light Cap | `230b2:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Shaman Light Gloves | `230b3:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Shaman Light Robe | `230b1:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Shellbug Helmet | `145c2:Dawnguard.esm` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Shield of Sithis | `2147d:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Shield of Ysgramor | `2147f:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Shiv | `9ff:MoreCraftableEquipment.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Shrouded Armor | `85a:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Shrouded Boots | `859:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Shrouded Gloves | `85c:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Shrouded Masked Cowl | `85e:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Shrouded Short-Sleeved Armor | `85b:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Silver Battle Staff | `c74735:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Silver Hawk Bow | `b9d9:Immersive Weapons.esp` | Woodwright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Silver Katana | `c7473a:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Silver Longsword | `c74734:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Silver Nodachi | `c74739:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Silver Scimitar | `c74738:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Silver Tanto | `c7473c:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Silver Wakizashi | `c7473b:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Sithis Buckler | `21479:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Sithis's Blade | `272fc:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Sithis's Razor | `272fd:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Sixth House Bell Hammer | `38b75:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Skaal Boots | `95e:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Skaal Coat | `95f:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Skaal Gloves | `960:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Skaal Hat | `961:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Skull Double Axe | `441015:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Snow Bear Armor | `2331e:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Snow Bear Boots | `2331d:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Snow Bear Bracers | `2331f:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Snow Bear Helmet | `23320:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Snow Bear Shield | `23321:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Soldier's Broadsword | `48bb:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Solitude Guard's Armor | `8b5:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Solitude Guard's Helmet | `8ba:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Solitude Guard's Shield | `8c6:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Sorrow Daito | `1d9a:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Sorrow Katana | `6bf7:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Sorrow Tanto | `4360:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Spearblade | `216f8:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Spellbinder Crimson Armor | `d176:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Spellbinder Crimson Boots | `d175:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Spellbinder Crimson Gauntlets | `d177:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Spellbinder Crimson Helmet | `d178:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Spellbinder Runic Armor | `d17e:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Spellbinder Runic Boots | `d17d:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Spellbinder Runic Gauntlets | `d17f:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Spellbinder Runic Helmet | `d180:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Splitter | `216fb:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Springsteel Bow | `2abe:Immersive Weapons.esp` | Woodwright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Steel Battle Staff | `c7470b:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Steel Buckler | `2147a:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Steel Club | `c74718:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Steel Cuffed Boots | `dd974:Skyrim.esm` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Steel Cutlass | `c74716:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Steel Horned Helmet | `f6f30:Skyrim.esm` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Steel Katana | `c74724:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Steel Longsword | `c74706:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Steel Nodachi | `c74723:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Steel Nordic Gauntlets | `dd976:Skyrim.esm` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Steel Nordic Spear | `1828:Immersive Weapons.esp` | Woodwright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Steel Quarterstaff | `791a:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Steel Scimitar | `c7471c:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Steel Tanto | `c74726:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Steel Wakizashi | `c74725:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Steel War Pick | `216ec:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Stone Mace | `84d:YokuWeapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Stone Raid Shield | `85a:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Stormlord Boots | `6a9f4:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Stormlord Cuirass | `6a9f5:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Stormlord Gauntlets | `6a9f6:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Stormlord Helmet | `6a9f7:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Stros M'Kai Scimitar | `94289e:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Studded Armor | `dc9f4:Skyrim.esm` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tapered Wooden Battle Staff | `c7470c:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tawagiz Armor | `8d2:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tawagiz Helmet | `8d3:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Thieves Guild Armor | `8dd:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Thieves Guild Boots | `8dc:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Thieves Guild Cowl | `8e8:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Thieves Guild Gloves | `8de:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Thieves Guild Gray Boots | `8e9:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Thieves Guild Gray Cowl | `8ec:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Thieves Guild Gray Gloves | `8eb:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Thieves Guild Gray Sleeveless Armor | `8ea:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Thieves Guild Hood | `8df:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Thresher Maul | `557d64:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tombstone Ceremonial Greatsword | `9d68:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Heavy Boots Blue | `23191:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Heavy Boots Green | `23192:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Heavy Boots Red | `23193:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Heavy Boots White | `23194:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Heavy Gloves Blue | `23196:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Heavy Gloves Green | `23197:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Heavy Gloves Red | `23198:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Heavy Gloves White | `23199:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Heavy Hood Blue | `2319b:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Heavy Hood Green | `2319c:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Heavy Hood Red | `2319d:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Heavy Hood White | `2319e:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Heavy Mantle Black | `231a4:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Heavy Mantle Blue | `231a5:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Heavy Mantle Green | `231a6:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Heavy Mantle Red | `231a7:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Heavy Mantle White | `231a8:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Heavy Robe Blue | `231a0:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Heavy Robe Green | `231a1:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Heavy Robe Red | `231a2:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Heavy Robe White | `231a3:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Light Boots Blue | `231aa:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Light Boots Green | `231ab:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Light Boots Red | `231ac:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Light Boots White | `231ad:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Light Gloves Blue | `231af:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Light Gloves Green | `231b0:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Light Gloves Red | `231b1:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Light Gloves White | `231b2:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Light Hood Blue | `231b4:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Light Hood Green | `231b5:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Light Hood Red | `231b6:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Light Hood White | `231b7:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Light Mantle Black | `231bd:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Light Mantle Blue | `231be:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Light Mantle Green | `231bf:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Light Mantle Red | `231c0:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Light Mantle White | `231c1:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Light Robe Blue | `231b9:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Light Robe Green | `231ba:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Light Robe Red | `231bb:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tribunal Light Robe White | `231bc:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Trident Blade | `216fd:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Trollsbane Heavy Armor | `2309a:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Trollsbane Heavy Boots | `23095:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Trollsbane Heavy Gauntlets | `23098:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Trollsbane Heavy Headdress | `23097:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Trollsbane Heavy Helmet | `23099:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Trollsbane Heavy Mask | `23096:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Trollsbane Light Armor | `23091:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Trollsbane Light Boots | `2308f:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Trollsbane Light Bracers | `23090:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Trollsbane Light Headdress | `23092:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Trollsbane Light Helmet | `23094:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Trollsbane Light Mask | `23093:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tsun's Armor | `8ee:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tsun's Boots | `8ed:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Tsun's Bracers | `8ef:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Vagabond Crimson Armor | `db2:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Vagabond Crimson Boots | `daf:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Vagabond Crimson Gauntlets | `db5:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Vagabond Dusk Armor | `db4:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Vagabond Dusk Boots | `db1:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Vagabond Dusk Gauntlets | `db7:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Vagabond Helmet | `db8:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Vagabond Leather Armor | `db3:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Vagabond Leather Boots | `db0:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Vagabond Leather Bracers | `db6:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Valenwood War Bow | `2ad2:Immersive Weapons.esp` | Woodwright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Vampire Armor | `86a:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Vampire Armor | `86b:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Vampire Armor | `86c:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Vampire Boots | `86e:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Vampire Gauntlets | `86f:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Vampire Royal Armor | `86d:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Vanguard Plate Armor | `dbc:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Vanguard Plate Boots | `dbb:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Vanguard Plate Gauntlets | `dbd:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Vanguard Plate Helmet | `dbe:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Vanguard Plate Helmet Closed | `dbf:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Viking Double Axe | `441012:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Volendrung | `478ed:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Vvardenfell Glass Armor | `23323:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Vvardenfell Glass Boots | `23322:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Vvardenfell Glass Gauntlets | `23324:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Vvardenfell Glass Helmet | `23325:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Vvardenfell Glass Shield | `23326:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Wabba Jackhammer | `394f:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Wabba Jaxe | `3950:Immersive Weapons.esp` | Woodwright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Warchief Heavy Battlecrown | `dc0:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Warchief Heavy Bulwark | `dc2:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Warchief Heavy Grips | `dc6:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Warchief Heavy Headdress | `dc8:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Warchief Heavy Stompers | `dca:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Warchief Light Battlecrown | `dc1:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Warchief Light Bulwark | `dc3:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Warchief Light Grips | `dc7:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Warchief Light Headdress | `dc9:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Warchief Light Stompers | `dcb:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Warchief's Might | `3953:Immersive Weapons.esp` | Woodwright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| White Mammoth Recurve Bow | `4e8b:Immersive Weapons.esp` | Woodwright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Whiterun Guard's Armor | `8b7:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Whiterun Guard's Helmet | `8bf:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Whiterun Guard's Shield | `8c7:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Wicked Dagger | `216b9:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Wicked Scimitar | `216ba:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Wild Hunt Heavy Boots | `23910:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Wild Hunt Heavy Cuirass | `23912:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Wild Hunt Heavy Gauntlets | `23913:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Wild Hunt Heavy Helm | `23911:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Wild Hunt Light Boots | `23914:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Wild Hunt Light Cuirass | `23915:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Wild Hunt Light Gauntlets | `23916:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Wild Hunt Light Hood | `23917:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Windhelm Guard's Shield | `9ee:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Winterhold Battlemage Buckler | `2147b:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Winterhold Battlemage Shield | `2147e:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Winterhold Guard's Armor | `8b8:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Winterhold Guard's Helmet | `8c0:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Winterhold Guard's Shield | `8c8:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Witchplate Cuirass | `c695:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Witchplate Gauntlets | `c697:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Witchplate Greaves | `c696:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Witchplate Hood | `c698:Hothtrooper44_ArmorCompilation.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Wolf Claymore | `701009:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Wolf Dadao | `84100b:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Wolf Daito | `961015:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Wolf Katana | `961016:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Wolf Scimitar | `7700c:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Wooden Battle Staff | `c7470d:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Wooden Club | `c7471a:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Worn Shrouded Cowl | `85d:MoreCraftableEquipment.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Wraith Scythe | `216b8:Immersive Weapons.esp` | Edgewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Yokudan Brave-Helm | `94d:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Yokudan Lion-Robes | `94b:YokuWeapons.esp` | Platewright | Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made. |
| Minor Staff of the Sun | `bae2f:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (DLC1SunFire). Not found and not made. |
| Staff of Corrosion | `2a8164:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Alt_Baleful3_Spell_DamageEquipment). Not found and not made. |
| Grand Staff of Corrosion | `2a8166:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Alt_Baleful4_Spell_DireDamageEquipment). Not found and not made. |
| Staff of Vulnerability | `2a8165:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Alt_Breach3_Spell_WeaknessToElements). Not found and not made. |
| Grand Staff of Vulnerability | `2a8167:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Alt_Breach4_Spell_DireWeaknessToElements). Not found and not made. |
| Staff of Horsemanship | `2a8163:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Alt_BuffOther2_Spell_HasteMount). Not found and not made. |
| Staff of Magelight | `17762:Dragonborn.esm` | Bladebinder | Staff whose spell is not in the college book (ODN_Alt_Light2_Spell_Magelight). Not found and not made. |
| Staff of Paralysis | `17763:Dragonborn.esm` | Bladebinder | Staff whose spell is not in the college book (ODN_Alt_Paralyze4_Spell_Paralyze). Not found and not made. |
| Staff of the Flame Atronach | `1774f:Dragonborn.esm` | Bladebinder | Staff whose spell is not in the college book (ODN_Con_Atronach2_Spell_ConjureFlameAtronach). Not found and not made. |
| Staff of the Frost Atronach | `17750:Dragonborn.esm` | Bladebinder | Staff whose spell is not in the college book (ODN_Con_Atronach3_Spell_ConjureFrostAtronach). Not found and not made. |
| Staff of the Storm Atronach | `17751:Dragonborn.esm` | Bladebinder | Staff whose spell is not in the college book (ODN_Con_Atronach4_Spell_ConjureStormAtronach). Not found and not made. |
| Staff of Banishing | `1774a:Dragonborn.esm` | Bladebinder | Staff whose spell is not in the college book (ODN_Con_Banish3_Spell_BanishDaedra). Not found and not made. |
| Staff of Expulsion | `17754:Dragonborn.esm` | Bladebinder | Staff whose spell is not in the college book (ODN_Con_Banish4_Spell_ExpelDaedra). Not found and not made. |
| Staff of the Familiar | `1774e:Dragonborn.esm` | Bladebinder | Staff whose spell is not in the college book (ODN_Con_Familiar1_Spell_ConjureFamiliar). Not found and not made. |
| Staff of the Feline Familiar | `2a8169:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Con_Familiar3_Spell_ConjureFelineFamiliar). Not found and not made. |
| Staff of the Ursine Familiar | `2a816c:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Con_Familiar4_Spell_ConjureUrsineFamiliar). Not found and not made. |
| Staff of Lesser Reanimation | `17764:Dragonborn.esm` | Bladebinder | Staff whose spell is not in the college book (ODN_Con_Reanimate1_Spell). Not found and not made. |
| Staff of Reanimation | `17766:Dragonborn.esm` | Bladebinder | Staff whose spell is not in the college book (ODN_Con_Reanimate2_Spell). Not found and not made. |
| Staff of Greater Reanimation | `17769:Dragonborn.esm` | Bladebinder | Staff whose spell is not in the college book (ODN_Con_Reanimate3_Spell). Not found and not made. |
| Staff of Dread Zombies | `17753:Dragonborn.esm` | Bladebinder | Staff whose spell is not in the college book (ODN_Con_Reanimate4_Spell). Not found and not made. |
| Staff of the Ancestors | `d4350:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Con_Undead3_Spell_ConjureGloomWraith). Not found and not made. |
| Staff of Mourning | `2a816d:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Con_Undead4_Spell_ConjureDreadShade). Not found and not made. |
| Staff of Taldam's Scorcher | `d1e78:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Des_Fire2_Spell_TaldamsScorcher). Not found and not made. |
| Staff of Fireballs | `17756:Dragonborn.esm` | Bladebinder | Staff whose spell is not in the college book (ODN_Des_Fire3_Spell_Fireball). Not found and not made. |
| Staff of Firehand | `2a8170:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Des_Fire3_Spell_Firehand). Not found and not made. |
| Staff of Flame Darts | `2a8171:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Des_Fire3_Spell_FlameDarts). Not found and not made. |
| Staff of Fireblooms | `d1e7d:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Des_Fire4_Spell_Firebloom). Not found and not made. |
| Staff of the Flame Wall | `17770:Dragonborn.esm` | Bladebinder | Staff whose spell is not in the college book (ODN_Des_Fire4_Spell_WallOfFlames). Not found and not made. |
| Staff of Wildfire | `2a8176:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Des_Fire4_Spell_Wildfire). Not found and not made. |
| Staff of Arctic Blast | `2a816e:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Des_Frost2_Spell_ArcticBlast). Not found and not made. |
| Staff of Frosthand | `2a8172:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Des_Frost3_Spell_Frosthand). Not found and not made. |
| Staff of Ice Shards | `2a8173:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Des_Frost3_Spell_IceShards). Not found and not made. |
| Staff of Arctic Frost | `2a8177:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Des_Frost4_Spell_ArcticFrost). Not found and not made. |
| Staff of Frostblooms | `2a8178:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Des_Frost4_Spell_Frostbloom). Not found and not made. |
| Staff of the Frost Wall | `17771:Dragonborn.esm` | Bladebinder | Staff whose spell is not in the college book (ODN_Des_Frost4_Spell_WallOfFrost). Not found and not made. |
| Staff of Lightning Grasp | `2a816f:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Des_Shock2_Spell_LightningGrasp). Not found and not made. |
| Staff of Chain Lightning | `1774c:Dragonborn.esm` | Bladebinder | Staff whose spell is not in the college book (ODN_Des_Shock3_Spell_ChainLightning). Not found and not made. |
| Staff of Charged Storms | `2a8174:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Des_Shock3_Spell_ChargedStorm). Not found and not made. |
| Staff of Stormhand | `2a8175:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Des_Shock3_Spell_Stormhand). Not found and not made. |
| Staff of Shockblooms | `2a8179:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Des_Shock4_Spell_Shockbloom). Not found and not made. |
| Staff of Thundering Grasp | `2a817a:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Des_Shock4_Spell_ThunderingGrasp). Not found and not made. |
| Staff of the Storm Wall | `17772:Dragonborn.esm` | Bladebinder | Staff whose spell is not in the college book (ODN_Des_Shock4_Spell_WallOfStorms). Not found and not made. |
| Staff of Hush | `2c16a7:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Ill_Antimage2_Spell_Hush). Not found and not made. |
| Staff of Mute | `2a817e:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Ill_Antimage3_Spell_Mute). Not found and not made. |
| Staff of Purge Magic | `2a8185:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Ill_Antimage4_Spell_PurgeMagic). Not found and not made. |
| Staff of Wizard Rend | `2a8181:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Ill_Antimage4_Spell_WizardRend). Not found and not made. |
| Staff of Calm | `1774b:Dragonborn.esm` | Bladebinder | Staff whose spell is not in the college book (ODN_Ill_Calm2_Spell_Calm). Not found and not made. |
| Staff of Soothe | `17b5e1:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Ill_Calm3_Spell_Soothe). Not found and not made. |
| Staff of Command | `2a817c:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Ill_Command2_Spell_Command). Not found and not made. |
| Staff of Subjugation | `17b5e2:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Ill_Command3_Spell_Subjugate). Not found and not made. |
| Staff of Domination | `2a8186:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Ill_Command4_Spell_Dominate). Not found and not made. |
| Staff of Fear | `17755:Dragonborn.esm` | Bladebinder | Staff whose spell is not in the college book (ODN_Ill_Fear2_Spell_Fear). Not found and not made. |
| Staff of Panic | `17b5e3:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Ill_Fear3_Spell_Panic). Not found and not made. |
| Staff of Vanquishment | `1776a:Dragonborn.esm` | Bladebinder | Staff whose spell is not in the college book (ODN_Ill_Fear4_Spell_Rout). Not found and not made. |
| Staff of Fury | `1775b:Dragonborn.esm` | Bladebinder | Staff whose spell is not in the college book (ODN_Ill_Fury1_Spell_Fury). Not found and not made. |
| Staff of Frenzy | `17759:Dragonborn.esm` | Bladebinder | Staff whose spell is not in the college book (ODN_Ill_Fury3_Spell_Frenzy). Not found and not made. |
| Staff of Rage | `17b5e5:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Ill_Fury4_Spell_Rage). Not found and not made. |
| Staff of Courage | `17752:Dragonborn.esm` | Bladebinder | Staff whose spell is not in the college book (ODN_Ill_Rally1_Spell_Courage). Not found and not made. |
| Staff of Inspiration | `17765:Dragonborn.esm` | Bladebinder | Staff whose spell is not in the college book (ODN_Ill_Rally3_Spell_Rally). Not found and not made. |
| Staff of Bravery | `17b5e4:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Ill_Rally4_Spell_Bravery). Not found and not made. |
| Staff of Crying Eyes | `2a817b:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Ill_Shadow1_Spell_CryingEye). Not found and not made. |
| Staff of Illusions | `2a817d:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Ill_Simulacrum2_Spell_Simulacrum). Not found and not made. |
| Grand Staff of Illusions | `2a817f:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Ill_Simulacrum3_Spell_GreaterSimulacrum). Not found and not made. |
| Staff of the Shadow Legion | `2a8187:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Ill_Simulacrum4_Spell_ShadowLegion). Not found and not made. |
| Staff of the Damned | `2a8180:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Ill_TempDamage3_Spell_DiscordantWail). Not found and not made. |
| Grand Staff of the Damned | `2a8188:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Ill_TempDamage4_Spell_Dirge). Not found and not made. |
| Staff of the Healing Hand | `1775c:Dragonborn.esm` | Bladebinder | Staff whose spell is not in the college book (ODN_Res_HealOther2_Spell). Not found and not made. |
| Staff of Mending | `1775d:Dragonborn.esm` | Bladebinder | Staff whose spell is not in the college book (ODN_Res_HealOther3_Spell). Not found and not made. |
| Staff of Disintegration | `2a8189:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Res_Necro3_Spell_DestroyLiving). Not found and not made. |
| Staff of Vipers | `2a818a:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Res_Poison2_Spell_Viperbolt). Not found and not made. |
| Greater Staff of Vipers | `17767:Dragonborn.esm` | Bladebinder | Staff whose spell is not in the college book (ODN_Res_Poison3_Spell_BlackHand). Not found and not made. |
| Grand Staff of Vipers | `17768:Dragonborn.esm` | Bladebinder | Staff whose spell is not in the college book (ODN_Res_Poison4_Spell_ToxicCloud). Not found and not made. |
| Staff of the Sun | `bae30:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Res_Sun3_Spell_VampiresBane). Not found and not made. |
| Greater Staff of the Sun | `bae31:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Res_Sun4_Spell_Sunstorm). Not found and not made. |
| Staff of Tears | `2a818b:Odin - Skyrim Magic Overhaul.esp` | Bladebinder | Staff whose spell is not in the college book (ODN_Res_Tap4_Spell_Enervate). Not found and not made. |
| Minor Staff of Turning | `1776f:Dragonborn.esm` | Bladebinder | Staff whose spell is not in the college book (TurnLesserUndead). Not found and not made. |
| Staff of Perilous Paths | `d1e98:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Alt_CrowdControl2_Spell_PerilousPath). Not found and not made. |
| Staff of Withering | `d1e69:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Alt_CrowdControl2_Spell_Wither). Not found and not made. |
| Staff of Imprisonment | `d1e8f:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Alt_CrowdControl3_Spell_TharnsPrison). Not found and not made. |
| Staff of Undermining | `d1e97:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Alt_CrowdControl3_Spell_Undermine). Not found and not made. |
| Staff of Entombing | `d1e6a:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Alt_CrowdControl4_Spell_Entomb). Not found and not made. |
| Staff of Skyfall | `d1e8e:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Alt_Telekinesis2_Spell_DropZone). Not found and not made. |
| Staff of Lockblasting | `d1e6b:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Alt_Unlock4_Spell_DetonateLock). Not found and not made. |
| Staff of Corpse Explosion | `d1e9b:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Con_Corpse3_Spell_CorpseExplosion). Not found and not made. |
| Staff of Atronach Marks | `d1e99:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Con_Curse2_Spell_AtronachMark). Not found and not made. |
| Staff of Monarch Mark | `161624:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Con_Curse4_Spell_MonarchMark). Not found and not made. |
| Staff of the Dremora Churl | `d1e6c:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Con_Dremora2_Spell_ConjureDremoraChurl_NPC). Not found and not made. |
| Staff of the Dremora Pit Fighter | `d1e6e:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Con_Dremora3_Spell_ConjureDremoraPitFighter_NPC). Not found and not made. |
| Staff of the Dremora Champion | `d1e70:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Con_Dremora4_Spell_ConjureDremoraChampion_NPC). Not found and not made. |
| Staff of the Dremora Honor Guard | `d1e71:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Con_Dremora4_Spell_ConjureDremoraHonorGuard_NPC). Not found and not made. |
| Staff of the Herne | `d1e72:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Con_Dremora4_Spell_ConjureHerne_NPC). Not found and not made. |
| Staff of the Avenging Wraith | `d1e66:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Con_Ghost4_Spell_ConjureAvengingWraith). Not found and not made. |
| Staff of the Oathbound | `d1e9c:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Con_Ghost4_Spell_OathboundGuardian). Not found and not made. |
| Staff of Flesh | `d1e90:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Con_Heal1_Spell_AzureReconstruction). Not found and not made. |
| Staff of the Cat Totem | `d1e6d:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Con_Spirit2_Spell_ConjureCatTotem). Not found and not made. |
| Staff of Ganking | `1a792f:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Con_Summon3_Spell_Gank). Not found and not made. |
| Staff of Summoning Runes | `d1e91:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Con_Summon3_Spell_SummoningRune). Not found and not made. |
| Staff of the Deadeye Captain | `d1e9a:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Con_Undead2_Spell_ConjureDeadeyeCaptain). Not found and not made. |
| Staff of the Xivilai Sorcerer | `d1e6f:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Con_Xivilai3_Spell_ConjureXivilaiSorcerer_NPC). Not found and not made. |
| Staff of the Xivilai Lord | `d1e73:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Con_Xivilai4_Spell_ConjureXivilaiLord_NPC). Not found and not made. |
| Staff of Blaze | `d1e92:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Des_Fire1_Spell_Blaze_NPC). Not found and not made. |
| Staff of Dragon's Teeth | `d1e75:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Des_Fire2_Spell_DragonsTeeth_NPC). Not found and not made. |
| Staff of Bolides | `d1e79:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Des_Fire3_Spell_Bolide_NPC). Not found and not made. |
| Staff of Incendiary Flows | `10c70a:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Des_Fire3_Spell_IncendiaryFlow_NPC). Not found and not made. |
| Staff of Bombardment | `d1e7f:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Des_Fire4_Spell_Bombardment_NPC). Not found and not made. |
| Staff of Scorching Hands | `d1e9d:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Des_Fire4_Spell_ScorchingHands_NPC). Not found and not made. |
| Staff of Hailstones | `d1e68:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Des_Frost1_Spell_Hailstone_NPC). Not found and not made. |
| Staff of the Creeping Cold | `d1e74:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Des_Frost2_Spell_CreepingCold_NPC). Not found and not made. |
| Staff of Fractures | `d1e76:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Des_Frost2_Spell_Fracture_NPC). Not found and not made. |
| Staff of Ice Shivs | `d1e7b:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Des_Frost3_Spell_IceShiv_NPC). Not found and not made. |
| Staff of Ice Prisms | `161633:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Des_Frost4_Spell_IcePrism_NPC). Not found and not made. |
| Staff of Sleet Storms | `d1e7d:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Des_Frost4_Spell_SleetStorm_NPC). Not found and not made. |
| Staff of Crackling | `d1e67:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Des_Shock1_Spell_Crackle_NPC). Not found and not made. |
| Staff of Rift Bolts | `d1e77:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Des_Shock2_Spell_RiftBolt_NPC). Not found and not made. |
| Staff of Thundercracks | `d1e78:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Des_Shock2_Spell_Thundercrack_NPC). Not found and not made. |
| Staff of Electrospheres | `d1e7a:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Des_Shock3_Spell_Electrosphere_NPC). Not found and not made. |
| Staff of Scattershocks | `d1e7c:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Des_Shock3_Spell_Scattershock_NPC). Not found and not made. |
| Staff of the Clouds | `d1e7e:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Des_Shock4_Spell_LightningStrike). Not found and not made. |
| Staff of Silvery Barbs | `1a7933:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Ill_Antimage1_Spell_SilveryBarbs). Not found and not made. |
| Staff of the Silent | `d1e80:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Ill_Antimage2_Spell_CurseOfTheSilent). Not found and not made. |
| Staff of Whispers | `d1e83:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Ill_Command3_Spell_CompellingWhispers). Not found and not made. |
| Staff of Command | `d1e87:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Ill_Command4_Spell_MindControl). Not found and not made. |
| Staff of Shadowbond | `d1e84:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Ill_Invis3_Spell_Shadowbond). Not found and not made. |
| Staff of Hrormir's Misdirection | `1a7937:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Ill_Invis4_Spell_HrormirsMisdirection). Not found and not made. |
| Staff of Pain | `d1e9e:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Ill_PassthroughDmg3_Spell_FigmentOfPain). Not found and not made. |
| Staff of Empathic Agony | `d1e85:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Ill_PassthroughDmg4_Spell_EmpathicAgony). Not found and not made. |
| Staff of Shadows | `d1e93:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Ill_Simulacrum1_Spell_PaleShadow). Not found and not made. |
| Staff of the Seidkona | `10983d:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Ill_Simulacrum4_Spell_Seidstone). Not found and not made. |
| Staff of Illusory Flames | `d1e81:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Ill_TempDmg2_Spell_IllusoryFlames). Not found and not made. |
| Staff of Illusory Pyres | `d1e9f:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Ill_TempDmg3_Spell_IllusoryPyre). Not found and not made. |
| Staff of Mind Vision | `d1e82:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Ill_Vision2_Spell_MindVision). Not found and not made. |
| Staff of Welling Blood | `d1e94:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Res_Blood2_Spell_WellingBlood). Not found and not made. |
| Staff of Necroplagues | `d1ea0:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Res_Disease2_Spell_Necroplague). Not found and not made. |
| Staff of Wilting | `d1e95:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Res_Disease3_Spell_HorridWilting). Not found and not made. |
| Staff of the Lamb | `d1e96:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Res_HealCurse2_Spell_LambOfMara). Not found and not made. |
| Staff of Poisoned Chalice | `1a793f:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Res_HealCurse4_Spell_PoisonedChalice). Not found and not made. |
| Staff of Slaying | `d1e89:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Res_Necro2_Spell_SlayLiving). Not found and not made. |
| Staff of Death | `d1e8a:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Res_Necro3_Spell_FingerOfDeath). Not found and not made. |
| Staff of Decomposition | `d1e8c:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Res_Necro4_Spell_Decompose). Not found and not made. |
| Staff of Automaton Breaking | `1a793b:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Res_Peace3_Spell_DustInTheClockwork). Not found and not made. |
| Staff of Nature's Balance | `d1e8d:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Res_Peace4_Spell_NaturesBalance). Not found and not made. |
| Staff of the Leech Seed | `d1e88:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Res_Poison2_Spell_LeechSeed). Not found and not made. |
| Staff of Ruin | `d1e8b:Apocalypse - Magic of Skyrim.esp` | Bladebinder | Staff whose spell is not in the college book (WB_Res_Tap3_Spell_Ruin). Not found and not made. |

