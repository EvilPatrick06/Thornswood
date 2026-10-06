# How Thornswood fits together

One page, for somebody new, with or without AI. What runs where, what talks
to what, and which script puts each piece in place. Every port, folder and
task name here is read off a script, which is named beside it. A script is
cited as `<script>.ps1:<what it says>`, its own words for the thing, never a
line number, because every edit above a line moves it. If a script and this
page disagree, the script is right and this page needs a fix.
Developer-Guide.md is the long form and the rules.

## The three places things run

| Where | What runs there | Who touches it |
| --- | --- | --- |
| A tester's PC | The launcher, Skyrim from Thornswood's own game folder, Vortex, Steam | The person playing; the launcher looks after its own files |
| Any developer's machine that can sign | The repo, the SkyMP fork build, `Ship.ps1`, `Publish-*`, `Deploy-*`, `Install-*` | Developers. Any of them may ship dev and main (Developer-Guide.md) |
| The VPS, 192.135.112.23, Windows, user Administrator | Both game servers, both voice services, the site, Caddy, the bot, the watchdog, the nightly backup | Reached over ssh by the scripts; nobody edits it by hand |

<!-- VPS address: "address" in scripts/vps/vps.json, which the scripts that reach the box over ssh read through `Vps.ps1:Get-ThornswoodVpsAddress`; launcher/app/Config.cs:256 -->

## The picture

```mermaid
flowchart LR
  subgraph PC["Tester's PC"]
    L["Launcher<br/>Thornswood\\Launcher"]
    G["Skyrim + SkyMP client<br/>Thornswood\\Game"]
    V["Vortex<br/>Nexus collection"]
    S["Steam copy of Skyrim"]
    V -->|deploys mods| S
    S -->|hard links and copies| G
    L -->|builds, patches, starts| G
  end

  subgraph VPS["VPS 192.135.112.23"]
    C["Caddy :80 :443<br/>thornswood.net"]
    W["Site node 127.0.0.1:3001"]
    F["Feed and downloads<br/>/feed and /feed-dev<br/>version.json, assets by sha256<br/>baseline and history, not served"]
    W --> F
    GS["Game server :7777<br/>resources :3000"]
    DS["Dev game server :7787<br/>resources :7788"]
    VO["Voice :7778"]
    VD["Dev voice :7789"]
    B["Discord bot"]
    WD["Watchdog, every 5 min"]
    BK["Nightly backup 03:15"]
    C --> W
    C -->|/voice| VO
    C -->|/voice-dev| VD
    GS -->|door list every 5 min| W
    DS -->|/dev/api/allowed| W
    GS -->|positions, loopback| VO
    DS -->|positions, loopback| VD
    B -->|/api/ticket| W
    B -->|reads watch.log| WD
    WD -->|restarts| GS & DS & VO & VD & W & C & B
  end

  P["Patrick's machine<br/>Ship.ps1, Deploy-*"]
  P -->|scp: assets, then version.json and the baseline| F
  P -->|ssh: Deploy-*, Install-*| VPS
  L -->|polls version.json| C
  L -->|downloads, host and sha256 checked| C
  L -->|Discord sign in, installer, news| C
  G -->|UDP 7777 or 7787| GS
  L -->|voice socket| C
```

## On a tester's PC

The launcher lives at `<drive>:\Thornswood\Launcher\Thornswood.exe` (C: on
most machines). Everything else hangs off that root, which is the folder above
the exe (`launcher/app/Paths.cs:42`):

