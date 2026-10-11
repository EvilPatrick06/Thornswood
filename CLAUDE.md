# Working in this repo, for a Claude

Developer-Guide.md holds the rules for everybody who works here, with AI or
without: the team, the words, the To Do List, the settled design, how work
moves and what to run after a merge. Read it first, every session, whoever
you are working with; every rule in it binds a Claude. This file adds only
what is about a Claude.

Decided by Patrick on 25 Sep and approved in #staff-general: the rules moved from this
file into the guide everybody reads, because the team grew past two people and not all of
them use AI, and one copy of the rules is the only copy that stays true. On 3 Oct
that copy became Developer-Guide.md.

## Recording what a session finds

Everything a session turns up goes on the board as an issue, or on the issue
it belongs to, before the session ends (Developer-Guide.md says where the board
is and how its order works). Saying it in a reply is not recording it: a
reply is gone when the window closes. Say in the reply which issues moved.

## Picking issues to work

Decided by Patrick on 11 Oct: needing his decision, needing the VPS, and
waiting on a date are not reasons to leave an issue out of a pick.
Developer-Guide.md "What is not a reason to skip an issue" is the rule. For a
Claude: a decision goes to him written out in full in the same reply (what is
wrong, what was measured, each option, a recommendation), not as a terse
picker; and a date in an issue is checked against what really waits on it
before it is trusted.

## The runs the lanes leave

Decided by Patrick on 11 Oct: the lanes only commit, push and merge, and a
Claude runs every Ship, deploy, install, live server and Vortex step for them.
Each lane writes one note per change in the vault's `wiki/claude-queue/`
(Developer-Guide.md, the lanes paragraph). At the start of a session on the
shipping machine, list that folder and run each note: dev ones when they are
ready, a Main Ship or a live server run when Patrick says so. Afterwards put
what ran, when, what it printed and the health check on the issue and in
`wiki/status.md`, and delete the note. A note that cannot run keeps the
reason written into it.

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

Extended by Patrick on 25 Sep to everybody on the team, after Djinn's Claude
kept handing him the steps: "I want to fix it so Djinn can do all of that
... I should not be the only one doing everything they have VPS access". A
Claude working with any other developer runs the same chain for their work:
commit, push, pull request, merge, a dev Ship (`Ship.ps1 -Channel dev`),
`Deploy-DevGamemode.ps1` and the other dev deploys, saying what goes out as
above. Never ask Patrick to run something the person you work with can run.
When their machine is missing something (the engine build, the VPS key, the
dev webhook), Developer-Guide.md "Setting up a
machine" says how; do that with them, and put on the board only the one-time
step that still needs an account holder. Any developer may merge their own
pull request when they are confident in it and `Launcher builds` is green,
and may Ship dev, Ship main, deploy the docs, deploy the gamemode, and post
the Discord news and the game news. Never start the launcher or the game.
Measure before claiming a cause: read Profile\launcher.log, look at the file,
check timestamps, say what you saw. When the doc and the machine disagree,
say so and ask.

### No band-aids, ever

Decided by Patrick on 4 Oct, after a Claude answered a band-aid with a second
one: the Riekling clothes remount took the clothes off at every door, and the
fix offered was to make the remount retry for four seconds instead of finding
the neck fault it covered. His words: "lets ban patching or bandaids for
fixes and actually fix things". Developer-Guide.md "Fix the cause, no
band-aids" is the rule for everybody. For a Claude it also means:

- Never offer a band-aid: not as a stopgap, not to unblock a test session,
  not "for now", not in a reply and not on a branch.
- When the cause is not known, say so, say what was measured, and say which
  measurement is missing and who can take it (a log off the VPS, a session in
  the game). Then get that measurement. Do not fill the gap with a guess and
  a retry.
- Read the code around what is being fixed for the band-aids already there.
  A fix that leaves one in place, or leans on one, is not finished.
- When your own earlier change turns out to be a band-aid, say so plainly,
  close or revert it, and record that on its issue.

### Buttons, not chat commands

Decided by Patrick on 4 Oct: never add a chat command for something people do in the world, only for staff and dev. `/stuck`, the lines that reach staff (`/helpme`, `/report`), the ways of saying a line (`/me`, `/do`, `/w`, `/s`, `/y`, `/ooc`) and `/roll` stay commands with no buttons, and help text names them; docs\SYSTEMS.md "Buttons, not commands" is the rule and what counts as a button.

