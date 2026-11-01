# The box deploy agent

Issue #5180. A small Windows service on the box that asks GitHub, on its
own, whether a Deployment is waiting for a server it looks after, puts in
that Deployment's signed Release, checks the server is healthy, and says how
it went on the Deployment. It only ever calls out. Nothing on the box
listens for it, and nobody reaches into the box to run it.

The code is in [tools/DeployAgent/](../tools/DeployAgent/), in C# on .NET 10
(Patrick, 31 Oct 2026: the release and box tools share code with the new
launcher, #4823). It ships as one signed, self-contained program, so the box
needs no .NET installed. Its tests are in
[tools/DeployAgent.Tests/](../tools/DeployAgent.Tests/).

It does two jobs with the same code:

- **Deploy one Release by its tag**, for the deploy gate's `Deploy-Release`
  verb. This came first (Patrick, 31 Oct 2026). A rollback is this with the
  Release before.
- **Apply each new Deployment by itself**, as the Windows service. Dev first.

## What this first slice does, and what it does not

It looks after the **dev server only** and applies **the gamemode and the
server build** (the engine).

| Part | Today |
| --- | --- |
| Dev gamemode | Applied by the agent: a merge that changes `game/gamemode.js` makes a signed Release and a Deployment, and the agent reloads the dev server's gamemode with nobody dropped. The gate's `Deploy-Release` verb puts in any such Release by its tag. |
| Dev engine (the server build) | Applied by the agent (#5219): every Release carries the server build its commit records, and when dev runs another one the agent stops dev, swaps in the build and the gamemode together and starts it under a hold. So a merged engine pin reaches dev with no Publish-Server and no Deploy-DevGamemode. See "A new server build" below. |
| Dev plugins, settings | Not yet. Like the engine they need a stop and a swap under a hold, but nothing puts them on a Release yet. Deploy-DevGamemode and Ship still do them. |
| Main | Not yet. Main waits on a Main environment that only Patrick can approve (#5181). The agent refuses any environment but dev. |
| Site, Discord bot | Applied by the agent (#5190, #5187): a merge that changes either makes a Deployment to **Site** or **Discord bot** with the Release's `site.zip` or `discord.zip`, and the agent swaps it in the way Deploy-Docs and Install-Bot -CodeOnly do. See "The site, the Discord bot and voice" below. |
| Dev voice | Applied with dev's Deployment (#5187): voice has no Deployment of its own, because the gamemode pushes positions to it. |
| Release news | After a Deployment goes in, the agent leaves its Release's notes for the bot, which posts them once (#5187). See "Release news" below. |
| Launcher and game files | Not the agent's job: they reach people through the launcher's feed and a Ship. Since #5179 every Release carries them as well (the signed launcher, the game files and the Velopack packages of both), attested, for the launcher's move to Velopack; the agent logs them as left alone. |
| Bot pass before each dev Deployment | Once `Install-DeployAgent` has set up its task, every Deployment waits on a bot pass on a throwaway copy of dev with the new gamemode (#5196, below). A FAIL fails the Deployment and dev keeps what it runs. A deploy by tag (the gate's `Deploy-Release`, a rollback) does not wait on one. |
| Parity check after a deploy | Not yet. The agent is to run `Check-ProdParity.ps1` after each deploy and file what differs as an issue, never putting it back by itself. That needs the parity scripts on the box from a signed Release, and the App to hold Issues write; until then the `Check-ProdParity` gate verb runs it. |

The old way keeps working beside the agent until the agent has proved itself
on dev. Both take the server folders' turn (#3247), so they never put files
in at the same time, and the agent's put-back folder has the same shape as
Deploy-DevGamemode's, so `Deploy-DevGamemode.ps1 -PutBack` puts back what
the agent put in.

## Deploying a Release by its tag, and rolling back

```
pwsh scripts/vps/Box-Run.ps1 -Line 'Deploy-Release -Tag build-20261101.12'
```

That is the gate verb for
[Deploy-Release.ps1](../scripts/deploy/Deploy-Release.ps1). It runs
`thornswood-agent.exe deploy --environment dev --tag <tag>` on the box, which
does steps 3 to 7 below with no Deployment to report on, and prints the
address of the log. The tags are on the
repository's Releases page as `build-<date>.<run>`. To roll dev back, deploy the tag before the one that
is on it now; the box's deploy record says which one that is
(`http://play.thornswood.net:7788/thornswood-deploy.json`).

A deploy by tag asks the App for **Contents: read** only, so it works before
the App holds Deployments.

## How a change reaches dev

1. A pull request that changes `game/`, `launcher/`, the bot pass or a
   record (`records/server-build.json` is an engine pin) merges to main.
2. [merge-release.yml](../.github/workflows/merge-release.yml) runs on
   GitHub's Windows runner in the `release` environment (main only). It
   builds or carries the signed launcher, builds the game files over dev's
   last release (Build-GameFiles.ps1), fetches CI's build of the pin, held to the records
   (Get-EngineArtifact.ps1, the server zip ServerArtifact.ps1 makes),
   stamps the gamemode (`thornswood-build.json`, BuildStamp.ps1), writes a
   manifest listing the gamemode, its stamp, the server zip and the record
   inside it, each with its sha256
   ([New-SignedManifest.ps1](../scripts/release/New-SignedManifest.ps1)),
   makes a catalog over the manifest and signs it with ThornswoodRelease
   ([Sign-OnRunner.ps1](../scripts/release/Sign-OnRunner.ps1)), then
   publishes the Release `build-<date>.<run>` from a draft (Releases here
   are immutable once published) and makes a Deployment to the environment
   **Dev** naming it. A merge that changed none of the parts publishes
   nothing; the workflow's header says how a change is told.
3. Within a minute the agent sees the Deployment, marks it in progress, and
   downloads `manifest.json` and `manifest.cat`. The catalog has to pass
   `launcher\app\Signature.cs`, the same check every installed launcher
   holds an update to, and `Test-FileCatalog` has to say it covers the
   manifest. Then each file is downloaded and held to the manifest's size
   and sha256, and the manifest's commit has to be the Deployment's commit.
   The server zip is downloaded only when dev runs another server build than
   the Release's record names (read from dev's `server-build.json`, each CR
   LF read as LF, the way the deploy scripts compare records); then the
   steps are the ones under "A new server build" instead of 4 to 6.
4. The agent takes the server folders' turn, keeps the running
   `gamemode.js`, `thornswood-build.json`, `server-settings.json`, the
   deploy record and the `gamemode-tables` folder in `.prev-<stamp>`, and
   moves the new tables folder, then the new stamp, then the new gamemode in,
   one rename each. The tables are the files game/gamemode-tables/<NAME>.json
   the gamemode reads as it loads (#5191), carried in the Release as
   `gamemode-tables.zip` and held to the manifest like the other files; a
   Release without that zip leaves the folder as it is.
5. `server.log` has to say the new gamemode's git blob loaded, and the git
   tree id of its tables folder too when that gamemode reads tables (it
   carries the line that logs them; one from before #5191 does not, whatever
   folder is beside it) (the reload Reload.ps1 uses, #3196), and then the
   health address has to answer.
6. If either does not happen, the old files go back, the tables folder first
   so the reload the old gamemode.js starts reads the old tables, and the
   old gamemode has to load again. The Deployment says **failure** and that
   the previous gamemode is back. If even that does not take, it says
   **error**, and dev needs `Deploy-DevGamemode.ps1 -PutBack`.
7. On success the agent writes the deploy record
   (`thornswood-deploy.json`, the same shape the deploy scripts write), and
   the Deployment says **success**. A success marks the Deployment before it
   inactive.

Every Deployment's log is left in the dev server's data folder as
`deploy-<id>.log` (`deploy-<tag>-<stamp>.log` for a deploy by tag), the
newest ten. The status's log link points there:
`http://play.thornswood.net:7788/deploy-<id>.log`. Network addresses in
server log lines are taken out before they go in.

## A new server build

When dev runs another server build than the Release records, the agent puts
the build and the gamemode in together, the way Swap.ps1 swaps a server:

1. The stage, while dev still runs: every fork file out of the zip into
   `.agent-stage-<stamp>`, held to the record by sha256 and commit
   (ServerBuild.ps1's rules, ported to `ServerBuild.cs`), the zip's own
   record the one the signed manifest names, and the new engine one that
   says how a gamemode load went (#3196). A refusal here touches nothing.
2. The server folders' turn (#3247), and a hold on the task `Thornswood Dev
   Server` in `C:\Thornswood-Watch\holds` (#5155, the file ServerHold.ps1
   writes), so neither the nightly backup nor the watchdog steps in.
3. The stop: the process holding dev's own UDP port and nothing else, waited
   for until it has exited, and a `restart.json` it never read removed.
4. One rename per file. What each replaces goes to `.prev-<stamp>`, and so
   does any fork file the new record does not list, so the folder holds one
   build. The `gamemode-tables` folder, when the Release carries it, goes
   aside and in whole, and step 5 waits for its tree id as well.
5. The start, then both ports from the box (UDP, and the resources port
   taking a connection) within 170 seconds (ServerReadyWait.ps1's wait),
   then `server.log` saying the new gamemode's git blob loaded, then the
   health address.
6. If any of that fails: the stop again, the new files out, the old ones in,
   the old server started and asked the same way. The Deployment says
   **failure** and that the previous server build is back and answering. If
   even that does not take it says **error**, keeps `.prev-<stamp>`, and dev
   needs `Publish-Server -PutBack`.
7. The hold is taken away on every way out.

Anybody on dev is dropped for the minute or two of the restart, as with
Publish-Server. Deploying an older tag by the gate verb swaps its server
build back in the same way.

When several Deployments are waiting, only the newest is applied, and the
older ones are marked inactive. The newest is the state dev should be in, and
putting in the ones before it first would only put in what is about to be
replaced.

## The bot pass before each dev Deployment

Issue #5196. Between holding the Release to its signature (step 3 above)
and putting the gamemode in (step 4), the agent checks the new gamemode on
a copy of dev that nobody plays on:

1. It takes the server folders' turn and makes the copy in
   `C:\Thornswood-BotPass\run\server`: dev's engine (`dist_back`,
   `scam_native.node`, `package.json`, any DLL beside it), the Release's
   `gamemode.js` and stamp, the `gamemode-tables` folder the gamemode reads
   (the Release's `gamemode-tables.zip`, or dev's own folder when the
   Release carries none, #5191), and dev's data folder without its plugins and
   archives. Those are read where the bot pass keeps them,
   `C:\Thornswood-BotPass\plugins`, copied from dev's only when one
   changes, by their full paths. Dev's world, its `private` folder (the
   door and the join pass key), its logs and deploy records never go in. The
   world starts empty.
2. The copy's settings are dev's with what reaches outside taken out
   (`discordAuth`, `metricsAuth`, `masterKey`, `additionalServerSettings`):
   no master server, offline login, no join pass hold, a password of its
   own, the name with " (bot pass)" on the end, and a game port from 7900
   that no server's settings name and nothing holds now, with its
   resources port beside it and a voice port above.
3. It starts the task **Thornswood Bot Pass**, which runs
   [Bot-Pass.js](../scripts/bot/Bot-Pass.js) from the same Release. The
   task runs as LOCAL SERVICE, Limited, with a SID of its own and rights in
   `C:\Thornswood-BotPass` only, at below normal priority, the way the game
   servers run (ServiceAccount.ps1). The agent never runs node or loads the
   engine itself; it reads the result the task writes.
4. Bot-Pass.js starts the copy, waits for it to say this gamemode loaded,
   and has a bot log in the way the game does as a profile nobody has. It
   checks, a line each: **loads**, **login**, **new** (the character comes
   with the race menu open and creation already open, at the face),
   **face** (a face is sent and creation moves on to choosing a home),
   **saved** (the world on disk holds the character by name), **restart**
   (the copy is stopped and started again and loads again) and **loads
   back** (a second bot logs in as the same profile and gets the same
   character, where it was saved, with no race menu). A FAIL at new, face
   or saved ends with what the gamemode's creation said about the bot.
5. Every line goes in the Deployment's log. All PASS and the gamemode goes
   in as below. One FAIL, a pass that does not end within 30 minutes
   (`botPassSeconds`), or no result, and the Deployment says **failure**
   with the step and why, and dev is not touched. The copy is left until the
   next pass, with its own server log at
   `C:\Thornswood-BotPass\run\server\bot-pass-server.log`;
   `Install-DeployAgent -Status` prints the last pass.

The bot pass rides in the gamemode Release as a part of its own, `bot`
(merge-release.yml, `New-SignedManifest.ps1 -BotFiles`), so the bot that
checks a gamemode comes from the same commit and is signed with it. A change
to the bot alone makes a Release too.

Setting it up is part of `Install-DeployAgent`, once dev's engine has the
bot client (`createBotClient`, skymp fork #137; the install checks and
says so). The fail-safe on what no service may read comes first, the task is registered on LOCAL SERVICE and
given its folder, and only then does `agent.json` name the folder
(`botPassRoot`). It is never put on SYSTEM: when any of that cannot be
done, the install says `BOT PASS NOT SET UP` and why, and Deployments go in
without a pass, each log saying so.
`pwsh scripts/vps/Box-Run.ps1 -Line 'Install-DeployAgent -NoBotPass'` takes
it off.

What the bot cannot reach yet: stations, claims and keys, needs, merchants
and jail go over the voice relay, which the copy does not start, so they
wait on a relay client for the bot (#5196).

## The site, the Discord bot and voice

Each is one zip on the Release, made by
[App-Part.ps1](../scripts/release/App-Part.ps1) the same way every time, so
the same files give the same bytes and a merge that does not touch one does
not count as a change to it. The agent (`tools/DeployAgent/App.cs`) puts one
in with the same halves as Swap.ps1's service swap:

1. The zip is opened into `<root>\.agent-stage-<stamp>` while the app runs.
   Every entry has to be a plain path to one of the files a Release may carry
   (the site: `server.js`, `public\*`, `data\site\*`; the bot: its code and
   `assets\*`, never anything `Get-ThornswoodBotOwned` names; voice:
   `voice-server.js`, `headlines.js`, `server-log.js`). Only the files that
   differ are kept, the programs are parsed and the JSON read. A bot whose
   `requirements.txt` changed gets its libraries installed into the stage,
   held to their hashes. A refusal here touches nothing.
2. Under a hold (#5155) the app is stopped and waited for, each new file is
   moved in, and what it replaces goes to `<root>\.prev-<stamp>`, so
   `Deploy-Docs.ps1 -PutBack`, `Install-Bot.ps1 -PutBack` and
   `Install-Voice.ps1 -PutBack` put back what the agent put in. The site's
   public files the Release no longer has, and anything in the bot's folder
   that is not the bot's own, go aside too.
3. It is started and has to answer: the site's front page under 500, the bot
   saying in its log that it is watching its server, and voice's `/health`,
   asked on the box, naming the `BUILD` of the `voice-server.js` in its
   folder, so an old copy still on the port is not taken for the new one.
4. When it does not, everything goes back and it is started on the old files.

Voice goes in with dev's Deployment, after the bot pass and before the
gamemode, and a voice that does not answer fails the Deployment with the
gamemode untouched. `Install-DeployAgent` names each one only where its full
install has set it up (the task `Thornswood Docs`, the service
`ThornswoodBot`, the task `Thornswood Dev Voice`). The site's and the bot's
Deployment logs go in the dev server's data folder beside dev's. The gate's
`Deploy-Release -Environment site` or `discord` rolls either back by tag.

## Release news

Once a Deployment's success is on GitHub, the agent reads its Release again
and writes the tag, name and notes to
`C:\Thornswood-Deploys\for-bot\news-<environment>.json`, a folder only
SYSTEM, Administrators and the bot's account read. The bot
(`watch_release_news` in `bot/bot.py`) posts each tag once: a merge's release
in the dev updates channel, a main release in #news, each by its id. A release
whose notes start "Nothing people would notice" (merge-release.yml's line for
a merge whose pull requests say none), and one deployed over a day ago, are
written down without a post. A rollback by tag is not news and leaves none.

## Why "Dev"

Until #5179, `release-files.yml` wrote a Deployment to **Dev** or **Main**
with `Record-Deployment.ps1` after each release went out, as a record with a
success straight away, and the agent's Deployments used an environment of
their own, **Dev server**. The merge release now makes the one Deployment to
**Dev**: it says what dev should run, and the agent's status on it says
whether it does. `Record-Deployment.ps1` went in the same pull request. The
old records in **Dev** all carry a success, so the agent never applies them;
the old **Dev server** Deployments are history. **Main** gets the same
Release deployed after Patrick's Approve click (#5181).

## What it holds and what it can do

- It runs as **LocalSystem**, the account the deploy gate's broker runs as.
  It replaces files in the dev server's folder, takes the server folders'
  turn, and reads the box admin App's key, which only SYSTEM,
  Administrators and the admin service can read.
- From that key it mints its own GitHub token for each hour, asking only for
  **Deployments: write** and **Contents: read** on this repository (Contents:
  read alone for a deploy by tag). The token lives in memory only. The
  repository is the one the box's checkout came from, written into
  `agent.json` by the installer, so nothing names an account and the move to
  an organization (#5184) needs no change here. The App has to hold Deployments first: an owner adds
  **Deployments: Read and write** on the App's permissions page and accepts
  it on the installation. Until then every pass says GitHub gave it no token,
  and nothing is applied.
- Its folder, `C:\Thornswood-Agent`, takes nothing from `C:\`: SYSTEM and
  Administrators only. `records\runner-isolation.json` keeps every runner
  account out of it.
- It trusts a Release only when the signature passes the launcher's own
  check for the signer `launcher\app\Updater.cs` names. `Signature.cs` is
  compiled into the agent from where it lives in the launcher, so there is
  one copy, and the workflow builds the signer's name in.

## How it updates itself

[deploy-agent.yml](../.github/workflows/deploy-agent.yml) tests the agent on
every pull request that touches it, on Linux and on Windows. On main it builds
the program with the version `1.0.<run>`, signs it, writes and signs its manifest the same way,
and publishes the Release `agent-v<version>`. Every 15 minutes the agent
looks for a newer one among all the `agent-v` tags and fetches its Release by
the tag. It never reads GitHub's list of Releases for this: that list is one
page in GitHub's own order (a Release's date is its commit's), so a new agent
can sit far down it. It holds the new program to its manifest and to its
own signature, renames itself aside (Windows lets a running program be
renamed), moves the new one in, and ends with code 3. The service manager
starts the new program, which removes the old one.

## Putting it on the box

Once, after its first Release is out:

```
pwsh scripts/vps/Box-Run.ps1 -Line 'Install-DeployAgent'
```

That is the gate verb for
[Install-DeployAgent.ps1](../scripts/deploy/Install-DeployAgent.ps1). It
takes the Release of the newest `agent-v` tag, found the same way, holds it to the same checks on the box
before anything is stopped, makes the service `ThornswoodDeployAgent`
(started after boot, started again after an error exit, three times a day at
most), starts it, and prints the agent's own check. To see it afterwards:

```
pwsh scripts/vps/Box-Run.ps1 -Line 'Install-DeployAgent -Status'
```

A service stuck stopping (`StopPending`) makes the install refuse and change
nothing. Agents up to 1.0.21 got there at their first self-update: the work
called `Stop()` from inside itself, and the stop waited for that same work,
so it never ended (1 Nov). The agent now ends its work first and stops from
outside it. A process stuck that way can only be ended, which this does
once, before the new agent goes in:

```
pwsh scripts/vps/Box-Run.ps1 -Line 'Install-DeployAgent -EndHung'
```

On the box itself, `thornswood-agent.exe check` says whether the App gives a
token, what the newest Deployment says, and whether the dev server answers.

## Tests

- `tools/DeployAgent.Tests` runs the agent against a stand-in GitHub, a
  stand-in signer and a stand-in game server whose engine reloads the
  gamemode and writes `server.log` lines the way the real one does: success,
  a deploy by tag and a rollback to the Release before, a gamemode that does
  not load, a failed health check, each refusal, only the newest Deployment
  applied, a Deployment cut short, the self-update, the git blob, a log roll,
  a new server build swapped in under a hold, the same build not fetched,
  a new engine that does not start and a gamemode that does not load on it
  both put back with the old build started, and a server build refused
  before anything stops,
  the turn, the App token and what it asks for, and the config; and for the
  site, the bot and voice: a swap with what left, an unchanged app not
  stopped, a put back, each refusal, a stop that leaves a process, the bot's
  libraries, voice answering with the old build, the news left after a
  Deployment and not after a failure or a rollback, and two swaps in one
  second.
  `dotnet test tools/DeployAgent.Tests` runs them.
- `tests/test-5180-deploy-agent.ps1` checks the manifest script, both gate
  verbs, the scripts they send the box, and both workflows, and runs the C#
  tests when the .NET SDK is on the machine.
