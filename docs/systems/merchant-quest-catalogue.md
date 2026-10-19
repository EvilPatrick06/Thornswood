# Merchant quest catalogue

There are **14 authored definitions** in
`game/data/merchant-quests.json`, toward the required 240 or more distinct
offers for the60 retained merchants. Four kill scenes are explicitly admitted
by the pinned activation manifest; the ten delivery commissions remain
inactive. The aggregate authoring file stays `active:false` and
`complete:false`, so adding a draft does not enable it. Runtime includes the23
legacy definitions and ten bound routes plus these four scenes. Source
activation is not proof of a completed Dev deployment.

Four scenes give Novice and Advanced Warriors and Mages different work. Ten
drafts request goods for specific trades and holds. These are deliveries,
which can include goods obtained from other craftspeople; they do not assert
that the person returning them crafted them. Neither kind grants ordinary
buy, sell or supply permissions.

## First playable scenes

| Work | Offering trade and hold | Required standing | Exact objective | Gold | Personal cooldown |
| --- | --- | --- | --- | ---: | --- |
| A clear road for cloth | Whiterun Tailor | Novice Warrior | Defeat the one bound bandit in Redoran's Retreat | 15 | 6 hours |
| Coastal preparations | Winterhold Enchanter | Novice Mage | Defeat the one bound skeever on Winterhold's coast | 10 | 6 hours |
| Northwind work clothes | Rift Tailor | Advanced Warrior | Defeat both bound skeletons inside Northwind Mine | 35 | 6 hours |
| Shimmermist preparations | Whiterun Enchanter | Advanced Mage | Defeat both bound Falmer inside Shimmermist Cave | 40 | 6 hours |

The offering references are `1a684:Skyrim.esm` (base `13b9c:Skyrim.esm`,
book hold `whiterun`) and `1e7d6:Skyrim.esm` (base `1e7d5:Skyrim.esm`,
book hold `winterhold`). These are exact retained roster bindings. The
Advanced offers bind
`31efc3:Riften Expansion.esp` (base `1d0769:Riften Expansion.esp`, book hold
`riften`) and `1a672:Skyrim.esm` (base `13ba1:Skyrim.esm`, book hold
`whiterun`), respectively. Their saved profession gates require Advanced
Warrior or Mage standing. Neither is Master work or needs a Master half or
school. These fill the two planned Advanced exceptions; they do not replace
the class-gated Novice reservations or any owning-trade work.

## Targets and their existing returns

The target data copies the retained placements in `npc-population.json`.
No new actor, extra harvest, equipment grant or changed return rate is added.
Source positions and normal leashes are recorded in the JSON.

| Target | Exact reference and base | Runtime place | Source position | Normal leash | Existing return |
| --- | --- | --- | --- | ---: | --- |
| Bandit | `36ce1:Skyrim.esm`, base `1e79d:Skyrim.esm` | Interior cell `15224:Skyrim.esm` | `[-2136.4208984375, 1534.8690185546875, -212.0419921875]` | 2,048 | 45 minutes |
| Skeever | `ef60f:Skyrim.esm`, base `23ab7:Skyrim.esm` | Tamriel `3c:Skyrim.esm`, source cell `8dea:Skyrim.esm` | `[99232, 128672, -13824]` | 1,536 | 20 minutes |
| Northwind skeleton | `476c9:Skyrim.esm`, base `2d1fc:Skyrim.esm` | Interior cell `15294:Skyrim.esm` | `[407.26873779296875, 3681.330322265625, 159.30126953125]` | 1,536 | 45 minutes |
| Northwind skeleton | `476ca:Skyrim.esm`, base `2d1fd:Skyrim.esm` | Interior cell `15294:Skyrim.esm` | `[-145.48818969726562, 2940.852783203125, 153.1743927001953]` | 1,536 | 45 minutes |
| Shimmermist Falmer | `530c0:Skyrim.esm`, base `1e7b3:Skyrim.esm` | Interior cell `1521c:Skyrim.esm` | `[3485.25244140625, -723.4301147460938, -624.6600341796875]` | 1,536 | 45 minutes |
| Shimmermist Falmer | `530c4:Skyrim.esm`, base `1e7b4:Skyrim.esm` | Interior cell `1521c:Skyrim.esm` | `[5013.04150390625, -3487.726806640625, -631.1539916992188]` | 1,536 | 45 minutes |

Northwind Mine's location identifier is `fdbdf:Skyrim.esm`; Shimmermist
Cave's is `1929d:Skyrim.esm`. Both already have population tier two and a
site cap of 12. Neither cap changes or promises all targets will be available
at once. Both selected Falmer are ordinary retained placements, not the
ambush or the deeper chamber's centurion. The work-party and warding
survey are reasons for these kill objectives, not additional escort,
shipment or survey mechanics. Population tier is not a measured guarantee
of combat balance for the quest rank. No connected balance test ran.

