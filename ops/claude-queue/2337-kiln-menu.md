# 2337 The charcoal kiln opens its menu and no press burns firewood (dev gamemode)

**Dev ran 12 Oct 2026 1:50 AM: Deploy-DevGamemode from origin/main e4d08763 (.prev-20261012-015022). Left: main, on Patrick's word.**

- **Lane:** Claude (overnight run, 12 Oct, slug gamemode-world)
- **Issue / PR:** #2337, #2355 (merged as 8f3bc518)
- **Channel:** dev
- **Staff status updates:** #staff-updates (1549254991082946570)
- **Needs first:** nothing. Gamemode only, no new property, no client or server build change. Can ride with any other dev gamemode deploy from a main that contains 8f3bc518.

## Run
From the shared clone, at an origin/main that contains 8f3bc518 (`git fetch origin; git log -1 origin/main`):

    .\scripts\deploy\Deploy-DevGamemode.ps1

## Check afterwards
- The script reports the dev server came back on the gamemode it sent.
- On dev, as a Woodworker (Charburner) with firewood: press a charcoal kiln. The crafting menu opens and lists Poor Charcoal, the Tool Handle and the Splint (Woodwright novice), and the higher grades by rank. No chat line about "Press it again to burn". Leave and press again inside 15 seconds: still no firewood taken.
- Dev server.log: `User N tries to craft 0x... on workbench 0x...` for each thing made at the kiln, and no `[...]` kiln yield line.
- Somebody who is not a woodworker pressing the kiln is still told the bench is not theirs.

## Risks and how to put it back
- Charcoal is now only made through the kiln's menu (2, 4, 7 or 12 firewood a grade, graded by the Charburner rank), not by pressing. Anybody used to the press will find it gone; that is the change.
- Put back: `.\scripts\deploy\Deploy-DevGamemode.ps1 -PutBack`.

## Release notes (draft)
The charcoal kiln is a proper bench
- Pressing a charcoal kiln opens its crafting menu, where woodworkers make the tool handle, the splint and charcoal.
- Pressing the kiln no longer burns your firewood by itself; each grade of charcoal is made in the menu and costs the firewood it lists.

## News post (draft)
Woodworkers: the charcoal kiln now opens its crafting menu like any other bench. Tool handles, splints and every grade of charcoal are made there, and pressing the kiln never spends your firewood on its own.

## Test task (draft, for closing the issue once the fix is on main)
Test task: Make a tool handle at the kiln
Server: Main
1. Play a Woodworker who took Charburner and carry at least five firewood.
2. Go to a charcoal kiln and press it.
3. In the menu that opens, make a Tool Handle, then Poor Charcoal.
4. Leave the kiln and press it again straight away, then leave without making anything.
5. If you can, ask a Woodwright to make a Splint at the same kiln.
What should happen: The kiln's crafting menu opens every time you press it. Each thing you make takes the firewood it lists. Pressing the kiln and leaving never takes firewood or gives charcoal by itself. A Woodwright can make the Splint there.
