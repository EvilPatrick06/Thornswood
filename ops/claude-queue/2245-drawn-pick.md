# #2245 Mining with the pickaxe drawn skipped the animation and gave ore on click

Status: queued, not live. PR #2286, merge 97409bf756afe40a5ea96545b511bfaa6f6134a3. Written by Herald (Website lane) for Claude to run. NOT DONE.

## 1. What to run

DevGamemode deploy of game/gamemode.js from One, from a checkout current with origin/main: `.\scripts\deploy\Deploy-DevGamemode.ps1` (never Deploy-Server.ps1, which is the live server). The swing script is set when the property is made, so it needs the gamemode restart the deploy does. Gamemode only; no client Ship. Share one run with the 2244, 2250 and 2256 notes.

Dev check (a Miner with a pickaxe, at an iron seam):
- Draw the pickaxe, then press the seam: the weapon is put away, then about a second later the pickaxe animation plays and strikes land with the sound. Ore comes with the strikes, not instantly on the click with no animation.
- With nothing drawn: the animation starts at once, as before.
- Press again to stop: the animation ends and you are freed (you can jump and sprint), and a pick that was drawn or worn is back on you.

## 2. Risk

- Gamemode restart only; people on dev are dropped for the restart.
- Known small gap: the first strike is paid 900 ms after the press, so with a drawn weapon the first ore can land just before the animation starts.
- Do NOT run scripts\deploy\Install-Bot.ps1 until Waystone's #2158 lands.
- Deploy only from a checkout current with main.

## 3. Draft release notes

- Mining: pressing a seam with your pickaxe already out now puts it away and plays the mining animation, instead of skipping it.

## 4. News post

Not needed beyond the release note.

## Claude, 11 Oct 8:35 PM MT
Dev done: Deploy-DevGamemode from main 97409bf7 at 8:24 PM, SWAP OK, posted. Live (Deploy-Server -GamemodeOnly) waits for Patrick's word; put to him.
