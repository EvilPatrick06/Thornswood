# Thornswood

A modded co-op Skyrim roleplay server on SkyMP, in closed playtest. This
repository is everything behind it. It is not where the game is downloaded:
people who want to join apply in the [Discord](https://thornswood.net/discord)
and follow [thornswood.net/join](https://thornswood.net/join).

## What is in here

- `launcher/app`: the launcher. C# 5 and WPF, compiled by
  `scripts/release/Build-Launcher.ps1` with the .NET Framework 4 csc.
- `launcher`: the window, the art and the voice page the launcher is
  built with.
- `installer`: what a new person runs first; `installer/setup` is the small
  setup program people download.
- `game/plugins`: the game plugins, in Skyrim Platform JavaScript.
- `game/ui`: the overlays inside the game.
- `game/gamemode.js`: the server's gamemode, with its tables in `game/data`.
- `site`: the site. Its public pages are `site/data/site`.
- `voice`: proximity voice.
- `bot`: the Discord bot, in Python.
- `records`: the client and server build records, and code signing.
- `scripts`: what builds, ships and deploys it all, listed in
  `scripts/README.md`; `tools` forwards the common commands there for now.
- `tests`: the test harnesses; run the ones your change touches before merging.
- `engine/skymp`: the SkyMP fork our engine changes live in, a git submodule.
  `scripts/release/Build-Engine.ps1` fetches and builds it (engine/README.md).
- `out` and `local`: the build output, and things kept beside the repository
  that never go to GitHub. Both are ignored by git.
- `lore/`: the world.

`bot`, `game`, `installer`, `records`, `scripts`, `site`, `tests`, `launcher`, `installer/setup`,
`records/signing`, `game/plugins`, `game/ui` and `voice` each have
a README of their own, which says what the folder is and how to change it.

## Before changing anything

- [CONTRIBUTING.md](CONTRIBUTING.md): the rules for everybody, with AI or
  without. Who is on the team, the words we use, the settled design, how work
  moves and what to run after a merge. Read it before your first change.
- [CLAUDE.md](CLAUDE.md): what applies to a Claude on top of those rules.
- [DEVELOPING.md](DEVELOPING.md): the long form. What the pieces
  are, how a release goes out, how a machine is set up.
- [docs](docs): the system map, the update feed, the gamemode and a glossary.
  [engine/README.md](engine/README.md): building the SkyMP fork.
- [docs/archive](docs/archive): dated snapshots kept for history, not current.
- [launcher/app/ARCHITECTURE.md](launcher/app/ARCHITECTURE.md): how the launcher
  starts, what each class owns and every step between Play and the game.
- [docs/IT-IS-DOWN.md](docs/IT-IS-DOWN.md): what to do when the server is down.
- [SECURITY.md](SECURITY.md): how to report a hole quietly.

Everything reaches `main` through a pull request, and `main` is what ships.

## Something wrong in the game

Say so in the [Discord](https://thornswood.net/discord), or on
[thornswood.net/report](https://thornswood.net/report).
