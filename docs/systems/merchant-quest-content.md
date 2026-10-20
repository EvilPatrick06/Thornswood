# Dedicated merchant quest objects

`quest-content.json` gives the authoring inputs for seven inventory tokens,
eight longfin markers and a ledger source. `Add-ContentRecords.py` writes them
into the repository's Content plugin. This section supplies objects only;
the remaining retrieval and longfin interactions require their runtime code.
No new actor, container contents, recipe, skill book or farming mechanic is added.

| Quest token | Local reference | Model source |
| --- | --- | --- |
| Guild Satchel | `17000:Thornswood-Content.esp` | Sack `97f54:Skyrim.esm` |
| Guild Ledger | `17001:Thornswood-Content.esp` | Book `ed045:Skyrim.esm` |
| Guild Signet | `17002:Thornswood-Content.esp` | Silver ring `3b97c:Skyrim.esm` |
| Guild Locket | `17003:Thornswood-Content.esp` | Necklace `877f1:Skyrim.esm` |
| Sealed Guild Case | `17004:Thornswood-Content.esp` | Strongbox `ea722:Skyrim.esm` |
| Sealed Guild Dispatch | `17005:Thornswood-Content.esp` | Parchment `33761:Skyrim.esm` |
| Guild Seal | `17006:Thornswood-Content.esp` | Parchment `33761:Skyrim.esm` |

These are MISC tokens with zero value and weight, no vendor keywords, no
equipment data, scripts, spells, recipes, book effects or container interface.
Only the verified model path and bounds come from the named source. They do
not copy vanilla quest items. The later retrieval controller must enforce
non-sale and transfer/drop restrictions before enabling these offers.

The ledger source is ACTI `17100:Thornswood-Content.esp`, with the book's
model and bounds. Its placement `17208:Thornswood-Content.esp` is in Riverwood
Trader CELL `133c9:Skyrim.esm` at `[173.47137451171875,-99.40931701660156,329.3854064941406]`.
This is12 units above the measured upstairs book anchor `1060aa:Skyrim.esm`.
The original book remains; activating the dedicated source grants no skill.

| New longfin reference | Original clam anchor | Source CELL |
| --- | --- | --- |
| `17200:Thornswood-Content.esp` | `100420:Skyrim.esm` | `1915:Skyrim.esm` |
| `17201:Thornswood-Content.esp` | `100422:Skyrim.esm` | `1915:Skyrim.esm` |
| `17202:Thornswood-Content.esp` | `100421:Skyrim.esm` | `1915:Skyrim.esm` |
| `17203:Thornswood-Content.esp` | `100423:Skyrim.esm` | `1934:Skyrim.esm` |
| `17204:Thornswood-Content.esp` | `fbc5c:Skyrim.esm` | `1935:Skyrim.esm` |
| `17205:Thornswood-Content.esp` | `fb01f:Skyrim.esm` | `1935:Skyrim.esm` |
| `17206:Thornswood-Content.esp` | `faf95:Skyrim.esm` | `3d8c:Skyrim.esm` |
| `17207:Thornswood-Content.esp` | `faf60:Skyrim.esm` | `3d6a:Skyrim.esm` |

All eight use the existing longfin FLOR base `154a5:Thornswood-Content.esp`
in Tamriel. Each final point is48 units east of its measured clam anchor,
at the same height, with zero rotation. Exact final positions are in the
manifest. Native CELL grids verify that every shifted point remains in its
declared exterior cell. The clams and their stock remain independent.

Source measurement used the enabled winning references under the population
catalogue's103-plugin order. The ledger CELL's Embers, populated-town and
Last overrides were inspected: their lighting, ownership and other fields
match the canonical master record after localized names are written in plain.
The five exterior CELLs have no non-master override apart from our new parent
records. No weather, ownership, lighting or hold changes are intended.

Authoring refuses an existing ID with another editor identity. A final pass
rejects duplicate record IDs and requires the exact union of station and
quest placements. Station checks retain their existing assertions; separate
tests verify every new field, item and placement, plus malformed declarations
and record collisions. Rendering and connected gameplay are not verified here.

Claude must deliver matching Content bytes to Dev's server before releasing
them to clients, using the normal content fingerprint checks. Runtime offers
stay disabled until their source validation succeeds. The next runtime section
must be released only with the matching content fingerprint. No install,
release, server command, Vortex action or playtest is part of source authoring.
