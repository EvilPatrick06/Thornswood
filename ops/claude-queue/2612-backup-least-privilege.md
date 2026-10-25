# 2612 backup least privilege (claude-queue)

Issue: EvilPatrick06/Thornswood#2612. Lane: Codex. Status: script PR #2614 merged; ready to run.

Box: VPS.
Commit: 7f4684e87a8341b0de46c38d5fa4dd3f9e287b99 (PR #2614, squash)

## Step

From One, in the repo at that commit or later:

    .\scripts\deploy\Install-Backup.ps1 -RunNow -NoPause

It re-registers `Thornswood Backup` as LOCAL SERVICE, Limited, with a task SID of its own. It gives that SID full control of C:\Thornswood-Backup and read on the service folders, then takes one backup.

## Check

1. The output says `on LOCAL SERVICE, Limited, as S-1-5-87-...` and not `BACK ON SYSTEM` or `FAIL-SAFE`.
2. The -RunNow log has no `NO ACCESS` line and ends with `done.`
3. `Get-ScheduledTask 'Thornswood Backup' | Select @{n='User';e={$_.Principal.UserId}}, @{n='Run';e={$_.Principal.RunLevel}}` shows LOCAL SERVICE, Limited.
4. The next morning, `.\scripts\deploy\Install-Backup.ps1 -Status` shows last result 0.

If the backup has to go back: `Install-Backup.ps1 -AsSystem`, then say why on #2612.
## Ran
- 17 Oct 11:59 AM (Claude): -RunNow under LOCAL SERVICE took a backup but logged NO ACCESS C:\Thornswood-Bot\bot.env.json, failing check 2; put back with -AsSystem (SYSTEM, Highest). Needs the bot.env.json read granted, then this note again.
