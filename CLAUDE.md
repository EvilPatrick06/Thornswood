# Working in this repo

Read this first, every session, whoever you are working with. It is the same
for Gavin's machine and Djinn's. SECOND-DEVELOPER.md is the long form: what
the pieces are, how a release goes out, how a machine is set up.

## What this is

Thornswood: a modded co-op Skyrim roleplay server on SkyMP, in closed
playtest. This repo is the launcher (tools\app, C# 5, WPF, built with the
.NET Framework 4 csc), the game plugins (tools\ts-plugins, Skyrim Platform
JavaScript), the site (tools\docs-app, node), the Discord bot (tools\discord,
Python) and every script that ships or runs it. Owner: Gavin (EvilPatrick06).
Second developer: Djinn (Windows account Ken, Discord WiccanDjinn).

## Words

The people in the world are customers, clients, people, testers, partners.
Never "player". No em dashes anywhere written for people. Plain, direct
sentences, no filler, no placeholders. Secrets (server passwords, site keys,
Discord tokens, the news webhook, anything out of a config.json or .env on the
VPS) are named by location only; never printed, pasted, committed or logged.

## Settled design, not up for a quiet rewrite

- Decided by Gavin and Djinn on 17 Sep, after the three launchers kept
  getting into each other's files: Thornswood runs from its own game folder
  (`Thornswood\Game`), built by the launcher from what Vortex has deployed
  into the Steam copy, the big files as hard links so the collection is not
  stored twice, and copies of everything another launcher rewrites in place
  (settings, scripts, programs, the client folders, the master files and
  whatever Keizaal is known to replace). Keizaal and Daedric get their own
  folders the same way (`tools\New-GameFolder.ps1`). Until that branch
  (`djinn/own-game-folder`) is on main, what ships is the Steam copy with
  Vortex, and the two shapes must not be mixed in one release.
- Whichever folder the game runs from, the launcher handles sharing on its
  own: Keep puts its files back before Play and parks other servers'
  plugins; Hold keeps its files open read only while the game runs; the
  plugins idle unless the client points at our server and a fresh session
  note is there; Publish-Update keeps other servers' files out of packs
  (Ship-Rules.ps1). No wrapper scripts around the launcher, nothing moved by
  hand in Data\Platform, nothing touches Vortex's own files.
- The SkyMP client bundle (skymp5-client.js) is not built here; the copy in
  the game folder is patched by Patch-Client.ps1 and shipped as is.
- Launcher code is C# 5 only: no string interpolation, no ?., no nameof,
  no expression bodied members, no out var.
- Every change goes out as one complete release: launcher, game files and
  server together, never a half.

Anything that changes one of these is a few lines in #dev first: the
problem, the approach, what it touches. Agreed between Gavin and Djinn
before code; a Claude does not settle it for them.

## How work moves between the two machines

- main is what ships. Only Gavin's machine ships main, and Ship.ps1 refuses
  a main release that is not on main or is behind origin. A main Ship
  commits and pushes the source when the release is out, so the other
  machine can `git pull` exactly what shipped.
- Work happens on a branch: `git checkout -b djinn/what-it-is` (or
  `gavin/...`). Small commits, plain messages saying what changed. Push the
  branch and open a pull request (`gh pr create --fill`). The other person
  reads it; it is merged into main from GitHub, never pushed over main.
- `git pull` before starting anything. If a pull conflicts, resolve it on
  your branch (`git fetch`, `git rebase origin/main`), never on main. If a
  push is rejected, pull, do not force.
- The dev channel (`.\tools\Ship.ps1 -Channel dev "what changed"`) may be
  run from any branch, from either machine, to try work on the dev server.
  Say in #dev when you take it, because there is one dev feed and the last
  dev Ship wins. A main Ship resets it.
- One fix per pull request. A branch that changes eight things is eight
  reviews nobody has time for; split it.
- Every pull request gets a build check on GitHub (.github/workflows/build.yml:
  the scripts parse, the launcher compiles with the .NET Framework csc). Red
  means the branch would stop Ship at the build step; fix that before asking
  for a read.
- Do not edit Shell.cs, Checks.cs, Keep.cs, Hold.cs, Updater.cs or
  Publish-Update.ps1 without a line in #dev first; both machines touch those.

## What a Claude here does itself and what the person does

Read anything. Run git status, diff, log, fetch, the read only scripts
(Why-Keizaal.ps1, Check-*.ps1, Setup-SshKey.ps1 -Test), and compile checks.
Edit source on a branch when asked. The person runs what leaves the machine:
Ship.ps1, git push, gh pr create, and every script that talks to the VPS
(Deploy-*, Request-Restart, Install-Bot, Rotate-ServerPassword, Publish-*).
Show the command; let them run it. Never start the launcher or the game.
Measure before claiming a cause: read Profile\launcher.log, look at the file,
check timestamps, say what you saw. When the doc and the machine disagree,
say so and ask.

## Where things are

SECOND-DEVELOPER.md (the long form), README.md, SETUP.md, tools\app\HOOKUP.md
(launcher classes), tools\MOVING-THE-SERVER.md (the VPS), lore\ (the world),
tools\docs-app\data\site\*.md (public pages), tools\Ship-Rules.ps1 (what
never leaves a machine in a release).
