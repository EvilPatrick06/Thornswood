# 2321 The bot reads the game's staff log from for-bot

**Dev ran 12 Oct 2026: Install-Bot -NoToken 8:05 AM, Deploy-DevGamemode 13f88fcc 8:07 AM. Left: live gamemode, on Patrick's word.**

- **Lane:** Claude (overnight, server-defects)
- **Issue / PR:** #2321, #2375 (merged as c40c708b)
- **Channel:** VPS (bot) and dev (gamemode); live gamemode only on Patrick's word
- **Staff status updates:** #staff-updates (1549254991082946570)
- **Needs first:** nothing

## Run
From a fresh worktree at origin/main (c40c708b or later), in this order:

    .\scripts\deploy\Install-Bot.ps1
    .\scripts\deploy\Deploy-DevGamemode.ps1 -Note "Staff actions on the test server reach the staff channel again
    - What staff do in the world is said in the staff channel from a place the bot can always read."

The first is a FULL Install-Bot, not -CodeOnly: -CodeOnly gives no rules. It makes `C:\Thornswood-Server\for-bot` and `C:\Thornswood-Server-Dev\for-bot`, gives the bot's account read on each, takes the bot's old rule off `private\moderation.log`, and restarts the bot on the new bot.py, which reads for-bot.

Either order works: a gamemode that runs before the bot install makes for-bot itself, and the next full Install-Bot puts the rule on the folder, which reaches the file already in it. Lines written before the bot restarts are taken as already said (that has always been so at a bot start).

Live: the live server's gamemode writes for-bot once main's gamemode is deployed (`Deploy-Server.ps1 -GamemodeOnly`), on Patrick's word. Until then live still writes `private\moderation.log`, which the new bot no longer reads; the live server had no staff log at all on 11 Oct, so nothing is lost that was being read.

## Check afterwards
- Install-Bot prints `granted the bot's account read, on the staff log the gamemode writes there and any it makes later, on C:\Thornswood-Server\for-bot` and the same for `-Dev`, and `took the bot's account off ...\private\moderation.log` for dev (dev had one, 532 bytes, 7 Oct).
- bot.log: `moderation: reading C:\Thornswood-Server\for-bot\moderation.log, C:\Thornswood-Server-Dev\for-bot\moderation.log, ...` and no `moderation: cannot read` line.
- Readback on the box: `icacls C:\Thornswood-Server-Dev\for-bot` shows `NT SERVICE\ThornswoodBot:(OI)(CI)(R)`; `icacls C:\Thornswood-Server-Dev\private` does not name the bot.
- After the dev gamemode is up, one staff action on dev (a /warn on yourself) appears in the staff channel and in `C:\Thornswood-Server-Dev\for-bot\moderation.log`.

## Risks and how to put it back
- A full Install-Bot restarts the bot: about a minute with no bot.
- `.\scripts\deploy\Install-Bot.ps1 -PutBack` puts the previous bot code back. The old private\moderation.log stays on dev untouched, so going back loses nothing; the old bot reads private again, and its rule there would need the previous Install-Bot to give it again.
- `.\scripts\deploy\Deploy-DevGamemode.ps1 -PutBack` puts the previous gamemode back.

## Release notes (draft)
Staff actions in the world reach the staff channel again, from a place the bot can always read.

## News post (draft)
none

## Test task (draft, for closing the issue once the fix is on main)
Test task: Staff actions reach the staff channel
1. On the main server, as staff, give someone a warning from the staff menu or with /warn.
2. Look in the staff channel in Discord.
What should happen: within a minute the staff channel says who warned whom and why.
