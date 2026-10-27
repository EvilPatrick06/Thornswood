# 3889 the signing runner refuses any job but main's

- **Lane:** Claude (cloud thread, 27 Oct)
- **Issue / PR:** #3889, the pull request that adds this note
- **Channel:** the box (runner 3 only); no game server, site, bot or voice change
- **Staff status updates:** none (nothing staff see or do changes)
- **Needs first:** this pull request merged, and #3908 (#3550) merged. #3908 holds every job a workflow on main can send to runner 3 to main or a v tag, and since #3930 release.yml sends no tag's job there (a tag push is handed to main's workflow), so main's jobs are all runner 3 takes; until it is in, harnesses.yml dispatched on a branch can still land on runner 3, and with the hook on that job would be refused and fail instead of running. Steps 1 and 2 need One (ssh to the box, and gh signed in as a repository admin for the registration token, which the cloud proxy refuses). Steps 3 and 4 run anywhere.

## Run
From a clean checkout of main with this pull request in it, in PowerShell 7.

1. On One, when runner 3 is not running a job (no release.yml run in progress; `.\scripts\deploy\Install-Runner.ps1 -Number 3 -Status -NoPause` says `thornswood-vps-3, online` with no `running a job`), install runner 3 again. This touches runner 3 alone: the account keeps its name and gets a new password, the service is made again, and the hook and its `.env` line are written and read back before the service first starts. A job runner 3 is running is stopped, which is why it waits for idle.

       .\scripts\deploy\Install-Runner.ps1 -Number 3 -NoPause

   It must print `C:\ProgramData\Thornswood-RunnerHooks\job-started.ps1: the signing runner's job-started hook, which only SYSTEM and Administrators may change`, then `C:\Thornswood-Runner3 now refuses any job but main's, through C:\ProgramData\Thornswood-RunnerHooks\job-started.ps1` (or `... already`), `service Running`, `thornswood-vps-3 is online`, and in the lock of every runner after it, `C:\Thornswood-Runner has no job-started hook, as a runner that does not sign already` and the same for `C:\Thornswood-Runner2`. Any `HOOK NOT WRITTEN` or `HOOK NOT SET` line is a failure: the hook is not on, and what it printed is the cause to fix.

2. Read it back:

       .\scripts\deploy\Install-Runner.ps1 -Number 3 -Status -NoPause

   It must print `hook      C:\ProgramData\Thornswood-RunnerHooks\job-started.ps1, refuses any job but main's (#3889)`.

3. The proof that it refuses, which is the measurement #3889's step 1 asked for. From any machine, push a throwaway branch with one workflow that asks for runner 3 and has a step marked `if: always()`:

       git checkout -b claude/proof-3889 origin/main
       New-Item -ItemType Directory -Force .github/workflows | Out-Null
       Set-Content -Encoding utf8 .github/workflows/proof-3889.yml "name: Proof 3889`non:`n  push:`n    branches: [claude/proof-3889]`npermissions:`n  contents: read`njobs:`n  proof:`n    runs-on: [self-hosted, Windows, X64, thornswood-vps, thornswood-sign]`n    timeout-minutes: 5`n    steps:`n      - run: Write-Output 'STEP-RAN'`n      - if: always()`n        run: Write-Output 'ALWAYS-STEP-RAN'`n"
       git add .github/workflows/proof-3889.yml
       git commit -m "Proof for #3889: a branch's workflow asks for the signing runner"
       git push -u origin claude/proof-3889

   Then read the run it started (a minute or so once runner 3 is free):

       gh run list --repo EvilPatrick06/Thornswood --branch claude/proof-3889 --limit 1 --json databaseId,conclusion,status
       gh api repos/EvilPatrick06/Thornswood/actions/runs/<databaseId>/jobs --jq '.jobs[] | {runner_name, conclusion, steps: [.steps[] | {name, conclusion}]}'
       gh run view <databaseId> --repo EvilPatrick06/Thornswood --log-failed

   It must show `runner_name` `thornswood-vps-3`, the job's `conclusion` `failure`, a `Set up runner` step that failed, and no step after it with `conclusion` `success`. The log must hold `REFUSED on the signing runner (#3889): it runs refs/heads/claude/proof-3889`, and neither `STEP-RAN` nor `ALWAYS-STEP-RAN` anywhere (`gh run view <databaseId> --repo EvilPatrick06/Thornswood --log | Select-String 'STEP-RAN'` prints nothing). If `ALWAYS-STEP-RAN` is there, the hook failed the step but did not end the job: that is a finding for #3889 with the log, not a pass.

   Then take the branch off GitHub (a cloud thread cannot delete a branch with git, #3107):

       pwsh scripts/ops/Set-Ref.ps1 -DeleteBranch claude/proof-3889 -Commit (git rev-parse claude/proof-3889)

4. The proof that it still takes main's jobs: the next job of main on runner 3 (`gh api "repos/EvilPatrick06/Thornswood/actions/runs?branch=main&per_page=20" --jq '.workflow_runs[].id'`, then each run's jobs as in step 3, until one has `runner_name` `thornswood-vps-3`) must have `conclusion` `success`, and its `Set up runner` log must say `The signing runner takes this job: EvilPatrick06/Thornswood/.github/workflows/<file>@refs/heads/main is main's (#3889).`

## Risks
- Step 1 stops a job runner 3 is running, so it waits for idle. The service is down for the few seconds config.cmd takes; GitHub hands a waiting light job to runner 1 or 2 meanwhile, and a waiting signing job waits for runner 3.
- After it, any job on runner 3 that is not main's fails at `Set up runner`. With #3908 in, no workflow on main sends one there.
- Runner 3 keeps the folder and profile it had: branch jobs ran there before #3550 (nine harnesses.yml runs of claude/* branches, 22 to 26 Oct). A clean slate needs `-Remove`, a box restart for the profile (A REMOVED ACCOUNT'S PROFILE in Install-Runner.ps1), and an install; this note does not do that.

## Afterwards
Put what ran, when, what it printed and both proofs on #3889 and in `ops/status.md`, close #3889 (no test task: nothing in the game changes), and delete this note.
