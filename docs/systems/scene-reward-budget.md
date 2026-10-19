# Source-only expanded scene reward accounting

`game/scene-reward-budget.js` projects a proposed accounting record. It has no
runtime import, writes no state and grants no gold. Existing quests and their
accepted terms are unchanged. The complete merchant catalogue, account and
world economy assessment, full saved-state capacity, objective proof and
runtime integration remain unfinished.

For future expanded scenes, the proposed allowance is 150 gold per character
in a half-open rolling 24-hour window. This is a source design value, not an
active or account-wide cap. At acceptance, reserve the original reward of
10 through 150 gold. Recent payouts plus all outstanding reservations cannot
exceed 150. There can be at most three held scenes. Reservations never expire;
completion moves their original amount into payout history, while cancellation
releases it without payment. Personal cooldowns belong to the future quest
controller and are not implemented here.

The record is `{v:1,clock,serial,held,paid}`. Each held ID maps to
`{gold,at,token}`. The counter never resets when reservations empty, and both
completion and cancellation require the exact reservation token. An old
request cannot consume a newer reservation under the same quest ID. Paid
entries are ordered `[timestamp,gold]` pairs. Their minimum amount limits an
active window to 15 entries. Only expired entries owned by this accounting
record are removed in a successful projection; no legacy fields or kill
history enter this module.

| Operation | Successful result | Required caller work |
| --- | --- | --- |
| `reserve(state,id,gold,now)` | Detached `next` and new `token` | Validate the offer and original terms; atomically save acceptance and reservation |
| `complete(state,id,token,now)` | Detached `next` and original `gold` | Prove the objective and atomically save completion, accounting and that inventory reward |
| `cancel(state,id,token,now)` | Detached `next` and zero `gold` | Apply original cancellation rules and atomically release the reservation |
| `inspect(state,now)` | Paid, reserved and available gold, plus open count | Display only after the current ownership and conversation checks |

Every refusal returns `{ok:false,why}` without changing its inputs. Missing
state starts an empty budget; present null, unknown fields/versions, malformed
or inherited evidence and accessors refuse. Timestamps and counters must be
safe integers. Time cannot move backward. Saved accounting must be consistent
at its saved clock before expiry is considered. Payouts exactly 24 hours old
are outside the window. Successful outputs are detached from their inputs.

The future controller must preserve unknown quest fields and keep accounting,
accepted original terms, progress and any inventory change in the same actor
property transaction. Two projections from one snapshot are alternatives;
the existing native expected-record CAS must admit only one. A projection
does not establish ownership, eligibility, objective completion, durability
or authority to pay. Never write it separately or infer a committed reward
from a lost reply. Existing legacy work is not retroactively charged.

`node tests/test-scene-reward-budget.js` exercises arithmetic, boundaries,
tokens, corruption and small operation sequences. The synthetic transaction
fixture in `node tests/test-quest-transactions.js` carries a proposed budget
through the real JavaScript adapter with modeled native comparisons, including
competing reservations, an inventory refusal and a stale repeated payout.
These are source tests, not a game/server or connected acceptance test.
Claude owns any later operational step after the full prerequisites land.
