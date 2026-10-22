# 2166 Retention and deletion, checked on the box (read only)

- **Lane:** Herald (Website), 17 Oct
- **Issue / PR:** #2166 (matrix comment from Herald, 17 Oct, against main b97808de). Related: #2349, #2350, #2351, #2352, #2353, #2164
- **Channel:** live and dev, **read only**. Nothing here changes a file, a task or a service
- **Needs first:** nothing merged. Run from the shared clone on main, in PowerShell 7, through `.\scripts\vps\Remote.ps1`
- **Data rule:** print only counts, dates, file names and setting values. Never print a row, a line of chat, a name, a Discord id or an address. Anything written back to GitHub uses the same rule

## Run (read only, each prints counts or dates only)

1. **The live site is running the hourly sweep.** Confirm the deployed `server.js` has the retention timer:

       .\scripts\vps\Remote.ps1 'Select-String -Path C:\Thornswood-Docs\server.js -Pattern "RETENTION_EVERY_MS = 60 \* 60 \* 1000","GALLERY_HOLD_DAYS = 30","SESSIONS_DAYS = 365" | Measure-Object | % Count'

   This should print 3. Also count retention failures in the site's log: `Select-String -Path C:\Thornswood-Docs\site.log* -Pattern "-retention " | Measure-Object | % Count`, which should be 0 (or list only file names and codes).

