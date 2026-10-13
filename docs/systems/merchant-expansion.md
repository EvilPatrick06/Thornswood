# Six trades in each hold

Patrick's requirements of 12 October 2026 replace the earlier unrestricted
trader count and locked quest lineup. This is the implementation contract;
it does not describe a completed release.

## Roster and tables

Each of the ten existing book holds, including Raven Rock, has exactly six
guild NPCs: Smith, Woodworker, Tailor, Enchanter, Cook and Alchemist. There
is one of each, for 60 total. Reuse suitable authored identities. Exact
guild relocation remains separate. All other guild traders are retired.

Each role has an explicit item table, checked by the server for purchases,
sales and supply work. Hold price books remain the price authority; a role
table is permission to trade an item, not permission to invent a price.
Different roles have different tables. Stock stays finite and consists of
goods bought; purses remain finite. Retiring a trader must preserve saved
balances, stock and unresolved settlements, without another starting grant.

The controller accepts server-compiled native item IDs for each role's buy,
sell and supply permissions. A declared role without verified tables refuses
setup. It copies permissions and reference bindings before interaction, so
later configuration edits cannot change an open controller's authority.
Both the panel and submitted actions check the actual resolved item ID;
stock must also match that ID, rather than its name alone. Supply permission
is separate from ordinary buying. Saved transfers recover their original
terms even if their goods are outside a later role's table. The current
249-trader catalogue has no role assignments: this support does not activate
the six-trade roster, its display titles or the final item-table data.

The panel has separate selling and buying sections. Selling shows only
carried items this merchant can buy at its submitted price, within its
current purse. A failed condition gives a clear reason and no sale rows.
Buying still shows stocked goods offered for sale even when the merchant
cannot buy anything. Quantity controls use the same authenticated settlement
and receipt checks as the existing transfer. A displayed quote never
authorizes a stale or forged request.

## Inactive item catalogue

`game/data/merchant-role-tables.json` records the six distinct static item
tables and the source evidence behind each identity. It is marked inactive
and is not imported into merchant startup. The active roster remains 249.
These are permissions, not starting stock or new gold, and a submitted hold
price is still required before an item can be traded.

| Trade | Buy identities | Sell identities | Supply identities |
| --- | ---: | ---: | ---: |
| Smith | 265 | 265 | 40 |
| Woodworker | 54 | 54 | 16 |
| Tailor | 271 | 271 | 23 |
| Enchanter | 408 | 408 | 16 |
| Cook | 116 | 116 | 53 |
| Alchemist | 70 | 70 | 68 |

Public work supplies its owning trade's outputs and ingredients. Crafting
fees never become goods. A cut duplicate smelt does not remove the ingot
made by the kept smelt; tempering does not establish a new source. Faction
rolls, removed goods, nonplayable equipment and currency are excluded.
The explicitly retained playable Riekling company goods stay with their
owning trade. Wardweaver bases use the same public wearable policy.
Enchanters also handle the measured ordinary soul gems. Existing enchanted
item metadata remains part of the original goods, without a new price bonus.

Alchemists accept verified ingredient records from plants, hunting, crops,
fish and dedicated stations, including eggs, honeycomb and salts, alongside
their medicine recipes. Additional Cook resource goods require verified
food records; its public authored outputs and ingredients, including
cooking materials such as fire paste, retain their owning trade. Unranked sources
are not imported wholesale, and potion-name text does not classify a good.
This static catalogue does not implement trading player-created brews.

`python scripts/dev/Build-MerchantRoleTables.py` generates source data from
the recorded load order and repository-owned plugins. It never writes game
files or ledger state. `--check` rederives the lists without an installed
game, checks input source hashes and plugin pins, and reads repository-owned
item records to verify their winning identity, type, flags and food status.
An unrelated own-plugin art or quest edit does not change item permission;
a contributing record change requires regenerated evidence. CI runs the
derivation and source-evidence regressions before its broader harnesses.

## Quests

Every NPC has Novice, Advanced, Expert and Master work. Both the trade and
the hold select the quests: Whiterun's Smith and Riften's Smith must differ
in objectives, locations and text, not just their displayed hold name.
Additional quests are authorized. Difficulty and rewards increase with
tier; every row records exact objectives, rewards and cooldowns before it
is enabled. Scarce resource limits and ordinary tool/rank gates still apply.

Across the catalogue, every profession and every class has at least two
distinct quests that explicitly require it. Higher rank satisfies a lower
rank gate. Each profession half has at least one Master quest requiring
mastery in that named half. Class Master work requires Master rank in that
class and no profession half. Mage Master work requires at least one known
Master spell of the named school, not merely a school selection or a tome
in the pack. Each of the five schools has such work.

