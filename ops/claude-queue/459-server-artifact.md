# 459 the server build from the box's store, and the engine built in CI

- **Lane:** Claude (12 Oct afternoon, slug feed-records; 16 Oct, slugs 459-store-deploy and 459-engine-ci; 17 Oct, slug 459-fork-ci)
- **Issue / PR:** #459; #2467 (merged as d8ec2081); #2593 (merged as a1ea6c47); #2589 (engine.yml, merged as cf032d29); fork EvilPatrick06/skymp#79 (merged as 877113d7), #2666 (merged as cb8fc188), #2712 (merged as c706cfda)
- **Channel:** dev for run 3; VPS only for run 4; none for the readbacks
- **Staff status updates:** #staff-updates (1549254991082946570)
- **Left:** only run 4's first engine.yml run that compiles (a fork commit with no fork build of its own). Runs 1, 2, 3 and 5 are done (Ran, below).

## Run

### 1. Two readbacks of the 12 Oct 10:34 AM dev Publish-Server (read only)
Still not read back. HTTP showed the publish wrote `dev` into `deployed-build.json`, which it does only after SERVER RECORDED, but a 2:36 PM Deploy-DevGamemode wrote over its deploy record. These two lines show the publish's own:

    ssh Administrator@192.135.112.23 "powershell -NoProfile -Command Get-Content C:\Thornswood-Deploys\history.log -Tail 20"
    ssh Administrator@192.135.112.23 "powershell -NoProfile -Command Get-ChildItem C:\Thornswood-Deploys\gamemode -Filter gamemode-e34bf423e946-*"

Expected: a line about 4:3x PM UTC (10:3x AM Mountain) ending `thornswood-server-dev gamemode-e34bf423e946-<16 hex>.zip from ONE`, and that zip with its .json. (history.log has moved on since; `-Tail 200` if 20 does not reach it.)

### 2. The store keeps the server build: done, measured 16 Oct about 7:40 AM
Read only: `C:\Thornswood-Deploys\server` holds `server-3bdf3d3c9926-0bb80f930aad8dbc.zip` (19,386,397 bytes) and its `.json`, whose `recordSha256` (650708069bd3...) is the sum of `records\server-build.json` on main. Nothing to run.

### 3. A dev publish from the store, with no engine build (after #2593 merges)
From a fresh worktree at origin/main (no engine build in it, no `-Dist`):

    git -C C:\Thornswood-Repo fetch origin
    git -C C:\Thornswood-Repo worktree add "C:\Thornswood-Repo\worktrees\run-459-fromstore" --detach origin/main
    cd "C:\Thornswood-Repo\worktrees\run-459-fromstore"
    .\scripts\release\Publish-Server.ps1 -Channel dev -FromStore

