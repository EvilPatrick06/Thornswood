# Working in this repo

Read this first, every session, whoever you are working with. It is the same
for Patrick's machine and Djinn's. SECOND-DEVELOPER.md is the long form: what
the pieces are, how a release goes out, how a machine is set up.

## What this is

Thornswood: a modded co-op Skyrim roleplay server on SkyMP, in closed
playtest. This repo is the launcher (tools\app, C# 5, WPF, built with the
.NET Framework 4 csc), the game plugins (tools\ts-plugins, Skyrim Platform
JavaScript), the site (tools\docs-app, node), the Discord bot (tools\discord,
Python) and every script that ships or runs it. Owner: Patrick (EvilPatrick06).
Second developer: Djinn (Windows account Ken, Discord WiccanDjinn).

## Words

The people in the world are customers, clients, people, testers, partners.
Never "player". No em dashes anywhere written for people. Plain, direct
sentences, no filler, no placeholders. Secrets (server passwords, site keys,
Discord tokens, the news webhook, anything out of a config.json or .env on the
VPS) are named by location only; never printed, pasted, committed or logged.

## Everything we need to do goes on the To Do List

The Thornswood To Do List is the one record of outstanding work:
https://claude.ai/artifact/DEaM2aKgAp3RYQnbox4WqY

Decided by Patrick on 17 Sep. Anything a session turns up goes on it before the
session ends. A defect, a decision, a correction to something already on there,
or work started and not finished. Saying it in a reply is not recording it: a
reply is gone when the window closes and the next person has no way to know it
was ever found. What prompted this was a Google Ads tag added to the site whose
only trace was a paragraph on a neighbouring entry, with no step telling anybody
to deploy it.

The number is the do-order, so a new entry goes where it belongs in that order
and not on the end. Work that fits an existing entry updates that entry rather
than making a second one. Write down what was measured and what is left.
Uncommitted changes sitting in the repo are outstanding work and belong on it
too. Say in the reply which entries moved.

## Settled design, not up for a quiet rewrite

- Decided by Patrick and Djinn on 17 Sep, after the three launchers kept
  getting into each other's files: Thornswood runs from its own game folder
  (`Thornswood\Game`), built by the launcher from what Vortex has deployed
  into the Steam copy, the big files as hard links so the collection is not
  stored twice, and copies of everything another launcher rewrites in place
  (settings, scripts, programs, the client folders, the master files and
  whatever Keizaal is known to replace). Keizaal and Daedric get their own
  folders the same way (`tools\New-GameFolder.ps1`).
  This is what ships now, corrected 18 Sep. The bullet used to say the Steam
  copy shipped until `djinn/own-game-folder` reached main. That branch is on
  main, `C:\Thornswood\Game` is built, and the launcher restarts into it:
  Profile\launcher.log records "runs from the new folder". A session reading
  the old wording would have believed the wrong layout was live, which is the
  one thing this section exists to prevent.
- Whichever folder the game runs from, the launcher handles sharing on its
  own: Keep puts its files back before Play and parks other servers'
  plugins; Hold keeps its files open read only while the game runs; the
  plugins idle unless the client points at our server and a fresh session
  note is there; Publish-Update keeps other servers' files out of packs
  (Ship-Rules.ps1). No wrapper scripts around the launcher, nothing moved by
  hand in Data\Platform, nothing touches Vortex's own files.
- The SkyMP client bundle (skymp5-client.js) is not built here; the copy in
  the game folder is patched by Patch-Client.ps1 and shipped as is.
- Launcher code is C# 5 only: no string interpolation, no ?., no nameof,
  no expression bodied members, no out var.
- Every change goes out as one complete release: launcher, game files and
  server together, never a half.

Anything that changes one of these is a few lines in #dev first: the
problem, the approach, what it touches. Agreed between Patrick and Djinn
before code; a Claude does not settle it for them.

## How work moves between the two machines

- main is what ships. Only Patrick's machine ships main, and Ship.ps1 refuses
  a main release that is not on main or is behind origin. A main Ship
  commits and pushes the source when the release is out, so the other
  machine can `git pull` exactly what shipped.
- Decided by Patrick on 18 Sep: his own work goes straight to main. Small
  commits, plain messages saying what changed, pushed to main. No branch and
  no pull request for it. He owns the repo and ships it, and main requires an
  approving review that he cannot give himself, so every one of his own pull
  requests sat blocked until he overrode it with `--admin`. This makes the
  real practice the written one.
