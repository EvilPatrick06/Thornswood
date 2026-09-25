# The test harnesses

## What they are

Every `test-*.js` and `test-*.ps1` here checks one thing the scripts, the
launcher, the plugins, the gamemode or the site promise, by reading the files
or by running a piece of them against a scratch copy. None of them talks to
the VPS or to GitHub unless it says so at the top (`test-branch-rules.js
--live` is the one that does). The nightly checks (`.github/workflows/nightly.yml`) run every one of them
on the VPS each night and open an issue when one fails; on a pull request,
run the ones your change touches yourself.

The voice service's own harnesses stay beside it in `voice\`, and the bot's in
`bot\`, because they are run from there.

## Where they look

They moved here from `tools\` on 25 September (issue #440, phase 5). What they
test did not move, so each one finds `tools\` from here: a `.js` harness through
`TOOLS_DIR`, declared at its top as `..\tools`, and a `.ps1` harness through the
line after its `$Here = $PSScriptRoot` that points `$Here` at `..\tools`. A new
harness does the same; copying the top of an existing one is the easy way.

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
