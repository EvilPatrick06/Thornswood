# 1267 Is the dev game server's crash capture armed, and has it caught anything (VPS)

- **Lane:** Claude (overnight, codex-ops, taken over from Codex)
- **Issue / PR:** #1267; no pull request (nothing to change in code until a dump names the fault)
- **Channel:** VPS only. Steps 1 to 5 are reads; step 6 changes the box and runs only when the reads say nothing is armed
- **Staff status updates:** #staff-updates (1549254991082946570)
- **Needs first:** nothing

Why: #1267 closes on a dump of the dev server's access violation read against the matching symbols. Crash capture was armed twice by hand (ProcDump, 30 Sep and 1 Oct: monitor PIDs 5900 and 1960 on dev node PIDs 1360 and 1496). Those node processes are long gone after the deploys since, and ProcDump attached to a PID does not follow a restart. Since 11 Oct `C:\Thornswood-Dumps` exists for Windows Error Reporting LocalDumps (`scripts\vps\Lock-VpsFolders.ps1`), but nothing in the repository sets the LocalDumps key, so whether it is set is unknown. A session in the overnight batch is refused ssh.

## Run
From anywhere on One, each a read:

    ssh Administrator@192.135.112.23 "reg query \"HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\node.exe\""
    ssh Administrator@192.135.112.23 "powershell -NoProfile -Command Get-ChildItem C:\Thornswood-Dumps -Recurse -Force"
    ssh Administrator@192.135.112.23 "powershell -NoProfile -Command Get-ScheduledTask -TaskName *dump*; Get-Process procdump* -EA SilentlyContinue; Get-Service WerSvc"
    ssh Administrator@192.135.112.23 "powershell -NoProfile -Command Get-ScheduledTaskInfo -TaskName 'Thornswood Dev Server'"
    ssh Administrator@192.135.112.23 "powershell -NoProfile -Command Select-String -Path C:\Thornswood-Watch\watch.log -SimpleMatch -Pattern 'dev'"

## Check afterwards
1. **A dump is in `C:\Thornswood-Dumps` (or the ProcDump folder the task names).** Note its time against the watch.log restart, the dev task's `LastTaskResult` (3221225477 is the access violation) and which engine dev ran then (status page: 9035ea46 since 10:34 AM 12 Oct, 92848550 before). Read it with cdb against that build's `scam_native.pdb` (the build dev runs is in `C:\Thornswood-Repo\worktrees\claude-skymp-7feb5dc4\build\dist\server`; the 30 Sep note says matching symbols are also kept privately on the box): `cdb -z <dump> -y <folder with scam_native.pdb> -c "!analyze -v; .ecxr; kb; q"`. Put the faulting function and line on #1267. If the dump has to come to One to be read, it goes in `C:\Thornswood-Repo\temp\1267\` and is deleted when read.
2. **No dump, LocalDumps key present (DumpFolder C:\Thornswood-Dumps), WerSvc not Disabled:** capture is armed for every node.exe on the box. Comment that on #1267 with the dev restarts watch.log shows since 1 Oct; the issue waits for the next crash.
3. **No dump and no key:** nothing is armed. Step 6.

## 6. Arm it (box change, only after 3)
LocalDumps catches every node.exe crash on the box, dev and live server, voice and the site, with no process to keep attached:

    ssh Administrator@192.135.112.23 "reg add \"HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\node.exe\" /v DumpFolder /t REG_EXPAND_SZ /d C:\Thornswood-Dumps /f"
    ssh Administrator@192.135.112.23 "reg add \"HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\node.exe\" /v DumpType /t REG_DWORD /d 2 /f"
    ssh Administrator@192.135.112.23 "reg add \"HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\node.exe\" /v DumpCount /t REG_DWORD /d 3 /f"

Then the first read again, and write on #1267 exactly what was added and its readback. A full dump of a game server node is about the size of its working set (1.3 to 1.7 GB on the status page), so three are about 5 GB: check free space first (`Get-PSDrive C`).

## Risks and how to put it back
Reads change nothing. Step 6: `reg delete "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\node.exe" /f` takes it off. Never touch the running servers for this.

## Release notes (draft)
none

## News post (draft)
none

## Test task (draft, for closing the issue once the fix is on main)
none yet; the fix does not exist until a dump names the fault.
