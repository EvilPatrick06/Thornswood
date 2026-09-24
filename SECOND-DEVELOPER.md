# Thornswood for a second developer

Read this first if you are working on Thornswood from a machine that is not
Patrick's, or if you are the Claude working with somebody who is. It says what
Thornswood is, how the pieces fit, how a release goes out, and what has to be
true on a machine before it can ship one. Nothing in here is a secret; the
secrets are listed by name near the end with where each one lives.

## What Thornswood is

Thornswood is a modded co-op Skyrim roleplay server on SkyMP, the server
authoritative multiplayer for Skyrim Special Edition. It is Patrick's, in a
closed playtest with friends and testers, becoming an RP server of its own,
less strict than the big ones, with working NPCs, its own launcher, its own
website and Discord, and a lore of its own (fifty years after the civil war,
the Stormcloaks won, a High King over the Jarls, the Thalmor expelled, the
Empire back under a trade treaty with one embassy). Characters live on the
server, not in save files. During the playtest they are throwaway.

Words: the people in the world are customers, clients, people, testers,
partners. Never "players". Writing anywhere public is plain and direct, no
em dashes, no placeholders, no AI sounding phrasing. Every change ships as
one complete release covering launcher, game files and server together, never
a half.

## The pieces

| Piece | Where | What it is |
| --- | --- | --- |
| Source repo | github.com/EvilPatrick06/Thornswood (private), clone at `C:\Users\<you>\Downloads\Thornswood-Repo` | Launcher source, plugins, site, bot, every script |
| Releases repo | github.com/EvilPatrick06/Thornswood-Releases (public), clone beside the source repo as `Thornswood-Releases`, dev branch as a worktree `Thornswood-Releases-dev` | `version.json` per branch (main, dev) and the release assets: packs and launcher exes |
| Launcher | `tools\app\*.cs` + `tools\ui.xaml`, built by `tools\Build-Launcher.ps1` with the .NET Framework 4 csc, C# 5 only | WPF app at `<drive>:\Thornswood\Launcher\Thornswood.exe` (C: on most machines); profile, config and packs under that folder. The scripts find the install on whichever fixed drive holds it; `-Root` overrides |
| Dev build | `<drive>:\Thornswood-DevBuild`, beside the main install, put there by the main launcher's Settings page | Same exe, `config.json` says `Channel: dev`, `UpdateBranch: dev`, port 7787, voice 7789. Owner and Dev roles only |
| Game | The Steam copy of Skyrim Special Edition, mods deployed by Vortex from the Nexus collection, or `<Root>\Game` once the launcher has made Thornswood's own folder from that deployment (see Separate Skyrim folders) | Without its own folder, every launcher shares the Steam copy. Thornswood's own loose files live in `Data\Platform` (plugins in `Plugins\thornswood-*.js`, page in `UI\`) and `Data\SKSE\Plugins\Thornswood.ini` |
| Plugins | `tools\ts-plugins\thornswood-{front,chargen,emotes,mark,voice}.js`, UI in `tools\ts-ui` | Skyrim Platform JavaScript. Idle unless the client points at our server and the launcher left a fresh session note |
| Game server | VPS 192.135.112.23, `C:\Thornswood-Server`, UDP/TCP 7777, resources 3000, task `Thornswood Server` | skymp5-server with `gamemode.js`; the door reads its allowed list from the site |
| Dev game server | `C:\Thornswood-Server-Dev`, 7787, resources 7788, task `Thornswood Dev Server` | Same binaries, fresh world, door list is Owner and Dev only (`https://thornswood.net/dev`) |
| Voice | `C:\Thornswood-Voice` 7778 and `C:\Thornswood-Voice-Dev` 7789 | node, `tools\voice\voice-server.js`; the launcher holds the microphone, the game plugin relays state through files in `Data\Platform` |
| Site | `tools\docs-app`, on the VPS at `C:\Thornswood-Docs`, node on 127.0.0.1:3001 behind Caddy, https://thornswood.net | Public pages from `data\site\*.md`, admin hub, Discord login, the door API, uploads, news |
| Bot | `tools\discord`, on the VPS at `C:\Thornswood-Bot`, task `Thornswood Bot` | discord.py: tickets, join cards, staff tools |
| Watchdog | `C:\Thornswood-Watch\watch.ps1`, every five minutes | Restarts any service that stops answering, three tries an hour |

The server's SkyMP fork and its build tree are Patrick's alone for now
(`C:\Thornswood-Dev\skymp`); server binaries are copied, not rebuilt, on a
second machine.

## How a release goes out

```
cd C:\Users\<you>\Downloads\Thornswood-Repo
.\tools\Bump-Version.ps1
# then the branch and pull request it prints; once that is merged:
git checkout main
git pull
.\tools\Ship.ps1 "what changed, in plain words"
```

`Bump-Version.ps1` moves `Version` in `tools\app\Updater.cs` (1.1.35 to
1.1.36), commits that one file, and prints the branch and pull request
commands for it, because main refuses a push from everybody. Ship runs once
that pull request is merged and pulled; it writes nothing to this repository.
It builds the launcher, checks the client is the recorded build, then runs
`tools\Publish-Update.ps1`, which
scans the game folder for loose files that are not Vortex's, not vanilla, not
runtime and not per machine, diffs them against this machine's baseline
(`%LOCALAPPDATA%\Thornswood\published.json`), zips the difference as a pack,
uploads pack and launcher as a GitHub release in the releases repo, rewrites
`version.json` and pushes it. Then the site's news, the Discord #news webhook
and the game server are told; the server warns the room for five minutes and
puts everyone back to the launcher to update.

The dev channel is the same with `-Channel dev`: version 1.1.36.1, .2, .3,
pack ids ending `-dev`, the dev worktree and branch, the dev baseline
(`published-dev.json`), the dev ports, the dev server told. No installer, no
news, no Discord post. A plain Ship afterwards promotes everything to main and
resets the dev feed and baseline to match main, so dev starts at .1 again.

Everything else: `Deploy-Server.ps1` pushes a server build, `Deploy-Gamemode.ps1`
the gamemode, `Deploy-Docs.ps1` the site, `Install-Bot.ps1` the bot,
`Request-Restart.ps1` an announcement, `Rotate-ServerPassword.ps1` the server
password. Every script closes the launcher and Skyrim itself when it needs to.

## Two machines shipping

Two people, two machines, one repo. The short rules are in `CLAUDE.md` at the
repo root, which every Claude Code session reads on its own; this is the long
form.

- **main is what ships.** Only Patrick's machine ships main. `Ship.ps1`
  refuses a main release that is not on the `main` branch, is behind or
  ahead of `origin/main`, has anything uncommitted, or has a file under
  `tools` that git does not know. It commits and pushes nothing, so what
  shipped is already on GitHub and the other machine can `git pull` exactly
  that.
- **Work happens on a branch.** `git checkout -b djinn/what-it-is` (or
  `gavin/...`), small commits with plain messages, `git push -u origin
  <branch>`, then `gh pr create --fill`. The other person reads the pull
  request and it is merged on GitHub. Nothing is pushed over main from a
  second machine, and nothing is force pushed.
- **One fix per pull request.** A branch that changes eight things is eight
  reviews at once; split it.
- **`git pull` before anything.** A conflicting pull is resolved on your
  branch (`git fetch`, `git rebase origin/main`), never on main. A rejected
  push means pull first; never `--force`.
- **The dev channel is for trying.** `.\tools\Ship.ps1 -Channel dev "..."`
  runs from any branch on either machine and puts that build on the dev
  server. There is one dev feed and the last dev Ship wins, so say in #dev
  when you take it. A main Ship resets dev to match main.
- **Settled design is a proposal first.** Where the game runs from (see the
  three launchers section: the own game folder is the decided direction),
  Keep and Hold for the shared Data\Platform, the patched client bundle,
  C# 5 only, one complete release at a time: changing any of these starts
  as a few lines in #dev, agreed between Patrick and Djinn before code. Editing `Shell.cs`, `Checks.cs`, `Keep.cs`, `Hold.cs`,
  `Updater.cs` or `Publish-Update.ps1` gets a line in #dev too; both
  machines touch them.
- **The publisher pulls the feed** before `version.json` is edited, so a
  release is added on top of whatever the other machine just published; a
  refused push means NOT SHIPPED, pull and run Ship again.
- **The baseline is per machine.** A machine that did not ship the last
  release ships those files again once; wasted bytes, never wrong files.
- **Keep trusts the game folder** over its kept copies on any machine with
  `Profile\developer.flag` (Publish-Update writes it), so an edit you are
  testing is not put back before you can ship it.
- **What never leaves a machine** in a pack or an installer is one list,
  `tools\Ship-Rules.ps1`, read by `Publish-Update.ps1` and
  `Package-Thornswood.ps1` both: runtime folders, one machine's own files,
  other servers' files, and the SkyMP client's saved sign in
  (`Data\Platform\PluginsNoLoad`). The installer of 16 Sep carried that
  sign in file before the list was shared; the launcher removes that exact
  copy from every install (Leaks.cs), matched by content so nobody's own
  sign in is touched.

## Setting up a machine

Needs: Windows 10 or 11, Skyrim Special Edition on Steam (any Steam library,
any drive; the scripts find it through Steam) with the Thornswood collection
deployed through Vortex, the Thornswood launcher installed on any drive and
signed in, git, the GitHub CLI (`gh`) signed in to an account that is a
collaborator on both repos, PowerShell 7, node, Python 3 with `discord.py`
and `Pillow` for the bot scripts, and an SSH key the VPS knows.

```
cd C:\Users\<you>\Downloads
git clone https://github.com/EvilPatrick06/Thornswood.git Thornswood-Repo
git clone https://github.com/EvilPatrick06/Thornswood-Releases.git Thornswood-Releases
gh auth login
gh auth status
```

Then in `Thornswood-Repo`:

```
.\tools\Setup-SshKey.ps1 -KeyOnly
```

which makes a key for the VPS, points ssh at it, and prints the public line.
Send that line to Patrick; he runs `.\tools\Add-VpsKey.ps1 -PublicKey '<the line>'`
from his machine and the VPS knows you. `.\tools\Setup-SshKey.ps1 -Test`
proves it. Until then the scripts that talk to the VPS (`Deploy-*`,
`Request-Restart`, `Install-Bot`, `Publish-Installer`, `Publish-News`) cannot
reach it, and Ship still publishes but cannot warn the room.

The first publish from a new machine needs a baseline:

```
.\tools\Publish-Update.ps1 -Baseline
```

which records what the game folder holds right now without shipping
anything. Do it straight after the launcher has brought the game up to date,
so the baseline is the current release and the first real Ship carries only
what you changed.

`Publish-Discord.ps1` reads the #news webhook from `tools\discord\news-webhook.txt`,
which is not in the repo. Patrick gives it to you if you will ship main releases
from your machine; without it Ship says so and carries on.

## Secrets, by name, none of them in the repo

| Secret | Where it lives | Who needs it |
| --- | --- | --- |
| Server password (`sPassword`, `sAdminPassword`) | VPS `server-settings.json`; the launcher gets it from the site at check in | Nobody types it |
| Site `botKey`, `secret`, Discord client secret and bot token | VPS `C:\Thornswood-Docs\config.json` | The site and the bot |
| Bot token, `THORNSWOOD_KEY` | VPS `C:\Thornswood-Bot\bot.env.json` | The bot |
| Door key | VPS `C:\Thornswood-Server*\data\door.json`, same as `botKey` | The game servers |
| #news webhook | `tools\discord\news-webhook.txt` on a shipping machine, ignored by git | Whoever ships main |
| GitHub access | your own `gh auth` | You |
| VPS access | your own SSH key in `administrators_authorized_keys` | You |

Never paste any of them into a chat, a commit, a Discord message or a doc.

## One Skyrim of its own

Thornswood runs from its own game folder, `<Root>\Game`, and nothing here
supports another server's install. Decided by Patrick on 20 September, after
measuring what the old sharing code had actually let through: the SkyMP client
runtime in Thornswood's folder, the bundle, `MpClientPlugin.dll`, both
SkyrimPlatform DLLs, the CEF host and `TESModPlatform.pex`, were all another
launcher's builds, copied across from the Steam copy on every rebuild and then
patched by text. None of them had come from Vortex and none had come from
here.

**The folder.** The launcher makes `<Root>\Game` itself (`tools\app\OwnGame.cs`,
Settings, Maintenance, "Thornswood's own Skyrim folder"). With the Thornswood
profile deployed in Vortex, it builds the folder from that deployment, then
restarts and runs from it. `Paths.Init` prefers `<Root>\Game` over the Steam
copy, so from then on the launcher points Windows' Skyrim settings, plugin list
and saves at `Profile` for each session and ignores which profile Vortex has
on. When Vortex deploys a newer Thornswood collection, the next launcher start
brings it in by itself. The offer to make the folder is made at startup
whenever it is possible; it used to wait for another server's files to be
found, and no longer looks for any.

**The client.** The SkyMP client runtime is built from the fork,
`C:\Thornswood-Dev\skymp` on `thornswood/engine-changes`: `npx webpack` in
`skymp5-client` for the bundle and the native build for the rest. After a
rebuild, `tools\New-ClientBuildRecord.ps1` records the six files that build
produces which differ from upstream, by hash, against the fork commit, into
`tools\client-build.json`. `tools\Sync-Client.ps1` copies those six from the
build output into the game folder and refuses any file that is not the
recorded one; `Go.ps1` runs it beside the overlays and the plugins. Ship runs
`Sync-Client.ps1 -Check` and refuses a release whose client is not the recorded
build. `OwnGame.Foreign` never takes those six paths from the Steam copy. The
launcher's Client row on the Play page tests the bundle for the
`THORNSWOOD PATCH` marker the fork's source carries.

**Links, not copies.** Big files (archives, textures, meshes, plugins) are hard
links to Vortex's copies, so a collection is not on the disk twice; this needs
the folders on the same drive as the Skyrim Vortex deploys into. A hard link is
the same file under a second name, so anything written into one in place lands
in every folder that links it. So these are always copied: the game's root
files, `Data\Platform`, `Data\NirnLabUIPlatform`, `Data\SKSE`, `Data\MCM`,
`Data\Video`, settings, script and program files, and the vanilla masters. The
launcher's own writes into the game folder go through `OwnGame.Unshare` or
`OwnGame.Separate` first.

**Left out of the folder, and of every pack and installer:** decided by what
belongs, never by whose a file is. `OwnGame.Foreign` in the launcher and
`Test-ShipOtherServer` in `tools\Ship-Rules.ps1` are the same list; change both
together. In `Data\Platform\Plugins` only `thornswood-*.js` and the recorded
bundle belong; in `Data\Platform\UI` only `index.html`, `build.js` and
`thornswood-*.js`; `PluginsNoLoad` is sign-in data with a token in it and never
travels; NirnLab UI Platform is left out because SkyrimPlatform will not start
on its own browser with it present. Vortex's records and markers, logs and
`Claude outputs` are left out too.

**In the folder while the game runs.** Keep puts back every file our own
updates wrote under `Data\Platform` before Play and parks any `.js` in
`Plugins` that is not ours in `Profile\Parked`, then puts them back the moment
the game closes. Hold keeps its own files open read only while the game runs,
so nothing can swap them under Skyrim Platform's hot reload. Every Thornswood
plugin idles unless the client settings point at our server and the launcher
left a fresh session note, `Data\Platform\thornswood-session.txt`. No wrapper
script is needed around the launcher for any of this.

A Skyrim on a newer build than 1.6.1170 gets a Downgrade button on the Play
page (Downgrade.cs): the launcher opens Steam's console, types the three
`download_depot` commands itself, watches Steam's content_log.txt for each
depot to finish, copies the 1.6.1170 files over the Steam copy and removes the
downloads. Nothing is typed unless Steam's window is confirmed in front; if it
cannot be, the command goes on the clipboard and the log says where to paste.

**Records.** `Profile\OwnGame\files.txt` lists each file brought in, whether it
was linked or copied and whether Vortex deployed it. Ship-Rules.ps1 reads that
list (`Get-ShipOwnGameCollection`) so Publish-Update and Package-Thornswood keep
the collection out of packs and the installer, exactly as they read
`vortex.deployment.json` when the game is the Steam copy, and both refuse to go
on if the list is empty. `Profile\OwnGame\plugins.txt` and `loadorder.txt` are
the Vortex profile's lists as of the folder's last update, and are the
reference load order a release carries (`Get-ShipLoadOrderDir`). Ship checks
the client in `<Root>\Game` against `tools\client-build.json`.

**The Skyrim build.** Steam updates the Steam copy by itself. With Thornswood's
own folder, the Downgrade button works on the Steam copy the folder is made
from, never on the folder's copies, and the folder is then brought up to date
from it. Until the Steam copy is back on 1.6.1170 the folder is not made or
refreshed, so Thornswood keeps playing on the build it has, and the card above
Play says the Steam copy is on the wrong build. Files a mod replaces are left as
the mod has them. The sign in file the 16 Sep installer carried is removed from
the Steam copy as well as from the folder (`Leaks.cs`).

**Testing it on the dev channel.** The dev build runs from
`<Root>-DevBuild`, which has no Game folder, so it starts on the Steam copy.
Its own Settings, Maintenance has "Make it", which builds
`<Root>-DevBuild\Game` the same way.

Skyrim reads its plugin list from one Windows folder per user. Thornswood swaps
it per session and ignores which profile Vortex has on.

## Where things are written down

- `README.md`, `SETUP.md`: the repo and a fresh install.
- `tools\app\HOOKUP.md`: how the launcher classes hang together.
- `tools\MOVING-THE-SERVER.md`, `tools\COLLECTION-METHOD.md`: the VPS and the
  mod collection.
- `lore\`: history and the Accord. `tools\docs-app\data\site\*.md`: the public
  pages (world, rules, join, classes, credits, support), also live on the site.
- The site's hub boards: Active Issues, Known Issues, Test These, Suggestions,
  Archive, and the Patrick runbook.
