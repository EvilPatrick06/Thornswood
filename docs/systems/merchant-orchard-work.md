# Orchard work

The Whiterun Cook (`1a66e:Skyrim.esm`) offers this work to Expert Farmers.
These are the ten existing Chillfurrow Farm apple trees outside Whiterun,
all in Tamriel, using `141081:JK's Whiterun's Outskirts.esp` and ordinary
Red Apples (`64b2e:Skyrim.esm`). No trees, planting rules or automatic
regrowth are added.

| Reference in JK's Whiterun's Outskirts.esp | Original position |
| --- | --- |
| `141084` | `[32734.08984375,-10301.1953125,-4197.89208984375]` |
| `141083` | `[32458.767578125,-10103.2978515625,-4139.51171875]` |
| `141082` | `[32243.041015625,-11261.99609375,-4217.8154296875]` |
| `141080` | `[32016.349609375,-11102.0615234375,-4172.181640625]` |
| `1699d7` | `[32340.267578125,-12131.546875,-4276.1220703125]` |
| `1831a6` | `[29450.37890625,-12450.99609375,-4248.1787109375]` |
| `1831a3` | `[30332.349609375,-12917.0849609375,-4313.6650390625]` |
| `1699d6` | `[32620.939453125,-12295.2822265625,-4265.97998046875]` |
| `1831a0` | `[30051.677734375,-12753.349609375,-4311.63037109375]` |
| `1831ad` | `[29923.47265625,-13003.6845703125,-4364.17578125]` |

Exact native references, original positions, FLOR base and apple produce
are checked at startup and harvest. Live sources stay within128 units of
the original point, and the Farmer stays within400 units of the source.
Missing source evidence closes this work.

Existing Farmer rules apply: shovel, profession rank, farm/building claims
and seasonal growth. An untouched standing tree gives one apple once.
An emptied plot must be sown with an apple using the existing interaction.
The crop's base growth is75 minutes, multiplied by its sower's rank:
Expert0.7 gives52.5 minutes, Master0.55 gives41.25 minutes. Expert crops
pause in autumn and winter under the existing season rules. Ripe yield
belongs to the sower's rank: four for Expert, five for Master.

Accepted work records the entire harvest quantity with the inventory award.
The personal allowance is ten apples; a full ripe yield that would exceed
the remaining allowance is refused and left ripe. Return four to the same
Cook, keep extras and start twelve hours of rest. Abandon consumes all
outstanding drawn apples without a rest. As with other scarce work, spent
apples must be replaced before the return or abandon can complete. There
is no gold reward, purse refill or separately generated quest apple.
Two completions in24 hours can retain at most twelve extra apples per
Farmer, before sowing costs; ordinary shared harvests are not duplicated.

Only these ten references keep their authoritative plot state in the private
`orchard-plots.json`, with initialization evidence and an integrity hash.
Normal and quest harvesting, sowing and plot inspection use that same
state. Other farms continue using their existing native plot properties.
This is disposable alpha initialization, with no migration of accepted work.

The existing native whole-file writer clears a plot before the character's
atomic goods/quest commit. The synchronous store lock refuses reentrant
sowing or harvesting. A definite refused award restores the source; an
unknown result closes the store until reload and retains the cleared plot.
Normal process restart reads that authoritative cleared state, preventing
the asynchronously saved native plot from reviving an awarded crop. An
abrupt failure can cost a crop. The native writer flushes file contents and
atomically replaces the file; physical power-loss durability of directory
renames is not established by this change.

Final award checks retain the original character identity, source, claims,
shovel, rank and verifiable seasonal growth. Missing property/season
services refuse quest harvests. Identity is checked again before each
post-success claim refresh, farming credit and tool wear.

Offline native proof and isolated Farmer/quest fixtures cover these paths.
Required CI, source merge and Claude's matching Dev delivery remain
separate from connected acceptance. No game playtest is claimed.
