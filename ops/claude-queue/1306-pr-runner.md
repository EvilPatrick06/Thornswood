# 1306 Pull request runner off the VPS (thornswood-pr on One)

Status: QUEUED, ready for Claude step 2 (lane: Waystone / Launcher). Mark DONE only after Claude reports it ran.
Written: 11 Oct 2026, origin/main at 2a5fb39.

## Current state
- DONE (lane): Install-Runner -OffBox and tests\test-runner-offbox.ps1 are on origin/main as of merge commit ca211b3fda8c (PR #2204, merged 4:31 PM MT 11 Oct, Launcher builds green). Register only from a clean checkout AT OR AFTER ca211b3.
- The build.yml runs-on change (old c3f0adb) is rebased locally as 6b31e80 on branch waystone/1306-buildyml-local (worktree C:\ThornswoodTemps&Worktrees\wt-1306-buildyml), NOT pushed. It waits for step 3.

## 1. What to run (order matters)
1. Lane (Waystone): rebase waystone/1306-runner-offbox onto origin/main, split so the Install-Runner -OffBox commits (34533ef, 6683a15) land first as their own PR, merged on green. build.yml (c3f0adb) stays unpushed.
2. Claude, on ship PC One, from a clean checkout at current origin/main that contains the merged -OffBox change, in an elevated PowerShell:
   - `git fetch origin; git status; git rev-parse HEAD` (must equal origin/main)
   - `.\scripts\deploy\Install-Runner.ps1 -OffBox -Label thornswood-pr -RunnerName <name, e.g. thornswood-pr-one>`
   - `.\scripts\deploy\Install-Runner.ps1 -OffBox -Status` (runner registered, online, network and folder guards on)
   - Confirm in GitHub Settings > Actions > Runners that the runner shows Idle with label thornswood-pr.
   - Report the PR/commit used and the runner name to Smeagle.
3. Lane (Waystone): only after Claude reports the runner online, push the rebased build.yml change (c3f0adb, rebased) and merge on green. Until a thornswood-pr runner is online, every pull request check would wait in the queue, so the order cannot be swapped.

## 2. Order and risk notes
- Lane names may change on rebase; check the exact parameter names in the merged Install-Runner.ps1 (-OffBox, -Label, -RunnerName, -Status, -Lock, -Remove, -AllowHost, -DefenderSkip exist on the branch). Optional: `-DefenderSkip` only if Claude decides it is acceptable on One.
- The runner account is shut out of C:\Thornswood* by design. Heavy builds on One: post in the Thornswood room before starting, one at a time.
- Registration needs a GitHub runner token fetched by the script via gh; no token goes in this note or the vault.
- Undo: `.\scripts\deploy\Install-Runner.ps1 -OffBox -Remove`.

## 3. Draft patch notes (internal)
- CI: pull request checks no longer run on the live VPS. They run on a separate locked down runner (thornswood-pr) off the box; pushes to main still build on the VPS.

## 4. News post
- None. Internal security change, people will not notice.

## Claude, 11 Oct 3:30 PM MT
Step 1 is done (ca211b3, PR #2204). Claude can run step 2 now, from a clean checkout at or after ca211b3.

## Patrick's decision, 11 Oct 7:20 PM MT: option C, GitHub-hosted runners
Not on One and not a separate machine. Pull request builds run on GitHub's hosted Windows runners; no machine of ours runs pull request code (#1306 has the full write-up). So step 2 here (Install-Runner -OffBox on One) is NOT run. The lane's work instead: build.yml's pull request job on a GitHub-hosted Windows image, anything it needs from the VPS installed in the job or the test made independent of it, then a pull request's Launcher builds passes there. Nothing for Claude to run until that merges; then Claude checks a pull request's run shows a GitHub-hosted runner and no pull request job reaches thornswood-vps.
