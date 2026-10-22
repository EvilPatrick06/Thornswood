# #502 Guards: jail cells and notice boards of their own hold (dev gamemode, then dev Ship)

**Ready: both pull requests are merged (12 Oct 2026).** One dev gamemode deploy carries both. The board page goes out with the next dev Ship.

- **Lane:** Claude (overnight run, guards)
- **Issue / PR:** #502, #2377 jail cells (merged as ffba0acb), #2394 board take down (merged as 51bb1195)
- **Channel:** dev
- **Staff status updates:** #staff-updates (1549254991082946570)
- **Needs first:** the dev server running the server build main records (`records\server-build.json`, native 9035ea46, from #2070). Since #2081, `Deploy-DevGamemode.ps1` refuses to send a gamemode onto any other server build and says so before anything is sent. That build goes onto dev in Stage B of `1373-merchant-quests.md`, so this deploy runs with or after that stage. If the dev server is already on it, nothing else is needed first.

## Run
From the shared clone, current with origin/main at or after 51bb1195:
    git fetch origin
    git checkout --detach origin/main
    .\scripts\deploy\Deploy-DevGamemode.ps1
The board page (`game\ui\thornswood-board.js`) goes out in the next dev Ship from a checkout at or after 51bb1195. It can share that Ship with `1385-client-perks.md` and any other page or front plugin note. It needs no line of its own in the Ship's notes, because nobody can be a guard yet. Nothing breaks while the page waits, because the server only ever offers a guard's Take down to a guard.

## Check afterwards
- The script prints that the dev server runs the build this commit records, then the restart and the log tail.
- The dev server log at boot has `[property] law: read 0 guard(s) and 0 cell door(s) a guard has turned`. Zero is right: nothing names a guard until Patrick decides who does (#502).
- Nothing in the world changes until a guard can be named. A cell door still offers Claim on the jail building as before. The board page shows Take down only on your own posts.

## Risks and how to put it back
- A gamemode restart drops anybody on dev. The script warns them first.
- `private\law.json` is new and is only written when a guard turns a cell, which nobody can do yet.
- To undo, `.\scripts\deploy\Deploy-DevGamemode.ps1 -PutBack`.

## Release notes (draft)
none until a guard can be named

## News post (draft)
none

## Test task (draft, for closing #502 once it is on main and a guard can be named)
Test task: A guard holds their own hold's cells
1. Two testers join main. A guard of Whiterun is named for the first, the way it is settled.
2. Both go to Dragonsreach Dungeon. The guard opens a cell door, lets the second tester in, closes it and presses the lock key on it.
3. The second tester tries the cell door.
4. The guard walks to the Whiterun notice board and takes down a notice the second tester posted.
5. The guard goes to the Riften board and Riften's jail and tries the same there.
What should happen: The cell stays shut for the second tester and opens for the guard. In Whiterun the guard can take the notice down, and the poster is told. In Riften the guard has no Take down on other people's posts and no lock key on the cells.
