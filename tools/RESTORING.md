# Getting the world back

What to do when the server is gone, or when somebody's character is.

**This has not been rehearsed yet.** Every step below is written from how the
pieces work, and that is not the same as having done it. Until somebody has run
the whole thing once on a throwaway box and written the date at the bottom, the
right assumption is that something here is wrong. Rehearsing it is the point of
the exercise, not paperwork about it.

## What exists

| | |
| --- | --- |
| `Thornswood Backup` | a task on the VPS, 03:15 nightly, `tools\vps-nightly-backup.ps1` |
| `C:\Thornswood-Backup` | where they land on the box, seven daily and four weekly |
| `tools\Fetch-Backups.ps1` | brings them here, run on Patrick's machine |
| `tools\Restore-Backup.ps1` | checks and unpacks one |
| the passphrase | `Documents\thornswood-backup-key.txt` here, `C:\Thornswood-Backup\key.txt` on the box |

A backup holds `game\world` (the characters), `game\private` (the door list and
who is allowed in), `game\data`, `server-settings.json`, `gamemode.js`, the
site's `data` folder, the bot's config, and the voice service's `owners.json`
and `choices.json`. It does **not** hold node_modules, the installer, or the
Skyrim data files. Those come back from the repo.

Before 18 September it held none of it. The world was never in the backup at
all.

## Losing the passphrase

The backups are AES-256 and signed. Without the passphrase they are noise, and
there is no way around that by design. It lives in two places on purpose. If
both are gone, so are the backups, and nothing in this file helps.

## One character came back wrong

The common case, and it does not need the server stopped for long.

1. Find which profile id. `tools\Characters.ps1` lists them, or the person's
   launcher shows it.
2. Get a backup from before it went wrong.
   ```powershell
   .\tools\Restore-Backup.ps1 -Backup "$env:USERPROFILE\Downloads\Thornswood-Backups\thornswood-<stamp>.zip.enc" -To C:\restore-check
   ```
3. The character is `C:\restore-check\game\world\<profileId in hex>.json`. Open
   it and confirm it is the right one before anything else.
4. Stop the game server, put that one file back, start it again. It has to be
   in that order: the server writes `world` while it runs, so a file copied in
   underneath a running server gets written straight back over. A restart is
   no good here for the same reason, because it never leaves the server down
   long enough to copy into.
   ```powershell
   ssh Administrator@192.135.112.23 "powershell -NoProfile -Command \"Stop-ScheduledTask -TaskName 'Thornswood Server'\""
   scp C:\restore-check\game\world\<id>.json Administrator@192.135.112.23:C:/Thornswood-Server/world/<id>.json
   ssh Administrator@192.135.112.23 "powershell -NoProfile -Command \"Start-ScheduledTask -TaskName 'Thornswood Server'\""
   ```
   Check nobody is on first. `tools\Restart-Server.ps1` refuses while people
   are online and is the polite way to find out.

Do not copy the whole `world` folder back for one character. Everybody else has
played since.

## The box is gone

Order matters here. The game server must not start before its world is in
place, or it writes fresh empty characters over the top.

1. **A new box, and the repo.** `tools\MOVING-THE-SERVER.md` is the long form
   of standing one up: Windows, node, the firewall rules, the scheduled tasks.
   Do all of that first and start nothing.
2. **Unpack the newest backup that opens.**
   ```powershell
   .\tools\Restore-Backup.ps1 -Backup <newest>.zip.enc -To C:\restore
   ```
   If the newest will not open, work backwards. That is what four weeklies are
   for.
3. **Check it before you trust it.** The unpack prints how many characters are
   in it. If it says `NOTHING. This backup has no characters in it.`, stop and
   use an older one. That is exactly the state the 15 September backups were in
   and the reason any of this exists.
4. **Put the pieces back**, with every Thornswood task stopped:
   - `C:\restore\game\world` → `C:\Thornswood-Server\world`
   - `C:\restore\game\private` → `C:\Thornswood-Server\private`
   - `C:\restore\game\data` → `C:\Thornswood-Server\data`
   - `C:\restore\game\server-settings.json` → the server root
   - `C:\restore\site\data` → `C:\Thornswood-Docs\data`
   - `C:\restore\bot\config.json`, `C:\restore\site\config.json` → their roots
   - `C:\restore\voice\owners.json` → `C:\Thornswood-Voice\owners.json`
5. **The rest comes from a release, not from the backup.** Run `Ship.ps1` from
   Patrick's machine so the server, the gamemode and the site are the versions
   that go with each other. `gamemode.js` is in the backup to be read, not to
   be the thing you run.
6. **Secrets that are not in there.** The server password, the Discord bot
   token, the client secret and the site keys are in the config files above, so
   they do come back. What does not is anything that was only ever in a config
   on the old box and not in one of those. Check `NOTES.txt` in the backup for
   what was running.
7. **Start the game server first, alone**, and watch `thornswood.log` until a
   character connects properly. Then the rest.
8. **Tell people.** Anything they did after the backup was taken is gone, and
   they should hear that from us rather than notice it.

## Rehearsing it

Worth an hour, and it is the only thing that turns this file from a guess into
a runbook.

1. Stand up a throwaway box, or a second folder on the VPS the way
   `tools\vps-dev-instance.ps1` does.
2. Run the whole of "the box is gone" against it, from a real backup.
3. Connect to it with a launcher pointed at that port and load a character.
4. Fix whatever in this file turned out to be wrong.
5. Write the date here.

**Last rehearsed: never.**