- Djinn's work still goes on a branch: `git checkout -b djinn/what-it-is`.
  Small commits, plain messages. Push the branch and open a pull request
  (`gh pr create --fill`). Patrick reads it; it is merged into main from
  GitHub, never pushed over main.
  The branches opened before 17 Sep use a `gavin/` prefix; they are the same
  person and were left alone rather than renamed under open pull requests.
- One fix per commit either way. Going straight to main is not permission to
  put eight unrelated things in one push, and the reason is the same: a commit
  that changes eight things cannot be reverted when one of them is wrong.
- `git pull` before starting anything. If a pull conflicts, resolve it on
  your branch (`git fetch`, `git rebase origin/main`), never on main. If a
  push is rejected, pull, do not force.
- The dev channel (`.\tools\Ship.ps1 -Channel dev "what changed"`) may be
  run from any branch, from either machine, to try work on the dev server.
  Say in #dev when you take it, because there is one dev feed and the last
  dev Ship wins. A main Ship resets it.
- One fix per pull request. A branch that changes eight things is eight
  reviews nobody has time for; split it.
- Every pull request gets a build check on GitHub (.github/workflows/build.yml:
  the scripts parse, the launcher compiles with the .NET Framework csc). Red
  means the branch would stop Ship at the build step; fix that before asking
  for a read.
- Do not edit Shell.cs, Checks.cs, Keep.cs, Hold.cs, Updater.cs or
  Publish-Update.ps1 without a line in #dev first; both machines touch those.

## After a pull request is merged

Merging on GitHub changes nothing anybody sees. Patrick runs the rest on his
machine, from the repo folder. A Claude shows him the commands and does not
run them.

1. `git checkout main`, then `git pull`. Ship.ps1 refuses a main release
   that is behind origin, so the pull comes first.
2. Then one command for each part the pull request touched:
   - The launcher (`tools\app`, `tools\ui.xaml`, the art and video that
     Build-Launcher.ps1 embeds), the game plugins (`tools\ts-plugins`), or
     anything else that goes out in a pack: `.\tools\Ship.ps1 "what changed"`.
   - The site's app or `tools\docs-app\public`: `.\tools\Deploy-Docs.ps1`.
     The public pages (`tools\docs-app\data\site\*.md`) need
     `.\tools\Deploy-Docs.ps1 -Site`.
   - The bot's code or join card art in `tools\discord`:
     `.\tools\Install-Bot.ps1 -CodeOnly`.
   - The bot's avatar (`tools\discord\thornswood-bot-*.png`): no script
     sends it. It is uploaded by hand in the Discord developer portal.
   - `tools\gamemode.js`: `.\tools\Deploy-Gamemode.ps1`, then
     `.\tools\Deploy-Server.ps1`.
   - The voice service (`tools\voice\voice-server.js`, `tools\voice\public`):
     `.\tools\Install-Voice.ps1`.
   - Only scripts that run on Patrick's machine (Ship.ps1, Publish-Update.ps1,
     the Deploy scripts): nothing more. The pull is the change.
   A pull request that touches several of these gets every one of them, in
   the same sitting, so nothing goes out half done.
3. Djinn, once it is out, from the main folder: `git checkout main`, then
   `git pull`. If the branch had its own folder, `git worktree remove
   ..\<that folder>`. Then `git branch -D djinn/what-it-is`, after GitHub
   shows the pull request as merged; GitHub squashes the merge, so
   `git branch -d` refuses. A file the branch added that also sits untracked
   in the main folder stops the pull, so delete that copy first.

## What a Claude here does itself and what the person does

Read anything. Run git status, diff, log, fetch, the read only scripts
(Why-Keizaal.ps1, Check-*.ps1, Setup-SshKey.ps1 -Test), and compile checks.
Edit source on a branch when asked. The person runs what leaves the machine:
Ship.ps1, git push, gh pr create, and every script that talks to the VPS
(Deploy-*, Request-Restart, Install-Bot, Rotate-ServerPassword, Publish-*).
Show the command; let them run it. Never start the launcher or the game.
Measure before claiming a cause: read Profile\launcher.log, look at the file,
check timestamps, say what you saw. When the doc and the machine disagree,
say so and ask.

## Where things are

HANDOFF.md (the open work list and what is live, as of 17 Sep),
SECOND-DEVELOPER.md (the long form), README.md, SETUP.md, tools\app\HOOKUP.md
(launcher classes), tools\MOVING-THE-SERVER.md (the VPS), lore\ (the world),
tools\docs-app\data\site\*.md (public pages), tools\Ship-Rules.ps1 (what
never leaves a machine in a release).