Population location identifiers such as `19295:Skyrim.esm` identify a named
place; they are not the runtime cell or worldspace. The future adapter must
use the actual cell/world, exact reference and base, current life and body
identity, species, authored leash, kill attribution and original conversation
and transaction fences. A similarly named bandit or skeever elsewhere does
not count. Existing camp difficulty and animal habitat remain unchanged.

## Draft finite-purse commissions

The five profession deliveries require the named Novice half. Five additional
deliveries require a Novice class, independently of crafting profession.
All ten propose a six-hour completion cooldown. Each row copies its complete offering roster identity
and either its selected public recipe's owner, half, rank, output, amount,
bench, inputs and conditions, or its canonical Gatherer harvest evidence.
Their goods already belong to that trade's ordinary
buy table. That does not grant legacy supply or commission permission.

| Work | Offering reference and trade | Required half | Delivery | Recipe reference |
| --- | --- | --- | --- | --- |
| Straps for the forge | Whiterun Smith `1a67c:Skyrim.esm` | Platewright | 6 Leather `db5d2:Skyrim.esm` | `1033de:Skyrim.esm` |
| Arrows for the hunt | Rift Woodworker `19dd0:Skyrim.esm` | Woodwright | 24 Iron Arrows `1397d:Skyrim.esm` | `b64f:Dawnguard.esm` |
| Thread for mourning cloth | Falkreath Tailor `1939ba:aaaGraniteHill.esp` | Haberdasher | 4 Thread `6ce001:Update.esm` | `84a:MoreCraftableEquipment.esp` |
| A supper for the docks | Haafingar Cook `198a0:Skyrim.esm` | Hearthcook | 2 Salmon Steak `64b3b:Skyrim.esm` | `f4310:Skyrim.esm` |
| Poultices for the marsh road | Hjaalmarch Alchemist `1aa61:Skyrim.esm` | Physicker | 2 Poultice `154c2:Thornswood-Content.esp` | `154c6:Thornswood-Content.esp` |

These five class offers are additional work at the same merchants. A class
has no profession half. Delivering goods from another craftsperson is valid;
the customer need not be a Smith, Woodworker, Tailor or Cook.

| Work | Offering reference and trade | Required class | Delivery | Recipe reference |
| --- | --- | --- | --- | --- |
| A spare pick for the mine | Whiterun Smith `1a67c:Skyrim.esm` | Novice Miner | 1 Pickaxe `e3c16:Skyrim.esm` | `1548d:Thornswood-Content.esp` |
| A spare pole for the lake | Rift Woodworker `19dd0:Skyrim.esm` | Novice Fisher | 1 Crude Fishing Pole `15498:Thornswood-Content.esp` | `1549c:Thornswood-Content.esp` |
| Boots for the trail | Falkreath Tailor `1939ba:aaaGraniteHill.esp` | Novice Hunter | 1 Boots `d1921:Skyrim.esm` | `928:MoreCraftableEquipment.esp` |
| Soup for the field hands | Haafingar Cook `198a0:Skyrim.esm` | Novice Farmer | 2 Potato Soup `353d:HearthFires.esm` | `3542:HearthFires.esm` |
| Cotton for marsh-road dressings | Hjaalmarch Alchemist `1aa61:Skyrim.esm` | Novice Gatherer | 3 Tundra Cotton `3f7f8:Skyrim.esm` | Harvest `bb947:Skyrim.esm`, no crafting recipe |

The source checker preserves these five exact merchant/class allocations.
Recipe ownership and buy permission still belong to the merchant's trade.
For profession deliveries the named half must still match the recipe.
The class allocation is separate from the exact authored goods in the JSON;
the future compiler must derive commission authority from that reviewed
catalogue, never from every item that could pass a source check. All five
planned class-Novice slots now have drafts. The second distinct quest for
each class, Master work and full catalogue coverage remain unfinished.

The pickaxe recipe makes one from one Iron Ingot and one Tool Handle. The
pole makes one from two Firewood, one Leather Strips and two Tundra Cotton.
The boots make one from one Leather and one Thread. Potato Soup makes one
from one Salt Pile, one Potato and one Leek; two bowls need two batches.
Their complete copied recipe proof retains the owning half, bench and
Novice input supply provenance. The boots use a vanilla output, without
adding any permission-held armor assets or changing creation equipment.

Cotton's proof copies the produce, name and Novice rank from the canonical
Gatherer `harvests` table in `game/data/harvests.json`. Its source is
`TreeFloraTundraCotton01`, a `TREE` record, not a crafting recipe. Only a
Gatherer-gated delivery may use this proof type; crop, fish, game, detail or
unranked records do not substitute for a canonical harvest entry. The
requested item must match its produce and the Alchemist's buy permission.
This is a delivery from any legitimate supplier, with no particular harvest
event required. It adds no plant, stock, yield, coordinates or return rate
and does not claim cotton is newly placed in Hjaalmarch or currently ready
to harvest. The future exact commission authority is still unimplemented.

