# Gourmet fishing without the Creation Club

Everyone gets Gourmet's fishing recipes, on plain Special Edition, with no
Anniversary content and no extra mod.

## What this is

`GourmetFishing.esp` is 9 books, 48 food items, 90 cooking recipes, 4 loot
lists and 9 perks. The only reason it needs `ccBGSSSE001-Fish.esm` is that its
recipes name the Creation Club's fish as ingredients. Nothing else about it is
Creation Club content.

Fishing in Skyrim was the obvious replacement and it is not one: it adds
fishing gear, a minigame and a handful of novel ingredients, not fish species.
Vanilla Skyrim does have fish, though, and vanilla is the one thing every
single person already has.

So every recipe gets repointed at a fish from `Skyrim.esm`. All 90 map. None
are dropped.

## What changes for somebody cooking

The recipes are all still there and still work. What you lose is the variety of
the *inputs*: the Creation Club's 25 fish species collapse onto vanilla's 11
fish items, so several recipes end up asking for the same pond fish. The dishes
stay distinct, the fish you catch to make them are less so.

That is the whole cost, and it buys a version that ships in your collection as
your own file, with no permissions question and no paid content.

## Doing it

Open `GourmetFishing.esp` in SSEEdit, work down this table, and for each recipe
replace the ingredient it names with the one in the "replace with" column. Then
remove `ccBGSSSE001-Fish.esm` from its master list, which SSEEdit will offer
once the last reference to it is gone, and save it under a new name so the
original is untouched.

Check two things when you are done. The master list should read `Skyrim.esm`,
`Update.esm` and `Gourmet.esp` and nothing else. And the record count is small
enough to flag ESL, which you want, because an ESL takes no load order slot and
so costs nobody an index shift.


Every recipe in GourmetFishing.esp, the Creation Club ingredient it wants
now, and what to point it at instead. All replacements live in Skyrim.esm,
so the result needs no Anniversary content and no other mod.

