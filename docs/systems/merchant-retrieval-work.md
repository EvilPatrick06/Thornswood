# Merchant retrieval work

The original seven retrievals use one appointed specialist each. They keep
their existing open eligibility, fixed payment and completion rest. The ranked
commission catalogue separately supplies profession and class work at all four
levels. A retrieval gives one dedicated, weightless, valueless quest item.

| Work | Offering specialist | Source reference | Return specialist | Gold | Rest |
| --- | --- | --- | --- | --- | --- |
| Satchel | Whiterun Woodworker | `17dfdc:JK's Whiterun's Outskirts.esp` | Same | 20 | 3 hours |
| Ledger | Whiterun Enchanter | `17208:Thornswood-Content.esp` | Same | 30 | 6 hours |
| Signet | Whiterun Smith | `c2a35:Skyrim.esm` | Same | 40 | 8 hours |
| Locket | Falkreath Tailor | `3906d:Skyrim.esm` | Same | 45 | 10 hours |
| Case | Whiterun Tailor | `ea73b:Skyrim.esm` | Same | 50 | 8 hours |
| Dispatch | Whiterun Cook | `547e8:Skyrim.esm` | Eastmarch Cook | 60 | 12 hours |
| Seal | Whiterun Alchemist | `53ff6:Skyrim.esm` | Same | 70 | 14 hours |

Exact actor references, original source bases, cells/worlds, coordinates,
offering/return identities and winning plugin evidence are recorded in
`game/data/merchant-retrievals.json`. Seven MISC items occupy
`17000` through `17006` in Thornswood-Content.esp. The ledger is an activator
with no book or skill effect. The case cannot open as a container.

`Build-MerchantRetrievalSources.py` reads the complete pinned load order. Every
external plugin, including a repository copy, must match its pinned SHA. Only
the authored Content prerequisite uses its separately verified current bytes.
The manifest pins each winning plugin index, raw reference ID and SHA of all
ordered native record fields. The runtime source validator also verifies
original NAME/DATA, enabled state, source/item/space types, source drift within
128 units and approach within 400 units. Native lookup cannot expose parent
CELL groups; the build evidence pins those, while runtime checks the live space.

The opt-in `tests/native-retrieval-sources.js` compares the actual compiled
native lookup with all seven proofs in an isolated offline test fixture. It
never connects to Main or Dev. The ordinary tests use the same measured native
record bytes and verify replacement, malformed provenance, distance, identity
and zero-value/weight refusal paths. CI also exercises truncated record/group
envelopes, ordered fields and compressed lengths/trailing bytes.

This source-evidence section exports the validated manifest, source factory and
closed seven-item transfer policy. It does not activate source pickup, merchant
offers or transfer hooks. Their atomic pickup/return/abandon and final live
conversation checks belong to the following runtime section. There are no new
NPCs, purse refills, migration prerequisites or invented farming mechanics.
