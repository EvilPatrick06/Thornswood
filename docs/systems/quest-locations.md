# Custom quest places

Patrick delegated the remaining place choices on 10 October 2026. These are
the selected existing places, checked against the installed 102-plugin order,
the winning enabled reference records, `resource-locations.json`, and the kept
cast in `npc-population.json`. Counts and rewards come from [Custom quests](quests.md).

This is the binding specification. The four rare-mine offers have an
implementation in PR2065. The six kill contracts have bindings in PR2130;
their matching native and gamemode changes still need to be released by
Claude. The [pearl bed](merchant-pearl-bed.md) now has its source interaction in code. Four other scarce offers and seven retrieval offers still need their resource or scene interaction connected before they can be taken. A
reference in this document does not mean the quest is deployed or playable.

Descriptors are local hexadecimal IDs followed by their source plugin. They
stay the same when full or light plugin indices change. Unless another plugin
is written, the suffix is `:Skyrim.esm`. A source reference is an existing
object; an anchor is only a verified position for a new quest object. Never
activate the original object as a different kind of resource by mistake.

## Scarce work

The draw limit is personal to the open quest. Completing consumes the ask and
keeps the remainder; abandoning consumes the entire outstanding draw and
starts no cooldown. These limits do not increase the world's ordinary stock
or its population. Each harvest must check both the quest and the profession's
normal rank and tool rules. Ordinary harvesting must not bypass a scarce gate.

| Work | Existing place | Exact source references or anchors | Ask / personal limit | Cooldown after completion |
| --- | --- | --- | --- | --- |
| Ebony | Raven Rock Mine | Cell `142fc:Dragonborn.esm`; every ebony vein inside it | 4 / 12 ore | 24 hours |
| Gem | White Ridge Sanctum for ruby; Highpoint Tower for sapphire and amethyst; Kolbjorn Barrow for emerald | Cells `3c7f5`, `184f0`, `142ee`, all `:Dragonborn.esm`; only veins of the chosen gem | 2 / 6 gems | 24 hours |
| Stalhrim | Kolbjorn Barrow | Cell `142ee:Dragonborn.esm`; its stalhrim deposits | 3 / 8 | 24 hours |
| Heart stone | Coldcinder Cave | Cell `3929e:Dragonborn.esm`; its heart-stone deposits | 3 / 8 | 24 hours |
| Longfin | Haafingar's northern sea coast | Coastal anchors `100420`, `100422`, `100421`, `100423`, `fbc5c`, `fb01f`, `faf95`, `faf60`; see the marker requirement below | 2 / 8 one-fish spots | 12 hours |
| Pearl bed | Raven Rock coast | `3828e`, `3919c`, `38894`, all `:Dragonborn.esm`; source cells `eed7`, `ef19` | 1 / 3 one-pearl spots | 8 hours |
| Crimson | Blackreach, from the sewer entrance towards Alftand's lift and the southern fungus grounds | `f3b51`, `f3b54`, `f3b5d`, `10ffac`, `10ffaf`, `10ffb0`, `f3b56`, `10ffa9` | 3 / 8 plants | 12 hours |
| Mammoth ground | Bleakwind Basin and its immediately adjacent western tundra | Existing mammoths `33fa6`, `846ea`, `846eb`; see the ground boundary below | Dress 1 / 3 existing mammoths | 24 hours |
| Orchard | Chillfurrow Farm's orchard outside Whiterun | Red apple trees `141084`, `141083`, `141082`, `141080`, `1699d7`, `1831a6`, `1831a3`, `1699d6`, `1831a0`, `1831ad`, all `:JK's Whiterun's Outskirts.esp` | 4 / 10 apples | 12 hours |
| Geode | Blackreach's soul-gem deposits | `10fc57`, `10eb24`, `10e994`, `10e955`, `10e8bb`, `10fc4c`; all use base `10e93b` | 2 / 6 empty petty soul gems | 12 hours |

The longfin base `154a5:Thornswood-Content.esp` exists, but the installed order
contains **zero placements** of it. The eight anchors above are existing clam
positions in sea water. They are not longfin spots yet. Add eight distinct
longfin markers, with their own final descriptors recorded here, before
enabling this offer. Keep the original clam sources and their shared stock.
The Fisher page requires master rank for longfin; the quest's broad Fisher
label does not remove that rank gate.

The pearl sources use base `3828c:Dragonborn.esm` and yield `854fe:Skyrim.esm`.
The crimson sources use base `b6fb9` and yield `b701a`. The red apple sources
yield `64b2e`. The geode's reward is the empty petty soul gem `2e4e2`, not the
filled `2e4e3`; all six chosen deposits are the existing soul-gem geode base,
not a ruby or other ordinary gem vein.

For the mammoth ground, the three source positions are approximately
`[520,3951,-5856]`, `[-1923,3608,-6275]`, and `[-1810,2848,-6141]` in Tamriel.
Use the exact three identities and the ground rectangle x -2500 to 1000,
y 2000 to 4500, with the normal leash. Do not accept other mammoths elsewhere
in the Tamriel worldspace. The existing cast returns after 240 minutes; the
quest's personal 24-hour cooldown is separate. Do not spawn three more.

