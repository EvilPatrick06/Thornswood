# Records

What a release is checked against, kept apart from the scripts that write and
read it (issue #440, phase 8):

- `client-build.json`: the six SkyMP client files built from the fork, by
  hash, and the fork commit they came from. `scripts\release\New-ClientBuildRecord.ps1`
  writes it; Build-Launcher puts it inside the launcher, and Sync-Client and
  Ship refuse a client that is not this build.
- `server-build.json`: the server binary the same way.
  `scripts\release\New-ServerBuildRecord.ps1` writes it and Deploy-Server
  refuses any other binary.
- `steam-build.json`: the public Steam build of Skyrim last looked at and
  accepted. `scripts\dev\Check-Outside.ps1` goes red when Steam moves past it,
  which is the day to try the downgrade on one machine.
- `skyrim-pin.json`: the build of Skyrim a release is pinned to, its
  SkyrimSE.exe size, the size of the newer build Steam hands out, and the
  three depot manifests the Downgrade button asks Steam for (issue #471).
  Publish-Update writes it into version.json and launchers take it from
  there. No script writes this one: it is changed by hand, in the same pull
  request as the script extender, the collection revision, the launcher's
  compiled fallback (Downgrade.cs, Config.cs) and Setup-Thornswood.ps1,
  because a pin move is one release. `tests\test-skyrim-pin.ps1` fails while
  they disagree.
- `signing\`: the code signing setup, with its own README. On since
  27 September: Ship refuses a launcher that is not signed (CONTRIBUTING.md).

Change a record only by running the script that writes it, in the same pull
request as the build or the fork commit it describes.
