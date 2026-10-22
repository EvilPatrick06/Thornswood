# #502 No bounty for killing or striking an NPC (dev Ship)

**Dev ran 12 Oct 2026: dev Ship 20261012-080945-dev ~8:12 AM. Left: main.**

**12 Oct, later: superseded on main by `502-guards-decisions.md`** (#2472 widens this to every crime). Use that note's release line and test task for the main run; this note's main line and test task are kept only for the record.

- **Lane:** Claude (overnight run, guards)
- **Issue / PR:** #502, #2371 (merged as c00089aa); #2391 (merged as 13f88fcc) takes out the respawn step that cleared the guards' arrest flag, front plugin too, same Ship
- **Channel:** dev
- **Staff status updates:** #staff-updates (1549254991082946570)
- **Needs first:** nothing. This is a front plugin change, so it goes out in a dev Ship. It can share a Ship with other front plugin and page notes in this folder, including 502-guards-cells-board.md, which changes the board page.

## Run
From the shared clone, current with origin/main at or after 13f88fcc:
    git fetch origin
    git checkout --detach origin/main
    .\scripts\release\Ship.ps1 -Channel dev "Killing someone in a town no longer puts a bounty on you
    - Killing or striking a trader or anybody else in a hold no longer adds a bounty in that hold."

## Check afterwards
- After joining dev, `Data\Platform\thornswood-front.log` has one line: `no bounty for a kill or a blow: 12 of 12 crime factions now ignore murder and assault`. A line with `REFUSED` or `not in this load order` names the faction that did not take it. Read that before anything else.
- In game on dev: strike a trader, then kill one, in Whiterun. The Journal (General Stats, Crime) shows no bounty for Whiterun.

## Risks and how to put it back
- Nothing to undo on the server. If the log says REFUSED for every faction (Skyrim Platform does not have SKSE's faction flags on this client), nothing changes from today, and the cause is written on #502. Ship the previous front plugin to put it back.
- Theft, pickpocketing and trespass still add a bounty. That is waiting on Patrick's answer on #502.

## Release notes (draft)
Killing someone in a town no longer puts a bounty on you
- Killing or striking a trader or anybody else in a hold no longer adds a bounty in that hold.

## News post (draft)
none

## Test task (draft, for closing once all of #502 is on main)
Test task: No bounty for killing in a town
1. Join the main server and go to Whiterun.
2. Open the Journal, General Stats, and look at the bounty for Whiterun.
3. Hit a trader in the market, then kill them.
4. Open the Journal again and look at the bounty for Whiterun.
What should happen: Whiterun's bounty is the same as before, with nothing added for the blow or the kill.
