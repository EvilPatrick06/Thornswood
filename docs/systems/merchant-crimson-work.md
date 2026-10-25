# Crimson work in Blackreach

The Winterhold Alchemist (`1c1aa:Skyrim.esm`, base `1c19c:Skyrim.esm`)
offers the original crimson work to a Gatherer. Another Alchemist does not
repeat this new offer. This uses eight existing crimson nirnroot activators;
it adds no NPC, plant, crop, planting, cultivation or growth mechanic.

| Rule | Amount |
| --- | --- |
| Existing sources | 8 |
| Yield per successful draw | 1 Crimson Nirnroot (`b701a:Skyrim.esm`) |
| Shared return at each source | 10 minutes |
| Personal limit while open | 8 |
| Turn-in consumes | 3; the remainder stays in the pack |
| Rest after completion | 12 hours |
| Abandonment | Consumes the entire outstanding draw, no personal rest |
| Gold or purse refill | None |

Gatherer standing and any rank required by the existing plant table apply on
every draw. The hand-written crimson row has no higher rank or tool rule.
The live source must be enabled, retain its exact base `b6fb9:Skyrim.esm`,
and stay within 128 units of its winning recorded position in Blackreach
(`1ee62:Skyrim.esm`). The character must be in that world and within 400 units
of that source. A deleted source or another plant cannot substitute.

| Existing reference | Winning source position |
| --- | --- |
| `f3b51:Skyrim.esm` | `[6737.6865234375, 7109.41552734375, 985.5054321289062]` |
| `f3b54:Skyrim.esm` | `[1864.7017822265625, 1518.39697265625, 992.927490234375]` |
| `f3b5d:Skyrim.esm` | `[22377.798828125, 13522.2265625, 1997.456787109375]` |
| `10ffac:Skyrim.esm` | `[22487.3359375, 11976.064453125, 2067.111572265625]` |
| `10ffaf:Skyrim.esm` | `[20627.134765625, 7700.14599609375, 1233.974609375]` |
| `10ffb0:Skyrim.esm` | `[17847.103515625, 6733.818359375, 1515.8726806640625]` |
| `f3b56:Skyrim.esm` | `[20210.73828125, 5823.5986328125, 970.6233520507812]` |
| `10ffa9:Skyrim.esm` | `[22159.330078125, 16684.431640625, 1486.5172119140625]` |

The eight fixed Skyrim reference IDs are intercepted before ordinary activation
and in direct harvesting. This remains true when the quest service fails or a
source is replaced by another base. Other plants do not consult this quest's
service. Runtime source validation checks native REFR, ACTI, INGR and WRLD
records, NAME mapping and live position. The source manifest pins the measured
winning placements and the 103-plugin population load order used to read them.

The existing native metadata/inventory operation grants the ingredient and
increments the quest draw together. The existing shared resource stock reserves
the plant before that operation. A definite refusal restores its reservation;
an unknown native result keeps it reserved and refuses further unsafe work.
Successful draws alone receive ordinary gathering credit. No second item grant,
repair loop, extra spawn, gold reward or changed ordinary plant yield is added.

Automated source and actual harvest/activation fixtures cover exact offers,
standing, source failures, shared depletion, caps, extras, abandonment and
concurrent writes. Automated checks do not establish connected playtest results.
Merging the source does not make it live; that needs a release.
