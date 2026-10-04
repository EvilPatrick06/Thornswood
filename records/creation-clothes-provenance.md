# Creation clothing runtime provenance

Native source: 731dfe049606e9223df229b97b43d720847d8518, merged fork PR 13.
Previous source: 52953b43c813d6993cd5d4178a97ab0520d7ad17.

`git diff 52953b43 731dfe04 --name-only` contains only two client TypeScript files and the new actual-handler regression test. All C++, Papyrus, server TypeScript, lockfiles and configure/build sources are unchanged. The five native/Papyrus client files retain their previous recorded hashes and build timestamps. Only the client JavaScript is newly compiled, from the clean merged source using the installed lockfile dependencies. The complete server build retains identical bytes and original build time; the new record associates that unchanged source with the same merged fork commit. No timestamp was advanced to pretend a native rebuild occurred.

The actual-handler test, strict TypeScript checking and webpack compilation pass. The regression fixture runs the actual client service and inventory diff, including delayed queued work and native base reset. Fresh and independent reviews were reconciled with tests. Ambiguous wrong item variants remain closed instead of accepting a false equipment readback; exact-instance repair is not claimed. Connected visual acceptance remains pending.
