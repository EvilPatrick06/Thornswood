# Contributing to Thornswood

The rules for everybody who works in this repository, with AI or without.
Read it before your first change and again when something here changes.
DEVELOPING.md is the long form: what the pieces are, how a release goes out,
how a machine is set up. CLAUDE.md is only what applies to a Claude.

## What this is

Thornswood: a modded co-op Skyrim roleplay server on SkyMP, in alpha and
open by application. This repo is the launcher (launcher\app, C# 5, WPF, built with the
.NET Framework 4 csc), the game plugins (game\plugins, Skyrim Platform
JavaScript), the site (site, node), the Discord bot (bot,
Python) and every script that ships or runs it. Owner: Patrick (EvilPatrick06). The team is in the table below.

## Who works here

| Who | GitHub | Discord | Mostly |
| --- | --- | --- | --- |
| Patrick | EvilPatrick06 | Patrick | Owner. Ships main, runs the VPS. |
| Djinn | WiccanDjinn | WiccanDjinn (953389672984363050) | Art and design. Windows account Ken. |
| Ataxayk | Ture-Neko | Ataxayk (324383732196704258) | A bit of everything. |

All three work on a bit of everything, with AI or without. Nothing here
assumes you use Claude: this file is the rules for everybody, and a Claude
reads the same file. CLAUDE.md only adds what is about a Claude. More people
are planned; a new developer goes in this table, in CODEOWNERS beside the
shared files, and on both repositories as a collaborator.

Patrick's Grok Bot lanes (Smeagle, Launcher, Installer, Website, GitHub,
Vortex) also work here, on the shipping machine, under his GitHub account.
Every rule in this file binds them the same as a person. They share notes
through an Obsidian vault at `C:\Thornswood Vault\Thornswood` on that machine
(`wiki/status.md` is what is true now); the vault is for coordinating, and
the board is still the one record of work. They mark what they are on with a
`claimed: <lane>` label and the board card moved to In Progress. Their
branches carry the lane's name (`launcher/`, `website/`, `github/` and so on).
On the shipping machine `C:\Users\evilp\Downloads\Thornswood-Repo` is shared
by all of them and sits detached at `origin/main`, because lanes build from
it: branch work goes in a worktree beside it, removed with its branch once
the pull request merges.


## Words

The people in the world are customers, clients, people, testers, partners.
Never "player". No em dashes anywhere written for people. Plain, direct
sentences, no filler, no placeholders. Secrets (server passwords, site keys,
Discord tokens, the news webhook, anything out of a config.json or .env on the
VPS) are named by location only; never printed, pasted, committed or logged.

## Everything we need to do goes on the board

The one record of outstanding work is the Thornswood To Do board:
https://github.com/users/EvilPatrick06/projects/1

Each piece of work is an issue on this repository, and every issue is on the
board. Decided by Patrick on 25 Sep and approved in #staff-general: the list moved there
from a claude.ai page that nobody without Claude could open. The 169 open
entries became issues #368 to #536, each keeping its old number as its Order.
`docs/archive/todo-list-2026-09-25.md` holds every entry as it stood that day,
the finished ones included, so a comment in the code that says "entry 243 on
the To Do List" means entry 243 in that file.

Decided by Patrick on 17 Sep. Anything a session turns up goes on the board
before the session ends. A defect, a decision, a correction to something
already on there, or work started and not finished. Saying it in a chat or a
reply is not recording it: that is gone when the window closes and the next
person has no way to know it was ever found. What prompted this was a Google
Ads tag added to the site whose only trace was a paragraph on a neighbouring
entry, with no step telling anybody to deploy it.

How to use it:

- Order is the do-order. A new issue gets the Order of where it belongs, not
  the end; a number between two others (52.5) is fine.
- Work that fits an existing issue is an edit or a comment on it, not a
  second issue. Write down what was measured and what is left.
- Uncommitted changes sitting in the repo are outstanding work and belong on
  the board too.
- Labels: `wave:` is the stage, `area:` the part of the project, `needs:` who
  or what it waits on, and `anyone can start` marks what needs nobody in
  particular. Assign yourself when you start one.