It should print `server build  server-3bdf3d3c9926-0bb80f930aad8dbc.zip, in the store on the box` before Copying, the installer's `the server build server-3bdf3d3c9926-... out of the store: 7 files ...`, `<n> plugin(s) the running server's load order names taken from ...\plugins into the stage`, INSTALL OK, SERVER RECORDED and DOOR CARRIED. It drops whoever is on dev for the restart: look at dev's online.json first. Afterwards remove the worktree:

    cd C:\Thornswood-Repo
    git worktree remove "C:\Thornswood-Repo\worktrees\run-459-fromstore"

### 4. The engine built in CI, first run (after #2589 merges; VPS change)
The fallback needs the C++ toolchain on the box, which changes the box (several GB of Build Tools, and yarn in Node's folder). Patrick chose the VPS as the fallback on 15 Oct (C then B), which this carries out; still, it installs on the live box, so run it when nobody is on:

    cd C:\Thornswood-Repo
    .\scripts\vps\Remote.ps1 -File .\scripts\vps\Bootstrap-VPS.ps1 -Arguments '-IncludeEngineTools -SkipFirewall'

It ends with `ready:` lines including `c++ ... with CMake` and `yarn ...yarn.cmd`. Then start the first build of the pinned engine:

    gh workflow run engine.yml --ref main
    gh run list --workflow engine.yml -L 1

The hosted job is skipped while `BUILD_RUNNER` is `vps`, and "Engine build (VPS fallback)" runs. The first run on a runner builds every vcpkg library; allow hours. Record on #459: how long each step took, the size the vcpkg cache folder printed, the disk free it printed at the end, the hosts vcpkg and yarn downloaded from (for the outbound limits, docs\RUNNER-ISOLATION.md section 6), and whether the records it made match the pin's commit. The records will not be One's bytes (a rebuild never is); nothing is pinned from it unless Patrick says so.

### 5. Patrick's B: the fork builds, engine.yml records (after fork #79 and #2666 merge)
The main session merges, in this order (Claude agents do not merge):

1. Fork #79 with a MERGE COMMIT (engine\README.md, One engine), from any folder:

       gh api -X PUT repos/EvilPatrick06/skymp/pulls/79/merge -f merge_method=merge -f sha=789b5cb6e9e0d67afe67fef778e27104b04c67eb

   That push to thornswood/engine-changes starts "Thornswood PR Windows" on the new head (about 30 minutes now that the LF libraries are in the package feed, up to about 70 if not). Its artifact is `thornswood-engine-<new head>`.
2. #2666 once Launcher builds (VPS fallback) is green on its head (green on 63db0ff6, rebased on 62f82e57, 18 Oct; rebase first if main moved since):

       gh api -X PUT repos/EvilPatrick06/Thornswood/pulls/2666/merge -f merge_method=squash -f sha=<head sha>

3. When the fork's push build of the new head is green (`gh api "repos/EvilPatrick06/skymp/actions/workflows/thornswood-pr-windows.yml/runs?event=push&per_page=1" --jq ".workflow_runs[0] | [.head_sha,.status,.conclusion]"`), the first engine.yml run (one run):

       cd C:\Thornswood-Repo
       gh workflow run engine.yml --ref main -f commit=<the new fork head, 40 hex>
       gh run list --workflow engine.yml -L 1

   The hosted job is skipped (BUILD_RUNNER vps) and "Engine build (VPS fallback)" runs. It should say "built <commit> in run <id>; this run records that build", skip every compile step, and end in minutes with artifact `engine-<12>`: both records, the server zip and .json, six client files, fork-build.json and SHA256SUMS. If "Look for the fork's build" fails with a 401 or 403 on the download, the run's token cannot read the fork's artifacts: say so on #459 (the one part not proven before merge). Nothing is pinned from it unless Patrick says so.

## Check afterwards (run 5)
- The fork's push run kept `thornswood-engine-<new head>` (`gh api repos/EvilPatrick06/skymp/actions/runs/<id>/artifacts --jq ".artifacts[].name"`).
- The engine.yml run's "Record the fork's server build" printed `built by https://github.com/EvilPatrick06/skymp/actions/runs/<id>` and `Server build recorded`, and "Check the records name this commit" passed.

## Check afterwards
- Run 3: `http://192.135.112.23:7788/thornswood-deploy.json` names the gamemode artifact of the main commit; `C:\Thornswood-Server-Dev\server-build.json` is still the 3bdf3d3c record; the dev load order unchanged.
- Run 4: the run's artifact `engine-3bdf3d3c9926` holds both records, the server zip and its .json, six client files and SHA256SUMS.

## Risks and how to put it back
- Run 3: a refusal before Copying changes nothing. A refused install leaves dev as it was (INSTALL REFUSED). One that does not answer is put back by the installer. Otherwise `.\scripts\release\Publish-Server.ps1 -Channel dev -PutBack`.
- Run 4: the install takes disk on the box (117 GB free on 16 Oct) and runs for a while; the game servers run at High priority above it. A build on the box uses its cores for a long time: start it when nobody is on. Each run removes its fork checkout and build folder; the vcpkg cache (one per runner, in each runner's `_work\Thornswood\engine-vcpkg-cache`) stays.

## Release notes (draft)
none

## News post (draft)
none

## Test task (draft)
none

## Ran
- 18 Oct 11:49 AM (Claude): step 5. The first run (39149317535, 11:22 AM) stopped in 13 s: the runner reused nightly.yml's depth 1 fork folder, so origin/thornswood/engine-changes was never made; fixed in #2712. The rerun, 39151300561, was green in 36 s: it recorded the fork's run 39146526303 build of 877113d7, compiled nothing, artifact engine-877113d72cbc (11 files, sums check). The run's token reads the fork's artifacts. Step 1 read back through Remote.ps1 -File: the 12 Oct 10:35 AM history line and gamemode-e34bf423e946-b7d70cdac5cb1031.zip are there. Details on #459. Left: step 4's compiling run; the pin stays 3bdf3d3c until its own PR.
- 17 Oct about 9:15 PM (Claude, 459-fork-ci): fork #79 and #2666 opened; fork CI run 39088067056 green with its artifact; VPS Launcher builds green on 08762d72; the found path's record steps run on One against that artifact recorded both (details on #459). Left: step 5.
- 16 Oct about 12:35 PM (Claude): step 3, `Publish-Server.ps1 -Channel dev -FromStore` from 9c27a1e4, INSTALL OK (details on #459). Left: step 4 (Bootstrap-VPS -IncludeEngineTools, then the first engine.yml run) and Patrick's B.
