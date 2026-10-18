# Hair dye

Issue #2675. A dye is made at a cooking spot from things people already
gather, and it changes the colour of somebody's hair in the world. Nobody's
hair changes without their own press. The colours, what makes them and who
may make them are the staff's list, `game/data/hair-dyes.json`; the code
names none of it.

## What a dye does

- **Making one.** At a cooking spot (the same bench keyword water boils at),
  carrying a bottle of water and one dye's inputs, a dye steeps for
  `steepSeconds`, a minute in the list as it ships. If the pack holds the
  inputs of more than one dye, the first in the list is made.
- **What it is carried as.** One vanilla misc record, the Bowl
  (`98626:Skyrim.esm`), with the dye's name on the entry, the way a deed is
  a named entry. Nothing else in the game reads that record, so a plain bowl
  is never a dye and a dye is never a plain bowl.
- **The colour.** Each channel of the hair colour goes `strength` of the way
  from the colour already there to the dye's colour, then moves by up to
  `wander` either way. The same dye on two heads comes out a little different,
  and never quite clean. A second coat goes on top of the first.
- **Washing out.** A dye marked `wash` has no colour of its own. It goes
  `strength` of the way back to the colour that character was made with,
  which the server keeps from their first dye on.
- **Hair, beard and brows.** The game gives a character one hair colour, so a
  dye colours all three.
- **No fading.** A colour stays until somebody dyes or washes it.

## The list

| Field | What it is |
| --- | --- |
| `item` | The record a dye is carried as. |
| `steepSeconds` | How long a dye steeps, in real seconds. |
| `steepAt` | The bench keyword a dye steeps at. |
| `who` | Who may steep: `anyone` true, or `halves`, each half at the lowest rank that may, the same shape as the benches. Ships as anyone. |
| `dyes` | Each dye: `id`, `name` (what the entry is called), `colour` (#rrggbb, lower case) or `wash: true`, `strength` (above 0, at most 1), `wander` (0 to 64), and `inputs` (each a record and a count). |

A list with any problem is refused whole, never half used: a key nobody
reads, a colour that is not #rrggbb, two dyes with one id or name, an input
named twice, or a dye that can never be made because an earlier dye takes
less of the same things.

## Where this is

The list and the colour sums only, in `game/hair-dye.js`, checked by
`tests/test-2675-hair-dye.js`. Nothing in play uses them yet: the steep, the
K panel's button, dyeing somebody else with their Accept, and the one write
of the new colour are the next slice.
