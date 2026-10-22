# 1387 Withered: too many potions or restoration casts in an hour (dev gamemode)

**Dev ran 12 Oct 2026 1:50 AM: Deploy-DevGamemode from origin/main e4d08763 (.prev-20261012-015022). Left: main, on Patrick's word.**

- **Lane:** Claude (overnight run, 12 Oct, slug gamemode-world)
- **Issue / PR:** #1387, #2365 (merged as e4d08763)
- **Channel:** dev
- **Staff status updates:** #staff-updates (1549254991082946570)
- **Needs first:** nothing. Gamemode only, no client or server build change. It makes one new property (`thornswoodWithered`, server only), so it needs the restart a deploy does. Can ride with #2337's dev gamemode deploy (wiki/claude-queue/2337-kiln-menu.md) from a main containing both 8f3bc518 and e4d08763.

## Run
From the shared clone, at an origin/main that contains e4d08763:

    .\scripts\deploy\Deploy-DevGamemode.ps1

## Check afterwards
- The script reports the dev server came back on the gamemode it sent, and server.log has `[college] ready`.
- On dev: drink five potions inside an hour. The fifth says "You are withered: five potions in an hour. For 30 minutes your health and magicka are four fifths of what they were." and the health and magicka bars shrink. Relog: still withered. 30 minutes after the fifth potion: "The withering has passed." and the bars come back. Server log: `[college] <id> is withered for 30 minutes ...` and later `is no longer withered`.
- Four potions in an hour, food, ale or a poison do nothing.

## Risks and how to put it back
- Max health and magicka are taken down by a fifth of what the race, the skill tree and the needs give; a fortify from gear or a running potion is not counted in that, because the server cannot see it.
- The cooked meal and bed clear on the potions page is not built (it waits for #1382). Only the 30 minutes clear it.
- Put back: `.\scripts\deploy\Deploy-DevGamemode.ps1 -PutBack`.

## Release notes (draft)
Too many potions leave you withered
- Five potions in an hour, or ten restoration spells in an hour, leave you withered for 30 minutes: your health and magicka are four fifths of what they were. You are told when it starts and when it passes.

## News post (draft)
Potions are a mouthful, not a way to live: drink five in an hour, or cast ten restoration spells in an hour, and you are withered for half an hour, with a fifth of your health and magicka gone until it passes.

## Test task (draft, for closing the issue once it is on main)
Test task: Too many potions leave you withered
Server: Main
1. Carry at least five potions of any kind, for example healing potions.
2. Drink four of them, a minute or two apart, and look at your health and magicka bars.
3. Drink the fifth, inside the same hour.
4. Log out and back in.
5. Wait 30 minutes from the fifth potion.
What should happen: The first four do nothing more than usual. The fifth tells you that you are withered, and your health and magicka bars shrink to about four fifths. Logging out and back in does not lift it. After 30 minutes you are told the withering has passed and the bars are back to full size.
