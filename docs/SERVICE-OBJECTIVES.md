# Service objectives

What "working" means for each service Thornswood runs, the number that says so,
what measures it today, who is told, and who is meant to act. Issue #2183.

Written 12 October 2026 from the scripts as they are on main. Every threshold
below is one a check already uses, with its file and line. Where no check
measures something, this page says "nothing measures this today", and any
number it offers there is marked **Proposal**. Nothing here claims a service
has met an objective. Since #2183 `scripts/vps/Read-Availability.ps1` turns the
down and back lines into down minutes and availability per service (see
"Availability"), but no baseline has been read with it yet (see "Baseline
period").

The owners below were **decided by Patrick on 12 October 2026**: he took the
proposed list as written (issue #2183). Behind every row is still Patrick's
own accounts ([OWNERSHIP.md](OWNERSHIP.md)).

## How the checks work

Three things watch the services, and one bot posts what they find.

- **The watchdog on the VPS**, `scripts/vps/Watch-Services.ps1`, installed as
  the task `Thornswood Watch`, every five minutes as SYSTEM
  (`Watch-Services.ps1:-RepetitionInterval (New-TimeSpan -Minutes 5)`, at normal priority, `Watch-Services.ps1:-MultipleInstances IgnoreNew -Priority 4`). It checks each service in its list
  (`Watch-Services.ps1:$checks`) and restarts one that does not answer, at
  most three times an hour (`Watch-Services.ps1:restarts this hour. Leaving it.`). A failed HTTP health
  answer counts after two runs in a row (`Watch-Services.ps1:$healthMisses = 2`), and a service is said to be back after two good
  runs (`Watch-Services.ps1:$backAfter = 2`). It writes one message
  when something goes down and one when it is back into
  `C:\Thornswood-Watch\alerts.jsonl`.
- **The outside watcher**, `scripts/vps/Watch-Outside.ps1`, on GitHub's Linux
  runners from a public repository of its own, about every five minutes,
  whether One is on or not (issue #2755). It asks what a stranger on the
  internet sees: the site, both feeds, the certificate, the name, the
  registration, the build runners and the Nexus collection
  (`Watch-Outside.ps1:Get-Checks`). A check whose remote service did not
  answer says it could not check, never that the thing is down, and is told
  only once it has lasted about an hour (`Watch-Outside.ps1:function Blind`,
  issue #2857).
- **The bot's uptime ping**, `bot/bot.py` `uptime_ping`, to an outside monitor
  at `PING_URL` in `bot.env.json` on the VPS, every minute while the bot is on
  Discord (issue #449). Whether `PING_URL` is set is not visible from the
  repository.
- **Where people are told.** The bot reads `alerts.jsonl` every minute and
  posts each message in #staff-updates, the staff channel, by the id in
  `bot/staff-channel.txt`. When the bot has not posted one within two and a
  half minutes (`Watch-Services.ps1:$ackWait = 150`), the watchdog posts it
  through its webhook, which `-SetWebhook` only accepts in that channel. The outside watcher
  posts its messages through the same webhook itself, from GitHub's runners,
  which cannot reach the box.

## The objectives

One row per service. "Window" is how long a failure has to last before the
check calls it one.

| Service | Metric | Window | Threshold today | Measured by | Alert | Cadence | Owner |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Site, from outside | `https://thornswood.net/` answers over HTTPS with a valid certificate | 2 runs in a row, 10 minutes | Any HTTP answer within 10 s | `Watch-Outside.ps1:Get-Checks`; Caddy from the box, `Watch-Services.ps1:Url = 'https://thornswood.net/'` | Staff channel | 5 min | Website lane, with Patrick |
| Site app | `http://127.0.0.1:3001/api/public` answers under HTTP 500 within 10 s | 2 runs, 10 minutes | Down: restart; sick: told | `Watch-Services.ps1:Health = 'http://127.0.0.1:3001/api/public'`, `Watch-Services.ps1:HealthProblem` | Staff channel | 5 min | Website lane, with Patrick |
| Certificate | Days left on the thornswood.net certificate | 1 run | Under 14 days | `Watch-Outside.ps1:CertDays = 14` | Staff channel | Hourly | Patrick (holds the domain) |
| Domain | Days left on the registration | 1 run | Under 30 days | `Watch-Outside.ps1:DomainDays = 30` | Staff channel | Daily | Patrick (holds the domain) |
| Feed, main and dev | `/feed/version.json` and `/feed-dev/version.json` answer 200 with a launcher address and packs, and that launcher answers its first byte | 2 runs, 10 minutes | Any failure of those | `Watch-Outside.ps1:foreach ($f in $S.Feeds)` | Staff channel | 5 min | Whoever shipped last on that channel |
| Live game server | Resources port 3000 answers, and its manifest answers under HTTP 500 within 10 s | 2 runs, 10 minutes for the manifest | Down: restart; sick: told | `Watch-Services.ps1:Health = 'http://127.0.0.1:3000/api/servers/thornswood/manifest.json'` | Staff channel | 5 min | Patrick, with Djinn as second |
| Dev game server | The same on port 7788 | 2 runs, 10 minutes | The same | `Watch-Services.ps1:Health = 'http://127.0.0.1:7788/api/servers/thornswood/manifest.json'` | Staff channel | 5 min | Whoever deployed dev last |
| Live voice | Port 7778 answers and `/health` answers under HTTP 500 within 10 s | 2 runs, 10 minutes | Down: restart; sick: told | `Watch-Services.ps1:Health = 'http://127.0.0.1:7778/health'` | Staff channel | 5 min | Patrick |
| Dev voice | The same on port 7789 | 2 runs, 10 minutes | The same | `Watch-Services.ps1:Health = 'http://127.0.0.1:7789/health'` | Staff channel | 5 min | Whoever deployed dev last |
| Bot | The bot's python process runs and `heartbeat.json` is under 10 minutes old | 10 minutes | Heartbeat older than 600 s, or no process: restart the service | `Watch-Services.ps1:$beatStale = 600`, `Watch-Services.ps1:BotSilent`; heartbeat every 60 s (`bot/bot.py:HEARTBEAT_EVERY`) | Staff channel, through the webhook when the bot is the thing down | 5 min | Patrick |
| Backup freshness | The `Thornswood Backup` task's last result, and the newest backup's age | 1 run | Last result not 0 (or running), or newest over 26 hours old | `Watch-Services.ps1:BackupProblem`, `Watch-Services.ps1:Hours = 26` | Staff channel | 5 min | Patrick (holds the passphrase) |
| Off-box copy | Age of the newest backup on One that Fetch-Backups.ps1 checked, by the stamp in the name it writes into `offbox.txt` on the box | 1 run | Over 26 hours old, or none said | `Watch-Services.ps1:function OffBoxProblem`, `Watch-Services.ps1:OffBox = (Join-Path $root 'offbox.txt'); Hours = 26`; filled by `Fetch-Backups.ps1` at 4:15 AM (`Fetch-Backups.ps1:every day at 04:15`) | Staff channel | 5 min, on the box, One on or off | Patrick |
| Disk on the VPS | Free space on C: | 1 run | Under 20% DISK LOW, under 10% DISK CRITICAL | `Watch-Services.ps1:$diskLow = 20`, `Watch-Services.ps1:$diskCritical = 10` | Staff channel | 5 min | Installer lane (as `Forecast-Storage.ps1` names it), with Patrick |
| Disk forecast | Days until free space on C: crosses 10% and 20%, a straight line through one sample a day over the last 30 days | 14 samples over at least 7 days before any forecast | Warning: 10% within 30 days, or 20% within 7. Critical: 10% within 7 days, or already under | `Forecast-Storage.ps1:$WarnDays = 30`, `Forecast-Storage.ps1:$CriticalDays = 7`; the `Thornswood Disk History` task, daily at 04:00 box time | Staff channel, once when the forecast turns and once when it is back | Daily | Warning: Installer lane. Critical: whoever is on staff |
| Build runners | Every runner's service runs, and GitHub lists every runner online | 1 run on the box; 3 runs, 15 minutes from outside | Any runner not running or not online | `Watch-Services.ps1:$tellOnly`; `Watch-Outside.ps1:are not all online on GitHub` | Staff channel | 5 min | GitHub lane, with Patrick |
| RPO (data that can be lost) | Hours between the newest backup and a failure | Per failure | 26 hours on the box and 26 hours off it (the two lines above) | See "RPO" below | As above | Daily | Patrick |
| RTO (time to come back) | Minutes from deciding to restore to a server answering | Per restore | Last rehearsed more than 35 days ago: the monthly hands-on rehearsal is overdue | `Check-RehearsalDue.ps1:$Days = 35`, reading RESTORING.md's Last rehearsed line; see "RTO" below | The board: the nightly checks fail and "Nightly checks failed" says so | Nightly | Patrick |

## Service by service

### Site

What a visitor touches is Caddy on 443, so the outside check and the box's own
Caddy check both ask over the public name. Any HTTP answer, a 502 included,
counts as Caddy being up, because a 502 is the app behind it, and the app has
its own check (`Watch-Services.ps1:SiteAnswers`). The 21 September outage, Caddy
stopped for hours while the app answered 3001, is why
(`Watch-Services.ps1:on 21 September Caddy was stopped for hours`).

Limitations: until 20 October the outside watcher ran on One and saw nothing
while One was off. Its log there held 16 lines from 30 September to
9 October where One itself was offline and nothing was judged. Since #2755
it runs on GitHub's runners, whose scheduled runs can start late when GitHub
is busy, so "about every five minutes" is the most it promises.
Response time is not recorded anywhere: the 213 ms in the outside watcher's
header is one reading from 28 September.

**Proposal:** availability of 99% a calendar month for the site from outside
(about seven hours down). The metric is the availability
`Read-Availability.ps1` gives for `caddy` (the box asking over the public
name) from `alerts.jsonl` (see "Availability"). The outside watcher's own
down and back lines no longer reach that file, because GitHub's runners
cannot reach the box (#2755); its messages in the staff channel are the
record of what it saw. The figure stays a proposal until the
baseline has been read, and this page does not say the site meets it.

### Feed

Every launcher reads `version.json` to update, and a new install starts from
it. The outside watcher checks both channels and the launcher each names. The
feed is served by the site, so a site outage is a feed outage.

### Game servers

The game's own traffic is UDP on 7777 (dev 7787), which nothing can connect to,
so the resources port of the same process stands in for it
(`Watch-Services.ps1:The game's own traffic is UDP on 7777`). A hung node process still accepts a connection,
which is why the manifest is asked over HTTP as well (`Watch-Services.ps1:a hung node process still accepts a connection`).
Nothing checks that a person can actually join and load a character.

The load collector, `scripts/vps/Watch-Load.ps1 -Install`, writes one line every
five minutes to `C:\Thornswood-Watch\load.csv` on the box: CPU, memory, free
disk, network, the people on, and each service's processor time, memory and
I/O. `Read-Load.ps1` reads it. Whether the collector is installed on the box
now is not known from here. It sets no threshold: it is the record a box size
decision is made from.

### Voice

Checked like the game servers, on its own port and `/health`. Voice binds to
127.0.0.1 only and reaches people through Caddy (`docs/SERVER.md`, the service
table), so the site being down also takes voice down for everybody.

### Bot

Running is not working: a bot whose process runs but is hung or off Discord
for ten minutes is restarted by its service name, like one whose process is
gone (`Watch-Services.ps1:BotSilent`, `Watch-Services.ps1:$beatStale = 600`). The bot is also the thing that posts the
alerts, which is why the watchdog falls back to the webhook after two and a
half minutes.

### Backups

The nightly backup runs at 08:15 UTC, 2:15 AM by the box's clock in summer and 1:15 AM in winter (`Install-Backup.ps1:$At = '08:15Z'`), 45 minutes before the nightly checks (#3187),
and keeps seven daily and four weekly (`vps-nightly-backup.ps1:$KeepDaily = 7`, `vps-nightly-backup.ps1:$KeepWeekly = 4`). What it
takes is in `docs/SERVER.md`. On One, `Thornswood Fetch Backups` brings each
one down at 4:15 AM, checks each copy opens, and writes the name of the
newest into `offbox.txt` on the box. Since #2755 the watchdog there tells the
staff channel when that copy is over 26 hours old (`Watch-Services.ps1:function OffBoxProblem`);
from #2183 until then the outside watcher on One did.
`local\backups` on One held 14 copies on 12 October, the newest
`thornswood-20261011-152237.zip.enc`. The copy for 7 October arrived on
9 October, so a day One is off is a day the off-box copy falls behind. On
15 October the newest copy on One was `thornswood-20261013-031501`: the fetch
task's last run was 4:15 AM on 13 October (result 0), and nothing had said so.
Judged on the box, it is told while One is off, which is when it falls behind.

The backup's contents are proved every night on stand-in folders by
`tests/test-backup-restore.ps1` in the nightly checks (`.github/workflows/nightly.yml`, which runs every `tests/test-*`
harness at 3:00 AM Mountain).

### RPO

How much can be lost:

- **The box is fine, a folder is damaged:** up to the age of the newest backup
  on the box, at most 26 hours before the watchdog says so (backup freshness).
- **The box is gone:** up to the age of the newest copy on One, which is the
  last 4:15 AM fetch, or older when One was off. The watchdog on the box says
  so past 26 hours.
- During the alpha all world and character data is throwaway
  ([RESTORING.md](RESTORING.md), "The box is gone"), so this is the most that
  can be lost, not a promise that nothing will be.

26 hours for both, the line the watchdog already holds the box to; the
off-box check was added for #2183.

### RTO

How long a restore takes. Measured once, on 28 September
([RESTORING.md](RESTORING.md), "Rehearsing it"): checking a backup 0.8 s,
unpacking it 3.6 s, `Restore-Server.ps1` 14 to 25 s on One and 2.7 to 3.3 s on
the VPS. A restored server has never been started and connected to, and a new
box has never been built from the runbook
([MOVING-THE-SERVER.md](MOVING-THE-SERVER.md)). So the time to bring a server
back is not measured; only the restore step is.

**Proposal:** a restore of one game server folder onto the same box, server
answering again, within one hour; a new box within one day. Both stay
proposals until a rehearsal that starts the server and connects measures them.

**Alert: a monthly rehearsal, overdue after 35 days.** Only a rehearsal
measures this. Patrick ruled on 18 October 2026 (#1046) that the hands-on
restore rehearsal, which starts the restored server and connects to it, runs
monthly ([RESTORING.md](RESTORING.md), "Rehearsing it"). Its record is
RESTORING.md's Last rehearsed line. `scripts/vps/Check-RehearsalDue.ps1` reads
it every night in the nightly checks (`Check-RehearsalDue.ps1:$Days = 35`, a
month with a few days' slack), and once the line is older than that the night
fails, so the board's "Nightly checks failed" issue says the rehearsal is
overdue until one is done and the date written. The proposal above stays a
proposal until the first such rehearsal measures it.

## Availability

`scripts/vps/Read-Availability.ps1` reads `C:\Thornswood-Watch\alerts.jsonl`,
or a copy brought down from the box with `-Path`, and pairs each service's
down and back lines over a window, 28 days unless told otherwise
(`Read-Availability.ps1:$Days = 28`, `Read-Availability.ps1:Get-Outages`). For
each service with an outage in the window it prints the outages, the minutes
down and the share of the window it was up. An outage open at either end of
the window is cut to it. A service with no line in the window is not listed:
no line is no recorded outage, not proof it was up. It only reads, and it
judges nothing against a target. `tests/test-2183-availability.ps1` holds it to
that on made-up lines.

Two limitations, which it prints with every report:

1. The times are the watchdog run that decided, not the moment a thing
   failed or came back. A down line is written only after the check's window
   has passed (one run for a port, two in a row for a health check, five
   minutes a run), so down time is undercounted by up to that window
   (`Read-Availability.ps1:so down time is undercounted by up to that window`).
   A back line comes after two good runs, so an outage's end is late by up to
   a run.
2. Nothing is counted while the watchdog itself is off
   (`Read-Availability.ps1:Nothing is counted while the watchdog itself is off`):
   a box that is down, or a task that is not running, writes no down line, and
   that time reads as up.

## Baseline period

The baseline period is 22 Oct to 19 Nov 2026: the first run of
`Read-Availability.ps1` on the box's `C:\Thornswood-Watch\alerts.jsonl` was
on 22 Oct 2026 at 10:07 AM (Patrick's time), from the Cloud Desk (#2183). It
read 107 lines, the oldest from 21 Oct 11:05 AM, with these outages so far:
the backup once (111.9 minutes), the dev game twice (24.3 minutes), runner 2
twice (20.0 minutes) and the website once (9.4 minutes). The load record from
`Watch-Load.ps1` over the same weeks goes with it, including at least one busy
evening (as `Watch-Load.ps1` itself asks). On 19 Nov the reader, run with
`-From 2026-10-22 -To 2026-11-19`, gives the baseline. Until then every
figure on this page stays as it is.

## What doing nothing costs

The checks and restarts above already run, so doing nothing keeps every alert
and every restart. What it leaves:

- **Restore:** one rehearsal, on 28 September, that stopped before starting
  the server. The monthly rehearsal is scheduled now (the RTO alert above),
  but until one has been done the time to come back stays unknown, and the 28 September rehearsal found three faults that
  would have been found during a real restore instead.
- **Capacity:** the disk warns only once it is under 20%.
  `scripts/vps/Forecast-Storage.ps1` forecasts the day each line is crossed
  and tells the staff channel when the forecast turns, once
  `Forecast-Storage.ps1 -Install` has put its daily task on the box and two
  weeks of samples exist (#2178). Until then it has no history. Without
  `load.csv` read over a week, a bigger box or a split is decided by guess.
- **Off-box backups:** a week of One being off is a week of no off-box copy.
  Since #2183 staff are told once One is back on; while it is off, nobody is.
- **Availability:** the reader exists, but until it is run on the box and the
  four weeks have passed, nobody can say whether the services are more or less
  reliable than last month.

## What is not measured

Each of these needs the box or a person, and none was read for this page:

- The down and back history in `C:\Thornswood-Watch\alerts.jsonl` and
  `watch.log` on the VPS, which is where a first availability figure comes
  from. Anybody with VPS access can read it with `Read-Availability.ps1`.
- Whether `Thornswood Load` is installed and how much of `load.csv` exists.
  `.\scripts\vps\Watch-Load.ps1` with no switches brings it down and reads it.
- Whether `PING_URL` is set in `bot.env.json` and which outside monitor it
  pings. Patrick, who would have made the monitor.
- A restore that starts a server and connects to it (RESTORING.md, "Not done
  yet").
