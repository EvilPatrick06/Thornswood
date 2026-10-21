# The mammoth ground

The Whiterun Cook (`1a66e:Skyrim.esm`) offers this work to Master Hunters.
The three existing mammoths remain server-owned population sources. No extra
animals are spawned and their normal population limits remain in force.

| Reference in Skyrim.esm | Original position | Normal leash | Return |
| --- | --- | --- | --- |
| `33fa6` | `[519.6705932617188,3950.623291015625,-5856]` | 2048 | 240 minutes |
| `846ea` | `[-1923.1177978515625,3608.172119140625,-6275.24169921875]` | 1536 | 240 minutes |
| `846eb` | `[-1810.09521484375,2847.945556640625,-6141.3271484375]` | 1536 | 240 minutes |

All three use base `dd641:Skyrim.esm` in Tamriel. The quest ground also limits
x to -2500 through 1000 and y to 2000 through 4500. A corpse must be inside
both its original leash and that rectangle, with the Hunter within 400 units.
Original native ACHR NAME/DATA, live base/world, server control and nonhuman
ownership must agree. Native life and body identities prevent an earlier
corpse or replaced actor from supplying a new draw.

The existing hunting table gives 1 through 5 Mammoth Tusks and independently
1 through 5 Mammoth Snouts per Master draw. The quest uses those same rolls.
One native corpse supplies one shared draw across all Hunters. A successful
draw receives ordinary hunting credit. Nothing gives extra credit or goods
for repeated presses.

The open work records at most three exact corpse bundles. Returning to the
same Cook consumes both goods from the first corpse, leaves the other draws
in the pack, closes the quest and starts its 24-hour rest. The panel states
the exact two counts needed. Abandon consumes all outstanding drawn goods
and starts no rest. These are ordinary hunting goods, with no new trophy,
gold reward or merchant purse refill. As with other scarce work, spent goods
must be replaced before the outstanding return or abandon can complete.

The native inventory/quest commit grants both goods and records their body
receipt together. It rechecks source and Master standing at commit, and
completion rechecks the live conversation with the same Cook. Definite
refusal releases only its own unchanged corpse reservation. An unknown save
outcome retains that claim and revokes further transactions. A source fence
that reenters another harvest cannot overwrite its newer reservation.

The actual native addon fixture verifies all three original source records.
Regressions cover native body replacement, bounds/leash/reach, class, malformed
or sparse bundles, duplicate draws across characters, respawn, restart,
completion/extras, abandon, failed and unknown writes, final conversations,
real loot/activation routing and reentrant reservation/rollback. Other hunting
and gathering sources keep their existing behavior. Claude owns Dev delivery
and connected acceptance; source checks do not claim it has been deployed.
