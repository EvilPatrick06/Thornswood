# Draft merchant quest catalogue

There are **2 authored draft definitions** in
`game/data/merchant-quests.json`, toward the required 240 or more distinct
offers for the 60 retained merchants. Both are inactive. The file is marked
`active:false` and `complete:false` and is not imported into the gamemode.
The current runtime still has the 23 legacy definitions and ten bound routes.
These candidates are not available in the game.

This first authoring slice gives a beginning Warrior and Mage different work.
The profession gate is separate from the merchant's trade and does not expand
the goods that trader can buy, sell or request as supply.

| Work | Offering trade and hold | Required standing | Exact objective | Gold | Personal cooldown |
| --- | --- | --- | --- | ---: | --- |
| A clear road for cloth | Whiterun Tailor | Novice Warrior | Defeat the one bound bandit in Redoran's Retreat | 15 | 6 hours |
| Coastal preparations | Winterhold Enchanter | Novice Mage | Defeat the one bound skeever on Winterhold's coast | 10 | 6 hours |

The offering references are `1a684:Skyrim.esm` (base `13b9c:Skyrim.esm`,
book hold `whiterun`) and `1e7d6:Skyrim.esm` (base `1e7d5:Skyrim.esm`,
book hold `winterhold`). These are exact proposed roster bindings, not a
change to the existing 249-trader population.

## Targets and their existing returns

The target data copies the retained placements in `npc-population.json`.
No new actor, extra harvest, equipment grant or changed return rate is added.
Source positions and normal leashes are recorded in the JSON.

| Target | Exact reference and base | Runtime place | Source position | Normal leash | Existing return |
| --- | --- | --- | --- | ---: | --- |
| Bandit | `36ce1:Skyrim.esm`, base `1e79d:Skyrim.esm` | Interior cell `15224:Skyrim.esm` | `[-2136.4208984375, 1534.8690185546875, -212.0419921875]` | 2,048 | 45 minutes |
| Skeever | `ef60f:Skyrim.esm`, base `23ab7:Skyrim.esm` | Tamriel `3c:Skyrim.esm`, source cell `8dea:Skyrim.esm` | `[99232, 128672, -13824]` | 1,536 | 20 minutes |

Population location identifiers such as `19295:Skyrim.esm` identify a named
place; they are not the runtime cell or worldspace. The future adapter must
use the actual cell/world, exact reference and base, current life and body
identity, species, authored leash, kill attribution and original conversation
and transaction fences. A similarly named bandit or skeever elsewhere does
not count. Existing camp difficulty and animal habitat remain unchanged.

## Reward and activation limits

One finish of each candidate totals **25 gold**. Their cooldowns alone permit
at most **100 gold** in a half-open 24-hour window if both could be completed
by one character. This is an arithmetic upper bound before eligibility,
travel, target availability and competition, not an approved aggregate
economy budget or measured income. These proposed scene rewards would be
created at completion, like legacy scene rewards; they are not supply
purchases from a finite purse.

Before activation, finish the full distinct catalogue and its numerical
aggregate budget and cadence, bounded saved-state representation, generic
target support, original-term recovery and coupled roster admission. Existing
accepted quests keep their original terms. Neither changing these flags nor
putting these IDs into the bundle is permitted as a shortcut. The source test
rejects activation or a runtime import in this incomplete slice.

`node tests/test-merchant-quest-catalogue.js` checks actual rulebook gates,
exact merchant and retained-target bindings, distinct objectives, source
positions and returns, and the inactive state. It does not construct a server,
touch a private world or establish connected acceptance. Claude owns all
operational steps after their source prerequisites are complete.
