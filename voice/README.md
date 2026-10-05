# Proximity voice and chat

## What it is

`voice-server.js` is one file of node with nothing to install from npm; it
carries its own WebSocket code. The game server posts where everybody is to it
five times a second over loopback (`POST /positions`). Every client holds a
WebSocket to it for those positions, for the WebRTC signalling that sets up
voice between two people, and for text chat, which it relays to the room and
writes to `chat\`, one file a day. The audio goes straight between people and
never passes through it. `public\` is the plain browser page it serves, and
the `test-*.js` files beside it are its harnesses. `gamemode-voice.js` is the
gamemode's half of the position feed as `Add-VoiceFeed.ps1` first added it.
The copy between the voice feed markers in `game\gamemode.js` has moved on
since: it reads its port from `server-settings.json`, so the dev server feeds
the dev service, where this file still has 7778 written in.
`Add-VoiceFeed.ps1` would write this file over that block and redeploy the
live gamemode, undoing that, so it stops when the two differ; `-Force` is the
only way past.

A socket opened by a browser has to come from the page this service serves
(its Origin names the host the socket was asked for, straight or through
Caddy) or from a page loaded off disk, which says `null` or `file://`: the
game's pages and the launcher's voice page. A page on any other website is
refused with 403 before the handshake (#1321). A client that sends no Origin
is not a browser and is let in.

## On your machine

Run it from a scratch copy, as its harnesses do, not from the checkout: on its
first start it makes `token-key.txt` beside itself, the key that signs join
tokens, and `chat\` once anybody talks. Git ignores both, but a signing key
has no business sitting in a checkout. From the copy:

```
$env:THORNSWOOD_VOICE_PORT = '7900'; $env:THORNSWOOD_VOICE_BIND = '127.0.0.1'; node voice-server.js
```

then open http://127.0.0.1:7900/health. It reads `THORNSWOOD_VOICE_PORT`
(7778 when unset), `THORNSWOOD_VOICE_BIND` (every address when unset),
`THORNSWOOD_CHAT_RANGE` (off when
unset, though Install-Voice.ps1 sets it on for live and dev: every typed
line goes to everybody; `on` keeps a line to the same cell
and 4000 units, a number sets the units, and /me, /do, /w and /s work),
`THORNSWOOD_CHAT_BURST` and `THORNSWOOD_CHAT_REFILL_MS` (5 and 1500 when
unset: how many said lines one connection gets out at once, and how often it
earns another; slash lines are never counted), `THORNSWOOD_TOKEN_PER_MINUTE`
and `THORNSWOOD_SOCKETS_PER_MINUTE` (20 and 60 when unset: how many token
requests and sockets one address gets a minute before it is answered 429;
behind Caddy the address is the last `X-Forwarded-For` hop, and this machine
itself is never counted, #1323) and `THORNSWOOD_SITE`, the
site `/token` asks whether a Discord ticket owns the profile it wants a join
token for. A join that cannot prove itself with a token is refused, and
`/token` mints one only when the site says yes: with the site unset, down or
answering anything else, it answers 503 and mints nothing (#1303, #1315).
`THORNSWOOD_VOICE_AUTH`, which once let unproven joins in, is not read any
more. `/health`
reports
the `BUILD` string at the top of the file, which is the only way to tell from
outside which copy is running, so change it whenever behaviour changes. The
harnesses run the real file in a temporary folder on a port the system hands
out, and ask it nothing until that copy has said it is listening there,
because several builds run at once on the VPS and a fixed port let one run
answer another (#1703). They need nothing else: each puts its own
`token-key.txt` beside its copy and signs the tokens it joins with, and
`test-auth.js` answers `/token`'s questions with a small site of its own.
`node voice\test-auth.js` and the rest.

A TURN relay, for the pairs of people who cannot reach each other directly,
is `THORNSWOOD_TURN_URL`. Its key is `THORNSWOOD_TURN_SECRET` or, so it stays
off the command line `Install-Voice.ps1` builds, `turn-key.txt` beside the
service, put there by hand. Unless both are there, `/ice` offers STUN only; with
neither, `/health` says `turn: none`, which is how every box runs today.
`Install-Voice.ps1 -TurnUrl` sets the address. `test-turn-key.js` covers it.

## Where it runs

On the VPS beside the game servers: the live service in `C:\Thornswood-Voice`
on 7778, task `Thornswood Voice`, and the dev one in `C:\Thornswood-Voice-Dev`
on 7789, task `Thornswood Dev Voice`. Caddy carries
https://thornswood.net/voice/ and /voice-dev/ to them. What it carries comes
from loopback as the gamemode does, so the gamemode's routes (`/positions`,
`/commands`, `/silenced`, `/textmute`, `/say`) also refuse any request with a
forwarding header on it, which Caddy always sets (#1797). Its clients are the
launcher's hidden voice page (`launcher`), the in-game overlays
(`game\ui`) and the two gamemodes. `.\scripts\deploy\Install-Voice.ps1` copies
`voice-server.js` and the two files in `public\`, restarts the task and waits
for `/health`; the dev service is the same script with
`-Root C:\Thornswood-Voice-Dev -Port 7789 -TaskName 'Thornswood Dev Voice'`.
`Go.ps1` without `-SkipServer` also copies this file over the live one and
restarts it.
