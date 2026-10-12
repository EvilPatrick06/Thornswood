# GitHub Actions runner isolation on the VPS (issue #2161)

Status: THREAT MODEL AND READ-ONLY CHECK. Nothing about the runners was
changed to write this: no runner, account, ACL, firewall rule, workflow,
repository setting or credential. No exploit was tried. Section 1 is what
was read on 11 Oct 2026, from the GitHub API (GET only) and from the box
over ssh, read-only, during #2182. The full per-path picture comes from the
first run of `scripts\vps\Check-RunnerIsolation.ps1 -Collect`, which is
queued for Claude. The one decision only Patrick can make is in section 6.

## 1. What is there

| What | Read |
| --- | --- |
| Runners | Four, `thornswood-vps`, `-2`, `-3`, `-4`, all online, labels `self-hosted, Windows, X64, thornswood-vps` |
| Where | The same Windows VPS that runs both game servers, both voice services, the site, Caddy, the bot, the watchdog and the nightly backup (docs\SYSTEM.md) |
| Accounts | `thornswood-runner`, `-runner2`, `-runner3`, `-runner4`: local users in Users and their GitHub runner groups, not in Administrators. Each runs its `actions.runner.*` service |
| Runner folders | Locked by `scripts\deploy\Install-Runner.ps1` to SYSTEM, Administrators and the runner's account, with nothing inherited from C:\ |
| Production folders | Locked by `scripts\vps\Lock-VpsFolders.ps1`; since #2106 the runner accounts may write crash dumps to `C:\Thornswood-Dumps` but not read them |
| Repository | Private. Three collaborators can push |
| Fork pull requests | Do not run workflows, get no write token and no secrets (`fork-pr-workflows-private-repos` all false) |
| Default workflow token | read; each workflow also sets its own `permissions` (build: contents read; nightly: contents read, issues write, pull-requests read; release: contents write, on a `v*` tag or by hand; drop-claims: issues write) |
| Actions sharing | `access_level: none` (no other repository may use these workflows) |
| Allowed actions | all, SHA pinning not required by the setting; the workflows pin every action to a full SHA by their own rule (release.yml) |

## 2. Trust boundaries

1. People who can push (three collaborators) to people who cannot: GitHub.
   Only pushers, and pull requests from branches in this repository, run
   code on the runners. Forks do not.
2. A job to its runner: none. A job runs as the runner's account and can read
   the runner's own `.credentials` (GitHub's design, Install-Runner.ps1 says
   so). A job can affect the next job on the same runner through anything it
   leaves in the runner's folder.
3. A runner account to production: the ACLs. Production folders deny or omit
   the runner accounts; the check reads every listed production path's ACL
   for each runner.
4. A runner account to production services: loopback. Every local account,
   a runner's included, can open the site on 127.0.0.1:3001 and voice on
   7778 and 7789 like Caddy does. Those services authenticate what matters
   (join tokens, the bot key), so this is reach, not control.
5. A runner account to the internet: nothing on the box limits it. The
   off-box pull request runner (`Install-Runner.ps1 -OffBox`, #1306) blocks
   everything but GitHub; the VPS runners have no such rules.
6. CI to release: release.yml runs on the same runners with contents write,
   only on a `v*` tag push or by hand. Its output is checked by SHA256SUMS
   and signed off the box (docs\SIGNED-RELEASES.md).

## 3. Findings

| # | Finding | Evidence | Class |
| --- | --- | --- | --- |
| F1 | Pull request code from any branch in this repository runs on the production box | build.yml: `on: pull_request` and `runs-on: [self-hosted, Windows, thornswood-vps]`. The check reports it as a risk row | Risk, see section 6 |
| F2 | Install-Runner.ps1's header says build.yml sends pull requests to the label `thornswood-pr`, which no VPS runner carries. build.yml has never used that label (git log -S finds none) | Install-Runner.ps1 "OFF THE BOX"; build.yml | Stale documentation, or the move was never finished: depends on F1's decision |
| F3 | VPS runner accounts have no outbound limit | Install-Runner.ps1 puts firewall rules on -OffBox only; the check counts rules naming each runner SID | Risk, measured by the check |
| F4 | A job can read its runner's `.credentials` and leave files for the next job | GitHub's runner design; `_work\_temp` leftovers are counted by the check | Residual, inherent to persistent self-hosted runners |
| F5 | Fork pull requests cannot run here | repository settings above | OK |
| F6 | Runners are not administrators | account groups above | OK, rechecked by every run |

## 4. Cleanup, success and failure

GitHub's runner empties `_work\_temp` at the start and end of each job, on
success and failure, and keeps `_work\<repo>` checkouts between jobs
(`actions/checkout` with `clean: true` resets them). The check counts files
left in `_work\_temp` and the age of the oldest on every runner; anything
older than `tempMaxHours` (24) in `records\runner-isolation.json` is a risk
row. Run after a green build and after a failed or cancelled one to cover
both paths (the vault note says how, without making a build fail on purpose
against production).

## 5. What the check does

`scripts\vps\Check-RunnerIsolation.ps1 -Collect` runs
`scripts\vps\Get-RunnerFacts.ps1` and `scripts\vps\Get-ProdFacts.ps1`
(#2165) on the VPS, both read-only, and reads the Actions settings above with
GET calls. Without -Collect it compares a saved facts file with the record
and the workflow files, offline (`tests\test-runner-isolation.ps1`). Rows
are ok, intentional (with the record's reason) or risk. It never records a
file's contents, a setting's value or a token, and refuses to write a report
holding anything shaped like a secret. Rights are read from ACLs, not from
Windows' effective access check.

Owner: the Installer lane owns the scripts and the record. Claude runs
`-Collect` after any `Install-Runner.ps1` or `Lock-VpsFolders.ps1` run and
monthly.

## 6. Decision needed (Patrick)

Residual risk acceptance. Today pull requests from branches in this
repository run on the production box (F1), with no outbound limit (F3).
Three choices, none made here:

1. Accept it as is: three trusted pushers, a private repository, forks shut
   out, runners not admins, production folders locked. Record that
   acceptance and the date in this section.
2. Finish the move #1306 began: send pull requests to an off-box runner
   (`thornswood-pr`), keep pushes to main, nightly and release on the VPS.
   Owner: Installer lane; rollback: put the label back in build.yml.
   Verification: the check's F1 row turns ok.
3. Keep pull requests on the VPS but add the -OffBox outbound rules to the
   VPS runner accounts. Owner: Installer lane; rollback: `Install-Runner.ps1
   -Remove` of the rule group; verification: the F3 rows turn ok.

No follow-up issue is filed by this change; whichever choice is made gets
its own issue then.
