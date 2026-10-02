# Records

What a release is checked against, kept apart from the scripts that write and
read it (issue #440, phase 8):

- `client-build.json`: the six SkyMP client files built from the fork, by
  hash, and the fork commit they came from. `scripts\release\New-ClientBuildRecord.ps1`
  writes it; Build-Launcher puts it inside the launcher, and Sync-Client and
  Ship refuse a client that is not this build.
- `server-build.json`: every server file the fork builds the same way (the
  binary, the JavaScript half the server runs, its map and the rest
  `scripts\deploy\ServerBuild.ps1` names), and the one fork commit.
  `scripts\release\New-ServerBuildRecord.ps1` writes it (Build-Server runs it),
  and Export-ServerPayload, Publish-Server, Deploy-Server and the installer on
  the box refuse any server file that is not this build.
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
- `skyrim-files.json`: every file of the pinned build, 46 on 1.6.1170, with
  its bytes, SHA-1 and depot, read out of Steam's own manifests of the three
  depots `skyrim-pin.json` names by `scripts\release\New-SkyrimFilesRecord.ps1`
  (issue #1232). Build-Launcher puts it inside the launcher, and Thornswood's
  own folder takes a file from the Steam copy as Skyrim's own only when it is
  on this list, so a mod put into the Steam copy by hand never gets in. Run
  the script again in the same pull request as a pin move;
  `tests\test-skyrim-pin.ps1` fails while the two disagree.
- `update-creation-club.json`: the Creation Club records Bethesda keeps in
  Update.esm (354 on build 1.6.1170, editor ids starting cc). Every Special
  Edition has them, but their art comes with the Creation Club files
  Thornswood leaves out, so the harvest, hunt and /give and /spawn table
  scripts skip them and `tests\test-special-edition-only.js` fails when a
  gamemode table hands one out (issue #479). `node
  scripts\mods\Check-CreationForms.js --write records\update-creation-club.json`
  writes it; run it again when the Skyrim pin moves.
- `signing\`: the code signing setup, with its own README. On since
  27 September: Ship refuses a launcher that is not signed (CONTRIBUTING.md).

Change a record only by running the script that writes it, in the same pull
request as the build or the fork commit it describes.