Leather's selected recipe produces two from one Novice Deer Hide. Iron
Arrows produce 24 from one Firewood and one Iron Ingot. Thread produces one
from two Tundra Cotton. Salmon Steak produces one from one Salt Pile and one
Salmon Meat. Poultice produces one from one Tundra Cotton and one Garlic.
Every listed input has Novice supply provenance in the public recipe table.
These producer facts do not add placed resources or alter shared stock and
returns. Current ingredient availability and accepted price are not measured.

The copied recipe conditions matter. Leather requires at least one
`DeerHide02`. Salmon Steak requires at least one `MAG_FoodSalmon` and no
`MAG_FoodUpgradePerk03`. Their `canBeMadeOnDayOne:false` flag does not mean
their ingredients have no Novice producer. It also does not prove every
qualified customer can personally run that recipe. No condition or rank is
changed for these drafts. Potato Soup also retains its requirement for
`MAG_RecipePerkPotatoSoup` and exclusion of `MAG_FoodUpgradePerk03`. Novice
Farmer standing alone does not establish those recipe conditions; this is
a delivery request and does not require personal crafting.

Commission payment is the future accepted submitted hold price multiplied
by the original quantity, from the merchant's finite purse. No default price,
fixed bonus or new gold is granted here. Missing price, unsupported goods or
insufficient unreserved purse must explain why new acceptance is refused.
Customers need not own the goods when accepting work. The future transaction
must reserve the promised purse amount and preserve the accepted quote
through its exact conserved pending-transfer protocol. At delivery, missing
matching inventory refuses completion while keeping the work and its purse
reservation. A changed current price or lack of other spendable purse money
must not invalidate that accepted promise. Ordinary stock for sale remains
visible. This source slice implements none of that runtime protocol.

Authored commissions need an explicit source-derived authority keyed by
their exact reviewed quest and merchant, plus their own conserved transfer
kind, cooldown persistence and recovery. Several finished goods are absent
from ordinary supply. Never widen that table, treat all buy goods as approved
commissions or pass these rows as legacy supply. Its existing five-good and
six-hour dynamic rules remain intact. The scene reward allowance does not
apply to these transfers of existing purse gold.

## Reward and activation limits

One finish of each scene candidate creates **100 gold**. Their cooldowns alone permit
at most **400 gold** in a half-open 24-hour window if all four could be completed
by one character. This is an arithmetic upper bound before eligibility,
travel, target availability and competition, not an approved aggregate
economy budget or measured income. These scene rewards are
created at completion, like legacy scene rewards; they are not supply
purchases from a finite purse. The bundled scene-accounting
proposal reserves rewards within 150 gold per character per rolling 24 hours,
but is not integrated here. That proposal is a further limit, not a reason
to call the 400-gold cooldown bound actual earnings or an account/world cap.
The ten commissions transfer existing purse
money at their future accepted submitted prices, which are not invented or
included as newly created gold in that bound.

Before activation, finish the full distinct catalogue and its numerical
aggregate budget and cadence, bounded saved-state representation, generic
target support, original-term recovery and coupled roster admission. Existing
accepted quests keep their original terms. Neither changing these flags nor
putting these IDs into the bundle is permitted as a shortcut. The source test
rejects activation or a runtime import in this incomplete slice.

`node tests/test-merchant-quest-catalogue.js` checks actual rulebook gates,
exact merchant and retained-target bindings, distinct objectives, source
positions and returns, exact commission recipe/harvest/gate/role evidence, distinct
goods bundles and the explicit activation boundary. It does not construct a server,
touch a private world or establish connected acceptance. Claude owns all
operational steps after their source prerequisites are complete.

## Runtime admission and recovery

The four published scene IDs and their full authored hashes are pinned in
`merchant-quest-activation.json`. Published definitions are immutable; new
deeds or rewards need new IDs while the old definitions remain available
for accepted work. Only these four IDs enter the hot-reload bundle.

At acceptance, the server reserves the original reward in the same character
property transaction as its objective and copied terms. At completion,
verified kills, that reservation, gold and the cooldown change in one native
inventory/property transaction. A failed write changes none of them. The
rolling24-hour allowance is150 gold per character across all newly admitted
scenes, counting paid gold plus every outstanding reservation. Holds do not
expire. A delayed payout is dated when it succeeds, never when it was reserved.
This is not an account or world cap and does not include legacy scene rewards.

Abandoning well-formed saved payment evidence removes only that current
job's own liability, without payment or a completion cooldown. It can also
reconcile copied terms or progress that no longer match, including an orphan
reservation, without releasing a different job's token or removing payout
history. Structurally corrupt payment evidence refuses changes and needs
trusted staff recovery; it is never erased or rebuilt by a retry.

There are at most three open expanded jobs. This first runtime section has
20 owned target references in total, including the14 legacy references. The
complete representative character property with three original-term jobs,
all20 maximum-generation histories,23 legacy cooldowns, the largest valid
remaining paid list and1024 retained unknown bytes is3523 UTF-8 bytes. Native
property capacity remains16384 bytes. Oversized existing records refuse new
acceptance without deleting unknown or legacy fields. This is a source and
synthetic transaction measurement, not a connected playtest.
