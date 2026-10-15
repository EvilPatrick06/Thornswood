# The in-game page and overlays

## What it is

What the game's browser shows: the page Skyrim Platform opens over the game
and the overlays drawn into it, plain JavaScript and HTML with nothing built.
`index.html` is the page. It is the front's own page, whose `build.js` comes
from `local\thornswood-front.zip`, plus `thornswood-bridge.js`, which supplies
what that page expects from a browser this one is not, and the character
choice at the main menu, `thornswood-select.js`, which draws itself before any
plugin runs. `thornswood-front.js` in `game\plugins` then fetches the
overlays into that one page: the chat (`thornswood-chat.js`, which holds the
one socket to the voice service), the emote wheel, voice, the character panel
and character creation behind K (`thornswood-skills.js`), the party menu
behind P, journals behind J, the trade panel, the repair panel that a key
in the inventory opens while a repair kit is carried (`thornswood-repair.js`),
the wounds panel that a key in the inventory, or X on somebody hurt, opens
(`thornswood-treat.js`),
the stops and fares of a carriage or ferry driver that E on the driver
opens (`thornswood-ride.js`), the hold's drop box that E on the box on a
notice board opens (`thornswood-box.js`), the help that the help key, F7, and Help on
the K, P and J panels open (`thornswood-help.js`), and the "Are you still here?"
window after 15 minutes idle (`thornswood-afk.js`). `thornswood-theme.mp3` is
the theme the main menu plays, and the launcher plays it too while it is open.

## On your machine

From the repo folder, with the game closed:

```
.\scripts\release\Go.ps1 -SkipServer
```

unpacks the front from `local\thornswood-front.zip` into
`C:\Thornswood\Game\Data\Platform\UI` (`-Game` names another game folder),
copies every `.js`, every `.mp3` and `index.html` from here over it so ours
wins, and copies the site's banner from `site\public` in as the
menu's painting. It copies nothing else from this folder. The zip is not in
git and nothing in the repo builds it; without it Go.ps1 says so and leaves
the front that a release already put in the game folder. `-SkipServer`
matters: without it Go.ps1 also copies the voice service over the live one on
the VPS and restarts it. The plugins' two rules apply here too: the launcher
holds these files read only while the game runs, and Keep puts its copy back
at Play, so Go.ps1 makes what it installs the kept copy and a file copied in by
hand is undone. A new overlay has to
be called `thornswood-*.js`, like every other file of ours under
`Data\Platform`, and named in the `OVERLAYS` list at the top of
`thornswood-front.js`, or nothing loads it. There is no build step; the
`tests\test-*.js` harnesses read several of these files and check them.

## Where it runs

In `Data\Platform\UI` in every person's game folder, drawn by the browser
Skyrim Platform runs over the game. The files reach people in a release pack
the same way as the plugins: Ship runs Go.ps1 into the shipping machine's game
folder, Publish-Update packs what changed (and puts this `index.html` back
first if another server's menu has replaced it), and each launcher unpacks the
pack, keeps a copy and holds the files read only while the game runs. Every
change goes to the dev build first, with
`.\scripts\release\Ship.ps1 -Channel dev "what changed"`.
