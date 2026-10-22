# 2332 Voice sends one roster per turn of joins, so a restart lets everybody back in quickly

- **Lane:** Claude (overnight run, 12 Oct, voice-privacy)
- **Issue / PR:** #2332, #2381 (merged as a84c9b47)
- **Channel:** dev first, then live on Patrick's word
- **Staff status updates:** #staff-updates (1549254991082946570)
- **Needs first:** nothing. The game servers are not touched. Can go in the same sitting as 481-voice-most if that is still waiting: both are Install-Voice.ps1, and an install from a84c9b47 or later carries both.

## Run
From the shared clone `C:\Thornswood-Repo` at origin/main (a84c9b47 or later), or a worktree at that commit:

Dev voice:

    .\scripts\deploy\Install-Voice.ps1 -Root C:\Thornswood-Voice-Dev -Port 7789 -TaskName 'Thornswood Dev Voice' -NoPause

Live voice, only on Patrick's word:

    .\scripts\deploy\Install-Voice.ps1 -NoPause

It keeps the settings already on the box (bind, chat range, relay, the most people at once), stages, swaps and waits for `/health` to answer with the new build. Restarting voice drops everybody's voice and chat socket for a few seconds; both pages reconnect by themselves, which is exactly the storm this change makes cheap.

## Check afterwards

    curl.exe -s https://thornswood.net/voice-dev/health

(`/voice/health` for live) answers with a build ending `-most-1-roster-once-1`, `"skippedRosters":0` or close to it, `"closedBacklogged":0`, and the same `chatRange`, `bind` and `most` as before. Nothing changes on the wire: the pages get the same roster message, only fewer of them.

## Risks and how to put it back
If the new copy does not answer, Install-Voice.ps1 puts the old files and the old task back by itself. Afterwards, `-PutBack` with the same `-Root`, `-Port` and `-TaskName` puts the files it replaced back. The change is server side only; no launcher or game file depends on it, so putting it back needs nothing else.

## Release notes (draft)
none (nobody notices until a restart brings many people back at once; the service changes, not the launcher or the game)

## News post (draft)
none

## Test task (draft, for closing the issue once the fix is on main)
none: it needs a hundred people reconnecting at once; `voice/test-roster-once.js` and `voice/load-voice.js` hold it. The issue closes once live runs it and its health check reads the new build.
