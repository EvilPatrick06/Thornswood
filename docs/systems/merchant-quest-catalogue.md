# Draft merchant quest catalogue

There are **9 authored draft definitions** in
`game/data/merchant-quests.json`, toward the required 240 or more distinct
offers for the 60 retained merchants. All are inactive. The file is marked
`active:false` and `complete:false` and is not imported into the gamemode.
The current runtime still has the 23 legacy definitions and ten bound routes.
These candidates are not available in the game.

Four scenes give Novice and Advanced Warriors and Mages different work. Five
drafts request goods for specific trades and holds. These are deliveries,
which can include goods obtained from other craftspeople; they do not assert
that the person returning them crafted them. Neither kind grants ordinary
buy, sell or supply permissions.

## Draft scenes

| Work | Offering trade and hold | Required standing | Exact objective | Gold | Personal cooldown |
| --- | --- | --- | --- | ---: | --- |
| A clear road for cloth | Whiterun Tailor | Novice Warrior | Defeat the one bound bandit in Redoran's Retreat | 15 | 6 hours |
| Coastal preparations | Winterhold Enchanter | Novice Mage | Defeat the one bound skeever on Winterhold's coast | 10 | 6 hours |
| Northwind work clothes | Rift Tailor | Advanced Warrior | Defeat both bound skeletons inside Northwind Mine | 35 | 6 hours |
| Shimmermist preparations | Whiterun Enchanter | Advanced Mage | Defeat both bound Falmer inside Shimmermist Cave | 40 | 6 hours |

The offering references are `1a684:Skyrim.esm` (base `13b9c:Skyrim.esm`,
book hold `whiterun`) and `1e7d6:Skyrim.esm` (base `1e7d5:Skyrim.esm`,
book hold `winterhold`). These are exact proposed roster bindings, not a
change to the existing 249-trader population. The Advanced offers bind
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
ambush or the deeper chamber's centurion. The proposed work-party and warding
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

All five require the named Novice profession half and propose a six-hour
completion cooldown. Each row copies its complete offering roster identity
and the selected public recipe's owner, half, rank, output, amount, bench,
inputs and conditions. Their goods already belong to that trade's ordinary
buy table. That does not grant legacy supply or commission permission.

| Work | Offering reference and trade | Required half | Delivery | Recipe reference |
| --- | --- | --- | --- | --- |
| Straps for the forge | Whiterun Smith `1a67c:Skyrim.esm` | Platewright | 6 Leather `db5d2:Skyrim.esm` | `1033de:Skyrim.esm` |
| Arrows for the hunt | Rift Woodworker `19dd0:Skyrim.esm` | Woodwright | 24 Iron Arrows `1397d:Skyrim.esm` | `b64f:Dawnguard.esm` |
| Thread for mourning cloth | Falkreath Tailor `1939ba:aaaGraniteHill.esp` | Haberdasher | 4 Thread `6ce001:Update.esm` | `84a:MoreCraftableEquipment.esp` |
| A supper for the docks | Haafingar Cook `198a0:Skyrim.esm` | Hearthcook | 2 Salmon Steak `64b3b:Skyrim.esm` | `f4310:Skyrim.esm` |
| Poultices for the marsh road | Hjaalmarch Alchemist `1aa61:Skyrim.esm` | Physicker | 2 Poultice `154c2:Thornswood-Content.esp` | `154c6:Thornswood-Content.esp` |

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
changed for these drafts.

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
six-hour dynamic rules remain intact. The proposed scene reward allowance does not
apply to these transfers of existing purse gold.

## Reward and activation limits

One finish of each scene candidate creates **100 gold**. Their cooldowns alone permit
at most **400 gold** in a half-open 24-hour window if all four could be completed
by one character. This is an arithmetic upper bound before eligibility,
travel, target availability and competition, not an approved aggregate
economy budget or measured income. These proposed scene rewards would be
created at completion, like legacy scene rewards; they are not supply
purchases from a finite purse. The separate unbundled scene-accounting
proposal reserves rewards within 150 gold per character per rolling 24 hours,
but is not integrated here. That proposal is a further limit, not a reason
to call the 400-gold cooldown bound actual earnings or an account/world cap.
The five commissions transfer existing purse
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
positions and returns, exact commission recipe/gate/role evidence, distinct
goods bundles and the inactive state. It does not construct a server,
touch a private world or establish connected acceptance. Claude owns all
operational steps after their source prerequisites are complete.
