# Client provenance at df2ae1f1

The canonical fork commit is `df2ae1f185e84bf9119ffa15d2e3da1622ac77fd`, the
merge of skymp pull request #10 (`thornswood/1268-server-mods-unreachable`)
onto `thornswood/engine-changes`. The only fork files that change from the
previous pin `6725fc778a99b2cf344426afb8158df500b7ad6f` are under
`skymp5-client` (load order check when the server never answers; Thornswood
#1268).

`skymp5-client.js` was rebuilt from that tip. Its sha256 is
`5886e4d2765c986a25b3e34c96372b296c5552f53c1091bf78c9030361f9068a`
(1,443,713 bytes). The other five recorded client runtime files keep the
hashes from the `6725fc77` pin because their sources and build inputs did not
change; see `records\client-provenance-6725fc77.md` for that native evidence.
Sync-Client.ps1 on One copied the new bundle into `C:\Thornswood\Game` from
`1268-skymp\build\dist\client` and verified all six against
`records\client-build.json`.

The server record was retagged to the same tip without an MSBuild. The
6725fc77..df2ae1f1 delta has no `skymp5-server` paths, and
`1268-skymp\build\dist\server` still matches the prior
`records\server-build.json` hashes (scam_native
`37d5bc5de33de11086b1180dcb1e8b64638398bf18c502541025133548ecd8a9`).
New-ServerBuildRecord.ps1 wrote the tip commit onto those hashes so the pin
and both records name one engine (#1200).
