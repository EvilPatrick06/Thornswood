# Thornswood

A modded co-op Skyrim roleplay server on SkyMP, in closed playtest. This
repository is everything behind it. It is not where the game is downloaded:
people who want to join apply in the [Discord](https://thornswood.net/discord)
and follow [thornswood.net/join](https://thornswood.net/join).

## What is in here

- `tools/app`: the launcher. C# 5 and WPF, compiled by
  `tools/Build-Launcher.ps1` with the .NET Framework 4 csc.
- `tools/launcher`: not the launcher's code, only the voice page it opens in
  a hidden window.
- `tools/setup`: the small setup program people download.
- `tools/ts-plugins`: the game plugins, in Skyrim Platform JavaScript.
- `tools/ts-ui`: the overlays inside the game.
- `tools/gamemode.js`: the server's gamemode.
- `tools/docs-app`: the site. Its public pages are `tools/docs-app/data/site`.
- `tools/voice`: proximity voice.
- `tools/discord`: the Discord bot, in Python.
- `tools/signing`: the code signing setup, switched off until it is finished.
- `tools/*.ps1`: the scripts that build, ship and deploy all of the above.
  `tools/Where.ps1` says where the engine and the build output are.
- `engine/skymp`: the SkyMP fork our engine changes live in, a git submodule.
  `git submodule update --init engine/skymp` fetches it; it needs Visual
  Studio to build.
- `out` and `local`: the build output, and things kept beside the repository
  that never go to GitHub. Both are ignored by git.
- `lore/`: the world.

`tools/discord`, `tools/docs-app`, `tools/launcher`, `tools/setup`,
`tools/signing`, `tools/ts-plugins`, `tools/ts-ui` and `tools/voice` each have
a README of their own, which says what the folder is and how to change it.

## Before changing anything

- [CLAUDE.md](CLAUDE.md): how work moves between the two machines, the settled
  design and the words we use. Read it first, every session.
- [SECOND-DEVELOPER.md](SECOND-DEVELOPER.md): the long form. What the pieces
  are, how a release goes out, how a machine is set up.
- [docs/archive](docs/archive): dated snapshots kept for history, not current.
- [tools/app/ARCHITECTURE.md](tools/app/ARCHITECTURE.md): how the launcher
  starts, what each class owns and every step between Play and the game.
- [IT-IS-DOWN.md](IT-IS-DOWN.md): what to do when the server is down.
- [SECURITY.md](SECURITY.md): how to report a hole quietly.

Everything reaches `main` through a pull request, and `main` is what ships.

## Something wrong in the game

Say so in the [Discord](https://thornswood.net/discord), or on
[thornswood.net/report](https://thornswood.net/report).
