# 2351 the game server lets go of a deleted character's registers

- **Lane:** Claude (background agent, 17 Oct)
- **Issue / PR:** #2351, #2651 (merged as e944971b). Follow-up for the merchant ledger: #2652 (the #1373 lane).
- **Channel:** dev first, then live on Patrick's word (the live site and Install-Backup do not change: no box script is installed and no public page changed)
- **Staff status updates:** #staff-updates (1549254991082946570)
- **Needs first:** #2651 merged. For the check: Patrick names a Discord account whose characters may be deleted for the test (an alt used only for testing), with at least one character on dev that holds something the release lets go of (a house or a farm claim, a post on a board, a place in a book), made in the game by whoever plays it. Nothing else: gamemode only, no client, no content plugin.

## Run
From the shared clone `C:\Thornswood-Repo` at origin/main with #2651 in it (`git fetch origin; git checkout --detach origin/main`), in PowerShell 7.

1. Dev gamemode:

       .\scripts\deploy\Deploy-DevGamemode.ps1 -Note "Deleted accounts let go of what their characters held
       - When someone asks for their account to be deleted, the house, farm, office and bed nights their characters held are free again the next time the server starts, and their posts come off the boards."

2. The check on dev, when nobody is on either game server (the real run refuses otherwise), with the test account's Discord id (17 to 20 digits) in place of `<test id>`. The dry run first; it changes nothing:

       .\scripts\vps\Remote.ps1 -File .\scripts\vps\Delete-Person.ps1 -Arguments '-DiscordId <test id>'

   It must end `DRY RUN: nothing was changed`, show `release` lines for the dev game server's registers (for example `release  1  dev game server: places in private\property.json naming their character`) and `release  1  dev game server: private\deleted-characters.json, the list the game server lets go of at its next start`. Then the real run (this deletes the test account's link, sessions, chat and characters on the box, and writes one line to `C:\Thornswood-Deletions\requests.jsonl`):

       .\scripts\vps\Remote.ps1 -File .\scripts\vps\Delete-Person.ps1 -Arguments '-DiscordId <test id> -Delete -By Claude'

   It must end `DELETED, and written down in C:\Thornswood-Deletions\requests.jsonl` and then `The game's registers are let go as each of these starts: dev game server`.

3. Live, **on Patrick's word only**, after the dev check reads back clean:

       .\scripts\deploy\Deploy-Server.ps1 -GamemodeOnly

   If it refuses because live runs another server build than the commit records, the live pair is `.\scripts\deploy\Deploy-Gamemode.ps1` then `.\scripts\deploy\Deploy-Server.ps1` (Developer-Guide "Deploy the live pieces the pull request touched").

## Check afterwards
After step 2, read the dev gamemode's own log:

    .\scripts\vps\Remote.ps1 'Select-String -Path C:\Thornswood-Server-Dev\thornswood.log -Pattern "release:" | Select-Object -Last 8 | ForEach-Object { $_.Line }'

It must show `release: a list of N profile(s) and M character(s) to let go, at server start`, one line for each of `farms`, `property`, `embassy`, `dungeon`, `books` with counts, and `release: every part is done, and the list is gone`. No line may hold a name, a profile id or a form id. Then:

    .\scripts\vps\Remote.ps1 'Test-Path C:\Thornswood-Server-Dev\private\deleted-characters.json'

must print `False`. A part that says it waits names why; read that line and fix the cause before anything else. If the run also wrote a list on live (the test account had something there), live keeps it until the live gamemode carries this change and lets go of it at that start; the same two reads with `C:\Thornswood-Server` show it then. Write the lines (counts only) on #2351, and in `ops/status.md`.

## Risks and how to put it back
- A real deletion run on a server stops it and starts it again (it did before too, wherever a character was removed); it refuses while anybody is on unless `-Now`.
- A faction or business book the test account owns is disbanded. Pick an account that owns none, or have staff hand it on first.
- If a register cannot be written, its part waits for the next start, said in the log; nothing is half released.
- Put back on dev: `.\scripts\deploy\Deploy-DevGamemode.ps1 -PutBack`. A list left behind by an older gamemode is not read and does nothing. On live, deploy the gamemode of the commit before the merge.

## Release notes (draft)
Deleted accounts let go of what their characters held
- When someone asks for their account to be deleted, the house, farm, office and bed nights their characters held are free again the next time the server starts, and their posts come off the boards.

## News post (draft)
None: nothing anybody does changes, and it only happens on a deletion request.

## Test task (draft, for closing the issue once the fix is on main)
None: testers cannot ask for a deletion as a test. The issue closes with the dev check's lines written on it, once the record has also been through a restore rehearsal (#2351 says so).

## Ran
- 18 Oct 1:20 PM (Claude): step 1, Deploy-DevGamemode from main 5484e842 (with #2654 and #2715), SWAP OK; dev release 20261018-132349-dev followed. Left: step 2 waits on Patrick naming a test-only Discord account with a character on dev that holds something; step 3 (live) on his word.
