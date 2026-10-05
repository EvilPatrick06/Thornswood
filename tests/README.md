# The test harnesses

## What they are

Every `test-*.js` and `test-*.ps1` here checks one thing the scripts, the
launcher, the plugins, the gamemode or the site promise, by reading the files
or by running a piece of them against a scratch copy. None of them talks to
the VPS or to GitHub unless it says so at the top (`test-branch-rules.js
--live` is one that does; `test-collection-revision-2.ps1` reads both
servers' manifests over plain HTTP unless given `-Offline`). The nightly checks (`.github/workflows/nightly.yml`) run every one of them
on the VPS each night and open an issue when one fails; on a pull request,
run the ones your change touches yourself.

A few of them run on every pull request as well, in the build check
(`.github/workflows/build.yml`), because each one's failure once sat on main
unseen: `test-ownership.js` (issue #752, a secret file reached main with no
row on `docs\OWNERSHIP.md`), and the list in its step "Run the harnesses that
went red unseen" (issues #875, #454 and #1088, the last three being the VPS
address kept in one place and deploys that are the same bytes for the same
commit). Each is under a minute. The rest are minutes together, which is why
they are nightly.

The voice service's own harnesses stay beside it in `voice\`, and the bot's in
`bot\`, because they are run from there.

## Where they look

They moved here from `tools\` on 25 September (issue #440, phase 5), and
`tools\` itself went on 29 September (phase 10). Each one finds the repository
folder from here, one folder up: a `.js` harness through `REPO_DIR`, declared at
its top as `path.join(__dirname, '..')`, and a `.ps1` harness through the line
after its `$Here = $PSScriptRoot` that points `$Here` at the repository folder.
A new harness does the same; copying the top of an existing one is the easy way.

## Running them

From the repository folder:

```
node tests\test-farming.js
pwsh -NoProfile -File tests\test-ship-rules.ps1
```

Each prints a PASS or FAIL line per check and ends on `N passed, M failed`,
and exits 1 when anything failed. A harness that reads something only one
machine has, such as the game folder, says SKIP for that part and checks the
rest.

## A harness that starts a service

Several builds run at once on the VPS and share its 127.0.0.1, so a harness
never gives a service a fixed port. It asks the system for one nothing holds
(listen on 0 and read the port back) and passes it in through the setting the
service already reads, `THORNSWOOD_VOICE_PORT` or `THORNSWOOD_DOCS_PORT`. A
server in the harness's own process listens on 0 and is asked on the port it
got. One that starts the voice service or the site asks nothing of the port
until that copy has printed its own `[voice] listening on` or
`[thornswood-docs] listening on` line for it, and fails saying so when the
service stops first because something else took the port. Before issue #1703
a run read another run's `/health` as its own, and before #1727 twelve site
harnesses polled the port they had let go until anything answered.
A `.ps1` harness does the same with its `Wait-OwnLine`, which reads the
child's output up to that line, and so does any stand-in it starts on a port
it let go (the GitHub stand-in in `test-site-assets.ps1`, the game server in
`test-record-sync.ps1`); before #1755 five of them drained the output unread
and polled the port. `test-1703-test-ports.js` fails on any `.js` harness here
or in `voice\` that names a fixed port, or on any `.js` or `.ps1` harness that
starts the site without waiting for that line.