- A pull request that finishes an issue says `Closes #N`, so merging closes
  it and the board moves it to Done. Say in the pull request, or in #staff-general,
  which issues moved.

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
  `records\client-build.json`; `Sync-Client.ps1` puts it in the game folder and
  Ship refuses a release whose client is not the recorded build. Nothing is
  taken from the Steam copy's `Data\Platform` or its SkyMP DLLs, because until
  that day another launcher's builds of all of them were what shipped.
  This is what ships now, corrected 18 Sep. The bullet used to say the Steam
  copy shipped until `djinn/own-game-folder` reached main. That branch is on
  main, `C:\Thornswood\Game` is built, and the launcher restarts into it:
  Profile\launcher.log records "runs from the new folder". A session reading
  the old wording would have believed the wrong layout was live, which is the
  one thing this section exists to prevent.
  Decided by Patrick on 24 Sep, for a tester whose Vortex deploys into
  another server's copy of Skyrim (`steamapps\common\Keizaal Online`), in
  his words "detcts and fixes this but doesnt have the servers bleed": when
  Vortex deploys anywhere but the Steam copy, `Thornswood\Game` is the Steam
  copy's game plus exactly the files Vortex's record in that folder lists,
  taken from Vortex's own mods folder, and nothing else of that folder is
  read. Scan names the folder, Fix and Settings point the launcher at it,
  and with no Steam copy on the machine it refuses (OwnGame.DeploysInto,
  Gather, tests\test-vortex-folder.ps1). Djinn to agree it in #staff-general.
- Whichever folder the game runs from, the launcher looks after its own
  files: Keep puts its files back before Play and parks any plugin in
  `Data\Platform\Plugins` that is not ours; Hold keeps its files open read
  only while the game runs; the plugins idle unless the client points at our
  server and a fresh session note is there; Publish-Update packs what belongs
  and nothing else (Ship-Rules.ps1, by what is ours rather than by whose
  anything is). No wrapper scripts around the launcher, nothing moved by hand
  in Data\Platform, nothing touches Vortex's own files.
