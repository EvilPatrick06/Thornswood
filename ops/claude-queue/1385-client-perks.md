# #1385 Unshakeable, Tireless and Windwalker's fall (dev Ship and dev gamemode, together)

- **Lane:** Claude (overnight run, client perks)
- **Issue / PR:** #1385, #2386 (merged as 2d29a480)
- **Channel:** dev
- **Staff status updates:** #staff-updates (1549254991082946570)
- **Needs first:** the dev server running the server build main records (`records\server-build.json`, native 9035ea46, from #2070). `Deploy-DevGamemode.ps1` refuses any other server build (#2081) and says so before anything is sent; Stage B of `1373-merchant-quests.md` puts that build on dev. Both halves go out together: the front plugin and K panel in a dev Ship, the server's half in a dev gamemode deploy. Either order is safe (see Risks), but run them back to back. The Ship can share a run with `502-guards-cells-board.md` (its board page) and any other front plugin or page note, and the gamemode deploy can be the same one that note runs, from a checkout at or after both merges.

## Run
From the shared clone, current with origin/main at or after 2d29a480:
    git fetch origin
    git checkout --detach origin/main
    .\scripts\deploy\Deploy-DevGamemode.ps1
    .\scripts\release\Ship.ps1 -Channel dev "Unshakeable, Tireless and Windwalker now work
    - Unshakeable: nothing staggers you while you block.
    - Tireless: a sprint and a power attack cost half the stamina they did.
    - Windwalker: a fall no longer hurts you, on top of the speed it already gave."
If this Ship is shared with other notes, add their lines under the same title or pick a title that covers all of them.

## Check afterwards
- Deploy: the script prints that the dev server runs the build this commit records, then the restart and the log tail.
- On a machine that joins dev with a character holding any of the three perks, `Data\Platform\thornswood-front.log` has a `perks:` line for each game setting it changed, for example `perks: fJumpFallHeightMult 0, from the game's 0.1` for Windwalker, and `fSprintStaminaDrainMult 3.5, from the game's 7; fStaminaAttackWeaponBase 10, from the game's 20; fStaminaAttackWeaponMult 0.5, from the game's 1` for Tireless. A line `unshakeable: could not hook animation events` means the hook failed; read it before anything else.
- Unshakeable is only seen in a fight: `unshakeable: refused a stagger while blocking (N so far)` when it worked, and `unshakeable: a stagger played with the block down (N so far)` when a stagger got through. The server logs `perks: Unshakeable fired for <actor>` when it holds back its own Break or Wreck stagger from a blocking holder.
- A character holding none of the three changes no setting and writes no `perks:` line.

## Risks and how to put it back
- Gamemode first: the server reads the block from the movement message for its own Break and Wreck, which works without the new front plugin. Ship first: the front plugin reads the perks list the server's K view already sends today, so it works on the old gamemode too.
- Tireless also halves a sprint and a power attack for any NPC whose AI runs on the holder's machine, because those settings have no NPC set. Written on #1385 for Patrick (decision 2).
- A gamemode restart drops anybody on dev; the script warns them first.
- To undo: `.\scripts\deploy\Deploy-DevGamemode.ps1 -PutBack` for the server, and a dev Ship from the commit before 2d29a480 for the front plugin.

## Release notes (draft)
Unshakeable, Tireless and Windwalker now work
- Unshakeable: nothing staggers you while you block.
- Tireless: a sprint and a power attack cost half the stamina they did.
- Windwalker: a fall no longer hurts you, on top of the speed it already gave.

## News post (draft)
none

## Test task (draft, for closing the three perks once they are on main)
Test task: Unshakeable, Tireless and Windwalker
1. Join main with a character, open K, and place points so you hold Unshakeable, Tireless and Windwalker.
2. Raise a shield or weapon to block, and have a second tester hit you with a power attack while you hold the block.
3. Lower your block and have them do it again.
4. Sprint a long way and watch your stamina bar. Then make a few power attacks and watch it again.
5. Jump off a high rock or wall, high enough that it would normally hurt.
6. Take the points back out of those perks and do steps 4 and 5 again.
What should happen: While blocking you are not staggered, and with the block down you are. A sprint and a power attack use about half the stamina they do without Tireless. The fall does no damage while you hold Windwalker, and hurts as usual once the points are out.
