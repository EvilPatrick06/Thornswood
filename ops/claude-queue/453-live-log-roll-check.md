# 453 Read that the live server, voice and bot roll their logs (VPS read only)

- **Lane:** Claude (overnight, codex-ops, taken over from Codex)
- **Issue / PR:** #453, repo half merged long ago (#332, #834); nothing new to merge
- **Channel:** VPS only, reads; nothing changes on the box
- **Staff status updates:** #staff-updates (1549254991082946570)
- **Needs first:** nothing

Everything else in #453 is done and checked: dev passed its done-when on 27 Sep (dummy voice.log rolled to .1, service kept writing), the gamemode's own log rolls in process and reports itself at `/thornswood-log.json` (read over HTTP at 3:00 PM 12 Oct: `{"ok":true}` on 3000 and on 7788), `Get-Logs.ps1` brings the rolled `.1` files down, the bot's service rolls bot.log by size (#465), and `docs\MOVING-THE-SERVER.md` says watch.log keeps its last 1,000 lines. The one open question is whether the **live** game server's task has the roll in front of node, because `Deploy-Server.ps1` (what put live on 92848550 and 9035ea46) never re-registers the task; only `Install-ThornswoodServer.ps1` (run by `Publish-Server.ps1`) does. A session in the overnight batch is refused ssh, so this is for the main session.

## Run
From anywhere on One (each line is a read):

    ssh Administrator@192.135.112.23 "powershell -NoProfile -Command (Get-ScheduledTask -TaskName 'Thornswood Server').Actions.Arguments"
    ssh Administrator@192.135.112.23 "powershell -NoProfile -Command (Get-FileHash C:\Thornswood-Server\roll-log.ps1).Hash"
    ssh Administrator@192.135.112.23 "powershell -NoProfile -Command Get-ChildItem C:\Thornswood-Server\server.log*,C:\Thornswood-Voice\voice.log*,C:\Thornswood-Bot\bot.log*"
    ssh Administrator@192.135.112.23 "powershell -NoProfile -Command (Get-ScheduledTask -TaskName 'Thornswood Voice').Actions.Arguments"

## Check afterwards
- The server task's arguments name `roll-log.ps1 -Path "C:\Thornswood-Server\server.log"` before `node ... >> server.log`.
- The hash is `8F27C741CA7CC7BF366E03BD4EF2915B429F9FCA7E1A0E42A73DB771D722A9D2`, which is `scripts\vps\Roll-Log.ps1` on main (sha256 of the file as checked out on One). A different hash with the roll in the task line is still a working roller from an older send; say which.
- `server.log` is being written (LastWriteTime now) and at least one `server.log.1` exists after the last restart; the same for voice; bot.log has its rolled copies.
- If all hold: comment on #453 with the four answers and **close it** (no release, no test task).
- If the live server task has no roll: the fix is a live run, `.\scripts\release\Publish-Server.ps1 -Channel main` (it re-registers the task with the roll), which restarts the live game server, so it waits on Patrick's word. Write that on #453 and leave it open.

## Risks and how to put it back
None: reads only.

## Release notes (draft)
none

## News post (draft)
none

## Test task (draft, for closing the issue once the fix is on main)
none
