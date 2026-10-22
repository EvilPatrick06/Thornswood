# 2578 least-privilege services (claude-queue)

Issue: EvilPatrick06/Thornswood#2578. Lane: Codex. Status: script PR #2608 merged; ready to run.

Box: VPS (prod and dev on the same box).
Commit: 69b44d2cea2de8fc69d4f33c89c34b4dee6b034f (PR #2608, squash)

## What changes
Thornswood Dev Server, Thornswood Dev Voice, Thornswood Server, Thornswood Voice and Thornswood Web (Caddy) move from SYSTEM, Highest to NT AUTHORITY\LOCAL SERVICE, Limited. They get ACLs as listed in the issue comment: Read and Execute on the roots, Modify only on the data, log and temp folders, and no access to secrets, backups or runner folders.

## Commands (from the merged commit)
Re-run the installers with their usual arguments; they now register the new principal and set the ACLs:
1. scripts\vps\vps-dev-instance.ps1 (dev server and dev voice)
2. Connect to Dev, check the logs write, and check that voice connects. Soak for at least 1 hour.
3. scripts\deploy\Install-ThornswoodServer.ps1 and scripts\deploy\Install-Voice.ps1 (live)
4. scripts\deploy\Setup-Domain.ps1 (Caddy last; confirm that cert renewal state is writable)
5. Get-ScheduledTask 'Thornswood*' | Select TaskName, @{n='User';e={$_.Principal.UserId}}, @{n='Run';e={$_.Principal.RunLevel}}

## Risks
- A folder the server writes to that the plan missed: the server fails to start or errors at runtime. Check the task's Last Run Result and the logs right after each step.
- Caddy cannot write its ACME data, so renewal fails silently later. Check the Caddy log for a storage error.
- Rollback: the installers save the old task XML; re-register it with Register-ScheduledTask -Xml.

## Ran
- 17 Oct 11:58 AM (Claude): dev voice moved to LOCAL SERVICE (PASS). Dev server refused: EPERM on C:\Thornswood-Server-Dev\server-settings-merged.json under LOCAL SERVICE; the installer rolled back, dev runs as before. Needs the root folder write granted (on #2578), then the dev step again. Live waits.
