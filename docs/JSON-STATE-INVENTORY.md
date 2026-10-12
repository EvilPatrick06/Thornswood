# Critical JSON state and configuration

The JSON files Thornswood's release, deploy, game, site, bot and voice trust, who writes each one, who reads it, and how it is checked today. This is the inventory #2180 asks for. The first slice also adds fail-closed shape and version checks for the four records marked **held**. The rest are listed so the next slices can take them in order of risk. Nothing here changes a file's format: there is no migration.

**How a check works.** `scripts\release\RecordShape.ps1` reads a record through `ConvertFrom-ThornswoodJson` (an empty or broken file names itself). It then refuses a version this checkout does not know, and refuses a missing or wrongly typed field the readers depend on. Records written before a version field existed are read as version 1. A file that says 2 is refused, not half understood. `scripts\release\Check-Records.ps1` runs this over the committed records, and `tests\test-record-shapes.ps1` holds it.

## Release and deploy records (repository)

| File | Written by | Read by | Risk | Check today |
| --- | --- | --- | --- | --- |
| `records/server-build.json` | New-ServerBuildRecord.ps1 (Build-Server) | Deploy-Server, Deploy-DevGamemode, Deploy-Gamemode, Export-ServerPayload, Publish-Server, Install-ThornswoodServer (on the box), ServerOrder, Check-ShipReady | High: every server deploy is held to it | **held** (sha256, bytes, source.commit, files map, lightPlugins) |
| `records/client-build.json` | New-ClientBuildRecord.ps1 | Ship, Sync-Client, Publish-Update, Build-Launcher (into the launcher), launcher ClientRuntime/OwnGame | High: every client and Ship is held to it | **held** (forkCommit, files map) |
| `records/most-online.json` | by hand | MaxOnline.ps1 (Deploy-Gamemode, Deploy-DevGamemode, Publish-Server, Publish-Update), site | High: the engine's seat count; over 1000 stops the server starting | **held** (people 1 to 1000, staffSeats) |
| `records/collection-plugins.json` | New-CollectionPluginRecord.ps1 | CollectionPlugins.ps1 (Deploy-Server, Deploy-DevGamemode -LoadOrder) | High: full deploys refuse on it (#2019) | **held** (version 1 required, plugins rows) |
| `records/skyrim-pin.json` | by hand | Publish-Update (into version.json), launcher Downgrade/Config | High: the pinned game build | test-skyrim-pin.ps1 (agreement), not shape |
| `records/ui-gone.json` | by hand | Ship-Rules, Build-Launcher, launcher OwnGame | Medium: what every pack deletes | Ship-Rules refuses empty or broken; test-ship-rules |
| `records/skyrim-files.json` | New-SkyrimFilesRecord.ps1 | Build-Launcher (into the launcher), launcher OwnGameKinds | Medium | named on a bad read (#2119) |
| `records/generated.json` | by hand | Build-Generated, Generated, Ship-Rules, Check-ShipReady | Medium | test-build-generated |
| `records/steam-build.json` | Check-Outside.ps1 | Check-Outside.ps1 | Low | none |
| `records/update-creation-club.json` | Build-HarvestTable tooling | Build-HarvestTable, Build-HuntTable | Low (build time only) | none |
| `records/upstream-not-taken.json` | by hand | people | Low | none |
| `records/signing/metadata.json`, `signing.template.json` | by hand (`signing.json` is ignored by git) | Sign-Artifact, Ship, Setup-ShipMachine, Check-ShipReady | Medium: signing config, no secret in the repository | named on a bad read |

## Built and deployed state (machine or box)

| File | Written by | Read by | Risk | Check today |
| --- | --- | --- | --- | --- |
| `server-settings.json` (built, and on each server) | Deploy-Gamemode, Export-ServerPayload; ServerSettings.ps1 carries settings on the box | the engine, Deploy-Server, Deploy-DevGamemode, Swap (on the box), site | High: port, load order, seats | named on a local bad read (#2154); box-side reads unchecked |
| `thornswood-build.json` (build stamp) | BuildStamp.ps1 | Deploy-Server, Deploy-DevGamemode | Medium | named on a bad read (#2154) |
| `deployed-build.json` | DeployedBuild.ps1 (on the box) | site | Low | none |
| `version.json`, `published.json` (feed store) | Publish-Update, Publish-Server, Rollback-Feed, Scrub-Feed | every launcher, site | High: what every launcher installs | named on a bad read (#2119) |
| launcher `config.json` | launcher, Set-Server, Set-Collection | launcher, Deploy-Gamemode, Ship-Rules | Medium | named on a bad read; Deploy-Gamemode falls back |

## Site, bot and voice state (on the box)

| File | Written by | Read by | Risk | Check today |
| --- | --- | --- | --- | --- |
| `bans.json`, `pk.json` | site | site (and what it hands the game server at join) | **Critical**: authorization. Malformed fails open today (#2186) | none: #2186 |
| `linked.json`, `sessions.json`, `signins.json`, `rules-accepted.json` | site | site, bot | High: identity and sign-in | none |
| `board.json`, `notes.json`, `inbox.json`, `open-tickets.json`, `trouble.json` | site | site | Medium: concurrent edits (#2188) | none |
| `gallery.json`, `gallery-pending.json`, `gallery-reports.json`, `uploads.json`, `files.json` | site | site | Medium | none |
| `news.json`, `page-versions.json` | Publish-News, Set-DevNews, site | site | Low | named on a bad read (#2119) |
| `online.json`, `roster.json`, `heartbeat.json` | game server, gamemode | site, launcher, Deploy-Server (on the box) | Medium | none |
| `joins.json`, `commands-synced.json`, `bot.env.json` | bot, Install-Bot | bot | Medium; `bot.env.json` holds a secret and is never in the repository | none |
| `thornswood-deploy.json` | Install-Bot, Install-Voice | site | Low | none |

## Next slices, in order

1. **Authorization state:** `bans.json` and `pk.json` fail closed on a malformed file (#2186; site lane).
2. **Box-side reads:** `server-settings.json` and `server-build.json`, inside the text Swap.ps1 and Install-ThornswoodServer run on the box. The helper has to travel with the payload first.
3. **Feed:** `version.json`, `skyrim-pin.json` and `ui-gone.json` get a contract in RecordShape.ps1.
4. **Site identity state:** `linked.json`, `sessions.json` and `signins.json` get a startup check with a readiness signal.
