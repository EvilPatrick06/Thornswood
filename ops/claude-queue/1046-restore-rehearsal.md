# 1046 restore rehearsal (monthly): start a restored server, connect, load a character

Issue: https://github.com/EvilPatrick06/Thornswood/issues/1046
Design: https://github.com/EvilPatrick06/Thornswood/issues/1046#issuecomment-6248455245
Lane: Anvil. PR: https://github.com/EvilPatrick06/Thornswood/pull/2702 (Restore-Server.ps1 -Rehearse, squash-merged to main).
Monthly: https://github.com/EvilPatrick06/Thornswood/pull/2714 (Check-RehearsalDue.ps1 and the nightly step). Ruling recorded: https://github.com/EvilPatrick06/Thornswood/issues/1046#issuecomment-6253067025

## A monthly recurring Claude step

Patrick ruled on 18 October 2026 (relayed by Smeagle, 11:30 AM MT) that this hands-on rehearsal runs monthly. It is not a one-off: do it once a month, every month, from step 1 below.

- First run: as soon as it can be done. By the current Last rehearsed line (28 September 2026), the nightly checks fail from the night of 3 November 2026 until it is done.
- Next due: one month after the first real run (the same day of the next month). Write that date here, in the line below, at the end of each run.
- Each later run is due one month after the run before it. scripts\vps\Check-RehearsalDue.ps1 says when the next one is due (`.\scripts\vps\Check-RehearsalDue.ps1` from a worktree of main). The nightly checks fail once Last rehearsed is more than 35 days old, so a late run shows on the board's "Nightly checks failed" issue.
- Only a real run (started, connected, a character loaded) moves the Last rehearsed line in docs\RESTORING.md. Never move it to quiet the check.

Next due: not set until the first real run (then: that date plus one month).

## Why this is in the queue

The tooling is on main. What is left is the hands-on run that meets the Done when, and lanes do not run that. It needs the backup key, a backup, the server payload and a launcher, all on Patrick's PC (One), with a person at the game. The issue is closed "Needs playtest."; this run is that playtest. docs\RESTORING.md "Not done yet: starting it and connecting" has the same steps.

## Where to do it

On One, not the VPS. The rehearsal turns the join pass hold off (the pass key lives in door.json, which -Rehearse deletes), so its ports must not be open to the internet. One is behind its router, and the launcher on the same machine connects to 127.0.0.1. Do it when nobody needs the launcher on One for anything else.

## Steps for Claude (with Patrick at the game for step 5)

1. From a fresh worktree of main, in Windows PowerShell or pwsh. Set the folders. Use the newest backup, from the repository's local\backups (Where.ps1 Backups), fetched with Fetch-Backups.ps1 if it is old. The key is the file named in docs\RESTORING.md; never print it.

```powershell
$W  = 'C:\Thornswood-Repo\temp\1046\work'
$R  = 'C:\Thornswood-Repo\temp\1046\server'
$key = "$env:USERPROFILE\Documents\thornswood-backup-key.txt"
$bk = (Get-ChildItem (Join-Path (& .\scripts\release\Where.ps1 Backups) 'thornswood-*.zip.enc') | Sort-Object Name -Descending | Select-Object -First 1).FullName
.\scripts\vps\Restore-Backup.ps1 -Backup $bk -KeyFile $key -CheckOnly -Work $W -NoPause
```

2. Put the server program in the folder. Install-ThornswoodServer.ps1 refuses a machine with SkyrimSE.exe in C:\Thornswood\Game, so unzip the payload, as on 28 September. The payload must match what the launcher plays (the main client): out\thornswood-server.zip from the last main build, or the one on the VPS at C:\thornswood-server.zip.

```powershell
Expand-Archive -LiteralPath <payload zip> -DestinationPath $R
```

3. Restore as a rehearsal, with a profile id Patrick knows is in the backup (his own character):

```powershell
.\scripts\vps\Restore-Server.ps1 -Backup $bk -Root $R -KeyFile $key -Expect <profile id> -Work $W -Rehearse -NoPause
```

   It must end RESTORE OK and REHEARSAL READY, with a game port from 7800 up and a voice port above it. Check that $R\private has no door.json and that $R\rehearsal.json names the ports.

4. Start it by hand and watch the log:

```powershell
cd $R; node dist_back/skymp5-server.js
```

   thornswood.log should come up with the restored name ending "(restore rehearsal)". It should say there is no door.json (expected), and nothing should reach thornswood.net.

5. Connect: copy C:\Thornswood\config.json aside first. Set its ServerAddress to "127.0.0.1" and its ServerPort to the game port REHEARSAL READY printed, start the launcher, press Play, and load the character from the backup. Check the character is where it was at the backup's time, with its inventory. Then quit the game and put the original config.json back. Check the launcher shows the live server again.

6. End it: stop node, then delete both folders:

```powershell
Remove-Item -LiteralPath $R, $W -Recurse -Force
```

7. Only now, after a real run that loaded a character, edit docs\RESTORING.md:
   - Change "Last rehearsed: 28 September 2026" to that day, saying started and connected to, on One, from which backup, and how long each step took.
   - Move the section's heading off "Not done yet" (first run only).
   - Open a PR with Refs #1046.
   If any step failed, do not touch the line. Write what happened on #1046 instead, and reopen it if the tooling is at fault.
8. Set "Next due" at the top of this note to one month after today's run, and keep this note in the queue for next month.

## Notes

- The real restore path is unchanged. -Rehearse refuses C:\Thornswood-Server and C:\Thornswood-Server-Dev before anything is put back.
- The backup still holds door.json. Nothing is moved anywhere, and the whole folder is deleted at step 6. The unpacked backup holds the bot token and the site keys. -Work is deleted by the script, and step 6 deletes it again.
- No numbers here are Patrick's choice. The ports are picked free and printed, and -Port and -VoicePort name others if wanted.
