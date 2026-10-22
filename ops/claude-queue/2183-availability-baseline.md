# 2183 availability baseline (Codex, 17 Oct)

PR #2637 (Refs #2183), squash commit 956c9ad9 on main, adds scripts\vps\Read-Availability.ps1. It reads the watchdog's alerts.jsonl, pairs each service's down and back lines over a window, and prints down minutes and availability. It only reads. docs\SERVICE-OBJECTIVES.md now says the baseline period is the four weeks that start the first time the reader is run on the box's alerts.jsonl, and that no baseline has been recorded until then.

## Live steps for Claude

1. On One, from the repository folder (not a worktree, so Where.ps1 Backups is the real local\backups), on main at 956c9ad9 or later: .\scripts\vps\Watch-Outside.ps1 -Install. The running task uses the installed copy at %LOCALAPPDATA%\Thornswood\Watch-Outside\Watch-Outside.ps1, which on 17 Oct still had no Check-OffBox. This also finishes step 1 of 2183-offbox-check.md. Expect the first hourly run to say whether the newest copy in local\backups is over 26 hours old; if it is, run .\scripts\vps\Fetch-Backups.ps1 as that note says.
2. Start the baseline: run the reader on the box's C:\Thornswood-Watch\alerts.jsonl. Either copy it down first and read the copy on One:
       scp Administrator@192.135.112.23:C:/Thornswood-Watch/alerts.jsonl $env:TEMP\alerts.jsonl
       .\scripts\vps\Read-Availability.ps1 -Path $env:TEMP\alerts.jsonl -NoPause
       Remove-Item $env:TEMP\alerts.jsonl
   or copy the script to the box and run it there with no -Path. The date and time of this first run is the start of the baseline.
3. Write that start date into the "Baseline period" section of docs\SERVICE-OBJECTIVES.md in a small PR, with the date four weeks later as its end. At that end date, run the reader again with -From the start and -To the end; that output is the baseline. Do not change any threshold or say any service meets its target from the first run.

No Ship, no deploy, no VPS change beyond reading alerts.jsonl.

## Ran

- 22 Oct 2026, 10:07 AM (Cloud Desk): step 2, on a copy of alerts.jsonl fetched with scp, deleted after. 107 lines, the oldest from 21 Oct 11:05 AM; down so far: the backup once (111.9 minutes), the dev game twice (24.3), runner 2 twice (20.0), the website once (9.4). Step 3 is in the Desk's 22 Oct batch pull request: the baseline period is 22 Oct to 19 Nov 2026. Left: step 1 on One, and on 19 Nov the reader with `-From 2026-10-22 -To 2026-11-19`, whose output goes on #2183 and into SERVICE-OBJECTIVES.md as the baseline.