2. **Nothing past its window on the site (#2350, #2352, G3).** Use node on the box with the site's own shapes, printing counts only:

       .\scripts\vps\Remote.ps1 'node -e "const fs=require(\"fs\"),d=\"C:/Thornswood-Docs/data/\",n=Date.now(),D=86400000;const j=f=>{try{return JSON.parse(fs.readFileSync(f,\"utf8\"))}catch(e){return null}};const s=j(d+\"sessions.json\")||[];const old=s.filter(r=>r&&!r.keep&&Math.max(+r.end||0,+r.start||0)>0&&Math.max(+r.end||0,+r.start||0)<n-365*D).length;const si=(j(d+\"signins.json\")||[]).filter(r=>r&&+r.at>0&&+r.at<n-30*D).length;const t=(j(d+\"for-bot/trouble.json\")||[]).filter(r=>r&&+r.at>0&&+r.at<n-365*D).length;const m=j(\"C:/Thornswood-Docs/uploads/uploads.json\")||{};const over=Object.values(m).filter(x=>x&&x.removed&&!(+x.heldUntil>n)).length;let sl=0;try{for(const f of fs.readdirSync(d+\"session-logs\")){const st=fs.statSync(d+\"session-logs/\"+f);if(st.mtimeMs<n-365*D)sl++}}catch(e){};console.log(JSON.stringify({sessionRows:s.length,sessionRowsPast365:old,signinsPast30:si,troublePast365:t,troubleRows:(j(d+\"for-bot/trouble.json\")||[]).length,removedUploadsPastHold:over,sessionLogFilesPast365ByMtime:sl}))"'

   Expected: `sessionRowsPast365` 0, `signinsPast30` 0 (or a few, only if nobody has signed in or opened the sign-in list since a row turned 30 days old; that is how the page says it works), `removedUploadsPastHold` 0, `sessionLogFilesPast365ByMtime` 0. `troublePast365` may not be 0 yet (G3, not fixed); write the number on #2166.

3. **Voice chat window (G2).** The value only, for both voice services:

       .\scripts\vps\Remote.ps1 '[Environment]::GetEnvironmentVariable("THORNSWOOD_CHAT_DAYS","Machine"); [Environment]::GetEnvironmentVariable("THORNSWOOD_CHAT_DAYS","User"); Get-ScheduledTask | ? TaskName -match "Voice" | % { $_.TaskName + " : " + (($_.Actions | % Arguments) -match "CHAT_DAYS") }'
       .\scripts\vps\Remote.ps1 '"live oldest " + (Get-ChildItem C:\Thornswood-Voice\chat\*.jsonl | Sort Name | Select -First 1 | % Name); "dev oldest " + (Get-ChildItem C:\Thornswood-Voice-Dev\chat\*.jsonl | Sort Name | Select -First 1 | % Name)'

   Then open `/voice/health` and note `chatRetention.overdueDays` and `pruneError`. Expected: no variable set, or 365; oldest day under 365 days old; overdueDays 0.

4. **Backups (rows 10-12).** Names and dates only:

       .\scripts\vps\Remote.ps1 'Get-ScheduledTaskInfo -TaskName "Thornswood Backup" | Select LastRunTime,LastTaskResult,NextRunTime | Format-List | Out-String; Get-ChildItem C:\Thornswood-Backup\thornswood-*.zip.enc | Sort Name | % { $_.Name + "  " + $_.LastWriteTime.DayOfWeek }; Select-String -Path C:\Thornswood-Backup\backup.log -Pattern "NOT DROPPED" | Measure-Object | % Count'

   Expected: at most 7 non-Sunday and 4 Sunday files, and 0 NOT DROPPED. On One: `Get-ScheduledTaskInfo -TaskName "Thornswood Fetch Backups"` (last result 0), and every file in `local\backups` is newer than 30 days except the newest 7.

5. **server.log**: don't repeat it here. It is the "Check afterwards" step of `2349-server-log-30-days.md`.

## Restore test against completed deletions (synthetic only)

Do this inside #2164's restore rehearsal, on its scratch target, **never on live and never on the live data folders**:

1. On the rehearsal target only, after `Restore-Backup.ps1` unpacks and before any service starts, add one synthetic request to the rehearsal copy of `deletions\requests.jsonl` for the made-up id `100000000000000001`, with profile id `999999901`. Also seed stand-in records for that id in the rehearsal copy only: one row each in `linked.json`, `sessions.json` and `rules-accepted.json`, one fake change form, and one chat line in a dated day file. All values are made up.
2. Run the reapply step exactly as `Restore-Box.ps1:225-236` does (`Delete-Person.ps1 -Reapply -Delete -Merge <copy>`), pointed at the rehearsal roots.
3. Check: 0 records remain for `100000000000000001` in every store `Delete-Person.ps1` lists; every other record's byte count is unchanged; the edited chat day's before and after line counts are in the record; and `deletions reapplied` result is 0.
4. Throw the rehearsal target away. Write only the pass or fail and the counts on #2166 and #2164.

If #2164's rehearsal can't run yet, the same checks are already covered with stand-ins by `tests\test-2351-delete-person.ps1` (69/69 on #2583). Run it on One under Windows PowerShell 5.1 and note the count on #2166 instead.

## Deploy: #2631 (G2, G3, G4), merged as 1538071c8d6dc7792126598c4936b692af363d4c

Claude deploys this. Herald does not run Deploy-Docs or any install. Use the shared clone on main at or after `1538071c`, in PowerShell 7.

1. **Site** (G3 trouble.json ages by 365 days, G4 no tw cookie on Discord sign-in): `.\scripts\deploy\Deploy-Docs.ps1` with the usual switches. No data, page or board switch is needed: only `server.js` changed.
2. **Live voice** (G2 chat prune every hour): `.\scripts\deploy\Install-Voice.ps1` with the same switches as the last live install, so the chat range and the relay stay as they are.
3. **Dev voice**: `.\scripts\deploy\Install-Voice.ps1 -Root C:\Thornswood-Voice-Dev -Port 7789 -TaskName 'Thornswood Dev Voice'`.
4. **Check, counts only** (the `Select-String` lines run on the box through `.\scripts\vps\Remote.ps1 -File` with a script file, because the cookie line has single quotes in it):
   - Step 2 above should now show `troublePast365` 0.
   - `Select-String -Path C:\Thornswood-Docs\server.js -SimpleMatch -Pattern "COOKIE + '=; Path=/; Max-Age=0" | Measure-Object | % Count` should print 2 (sign-out and the Discord callback; 1 before this deploy).
   - `Select-String -Path C:\Thornswood-Voice\voice-server.js,C:\Thornswood-Voice-Dev\voice-server.js -Pattern "chatPruneTimer = setTimeout\(chatPrune, 3600000\)" | Measure-Object | % Count` should print 2 (one in each file).
   - On `/voice/health`, `chatRetention.overdueDays` should be 0.
   - In a private window, sign in with Discord: the response sets `twa` and clears `tw` (`Max-Age=0`). Check this on the browser's cookie list, not by pasting a value anywhere.
5. **Put back:** Deploy-Docs and Install-Voice each keep the previous files (`-PutBack` for voice). Nothing here changes data.

## Deploy: #2658 (G1, G5), merged as 2fb7bb9fe6973f193eff6ab6068a8e0675bb99b6

Claude deploys this, after the #2631 steps above (or with them: the site and voice installs below carry both). Herald does not run Deploy-Docs or any install. Use the shared clone on main at or after `2fb7bb9f`, in PowerShell 7.

1. **Site** (G1 kept sessions keep their chat, G5 site.log by age, privacy page line): `.\scripts\deploy\Deploy-Docs.ps1 -Site` with the usual switches. `-Site` is needed because `site/data/site/privacy.md` changed (Last changed 17 October 2026). The new `page-versions.json` rows go with the app, so signed-in people are asked to accept the privacy page again. That is expected.
2. **Live voice, before dev** (G5 voice.log): `.\scripts\deploy\Install-Voice.ps1` with the same switches as the last live install, so the chat range and the relay stay as they are. It now sends `server-log.js` in place of `roll-log.ps1` and registers the task as `server-log.js --log voice.log --days 90 --stamp voice-server.js`.
3. **Dev voice**: `.\scripts\deploy\Install-Voice.ps1 -Root C:\Thornswood-Voice-Dev -Port 7789 -TaskName 'Thornswood Dev Voice'`.
4. **Bot** (G5 bot.log by age, `BotService.cs`): a full `.\scripts\deploy\Install-Bot.ps1 -NoToken`. `-CodeOnly` does not rebuild the service, so it won't do. Check the #2158 bot.env.json read-access prerequisite first. About a minute with no bot.
5. **Game server** (G5 thornswood.log, `Install-ThornswoodServer.ps1` task line `--also thornswood.log`): no separate install. It goes in with the next normal `Publish-Server.ps1`, dev then live, after the 1.2.4 freeze. Until then thornswood.log keeps rolling by size only.
6. **Delete-Person**: nothing to deploy. It runs from the clone through `Remote.ps1 -File`, so main at or after `2fb7bb9f` is enough.
7. **Check, counts only** (on the box through `.\scripts\vps\Remote.ps1`):
   - `Select-String -Path C:\Thornswood-Docs\data\site\privacy.md -SimpleMatch -Pattern "Nothing in" | Measure-Object | % Count`. The page should hold the line "Nothing in them is kept past 90 days".
   - `(Get-ScheduledTask -TaskName 'Thornswood Voice','Thornswood Dev Voice').Actions.Arguments -match '--days 90 --stamp' | Measure-Object | % Count` should print 2. `Test-Path C:\Thornswood-Voice\server-log.js, C:\Thornswood-Voice-Dev\server-log.js` should print True twice.
   - The newest voice.log in each voice root: the first line should start with `[2026-` (stamped). Print the first 21 characters only, no content.
   - `/voice/health` answers on live and dev, and `chatRetention.overdueDays` is 0.
   - `Get-Service ThornswoodBot | % Status` should be Running. Check that `C:\Thornswood-Bot\data\bot.log` is being written (its LastWriteTime moves).
   - The next day: no `voice.log.*`, `bot.log.*` or `site.log.*` file has a LastWriteTime older than 90 days. Names and dates only.
   - After the next Publish-Server: the game server task arguments contain `--also thornswood.log`.
8. **Put back:** `Deploy-Docs.ps1 -PutBack` and `Install-Voice.ps1 -PutBack` (it leaves the task as is, so then run `Install-Voice.ps1 -TaskOnly` from a checkout of `2fb7bb9f~1` with the same switches, which registers the old `roll-log.ps1` task line again, and check `/voice/health`), and `Install-Bot.ps1 -PutBack`. Nothing here changes data, except that rolled logs past 90 days are deleted, and that is the point of the change.

## Check afterwards
Write steps 1-4 and the restore result on #2166 as one comment, counts and dates only. Anything past its window goes on the issue that owns it (#2350 sessions or logs, #2352 uploads, #2349 server.log, #2166 for G2 and G3).

## Risks and how to put it back
None: every step reads. The restore test runs only on #2164's disposable target. If a command would write, stop.

## Release notes (draft)
None.

## News post (draft)
None. Nothing in the policy changes.

## Test task (draft)
None. G1 and G5 decided by Patrick on 17 Oct and merged in #2658. #2166 is closed "Needs playtest."; these deploy steps and checks are what is left.

## Ran
- 18 Oct about 11:45 AM (Claude): the 90-day log check, read only: 0 voice.log.*, bot.log.* or site.log.* older than 90 days, but the oldest rolled log is 32 days old, so it cannot show a deletion until bot.log.20260916-1535.old turns 90 on 15 Dec 2026; check it is gone then. `--also thornswood.log` is still 0 on both game server tasks. test-2351-delete-person.ps1 under Windows PowerShell 5.1 69/0 in place of #2164's rehearsal. On #2166. Left: the 15 Dec check, `--also thornswood.log` with the next Publish-Server (dev first), the restore rehearsal inside #2164.
- 17 Oct 8:40 PM and 18 Oct 10:41 AM (Claude): site from 0a43c273 then 4782b2f5 (with #2707 and #2708). Live and dev voice 10:03 AM 18 Oct, bot full install 10:05 AM, all from 62f82e57. Every check in steps 1 to 4 and #2658 step 7 passed, written on #2166; sign-ins were 41 past 30 days until #2708, now 0. Left: the next-day 90-day log check (19 Oct), the restore rehearsal inside #2164, and `--also thornswood.log` with the next Publish-Server.
