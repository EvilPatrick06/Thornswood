# Thornswood

A modded co-op Skyrim roleplay server on SkyMP, in alpha and open by
application. This
repository is everything behind it. It is not where the game is downloaded:
people who want to join apply in the [Discord](https://thornswood.net/discord)
and follow [thornswood.net/join](https://thornswood.net/join).

## What is in here

- `launcher/`: launcher chrome (window, art, voice page). The C# app lives in
  `launcher/app/` (C# 13 / WPF), built by `scripts/release/Build-Launcher.ps1`
  with MSBuild from `launcher/app/Thornswood.csproj` (#498). See
  `launcher/app/ARCHITECTURE.md`.
- `installer/`: what a new person runs first. `installer/setup/` is the small
  setup program people download (one installer tree, not two products).
- `game/`: everything that runs as the multiplayer game on the server and
  clients:
  - `game/gamemode.js`: the server's gamemode
  - `game/data/`: gamemode tables
  - `game/plugins/`: Skyrim Platform JavaScript plugins
  - `game/ui/`: overlays inside the game
  - `game/menu/`: in-game menu pieces
  - `game/content/`: authored content
  - `game/required-data/`: data the client/server must have beside the build
- `site/`: the website. Public pages under `site/data/site`.
- `voice/`: proximity voice.
- `bot/`: the Discord bot (Python).
- `records/`: client and server build records, and code signing
  (`records/signing/`).
- `scripts/`: build, ship, and deploy scripts (`scripts/README.md`).
- `tests/`: harnesses; the nightly on the VPS runs them.
- `docs/`: system map, update feed, glossary, and runbooks.
- `engine/skymp/`: SkyMP fork submodule. Built by
  `scripts/release/Build-Engine.ps1` (`engine/README.md`).
- `lore/`: the world.
- `out/` and `local/`: build output and machine-local files that never go to
  GitHub (both gitignored).
- `config.example.json`: launcher `config.json` example matching
  `launcher/app/Config.cs` defaults (empty `UpdateToken`). Site example:
  `site/config.example.json`.

`bot`, `game`, `installer`, `records`, `scripts`, `site`, `tests`, `launcher`,
`installer/setup`, `records/signing`, `game/plugins`, `game/ui` and `voice`
each have a README of their own, which says what the folder is and how to
change it.

## Before changing anything

- [Developer-Guide.md](Developer-Guide.md): how to get the code onto your
  computer, open a pull request, ship a dev or main release, deploy the site
  and the gamemode, and post the news. Read it before your first change.
- [CLAUDE.md](CLAUDE.md): what applies to a Claude on top of that guide.
- [docs](docs): the system map, the update feed, the gamemode and a glossary.
  [engine/README.md](engine/README.md): building the SkyMP fork.
- [docs/archive](docs/archive): dated snapshots kept for history, not current.
- [launcher/app/ARCHITECTURE.md](launcher/app/ARCHITECTURE.md): how the launcher
  starts, what each class owns and every step between Play and the game.
- [docs/IT-IS-DOWN.md](docs/IT-IS-DOWN.md): what to do when the server is down.
- [SECURITY.md](SECURITY.md): how to report a hole quietly.
- [LICENSE](LICENSE): Thornswood's own work is all rights reserved, and
  everybody who contributes agrees once to the contributor terms in it.
  [THIRD-PARTY.md](THIRD-PARTY.md) is what other people wrote, under their
  own licences.

Everything reaches `main` through a pull request, and `main` is what ships.

## Something wrong in the game

Say so in the [Discord](https://thornswood.net/discord), or on
[thornswood.net/report](https://thornswood.net/report).
