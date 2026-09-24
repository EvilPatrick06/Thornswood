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
`tools\Watch-Load.ps1` nothing on the box kept a number over time.

    .\tools\Watch-Load.ps1 -Install   a line every five minutes, on the box
    .\tools\Watch-Load.ps1            bring the record down and read it

Each line holds the box's CPU, memory, free disk and network bytes, the people
on, and each of the seven services' processor time, memory and I/O
(`tools\vps-load.ps1` lists every column). `tools\Read-Load.ps1` turns it into
which service leads each of those, and when the busiest hour was.

Leave it a week that includes a busy evening before reading anything into it.
Whether the answer is the plan above or moving some services off this box is
for Patrick and Djinn in #dev, and whatever is done goes back on this page.

## Doing it

It is self service. No ticket needed.

1. `.\tools\Watch-Services.ps1 -Install`, first, before anything else. The
   change needs a restart, and if one of the four services does not come back
   on its own the watcher starts it within five minutes instead of you finding
   out from Discord.
2. `.\tools\Backup-Server.ps1`. Two minutes, and it is the only copy of the
   linked Discord accounts.
3. Billing panel, Services, pick the VPS, Change Plan, drag the slider to the
   16GB plan, pay, Continue.
4. Restart the server to apply it.
5. Disk Management on the server, right click the C: partition, Extend Volume,
   take all of it. Windows does not use new disk space on its own, so until
   this is done the plan says 160 GB and Windows still says 80.
6. `.\tools\Check-Load.ps1` to confirm 16 GB and 160 GB are really there.
7. `.\tools\Watch-Services.ps1` with no switches to confirm all four came
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

1. `.\tools\Backup-Server.ps1`
2. Let them do the change. It reboots.
3. Windows will not use the new disk space on its own. Disk Management,
   right click the C: partition, Extend Volume, take all of it.
4. `.\tools\Check-Load.ps1` to confirm the new numbers are really there.

Nothing else moves. The address is the same, so the launchers, the DNS record
and the Discord sign in all carry on.

## If it is a new machine, new address

Do the Vortex switch first. The installer on the site is about 18 GB today and
all of it would have to be copied to the new box. After the mods come out of
the installer it is a fraction of that. Moving first and switching later means
doing the painful copy for no reason.

Then, in this order:

1. `.\tools\Backup-Server.ps1`
2. Order the new box in the same datacenter as the old one, so nobody's ping
   changes. Windows Server, same version as the old one, which is in
   `notes.txt` inside the backup zip.
3. `.\tools\Setup-SshKey.ps1` against the new address, so the rest of the
   scripts can reach it without a password.
4. `.\tools\Bootstrap-VPS.ps1` against the new address. Node, Python, git,
   the folders.
5. Restore from the backup zip, by hand, into the same four places:
   `C:\Thornswood-Docs\data`, `C:\Thornswood-Bot`, `C:\Thornswood-Voice`, and
   the game server's own folder. The website's `data` folder is the one that
   matters. It has the linked Discord accounts, the boards and every document
   anyone has typed into on the site.
6. `.\tools\Install-Bot.ps1`, `.\tools\Install-Voice.ps1` and
   `.\tools\Install-ThornswoodServer.ps1` against the new address.
7. `.\tools\Deploy-Docs.ps1` against the new address. Not `-SeedDocs`. That
   flattens every document with the repo copy and would throw away what people
   have written.
8. Open the ports. They are listed in `notes.txt` in the backup. The game is
   UDP, which is the one people forget.
9. Import the scheduled tasks from the `tasks` folder in the backup, so the
   three services come back after a reboot.
10. Point the DNS A record for thornswood.net at the new address. Wait for the
    certificate to reissue before telling anyone, or the site shows a warning.
11. Check the Discord application's redirect URI. If it names the domain there
    is nothing to do. If it names an address, it has to be changed in the
    Discord developer portal by hand.
12. `.\tools\Set-Vps.ps1`. It asks for the new address and repoints all
    twenty three files in the repo that carry the old one, and adds a line to
    the launcher so copies already installed move themselves across.
13. `.\tools\Ship.ps1 "Server moved"` so a fresh install has the new address
    baked in.
14. `.\tools\Set-Server.ps1` with the new address. This is the one that moves
    everybody. It checks the new box answers before it publishes.

## Then leave the old box alone for a week

Do not cancel it the same day. Two things still point at it: any launcher that
has not checked for an update yet, and every Discord message anyone has ever
posted with the old address in it. A week of the old box quietly running costs
one month at the old price and saves a week of people asking why nothing works.

`.\tools\Check-Load.ps1` against the old address shows whether anyone is still
landing there. When that is zero for a few days, cancel it.

## The logs on the box, and how big they get

Each service writes its log in its own folder, and each service's log is
rolled: at 4 MB `x.log` becomes `x.log.1`, what was `.1` becomes `.2`, and five
are kept. The oldest past five is the only thing that is ever removed. The
watchdog's files and the door's log are kept a different way, or not at all,
and are listed below.

- `server.log` (game server, live and dev), `voice.log` (live and dev) and
  `bot.log` are written by cmd's `>>` from the scheduled task, and Windows
  will not move a file held that way while the service runs. So
  `roll-log.ps1`, beside each service, rolls it just before the service
  starts. A service that runs for days grows one file until its next restart.
  An install of the game server or of voice rolls its log whatever the size,
  so the run it starts has a file of its own and the one before is `.1`.
- `thornswood.log` (the gamemode) and `site.log` (the website) roll
  themselves.
- `C:\Thornswood-Watch\watch.log` and `restarts.txt` beside it are not
  rolled. Past 2,000 lines the watcher keeps the last 1,000 of each and the
  rest is gone.
- `load.csv` in the same folder, the five minute load record, rolls itself to
  `load.1.csv` at 4 MB, one kept, which is about five weeks. Its `load.log`
  keeps the last 500 lines once it passes 256 KB.
- `private\door.log` in the game server's folder is not rolled or trimmed.
  The gamemode appends a line each time the door decides about somebody, and
  the file grows until somebody moves it.
- `.\tools\Get-Logs.ps1` reads only the current file. After a restart, last
  night's crash may be in `.1` beside it.
- Whether the gamemode can write its log at all is at
  `http://192.135.112.23:3000/thornswood-log.json`, and on 7788 for dev.
  `"ok": false` means thornswood.log has stopped, and `why` says what the
  write was refused with.
