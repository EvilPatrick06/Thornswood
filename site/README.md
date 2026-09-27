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

These are what ask it for something other than a page, and each of them stops
working while the site is down. `/api/play/join` is the launcher's question
before every launch; when the site does not answer, a yes from the last 72
hours still starts the game (`GraceHours` in `launcher\app\Door.cs`) and nothing
else does.

| Route | Method | Asked by |
| --- | --- | --- |
| `/api/play/join` | POST | the launcher, before every launch (`launcher\app\Discord.cs`) |
| `/api/play/start`, `/api/play/end`, `/api/play/logs` | POST | the launcher, as a session starts, as it ends, and with the logs after (`launcher\app\Discord.cs`) |
| `/api/play/roster` | POST | the launcher, for the names on the character cards (`launcher\app\Roster.cs`) |
| `/auth/discord` | GET | the launcher's link button, through the browser; Discord sends the browser back to `/auth/discord/callback` (`launcher\app\Discord.cs`) |
| `/api/allowed`, `/dev/api/allowed` | GET | each game server's door, every five minutes, with the bot's key; the dev server's `door.json` names the site with `/dev` on the end (`game\gamemode.js`) |
| `/api/roster` | POST | the game server, with the bot's key, when its book of characters changes (`game\gamemode.js`) |
| `/api/play/owns` | POST | the voice service, before it keeps a character creation choice (`voice\voice-server.js`) |
| `/api/payload` | GET | the installer, which then downloads the zip it names from `/file/` (`installer\setup\Bootstrap.cs`) |
| `/api/ticket` | POST | the Discord bot, for a support ticket (`bot\bot.py`) |
| `/api/play/who` | POST | nothing in the repo asks it now. It says who a ticket belongs to and writes nothing, which makes it the one to try by hand |

## On your machine

