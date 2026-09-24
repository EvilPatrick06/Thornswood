# The site

## What it is

The Thornswood website, https://thornswood.net, as one file of node,
`server.js`, with nothing to install from npm. It serves the public pages
(`data\site\*.md`), the news, the installer download and the member pages
behind the password, and after a Discord sign in, the admin hub and its boards
(`data\*.md`, `data\board.json`). It is also the door: the game servers and
the launchers ask it who may play (`/api/allowed`, and `/dev/api/allowed` for
the dev server), and it answers from the Discord roles in its config.
`public\` holds the pages and the art it serves as they are.

## On your machine

It needs node and nothing else. Run it from a copy of this folder rather than
from the checkout, because it writes beside itself: `config.json` with a fresh
cookie secret, `site.log`, the `files\` and `uploads\` folders, and anything
typed into a board or a page in the browser goes into `data\`, which git
tracks. From the copy:

```
$env:THORNSWOOD_DOCS_PORT = '3101'; $env:THORNSWOOD_DOCS_LOCAL = '1'; node server.js
```

then open http://127.0.0.1:3101. Left unset it listens on every address on
3001. Without a `config.json` it runs on the defaults written in `server.js`:
the member password is the one written there, and Discord sign in and the role
checks are off, since there is no client id or bot token. The game status and
the chat under each session read files that only exist on the VPS
(`C:\Thornswood-Server\data\online.json`, `C:\Thornswood-Voice\chat`), so
locally the game shows as down.

## Where it runs

On the VPS in `C:\Thornswood-Docs`, started by the scheduled task
`Thornswood Docs`, answering on 127.0.0.1:3001 only. Caddy holds ports 80 and
443 and the certificate in front of it (`tools\Caddyfile` is the reference
copy of the live `C:\Thornswood-Caddy\Caddyfile`), and `Setup-Domain.ps1` is
what set `THORNSWOOD_DOCS_LOCAL=1` there. Its `config.json` on the VPS holds
the member password, the Discord client secret and bot token, the bot's key
and the cookie secret, and is never in the repo. `.\tools\Deploy-Docs.ps1`
sends `server.js` and everything in `public\` and restarts the task, and
`-Site` also sends the public pages. A plain deploy never overwrites a
document somebody has typed into on the site; `-Boards`, `-Docs` and
`-SeedDocs` do, after a `.bak` of each.
