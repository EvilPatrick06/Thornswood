# Working in this repo, for a Claude

CONTRIBUTING.md holds the rules for everybody who works here, with AI or
without: the team, the words, the To Do List, the settled design, how work
moves and what to run after a merge. Read it first, every session, whoever
you are working with; every rule in it binds a Claude. This file adds only
what is about a Claude.

Decided by Patrick on 25 Sep and approved in #staff-general: the rules moved from this
file to CONTRIBUTING.md, because the team grew past two people and not all of
them use AI, and one copy of the rules is the only copy that stays true.

## Recording what a session finds

Everything a session turns up goes on the board as an issue, or on the issue
it belongs to, before the session ends (CONTRIBUTING.md says where the board
is and how its order works). Saying it in a reply is not recording it: a
reply is gone when the window closes. Say in the reply which issues moved.

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
Claude working with Djinn or Ataxayk runs the same chain for their work:
commit, push, pull request, merge, a dev Ship (`Ship.ps1 -Channel dev`),
`Deploy-DevGamemode.ps1` and the other dev deploys, saying what goes out as
above. Never ask Patrick to run something the person you work with can run.
When their machine is missing something (the engine build, the VPS key, the
dev webhook, access to Thornswood-Releases), DEVELOPING.md "Setting up a
machine" says how; do that with them, and put on the board only the one-time
step that needs Patrick. It is not permission to ship on a hunch: a main Ship
still needs Patrick to say so. Never start the launcher or the game.
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
- Merge only once `Launcher builds` (the VPS runner) says pass. Nothing on
  GitHub enforces it; see CONTRIBUTING.md.

## Where things are

CONTRIBUTING.md (the rules, for everybody), the board for open work,
DEVELOPING.md (the long form), README.md,
launcher\app\ARCHITECTURE.md (the launcher: startup, what each class owns, and
the Play sequence), docs\MOVING-THE-SERVER.md (the VPS), lore\ (the world),
site\data\site\*.md (public pages), scripts\release\Ship-Rules.ps1 (what
never leaves a machine in a release), docs\archive (dated snapshots, history
only).
