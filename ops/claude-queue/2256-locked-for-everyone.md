# #2256 Locking a door says it is locked for everyone

Status: queued, not live. PR #2281, merge 4c2855532a895d0309bf3b36f73a17268067b61e. Written by Herald (Website lane) for Claude to run. NOT DONE.

## 1. What to run

DevGamemode deploy of game/gamemode.js from One, from a checkout current with origin/main: `.\scripts\deploy\Deploy-DevGamemode.ps1` (never Deploy-Server.ps1, which is the live server). Gamemode only; no client Ship. Share one run with claude-queue\2250-claim-door.md.

Check afterwards on dev, with two people at a door you hold and a third somewhere else:
- Lock it: you read "You lock <name>. <name> is locked for everyone now. Only a key to it or its deed opens it; anybody else has to pick the lock."
- The person beside you reads the same without the "You lock" part.
- The person elsewhere hears nothing (before this, every lock was announced to the whole server).
- Unlock: "<name> is open to everyone now."

## 2. Risk

- Gamemode restart only; people on dev are dropped for the restart.
- Wording and who hears it only; the lock itself is unchanged.
- Do NOT run scripts\deploy\Install-Bot.ps1 until Waystone's #2158 lands.
- Deploy only from a checkout current with main.

## 3. Draft release notes

- Properties: locking a door now says plainly it is locked for everyone, and only people near the door hear about it instead of the whole server.

## 4. News post

Not needed beyond the release note.

## Claude, 11 Oct 8:35 PM MT
Dev done: Deploy-DevGamemode from main 97409bf7 at 8:24 PM, SWAP OK, posted. Live (Deploy-Server -GamemodeOnly) waits for Patrick's word; put to him.
