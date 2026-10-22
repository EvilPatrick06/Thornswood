# 2161 Runner isolation: outbound limits on the VPS runners, then the two collects

- **Lane:** Claude (taken over from Anvil / Installer, 12 Oct 2026, at Patrick's request)
- **Issue / PR:** #2161. Code already on main: Check-RunnerIsolation.ps1 (#2285, b47830fa), Install-Runner.ps1 -NetworkOnly (#2307, 3944c795), decision in docs/RUNNER-ISOLATION.md section 6 (#2305, 2b509b2f).
- **Channel:** VPS only
- **Staff status updates:** #staff-updates (1549254991082946570)
- **Needs first:** Patrick confirms the hosting console login works (step 1 of 2182-deploy-identities.md). Nothing below runs before that. Patrick's own order, 11 Oct.

## Decision (Patrick, 11 Oct 2026, final)
1. GitHub-hosted runners are the default for builds; the VPS runners are the backup. Codex's #1306 change is in: pull requests reach `thornswood-vps` only through the fallback job, same repository only. Read offline by Claude on 12 Oct (`Check-RunnerIsolation.ps1` against an empty facts file): every workflow row ok, 11 rows, 0 risk.
2. The VPS runner accounts get outbound limits allowing only GitHub and the package feeds builds use (pypi.org, files.pythonhosted.org, registry.npmjs.org). This note's live step.

## Read this before starting
- Since about 7:49 AM MT on 12 Oct the hosted runner is refused on billing (#2393), so every build now runs on the four VPS runners. A wrong block on one runner turns about a quarter of all builds red until it is removed. Do runner 4 alone first and watch its next jobs.
- A manual build cannot pick its runner: all four carry the same labels. Read which runner took a job with
  `gh api repos/EvilPatrick06/Thornswood/actions/runs/<run id>/jobs --jq '.jobs[] | "\(.name) \(.runner_name) \(.conclusion)"'`
  The runner names are `thornswood-vps`, `thornswood-vps-2`, `thornswood-vps-3`, `thornswood-vps-4`; their accounts are `thornswood-runner`, `thornswood-runner2`, `thornswood-runner3`, `thornswood-runner4`.
- Scratch goes in `C:\Thornswood-Repo\temp\2161-runner`, not $env:TEMP. Delete it when done; the facts file lists accounts and paths.

## Run
From the shared clone `C:\Thornswood-Repo`, detached at current origin/main, with gh signed in:

1. Dry run, runner 4. Changes nothing; writes the script it would send.

       New-Item -ItemType Directory -Force "C:\Thornswood-Repo\temp\2161-runner" | Out-Null
       .\scripts\deploy\Install-Runner.ps1 -NetworkOnly -Number 4 -AllowHost pypi.org,files.pythonhosted.org,registry.npmjs.org -DryRunTo "C:\Thornswood-Repo\temp\2161-runner\runner4-net.ps1" -NoPause

   Read the file: one script, Set-RunnerFirewall for `thornswood-runner4`, rule group `Thornswood PR runner thornswood-runner4`, outbound Block rules matched to that account's SID that cover every address except GitHub's ranges (from api.github.com/meta), loopback and the three hosts' addresses. Nothing for any other account.

2. Real run, runner 4 (changes the VPS firewall for that one account):

       .\scripts\deploy\Install-Runner.ps1 -NetworkOnly -Number 4 -AllowHost pypi.org,files.pythonhosted.org,registry.npmjs.org -NoPause
       .\scripts\deploy\Install-Runner.ps1 -NetworkOnly -Number 4 -Status -NoPause

   -Status should print `firewall  <n> outbound block rule(s), <n> on (group Thornswood PR runner thornswood-runner4)` with n above zero and both numbers equal.

3. Verify on runner 4. Start a build and find the job that `thornswood-vps-4` takes (the build queue is busy, so its next pull request job is as good as a hand-started one):

       gh workflow run build.yml --ref main -f runner=vps
       gh run list --workflow build.yml --limit 5

   For each recent run, the jobs line above shows `runner_name`. Wait until a `Launcher builds (VPS fallback)` job ran on `thornswood-vps-4` and finished `success`. If one fails on a step that reaches the network (pip, npm, git), read its log for the host it could not reach; add it with -AllowHost only if it is a real build need (Windows certificate revocation and timestamp hosts are the likely ones), rerun step 2 with the longer list, and verify again. Watch the next nightly (3:00 AM MT) too, if it lands on runner 4.

4. Collect, to see the outbound row:

       .\scripts\vps\Check-RunnerIsolation.ps1 -Collect -Facts "C:\Thornswood-Repo\temp\2161-runner\runner-facts.json" -Report "C:\Thornswood-Repo\temp\2161-runner\runner-isolation.md"

   The row `network | thornswood-runner4 outbound` reads ok. The other three still read risk.

5. Runners 1, 2 and 3: steps 2 and 3 with `-Number 1`, `-Number 2`, `-Number 3`, one at a time, each verified by a green job on that runner before the next.

6. The two collects for cleanup: run step 4 once after a green VPS build has finished, and once after a VPS build that failed or was cancelled for its own reasons (cancel one in progress if none failed recently; never make one fail on purpose). Each time the `cleanup | <account> _work\_temp` rows should read ok.

7. Record: post the report's risk rows (the report is already redacted) on #2161, and open a pull request putting the account by account reach table into docs/RUNNER-ISOLATION.md section 1 (any Claude session can write it from the report). Close #2161 once both are recorded. Delete `C:\Thornswood-Repo\temp\2161-runner` and this note.

## Risks and how to put it back
- A blocked host a build needs: that runner's builds go red. Put back one account with
  `.\scripts\deploy\Install-Runner.ps1 -NetworkOnly -Number <n> -Remove -NoPause`
  which takes that account's rule group off and nothing else; confirm the next job on that runner is green.
- GitHub's address ranges change. A new range is blocked until step 2 is rerun for that runner (it fails closed: a build goes red, nothing leaks). Rerun the -NetworkOnly line for each runner when that happens.
- The rules match the runner account's SID only. Administrator's ssh, the game servers, the site, voice and the bot are not touched.
- Check-RunnerIsolation and Get-RunnerFacts only read ACLs, names, sizes and dates.

## Release notes (draft)
None. Nothing reaches anyone.

## News post (draft)
None.

## Test task (draft)
None.

## History
- 11 Oct 8:35 PM MT, Claude: not ready, #2285 still open (it merged as b47830fa).
- 12 Oct, Anvil: refreshed against main e34bf423.
- 12 Oct, Claude (anvil-ops): rewritten after the takeover. Added the billing note (#2393), the runner names and how to see which runner took a job, the temp folder, and the offline workflow read (11 rows, 0 risk).
