# Getting the world back

What to do when the server is gone, or when somebody's character is.

**Rehearsed once, 28 September 2026**, on Patrick's machine and on the VPS,
into throwaway folders, from the newest real backup. "Rehearsing it" at the
bottom is exactly what was typed and how long each step took. It found three
things wrong, all fixed the same night (issue #401): deleted characters were
counted as people, `-Expect` looked for the wrong file, and a live restore on
the box came back with the dev server's port and name. What it did not do is
start the restored server and connect to it; see the end of that section.

## What exists

| | |
| --- | --- |
| `Thornswood Backup` | a task on the VPS, 03:15 nightly, `scripts\vps\vps-nightly-backup.ps1` |
| `C:\Thornswood-Backup` | where they land on the box, seven daily and four weekly |
| `scripts\vps\Fetch-Backups.ps1` | brings them here, run on Patrick's machine; `-Schedule` makes that a daily task at 04:15 |
| `Thornswood Fetch Backups` | that task, on Patrick's machine (One), keeping 30 days and never fewer than seven, logging to `fetch.log` beside them |
| `scripts\vps\Restore-Backup.ps1` | checks and unpacks one; `-CheckOnly` fails a backup with no characters in it |
| `scripts\vps\Restore-Server.ps1` | puts one back into a server folder and checks the load order resolves and the characters are there |
| `tests\test-backup-restore.ps1` | backs up a scratch server, restores it into another, and checks it, every night in the build checks |
| the passphrase | `Documents\thornswood-backup-key.txt` here, `C:\Thornswood-Backup\key.txt` on the box |

The copy off the box is pulled to Patrick's machine over ssh. It is never
served over HTTPS, from the site or anywhere else.

A backup holds `game\world` (the characters), `game\private` (the whole
folder: the character cards in `characters.json`, the door's `door.json`,
`allowed.json` and `door.log`, `online-names.json`, and on live
`farm-claims.json`, on dev `property.json`; `mod-settings.json` and
`take-limit.json` when the server has written them), `game\data`, `server-settings.json`,
`gamemode.js`, the same five from the dev server under `game-dev` (since issue
#401), the site's `data` folder, the bot's config and its join record
(`joins.json`, which arrival each person was), the voice service's
`choices.json`, and the Caddyfile. `NOTES.txt` in it counts the characters in
each world and names any private file that was missing. The voice service's
`owners.json` and `secret.txt` stopped being taken on 23 September, when the
character register they belonged to was retired. It does **not** hold
node_modules, the installer, the dev voice service, or the Skyrim data files.
Those come back from the repo. The published launcher feed is not in it
either; it is kept separately.

Before 18 September it held none of it. The world was never in the backup at
all.

## Losing the passphrase

The backups are AES-256 and signed. Without the passphrase they are noise, and
there is no way around that by design. It lives in two places on purpose. If
both are gone, so are the backups, and nothing in this file helps.

## One character came back wrong

The common case, and it does not need the server stopped for long.

1. Find which profile id. `.\scripts\ops\Chargen-Log.ps1` prints a
   `chargen <actor> profile <id>` line for each character, or the person's
   launcher shows it.
2. Get a backup from before it went wrong.
   ```powershell
   .\scripts\vps\Restore-Backup.ps1 -Backup "$env:USERPROFILE\Downloads\Thornswood-Backups\thornswood-<stamp>.zip.enc" -To C:\restore-check
   ```
3. Find the character's file. Characters are not named by profile id: each is
   a slot, `game\world\changeForms\0.json`, `1.json` and so on, with the
   profile id inside (`"profileId"`). A deleted character leaves its slot
   behind with `"profileId": -1` and `"isDeleted": true`. This prints which
   slot holds a profile id (put the id in place of 1234567):
   ```powershell
   Get-ChildItem C:\restore-check\game\world\changeForms -Filter *.json | Where-Object { $_.BaseName -match '^\d+$' } | Where-Object { (Get-Content $_.FullName -Raw | ConvertFrom-Json).profileId -eq 1234567 } | Select-Object Name
   ```
   Confirm the live server's file with the same slot number holds the same
   profile id before copying anything: a slot belongs to one character for as
   long as it lives, but a character deleted and made again gets a new one.
4. Stop the game server, put that one file back, start it again. It has to be
   in that order: the server writes `world` while it runs, so a file copied in
   underneath a running server gets written straight back over. A restart is
   no good here for the same reason, because it never leaves the server down
   long enough to copy into.
   ```powershell
   ssh Administrator@192.135.112.23 "powershell -NoProfile -Command \"Stop-ScheduledTask -TaskName 'Thornswood Server'\""
   scp C:\restore-check\game\world\changeForms\<slot>.json Administrator@192.135.112.23:C:/Thornswood-Server/world/changeForms/<slot>.json
   ssh Administrator@192.135.112.23 "powershell -NoProfile -Command \"Start-ScheduledTask -TaskName 'Thornswood Server'\""
   ```
   Check nobody is on first. `scripts\vps\Restart-Server.ps1` refuses while people
   are online and is the polite way to find out.

Do not copy the whole `world` folder back for one character. Everybody else has
played since.

## The box is gone

Order matters here. The game server must not start before its world is in
place, or it writes fresh empty characters over the top.

1. **A new box, and the repo.** `docs\MOVING-THE-SERVER.md` is the long form
   of standing one up: Windows, node, the firewall rules, the scheduled tasks.
   Do all of that first and start nothing.
2. **Unpack the newest backup that opens.**
   ```powershell
   .\scripts\vps\Restore-Backup.ps1 -Backup <newest>.zip.enc -To C:\restore
   ```
   If the newest will not open, work backwards. That is what four weeklies are
   for.
3. **Check it before you trust it.** The unpack prints how many characters are
   in it. If it says `NOTHING. This backup has no characters in it.`, stop and
   use an older one. That is exactly the state the 15 September backups were in
   and the reason any of this exists.
4. **Put the pieces back**, with every Thornswood task stopped. The game
   server's half is one command, once the server program is in its folder
   (`Deploy-Server.ps1`, or `Install-ThornswoodServer.ps1 -Zip <payload>
   -Root C:\Thornswood-Server -NoTask`):
   ```powershell
   .\scripts\vps\Restore-Server.ps1 -Backup <newest>.zip.enc -Root C:\Thornswood-Server
   .\scripts\vps\Restore-Server.ps1 -Backup <newest>.zip.enc -Root C:\Thornswood-Server-Dev -Which dev
   ```
   It puts `world` and `private` back whole, fills in `data`, refuses if the
   server is running, and ends with `RESTORE OK` only when every plugin in the
   load order is on disk and the characters are there. It also takes the
   server's port, name and voice port from the backup: `C:\thornswood-server.zip`
   is whichever channel was published last, so a live restore on top of a dev
   payload would otherwise come back on the dev port under the dev name. Read
   the `from the backup, was` lines it prints. By hand it is:
   - `C:\restore\game\world` -> `C:\Thornswood-Server\world`
   - `C:\restore\game\private` -> `C:\Thornswood-Server\private`
   - `C:\restore\game\data` -> `C:\Thornswood-Server\data`
   - `C:\restore\game\server-settings.json` -> the server root
   - `C:\restore\game-dev\...` -> `C:\Thornswood-Server-Dev\...` the same way
   - `C:\restore\site\data` -> `C:\Thornswood-Docs\data`
   - `C:\restore\bot\bot.env.json`, `C:\restore\site\config.json` -> their roots
   - `C:\restore\bot\joins.json` -> `C:\Thornswood-Bot\joins.json`, before the
     bot starts, or the join cards start counting again
   - `C:\restore\voice\choices.json` -> `C:\Thornswood-Voice\choices.json`
   - `C:\restore\web\Caddyfile` -> `C:\Thornswood-Caddy\Caddyfile`
5. **The rest comes from the repository, not from the backup.** `Ship.ps1`
   publishes the launcher and the packs and deploys none of these, so each
   goes back with its own command, from main on Patrick's machine, in this
   order: `.\scripts\deploy\Deploy-Server.ps1` (the recorded server build),
   `.\scripts\deploy\Deploy-Gamemode.ps1`, `.\scripts\deploy\Deploy-Docs.ps1` (never
   `-SeedDocs`, which would flatten the restored documents),
   `.\scripts\deploy\Install-Bot.ps1 -CodeOnly` and `.\scripts\deploy\Install-Voice.ps1`.
   `gamemode.js` is in the backup to be read, not to be the thing you run.
   The dev server's world and private folder are in the backup since issue
   #401 (step 4); the dev voice folder is not, and
   `.\scripts\deploy\Deploy-DevGamemode.ps1` puts the dev gamemode back.
6. **Secrets that are not in there.** The Discord bot token, the client secret and the site keys are in the config files above, so
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

`tests\test-backup-restore.ps1` does the scripted half every night on
scratch folders: backs up a stand-in live and dev server, deletes the
original, restores into another folder, and checks the character and the load
order. What it cannot do is use the real world, so a real rehearsal is done
by hand, below. The restored folder holds everybody's characters and the
unpacked backup holds the bot token and the site keys: delete both at the end,
every time, and never put either on a shared drive.

### What was typed on 28 September, and how long it took

The backup was `thornswood-20260928-204001.zip.enc` (28.6 MB, 1,421 entries),
the newest one `Fetch-Backups.ps1` had brought to Patrick's machine. Nobody
was online (`https://thornswood.net/api/public` said `online: 0`).

**On Patrick's machine**, from a worktree, into
`C:\ThornswoodTemps&Worktrees\temp\401\restore`. `Install-ThornswoodServer.ps1`
refuses to run on a machine with `SkyrimSE.exe` in `C:\Thornswood\Game`, so the
server program went in by unzipping the payload instead. `TEMP` is pointed at
the task's temp folder so the decrypted copy never lands in `%TEMP%`.

```powershell
$env:TEMP = 'C:\ThornswoodTemps&Worktrees\temp\401\work'
$key = "$env:USERPROFILE\Documents\thornswood-backup-key.txt"
$bk  = (Get-ChildItem "$env:USERPROFILE\Downloads\Thornswood-Backups\thornswood-*.zip.enc" | Sort-Object Name -Descending | Select-Object -First 1).FullName
$R   = 'C:\ThornswoodTemps&Worktrees\temp\401\restore'
.\scripts\vps\Restore-Backup.ps1 -Backup $bk -KeyFile $key -CheckOnly -NoPause
.\scripts\vps\Restore-Backup.ps1 -Backup $bk -KeyFile $key -To "$R\unpacked" -NoPause
$payload = 'C:\Users\evilp\Downloads\Thornswood-Repo\out\thornswood-server.zip'
Expand-Archive -LiteralPath $payload -DestinationPath "$R\server-live"
.\scripts\vps\Restore-Server.ps1 -Backup $bk -Root "$R\server-live" -KeyFile $key -Expect <a profile id> -NoPause
Expand-Archive -LiteralPath $payload -DestinationPath "$R\server-dev"
.\scripts\vps\Restore-Server.ps1 -Backup $bk -Root "$R\server-dev" -Which dev -KeyFile $key -Expect <a profile id> -NoPause
Remove-Item -LiteralPath $R -Recurse -Force
```

| Step | Took |
| --- | --- |
| `-CheckOnly`: signature, then what is in it | 0.8 s |
| unpack the whole backup | 3.6 s |
| server program into a folder (284 MB payload) | 2 to 3 s each |
| `Restore-Server.ps1`, live | 14 to 25 s |
| `Restore-Server.ps1`, dev | 11 to 13 s |

**On the VPS**, into `C:\Thornswood-RestoreTest`, from the backup already in
`C:\Thornswood-Backup` and the payload already at `C:\thornswood-server.zip`,
under Windows PowerShell 5.1. The three scripts were copied up first, because
the box has no repo:

```powershell
scp .\scripts\deploy\Install-ThornswoodServer.ps1 Administrator@192.135.112.23:C:/Thornswood-RestoreTest/scripts/deploy/
scp .\scripts\vps\Restore-Server.ps1 .\scripts\vps\Restore-Backup.ps1 .\scripts\vps\Roll-Log.ps1 Administrator@192.135.112.23:C:/Thornswood-RestoreTest/scripts/vps/
```

and then, on the box:

```powershell
C:\Thornswood-RestoreTest\scripts\deploy\Install-ThornswoodServer.ps1 -Zip C:\thornswood-server.zip -Root C:\Thornswood-RestoreTest\server -NoTask
C:\Thornswood-RestoreTest\scripts\vps\Restore-Server.ps1 -Backup C:\Thornswood-Backup\<newest>.zip.enc -Root C:\Thornswood-RestoreTest\server -KeyFile C:\Thornswood-Backup\key.txt -Expect <a profile id> -NoPause
Remove-Item -LiteralPath C:\Thornswood-RestoreTest -Recurse -Force
```

| Step | Took |
| --- | --- |
| copy the scripts up | 3.4 s |
| `Install-ThornswoodServer.ps1 -NoTask` | 2.4 s |
| `Restore-Server.ps1`, live | 2.7 to 3.3 s |
| delete the folder | 0.1 s |

The whole thing, typing included, is well under the hour this section used to
guess. `Install-ThornswoodServer`'s own load order check resolves against the
live server's plugins, because the payload's settings name
`C:/Thornswood-Server`; Restore-Server points them at the test folder first,
so its check is the one that means something.

### What it showed

- Live: 11 characters (18 slot files, 7 of them deleted characters), all 48
  plugins on disk. Dev: 11 characters (27 slot files, 16 deleted), all 48.
  Every one of the 22 has a card in `characters.json` and a line in the site's
  `roster.json`.
- The restored load order is the one each server serves, name for name and in
  order: live's against
  `http://192.135.112.23:3000/api/servers/thornswood/manifest.json`, dev's
  against the same path on port 7788.
- All 1,287 JSON files restored (both worlds, private and data folders, the
  site's data, the bot's and the voice service's files) parse, both
  `gamemode.js` copies pass `node --check`, and the site's `gallery.json`
  holds the 8 pictures `https://thornswood.net/api/public` shows.
- Staff bans, notes and PKs (`bans.json`, `notes.json`, `pk.json` in the
  site's data) were not in this backup because they did not exist yet: they
  arrived that night at 21:28, after it was taken. The backup takes the
  site's whole `data` folder, so every backup from 29 September on has them.
  Check they are there on the next rehearsal.

### Not done yet: starting it and connecting

A restored folder has not been started and connected to. Before anybody does:

1. Give it free ports in its `server-settings.json` (`port`, and
   `thornswoodVoicePort`): Restore-Server has just set them to the live ones.
2. Move `private\door.json` out of the folder. It names the live site and
   holds the key the site trusts, so a test server started with it pushes its
   roster to the live site and asks the live site who is allowed in.
3. Start it by hand (`node dist_back/skymp5-server.js` in that folder), watch
   `thornswood.log`, connect with a launcher pointed at that port and load a
   character.
4. Delete the folder.

**Last rehearsed: 28 September 2026** (unpack and restore, on Patrick's machine
and on the VPS; not started or connected to).
