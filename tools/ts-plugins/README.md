# The game plugins

## What it is

Skyrim Platform JavaScript, the part of Thornswood that runs inside the game.
Skyrim Platform runs every `.js` in the game folder's `Data\Platform\Plugins`
in the game's own node, and reloads one the moment its file changes. Nothing
here is built or bundled: the file in the repo is the file that runs.
`thornswood-front.js` is the one plugin that owns the game's browser: it loads
the page from `tools\ts-ui` once, mounts the overlays into it and does most of
the client's own work. `thornswood-emotes.js` is the game side of the emote
wheel, `thornswood-voice.js` the game side of proximity voice (who you are,
where to call, push to talk), and `thornswood-mark.js` writes down the spot
you stand on for `Mark-Spot.ps1`. Every one of them
idles unless the client settings point at our server and the launcher has left
a fresh session note, `Data\Platform\thornswood-session.txt`.

## On your machine

From the repo folder, with the game closed:

```
.\tools\Go.ps1 -SkipServer
```

copies every `.js` here into `C:\Thornswood\Game\Data\Platform\Plugins`
(`-Game` names another game folder, such as the dev build's), puts the page
and the overlays from `tools\ts-ui` beside them, and removes anything in that
folder that is not ours. It also puts the menu art and the recorded client in
place. `-SkipServer` matters: without it Go.ps1 also copies
`voice\voice-server.js` over the live voice service on the VPS and
restarts it. The game has to be closed because the launcher holds these files
read only while it runs (Hold). Keep puts its own copy back at every Play, so
Go.ps1 makes what it installs the kept copy, the way a pack does; an edit
copied in by hand, not through Go.ps1, lasts until the next Play. A new plugin has to be called `thornswood-*.js`: Keep parks any
other plugin, and a pack carries nothing else from this folder
(`Ship-Rules.ps1`). There is no build step; `node --check` parses a file, and
the `tools\test-*.js` harnesses read these files and check them.

## Where it runs

In `Data\Platform\Plugins` in every person's game folder, the `Game` folder
beside their launcher. A release takes them there: Ship runs Go.ps1 into the
shipping machine's game folder and stops if a plugin there is not byte for
byte the one in this folder, Publish-Update packs the ones that changed, and
each launcher unpacks the pack into its game folder, keeps a copy of our files
(Keep) and holds them read only while the game runs (Hold). Every change goes
to the dev build first, with `.\tools\Ship.ps1 -Channel dev "what changed"`.
