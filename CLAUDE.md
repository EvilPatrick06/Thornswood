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
  whatever else rewrites a copied file in place). Decided by Patrick on
  20 Sep: nothing here supports another server's install any more. The SkyMP
  client runtime is built from the fork and recorded in
  `tools\client-build.json`; `Sync-Client.ps1` puts it in the game folder and
  Ship refuses a release whose client is not the recorded build. Nothing is
  taken from the Steam copy's `Data\Platform` or its SkyMP DLLs, because until
  that day another launcher's builds of all of them were what shipped.
  This is what ships now, corrected 18 Sep. The bullet used to say the Steam
  copy shipped until `djinn/own-game-folder` reached main. That branch is on
  main, `C:\Thornswood\Game` is built, and the launcher restarts into it:
  Profile\launcher.log records "runs from the new folder". A session reading
  the old wording would have believed the wrong layout was live, which is the
  one thing this section exists to prevent.
- Whichever folder the game runs from, the launcher looks after its own
  files: Keep puts its files back before Play and parks any plugin in
  `Data\Platform\Plugins` that is not ours; Hold keeps its files open read
  only while the game runs; the plugins idle unless the client points at our
  server and a fresh session note is there; Publish-Update packs what belongs
  and nothing else (Ship-Rules.ps1, by what is ours rather than by whose
  anything is). No wrapper scripts around the launcher, nothing moved by hand
  in Data\Platform, nothing touches Vortex's own files.
- The SkyMP client runtime is built from the fork, `C:\Thornswood-Dev\skymp`
  on `thornswood/engine-changes`, and recorded in `tools\client-build.json`
  by `New-ClientBuildRecord.ps1`. `Sync-Client.ps1` puts the six recorded
  files in the game folder and refuses any that is not the recorded build;
  Ship refuses a release whose client is not. Every change Patch-Client.ps1
  used to make by text is in the fork's source, and that script is gone.
- Launcher code is C# 5 only: no string interpolation, no ?., no nameof,
  no expression bodied members, no out var.
- Every change goes out as one complete release: launcher, game files and
  server together, never a half.

Anything that changes one of these is a few lines in #dev first: the
problem, the approach, what it touches. Agreed between Patrick and Djinn
before code; a Claude does not settle it for them.

## How work moves between the two machines

- main is what ships. Only Patrick's machine ships main, and Ship.ps1 refuses
  a main release that is not on main, is behind or ahead of origin, has
  anything uncommitted, has a file under `tools` that git does not know, or
  asks for a new number with `-Version`. A main Ship writes nothing to the
  repository: the version moves first through `Bump-Version.ps1` and its own
  pull request, and Ship builds only what is already on GitHub, so the other
  machine can `git pull` exactly what shipped. Corrected 24 Sep: this bullet
  said a main Ship commits and pushes the source, which stopped being true
  on 22 Sep (f917dd8).
- Nobody pushes to main any more, Patrick included. Everything goes through a
  pull request. This replaces the 18 Sep decision that his own work went
  straight to main, which held while `enforce_admins` was off and stopped
  holding the moment it went on.
- What branch protection on main actually enforces, read off GitHub on
  23 Sep and not off this file: `enforce_admins` is **on**, the one required
  check is `Launcher builds`, required approving reviews is **0**, and the
  code owner review is **off**. So a pull request from either of them merges
  itself once the build goes green, and neither of them can push to main at
  all. Force pushes are refused.
  The three things that changed since 22 Sep: the review requirement was one
  approving review, which Patrick could not give himself and had to override
  with `--admin` on every one of his own pull requests, and it is now zero.
  The code owner review on `.github/CODEOWNERS` is off. And `enforce_admins`,
  which had to stay off while `Ship.ps1` pushed its own version commit
  straight to main, is on, because Ship writes nothing to the repository now:
  `Bump-Version.ps1` moves the number first, as an ordinary commit on a
  branch, and Ship reads it.
  Check which it is rather than assuming, because this paragraph was wrong
  for a day before anybody looked:
  `gh api repos/EvilPatrick06/Thornswood/branches/main/protection`
- Djinn's work still goes on a branch: `git checkout -b djinn/what-it-is`.
  Small commits, plain messages. Push the branch and open a pull request,
  standing on the branch, not on main:
  `git checkout djinn/what-it-is; git push -u origin djinn/what-it-is; gh pr create --fill`.
  Patrick reads it; it is merged into main from GitHub, never pushed over
  main.
  The branches opened before 17 Sep use a `gavin/` prefix; they are the same
  person and were left alone rather than renamed under open pull requests.
