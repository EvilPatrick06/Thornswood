# Moving the server

Written 15 September 2026, while working out whether to upgrade the box.

## What the box is now

BisectHosting, KVM, VirtFusion panel, `192.135.112.23`, on the 8GB plan at
$32 a month. What is actually on it, read off the box on 15 September 2026:

    Windows Server 2022 Standard
    AMD EPYC-Milan, 5 cores
    8 GB RAM, 2.6 GB in use
    80 GB disk, 81 percent free

Worth knowing: their page advertises "Ryzen 7 9700X or better" for the VPS
range, and this box is an EPYC Milan, which is an older and slower chip per
core. The advertised CPU is what the range can land on, not what any one
server gets. Ask what the new one would be before assuming an upgrade makes
anything faster, as opposed to only bigger.

The website, the game server, the Discord bot and the voice server all run on
this one machine.

Their tiers, monthly, 15 percent off if paid annually:

| plan | RAM | disk | bandwidth | cores | price |
|---|---|---|---|---|---|
| 4GB | 4 GB | 40 GB | 4 TB | 4 | $16 |
| 8GB | 8 GB | 80 GB | 8 TB | 5 | $32 |
| 16GB | 16 GB | 160 GB | 16 TB | 6 | $64 |
| 20GB | 20 GB | 160 GB | 16 TB | 7 | $80 |
| 24GB | 24 GB | 160 GB | 16 TB | 8 | $96 |
| 32GB | 32 GB | 160 GB | 16 TB | 8 | $128 |

The disk stops growing after the 16GB plan. Everything above it is RAM and
cores for sixteen dollars a step, on the same 160 GB.

## The decision

Buy the 16GB plan. It is 16 GB of RAM, double the disk at 160 GB, double the
bandwidth at 16 TB, and one more core, for $64. That is 16 GB and more storage
inside an $80 budget with $16 left over.

The 20GB plan is the one that spends the whole $80. It adds 4 GB of RAM and one
core on the same 160 GB disk. If the budget is there to be used, it is not a
bad buy, but it is RAM only. The storage is identical.

Paying annually takes 15 percent off either one, so 16GB works out near $54 a
month and 20GB near $68. That commits you for the year.

## Measuring it first

The decision above rests on one reading, taken on 15 September. Until
`scripts\vps\Watch-Load.ps1` nothing on the box kept a number over time.

    .\scripts\vps\Watch-Load.ps1 -Install   a line every five minutes, on the box
    .\scripts\vps\Watch-Load.ps1            bring the record down and read it

Each line holds the box's CPU, memory, free disk and network bytes, the people
on, and each of the seven services' processor time, memory and I/O
(`scripts\vps\vps-load.ps1` lists every column). `scripts\vps\Read-Load.ps1` turns it into
which service leads each of those, and when the busiest hour was.

Leave it a week that includes a busy evening before reading anything into it.
Whether the answer is the plan above or moving some services off this box is
for the team in #staff-general, and whatever is done goes back on this page.

## Doing it

It is self service. No ticket needed.

1. `.\scripts\vps\Watch-Services.ps1 -Install`, first, before anything else. The
   change needs a restart, and if one of the four services does not come back
   on its own the watcher starts it within five minutes instead of you finding
   out from Discord.
2. `.\scripts\vps\Backup-Server.ps1`. Two minutes, and it is the only copy of the
   linked Discord accounts.
3. Billing panel, Services, pick the VPS, Change Plan, drag the slider to the
   16GB plan, pay, Continue.
4. Restart the server to apply it.
5. Disk Management on the server, right click the C: partition, Extend Volume,
   take all of it. Windows does not use new disk space on its own, so until
   this is done the plan says 160 GB and Windows still says 80.
6. `.\scripts\vps\Check-Load.ps1` to confirm 16 GB and 160 GB are really there.
7. `.\scripts\vps\Watch-Services.ps1` with no switches to confirm all four came
   back up.

