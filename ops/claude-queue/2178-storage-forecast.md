# 2178 Storage forecast: put the daily disk sample on the VPS and test its alert

- **Lane:** Claude (taken over from Anvil / Installer, 12 Oct 2026, at Patrick's request)
- **Issue / PR:** #2178 (carries #2174). #2291 (7cd414ca, the forecast) and #2463 (merged as 1abf28f3: -Install, -Status, -Remove, -Alerts, -TestAlert).
- **Channel:** VPS only
- **Staff status updates:** #staff-updates (1549254991082946570)
- **Needs first:** nothing. #2463 is on main (1abf28f3). This replaces the old hand-made schtasks line, which pointed at a C:\Thornswood\scripts folder and pwsh, neither of which is on the box.

**Steps 1 to 4 done 12 Oct about 8:18 PM (on #2178). Only step 5 is left, on or after 26 Oct.**

## Run
From the shared clone `C:\Thornswood-Repo`, detached at a current origin/main that contains 1abf28f3 (`git merge-base --is-ancestor 1abf28f3 HEAD` exits 0):

1. Install (writes `C:\Thornswood-Watch\forecast-storage.ps1` on the box and registers a SYSTEM task):

       .\scripts\vps\Forecast-Storage.ps1 -Install -NoPause

   Should print, in green: `wrote     C:\Thornswood-Watch\forecast-storage.ps1  <n> bytes`, `made      the task, daily at 04:00`, `sampled   1 line(s) in C:\Thornswood-Watch\disk-history.jsonl` and the sample itself (`{"t":"...","drive":"C","total":...,"free":...}`), then `task      Thornswood Disk History is registered`. Exit 0. Any FAILED line, or a STOP, exits 1 with nothing else changed: read the lines and run it again.

2. Read it back:

       .\scripts\vps\Forecast-Storage.ps1 -Status -NoPause

   `task      Ready, last ran <now>, result 0`, then `verdict   not-enough-data` with `samples   1 in the last 30 days (need 14 over 7 days)`, and `exit      0`.

3. Test the alert without touching any data. This writes one test line into the watchdog's outbox and nothing else (no sample, no level):

       ssh Administrator@play.thornswood.net "powershell -NoProfile -ExecutionPolicy Bypass -File C:\Thornswood-Watch\forecast-storage.ps1 -TestAlert -Alerts C:\Thornswood-Watch\alerts.jsonl"

   Prints `told      <id> into C:\Thornswood-Watch\alerts.jsonl`, the id ending `-diskforecast-test`. Within about three minutes the staff channel shows "**Test of the disk forecast alert.** Nothing is wrong with the disk. ..." Confirm the bot (or the webhook) delivered it:

       ssh Administrator@play.thornswood.net "findstr diskforecast-test C:\Thornswood-Watch\alerts-sent-bot.txt C:\Thornswood-Watch\alerts-sent-webhook.txt"

   One of the two files names the id. Neither after five minutes: the delivery path is broken. That is its own issue (the watchdog outbox, #447), and it is not fixed here.

4. Write on #2178 what steps 1 to 3 printed, with the time.

5. On or after 26 Oct (14 daily samples), run step 2 again. Post the verdict and the days to 20% and 10% on #2178, then close #2178 (and #2174 with it). The forecast refuses to project before then, by design.

## Check afterwards
- After the next 04:00 run: `-Status` shows `samples   2`.
- After #2165's next `Check-ProdParity.ps1 -Collect`: the task row `Thornswood Disk History` reads ok (#2463 put it in the record).

## Risks and how to put it back
- Low. It reads free space and appends one short line a day (about 100 bytes). It deletes nothing and touches no service. Its alert is one line in the outbox the bot already reads, and only when the forecast turns.
- Take it off: `.\scripts\vps\Forecast-Storage.ps1 -Remove -NoPause` (prints `the task is gone`; the history stays). To remove the script file too: `ssh Administrator@play.thornswood.net "del C:\Thornswood-Watch\forecast-storage.ps1"`.
- 04:00 is the box's own clock; the backup runs at 03:15 on the same clock, so every sample is taken at the same point after it.

## Release notes (draft)
None. Nothing reaches anyone in the game.

## News post (draft)
None.

## Test task (draft)
None. Nothing in the game changes.

## History
- 12 Oct, Anvil: the first version of this note (a hand-made schtasks line).
- 12 Oct, Claude (anvil-ops): rewritten for Forecast-Storage.ps1 -Install, -Status and -TestAlert from #2463.
