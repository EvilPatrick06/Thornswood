# Glossary

The Thornswood words a newcomer meets in CONTRIBUTING.md, DEVELOPING.md,
`launcher\app\ARCHITECTURE.md` and the scripts, alphabetical. `<Root>` is the
launcher's install folder (`C:\Thornswood` on most machines), `Profile` is
`<Root>\Profile` and `Game` is `<Root>\Game`. Launcher files are in
`launcher\app`.

| Term | What it is | Where it lives |
|---|---|---|
| Allowed list | The profile ids let into the game server. The site builds it from Discord roles, and the server's door fetches it every five minutes. | `private\allowed.json` on the game server; `game\gamemode.js:11059`; DEVELOPING.md "Who gets into the game" |
| Arrival | Where a new character first stands: the inn of the town picked at the end of creation. Respawn uses the same points. | `CHARGEN.towns` (`gamemode.js:3881`) and `arriveAt` (`gamemode.js:4039`); `tests\test-arrivals.js` |
| Baseline | The channel's record of what its last release shipped, shared in Thornswood-Releases. Publish-Update packs only the difference, so a second machine's Dev Ship publishes the same packs. | `published.json` in the releases clone for that channel (`Thornswood-Releases` / `Thornswood-Releases-dev`); `Publish-Update.ps1 -Baseline` makes one |
| Board, the | The Thornswood To Do board, the one record of outstanding work. Each piece of work is an issue; Order is the do-order. | https://github.com/users/EvilPatrick06/projects/1; CONTRIBUTING.md "Everything we need to do goes on the board" |
| Bump-Version | Moves `Version` in `Updater.cs` as its own commit and pull request, before a main Ship. | `scripts\release\Bump-Version.ps1`; DEVELOPING.md "How a release goes out" |
| Channel | Which feed an install follows and a Ship publishes to: `main` (live) or `dev`. | `Channel` in `<Root>\config.json`; `Ship.ps1 -Channel dev` |
| Chargen | Character creation on the server: the hall, the face, the choice on K, then the trip to the inn. | `game\gamemode.js:3618` "character creation"; `thornswoodChargen` in `server-settings.json` switches it off |
| Client build record | The sha256 and size of the six client runtime files and the fork commit they came from. Sync-Client, Ship and the launcher refuse any other build. | `records\client-build.json`, written by `scripts\release\New-ClientBuildRecord.ps1` |
| Client runtime | The six SkyMP client files built from the fork: `MpClientPlugin.dll`, both SkyrimPlatform DLLs, the CEF host, `skymp5-client.js`, `TESModPlatform.pex`. | `ClientRuntime.cs`; engine/README.md |
| Collection | The Nexus collection of mods Thornswood runs on, curated in Vortex and deployed into the Steam copy. | `Collection` in `Config.cs`; `docs\COLLECTION-METHOD.md`; `scripts\ops\Set-Collection.ps1` |
| Collection revision | Which revision of the collection a release was built against. The launcher compares it with the revision installed and says when that is behind. | `collectionRevision` in version.json; `Config.cs`, `Shell.cs` |
| #staff-general | The team's Discord channel. A change to settled design or to one of the six shared files starts there, and whoever takes the dev feed says so there. | CONTRIBUTING.md "Settled design" and "How work moves" |
| Dev build | A second launcher beside the main one, on the dev channel, dev ports (game 7787, voice 7789) and its own Profile and Game. Every change is tried here first. | `<Root>-DevBuild`; `DevBuild.cs`; installed from Settings, Maintenance |
| Dev server | The game server the dev build joins: a copy of the live install with a fresh world, open to the staff roles (Owner, Dev, Gamemaster, Moderator, Loremaster). | VPS `C:\Thornswood-Server-Dev`, port 7787, resources 7788; `scripts\deploy\Deploy-DevGamemode.ps1` |
| Door | Who is let in. The launcher asks the site at Play (`Door.cs`, `/api/play/join`); the game server compares each connection with the allowed list, and turns people away only when enforcing. | `Door.cs:106 Check()`; `game\gamemode.js:10994`; `scripts\ops\Set-Door.ps1` |
| Downgrade | Puts the Steam copy back on Skyrim 1.6.1170 through Steam's own console, after asking, when Steam has updated it. | `Downgrade.cs:39`; the Downgrade button on the Play page |
| Feed | `version.json` in the releases repository, one per branch (main, dev): the latest version, its packs, the server's address, and optional `message`, `maintenance` and `minLauncher`. | github.com/EvilPatrick06/Thornswood-Releases; `Updater.cs`, `FeedNotice.cs` |
| Fix | The button that repairs what a scan found: the reference plugin list, a plugin fetched from the server, other servers' files moved to `Profile\Isolated`, or the launcher pointed at Vortex's folder. | `Verify.cs`; ARCHITECTURE.md "Verify and LoadOrder" |
| Gamemode | The server's own rules, one JavaScript file loaded by skymp5-server. | `game\gamemode.js`; GAMEMODE.md |
| Go.ps1 | Installs the front, the overlays, the plugins and the recorded client into the game folder and makes them the kept copies. Ship runs it. | `scripts\release\Go.ps1` |
| Hold | Read-only handles on every kept file and the client settings while the game runs, so nothing can change them under it. | `Hold.cs:56 Take()`, `Hold.cs:105 Release()` |
| Hotfix | The one live release not built from main: a `hotfix/...` branch from the live release's commit carrying one fix and its version bump. Patrick's call. | CONTRIBUTING.md "How work moves" |
| Keep | Thornswood's own files under `Game\Data\Platform`, kept pristine and put back before every Play. | `Keep.cs:323 Restore()`; `Profile\Keep` |
| Leaks | Removes the one sign in file the 16 September installer shipped, matched by hash so nobody's own sign in is touched. | `Leaks.cs:36 Clean()` |
| Main | The branch that ships and the live feed. Nobody pushes to it; everything arrives by pull request. | CONTRIBUTING.md "How work moves" |
| OwnGame | Builds and refreshes `<Root>\Game` from the Steam copy and what Vortex deployed: big files as hard links, anything rewritten in place as copies. | `OwnGame.cs:477 Make()`, `ShellOwnGame.cs`; records in `Profile\OwnGame` |
| Pack | A zip of the loose game files that changed since the baseline, published as a GitHub release asset. The launcher unpacks it into Game and Profile. | `scripts\release\Publish-Update.ps1`; `Updater.cs` `ApplyPack`; `Profile\Packs` |
| Park | Keep moves any plugin in `Game\Data\Platform\Plugins` that is not ours out of the way for the session, and puts it back when the game closes. | `Profile\Parked`, listed in `parked.txt`; `Keep.cs:406 Unpark()` |
| Profile id | The number SkyMP knows a character by. The launcher writes it into the client settings, and the door checks it. | `gameData.profileId` in `skymp5-client-settings.txt`; `Profile\Characters\profiles.txt` |
| Resources port | The game server's HTTP port (3000 live, 7788 dev). It serves the manifest and everything in the server's `data` folder to anybody. | `SkyMp.cs`; `Verify.cs` |
| Scan | The check at startup and on every recheck: the plugin list against the server's manifest, the Mods card and the rows on the Play page. It writes nothing. | `Shell.cs:2040 RunScan()`; `Verify.cs:60 Run()` |
| Server build record | The sha256 of `scam_native.node` and the fork commit it was built from. Deploy-Server refuses any other binary. | `records\server-build.json`, written by `scripts\release\New-ServerBuildRecord.ps1` |
| Session note | The file that tells the plugins this session is Thornswood's. Every plugin idles without a fresh one. | `Game\Data\Platform\thornswood-session.txt`; `Keep.cs:474 LeaveNote()` |
| Settled design | The decisions not open to a quiet rewrite: the game folder, Keep and Hold, the recorded client, C# 5, one complete release at a time. | CONTRIBUTING.md "Settled design" |
| Ship | The release: builds the launcher, checks the client, runs Go.ps1 and Publish-Update, posts the news and warns the server. `-Channel dev` for the dev feed. | `scripts\release\Ship.ps1`; `scripts\release\Check-ShipReady.ps1` says whether a machine can |
| Ship-Rules | The one list of what never leaves a machine in a pack or an installer, decided by what is ours rather than by whose. | `scripts\release\Ship-Rules.ps1`, read by `Publish-Update.ps1` and `Package-Thornswood.ps1` |
| Six shared files | `Shell.cs`, `Checks.cs`, `Keep.cs`, `Hold.cs`, `Updater.cs` and `Publish-Update.ps1`. Every machine works in them, so an edit gets a line in #staff-general first. Not the six client runtime files. | ARCHITECTURE.md "The six shared files"; CONTRIBUTING.md |
| Steam copy | Steam's own install of Skyrim Special Edition, which Vortex deploys into and OwnGame builds from. The launcher will not Play from it. | Found through Steam (`Steam.cs`) |
| Swap | Points Windows' two Skyrim folders at Profile for a session with junctions, and puts them back after. | `Swap.cs:107 Apply()`, `Swap.cs:40 Restore()`; `Profile\swap.json` |
| Sync-Client | Copies the recorded client runtime from the fork's build into the game folder; `-Check` compares only. | `scripts\release\Sync-Client.ps1` |
| Wave | The stage of an issue on the board, as a `wave:` label. | CONTRIBUTING.md "How to use it" |
| Where.ps1 | Says where the engine, its build output and the release output are on this machine, so no script names a path. | `scripts\release\Where.ps1`; engine/README.md |
| Your Mods | A folder for a person's own extra files, copied into `Game\Data` at Play. Never a plugin. | `<Root>\Your Mods`; `Verify.cs:750 DeployPersonal()` |
