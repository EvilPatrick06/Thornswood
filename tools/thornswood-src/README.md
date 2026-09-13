# Thornswood content pipeline

Everything here regenerates `Thornswood-Content.esp` and `gamemode.js`. It is
checked in because the last set of intermediates did not survive, and rebuilding
them from the shipped artifacts cost an afternoon.

## What reads what

    index.py          TES4 walker. Records, GRUPs, byte ranges, zlib bodies.
    content.py        The book text, the donor field bytes, the gear tables.
    patch_esp.py      Reads the shipped .esp, rewrites the fifteen Keizaal
                      manuals so they have a name/mesh/text, appends the
                      fourteen new books, fixes the GRUP sizes and the header.
    validate.py       Structural check on the result. Every GRUP size exact,
                      every field length sums to its record, no record claiming
                      a master index that does not exist.

    body.js           The gamemode as it was before creation existed.
    chargen_body.js   The creation module on its own.
    weave.py          Splices the module into the body at six named points and
                      refuses to guess if any of them is not found exactly once.
    build.py          Inlines the four data blobs into gamemode_body.js.
    test.js           82 assertions against a stubbed mp. Run it on every change.

## Order

    python3 patch_esp.py && python3 validate.py
    python3 weave.py && python3 build.py && node test.js

`weave.py` reads `body.js` and writes `gamemode_body.js`, so it is not
idempotent against its own output: edit `body.js` or `chargen_body.js`, never
`gamemode_body.js`.

## Where the data came from

`data.json`, `stations.json`, `manuals.json` and `items.json` were recovered out
of the deployed `gamemode.js` rather than rebuilt from `respawn-holds.json` and
`thornswood-descs.json`, which are gone. They are identical to what the server
was running, with two changes made in `build.py` and visible in its output:

  * the alchemy track gained a Novice manual. Keizaal shipped Advanced, Expert
    and Master and no Novice, so tier 1 was unreachable.
  * every arrival rotation was converted from radians to degrees. They were read
    straight out of the markers' REFR DATA fields, which store radians, and both
    properties they feed (`spawnPoint` and `locationalData`) take degrees. Every
    value in the table was a multiple of pi/2, so this had been landing everyone
    facing roughly north since the respawn system shipped.
