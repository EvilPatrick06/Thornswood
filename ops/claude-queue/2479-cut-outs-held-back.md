# 2479 The cut rows are held back from chests and the floor

- **Lane:** Wyrd
- **Issue / PR:** #2479, #2549 (NOT merged yet: held for the 1.2.4 freeze, it touches game\gamemode.js)
- **Channel:** dev
- **Staff status updates:** #staff-updates (1549254991082946570)
- **Needs first:** #2549 merged after Claude posts 1.2.4 is out. Do not run before that.

## Run
From the shared clone at the merge commit of #2549:
    .\scripts\deploy\Deploy-DevGamemode.ps1 -Note "Dragon Bone and the Riekling spear tomes are held back from chests and the floor (#2479)"

## Check afterwards
- On dev, a world-placed Dragon Bone (3ada4:Skyrim.esm) on the floor is refused with the "put here by the world" line, and a chest that held one opens without it.
- The same goes for the Riekling spear tomes (bff20 / bff21:Playable Rieklings.esp), where a chest or the floor carries them.
- One a person drops can still be picked up.
- Server log: no new spoils errors after the restart.

## Risks and how to put it back
- Only these three base ids change. Everything else isSpoil decides is untouched.
- Revert #2549 and run Deploy-DevGamemode again.

## Release notes (draft)
Dragon Bone and the Riekling spear spell tomes no longer turn up in chests or on the ground. They were cut, and now the world holds them back like weapons and armour.

## News post (draft)
none

## Test task (draft)
On dev, open a chest or find a spot that used to hold Dragon Bone (or a Riekling spear tome) and check it is not there. Drop one of your own and check it can be picked back up.
## Ran (Claude)
- 19 Oct 2026, 4:40 to 5:05 PM: on dev in release 20261019-165915-dev from b8c757bd (Publish-Server dev with engine 9d3139ca, Deploy-DevGamemode, Install-Voice dev, dev Ship, SHIP EXIT 0). Main waits on Patrick's main release. On the issue.
