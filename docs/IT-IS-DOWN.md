# It is down

For the person on their own at 2am. Read top to bottom, stop when it is back.

Everything here is read-only until it says otherwise, and every command says
what it changes. If you are not sure, the answer is further down.

## First: what is actually down

Ask from outside the box, because the box can always reach itself.

```powershell
cd C:\Thornswood-Repo
.\scripts\vps\Check-Site.ps1
```

That answers for the site, the feed and the game server in one go.

| What it says | What is wrong | Go to |
|---|---|---|
| Nothing answers at all, on any port | The box is off or the network is | [The box](#the-box) |
| Pages time out, game server fine | Caddy, which holds 443 | [The site](#the-site) |
| Pages fine, "could not reach the server" | The game server | [The game server](#the-game-server) |
| Everything fine from here | It is one person's machine | [One person](#one-person) |

**The box being up is not the site being up.** `ssh` working proves only the
first. That cost the first round of the 21 September outage.

## The box

```powershell
.\scripts\vps\Setup-SshKey.ps1 -Test
```

`it does, nothing to do` means the box is up and this is a service. If ssh
itself does not answer, the box is off or unreachable and nothing in this file
helps: that is the host's control panel, and the address is in
`docs\MOVING-THE-SERVER.md`. Once port 22 is limited to known addresses
(`scripts\vps\Set-SshScope.ps1`, #2182), a machine whose own address changed
is refused too while everyone else still gets in: run the same check from
another machine in the list before deciding the box is down.

## The site

Caddy holds 443. The site itself answers on loopback 3001 and nobody outside
can reach it directly, so **node being up tells you nothing** about whether
anybody can see the site.

Cloudflare's proxy stands in front of Caddy (#2995), and the box takes 80 and
443 only from Cloudflare's ranges. A Cloudflare error page says which side is
wrong: 521 and 522 are Cloudflare not reaching the box (Caddy down, or the
firewall not taking Cloudflare: `.\scripts\vps\Set-WebFirewall.ps1 -Check`),
525 and 526 are Caddy's certificate (Watch-Services' cert check says when it
runs short). The ssh bridge comes in through Cloudflare too, so while
Cloudflare itself is down the way in is the VNC console in the BisectHosting
panel. The way back from Cloudflare altogether is in this order:
`.\scripts\vps\Set-WebFirewall.ps1 -Open` while ssh still works (or, from
the console, `Set-NetFirewallRule -DisplayName 'Thornswood Web 80','Thornswood Web 443' -RemoteAddress Any`),
then the two records set to DNS only in Cloudflare.

```powershell
ssh Administrator@192.135.112.23 'tasklist /fi "imagename eq caddy.exe"'
```

No `caddy.exe` in that list is the whole answer.

```powershell
ssh Administrator@192.135.112.23 'schtasks /end /tn "Thornswood Web"'
ssh Administrator@192.135.112.23 'schtasks /run /tn "Thornswood Web"'
```

**Both of those change the box.** End first, then run: `schtasks /run` on a
task that is already running prints SUCCESS, does nothing, and reads exactly
like it worked.

Then `.\scripts\vps\Check-Site.ps1` again. The first start after a gap can take a few
seconds while the certificate is sorted out.

Since 21 September the task carries a trigger that repeats every five minutes,
so a stopped Caddy starts itself within five. If it is down and staying down,
that trigger is gone and `scripts\deploy\Setup-Domain.ps1 -TaskOnly` puts it back.

About a hundred half-open connections on 443, most inbound connects failing
and a retransmit share near 20% are not the site going down. They are a
forged SYN flood that used the box as a reflector (#2995). With 443 taking
only Cloudflare the box answers none of it, so FLOOD here means the scope is
off: `.\scripts\vps\Set-WebFirewall.ps1 -Check` says how the rules stand.
This measures it and says FLOOD or QUIET:

```powershell
.\scripts\vps\Remote.ps1 -File .\scripts\vps\vps-syn-flood.ps1
```

## The game server

```powershell
.\scripts\mods\Check-Manifest.ps1
```

If the manifest does not answer, the server process is not running, or it
is running and could not publish the manifest. In that case its log has one
line saying `the load order manifest was NOT published` and why. Nothing
tries again: put that cause right, then restart the server below.

```powershell
.\scripts\vps\Restart-Server.ps1 -Service game
```

**Changes the box.** It refuses while people are in the world unless you pass
`-Now`, which is the right default: a restart with nobody warned is how people
come back to an empty world.

If people ARE in there and it has to go down:

```powershell
.\scripts\vps\Request-Restart.ps1 -Minutes 5 -Mode restart -Why "it has to go down" -ThenRestart
```

**Changes the box.** Counts everybody down in chat, clears the room, then
bounces the process. `-ThenRestart` matters: a kick with no restart behind it
leaves people reconnecting into a world with no NPCs in it.

## The bot

The bot is what tells anybody the site is down, so check it after the site
rather than before.

```powershell
.\scripts\vps\Show-BotLog.ps1
```

`up as Thornswood#...` near the end means it is running. If not:

```powershell
git checkout main
git pull
.\scripts\deploy\Install-Bot.ps1 -CodeOnly
```

**Changes the box.** Sends the code and restarts it. It leaves Python, the
libraries, the token and the service alone. The pull comes first because the
deploy sends what the commit holds, so a folder that has not been pulled
sends the bot as it was before whatever you are putting out.

The log it reads to tell whether the bot came up is
`C:\Thornswood-Bot\data\bot.log`, in the data folder under the bot's folder.
A box with no log there gets an empty one made for it before the restart, so
a missing log is not a failed deploy.

The last thing the run prints is what the box holds at that folder, one
`Test-Path` line per file with its full path, the log included. Those answers
come from the VPS. The same command typed on the machine you ran the deploy
from answers for a folder that machine does not have, and is False whatever
the box holds.

## The voice service

```powershell
curl https://thornswood.net/voice/health
```

`{"ok":true,...}` and it is fine. If not:

```powershell
.\scripts\deploy\Install-Voice.ps1
```

**Changes the box.** For the dev one, add
`-Root C:\Thornswood-Voice-Dev -Port 7789 -TaskName "Thornswood Dev Voice"`.

## One person

Everything answers from here and one person cannot play.

1. Their `Profile\launcher.log`. Every session writes one and it names the
   problem in full, including which plugin and which file.
2. `Scan finished.` in that log now lists what it found, blocking first.
3. A red `LOAD ORDER ERROR` in game is the client and the server disagreeing
   about plugin order: `.\scripts\mods\Check-Manifest.ps1` from their machine says
   whether it is real.
4. Voice one way is a known shape: the page's own column says `hears you` or
   `CANNOT hear you` per person.

## When it is back

Say so in Discord, then write down what it was. Anything found here goes on the
board before the session ends, or the next person at 2am starts from
nothing again.

## What is deliberately not here

- Restoring from backup. That is `docs\RESTORING.md`, it takes longer than this
  file's problems, and it has never been rehearsed.
- Anything that needs a secret. If a step wants a token or a password, stop:
  they live in the owner's password manager and on the box, never in the repo
  and never in a command line.
