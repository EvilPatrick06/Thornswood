# 2303 / 459 Credits page names the right engine; Publish-Server records what it installs

- **Lane:** Claude (overnight run 11 to 12 Oct, slug deploy-records)
- **Issue / PR:** #2303 and #459, #2335 (merged as 4ff1e607)
- **Channel:** the site (live, thornswood.net) for the credits page; dev for the Publish-Server proof
- **Staff status updates:** #staff-updates (1549254991082946570)
- **Needs first:** nothing for the docs deploy. The dev Publish-Server needs the server build on One (dist\server at the build records\server-build.json names, 92848550), which is the fork worktree's, not the shared clone's (step 2 says why and where).

## Run

### 1. The docs deploy (refreshes https://thornswood.net/credits)
From the shared clone `C:\Thornswood-Repo` once it is at or past the merge commit (`git fetch` then the clone is detached at origin/main):

    .\scripts\deploy\Deploy-Docs.ps1 -Site

That sends the app with the public pages. The app part is site\server.js, which can now fill the credits sentence when the record names only one server. The pages part is site\data\site\credits.md, whose hand sentence no longer names an engine. Both are needed: server.js alone would fix the page, but whenever the record could not be read the old credits.md hand text would come back, still naming 3a32e961.

### 2. The proof that Publish-Server records (leaves #459 and #2303 open until it is done)
The next time a server goes to dev through Publish-Server, or now if the main session wants the proof tonight.

**Not from the shared clone, and not with the shared clone's build.** Measured 12 Oct about 2:40 AM (slug small-followups):
- The shared clone fails the deploy guard (#2118): its `engine\skymp` is checked out at 9035ea46 (fork PR 52, the death path) while main pins 92848550, and `git status` counts that as a change.
- Its `engine\skymp\build\dist\server` is NOT the 92848550 build. It was built 7:11 PM 11 Oct from 9035ea46: `scam_native.node` 91d2b80e where the record says 1ce9da49, and `ActiveMagicEffect.pex`, `skymp5-server.js.map` and `yarn.lock` differ too. Publish-Server would refuse it at the record check (nothing sent), but it is the wrong build to name.
- The build that is `records\server-build.json` file for file (checked with `Get-ThornswoodServerBuildProblems`): `C:\Thornswood-Repo\worktrees\claude-skymp-7feb5dc4\build\dist\server`, a fork worktree at 92848550. Its load order is the same 102 plugins in the same order as the shared clone's build (which #2309 found equal to the dev box's), and the same start point.

**Needs first:** #2388 merged (Publish-Server names the built server it packs and stops before anything when there is none; without it a fresh worktree stops late inside Export-ServerPayload with "server dist not found"). The command below works on main before #2388 too, because `-Dist` is given; #2388 only makes the no `-Dist` case say what to do.

From a fresh worktree at origin/main (the guard needs one), in PowerShell 7:

    git -C C:\Thornswood-Repo fetch origin
    git -C C:\Thornswood-Repo worktree add --detach "C:\Thornswood-Repo\worktrees\publish-dev-459" origin/main
    cd "C:\Thornswood-Repo\worktrees\publish-dev-459"
    .\scripts\release\Publish-Server.ps1 -Channel dev -NoPause -Dist "C:\Thornswood-Repo\worktrees\claude-skymp-7feb5dc4\build\dist\server"

Then, once it is read back: `cd C:\Thornswood-Repo` and `git worktree remove --force "C:\Thornswood-Repo\worktrees\publish-dev-459"` (its `out\` holds the payload zip and the artifact, which are scratch).

What the run writes outside the box, so nobody is surprised: Publish-Server copies the commit's `game\gamemode.js` into the `-Dist` build and sets `thornswoodMostOnline`/`maxPlayers` in that build's `server-settings.json` from `records\most-online.json` (it always has; both are already the values it would write unless main moved the gamemode). That folder belongs to the claude-skymp-7feb5dc4 worktree; check nobody is building in it first.

## Check afterwards

After step 1 (read https://thornswood.net/credits): the paragraph that starts "The server's engine goes to our test server first" should end "The main server runs it, 92848550." (with a link to the full commit). That comes from the box's `C:\Thornswood-Docs\data\deployed-build.json`, which at 10:40 PM on 11 Oct held `live` only, 928485503333b18c2325fc13cbf781d254b19af0, written 4:37 PM by Deploy-Server. It must no longer say 3a32e961.

After step 2, Publish-Server prints a "Recording what it runs" block with "the box records thornswood-server-dev as gamemode-<12 of the commit>-<16 of the zip hash>.zip" and "the site now reads that the dev server runs 92848550". What the box should then hold:
- `C:\Thornswood-Deploys\current\thornswood-server-dev.json` and `C:\Thornswood-Server-Dev\data\thornswood-deploy.json`, the same file: part thornswood-server-dev, component gamemode, name = the gamemode artifact for the commit the clone is at, commit = that commit in full, deployedUtc = the run's time. Also readable at http://192.135.112.23:7788/thornswood-deploy.json.
- `C:\Thornswood-Deploys\gamemode\<that name>.zip` and `.json`, and a line in `C:\Thornswood-Deploys\history.log`.
- `C:\Thornswood-Server-Dev\thornswood-build.json` with channel dev, commit = the clone's short commit, gamemodeSha256 = the SHA-256 of `C:\Thornswood-Server-Dev\gamemode.js`.
- `C:\Thornswood-Docs\data\deployed-build.json` with `dev` added (commit 928485503333b18c2325fc13cbf781d254b19af0, the records\server-build.json source commit) and `live` kept. After that, the credits page says "Both servers run it, 92848550."
Then comment the readback on #459 and #2303. If both hold, close both: #2303 once the credits page reads right as well, and #459's record and stamp half (its other half, a CI-built versioned server payload, stays open on its own issue text, so leave #459 open with that said unless Patrick splits it).

## Risks and how to put it back

- Step 1 is the live site. If /credits misreads or the site does not come up, `.\scripts\deploy\Deploy-Docs.ps1 -PutBack` puts the app the deploy replaced back. The pages are files in the data folder and go back with a `-Site` run from the commit before the merge.
- Step 2 reinstalls the dev server the usual Publish-Server way (stage, check, swap, roll back if it does not answer). New in this change: if the box cannot write the deploy record after INSTALL OK, Publish-Server stops with exit 1 and says SERVER NOT RECORDED and why. The dev server is still up when that happens. Put back with `.\scripts\release\Publish-Server.ps1 -Channel dev -PutBack -NoPause`. That now records the folder that came back as "an older copy its record does not describe", because every folder installed before this change holds a record carried in from the folder before it, and that record is not trusted.
- A -SkipBuild zip packed before this change has no stamp for its channel and is refused before anything is sent. Run without -SkipBuild.

## Release notes (draft)

none (the site and the deploy records only; nothing in the game changes)

## News post (draft)

none

## Test task (draft, for closing the issue once the fix is on main)

none: nothing in the game changes. Close each issue with the readback above.
