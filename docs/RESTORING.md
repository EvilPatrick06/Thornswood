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
| `scripts\vps\Fetch-Backups.ps1` | brings them here, run on Patrick's machine, into `local\backups` in the repository folder (`C:\Users\evilp\Downloads\Thornswood-Repo\local\backups` on One, since 5 October); `-Schedule` makes that a daily task at 04:15 |
| `Thornswood Fetch Backups` | that task, on Patrick's machine (One), keeping 30 days and never fewer than seven, logging to `fetch.log` beside them |
| `scripts\vps\Restore-Backup.ps1` | checks and unpacks one; `-CheckOnly` fails a backup with no characters in it |
| `scripts\vps\Restore-Server.ps1` | puts one back into a server folder and checks the load order resolves and the characters are there |
| `scripts\vps\Restore-Box.ps1` | run on Patrick's machine: carries one to a new box and puts all of it back there, both worlds with Restore-Server.ps1 and the rest with `vps-restore-services.ps1`, then deletes its copy (issue #454) |
| `scripts\vps\Delete-Person.ps1` | carries out a deletion request and writes it in `C:\Thornswood-Deletions\requests.jsonl`; `-Reapply` removes everybody in that record again after a restore (issue #2351, `docs\WEBSITE-OPERATIONS.md` "Deletion requests") |
| `scripts\vps\vps-freeze.ps1` | run on the old box through Remote.ps1 on the day of a move: stops everything and takes the last backup |
| `tests\test-backup-restore.ps1` | backs up a scratch server, restores it into another, and checks it, every night in the build checks |
| `tests\test-backup-streaming.ps1` | verifies large uploads, old archive compatibility, tampering, stream failures and publication collisions with disposable data |
| the passphrase | `Documents\thornswood-backup-key.txt` here, `C:\Thornswood-Backup\key.txt` on the box |

The copy off the box is pulled to Patrick's machine over ssh. It is never
served over HTTPS, from the site or anywhere else.

A backup holds `game\world` (the characters), `game\private` (the whole
folder: the character cards in `characters.json`, the door's `door.json`,
`allowed.json` and `door.log`, `online-names.json`, and on live
`farm-claims.json`, on dev `property.json`; `mod-settings.json` and
`take-limit.json` when the server has written them), `game\data`, `server-settings.json`,
`gamemode.js`, the same five from the dev server under `game-dev` (since issue
#401), the site's `data` folder and `config.json`, since issue #454 the
site's `uploads` (the gallery's pictures) and each feed's store
(`version.json`, `published.json`, `launchers.txt`, `releases.txt` and
`history`, for `feed` and `feed-dev`), the bot's config and its join record
(`joins.json`, which arrival each person was), the record of completed
deletion requests (`deletions\requests.jsonl`, since issue #2351), and the
Caddyfile. `NOTES.txt`
in it counts the characters in each world and names any private file that was
missing. The voice service's `owners.json` and `secret.txt` stopped being
taken on 23 September, when the character register they belonged to was
retired. It does **not** hold
node_modules, the installer, the dev voice service, the feed's downloads
(`feed\assets`, the size of every release; `Remirror-Site-Feed.ps1` sends them
again from the machine that shipped), or the Skyrim data files. Those come
back from the repo and from Patrick's machine.

Every website upload is included, including recordings above the general
per-file cap. `MaxUploadsMB` now warns when the total grows; it does not
discard files. An unreadable or changing upload fails the run rather than
publishing an archive that silently omits it. Check free disk space as the
gallery grows: staging, the clear zip and encrypted output still need space.
Encryption and decryption use bounded buffers rather than loading the whole
archive into memory. The authenticated `TSBK1` format is unchanged, so existing
encrypted archives still open. A missing or empty key prevents an encrypted
backup from being created. Only an explicit `-Plain` creates an unencrypted
archive, for a local rehearsal.

Temporary backup data is restricted to the account running the backup,
SYSTEM and Administrators. Failure cleanup closes every stream even if
another stream's cleanup fails. Publication refuses to overwrite a backup
with the same timestamp. Neither a failed run nor retention considers an
unrelated file for deletion.

Before anything restored goes back into service, the people who asked to be
deleted are removed again (issue #2351): a backup still holds everybody who
asked after it was taken. `Restore-Box.ps1` does it as its last step. After
any other restore (Restore-Server.ps1 on its own, a folder copied back by
hand), with the services it wrote under still stopped, on the box:
```powershell
.\scripts\vps\Remote.ps1 -File .\scripts\vps\Delete-Person.ps1 -Arguments '-Reapply'
.\scripts\vps\Remote.ps1 -File .\scripts\vps\Delete-Person.ps1 -Arguments '-Reapply -Delete'
```
The first is a dry run that counts what goes; the second removes it, and
refuses while a service it would write under is running. When the backup
being put back carries a record the box's own does not, add
`-Merge <its deletions\requests.jsonl>` to both. "Deletion requests" in
`docs\WEBSITE-OPERATIONS.md` is the whole procedure. Restrict the rehearsal
destination to the operators: an unpacked archive contains credentials and
private records. A restore rehearsal must use a disposable destination, never
the live service folder.

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
2. Get a backup from before it went wrong. The fetched ones are in
   `local\backups` in the repository folder; this runs from that folder:
   ```powershell
   .\scripts\vps\Restore-Backup.ps1 -Backup ".\local\backups\thornswood-<stamp>.zip.enc" -To C:\restore-check
   ```
3. Find the character's file. Characters are not named by profile id: each is
   a slot, `game\world\changeForms\0.json`, `1.json` and so on, with the
   profile id inside (`"profileId"`). A deleted character leaves its slot
   behind with `"profileId": -1` and `"isDeleted": true`. This prints which
   slot holds a profile id (put the id in place of 1234567):
   ```powershell
   Get-ChildItem C:\restore-check\game\world\changeForms -Filter *.json | Where-Object { $_.BaseName -match '^\d+$' } | Where-Object { (Get-Content $_.FullName -Raw | ConvertFrom-Json).profileId -eq 1234567 } | Select-Object Name
   ```
   Never put back a character whose profile id is in the record of deletion
   requests, `C:\Thornswood-Deletions\requests.jsonl`: that person asked for
   it to be gone (issue #2351).
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
`docs\MOVING-THE-SERVER.md` "If it is a new machine, new address" is the whole
sequence, checked against the scripts on 29 September (issue #454); with the
old box gone it is the same list without its steps 10 to 12. It has not
been followed on a real box yet; "Rehearsing the move on a throwaway server"
in the same file is how to try it for an afternoon without touching the real
one. During the alpha all world and character data is throwaway, so a
rehearsal, or a real move, that loses it is acceptable. In short:

1. **A new box**, steps 1 to 8 there: the box, its ssh server, Set-Vps, the
   key, Bootstrap-VPS, the live server program installed and not started,
   voice, and the dev instance. Start nothing else.
2. **The newest backup that opens**, from `local\backups` in the repository
   folder on Patrick's machine, where Fetch-Backups.ps1 brings them every day:
   ```powershell
   .\scripts\vps\Restore-Box.ps1 -Backup <newest>.zip.enc -Check
   ```
   It opens it there with the passphrase and prints how many characters are in
   it. If it says `NOTHING. This backup has no characters in it.`, stop and
   use an older one, and if the newest will not open, work backwards. That is
   what four weeklies are for, and exactly the state the 15 September backups
   were in. It also asks the new box whether it is ready, and sends nothing.
3. **Put it back**, with nothing that writes into it running:
   ```powershell
   .\scripts\vps\Restore-Box.ps1 -Backup <newest>.zip.enc
   ```
   On the new box it runs Restore-Server.ps1 for each game server: `world` and
   `private` back whole, `data` filled in, a refusal if the server is running,
   and `RESTORE OK` only when every plugin in the load order is on disk and the
   characters are there. It takes each server's port, name and voice port from
   the backup, because `C:\thornswood-server.zip` is whichever channel was
   published last and a live restore on a dev payload would otherwise come
   back on the dev port under the dev name: read the `from the backup, was`
   lines it prints. The join pass switch and the written role lists
   (`thornswoodRequirePass`, `thornswoodDevs`, `thornswoodPlaytesters`) come
   from the backup too, since no build carries them (issue #1845); those
   lines name each one and never its value. Then `vps-restore-services.ps1` puts the rest back,
   `Delete-Person.ps1 -Reapply -Delete` removes again everybody in the record
   of deletion requests, the backup's merged into the box's, and the copy on
   the box is deleted. By hand, from an unpacked backup, it is:
   - `game\world` -> `C:\Thornswood-Server\world`
   - `game\private` -> `C:\Thornswood-Server\private`
   - `game\data` -> `C:\Thornswood-Server\data`
   - `game\server-settings.json` -> the server root
   - `game-dev\...` -> `C:\Thornswood-Server-Dev\...` the same way
   - `site\data`, `site\config.json` and `site\uploads` -> `C:\Thornswood-Docs`
   - `site\feed\...` and `site\feed-dev\...` -> `C:\Thornswood-Docs\feed` and
     `feed-dev`, file by file, beside the downloads already there
   - `bot\bot.env.json` -> `C:\Thornswood-Bot`, readable by SYSTEM and
     Administrators only
   - `bot\joins.json` -> `C:\Thornswood-Bot\data\joins.json`, before the bot
     starts, or the join cards start counting again
   - `web\Caddyfile` -> `C:\Thornswood-Caddy\Caddyfile`
   - `deletions\requests.jsonl` is not copied: with everything above in place
     and nothing started, `Delete-Person.ps1 -Reapply -Delete -Merge
     <unpacked>\deletions\requests.jsonl` adds its lines to the box's record
     and removes those people again
4. **The rest comes from the repository and Patrick's machine, not from the
   backup**, steps 14 to 25 there: `.\scripts\deploy\Deploy-Docs.ps1` (never
   `-SeedDocs`, which would flatten the restored documents),
   `.\scripts\deploy\Install-Bot.ps1 -NoToken` (the whole install: `-CodeOnly`
   on a new box has no Python libraries and no task to restart), the feed's
   downloads with `.\scripts\deploy\Remirror-Site-Feed.ps1`, the installer with
   `.\scripts\release\Publish-Installer.ps1`, the name and Caddy with
   `.\scripts\deploy\Setup-Domain.ps1`, then the watchers. `gamemode.js` is in
   the backup to be read, not to be the thing you run; Restore-Box says when
   the one installed differs from it. A backup from before 29 September has
   no uploads and no feed store: the gallery's pictures are then gone, and
   each feed goes back from Patrick's working copy by handing
   `Remirror-Site-Feed.ps1 -FeedDir` a new folder holding only a copy of the
   `version.json` in `%LOCALAPPDATA%\Thornswood\feed\main` (or `dev`, with
   `-Dev`), which it sends as a feed it never received.
5. **Secrets that are not in there.** The Discord bot token, the client
   secret and the site keys are in the config files above, so they do come
   back. The watchdog's webhook does not: `Watch-Services.ps1 -SetWebhook`
   asks for it. Nor does anything that was only ever in a config on the old
   box and not in one of those; check `NOTES.txt` in the backup for what was
   running.
6. **Start the game server first, alone**, and watch `thornswood.log` until a
   character connects properly. Then the rest.
7. **Tell people.** Anything they did after the backup was taken is gone, and
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
server program went in by unzipping the payload instead. On that day `TEMP`
was pointed at the task's temp folder by hand, because both scripts decrypted
into `%TEMP%`. They take `-Work` now, and the commands below pass it. Left
out, `-Work` is still `%TEMP%`. The decrypted zip and the unpacked backup are
deleted before either script exits, including when it refuses. The backups
were in `Downloads\Thornswood-Backups` that day; since 5 October they are in
`local\backups` in the repository folder, and the line below says so.

```powershell
$W   = 'C:\ThornswoodTemps&Worktrees\temp\401\work'
$key = "$env:USERPROFILE\Documents\thornswood-backup-key.txt"
$bk  = (Get-ChildItem 'C:\Users\evilp\Downloads\Thornswood-Repo\local\backups\thornswood-*.zip.enc' | Sort-Object Name -Descending | Select-Object -First 1).FullName
$R   = 'C:\ThornswoodTemps&Worktrees\temp\401\restore'
.\scripts\vps\Restore-Backup.ps1 -Backup $bk -KeyFile $key -CheckOnly -Work $W -NoPause
.\scripts\vps\Restore-Backup.ps1 -Backup $bk -KeyFile $key -To "$R\unpacked" -Work $W -NoPause
$payload = 'C:\Users\evilp\Downloads\Thornswood-Repo\out\thornswood-server.zip'
Expand-Archive -LiteralPath $payload -DestinationPath "$R\server-live"
.\scripts\vps\Restore-Server.ps1 -Backup $bk -Root "$R\server-live" -KeyFile $key -Expect <a profile id> -Work $W -NoPause
Expand-Archive -LiteralPath $payload -DestinationPath "$R\server-dev"
.\scripts\vps\Restore-Server.ps1 -Backup $bk -Root "$R\server-dev" -Which dev -KeyFile $key -Expect <a profile id> -Work $W -NoPause
Remove-Item -LiteralPath $R, $W -Recurse -Force
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
scp .\scripts\deploy\Install-ThornswoodServer.ps1 .\scripts\deploy\ServerSettings.ps1 Administrator@192.135.112.23:C:/Thornswood-RestoreTest/scripts/deploy/
scp .\scripts\vps\Restore-Server.ps1 .\scripts\vps\Restore-Backup.ps1 .\scripts\vps\Server-Log.js Administrator@192.135.112.23:C:/Thornswood-RestoreTest/scripts/vps/
```

and then, on the box:

```powershell
C:\Thornswood-RestoreTest\scripts\deploy\Install-ThornswoodServer.ps1 -Zip C:\thornswood-server.zip -Root C:\Thornswood-RestoreTest\server -NoTask
C:\Thornswood-RestoreTest\scripts\vps\Restore-Server.ps1 -Backup C:\Thornswood-Backup\<newest>.zip.enc -Root C:\Thornswood-RestoreTest\server -KeyFile C:\Thornswood-Backup\key.txt -Expect <a profile id> -Work C:\Thornswood-RestoreTest\work -NoPause
Remove-Item -LiteralPath C:\Thornswood-RestoreTest -Recurse -Force
```

| Step | Took |
| --- | --- |
| copy the scripts up | 3.4 s |
| `Install-ThornswoodServer.ps1 -NoTask` | 2.4 s |
| `Restore-Server.ps1`, live | 2.7 to 3.3 s |
| delete the folder | 0.1 s |

Typed now, the install line needs `-RequirePass on` at its end: no
build carries the join pass switch (issue #1223), and the installer refuses a
server without one (issue #1804). Restore-Server then puts the backup's own
switch back (issue #1845).

Typed now, the first `scp` carries `.\scripts\deploy\ServerBuild.ps1` as well,
into the same folder as the installer. Since issue #1214 the installer loads
it from beside itself to hold the payload's server files to their record, and
without it stops at `INSTALL REFUSED` having changed nothing (issue #1884).
The same `scp` carries `.\scripts\deploy\ServerReadyWait.ps1`, which is how
long a start may take to answer on both ports (issue #1938); without it the
installer stops the same way. And it carries `.\scripts\release\Read-JsonFile.ps1`
and `.\scripts\release\RecordShape.ps1`, which hold the payload's settings and
server-build.json to their shape (issue #2180); without them the installer
stops the same way.

The whole thing, typing included, is well under the hour this section used to
guess. `Install-ThornswoodServer`'s own load order check resolves against the
live server's plugins, because the payload's settings name
`C:/Thornswood-Server`; Restore-Server points them at the test folder first,
so its check is the one that means something.

Since issue #446 the installer unpacks into `C:\Thornswood-RestoreTest\server.stage-<stamp>`
beside the root and renames it in, and a second run keeps the first as
`server.prev-<stamp>`, all inside `C:\Thornswood-RestoreTest`, so the
`Remove-Item` above still takes everything. What it stops before a second
run is only what runs from that folder: the payload's settings name the live
server's port, and the process on that port is the live server, which is left
alone (`tests	est-install-server.ps1` holds it to that).

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
