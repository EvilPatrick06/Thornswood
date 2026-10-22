# Claude queue: collection revision 3 (USSEP), #1262

From: Wyrd (Vortex/collection lane). Card: #1262, In Progress.
Page: docs/COLLECTION-REVISION-3.md. Ownership fix: PR #2426, merged as b5acc603.

## Cannot run yet (Claude, 12 Oct, about 3:30 PM MT)

Steps 1 to 3 are Vortex's own window, which no Claude may drive (the main
session's word, 12 Oct). They are Patrick's, by the click path in
`wiki/lanes/claude-1262-ussep-clickpath.md`. This note waits for
`DONE #1262 rev <n>` on #1262, then steps 4 to 6 below run. Before the step 5
dev Ship, the dev release folder (`local\release-devbuild`) needs refreshing
from the new deployment: it is still the 3 Oct build (#2019).

## What to run

Every step on the page, 1 to 7, is yours under Patrick's rule of 11 October.
Run them from an up-to-date checkout of main that includes PR #2426
(git fetch, then check out origin/main). Commit: b5acc603 (PR #2426 squash) or later.

## Box

Patrick's PC One: Vortex with the Thornswood profile, the 7essxf collection,
and the Dev server folder for the deploy and the clean install check.

## Command

1. Steps 1 and 2 in Vortex: start from revision 2 (115 packages), add USSEP
   4.3.8a (Nexus 266, Old files, pinned, not latest), add the two rules on
   the page, leave Skip plugin rules off, Sort Now and Deploy.
2. Step 3: publish 7essxf revision 3 (116 packages).
3. Step 4: rebuild the server plugin list and the game data tables from the
   new deployment, with their tests, in one PR.
4. Step 5, Dev first:
   pwsh -NoProfile -File scripts\deploy\Deploy-DevGamemode.ps1 -LoadOrder -Dist <dist\server>
   then scripts\release\Ship.ps1 -Channel dev from Dev's own folder.
5. Step 6: scripts\mods\Check-CleanInstall.ps1 against Dev's own Data and
   plugin list, and compare Dev's manifest with the 49-position table.
   pwsh -NoProfile -File tests\test-collection-revision-3.ps1 must pass.
6. Step 7, Main: only when Patrick asks. Do not move Main from this note.

## Risks

- USSEP is a full plugin. Every full plugin after the base masters moves
  down one, so Dev needs a world reset. Patrick accepted that for the alpha.
- 4.3.9 and newer need SSE 1.7.99 and will not run on 1.6.1170. Pin 4.3.8a.
- Without -Dist, Deploy-DevGamemode keeps Dev's old order (#2309).
- The dist\server folder is the one Deploy-Gamemode.ps1 wrote for this build.

## Draft release notes (Dev)

Collection revision 3 adds the Unofficial Skyrim Special Edition Patch
4.3.8a. It fixes many vanilla bugs, including the Dawnguard moon dial
scripts. The load order moves by one, so the Dev world is reset.

## Draft news post

The Thornswood collection now includes the Unofficial Skyrim Special
Edition Patch. Update through the launcher before you play. Because the load
order changed, the Dev world has been reset.