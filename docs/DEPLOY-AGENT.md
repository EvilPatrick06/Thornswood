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

It looks after the **dev server only** and applies **the gamemode only**.

| Part | Today |
| --- | --- |
| Dev gamemode | Applied by the agent: a merge that changes `game/gamemode.js` makes a signed Release and a Deployment, and the agent reloads the dev server's gamemode with nobody dropped. The gate's `Deploy-Release` verb puts in any such Release by its tag. |
| Dev plugins, settings, engine | Not yet. These need the server stopped and its files swapped, with a watchdog hold (#5155). Deploy-DevGamemode, Publish-Server and Ship still do them. |
| Main | Not yet. Main waits on a Main environment that only Patrick can approve (#5181). The agent refuses any environment but dev. |
| Bot, site | Not yet. Their own slices. |
| Launcher and game files | Not the agent's job: they reach people through the launcher's feed and a Ship. The release workflow (#5179) moves them onto Releases. |
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

1. A pull request that changes `game/gamemode.js` merges to main.
2. [gamemode-release.yml](../.github/workflows/gamemode-release.yml) runs on
   GitHub's Windows runner in the `release` environment (main only). It
   stamps the gamemode (`thornswood-build.json`, BuildStamp.ps1), writes a
   manifest listing both files with their sha256
   ([New-SignedManifest.ps1](../scripts/release/New-SignedManifest.ps1)),
   makes a catalog over the manifest and signs it with ThornswoodRelease
   ([Sign-OnRunner.ps1](../scripts/release/Sign-OnRunner.ps1)), then
   publishes the Release `build-<date>.<run>` from a draft (Releases here
   are immutable once published) and makes a Deployment to the environment
   **Dev server** naming it.
3. Within a minute the agent sees the Deployment, marks it in progress, and
   downloads `manifest.json` and `manifest.cat`. The catalog has to pass
   `launcher\app\Signature.cs`, the same check every installed launcher
   holds an update to, and `Test-FileCatalog` has to say it covers the
   manifest. Then each file is downloaded and held to the manifest's size
   and sha256, and the manifest's commit has to be the Deployment's commit.
4. The agent takes the server folders' turn, keeps the running
   `gamemode.js`, `thornswood-build.json`, `server-settings.json` and the
   deploy record in `.prev-<stamp>`, and moves the new stamp and then the new
   gamemode in, one rename each.
5. `server.log` has to say the new gamemode's git blob loaded (the reload
   Reload.ps1 uses, #3196), and then the health address has to answer.
6. If either does not happen, the old files go back the same way and the
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
   `gamemode.js` and stamp, and dev's data folder without its plugins and
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
   checks, a line each: **loads**, **login**, **new** (the race menu is
   open), **face** (a face is sent, the race menu closes and the plain
   clothes arrive), **saved** (the world on disk holds the character by
   name), **restart** (the copy is stopped and started again and loads
   again) and **loads back** (a second bot logs in as the same profile and
   gets the same character, where it was saved, with no race menu).
5. Every line goes in the Deployment's log. All PASS and the gamemode goes
   in as below. One FAIL, a pass that does not end within 30 minutes
   (`botPassSeconds`), or no result, and the Deployment says **failure**
   with the step and why, and dev is not touched. The copy is left until the
   next pass, with its own server log at
   `C:\Thornswood-BotPass\run\server\bot-pass-server.log`;
   `Install-DeployAgent -Status` prints the last pass.

The bot pass rides in the gamemode Release as a part of its own, `bot`
(gamemode-release.yml, `New-SignedManifest.ps1 -BotFiles`), so the bot that
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

## Why "Dev server" and not "Dev"

Deployments to **Dev** and **Main** already exist. `release-files.yml` writes
one with `Record-Deployment.ps1` after each release goes out, as a record,
with a success status straight away. The agent's Deployments say what should
run, which is a different meaning, so they use their own environment until
the release workflow (#5179) makes one Deployment carry both meanings and
`Record-Deployment.ps1` goes in the same pull request.

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
looks for a newer one. It holds the new program to its manifest and to its
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
takes the newest `agent-v` Release, holds it to the same checks on the box
before anything is stopped, makes the service `ThornswoodDeployAgent`
(started after boot, started again after an error exit, three times a day at
most), starts it, and prints the agent's own check. To see it afterwards:

```
pwsh scripts/vps/Box-Run.ps1 -Line 'Install-DeployAgent -Status'
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
  the turn, the App token and what it asks for, and the config.
  `dotnet test tools/DeployAgent.Tests` runs them.
- `tests/test-5180-deploy-agent.ps1` checks the manifest script, both gate
  verbs, the scripts they send the box, and both workflows, and runs the C#
  tests when the .NET SDK is on the machine.
