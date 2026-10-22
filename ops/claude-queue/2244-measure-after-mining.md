# 2244 Dev Ship carrying the corrected after-mining measurement, then a person mines on dev

- **Lane:** Claude (taken over from Herald, 12 Oct)
- **Issue / PR:** #2244, #2444 (merged as 673af7c8)
- **Channel:** dev
- **Staff status updates:** #staff-updates (1549254991082946570)
- **Needs first:** nothing; #2444 is on main.

What changed since Herald wrote this note: the dev Ship it asked for has happened. Dev release 20261012-143758-dev (from 2d29a480) carries #2396's measurement; its record's `thornswood-front.js` is main's file at that commit byte for byte. While writing the test steps Claude found the measurement took any actor's equip as the character's (an NPC drawing a weapon would have used up the one "after the next equip" line) and logged only the first spell's events. #2444 fixes both. It is logging only.

## Run
On the next dev Ship you were going to do anyway, from a clean checkout of origin/main that includes #2444 (One, the shared clone or a fresh worktree):

    .\scripts\release\Ship.ps1 -Channel dev "<the notes of whatever else goes out>"

No line in the notes for this: nobody notices it. No gamemode deploy: the change is in `game\plugins\thornswood-front.js` only.

## Check afterwards
- The dev feed's release names a commit that contains #2444.
- Then a person mines on dev, by the steps on #2244 (Claude's comment of 12 Oct). Nobody can today. If they mined on One, read `C:\Thornswood-DevBuild\Game\Data\Platform\thornswood-front.log` before the game is started again (the plugin empties it at each start) and copy every line with `mining` in it onto #2244.

## Risks and how to put it back
Logging only: no equip, no animation event, no message to the server. A client Ship, so dev clients update on their next launch. A later dev Ship replaces it.

## Release notes (draft)
None. Developer measurement only.

## News post (draft)
None.

## Test task (draft, for closing the issue once the fix is on main)
None yet. The fix comes after the measurement, in its own pull request, with its own note and Test task.
