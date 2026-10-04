# Creation clothing runtime provenance

Native source: 32b23c58e50d908497b58d7f8f90e12bd1629fdb, merged fork PR 13.
Previous source: ae054a7ab384e83634755a078c58baf4bd81d610.

`git diff ae054a7a 32b23c58 --name-only` contains only two client TypeScript files and the new actual-handler regression test. All C++, Papyrus, server TypeScript, lockfiles and configure/build sources are unchanged. The five native/Papyrus client files retain their previous recorded hashes and build timestamps. Only the client JavaScript is newly compiled, from the clean merged source using the installed lockfile dependencies. The complete server build retains identical bytes and original build time; the new record associates that unchanged source with the same merged fork commit. No timestamp was advanced to pretend a native rebuild occurred.

The actual-handler test, strict TypeScript checking and webpack compilation pass. The regression fixture runs the actual client service and inventory diff, including delayed queued work and native base reset. Fresh and independent reviews were reconciled with tests. Ambiguous wrong item variants remain closed instead of accepting a false equipment readback; exact-instance repair is not claimed. Connected visual acceptance remains pending.
