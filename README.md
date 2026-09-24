# Thornswood

A modded co-op Skyrim roleplay server on SkyMP, in closed playtest. This
repository is everything behind it. It is not where the game is downloaded:
people who want to join apply in the [Discord](https://thornswood.net/discord)
and follow [thornswood.net/join](https://thornswood.net/join).

## What is in here

- `tools/app`: the launcher. C# 5 and WPF, compiled by
  `tools/Build-Launcher.ps1` with the .NET Framework 4 csc.
- `tools/setup`: the small setup program people download.
- `tools/ts-plugins`: the game plugins, in Skyrim Platform JavaScript.
- `tools/ts-ui`: the overlays inside the game.
- `tools/gamemode.js`: the server's gamemode.
- `tools/docs-app`: the site. Its public pages are `tools/docs-app/data/site`.
- `tools/voice`: proximity voice.
- `tools/discord`: the Discord bot, in Python.
- `tools/*.ps1`: the scripts that build, ship and deploy all of the above.
- `lore/`: the world.

## Before changing anything

- [CLAUDE.md](CLAUDE.md): how work moves between the two machines, the settled
  design and the words we use. Read it first, every session.
- [SECOND-DEVELOPER.md](SECOND-DEVELOPER.md): the long form. What the pieces
  are, how a release goes out, how a machine is set up.
- [HANDOFF.md](HANDOFF.md): open work and what is live.
- [tools/app/HOOKUP.md](tools/app/HOOKUP.md): how the launcher classes fit.
- [IT-IS-DOWN.md](IT-IS-DOWN.md): what to do when the server is down.
- [SECURITY.md](SECURITY.md): how to report a hole quietly.

Everything reaches `main` through a pull request, and `main` is what ships.

## Something wrong in the game

Say so in the [Discord](https://thornswood.net/discord), or on
[thornswood.net/report](https://thornswood.net/report).
