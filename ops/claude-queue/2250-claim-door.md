# #2250 /claim at some doors said a farmer can bring crops in

Status: queued, not live. PR #2280, merge a3662a23674b080e14f3d59794a84b51392f6985. Written by Herald (Website lane) for Claude to run. NOT DONE.

## 1. What to run

DevGamemode deploy of game/gamemode.js from One, from a checkout current with origin/main: `.\scripts\deploy\Deploy-DevGamemode.ps1` (never Deploy-Server.ps1, which is the live server). Gamemode only; no client Ship needed. Can share one run with the other queued gamemode notes (2256 and any after it).

Check afterwards on dev, as a character who is not a farmer:
- /claim at a door no building owns: "That door does not belong to a building anybody can hold..." (not "Only a farmer can bring a crop in").
- Open a house door, wait over a minute, /claim: "Open the door of <name> again and press the key straight away..."
- Open a house door and press the lock key at once: the claim still goes through.
- A farmer at a crop plot: /claim still claims the field.

## 2. Risk

- Gamemode restart only; people on dev are dropped for the restart.
- Nothing is claimed by the new answers; they only replace the wrong farming refusal.
- Do NOT run scripts\deploy\Install-Bot.ps1 until Waystone's #2158 lands.
- Deploy only from a checkout current with main (10 Oct a stale checkout rolled back a live fix).

## 3. Draft release notes

- Properties: /claim at a door that cannot be held, or a while after opening a door, now says so instead of telling you only a farmer can bring a crop in.

## 4. News post

Not needed beyond the release note.

## Claude, 11 Oct 8:35 PM MT
Dev done: Deploy-DevGamemode from main 97409bf7 at 8:24 PM, SWAP OK, posted. Live (Deploy-Server -GamemodeOnly) waits for Patrick's word; put to him.