| Folder or file | What it is | From |
| --- | --- | --- |
| `Thornswood\Launcher` | The exe, the WebView2 loader, the voice host page | `Paths.cs:53`, `DevBuild.cs:72` |
| `Thornswood\Game` | Thornswood's own Skyrim, built by the launcher from the Steam copy and what Vortex deployed; big files are hard links, anything rewritten in place is a copy | `Paths.cs:44`, Developer-Guide.md "One Skyrim of its own" |
| `Thornswood\Profile` | `launcher.log`, `applied.txt` (packs already in), `Packs\*.files` (what each pack wrote), `Default` (reference plugin list), `Keep` | `Paths.cs:54-66` |
| `Thornswood\config.json` | The launcher's settings. Server address, ports, update repo and branch; several are overwritten from the feed (see FEED.md) | `Paths.cs:66`, `Config.cs:133-147` |
| `Thornswood-DevBuild\` | The dev build: same exe, `Channel` and `UpdateBranch` set to `dev`, server port 7787, voice port 7789, voice address with `-dev` on the end. Installed from the main launcher's Play page Server card; staff roles only | `DevBuild.cs:26-27,49-52,126-130` |

With no `Game` folder the launcher reads the Steam copy (`Paths.cs:51`), but
Play will not start from it (Developer-Guide.md:32).

**Vortex and the Nexus collection.** The mods come from the Nexus collection
(`collectionUrl` in the feed,
`https://www.nexusmods.com/games/skyrimspecialedition/collections/7essxf`).
Vortex deploys it into the Steam copy, or into whatever folder Vortex manages;
the launcher finds that folder (`OwnGame.DeploysInto`) and builds `Game` from
the Steam copy's game plus exactly the files Vortex's record lists.

**The SkyMP client runtime** (six files) is built from the fork in
`engine\skymp`, recorded in `records\client-build.json`, and shipped both inside
packs and as its own asset named in the feed's `clientRuntime`
(`Publish-Update.ps1:the client runtime, as an asset with an address`,
`Publish-Update.ps1:Set-Prop $doc 'clientRuntime'`, `ClientRuntime.cs:261-269`).

## Updates, the installer and the site

- **The feed.** Every launcher reads `version.json` from
  `https://thornswood.net/feed/version.json` (dev: `/feed-dev/`) since #649,
  and since #907 nowhere else: a site feed that does not answer is asked again
  on the next check (`Updater.Check`). Since #897 packs, the launcher exe and
  the client runtime are served by the site too, at
  `/feed[-dev]/assets/<sha256>`. FEED.md has every field.
