# Client provenance at 47da3f34

The canonical fork commit is `47da3f34973828e46fad1aaf10616bb7ef2df8ad`, the
merge of skymp pull request #10 (`thornswood/1268-server-mods-unreachable`)
onto `thornswood/engine-changes`. The only fork files that change from the
previous pin `51faac39597ac235d08179b494e5de23aadcdcd9` are under
`skymp5-client` (load order check when the server never answers; Thornswood
#1268).

`skymp5-client.js` was rebuilt from that tip. Its sha256 is
`5886e4d2765c986a25b3e34c96372b296c5552f53c1091bf78c9030361f9068a`
(1,443,713 bytes). The other five recorded client runtime files keep the
hashes from the `51faac39` pin because their sources and build inputs did not
change; see `records\client-provenance-51faac39.md` for that native evidence.
Sync-Client.ps1 on One copied the new bundle into `C:\Thornswood\Game` from
`1268-skymp\build\dist\client` and verified all six against
`records\client-build.json`.

The server record was retagged to the same tip without an MSBuild. The
51faac39..47da3f34 delta has no `skymp5-server` paths, and
`1268-skymp\build\dist\server` still matches the prior
`records\server-build.json` hashes (scam_native
`37d5bc5de33de11086b1180dcb1e8b64638398bf18c502541025133548ecd8a9`).
New-ServerBuildRecord.ps1 wrote the tip commit onto those hashes so the pin
and both records name one engine (#1200).
