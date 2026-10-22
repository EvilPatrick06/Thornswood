# Status

What is true now. Rewritten in place by whoever changes it; history is in git.

Last rewritten 22 Oct 2026, 10:45 AM (Patrick's time) by the Cloud Desk, after
the morning's run notes (the batch that deleted the finished ones). Before
that, 9:55 AM by the Local Desk on One, which folded in what was still true
from the vault's `wiki/status.md` and moved the run notes here.

## Releases now

| Channel | Launcher | Release | Built from | Engine | Game / resources / voice |
|---------|----------|---------|------------|--------|--------------------------|
| Main | 1.2.5 | 20261017-205912 | 24572604 (tag release/main/20261017-205912) | 3bdf3d3c | 7777 / 3000 / 7778 |
| Dev | 1.2.6.6 | 20261022-162021-dev | d1778c99 (tag release/dev/20261022-162021-dev) | eaf9f0b9 | 7787 / 7788 / 7789 |

- **Dev server:** engine eaf9f0b9 (#3306) since Publish-Server -FromStore
  from the cloud at 10:18 AM on 22 Oct, INSTALL OK, with the gamemode of
  d1778c99. #3302 (Thornswood-Last.esp) went on at 9:45 AM with
  Deploy-DevGamemode -LoadOrder, and both of its halves reached clients in
  20261022-154916-dev (9:49 AM). Its world was wiped on purpose at 2:48 AM
  for #3078 (Wipe-Saves.ps1 -Server dev, 42 characters); the 2:15 AM backup
  holds them.
- **Dev profile** (#3181), 7:28 AM on 22 Oct, nobody on, 4,883 NPCs loaded:
  0.125 of a core on the JavaScript thread (0.176 before #3255). A 120 second
  profile on eaf9f0b9 started at 10:26 AM for the VPS performance work.
- **Live server:** engine 3bdf3d3c with main's 1.2.5 gamemode. The next main
  release needs a live `Deploy-Server -GamemodeOnly` first, and never goes
  straight after a dev Ship.
- **Live voice:** voice-bcc2dbaa (deployed 19 Oct), auth on, loopback only;
  /health chatRetention overdueDays 0, no prune error (read 8:37 AM 22 Oct).
- **Site:** from main d1778c99 (Deploy-Docs -Site from the cloud, 10:24 AM 22
  Oct: the credits page names eaf9f0b9 and the licences folder). The roadmap
  board was replaced from main at 10:16 AM (#2560: the #502 row without
  bounties, #507's free claim row); the known board is still as typed on the
  site, held for #3137. Cloudflare fronts ports 80 and 443, which take only
  Cloudflare's addresses (#2995).

## The box

- **Runners:** three on the VPS. 1 and 2 carry thornswood-build, 3 takes light
  jobs only (#3108, #3117). Each runner account has its 6 outbound block rules
  (#2161, read 10:10 AM 22 Oct). The `Thornswood Gate Trace` task runs for
  runners 1 and 2 since 9:22 AM on 22 Oct, and its map is live: a pull
  request's gate takes about 2 minutes (#3114, closed).
- **Accounts:** the dev server, dev voice, live voice, Caddy, the site, the
  backup and the bridge run as LOCAL SERVICE, Limited. `Thornswood Server`
  (live) is still SYSTEM until the next main release's Publish-Server (#2578).
- **Backup:** the `Thornswood Backup` task runs on its own LOCAL SERVICE
  account and may read bot.env.json since 4:17 AM on 22 Oct (#2836, #3258). The
  4:17 AM run ended with result 0, 0 skipped. Next at 2:15 AM, and it takes
  turns with server installs (#3247).
- **Watchdog:** a delayed-start service within 15 minutes of boot counts as
  starting, not down (#3222).
- **Windows on the box:** telemetry tasks still on, and Windows Update still
  on its own hours. Harden-VPS for #3213 stopped at 7:51 AM on 22 Oct before
  changing anything, when one ssh through the bridge timed out at the banner
  (#3297). `UpdateOrchestrator\Reboot_AC` plans a restart of the box by
  itself at 6:08 AM on 23 Oct until the hardening runs. #1043: upgrade OpenSSH
  at the box's next planned restart, then check the host key against
  `scripts\vps\vps.json` and that the post-quantum warning is gone.

## Waiting

- **#3297**, then Harden-VPS for #3213 (Patrick's standing rule lets the Desk
  run it).
- **#2519:** the Gamemasters channels are made (7:51 AM 22 Oct). GM Rules v1.0
  is to be posted and pinned in #gm-rules by the bot, but its text is in none
  of the repository, the vault or Drive; it waits on Djinn or Patrick for the
  text.
- **The main release** carries what dev has: the merchant work (#1373, its
  Content.esp `fecfb823…` is on the dev server and in the dev release), the
  licences folder (#3099, #3287, both in Done), the help page's hair dye
  section (#2705) and the rows in `claude-queue/test-tasks-at-main.md`.
- **#2183:** the availability baseline runs 22 Oct to 19 Nov 2026
  (docs/SERVICE-OBJECTIVES.md). Watch-Outside -Install for the off-box check
  needs One.
- **A launcher change** still needs a Ship from One: -FromFeed refuses one and
  -ModsOnly keeps the feed's launcher. The cloud fix is compiling and signing
  the launcher in CI.
- **#2578:** at the next main release, after the live Publish-Server,
  `claude-queue/2578-prod-parity.md`.
- **Checks that need a game client** (nobody here starts the launcher or the
  game): #1032, #1031, #1269, #2434.

## Where things are on One

- The repository: `C:\Thornswood-Repo`, detached at origin/main, worktrees in
  `worktrees\`, scratch in `temp\` (#2900).
- Backups pulled from the box: `C:\Thornswood-Repo\local\backups` (Fetch
  Backups task).
- The engine build: CI's, in `%LOCALAPPDATA%\Thornswood\engine-ci\<pin12>`
  (`engine-build.json` says `ci`); `Get-EngineArtifact.ps1` fills it.
- Release roots: `local\release-main` and `local\release-devbuild`
  (`%LOCALAPPDATA%\Thornswood\ship-roots.json`); every Ship refreshes its root
  first. Their launchers are never started.
- Signing: the Ship signs the launcher on One through Azure Artifact Signing
  (ThornswoodSigning), and the release manifest on GitHub.
- Patrick plays dev from `C:\Thornswood-DevBuild` and main from `C:\Thornswood`.
- Node v24.21.0 on One and the box (#1961).

## Traps

- `Get-Logs.ps1 -Port` names the voice port, not the game port; `-Dev` reads
  dev.
- A fresh engine build's `server-settings.json` lists only the five masters;
  give it the server's own order first.
- An engine pin changes both halves: Publish-Server, then the gamemode, then
  the Ship. After a ship root refresh, run `Build-Generated.ps1 -Channel
  <channel>` before the Ship.
- Thornswood-Last.esp's order includes the Skyrim.ccc plugins after the five
  masters.
- Deploy-Docs, Trace-Gate and Deploy-DevGamemode take no `-NoPause`.

## Standing orders not written elsewhere

- **#staff-updates** (Patrick, 22 Oct): post only when staff must act, for a
  restart or outage they would see, or a change to how staff work. Never for
  merges, pull requests, progress, deploys, or dev or main releases.
- Discord release posts go out after every Ship, dev and main, in their own
  channels; `-NoAnnounce` controls only the server countdown.
- Read-only Codex CLI reviews of a plan, implementation or correction are
  pre-authorized (Patrick, 15 Oct).
- Alpha capacity is 25 people plus 5 staff seats; actor fade 10; an older
  launcher updates before it enters the world.
- Claims use the `claimed:` label and the board's In Progress; a held pull
  request carries the `held` label with the reason in its body.
- The Merchants' Guild is NPCs only.