- **Who writes it.** `Ship.ps1` runs `Publish-Update.ps1`, which diffs the game
  folder against this channel's baseline
  (`published.json`, received from the VPS store beside the channel's feed,
  `Feed-Store.ps1`), zips the difference, sends it and the launcher to the
  site's assets folder, rewrites `version.json` and sends it and the baseline
  back to the store, which is when the site serves it; `Publish-PostShip.ps1`
  then checks every asset the feed names is up with `Remirror-Site-Feed.ps1`. Then `Publish-News.ps1` (main only), then
  `Publish-Discord.ps1` (#news, or the dev updates channel), then
  `Request-Restart.ps1`, which warns the room for five minutes
  (`Ship.ps1:Invoke-PostShip`, `Ship.ps1:$AnnounceMinutes = 5`).
- **The installer.** `Package-Thornswood.ps1` builds `Thornswood-Setup` and
  `Publish-Installer.ps1` copies it over ssh into `C:\Thornswood-Docs\files`
  on the VPS (`Publish-Installer.ps1:$Root = 'C:/Thornswood-Docs'`,
  `Publish-Installer.ps1:$Root/files/`). The setup program asks the
  site's `/api/payload` for `Thornswood-Setup.zip` (or a leftover stamped tip), its size and
  sha256 (`site/server.js:2247-2275`); people get it from
  `https://thornswood.net/downloads` (`server.js:2214-2215`). A dev release
  never touches the installer (`Ship.ps1:dev release, the installer is not touched`).
- **The site.** `site`, deployed by `Deploy-Docs.ps1` into
  `C:\Thornswood-Docs` (`Deploy-Docs.ps1:$Root = 'C:/Thornswood-Docs'`). Node
  listens on 3001 (`server.js:34`) and, once `THORNSWOOD_DOCS_LOCAL=1` is set
  by `Setup-Domain.ps1` (`Setup-Domain.ps1:SetEnvironmentVariable('THORNSWOOD_DOCS_LOCAL','1','Machine')`),
  only on 127.0.0.1 (`server.js:38`). Caddy holds 80 and
  443 for `thornswood.net` and `www.thornswood.net`, proxies `/voice/*` to
  7778, `/voice-dev/*` to 7789 and everything else to 3001
  (`scripts/deploy/Caddyfile:40-51`). The live Caddyfile is
  `C:\Thornswood-Caddy\Caddyfile` (`scripts/deploy/Caddyfile:4-6`). The site does
  Discord sign in, the public pages from `data\site\*.md`, news, uploads, the
  admin hub, and the door's lists.

## The door

No password decides who gets into the game; the server runs in offline mode
(Developer-Guide.md:279-290). Each game server's `gamemode.js` reads
`private\door.json` (the site address and the site's `botKey`, named here by
location only) and fetches the allowed list every five minutes into
`private\allowed.json` (`gamemode.js:11270-11276,11392`). The live server
asks `https://thornswood.net/api/allowed`; the dev server's `door.json` names
`https://thornswood.net/dev`, so it asks `/dev/api/allowed`, which lists Owner
and Dev only (`server.js:2921-2922`, Developer-Guide.md:35). The door turns
somebody away only when `allowed.json` says `"enforce": true`
(`gamemode.js:11008-11010`), which `Set-Door.ps1 -Enforce` sets.

## The VPS services

Every service but the bot is a Windows scheduled task; the bot is a Windows
service. The watchdog starts a task, or restarts the bot's service, by name
when its check fails, three times an hour at most
(`Watch-Services.ps1:$already -ge 3`).

| Service | Folder on the VPS | Port(s) | Scheduled task | Deployed or set up by | From |
| --- | --- | --- | --- | --- | --- |
| Game server (live) | `C:\Thornswood-Server` | UDP and TCP 7777, resources TCP 3000 | `Thornswood Server` | `Deploy-Gamemode.ps1` builds it locally, `Deploy-Server.ps1` sends it; a gamemode alone from any machine, onto the server build running, `Deploy-Server.ps1 -GamemodeOnly`; first install `Install-ThornswoodServer.ps1` | `Deploy-Server.ps1:$Root = 'C:/Thornswood-Server'`, `Deploy-Server.ps1:$Task = 'Thornswood Server'`, `Bootstrap-VPS.ps1:$GamePort = 7777`, `Bootstrap-VPS.ps1:$ResourcePort = 3000`, `Install-ThornswoodServer.ps1:$TaskName = 'Thornswood Server'` |
| Dev game server | `C:\Thornswood-Server-Dev` | UDP and TCP 7787, resources TCP 7788 | `Thornswood Dev Server` | Made once by `vps-dev-instance.ps1` (runs on the VPS); gamemode by `Deploy-DevGamemode.ps1` | `vps-dev-instance.ps1:$Dev = 'C:\Thornswood-Server-Dev'`, `vps-dev-instance.ps1:$devPort = 7787`, `vps-dev-instance.ps1:Port = ($devPort + 1)`, `vps-dev-instance.ps1:Register-ScheduledTask -TaskName 'Thornswood Dev Server'`, `Deploy-DevGamemode.ps1:$Root = 'C:/Thornswood-Server-Dev'` |
| Voice (live) | `C:\Thornswood-Voice` | TCP 7778 on 127.0.0.1 only, and `/voice` through Caddy | `Thornswood Voice` | `Install-Voice.ps1` | `Install-Voice.ps1:$Root = 'C:\Thornswood-Voice'`, `Install-Voice.ps1:$Port = 7778`, `Install-Voice.ps1:$Bind = '127.0.0.1'`, `Install-Voice.ps1:$TaskName = 'Thornswood Voice'`, `voice-server.js:28` |
| Dev voice | `C:\Thornswood-Voice-Dev` | TCP 7789 on 127.0.0.1 only, and `/voice-dev` through Caddy | `Thornswood Dev Voice` | Made by `vps-dev-instance.ps1`; `Install-Voice.ps1 -Root C:\Thornswood-Voice-Dev -Port 7789 -TaskName 'Thornswood Dev Voice'` | `vps-dev-instance.ps1:$DevVoice = 'C:\Thornswood-Voice-Dev'`, `vps-dev-instance.ps1:$devVoicePort = 7789`, `vps-dev-instance.ps1:THORNSWOOD_VOICE_BIND=127.0.0.1`, `vps-dev-instance.ps1:Register-ScheduledTask -TaskName 'Thornswood Dev Voice'`, `voice/README.md:57-64` |
| Site | `C:\Thornswood-Docs` | 127.0.0.1:3001 | `Thornswood Docs` | `Deploy-Docs.ps1`, `-Site` for the public pages | `Deploy-Docs.ps1:$Root = 'C:/Thornswood-Docs'`, `Deploy-Docs.ps1:$Task = 'Thornswood Docs'`, `Deploy-Docs.ps1:$Port = 3001`, `server.js:34-38` |
| Caddy | `C:\Thornswood-Caddy` | 80, 443 | `Thornswood Web` (at startup and every five minutes) | `Setup-Domain.ps1`, which sends `scripts\deploy\Caddyfile` as the live one on every run without `-TaskOnly` (issue #543) | `Setup-Domain.ps1:$CaddyDir = 'C:/Thornswood-Caddy'`, `Setup-Domain.ps1:Caddyfile written, from scripts\deploy\Caddyfile`, `Setup-Domain.ps1:Register-ScheduledTask -TaskName 'Thornswood Web'`, `Setup-Domain.ps1:New-ScheduledTaskTrigger -AtStartup`, `Setup-Domain.ps1:-RepetitionInterval (New-TimeSpan -Minutes 5)`, `scripts/deploy/Caddyfile:4-7` |
| Discord bot | `C:\Thornswood-Bot` | none | none: the Windows service `ThornswoodBot`, as `NT SERVICE\ThornswoodBot` (issue #465) | `Install-Bot.ps1`, `-CodeOnly` for the code, the card art and the live smoke's export | `Install-Bot.ps1`, `Bot-Service.ps1`, `BotService.cs` |
| Watchdog | `C:\Thornswood-Watch` (`watch.ps1`, `watch.log`) | none | `Thornswood Watch`, every five minutes as SYSTEM | `Watch-Services.ps1 -Install` | `Watch-Services.ps1:$Root = 'C:\Thornswood-Watch'`, `Watch-Services.ps1:$Task = 'Thornswood Watch'`, `Watch-Services.ps1:schtasks /create /tn '$Task' /sc minute /mo 5 /ru SYSTEM` |
| Nightly backup | `C:\Thornswood-Backup` (passphrase in `key.txt`) | none | `Thornswood Backup`, daily at 03:15 | `Install-Backup.ps1`; `Fetch-Backups.ps1` brings them down | `Install-Backup.ps1:$Root = 'C:\Thornswood-Backup'`, `Install-Backup.ps1:$keyFile = Join-Path $Root 'key.txt'`, `Install-Backup.ps1:$TaskName = 'Thornswood Backup'`, `Install-Backup.ps1:$At = '03:15'`, `Install-Backup.ps1:New-ScheduledTaskTrigger -Daily`, `vps-nightly-backup.ps1:$KeyFile = 'C:\Thornswood-Backup\key.txt'` |

What the watchdog checks: `https://thornswood.net/` for Caddy, then TCP 3001,
3000, 7778, 7788 and 7789, and a python process with `Thornswood-Bot` in its
command line for the bot (`Watch-Services.ps1:$checks`,
`Watch-Services.ps1:BotAlive`). The bot writes
`heartbeat.json` in `C:\Thornswood-Bot\data` every minute (#1104), and a bot whose process runs but
which is hung or off Discord for ten minutes is down too, and is restarted by
its service's name like one whose process is gone (issues #449 and #465,
`Watch-Services.ps1:BotSilent`, `Watch-Services.ps1:$beatStale = 600`,
`bot/bot.py:2408-2510`). From outside the box, the bot also pings an uptime
monitor every minute while it is on Discord, so a bot or a whole VPS that
stops is noticed when One is off too: the address is `PING_URL` in
`bot.env.json`, set by `Install-Bot.ps1 -SetPing`, and `bot/README.md` says
how to make the check (issue #449, `bot/bot.py:2513-2618`). It also asks the site,
both game servers and both voice servers over HTTP, which it tells about and
never restarts for, and checks the `Thornswood Backup` task's last result with
a backup under 26 hours old, every build runner's service, and writes DISK LOW
under 20 percent free on C: and DISK CRITICAL under 10. It tells the staff
channel once when any of these goes down and once when it is back (issue
#447): each message goes into `C:\Thornswood-Watch\alerts.jsonl`, the bot
posts it within a minute, and when the bot is down or silent the watchdog posts
it through the webhook in `alerts-webhook.txt` beside it
(`Watch-Services.ps1:HealthProblem`, `Watch-Services.ps1:$tellOnly`,
`Watch-Services.ps1:$diskLow = 20`, `Watch-Services.ps1:$diskCritical = 10`,
`Watch-Services.ps1:Observe`, `Watch-Services.ps1:Deliver`,
`bot/bot.py:1998-2098`).

What the backup takes: the live server's `world`, `private`, `data`,
`server-settings.json` and `gamemode.js`, and the same five from
`C:\Thornswood-Server-Dev` under `game-dev` (issue #401); the site's data,
config, uploads and each feed's store but not its downloads (issue #454); the
bot's config and join record; the Caddyfile. Encrypted, seven daily and four
weekly kept (`vps-nightly-backup.ps1:$KeepDaily = 7`,
`vps-nightly-backup.ps1:$KeepWeekly = 4`). It takes nothing from either voice
folder: the live one's `choices.json`, which nothing reads, stopped being taken
with issue #1084. The copy off the box is pulled to Patrick's machine
over ssh by the `Thornswood Fetch Backups` task there (`Fetch-Backups.ps1
-Schedule`), never served over HTTPS; `Restore-Server.ps1` puts one back into
a server folder, `Restore-Box.ps1` puts all of it onto a new box, and
`tests\test-backup-restore.ps1` and `tests\test-new-box-runbook.ps1` prove the
round trip.

03:15 is a quiet hour, not the hour after a restart: no script under `scripts`
registers a nightly restart task. Measured on 5 Oct over every
`Register-ScheduledTask`, `New-ScheduledTaskTrigger` and `schtasks /create` in
`scripts`: the only daily triggers are this backup's and the one
`Fetch-Backups.ps1 -Schedule` makes on Patrick's machine, and every other task
those scripts register starts at boot, every few minutes, at sign in or once.
`Install-Backup.ps1` says the same
(`Install-Backup.ps1:well clear of when anybody is playing`).

A deploy sends a commit or nothing (issue #1121): `Deploy-Docs.ps1`,
`Install-Voice.ps1`, `Install-Bot.ps1`, `Deploy-DevGamemode.ps1`,
`Deploy-Server.ps1` and `Publish-Server.ps1` refuse, before they talk to the
box, when a file they would send out of the repository has uncommitted
changes or is untracked, and name each one (`Assert-ThornswoodCommitted` in
`scripts\deploy\Artifact.ps1`). There is no switch past it.
`Deploy-Docs.ps1` and `Install-Voice.ps1` then check the site or voice tree
they are about to send, file by file, against that same commit
(`Assert-ThornswoodSourceIntegrity`, issue #1335). The zip, the expanded
tree and the commit's own bytes have to be the same hashes. If they are not,
nothing is sent and the box is not touched. The hash compare Deploy-Docs
already makes of server.js and the public files, on the box, is unchanged.

How a deploy replaces what runs (issue #446): nothing is written over a
running service any more. The new files go into `<folder>\.stage-<stamp>`
while the old one runs, the box checks them there (each file by its hash, the
program parsing, the load order resolving), and a refusal stops nothing. Only
then is it stopped, the files renamed in, started and asked whether it
answers; if it does not, the old files go back and it is started again, and
the run says `SWAP ROLLED BACK` and fails. What a deploy replaced stays in
`<folder>\.prev-<stamp>`, the newest two, and `-PutBack` puts the newest
back the same way, keeping what it took out in `.undone-<stamp>`:
`Deploy-Server.ps1`, `Deploy-DevGamemode.ps1`, `Deploy-Docs.ps1`,
`Install-Voice.ps1` and `Install-Bot.ps1` all take it, and the blocks that do
it on the box are `scripts\deploy\Swap.ps1`. The record of what a part runs (issue #459,
`C:\Thornswood-Deploys`) is written only once the swap has answered; the one
it had goes into `.prev` with the files it describes, and `-PutBack` brings it
back and tells the store. A whole server install through
`Publish-Server.ps1` does the same one level up: the payload is unpacked to
`C:\Thornswood-Server.stage-<stamp>` beside the root, the old root becomes
`C:\Thornswood-Server.prev-<stamp>` (the newest two kept, each a whole
server folder, so they cost disk), the world, the roster, the runtime data and
the logs are carried across, and a server that does not answer is swapped
back and kept as `.failed-<stamp>` to read. `Publish-Server.ps1 -PutBack`
puts the newest `.prev` back. What a publish expects and does not find stops
it, never skipped without a word (issue #1336): `Export-ServerPayload.ps1`
refuses a build with no `gamemode.js` (skymp5-server logs the missing file and
runs on with no gamemode, so no door and no join pass) and a load order naming
a plugin the machine does not have, and the installer refuses a stage with no
`gamemode.js`. A dev publish gives the dev door the live `door.json`'s address,
key and join pass key; when the live one, or any of those three, is not there,
the dev door is left as it was and the publish stops with exit 1
(`DOOR NOT CARRIED`). The settings lines a deploy prints name every release
key the release does not carry, which stays as the running server has it.
The live join pass switch and the written role lists are never a release
key (issue #1223): a build no longer carries them, and they change on live
only in a `Deploy-Server.ps1` run given `-RequirePass on|off`, `-Devs` or
`-Playtesters`, set on the box in the carry and named there
(`tests\test-1223-live-pass-asked.ps1`).
`tests\test-1336-missing-stops.ps1` holds all of it. The documents and public pages the site serves
from `data` are content, not the app, and still go up in place with a `.bak`.
The harnesses are `tests\test-deploy-swaps.ps1`,
`tests\test-install-server.ps1` and `tests\test-deploy-server-swap.ps1`.

## How the pieces talk

- **Launcher to game server:** the SkyMP client connects to `serverAddress` and
  `serverPort` from the feed, UDP 7777 live or 7787 dev (`Config.cs:256-257`,
  `DevBuild.cs:26`).
- **Game server to voice:** `gamemode.js` pushes positions five times a second
  to `127.0.0.1:<thornswoodVoicePort>` from its own `server-settings.json`,
  falling back to 7778 (`gamemode.js:253-258,10641`,
  `Install-Voice.ps1:five times a second, over loopback on the VPS`).
  `Deploy-DevGamemode.ps1` sets 7789 for dev (`Deploy-DevGamemode.ps1:$VoicePort = 7789`).
- **Launcher to voice:** the voice page holds a WebSocket to `voiceUrl`
  (`https://thornswood.net/voice` or `/voice-dev`), or with that empty the same
  built-in address, never the raw port: the service listens on loopback and
  takes a join token only over wss (#1304). Audio goes between people directly
  (`Install-Voice.ps1:The audio itself goes straight between people`). The
  page and the game's chat each offer a join token of their own with the
  handshake, minted by the launcher for that one connection (#1337, #1322).
- **Bot to site:** `/api/ticket` with the site's `botKey` (`bot.py:27,277`).
- **Game server to site:** the door list (above) and `/api/roster`
  (`gamemode.js:10900-10906`).

## What runs on a developer's machine

`Ship.ps1`, `Publish-*`, `Repair-Manifest.ps1`, `Bump-Version.ps1`, every
`Deploy-*` and `Install-*`, and `Request-Restart.ps1`. The engine build and the
release output (`out`, ignored by git) are in the repo folder; `scripts\release\Where.ps1`
says where (`Where.ps1:Get-Place`). The feed and its baseline are received from
the VPS into `%LOCALAPPDATA%\Thornswood\feed\main` and `\dev`, working copies
with a backup of the last twenty of each, not git clones (`Feed-Store.ps1`,
#907). Which command each
change needs after a merge: Developer-Guide.md, "After a pull request is merged".

## Where the sources disagree

- `DevBuild.cs:21-22` says both launchers share the one Skyrim, and
  `DevBuild.cs:92` copies `developer.flag`. Developer-Guide.md:431-435 says the dev
  build makes its own `<Root>-DevBuild\Game`, and Developer-Guide.md:180-182 says
  nothing writes `developer.flag` since 25 September.
