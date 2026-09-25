# Working in this repo, for a Claude

CONTRIBUTING.md holds the rules for everybody who works here, with AI or
without: the team, the words, the To Do List, the settled design, how work
moves and what to run after a merge. Read it first, every session, whoever
you are working with; every rule in it binds a Claude. This file adds only
what is about a Claude.

Decided by Patrick on 25 Sep and approved in #dev: the rules moved from this
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

That is Patrick. It is not a change for anybody else's sessions, and it is not
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

## Where things are

CONTRIBUTING.md (the rules, for everybody), the board for open work,
DEVELOPING.md (the long form), README.md,
tools\app\ARCHITECTURE.md (the launcher: startup, what each class owns, and
the Play sequence), docs\MOVING-THE-SERVER.md (the VPS), lore\ (the world),
tools\docs-app\data\site\*.md (public pages), tools\Ship-Rules.ps1 (what
never leaves a machine in a release), docs\archive (dated snapshots, history
only).
