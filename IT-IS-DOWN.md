# It is down

For the person on their own at 2am. Read top to bottom, stop when it is back.

Everything here is read-only until it says otherwise, and every command says
what it changes. If you are not sure, the answer is further down.

## First: what is actually down

Ask from outside the box, because the box can always reach itself.

```powershell
cd C:\Users\evilp\Downloads\Thornswood-Repo
.\tools\Check-Site.ps1
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
.\tools\Setup-SshKey.ps1 -Test
```

`it does, nothing to do` means the box is up and this is a service. If ssh
itself does not answer, the box is off or unreachable and nothing in this file
helps: that is the host's control panel, and the address is in
`tools\MOVING-THE-SERVER.md`.

## The site

Caddy holds 443. The site itself answers on loopback 3001 and nobody outside
can reach it directly, so **node being up tells you nothing** about whether
anybody can see the site.

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

Then `.\tools\Check-Site.ps1` again. The first start after a gap can take a few
seconds while the certificate is sorted out.

Since 21 September the task carries a trigger that repeats every five minutes,
so a stopped Caddy starts itself within five. If it is down and staying down,
that trigger is gone and `tools\Setup-Domain.ps1 -TaskOnly` puts it back.

## The game server

```powershell
.\tools\Check-Manifest.ps1
```

If the manifest does not answer, the server process is not running.

```powershell
.\tools\Restart-Server.ps1 -Service game
```

**Changes the box.** It refuses while people are in the world unless you pass
`-Now`, which is the right default: a restart with nobody warned is how people
come back to an empty world.

If people ARE in there and it has to go down:

```powershell
.\tools\Request-Restart.ps1 -Minutes 5 -Mode restart -Why "it has to go down" -ThenRestart
```

**Changes the box.** Counts everybody down in chat, clears the room, then
bounces the process. `-ThenRestart` matters: a kick with no restart behind it
leaves people reconnecting into a world with no NPCs in it.

## The bot

The bot is what tells anybody the site is down, so check it after the site
rather than before.

```powershell
.\tools\Show-BotLog.ps1
```

`up as Thornswood#...` near the end means it is running. If not:

```powershell
.\tools\Install-Bot.ps1 -CodeOnly
```

**Changes the box.** Sends the code and restarts it. It leaves Python, the
libraries, the token and the task alone.

## The voice service

```powershell
curl https://thornswood.net/voice/health
```

`{"ok":true,...}` and it is fine. If not:

```powershell
.\tools\Install-Voice.ps1
```

**Changes the box.** For the dev one, add
`-Root C:\Thornswood-Voice-Dev -Port 7789 -TaskName "Thornswood Dev Voice"`.

## One person

Everything answers from here and one person cannot play.

1. Their `Profile\launcher.log`. Every session writes one and it names the
   problem in full, including which plugin and which file.
2. `Scan finished.` in that log now lists what it found, blocking first.
3. A red `LOAD ORDER ERROR` in game is the client and the server disagreeing
   about plugin order: `.\tools\Check-Manifest.ps1` from their machine says
   whether it is real.
4. Voice one way is a known shape: the page's own column says `hears you` or
   `CANNOT hear you` per person.

## When it is back

Say so in Discord, then write down what it was. Anything found here goes on the
To Do List before the session ends, or the next person at 2am starts from
nothing again.

## What is deliberately not here

- Restoring from backup. That is `tools\RESTORING.md`, it takes longer than this
  file's problems, and it has never been rehearsed.
- Anything that needs a secret. If a step wants a token or a password, stop:
  they live in the owner's password manager and on the box, never in the repo
  and never in a command line.