The coverage check enumerates Warrior, Mage, Alchemist, Cook, Smith,
Enchanter, Tailor and Woodworker; Hunter, Fisher, Gatherer, Miner and Farmer;
all fourteen non-Mage halves; and all five magic schools. A cosmetic text
label does not count as a server gate. Quest eligibility and quest ownership
are separate: changing a rank, merchant or session cannot duplicate a
reward, erase old work or allow a different trader to take its turn-in.

Supply still moves goods at the submitted price from a finite NPC purse.
Scene work pays its authored reward once through the quest transaction.
New reward totals and repeat cadence must be checked against the economy;
adding many offers must not create an uncapped new daily gold faucet.

## Build order and checks

| Part | Responsibility | Requires |
| --- | --- | --- |
| merchant-panel | Separate eligible pack sales and stocked shelf purchases | Existing settlement |
| merchant-history | Separate historical purse identities from active interaction references | Existing private ledger and receipt recovery |
| merchant-roster | Six identities per hold and safe retirement of others | Ledger migration checks |
| merchant-tables | Explicit role item permissions on every server path | Roster |
| merchant-quests | Hold/role/tier objectives, gates and economy limits | Tables and native quest transactions |

First reproduce and fix the item-offer UI with server fixtures and a local
browser fixture. Then validate the roster and ledger migration before
cutting identities. Add table checks to view and command paths together.
The purse controller accepts an explicit `merchantHistory` manifest of
reference/base pairs for retirement recovery. A retired identity cannot be
prepared for interaction or receive a starting purse; its existing pending
transfer can finish against the private ledger without loading its NPC.
The purse controller has one writer per ledger namespace within the server
runtime. Replacing it revokes the old controller across all merchants. A
synchronous mutation locks the namespace through its durable save and
native projection; nested mutation or replacement is refused explicitly.
Each commit starts from the controller's latest document, so another
merchant's saved change survives an older prepared offer.
Before recovery, trade admission, supply-history cleanup or another inventory
writer proceeds, settlement checks the whole pending list. Merchant references,
transaction identities, humans and receipts must be exclusive; each saved intent
must match its world, merchant and current debit or credit state. An invalid
list stops settlement without deleting records or changing inventory, including
malformed non-null intents. Runtime human descriptions use the native local
hexadecimal form; numeric aliases share the same reservation. Debit recovery
checks the original preceding receipt as well as the debit and final receipts.
Legacy intents without a supply map compare as an empty map throughout recovery;
invalid maps are rejected. Recovery applies only merchant snapshot fields,
preserving unrelated saved state.
Full saved trade snapshots must conserve goods, gold, stock labels and item
metadata using their original terms. Zero-price transfers remain valid. New
intents retain fixed-size terms and inventory digests through compaction,
including the original cooldown-history digest. Compact records validate
their retained supply transition before recovery or retirement readiness,
within the same initial and recovery size limits. Recovery attempts must add
exactly the saved credit to their expected inventory. Supply keys bind to the
human and the outer item label, separate from the native item's name.
Legacy intents gain no new summary bytes. Full legacy snapshots are checked
where available; genuine old compact credit keeps its bounded receipt-based
recovery because its discarded original deltas cannot be reconstructed.
The settlement canRetire readiness check refuses any remaining legacy pending
intent without retained terms. This readiness check still needs integration
with the explicit roster activation step before a cut; no population change
is included here. Unresolved legacy transfers retain their records and block
activation rather than being reset or reissued.
New intents use format3 and require their retained terms; format2 identifies
genuine pre-summary legacy work. Dropping terms cannot downgrade a new record.
Legacy array cooldown keys still require a nonempty item label; original
item-only legacy keys keep their compatible saved meaning.
Without an explicit history manifest, the current active roster remains the
manifest. This support alone does not cut the current 249 traders. Before
activating retirement, validate writer ownership, pending-intent uniqueness,
explicit first-world initialization and reachable legacy quest turn-ins.
Merchant runtime startup requires its existing private ledger and initialization
marker. Missing evidence stops service without creating a fresh manifest or
resetting purses. It checks again before durable writer dispatch, after privacy
checks and serialization. Recover missing existing-world evidence from its
original records; do not treat a restart or repair as new-world authorization.
The explicit offline initializer remains a separate prerequisite. Existing
native replacement of a known valid document and dungeon-ledger initialization
keep their existing behavior.
Implement quests in complete, source-bound slices with coverage checks for
all trades, holds, tiers, classes, professions, halves and schools. Legacy
open quests must remain recoverable during catalogue changes.

Local checks include `node tests/test-merchant-trading.js`,
`node tests/test-merchant-settlement.js`,
`node tests/test-merchant-pending-preflight.js`,
`node tests/test-merchant-conservation.js`,
`node tests/test-merchant-deployment.js` and
`node scripts/dev/Build-MerchantGamemode.js --check`.
No game playtests or operational steps are performed by Codex. Changes
merge only after the required exact-head Launcher builds gate. Claude
receives the release handoff; no change is described as live before that.