Exterior references retain their source CELL in the plugin, but the runtime
reports a worldspace such as Tamriel. Binding a quest to `3c:Skyrim.esm` alone
would accept the whole wilderness. Exterior bindings must check the exact
source reference and its ground boundary. Persistent CELL `d74` is storage
organization, not a playable quest area.

For stationary exterior sources, use a sphere of radius 128 game units
around each winning source-record position, plus the exact reference and
worldspace. This applies to the pearl, crimson, orchard and geode sources,
the satchel sack, and the eventual longfin markers. These are per-source
bounds, not a radius around the whole route. Keep the normal interaction
reach check between the character and that source as well. Longfin, orchard
and satchel use Tamriel `3c:Skyrim.esm`; pearls use Solstheim
`800:Dragonborn.esm`; crimson and geodes use Blackreach `1ee62:Skyrim.esm`.
Record each new longfin marker's final position and reference when placing it;
the anchor's current clam identity never passes as that marker.

## Scene work

Retrievals require one dedicated, nonsellable quest item. Their source
containers remain the ordinary objects listed below. A draw and its quest
record must commit together. Finish consumes the item and pays the listed
gold in the same commit; abandon consumes it without gold or a cooldown.
Do not use an unrelated vanilla quest item or a skill book as the reward.

| Work | Offering hold and existing place | Exact object or allowed actors | Gold | Cooldown |
| --- | --- | --- | --- | --- |
| Satchel | Whiterun, the roadside sack outside the city | Sack `17dfdc:JK's Whiterun's Outskirts.esp`, base `97f54:Skyrim.esm`, source CELL `961b`; approximate position `[17713,-9894,-4386]` | 20 | 3 hours |
| Ledger | Whiterun, Riverwood Trader's upstairs books | Shelf-book anchor `1060aa`, CELL `133c9`, position `[173,-99,317]`; add a dedicated ledger that grants no skill | 30 | 6 hours |
| Signet | Whiterun, Redoran's Retreat | Chest `c2a35`, CELL `15224` | 40 | 8 hours |
| Locket | Falkreath, Bleak Falls Temple | Urn `3906d`, CELL `371de` | 45 | 10 hours |
| Case | Whiterun, Whiterun Stables | Strongbox `ea73b`, CELL `165a0`; the dedicated case cannot open | 50 | 8 hours |
| Dispatch | Take in Whiterun; deliver to an Eastmarch guild trader | Chest `547e8`, CELL `43fab`, Halted Stream Camp; destination hold `eastmarch` | 60 | 12 hours |
| Seal | Whiterun, Silent Moons Camp's ruined interior | Chest `53ff6`, CELL `15211` | 70 | 14 hours |
| Wolf | Whiterun, White River Watch | Wolf `86a88`, CELL `151f9`; one kill | 25 | 3 hours |
| Sabre cat | Eastmarch, Lost Knife Hideout | Sabre cat `1ce7b`, CELL `1a337`; one kill | 40 | 6 hours |
| Camp | Whiterun, Halted Stream Camp | Bandits `50533`, `50549`, `5054a`, `5054e`, source CELLs `9143` and `9144`; three distinct kills in the camp ground | 45 | 6 hours |
| Bear | The Rift, Pinepeak Cavern | Bear `19f3e`, CELL `15230`; one kill | 50 | 8 hours |
| Barrow | Falkreath, Bleak Falls Temple | Draugr `1d219`, `380b3`, `380b5`, `380b7`, `380b8`, CELL `371de`; one kill | 60 | 10 hours |
| Giant | Whiterun, Bleakwind Basin | Giants `33f9f`, `33fa3`, source CELL `99a2`; one kill inside their camp ground | 100 | 18 hours |

Only a trader in the offering hold gives the local scene. The dispatch alone
has a different destination hold. A kill must match the kept NPC's source
reference, species, current life, and location when it dies. Repeated death
notifications for the same life count once. Leaving the named place does not
make a kill elsewhere count. A dragon never matches a contract.

Halted Stream's camp ground is x 14000 to 18000, y 16000 to 22000 in Tamriel.
Bleakwind's giant ground is x -500 to 2500, y -1000 to 3000 in Tamriel.
Both also require the exact actors listed above and their normal authored
leashes. The bounds are horizontal; the death must remain in Tamriel, not an
interior or another worldspace. The source CELL list alone is insufficient.

These scene contracts add no enemy spawns and change no dungeon tier,
camp difficulty, ordinary loot, population cap, or NPC return clock.
Connected acceptance is tracked separately from these source-record choices.

The [crimson work](merchant-crimson-work.md) now connects its eight existing Blackreach plants to the Winterhold Alchemist, using the original Gatherer rules, shared ten-minute returns, ask3/cap8 and12-hour personal rest. No orchard planting or cultivation mechanics are included. Source activation still requires Claude's release step.
