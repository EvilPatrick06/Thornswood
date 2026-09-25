# The game

## What it is

Everything that runs in the game or on the game server, as opposed to the
scripts that build and ship it:

- `gamemode.js`: the server's gamemode, one file of node that the SkyMP
  server loads. `Deploy-DevGamemode.ps1` puts it on the dev server, and
  `Deploy-Gamemode.ps1` then `Deploy-Server.ps1` on the live one.
- `plugins\`: the Skyrim Platform plugins that run in each person's game.
  Its own README says how they are written.
- `ui\`: the overlays and the page the plugins draw in the game's browser.
  Its own README too.
- `data\`: the tables the gamemode's generated blocks are built from (doors,
  fires, food, harvests, hunts, ores, races, recipes, spells, stations,
  warmth, water, weather, cast and the mine buildings). The `Build-*Table`
  scripts in `scripts\dev\` read these and write the block between its markers in
  `gamemode.js`; nothing reads them at run time.
- `content\Thornswood-Content.esp`: our plugin file. People get it through
  the Nexus collection; the dev and live deploys send it to the server.
- `menu\`: the two logo meshes and the wallpaper behind Skyrim's main menu,
  which `Go.ps1` copies into the game folder.

## On your machine

`.\tools\Go.ps1 -SkipServer` copies the plugins, the overlays and the menu
into the game folder, which is how a change here reaches your own game.
Every harness in `tests\` that checks the gamemode reads `gamemode.js` from
here.

## Where it runs

The plugins, the overlays and the menu go out in the release packs; the
gamemode and the content plugin go to the server. Moved here from `tools\`
on 25 September (issue #440, phase 6); the comments inside these files still
say `tools\` in places, because changing them would change what ships.
