# 2183 off-box backup check (Codex, 15 Oct)

PR #2533 (Refs #2183) adds Check-OffBox to scripts\vps\Watch-Outside.ps1: staff are told when the newest backup on One in local\backups is over 26 hours old.

## Live steps for Claude or Patrick, after #2533 merges

1. On One, from the repository folder (not a worktree, so Where.ps1 Backups is the real local\backups): .\scripts\vps\Watch-Outside.ps1 -Install. The running task uses the installed copy, so the new check does nothing until this.
2. Expect its first run to say the off-box copy is out of date: on 15 Oct the newest copy on One was thornswood-20261013-031501, and the Thornswood Fetch Backups task last ran 4:15 AM 13 Oct.
3. Run .\scripts\vps\Fetch-Backups.ps1 on One (or check why its 04:15 task did not run on 14 and 15 Oct). The next hourly check then says it is up to date again.

No Ship, no deploy, no VPS change.