- The SkyMP client runtime is built from the fork, the `engine\skymp`
  submodule of this repository on `thornswood/engine-changes`, and recorded
  in `records\client-build.json` by `New-ClientBuildRecord.ps1`.
  `Sync-Client.ps1` puts the six recorded files in the game folder and
  refuses any that is not the recorded build; Ship refuses a release whose
  client is not. Every change Patch-Client.ps1 used to make by text is in the
  fork's source, and that script is gone.
  Decided by Patrick and Djinn on 25 Sep, so the second machine has
  everything and GitHub holds it: the fork, its build and the release output
  live in the repository folder, not in `C:\Thornswood-Dev`. The fork is the
  `engine\skymp` submodule, pinned to the commit the build records name; the
  output (packs, launcher, installer, server payload) is `out`, ignored by
  git; anything else that folder held and that never goes to GitHub is
  `local`, ignored too. Scripts ask `scripts\release\Where.ps1` where each of these is
  rather than naming a path. It no longer falls back to `C:\Thornswood-Dev`:
  no machine has that folder any more, and the fallback went on 28 Sep
  (issue #440), along with the forwarding copies in `tools\`.
- Launcher code is C# 5 only: no string interpolation, no ?., no nameof,
  no expression bodied members, no out var.
- Every change goes out as one complete release: launcher, game files and
  server together, never a half.

Anything that changes one of these is a few lines in #staff-general first: the
problem, the approach, what it touches. Agreed in #staff-general by
the team before code; nobody settles it alone, and a Claude never does.
## How work moves

- main is what ships. Only Patrick's machine ships main, and Ship.ps1 refuses
  a main release that is not on main, is behind or ahead of origin, has
  anything uncommitted, has a file under `scripts` or another folder a release is built from that git does not know, or
  asks for a new number with `-Version`. A main Ship writes nothing to the
  repository: the version moves first through `Bump-Version.ps1` and its own
  pull request, and Ship builds only what is already on GitHub, so every other
  machine can `git pull` exactly what shipped. Corrected 24 Sep: this bullet
  used to say a main Ship committed and pushed the source after the release,
  which stopped being true on 22 Sep (f917dd8).
- The one live release that does not come off main is a hotfix, decided by
  Patrick on 24 Sep for a tester who could not get in while a day of dev work
  sat on main: "the only thing that should be going to main now is the fix
  for him". A branch named `hotfix/...` starts from the commit the live
  release was built from, carries only the fix and its `Bump-Version.ps1`
  commit, is pushed, and Ship runs from a checkout of it; every other gate
  above still applies, and Ship refuses a hotfix branch that is not on
  GitHub. A hotfix leaves the dev feed alone. The fix also goes to main
  through its own pull request, or the next main release loses it. 1.1.93 was
  the first, built from 55ac6ef. A hotfix is Patrick's call, like any live
  release. Once it is live, its commit is kept as a tag, `live-<version>`,
  and the branch is deleted, so no hotfix branch sits on GitHub: the next
  hotfix starts with `git checkout -b hotfix/<name> live-<version>` from the
  tag of the release that is live. 1.1.94 is `live-1.1.94` (25 Sep).
- Nobody pushes to main any more, Patrick included. Everything goes through a
  pull request. This replaces the 18 Sep decision that his own work went
  straight to main, which held while `enforce_admins` was off and stopped
  holding the moment it went on.
- What branch protection on main actually enforces, since 25 Sep:
  `enforce_admins` is **off**, there is no required check, required
  approving reviews is **0**, and the code owner review is **off**.
  Patrick, that day: "we don't need the required check/reviewer at all anymore for anyone as long as we give verbal agreement and the VPS check goes through". So the rule is ours, not a setting:
  anybody on the team merges their own pull request once `Launcher builds`
  (the build check, on the VPS) is green and they have said what it is in
  #staff-general. Nobody waits for Patrick. Force pushes are refused.
  Because nothing enforces it, it has to be kept by hand: on 25 Sep 35 pull
  requests were merged with their VPS build red and 18 with no build at all,
  and main went red with them. Wait for `Launcher builds` to say pass before
  merging, every time, including your own and including a Claude's. The last
  GitHub setting, "require branches to be up to date" with no check listed,
  was removed on 27 Sep at Patrick's word ("we use the VPS's build checker"),
  so GitHub requires nothing at all now.
  What changed on 23 Sep, since 22 Sep: the review requirement was one
  approving review, which Patrick could not give himself and had to override
  with `--admin` on every one of his own pull requests, and it is now zero.
  The code owner review on `.github/CODEOWNERS` is off. And `enforce_admins`,
  which had to stay off while `Ship.ps1` pushed its own version commit
  straight to main, went on, because Ship writes nothing to the repository now:
  `Bump-Version.ps1` moves the number first, as an ordinary commit on a
  branch, and Ship reads it.
  Check which it is rather than assuming, because this paragraph was wrong
  for a day before anybody looked:
  `gh api repos/EvilPatrick06/Thornswood/branches/main/protection`
- Everybody's work goes on a branch named for whoever did it:
  `git checkout -b <name>/what-it-is` (patrick/, djinn/, ataxayk/, and
  claude/ for a Claude's). Small commits, plain messages. Push the branch and
  open a pull request, standing on the branch, not on main:
  `git checkout <name>/what-it-is; git push -u origin <name>/what-it-is; gh pr create --fill`.
  It is merged into main from GitHub, never pushed over main.
  The branches opened before 17 Sep use a `gavin/` prefix; they are Djinn's
  and were left alone rather than renamed under open pull requests.
- One fix per commit, on a branch as much as anywhere: a commit that changes
  eight things cannot be reverted when one of them is wrong.
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
- The dev channel (`.\scripts\release\Ship.ps1 -Channel dev "what changed"`) may be
  run from any branch, from any developer's machine, to try work on the dev server.
  Say in #staff-general when you take it, because there is one dev feed and the last
  dev Ship wins. A main Ship resets it.
- Every release note has a title and details, dev included. Patrick, 25 Sep,
  after two dev posts went out as "The scroll glows" and "Dev build: ...":
  they must have details and be as good as the ones before them. The notes
  are what people read in the launcher, on the site and in Discord, so write
  them from the side of the person playing: a title that says what changed
  for them, then one "- " line for each thing they will notice, saying what
  it does and what to do if anything. Ship refuses a title under three words
  or notes with no "- " line. Since 27 Sep it also refuses notes that say
  what only we would understand (scripts\release\Note-Rules.ps1): the word
  player, an em dash, an issue or pull request number, "PR", a code file or
  a setting name (WEBVIEW2_LIKE_THIS), a name out of the code (PutInServerOrder,
  camelCase), our own words for how we work (demoting, worktree, squash, CI),
  and the same line twice. On 26 and 27 Sep all of those went out to the
  launcher, the site and Discord. And "The load order moved, so start a new
  character" is added by Publish-Update only when the plugins that are on, or
  their order, really changed; it used to follow any byte of plugins.txt and
  told testers to start over three times in two days. The shape:

  ```
  .\scripts\release\Ship.ps1 -Channel dev "The Downgrade button shows its progress and says why it stopped
  - A bar under the Downgrade button shows how far the downgrade has got: each of the three downloads with its size, then the copy into your game.
  - When the downgrade stops for any reason, the line under the button says why and what to do next.
  - If Windows will not open Steam's links, the launcher asks Steam directly, so Steam's console still opens."
  ```
- One fix per pull request. A branch that changes eight things is eight
  reviews nobody has time for; split it.
- No stray branches and no stray pull requests. Decided by Patrick on
  25 Sep, after a count found 70 branches on GitHub, two of them holding
  work that had never been merged and was nearly deleted with the rest:
  "we need to make sure in the docs that we don't leave a bunch of stray
  branches and PRs and fix+merge them everytime or delete if old".
  - A branch is deleted once its pull request is merged. GitHub does that
    by itself (the repository setting "Automatically delete head branches", on since 25 Sep);
    delete it by hand if it was not.
  - Work goes into a pull request the day it is done, never left on a
    pushed branch without one. That is how the two above were lost track of.
  - At the start of a session, and before anything is shipped, look at what
    is open: `gh pr list --state open` and `git ls-remote --heads origin`.
    Everything there other than main, the current `hotfix/` branch and work
    somebody is doing today gets one of two things: fixed and merged, or,
    when it is old or no longer wanted, its pull request closed with a line
    saying why and its branch deleted. Somebody else's branch is theirs to
    decide on: ask them, and put it on the board if they cannot be asked.
    Check whether its work is already in main before deleting it; a
    squashed merge leaves the branch looking unmerged to git.
- Code signing is on since 27 Sep (issue #390, closed): the launcher and the
  setup program are signed through Azure Artifact Signing
  (`records\signing\README.md`). `ExpectedSigner` in `launcher\app\Updater.cs`
  is set, so every launcher from dev 1.1.101.17 on refuses an update that is
  not signed by that certificate. **Only a machine that signs may Ship, dev
  included.** `Ship.ps1` and `Publish-Installer.ps1` refuse (non-zero exit) when
  `tools\signing.json` is missing or disabled, or when the launcher / Setup tip
  is not Authenticode Valid under `ExpectedSigner`. Local `Build-Launcher` /
  `Package -NoPublish` may still print "not signing" and leave an unsigned
  intermediate; that soft skip must not reach the site or the feed. The live main launcher,
  1.1.101, predates signing; the next main Ship is the first signed one.
- Every pull request gets the build check (.github/workflows/build.yml, about
  two minutes: the secret scan, every script and file parses, the writing
  rules, the ownership page (`tests\test-ownership.js`, added by issue #752),
  six more harnesses that are just as quick (the script index, the script
  paths, the architecture page and three launcher harnesses, issue #875),
  the launcher window, the count of
  silent catches in the launcher, and the launcher compiles with the .NET
  Framework csc). Red means the branch would stop Ship at the build step;
  fix that, and merge once it is green and you have said so in
  #staff-general. Run the test harnesses your change touches yourself. All
  ~190 of them, the bot and voice ones, and a look for stray pull requests
  and branches run every night on the VPS (.github/workflows/nightly.yml,
  03:00 Mountain); a failure there opens an issue on the board, "Nightly
  checks failed", and whoever broke it fixes it next. It runs on the VPS, on a runner
  `.\scripts\deploy\Install-Runner.ps1` puts there (issue #437), because
  GitHub's own runners were blocked on billing from 25 Sep.
  `.\scripts\deploy\Install-Runner.ps1 -Status` says whether GitHub sees it.
- Do not edit Shell.cs, Checks.cs, Keep.cs, Hold.cs, Updater.cs or
  Publish-Update.ps1 without a line in #staff-general first; every machine touches those.
## After a pull request is merged

Merging on GitHub changes nothing anybody sees. Patrick runs the rest on his
machine, from the repo folder.

1. `git checkout main`, then `git pull`. Ship.ps1 refuses a main release
   that is behind origin, so the pull comes first.
2. Then one command for each part the pull request touched:
   - The launcher (`launcher\app`, `launcher\ui.xaml`, the art and video that
     Build-Launcher.ps1 embeds), the game plugins (`game\plugins`), or
     anything else that goes out in a pack:
     `.\scripts\release\Ship.ps1 -Channel dev "what changed"`. The dev build is where
     it goes first, by the rule above. `.\scripts\release\Ship.ps1 "what changed"`
     with no channel is the live one, and that is for a security fix, for
     something that leaves the game untestable, or for work Patrick has
     said goes live.

     The note is the release post: #news, the launcher's News tab and the
     site all show it. Asked for by Patrick on 25 September, after a one-line
     dev note went out as a bare title: "what you gave for the news wasnt
     detailed enough". So a Ship command written for him carries the whole
     note. The first line is a title from the customer's side. Then one line
     starting with `- ` for each thing a person will notice, a plain sentence
     saying what it does for them and how to use it: the key, the button, the
     place. Never one line, and never branch names, pull request numbers or
     entry numbers. The dev post of 24 September 14:36 is the shape to copy.
     Ship refuses notes that break this (see "Every release note has a title
     and details" above), before it builds anything.
   - The gamemode behind that dev release: `.\scripts\deploy\Deploy-DevGamemode.ps1`.
     `Deploy-Gamemode.ps1` then `Deploy-Server.ps1` is the live pair.
   - The site's app or `site\public`: `.\scripts\deploy\Deploy-Docs.ps1`.
     The public pages (`site\data\site\*.md`) need
     `.\scripts\deploy\Deploy-Docs.ps1 -Site`.
   - The bot's code or join card art in `bot`:
     `.\scripts\deploy\Install-Bot.ps1 -CodeOnly`.
   - The bot's avatar (`bot\thornswood-bot-*.png`): no script
     sends it. It is uploaded by hand in the Discord developer portal.
   - `game\gamemode.js`: `.\scripts\deploy\Deploy-Gamemode.ps1`, then
     `.\scripts\deploy\Deploy-Server.ps1`.
   - The voice service (`voice\voice-server.js`, `voice\public`):
     `.\scripts\deploy\Install-Voice.ps1`.
   - Only scripts that run on Patrick's machine (Ship.ps1, Publish-Update.ps1,
     the Deploy scripts): nothing more. The pull is the change.
   A pull request that touches several of these gets every one of them, in
   the same sitting, so nothing goes out half done.
3. Everybody else, once it is out, from the main folder: `git checkout main`, then
   `git pull`. If the branch had its own folder, `git worktree remove
   ..\<that folder>`. Then `git branch -D <name>/what-it-is`, after GitHub
   shows the pull request as merged; GitHub squashes the merge, so
   `git branch -d` refuses. A file the branch added that also sits untracked
   in the main folder stops the pull, so delete that copy first.