- One fix per commit either way. Going straight to main is not permission to
  put eight unrelated things in one push, and the reason is the same: a commit
  that changes eight things cannot be reverted when one of them is wrong.
- `git pull` before starting anything. If a pull conflicts, resolve it on
  your branch (`git fetch`, `git rebase origin/main`), never on main. If a
  push is rejected, pull, do not force.
- Decided by Patrick on 23 Sep: **everything goes to the dev build first.**
  His words: "start puttin these on the dev build and not the main build
  launcher unless it's a security issue or can make the game untestable,
  everything else even small changes go to the dev build launcher for
  pretesting". Size is not a reason to skip it. A main Ship is for a
  security fix or for something that leaves the game untestable, and he
  says which.
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
     anything else that goes out in a pack:
     `.\tools\Ship.ps1 -Channel dev "what changed"`. The dev build is where
     it goes first, by the rule above. `.\tools\Ship.ps1 "what changed"`
     with no channel is the live one, and that is for a security fix, for
     something that leaves the game untestable, or for work Patrick has
     said goes live.
   - The gamemode behind that dev release: `.\tools\Deploy-DevGamemode.ps1`.
     `Deploy-Gamemode.ps1` then `Deploy-Server.ps1` is the live pair.
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
(Check-*.ps1, Setup-SshKey.ps1 -Test, Sync-Client.ps1 -Check), and compile checks.
Edit source on a branch when asked.

Changed by Patrick on 23 Sep, during a night of playtesting: a Claude working
with him runs the whole chain itself, commit, push, pull request, merge, Ship
and the Deploy scripts. His words when it stopped to hand him commands: "why
arent you pushiong and merging and publishing these changes to the dev server",
and earlier, "you do those bro". Handing back a list of commands in the middle
of a test session costs more than it protects. Say which ones leave the machine
before running them, say what they did afterwards, and say in the reply what
went out.

That is Patrick. It is not a change for Djinn's sessions, and it is not
permission to ship on a hunch: a main Ship still needs him to say so. Never
start the launcher or the game.
Measure before claiming a cause: read Profile\launcher.log, look at the file,
check timestamps, say what you saw. When the doc and the machine disagree,
say so and ask.

### Every reply ends with the commands, in order, and what each one is for

Asked for by Patrick on 19 Sep, after four pushes went out and not one pull
request was created, because the commands in the reply were missing a
`git checkout` and nobody could tell from reading them.

So a reply that leaves anything for a person to run ends with a block of the
exact commands, in the order they are run, each with a line saying what it
does and what it should print when it worked. No "then open a pull request",
no "deploy it": the literal line, copy and paste, from whatever directory the
reply says to start in. If a command needs a different directory, the `cd` is
one of the commands. If one of them is Patrick's rather than Djinn's, say so
on that line, because the two of them run different halves.

Say which commands change something outside this machine, since those are
the ones that cannot be taken back: a push, a pull request, any Deploy-*,
Publish-*, Request-Restart, or Ship.

Run the whole block yourself in your head before you write it, against what
`git status` and `git branch --show-current` actually say right now. A
command that assumes a branch is checked out when it is not is the failure
this section exists for.

### Traps in the commands themselves

- `gh pr create` reads the CHECKED OUT branch as the head of the pull
  request. `git push -u origin <branch>` pushes the branch and does not
  check it out, so `git push -u origin <branch> && gh pr create --fill`
  run from main fails with "head branch main is the same as base branch
  main". Check the branch out first, or pass `--head <branch>`.
- `gh pr create --fill` also warns about uncommitted changes and carries on.
  `Claude outputs\` and `art-latest.txt` are untracked here and show up in
  that warning every time; they are not part of the pull request.

## Where things are

HANDOFF.md (the open work list and what is live, as of 17 Sep),
SECOND-DEVELOPER.md (the long form), README.md, tools\app\HOOKUP.md
(launcher classes), tools\MOVING-THE-SERVER.md (the VPS), lore\ (the world),
tools\docs-app\data\site\*.md (public pages), tools\Ship-Rules.ps1 (what
never leaves a machine in a release).