### Every reply ends with the commands, in order, and what each one is for

Asked for by Patrick on 19 Sep, after four pushes went out and not one pull
request was created, because the commands in the reply were missing a
`git checkout` and nobody could tell from reading them.

So a reply that leaves anything for a person to run ends with a block of the
exact commands, in the order they are run, each with a line saying what it
does and what it should print when it worked. No "then open a pull request",
no "deploy it": the literal line, copy and paste, from whatever directory the
reply says to start in. If a command needs a different directory, the `cd` is
one of the commands. If one of them is Patrick's rather than the person's
you are working with, say so on that line, because they run different halves.

Only commands that can be run now. Asked for by Patrick on 25 Sep: "stop
giving me commands when they arent ready to be ran yet if they are for later
than wait". A command that has to wait for a merge, a build or an answer goes
in the reply that comes after it, not in this one.

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
- In PowerShell a one-line `--body` uses ordinary double quotes. `@" ` starts
  a here-string, and the next character has to be a line break. A body of
  several lines goes in a variable first, then `--body $body`. Developer-Guide.md
  Quick start has the lines.

## On the shipping machine

Added by Patrick on 27 Sep, after a session found 624 local branches and 15
worktrees in the shared clone and read a session-start snapshot as the truth.

- `C:\Users\evilp\Downloads\Thornswood-Repo` is shared with Patrick's Grok Bot
  lanes and sits detached at `origin/main`, because they build from it. Do
  branch work in a worktree beside it (`git worktree add
  ..\Thornswood-claude-<what> -b claude/<what> origin/main`), and afterwards
  remove the worktree and delete the branch. Never leave that folder on a
  branch. Before deleting a worktree or branch you did not make, check no
  running process names its folder and its pull request merged over an hour
  ago; lanes may be mid-run in it.
- Never `git stash` in the shared clone (#992: 244 orphaned stashes were
  found there, archived as `refs/stash-archive/*`). Park work on a branch
  in your own worktree instead; a stash there is invisible to every other lane.
- Leave nothing stale (Patrick, 5 Oct: "we need rules ... not to leave stale
  worktrees, branches, or PRs local or on GitHub it's messy work"). The
  moment a pull request of yours merges or is closed, its worktree, local
  branch and GitHub branch go, in the fork as well as here, and so do any
  scratch folders and any process you started for it (a build, a load
  test). Before the session ends, list `git worktree list`, `git branch`,
  `gh pr list` and `git ls-remote --heads origin` in both repositories;
  what of yours is still there has its reason written on its issue, or it
  goes. Developer-Guide.md "No stray branches, worktrees or pull requests"
  is the rule for everybody.
- Three folders, no copies (Patrick, 5 Oct). Work only in this repository,
  the vault and `C:\ThornswoodTemps&Worktrees` (`worktrees\<name>`,
  `temp\<task>`); never make another top-level folder or leave scratch in
  Downloads, and never save a copy of a log, report, build or backup that
  GitHub or the VPS already holds. Cite where it lives instead.
- The git status at the start of a session is a snapshot and can be hours
  old. Run `git status` and `git log -1 origin/main` before saying what state
  the clone is in.
- Claude here often runs behind Headroom, which compresses tool output on
  purpose to save credits and drops small words from it ("the rule is and
  not"). A line that reads wrong may be the compression: read the file itself
  before acting on a rule that seems to say something odd, and never quote
  compressed output back as what a file says.
- The lanes' shared notes are the vault at `C:\Thornswood Vault\Thornswood`
  (`wiki/status.md` for what is true now, rewritten in place). Anything a
  session changes about tips, standing orders or what waits on Patrick goes
  there as well as on the board.
- Merge only once `Launcher builds` (the VPS runner) says pass and you are
  confident in the change. Nothing on GitHub enforces it; see Developer-Guide.md.

## Where things are

Developer-Guide.md (the rules and the long form, for everybody), the board for open work,
README.md,
launcher\app\ARCHITECTURE.md (the launcher: startup, what each class owns, and
the Play sequence), docs\MOVING-THE-SERVER.md (the VPS), lore\ (the world),
site\data\site\*.md (public pages), scripts\release\Ship-Rules.ps1 (what
never leaves a machine in a release), docs\archive (dated snapshots, history
only).
