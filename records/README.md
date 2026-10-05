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
- `generated.json`: what `scripts\mods\Build-Generated.ps1` builds in
  Thornswood's own game folder on the shipping machine before a Ship (issue
  #1247): the behavior patch codes Pandora Behaviour Engine+ generates the behavior files with, and
  the BodySlide slider sets built into the bodies, each at its own slider
  defaults. No script writes this one: it is changed by hand, in a pull
  request. Build-Generated refuses a set or a slider move that shapes the
  breasts, the seat, the genitals or the nipples (#1004) or takes the
  underwear off (#405), and Ship stops after a change until the files are
  built again.
- `most-online.json`: the most people in the world at once (`people`) and
  the seats over it that only the Discord staff roles may take
  (`staffSeats`), with Patrick's decisions in its `note` (issue #481).
  `scripts\deploy\MaxOnline.ps1` reads it for Deploy-Gamemode,
  Deploy-DevGamemode, Publish-Server and Publish-Update, and `site\server.js`
  reads `people` when the site runs from the repository. No script writes
  this one: it is changed by hand in a pull request, then each server is
  deployed and a Ship carries it to the feed.
- `upstream-not-taken.json`: the upstream SkyMP commits the fork is not
  taking, each by its full sha with the reason and who decided (issue
  #1791). `tests\test-fork-upstream.js` is red every night upstream `main`
  has a commit `thornswood/engine-changes` lacks that is not listed here.
  No script writes this one: it is changed by hand in a pull request.
- `signing\`: the code signing setup, with its own README. On since
  27 September: Ship refuses a launcher that is not signed (Developer-Guide.md).

## Provenance notes

Each of these says how one engine build was made when it was not a plain
build of the pinned commit: which files were built again, which kept the
bytes of an earlier build and why that is the same source, and what was run
to check it. They are evidence for the records above at the commit each
names. No script reads them. `THIRD-PARTY.md` and
`site\data\site\credits.md` point at the one behind the current pin.

- `client-provenance-4952dbb6.md`, `client-provenance-e0135f5a.md`,
  `client-provenance-df1a6c39.md` and `client-provenance-d6c99400.md`: the
  six client files at those fork commits (30 September to 2 October).
- `creation-clothes-provenance.md`: the client and SkyrimPlatformImpl.dll
  built for the starting clothes in character creation (fork commit
  bd1d80e2, 3 October).
- `merchant-runtime-provenance.md`: the server module built for merchant
  settlement, and why the six client files kept their e6534129 bytes (fork
  commit a247ef27, 4 October).

`client-inputs-4952dbb6.json`, the hashes of the cached build inputs behind
`client-provenance-4952dbb6.md`, was removed on 5 October (issue #1347):
nothing read it, the engine has been pinned to other commits since, and it
named folders on the machine that built it. It is in the history at 9e4ba70.

Change a record only by running the script that writes it, in the same pull
request as the build or the fork commit it describes.
