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
  the box refuse any server file that is not this build. `"lightPlugins": true`
  says the recorded fork loads light plugins (it has espm::IsLightPlugin), and
  only then does Deploy-Gamemode list them in the server's load order (#1715).
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
- `ui-gone.json`: the 37 Daedric Online menu files (name and sha256) and the
  42 unused skymp5-front svgs plus bg.png that must never ship and that every
  pack deletes (issue #1318). `Ship-Rules.ps1` loads it; Build-Launcher puts
  it inside the launcher; OwnGame.Foreign reads that copy so a refresh cannot
  copy those files back. No script writes this one: it is changed by hand, in
  a pull request. `tests\test-ship-rules.ps1` fails while Ship-Rules and
  OwnGame disagree with it.
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
  (`staffSeats`), with Patrick's decisions in its `note` (issue #481), and
  the most people the voice service takes at once (`voice`), never fewer than
  the two together, since everybody seated and everybody waiting in line at
  the menu holds a socket to it. Those are main's. Its `dev` object holds the
  same three for the dev server and dev voice (Patrick, 12 Oct: 5, 0 and 5),
  and a record without one gives dev main's numbers.
  `scripts\deploy\MaxOnline.ps1` reads it for Deploy-Gamemode,
  Deploy-DevGamemode (dev), Publish-Server and Publish-Update (each for its
  channel) and Install-Voice (dev for `C:\Thornswood-Voice-Dev`), and
  `site\server.js` reads `people` and `staffSeats` when the site runs from
  the repository. What people are shown, the M of "N of M awake", is the
  seats, people and staffSeats together: 30 on main, 5 on dev. No script writes
  this one: it is changed by hand in a pull request, then each server is
  deployed and a Ship carries it to the feed.
- `upstream-not-taken.json`: the upstream SkyMP commits the fork is not
  taking, each by its full sha with the reason and who decided (issue
  #1791). `tests\test-fork-upstream.js` is red every night upstream `main`
  has a commit `thornswood/engine-changes` lacks that is not listed here.
  No script writes this one: it is changed by hand in a pull request.
- `papyrus-events.json`: the fork's Papyrus event list, both halves (issue
  #503). The client half is what the blocker in skyrim-platform's
  FridaHooks.cpp lets through on each person's machine: the event names
  and the script names that free an object. The server half is the event
  names the server's own Papyrus machine is sent, that it attaches scripts
  only to placed references, the scripts its storage can load (built in,
  data\scripts, and the archives the "archives" setting names, which no
  deploy script writes), and what InitScripts drops. `readAt` is the fork
  commit it was read at. `node scripts\dev\PapyrusEventList.js --write`
  writes it from the fork at the pin; `scripts\dev\Audit-PapyrusEvents.py`
  judges the load order against it. `tests\test-papyrus-event-list.js`
  holds it to the rest of this repository on every pull request, and the
  nightly fetches the fork and reads it against the pin. The check is the
  list, not the commit: a pin moved over fork work that leaves the list
  alone passes, and one that changes it fails there, naming what changed.
- `signing\`: the code signing setup, with its own README. On since
  27 September: Ship refuses a launcher that is not signed (Developer-Guide.md).

## Provenance notes

Each of these says how one engine build was made when it was not a plain
build of the pinned commit: which files were built again, which kept the
bytes of an earlier build and why that is the same source, and what was run
to check it. They are evidence for the records above at the commit each
names. No script reads them. `THIRD-PARTY.md` and
`site\data\site\credits.md` point at the one behind the current pin.

- `client-provenance-e248493f.md`, `client-provenance-bb62695c.md`,
  `client-provenance-51faac39.md` and `client-provenance-47da3f34.md`: the
  six client files at those fork commits (30 September to 2 October).
- `creation-clothes-provenance.md`: the client and SkyrimPlatformImpl.dll
  built for the starting clothes in character creation (fork commit
  ac46d078, 3 October).
- `runner-isolation.json`: what a runner account on the VPS must not reach (production paths, groups), the crash dump folder it may only write, the age limit for files left in its temp folder, and differences agreed as intentional. `scripts\vps\Check-RunnerIsolation.ps1` compares the runners against it (issue #2161).
- `remote-commands.json`: every call under `scripts\` that reaches the VPS (ssh, scp, Invoke-ThornswoodRemote and its wrappers, Remote.ps1), what it sends, and the class it needs: a gate verb, admin, or transport. Read from the code; `docs\DEPLOY-IDENTITIES.md` section 2a is its summary. `tests\test-remote-command-map.ps1` fails when a remote call has no row or a row has no call (issue #2182). A row names its call by script, function, command and an anchor, a line of text from the call (or just above it), never by its place in the file, so a call put in elsewhere moves no row (#2498).
- `prod-parity.json`: what the VPS should look like (which ports listen where and as which program, each task's account and triggers, the services' accounts, which live files must match which repository file, the TLS margin, environment variables that must not be set) and the differences agreed as intentional, each with its reason. `scripts\vps\Check-ProdParity.ps1` compares the box against it; no secret belongs in it (issue #2165).
- `asset-provenance.json`: the asset provenance register (issue #2177). Every picture, video, sound, font, mesh, texture, interface file and plugin Thornswood hands to people or shows them: where it came from, who made it, its licence or permission, the credit it asks for, who approved it and when, where it is published and its sha256, or which of those is not recorded and who can answer. Files that ship from the game folder but are not in the repository are in it by name, and gallery uploads and the collection's mods are dispositioned. Operator only: nothing that builds a pack, the installer, the launcher or the site reads it. A permission itself is never written in it; an entry says where it is kept. No script writes it: it is changed by hand in the pull request that adds or changes an asset, and `tests	est-asset-provenance.js` fails on a tracked asset with no entry or a changed hash.
- `merchant-runtime-provenance.md`: the server module built for merchant
  settlement, and why the six client files kept their 0dd0590b bytes (fork
  commit 5328e5c1, 4 October).

`client-inputs-e248493f.json`, the hashes of the cached build inputs behind
`client-provenance-e248493f.md`, was removed on 5 October (issue #1347):
nothing read it, the engine has been pinned to other commits since, and it
named folders on the machine that built it. It is in the history at 9e4ba70.

Change a record only by running the script that writes it, in the same pull
request as the build or the fork commit it describes.