It needs node and nothing else. Run it from a copy of this folder rather than
from the checkout, because it writes beside itself: `config.json` with a fresh
cookie secret, `site.log`, the `files\` and `uploads\` folders, and anything
typed into a board or a page in the browser goes into `data\`, which git
tracks. Copy `config.sample.json` into the copy as `config.json` first. It is
every setting `server.js` reads, holding what it runs on when there is no
`config.json` at all: the member password written in `server.js`, the roles,
and every Discord setting, the bot's key and the cookie secret empty. Empty is
what keeps a copy on your machine from asking Discord anything. A
`config.json` already in this folder is that machine's own, and git ignores it;
leave it where it is rather than copying it. From the copy:

```
$env:THORNSWOOD_DOCS_PORT = '3101'; $env:THORNSWOOD_DOCS_LOCAL = '1'; node server.js
```

then open http://127.0.0.1:3101. Left unset it listens on every address on
3001. Without a `config.json` it runs on the defaults written in `server.js`:
the member password is the one written there, and Discord sign in and the role
checks are off, since there is no client id or bot token. The game status and
the chat under each session read files that only exist on the VPS
(`C:\Thornswood-Server\data\online.json`, `C:\Thornswood-Voice\chat`, and
`C:\Thornswood-Voice-Dev\chat` for a dev session), so locally the game shows
as down.

To see the door answer, from a second window:

```
curl.exe -i -X POST -H "Content-Type: application/json" -d "{}" http://127.0.0.1:3101/api/play/who
```

It answers 401 with `{"ok":false,"why":"link"}`, because no ticket was sent.
It is POST only: a GET answers 401 as well, but from the sign in gate with
`sign in first`, which says nothing about the door. `curl.exe` rather than
`curl`, because in Windows PowerShell `curl` is another name for
Invoke-WebRequest. With no bot token the copy counts every Discord account as
allowed in, so a ticket signed with the `secret` it wrote into its own
`config.json` gets a 200, which is how a change to the door can be tried
without Discord. `tests\test-site-local.js` does all of this against copies in
the temp folder, and never reads a `config.json` out of the checkout.

## Where it runs

On the VPS in `C:\Thornswood-Docs`, started by the scheduled task
`Thornswood Docs`, answering on 127.0.0.1:3001 only. Caddy holds ports 80 and
443 and the certificate in front of it (`scripts\deploy\Caddyfile` is the reference
copy of the live `C:\Thornswood-Caddy\Caddyfile`), and `Setup-Domain.ps1` is
what set `THORNSWOOD_DOCS_LOCAL=1` there. Its `config.json` on the VPS holds
the member password, the Discord client secret and bot token, the bot's key
and the cookie secret, and is never in the repo. `.\scripts\deploy\Deploy-Docs.ps1`
sends `server.js` and everything in `public\` and restarts the task, and
`-Site` also sends the public pages. A plain deploy never overwrites a
document somebody has typed into on the site; `-Boards`, `-Docs` and
`-SeedDocs` do, after a `.bak` of each. `-Password` reads the `config.json`
on the VPS, changes the member password in it and keeps every other setting.
A `config.json` there that will not read as JSON, an empty one included, is
left exactly as it is and the password is not changed.
`tests\test-docs-password.ps1` runs that part of the script against copies.

The pages, the downloads, the hub and every route in the table above are one
node process. A route that throws is answered 500 and the rest carry on, and a
throw in a timer is logged and carried on from, so a broken page does not take
the door with it. What one process cannot keep apart: anything that holds its
event loop holds the door for as long, and every `Deploy-Docs.ps1` restarts the
door along with the pages. `tests\test-site-local.js` measures the first two
against a copy: with a page made to throw, `/api/play/who` still answers its
401, and with a page made to hold the loop for a second and a half, the same
question waits until it lets go.

## The gallery

The public gallery is `data\gallery.json`, a list of `{ name, url: '/shot/'+name,
by }`. `/api/public` hands it out under `gallery` and `GET /shot/<name>` serves
the file from `uploads\` only when the name is on that list. A picture reaches
that list through a queue an admin approves, so nothing a stranger sends is
public until somebody says so. The queue is `data\gallery-pending.json`, an
array that starts `[]`, deployed by the same rule as every other data JSON
(`Deploy-Docs.ps1` sends a data JSON only when the VPS is missing it, so the
queue is never overwritten once it exists there). `/api/public` and `/shot`
never read the queue.

| Route | Method | Who | Body | Answers |
| --- | --- | --- | --- | --- |
| `/api/gallery/submit` | POST | a hub member (the `/api/upload` cookie), or the launcher with the same signed ticket it sends `/api/play/join` | the file is the body, the way `/api/upload` takes it; `name`, `by`, `note` and, for the launcher, `ticket` are in the query | `200 {ok,name}`; `401 {why:'link'}` with neither door; `403`/`503` for a launcher ticket the door would also refuse; `415` for anything but png, jpg, jpeg, webp or gif; `413` over 25 MB |
| `/api/gallery/pending` | GET | admin | none | `200 {pending:[...]}`; `403` otherwise |
| `/api/gallery/approve` | POST | admin | `{name, by?}` | `200 {ok,approved}`; upserts the name onto `gallery.json`, removes it from the queue, idempotent; `400` with no name |
| `/api/gallery/reject` | POST | admin | `{name, deleteFile?}` | `200 {ok,removed}`; drops it from the queue and unlinks the upload when `deleteFile` is set; `gallery.json` is untouched; `400` with no name |

A submission lands in `uploads\` under the same stamped name `/api/upload` uses
(`receiveUpload` in `server.js` is the one helper both go through) and adds
`{ name, by, note, at, from: 'web'|'launcher', discordId? }` to the queue. The
cap is 25 MB rather than the 200 MB `/api/upload` takes for logs, and only
images are taken: `/shot` serves with a plain `Content-Length` and no range,
which a browser needs before it will play an mp4, so video waits until `/shot`
honours a range. The Uploads page in the hub shows the queue to an admin with
Approve and Reject on each. `tests\test-gallery.js` drives all four routes end
to end against a copy. Deploy with `.\scripts\deploy\Deploy-Docs.ps1`, which
sends `server.js`, the hub page and the empty queue file.