| # | Recipe (COBJ EDID) | wants now | replace with | note |
|---:|---|---|---|---|
| 1 | `MAG_FishUpgradeRecipeFoodVampireFishCooked` | `ccBGSSSE001_FoodVampireFish` | `CritterPondFish02Ingredient` 0x00106E1B | substitute |
| 2 | `MAG_FishRecipeFoodVampireFishCooked` | `ccBGSSSE001_FoodVampireFish` | `CritterPondFish02Ingredient` 0x00106E1B | substitute |
| 3 | `MAG_FishRecipeFoodTunaSalmonCooked` | `ccBGSSSE001_FoodTunaSalmon` | `FoodSalmonCooked` 0x00064B3B | close, salmon |
| 4 | `MAG_FishRecipeFoodTripodFishCooked` | `ccBGSSSE001_FoodTripodFish` | `CritterPondFish05Ingredient` 0x00106E18 | substitute |
| 5 | `MAG_FishRecipeFoodPinnateSpadefishCooked` | `ccBGSSSE001_PinnateSpadefishIng` | `CritterPondFish02Ingredient` 0x00106E1B | substitute, small fish |
| 6 | `MAG_FishRecipeFoodAnglerCooked` | `ccBGSSSE001_FoodAngler` | `CritterPondFish04Ingredient` 0x00106E19 | substitute |
| 7 | `MAG_FishRecipeFoodArcticCharCooked` | `ccBGSSSE001_FoodArcticChar` | `CritterPondFish05Ingredient` 0x00106E18 | substitute, cold water |
| 8 | `MAG_FishRecipeFoodArcticGraylingCooked` | `ccBGSSSE001_FoodArcticGrayling` | `CritterPondFish01Ingredient` 0x00106E1C | substitute, cold water |
| 9 | `MAG_FishRecipeFoodSalmonCooked01` | `ccBGSSSE001_FoodSalmon` | `FoodSalmon` 0x00065C9F | exact, same fish |
| 10 | `MAG_FishRecipeFoodAsiaticGlassfishCooked` | `ccBGSSSE001_GlassfishIng` | `CritterPondFish04Ingredient` 0x00106E19 | substitute, small fish |
| 11 | `MAG_FishRecipeFoodAtlanticCodCooked` | `ccBGSSSE001_FoodAtlanticCod` | `CritterPondFish04Ingredient` 0x00106E19 | substitute, sea fish |
| 12 | `MAG_FishRecipeFoodAustrolebiasCooked` | `ccBGSSSE001_PearlfishIng` | `CritterPondFish02Ingredient` 0x00106E1B | substitute, small fish |
| 13 | `MAG_FishRecipeFoodBucketFishCooked` | `ccBGSSSE001_FoodBucketFish` | `CritterPondFish01Ingredient` 0x00106E1C | substitute |
| 14 | `MAG_FishRecipeFoodCabezonCooked` | `ccBGSSSE001_FoodCabezon` | `CritterPondFish02Ingredient` 0x00106E1B | substitute, sea fish |
| 15 | `MAG_FishRecipeFoodCarpCooked` | `ccBGSSSE001_FoodCarp` | `CritterPondFish01Ingredient` 0x00106E1C | substitute, river fish |
| 16 | `MAG_FishRecipeFoodCuckooCatfishCooked` | `ccBGSSSE001_FoodCuckooCatfish` | `CritterPondFish02Ingredient` 0x00106E1B | substitute, river fish |
| 17 | `MAG_FishRecipeFoodDragonfishCooked` | `ccBGSSSE001_FoodDragonfish` | `CritterPondFish03Ingredient` 0x00106E1A | substitute |
| 18 | `MAG_FishRecipeFoodFlameAnglerfishCooked` | `ccBGSSSE001_AngelfishIng` | `CritterPondFish01Ingredient` 0x00106E1C | substitute, small fish |
| 19 | `MAG_FishRecipeFoodGlassCatfishCooked` | `ccBGSSSE001_FoodGlassCatfish` | `CritterPondFish03Ingredient` 0x00106E1A | substitute, river fish |
| 20 | `MAG_FishRecipeFoodGoldfishCooked` | `ccBGSSSE001_GoldfishIng` | `CritterPondFish05Ingredient` 0x00106E18 | substitute, small fish |
| 21 | `MAG_FishRecipeFoodLyretailAnthiasCooked` | `ccBGSSSE001_LyretailAnthiasIng` | `CritterPondFish01Ingredient` 0x00106E1C | substitute, small fish |
| 22 | `MAG_FishRecipeFoodPygmySunfishCooked` | `ccBGSSSE001_PygmySunfishIng` | `CritterPondFish03Ingredient` 0x00106E1A | substitute, small fish |
| 23 | `MAG_FishRecipeFoodAnglerLarvaeCooked` | `ccBGSSSE001_AnglerLarvaeIng` | `SlaughterfishEgg01` 0x0007E8C5 | substitute, roe |
| 24 | `MAG_FishRecipeFoodJuvenileMudcrabCooked` | `ccBGSSSE001_JuvenileMudcrabIng` | `SlaughterfishScales` 0x0003AD70 | substitute, shellfish |
| 25 | `MAG_FishRecipeFoodCrabBisque` | `ccBGSSSE001_FoodCrabMeat` | `FoodClamMeat` 0x000EBA03 | substitute, shellfish |
| 26 | `MAG_FishRecipeFoodTomatoCrabBisque` | `ccBGSSSE001_FoodCrabMeat` | `FoodClamMeat` 0x000EBA03 | substitute, shellfish |
| 27 | `MAG_FishRecipeFoodPotatoCrabBisque` | `ccBGSSSE001_FoodCrabMeat` | `FoodClamMeat` 0x000EBA03 | substitute, shellfish |
| 28 | `MAG_FishRecipeFoodPotatoCrabBisqueHOT` | `ccBGSSSE001_FoodCrabMeat` | `FoodClamMeat` 0x000EBA03 | substitute, shellfish |
| 29 | `MAG_FishRecipeFoodTomatoCrabBisqueHOT` | `ccBGSSSE001_FoodCrabMeat` | `FoodClamMeat` 0x000EBA03 | substitute, shellfish |
| 30 | `MAG_FishRecipeFoodCrabBisqueHOT` | `ccBGSSSE001_FoodCrabMeat` | `FoodClamMeat` 0x000EBA03 | substitute, shellfish |
| 31 | `MAG_FishRecipeFoodSlaughterfishCooked` | `ccBGSSSE001_FoodSlaughterfish` | `FoodSlaughterfishCooked` 0x00064B3C | exact, same fish |
| 32 | `MAG_FishRecipeFoodCrabStew` | `ccBGSSSE001_FoodCrabMeat` | `FoodClamMeat` 0x000EBA03 | substitute, shellfish |
| 33 | `MAG_FishRecipeFoodCrabStewHOT` | `ccBGSSSE001_FoodCrabMeat` | `FoodClamMeat` 0x000EBA03 | substitute, shellfish |
| 34 | `MAG_FishRecipeFoodCrabCakes` | `ccBGSSSE001_FoodCrabMeat` | `FoodClamMeat` 0x000EBA03 | substitute, shellfish |
| 35 | `MAG_FishRecipeFoodAnglerLarvaeCookedCamping` | `ccBGSSSE001_AnglerLarvaeIng` | `SlaughterfishEgg01` 0x0007E8C5 | substitute, roe |
| 36 | `MAG_FishRecipeFoodArcticCharCookedCamping` | `ccBGSSSE001_FoodArcticChar` | `CritterPondFish05Ingredient` 0x00106E18 | substitute, cold water |
| 37 | `MAG_FishRecipeFoodArcticGraylingCookedCamping` | `ccBGSSSE001_FoodArcticGrayling` | `CritterPondFish01Ingredient` 0x00106E1C | substitute, cold water |
| 38 | `MAG_FishRecipeFoodAsiaticGlassfishCookedCamping` | `ccBGSSSE001_GlassfishIng` | `CritterPondFish04Ingredient` 0x00106E19 | substitute, small fish |
| 39 | `MAG_FishRecipeFoodAtlanticCodCookedCamping` | `ccBGSSSE001_FoodAtlanticCod` | `CritterPondFish04Ingredient` 0x00106E19 | substitute, sea fish |
| 40 | `MAG_FishRecipeFoodAustrolebiasCookedCamping` | `ccBGSSSE001_PearlfishIng` | `CritterPondFish02Ingredient` 0x00106E1B | substitute, small fish |
| 41 | `MAG_FishRecipeFoodBucketFishCookedCamping` | `ccBGSSSE001_FoodBucketFish` | `CritterPondFish01Ingredient` 0x00106E1C | substitute |
| 42 | `MAG_FishRecipeFoodCabezonCookedCamping` | `ccBGSSSE001_FoodCabezon` | `CritterPondFish02Ingredient` 0x00106E1B | substitute, sea fish |
| 43 | `MAG_FishRecipeFoodCarpCookedCamping` | `ccBGSSSE001_FoodCarp` | `CritterPondFish01Ingredient` 0x00106E1C | substitute, river fish |
| 44 | `MAG_FishRecipeFoodVampireFishCookedCamping` | `ccBGSSSE001_FoodVampireFish` | `CritterPondFish02Ingredient` 0x00106E1B | substitute |
| 45 | `MAG_FishRecipeFoodTunaSalmonCookedCamping` | `ccBGSSSE001_FoodTunaSalmon` | `FoodSalmonCooked` 0x00064B3B | close, salmon |
| 46 | `MAG_FishRecipeFoodTripodFishCookedCamping` | `ccBGSSSE001_FoodTripodFish` | `CritterPondFish05Ingredient` 0x00106E18 | substitute |
| 47 | `MAG_FishRecipeFoodSlaughterfishCookedCamping` | `ccBGSSSE001_FoodSlaughterfish` | `FoodSlaughterfishCooked` 0x00064B3C | exact, same fish |
| 48 | `MAG_FishRecipeFoodSalmonCookedCamping` | `ccBGSSSE001_FoodSalmon` | `FoodSalmon` 0x00065C9F | exact, same fish |
| 49 | `MAG_FishRecipeFoodPinnateSpadefishCookedCamping` | `ccBGSSSE001_PinnateSpadefishIng` | `CritterPondFish02Ingredient` 0x00106E1B | substitute, small fish |
| 50 | `MAG_FishRecipeFoodPygmySunfishCookedCamping` | `ccBGSSSE001_PygmySunfishIng` | `CritterPondFish03Ingredient` 0x00106E1A | substitute, small fish |
| 51 | `MAG_FishRecipeFoodLyretailAnthiasCookedCamping` | `ccBGSSSE001_LyretailAnthiasIng` | `CritterPondFish01Ingredient` 0x00106E1C | substitute, small fish |
| 52 | `MAG_FishRecipeFoodJuvenileMudcrabCookedCamping` | `ccBGSSSE001_JuvenileMudcrabIng` | `SlaughterfishScales` 0x0003AD70 | substitute, shellfish |
| 53 | `MAG_FishRecipeFoodGoldfishCookedCamping` | `ccBGSSSE001_GoldfishIng` | `CritterPondFish05Ingredient` 0x00106E18 | substitute, small fish |
| 54 | `MAG_FishRecipeFoodGlassCatfishCookedCamping` | `ccBGSSSE001_FoodGlassCatfish` | `CritterPondFish03Ingredient` 0x00106E1A | substitute, river fish |
| 55 | `MAG_FishRecipeFoodFlameAnglerfishCookedCamping` | `ccBGSSSE001_AngelfishIng` | `CritterPondFish01Ingredient` 0x00106E1C | substitute, small fish |
| 56 | `MAG_FishRecipeFoodDragonfishCookedCamping` | `ccBGSSSE001_FoodDragonfish` | `CritterPondFish03Ingredient` 0x00106E1A | substitute |
| 57 | `MAG_FishRecipeFoodCuckooCatfishCookedCamping` | `ccBGSSSE001_FoodCuckooCatfish` | `CritterPondFish02Ingredient` 0x00106E1B | substitute, river fish |
| 58 | `MAG_FishRecipeFoodAnglerCookedCamping` | `ccBGSSSE001_FoodAngler` | `CritterPondFish04Ingredient` 0x00106E19 | substitute |
| 59 | `MAG_FishUpgradeRecipeFoodCrabCakes` | `ccBGSSSE001_FoodCrabMeat` | `FoodClamMeat` 0x000EBA03 | substitute, shellfish |
| 60 | `MAG_FishUpgradeRecipeFoodCrabStew` | `ccBGSSSE001_FoodCrabMeat` | `FoodClamMeat` 0x000EBA03 | substitute, shellfish |
| 61 | `MAG_FishUpgradeRecipeFoodPotatoCrabBisque` | `ccBGSSSE001_FoodCrabMeat` | `FoodClamMeat` 0x000EBA03 | substitute, shellfish |
| 62 | `MAG_FishUpgradeRecipeFoodCrabStewHOT` | `ccBGSSSE001_FoodCrabMeat` | `FoodClamMeat` 0x000EBA03 | substitute, shellfish |
| 63 | `MAG_FishUpgradeRecipeFoodCrabBisque` | `ccBGSSSE001_FoodCrabMeat` | `FoodClamMeat` 0x000EBA03 | substitute, shellfish |
| 64 | `MAG_FishUpgradeRecipeFoodCrabBisqueHOT` | `ccBGSSSE001_FoodCrabMeat` | `FoodClamMeat` 0x000EBA03 | substitute, shellfish |
| 65 | `MAG_FishUpgrardeRecipeFoodTomatoCrabBisque` | `ccBGSSSE001_FoodCrabMeat` | `FoodClamMeat` 0x000EBA03 | substitute, shellfish |
| 66 | `MAG_FishUpgradeRecipeFoodTomatoCrabBisqueHOT` | `ccBGSSSE001_FoodCrabMeat` | `FoodClamMeat` 0x000EBA03 | substitute, shellfish |
| 67 | `MAG_FishUpgradeRecipeFoodPotatoCrabBisqueHOT` | `ccBGSSSE001_FoodCrabMeat` | `FoodClamMeat` 0x000EBA03 | substitute, shellfish |
| 68 | `MAG_FishUpgradeRecipeFoodAnglerCooked` | `ccBGSSSE001_FoodAngler` | `CritterPondFish04Ingredient` 0x00106E19 | substitute |
| 69 | `MAG_FishUpgradeRecipeFoodAnglerLarvaeCooked` | `ccBGSSSE001_AnglerLarvaeIng` | `SlaughterfishEgg01` 0x0007E8C5 | substitute, roe |
| 70 | `MAG_FishUpgradeRecipeFoodArcticCharCooked` | `ccBGSSSE001_FoodArcticChar` | `CritterPondFish05Ingredient` 0x00106E18 | substitute, cold water |
| 71 | `MAG_FishUpgradeRecipeFoodArcticGraylingCooked` | `ccBGSSSE001_FoodArcticGrayling` | `CritterPondFish01Ingredient` 0x00106E1C | substitute, cold water |
| 72 | `MAG_FishUpgradeRecipeFoodAsiaticGlassfishCooked` | `ccBGSSSE001_GlassfishIng` | `CritterPondFish04Ingredient` 0x00106E19 | substitute, small fish |
| 73 | `MAG_FishUpgradeRecipeFoodAtlanticCodCooked` | `ccBGSSSE001_FoodAtlanticCod` | `CritterPondFish04Ingredient` 0x00106E19 | substitute, sea fish |
| 74 | `MAG_FishUpgradeRecipeFoodAustrolebiasCooked` | `ccBGSSSE001_PearlfishIng` | `CritterPondFish02Ingredient` 0x00106E1B | substitute, small fish |
| 75 | `MAG_FishUpgradeRecipeFoodBucketFishCooked` | `ccBGSSSE001_FoodBucketFish` | `CritterPondFish01Ingredient` 0x00106E1C | substitute |
| 76 | `MAG_FishUpgradeRecipeFoodCabezonCooked` | `ccBGSSSE001_FoodCabezon` | `CritterPondFish02Ingredient` 0x00106E1B | substitute, sea fish |
| 77 | `MAG_FishUpgradeRecipeFoodCarpCooked` | `ccBGSSSE001_FoodCarp` | `CritterPondFish01Ingredient` 0x00106E1C | substitute, river fish |
| 78 | `MAG_FishUpgradeRecipeFoodCuckooCatfishCooked` | `ccBGSSSE001_FoodCuckooCatfish` | `CritterPondFish02Ingredient` 0x00106E1B | substitute, river fish |
| 79 | `MAG_FishUpgradeRecipeFoodDragonfishCooked` | `ccBGSSSE001_FoodDragonfish` | `CritterPondFish03Ingredient` 0x00106E1A | substitute |
| 80 | `MAG_FishUpgradeRecipeFoodFlameAnglerfishCooked` | `ccBGSSSE001_AngelfishIng` | `CritterPondFish01Ingredient` 0x00106E1C | substitute, small fish |
| 81 | `MAG_FishUpgradeRecipeFoodGlassCatfishCooked` | `ccBGSSSE001_FoodGlassCatfish` | `CritterPondFish03Ingredient` 0x00106E1A | substitute, river fish |
| 82 | `MAG_FishUpgradeRecipeFoodGoldfishCooked` | `ccBGSSSE001_GoldfishIng` | `CritterPondFish05Ingredient` 0x00106E18 | substitute, small fish |
| 83 | `MAG_FishUpgradeRecipeFoodJuvenileMudcrabCooked` | `ccBGSSSE001_JuvenileMudcrabIng` | `SlaughterfishScales` 0x0003AD70 | substitute, shellfish |
| 84 | `MAG_FishUpgradeRecipeFoodLyretailAnthiasCooked` | `ccBGSSSE001_LyretailAnthiasIng` | `CritterPondFish01Ingredient` 0x00106E1C | substitute, small fish |
| 85 | `MAG_FishUpgradeRecipeFoodPinnateSpadefishCooked` | `ccBGSSSE001_PinnateSpadefishIng` | `CritterPondFish02Ingredient` 0x00106E1B | substitute, small fish |
| 86 | `MAG_FishUpgradeRecipeFoodPygmySunfishCooked` | `ccBGSSSE001_PygmySunfishIng` | `CritterPondFish03Ingredient` 0x00106E1A | substitute, small fish |
| 87 | `MAG_FishUpgradeRecipeFoodSalmonCooked` | `ccBGSSSE001_FoodSalmon` | `FoodSalmon` 0x00065C9F | exact, same fish |
| 88 | `MAG_FishUpgradeRecipeFoodSlaughterfishCooked` | `ccBGSSSE001_FoodSlaughterfish` | `FoodSlaughterfishCooked` 0x00064B3C | exact, same fish |
| 89 | `MAG_FishUpgradeRecipeFoodTripodFishCooked` | `ccBGSSSE001_FoodTripodFish` | `CritterPondFish05Ingredient` 0x00106E18 | substitute |
| 90 | `MAG_FishUpgradeRecipeFoodTunaSalmonCooked` | `ccBGSSSE001_FoodTunaSalmon` | `FoodSalmonCooked` 0x00064B3B | close, salmon |

Rows: 90
