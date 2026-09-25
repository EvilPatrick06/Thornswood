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
`Add-VoiceFeed.ps1` writes this file over that block and redeploys the live
gamemode, so running it would undo that.

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
`THORNSWOOD_VOICE_AUTH` (`log` when unset: a join that cannot prove itself is
let in and written down; `on` refuses it), `THORNSWOOD_CHAT_RANGE` (off when
unset: every typed line goes to everybody; `on` keeps a line to the same cell
and 4000 units, a number sets the units, and /me, /do, /w and /s work),
`THORNSWOOD_CHAT_BURST` and `THORNSWOOD_CHAT_REFILL_MS` (5 and 1500 when
unset: how many said lines one connection gets out at once, and how often it
earns another; slash lines are never counted) and `THORNSWOOD_SITE` (when
unset, nobody is asked whether a join owns the profile it claims). `/health`
reports
the `BUILD` string at the top of the file, which is the only way to tell from
outside which copy is running, so change it whenever behaviour changes. The
harnesses run the real file in a temporary folder on a spare port and need
nothing else: `node voice\test-auth.js` and the rest.

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
https://thornswood.net/voice/ and /voice-dev/ to them. Its clients are the
launcher's hidden voice page (`launcher`), the in-game overlays
(`game\ui`) and the two gamemodes. `.\tools\Install-Voice.ps1` copies
`voice-server.js` and the two files in `public\`, restarts the task and waits
for `/health`; the dev service is the same script with
`-Root C:\Thornswood-Voice-Dev -Port 7789 -TaskName 'Thornswood Dev Voice'`.
`Go.ps1` without `-SkipServer` also copies this file over the live one and
restarts it.