What the billing charges is the difference between the plans for the days left
in this cycle, then the full new rate from the next billing date.

Two things their article does not say, so check them yourself:

- **Whether the IP stays.** A plan change on VirtFusion can either grow the
  machine in place or move it to a different node. In place keeps the address.
  A move does not, and then the rest of this page applies. Ask them first if
  you would rather know than find out, or just look at the address in the panel
  after the restart.
- **That it is close to one way.** Growing a disk on KVM is easy and shrinking
  one is not. Their own article says downgrades earn no credit and should be
  timed for the end of a billing period. Go up when you mean it.

## If it is a package change, same box

1. `.\scripts\vps\Backup-Server.ps1`
2. Let them do the change. It reboots.
3. Windows will not use the new disk space on its own. Disk Management,
   right click the C: partition, Extend Volume, take all of it.
4. `.\scripts\vps\Check-Load.ps1` to confirm the new numbers are really there.

Nothing else moves. The address is the same, so the launchers, the DNS record
and the Discord sign in all carry on.

## If it is a new machine, new address

Checked against the scripts on 29 September 2026 (issue #454): every command
below was read against the script it names, the parameters it passes and the
order it needs, and `tests\test-new-box-runbook.ps1` checks the same on every
pull request, so a renamed script or parameter fails the build rather than the
day this is needed. It has not been followed on a real new box yet. Until it
has, it is a plan checked on paper: write what the first real move finds back
into it, with the date.

Run everything from Patrick's machine (One), in PowerShell 7, from the root of
a worktree of the repository on a branch of its own, because step 3 changes
files in it. Steps 1 to 9 leave the old box serving, so they can take as many
days as they need.

```powershell
git -C C:\Users\evilp\Downloads\Thornswood-Repo fetch origin
git -C C:\Users\evilp\Downloads\Thornswood-Repo worktree add "C:\ThornswoodTemps&Worktrees\worktrees\move" -b patrick/move-to-new-box origin/main
Set-Location "C:\ThornswoodTemps&Worktrees\worktrees\move"
```

The secrets a move needs, and where each one comes from. None of them is ever
typed on a command line or written on this page.

| Secret | Comes from | Used at |
| --- | --- | --- |
| The new box's Administrator password | the hosting provider's panel for the new box | typed once, at Setup-SshKey's prompt, step 4 |
| The backup passphrase | `Documents\thornswood-backup-key.txt` on One | read there by Restore-Box at step 9, sent as a file by it at step 13 and by Install-Backup at step 23 |
| The bot token, the Discord client secret, the site's keys, the door key | inside the backup: the site's `config.json`, the bot's `bot.env.json`, each server's `private\door.json` | put back by Restore-Box, step 13; Install-Bot runs with `-NoToken`, so nothing asks for them |
| The staff channel webhook | Discord: the staff channel, Edit Channel, Integrations, Webhooks, Copy Webhook URL | pasted at Watch-Services' prompt, step 21 |
| Patrick's GitHub sign in | `gh auth login` on One | the build runner's registration, step 24 |
| The DNS records | Patrick's own Cloudflare login, which he signs in to with GitHub, where thornswood.net is registered | step 18 |
| Code signing | `records\signing\signing.json` on One and the Azure account behind it | the installer, step 17, and the main Ship, step 29 |

### Standing it up, while the old box still serves

1. **Order the box.** In the same datacenter as the old one, so nobody's ping
   changes, and Windows Server 2022 like the old one: the `windows` line of
   the backup's NOTES.txt (10.0.20348 is Windows Server 2022), which
   `.\scripts\vps\Restore-Backup.ps1 -Backup <newest backup> -CheckOnly -NoPause`
   prints (the newest is in `local\backups` in the repository folder). Note the new
   address, and leave the Administrator password in the panel.
2. **Turn on its ssh server**, in the new box's own console, which the
   provider's panel opens. A fresh Windows Server 2022 does not have one, and
   every script here reaches the box over ssh:
   ```powershell
   Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
   Set-Service -Name sshd -StartupType Automatic
   Start-Service sshd
   ```
   Windows opens port 22 for it by itself, as the firewall rule
   `OpenSSH-Server-In-TCP`. Then, in the same console and not over the
   network, read the box's own key fingerprints for step 3:
   ```powershell
   Get-ChildItem C:\ProgramData\ssh\ssh_host_*_key.pub | ForEach-Object { ssh-keygen -lf $_.FullName }
   ```
   They are public; the private halves never leave the box.
3. **Point this branch at the new box:**
   `.\scripts\vps\Set-Vps.ps1 -Address <new address>`. It rewrites
   `scripts\vps\vps.json` and every other file that carries the old address,
   and adds a line to the launcher so installed copies move themselves across.
   From here on every script talks to the new box without being told, and the
   old box is reached only where a step says `-VpsHost <old address>`. Then
   add the `SHA256:...` values from step 2 to `hostKeys` in
   `scripts\vps\vps.json`, beside the old box's, which stay until the move is
   done: every script runs ssh with StrictHostKeyChecking=yes (issue #450), so
   a box whose key is not pinned there is refused. The changed files stay on
   this branch until step 27.
4. **This machine's key on the box:** `.\scripts\vps\Setup-SshKey.ps1`. It
   writes the box into known_hosts only when it shows a key step 3 pinned,
   then asks for the Administrator password once. Then
   `.\scripts\vps\Setup-SshKey.ps1 -Test` says the key works. Another machine that deploys runs
   `.\scripts\vps\Setup-SshKey.ps1 -KeyOnly` and Patrick adds the line it
   prints with `.\scripts\vps\Add-VpsKey.ps1`.
5. **PowerShell 7, Node and Git on the box**, and the firewall for the live
   game:
   `.\scripts\vps\Remote.ps1 -File .\scripts\vps\Bootstrap-VPS.ps1 -Arguments '-IncludeGit'`.
   Bootstrap-VPS runs on the box and refuses to run anywhere else; Remote.ps1
   carries it there. Git is for the build runner, step 24. Python comes with
   the bot, step 15.
6. **The live game server program**, built here from this branch and installed
   there without being started. The world is not in it; that is step 13.
   ```powershell
   .\scripts\deploy\Deploy-Gamemode.ps1
   .\scripts\release\Export-ServerPayload.ps1
   scp (.\scripts\release\Where.ps1 ServerZip) Administrator@<new address>:C:/thornswood-server.zip
   scp .\scripts\deploy\Install-ThornswoodServer.ps1 .\scripts\deploy\ServerSettings.ps1 .\scripts\deploy\ServerBuild.ps1 .\scripts\deploy\ServerReadyWait.ps1 .\scripts\release\Read-JsonFile.ps1 .\scripts\release\RecordShape.ps1 .\scripts\vps\Roll-Log.ps1 Administrator@<new address>:C:/
   ssh Administrator@<new address> "powershell -NoProfile -ExecutionPolicy Bypass -File C:\Install-ThornswoodServer.ps1 -RequirePass on"
   ```
   The last one prints `load order: all <n> plugins present` and registers the
   `Thornswood Server` task, which starts at boot; without `-StartNow` it does
   not start now. If the box restarts before step 13, stop that task first.
   `-RequirePass on` is there because no build carries the join pass switch
   (issue #1223) and the installer refuses a server without one (issue
   #1804); step 13 puts the old server's own switch back from the backup
   (issue #1845), so on holds only until then.
   The installer unpacks beside `C:\Thornswood-Server` and checks the payload
   there before it touches anything (issue #446); on a box that already has a
   server it keeps the one it replaces as `C:\Thornswood-Server.prev-<stamp>`,
   and `.\scripts\release\Publish-Server.ps1 -PutBack` puts that back. On a
   new box there is nothing to keep.
   The gamemode that goes up is this branch's, which is main's; if main holds
   gamemode changes that have not been tried on dev, tell Patrick before
   step 16. Restore-Box says so too (step 13).
7. **Live voice, set the way the old box runs it:**
   `.\scripts\deploy\Install-Voice.ps1 -Bind 127.0.0.1`. On
   29 September `https://thornswood.net/voice/health` said auth on, bind
   127.0.0.1, no relay and chat range off; read it again on the day and pass
   what it says. On a new box there is nothing running for Install-Voice to
   keep; loopback is its default since #1304, so `-Bind 127.0.0.1` only says
   so out loud, and no firewall rule is opened for the port. Auth needs no
   flag: since #1303 the service refuses every join that cannot prove
   itself.
8. **The dev game server and dev voice**, copied from the live ones onto their
   own ports, tasks and firewall rules, with nothing of live's private folder,
   chat logs or keys, and dev voice starting with auth on, on 127.0.0.1 only
   (#1082, #1083):
   `.\scripts\vps\Remote.ps1 -File .\scripts\vps\vps-dev-instance.ps1`. Then dev
   voice set the way `https://thornswood.net/voice-dev/health` says it runs
   (auth on, bind 127.0.0.1 on 29 September), which is what the dev instance
   already starts it with:
   `.\scripts\deploy\Install-Voice.ps1 -Root C:\Thornswood-Voice-Dev -Port 7789 -TaskName 'Thornswood Dev Voice' -Bind 127.0.0.1`.
   The dev server is not started.
9. **Is it ready for the restore:**
   `.\scripts\vps\Restore-Box.ps1 -Backup <newest backup> -Check`. It opens the
   backup here with the passphrase, and asks the new box whether both server
   folders hold the program and whether anything the restore writes under is
   running. It sends nothing, and should end `READY`.

### Moving over

The old box stops serving at step 11. Pick a quiet hour: nothing anybody does
on the old box after that is carried across. If the old box is already gone,
skip steps 10 to 12 and use the newest backup in `local\backups` in the
repository folder, as docs\RESTORING.md "The box is gone" says.

10. **Tell people** in Discord that the server is going down to move, and for
    about how long.
11. **Freeze the old box and take its last backup:**
    `.\scripts\vps\Remote.ps1 -VpsHost <old address> -File .\scripts\vps\vps-freeze.ps1`.
    It turns the watchdog off, stops both game servers, the site, the bot and
    both voice services, runs the nightly backup once and names the file, and
    says which account the site ran as. It should end `FROZEN`. If the move is
    called off, the same line with `-Arguments '-Undo'` puts the old box back.
12. **Bring that backup here:**
    `.\scripts\vps\Fetch-Backups.ps1 -VpsHost <old address>`, from the
    repository folder itself, not a worktree (it stops in one). It lands in
    `local\backups` there and is opened to check it.
13. **Put it back:** `.\scripts\vps\Restore-Box.ps1 -Backup <the backup from step 12>`,
    with `-Expect <a profile id>` for somebody known to have a character. It
    carries the backup, the passphrase file and the restore scripts to the new
    box; puts back both worlds (Restore-Server.ps1) and the site's data,
    config, uploads and feed store, the bot's settings and join record and the
    Caddyfile (vps-restore-services.ps1); and deletes its copy from the box
    again. It should end `RESTORE BOX OK`. A `GAMEMODE DIFFERS` line means
    step 6 installed a gamemode the old box was not running: ask Patrick
    before step 16.
14. **The site:** `.\scripts\deploy\Deploy-Docs.ps1`, with
    `-RunAs 'LOCAL SERVICE'` when step 11 said the site ran as LOCAL SERVICE.
    Never `-SeedDocs`, which flattens every document with the repo copy and
    throws away what people have written. It starts the site on the restored
    config, so nobody has to link Discord again. It also gives the site its
    read on the servers' logs and the chat logs, so then lock the server and
    voice folders to their own services (#1105):
    `.\scripts\vps\Remote.ps1 -File .\scripts\vps\Lock-VpsFolders.ps1`.
15. **The bot:** `.\scripts\deploy\Install-Bot.ps1 -NoToken`. Python, its
    libraries and the task; the token and the site key are the restored ones,
    so it asks for nothing. The old bot stopped at step 11, so only this one
    answers in Discord.
16. **The game servers, live first and alone:**
    `.\scripts\vps\Remote.ps1 "Start-ScheduledTask -TaskName 'Thornswood Server'"`,
    then `http://<new address>:3000/api/servers/thornswood/manifest.json`
    answers when it is up, and `.\scripts\vps\Get-Logs.ps1` brings its logs
    here to read. Then dev, the same way:
    `.\scripts\vps\Remote.ps1 "Start-ScheduledTask -TaskName 'Thornswood Dev Server'"`
    and the same page on port 7788.
17. **The feed and the installer.** Every launcher updates from
    `https://thornswood.net/feed`. Its store came back in step 13; its
    downloads are in no backup, because they are the size of every release.
    `.\scripts\deploy\Remirror-Site-Feed.ps1 -Check` and
    `.\scripts\deploy\Remirror-Site-Feed.ps1 -Dev -Check` say what the new box
    lacks and whether this machine has the bytes; the same two without `-Check`
    send them. For any this machine does not have, bring the old box's copy
    down first with
    `scp -r Administrator@<old address>:C:/Thornswood-Docs/feed/assets "C:\ThornswoodTemps&Worktrees\temp\move\feed-assets"`
    (and `feed-dev/assets` for the dev feed) and add
    `-AssetDir "C:\ThornswoodTemps&Worktrees\temp\move\feed-assets"`. Then
    `.\scripts\release\Publish-Installer.ps1` puts the installer from the last
    package build back on the site.
18. **The name:** in Patrick's Cloudflare login, point the A records for
    `thornswood.net` and `www` at the new address, not proxied (Watch-Outside's
    dns check expects them straight at the box). When the name resolves there,
    `.\scripts\deploy\Setup-Domain.ps1`. It refuses until it does, then
    installs Caddy and the `Thornswood Web` task, sends
    `scripts\deploy\Caddyfile` (the restored one is kept beside it as
    `Caddyfile.before-<date>`), moves the site onto loopback and asks for the
    certificate. Discord sign in needs nothing: the site builds its redirect
    from the name, not the address.
19. **Check it from outside:** `.\scripts\vps\Check-Site.ps1 -NoSsh -NoPause`,
    and `https://thornswood.net/voice/health` and `/voice-dev/health` answer.
    Wait for the certificate before telling anybody, or the site shows a
    warning.

### Watching it

20. **The watchdog, only now,** because it starts whatever is not running and
    everything should be running by here:
    `.\scripts\vps\Watch-Services.ps1 -Install`.
21. **Where it posts when the bot is down:**
    `.\scripts\vps\Watch-Services.ps1 -SetWebhook`. It asks for the webhook at
    a prompt and posts a test message in the staff channel.
22. **The load record:** `.\scripts\vps\Watch-Load.ps1 -Install`.
23. **The nightly backup, and one now:**
    `.\scripts\deploy\Install-Backup.ps1 -RunNow`. The box already has this
    machine's passphrase from step 13; on a box without one, Install-Backup
    sends this machine's copy up rather than making a new one.
24. **The build runners:** `.\scripts\deploy\Install-Runner.ps1`, then
    `.\scripts\deploy\Install-Runner.ps1 -Number 2` and up for as many as the
    old box had (the repository's Settings, Actions, Runners lists them). Each
    replaces the runner of that name the old box registered, so
    `Launcher builds` runs on the new box from the next pull request.
25. **Close it to all but ssh with a key**, once every machine that deploys
    has passed `.\scripts\vps\Setup-SshKey.ps1 -Test` against it:
    `.\scripts\vps\Harden-VPS.ps1`. It proves key login first, then turns ssh
    password login and Remote Desktop off (issue #450). The provider's console
    and the Administrator password stay the way back.

### Moving everybody

26. **Everybody's launcher:** `.\scripts\ops\Set-Server.ps1 -Address <new address>`.
    It checks the new box answers, then moves this machine's launcher and the
    feed every other launcher reads. Then tell people in Discord it is back.
27. **The repository:** take the old box's fingerprints out of `hostKeys`,
    then commit what Set-Vps and step 3 changed on this branch, push it, open
    a pull request and merge it once `Launcher builds` is green.
28. **The version:** `.\scripts\release\Bump-Version.ps1` through its own pull
    request, merged on green.
29. **A launcher with the new address built in**, so a fresh install is right:
    a main Ship from a machine that can sign, as Developer-Guide.md says. A move is one
    of the main releases that does not wait for dev, because the old address
    is going away:
    ```powershell
    .\scripts\release\Ship.ps1 "Thornswood has moved to a new server
    - The launcher finds the new server by itself after this update, so there is nothing to change on your side.
    - If it cannot connect straight away, close the launcher and open it again so it picks up the new address."
    ```
30. **The watchers on this machine**, last, from a checkout of main that has
    step 27 in it, because each keeps its own copy of the address:
    `.\scripts\vps\Fetch-Backups.ps1 -Schedule` brings the new box's backups
    here every day, and `.\scripts\vps\Watch-Outside.ps1 -Install` watches the
    site, the feeds, the certificate, the name and the runner from outside it.

## Then leave the old box alone for a week

Do not cancel it the same day. It is frozen from step 11 and serves nothing,
but it is the way back if something on the new box turns out wrong
(`vps-freeze.ps1 -Undo`, step 11), and its `C:\Thornswood-Backup` holds the
last backups taken there. A week of it costs one month at the old price.
Once the new box has run a week and Fetch-Backups has brought its backups
here every night, cancel it.

## Rehearsing the move on a throwaway server

Everything above has only been checked on paper: `tests\test-new-box-runbook.ps1`
proves every command and parameter is real and in the right order, but
nobody has followed it on a real new box. A rehearsal is how to find the step
that fails before the day it matters. Patrick, 29 September: "This a playtest
server in alpha so everyone knows everything is throwaway rn, just add that
all to the guide and I might do it eventually."

**What it costs.** A small Windows Server 2022 VPS rented by the hour, for an
afternoon. Nothing on the real box changes, and nobody playing notices.

**During the alpha all world and character data is throwaway.** So a
rehearsal that goes wrong costs nothing, and a real move that loses the world
or the characters is acceptable too: tell people, and carry on.

The steps, in order:

1. **Rent it.** Any provider, the smallest Windows Server 2022 box it has,
   billed by the hour. Note its address and leave its Administrator password
   in the provider's panel.
2. **Point only this rehearsal at it, never the real box.** Do not run
   Set-Vps and do not edit `scripts\vps\vps.json`. Instead give it a
   per-machine override (issue #1090, `scripts\vps\Vps.ps1`): a file holding
   only `{"address": "<its address>", "hostKeys": ["SHA256:..."]}`, with the
   fingerprints step 2 of "If it is a new machine" reads in its console.
   Save it as `C:\ThornswoodTemps&Worktrees\temp\rehearsal\vps.json` and, in
   the one PowerShell window the rehearsal runs in, set
   `$env:THORNSWOOD_VPS_LOCAL = "C:\ThornswoodTemps&Worktrees\temp\rehearsal\vps.json"`.
   Every script run from that window talks to the throwaway box, and every
   other window and every lane on the machine still talks to the real one.
   (`%LOCALAPPDATA%\Thornswood\vps.json` also works, but it points the whole
   machine at the throwaway box, lanes included, so use it only on a machine
   nothing else deploys from.)
3. **Follow "If it is a new machine, new address" from start to finish** in
   that window, including step 13, the restore from the newest backup in
   `local\backups` in the repository folder. Skip only what would reach the real box or
   the people on it: step 3 (the override stands in for it), steps 10 to 12
   (they freeze the real box), step 18 (the name stays on the real box),
   steps 20 to 22 and 24 (a second watchdog, alert poster and build runner
   would answer for the real ones), and steps 26 to 30 (they move everybody).
   Install the bot in step 15 to see it start, then stop it at once
   (`.\scripts\vps\Remote.ps1 "Stop-Service ThornswoodBot"`): it holds the same
   token as the real bot, and two of them answer everything twice. Check the
   site by its address rather than by name, since the name still points at
   the real box.
4. **Write down every step that fails**, and every step whose wording did not
   match what happened, on the issue for the rehearsal, with what was typed
   and what came back. Fix the page from those notes in the same pull request
   as anything a script needed.
5. **Delete it all.** Cancel the server at the provider, delete the override
   file, and remove the throwaway box's lines from `.ssh\known_hosts` (and
   from `.ssh\config` if Setup-SshKey added one), so nothing is left pointing
   at an address somebody else will be given next.

## The logs on the box, and how big they get

Each service writes its log in its own folder, and each service's log is
rolled: at 4 MB `x.log` becomes `x.log.1`, what was `.1` becomes `.2`, and five
are kept. The oldest past five is the only thing that is ever removed. The
watchdog's files and the door's log are kept a different way, or not at all,
and are listed below.

- `server.log` (game server, live and dev) and `voice.log` (live and dev)
  are written by cmd's `>>` from the scheduled task, and Windows will not
  move a file held that way while the service runs. So `roll-log.ps1`,
  beside each service, rolls it just before the service starts. A service
  that runs for days grows one file until its next restart. An install of
  the game server or of voice rolls its log whatever the size, so the run it
  starts has a file of its own and the one before is `.1`.
- `thornswood.log` (the gamemode), `site.log` (the website) and `bot.log`
  roll themselves. The bot's is written by its Windows service,
  `ThornswoodBot` (`scripts\vps\BotService.cs`, issue #465), which rolls it
  by size while the bot runs.
- `C:\Thornswood-Watch\watch.log` and `restarts.txt` beside it are not
  rolled. Past 2,000 lines the watcher keeps the last 1,000 of each and the
  rest is gone.
- `load.csv` in the same folder, the five minute load record, rolls itself to
  `load.1.csv` at 4 MB, one kept, which is about five weeks. Its `load.log`
  keeps the last 500 lines once it passes 256 KB.
- `private\door.log` in the game server's folder is not rolled or trimmed.
  The gamemode appends a line each time the door decides about somebody, and
  the file grows until somebody moves it.
- `.\scripts\vps\Get-Logs.ps1` brings down the current file of each log and,
  for every log that rolls (server, thornswood, voice, site and bot), the
  rolled `.1` to `.5` the box has, under the same names, so last night's
  crash in `.1` comes down with the rest. `door.log` does not roll, so only
  its current file comes. Each file is the last 4000 lines unless `-Lines` or
  `-All` asks for more.
- The site's /sessions page reads a session's game server lines out of
  `server.log` and, when that is shorter than 4 MB, out of the end of
  `server.log.1` and the older ones behind it, so a session from before a
  restart, the crash session included, is still on the page.
- Whether the gamemode can write its log at all is at
  `http://192.135.112.23:3000/thornswood-log.json`, and on 7788 for dev.
  `"ok": false` means thornswood.log has stopped, and `why` says what the
  write was refused with.
