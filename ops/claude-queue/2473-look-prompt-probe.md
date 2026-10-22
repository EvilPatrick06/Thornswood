# 2473 Write down the game's own prompt on a person (dev Ship, then one session)

- **Lane:** Claude (overnight, slug heads)
- **Issue / PR:** #2473, #2480 (merged as 1d8e96be9d6fc491b2a4f60e645075cf10331438)
- **Channel:** dev
- **Staff status updates:** #staff-updates (1549254991082946570)
- **Needs first:** nothing. It is a log line only and can ride the same dev Ship as 2474-party-names-voice-marks.md (one Ship carries both; run the Ship once, with both notes' lines in its note).

## Run
From the shared clone `C:\Thornswood-Repo`, at origin/main containing 1d8e96be9d6fc491b2a4f60e645075cf10331438, if no other dev Ship carries it:
    .\scripts\release\Ship.ps1 -Channel dev "A note for the team when you look at somebody
    - Looking at another person writes what the game itself offers on them into the session log, so the extra Talk prompt over people can be traced."

## Check afterwards
The measurement this exists for: one dev session with two people. Each looks at the other once in first person and once in third person (F to switch), then sends `Data\Platform\thornswood-front.log`. The lines that start `looking at` say the camera, the text in the game's own HUD line, whether Better Third Person Selection's menu is up, and whether the activation is blocked. Write what they say on #2473; the decision there waits on it.

## Risks and how to put it back
Reads only, once per new person looked at. Revert #2480 and dev Ship again to take it out.

## Release notes (draft)
A note for the team when you look at somebody
- Looking at another person writes what the game itself offers on them into the session log, so the extra Talk prompt over people can be traced.

## News post (draft)
none

## Test task (draft, for closing the issue once the fix is on main)
none yet: the issue's fix is not written. The test task goes with the fix.
