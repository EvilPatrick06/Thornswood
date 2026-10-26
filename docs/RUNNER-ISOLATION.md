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
| Runners, 22 Oct 2026 | Three, `thornswood-vps`, `-2` and `-3`, from the `runner_name` on their jobs since 9 PM on 21 Oct (eight from 20 Oct, #2929; 6, 7 and 8 removed on 21 Oct at Patrick's ask, #3108; 4 and 5 off at the box restart of 8:45 PM that evening, #3219). 1 and 2 also carry `thornswood-build` and take the heavy jobs (records\build-runners.json, #2994; 1 to 4 until the side-by-side gate, #3114); 3 takes only the light ones (board cards, dropped claims, the nightly's board job, the release jobs, harnesses.yml). 3 is the old 5 installed again clean under that number, with its outbound limits (`-NetworkOnly`) |
| Where | The same Windows VPS that runs both game servers, both voice services, the site, Caddy, the bot, the watchdog and the nightly backup (docs\SERVER.md) |
| Accounts | `thornswood-runner`, `-runner2` and `-runner3`: local users in Users and their GitHub runner groups, not in Administrators. Each runs its `actions.runner.*` service |
| Runner folders | Locked by `scripts\deploy\Install-Runner.ps1` to SYSTEM, Administrators and the runner's account, with nothing inherited from C:\ |
| Production folders | Locked by `scripts\vps\Lock-VpsFolders.ps1`; the runner accounts may write crash dumps to `C:\Thornswood-Dumps` but not read them |
| Repository | Private. Three collaborators can push |
| Fork pull requests | Do not run workflows, get no write token and no secrets (`fork-pr-workflows-private-repos` all false) |
| Default workflow token | read; each workflow also sets its own `permissions` (build: contents read; nightly: contents read, issues write, pull-requests read; release: contents write, on a `v*` tag or by hand; engine: contents read, by hand only; drop-claims: issues write; board-status: issues write, with the board token from the `board` environment, which only main may use; staff-notice: contents read, started by hand, with the notices key named claude from the `notices` environment, which only main may use, and which sshd takes only from 127.0.0.1 and runs only say-staff.ps1 for, #3045; git-ref: contents write and pull-requests read, started by hand, makes only release tags and deletes only a branch at a given commit with nothing open on it, #3107; github-admin: contents read, id-token write and actions read, by hand or a push to main that changes a runner record, holds no secret and hands its OIDC token to the box's admin service on 127.0.0.1:7791, which acts only for that workflow on main and only makes the runners' labels match main's records, #3107, or by hand with `what: settings` only reads the Actions settings, the runners and what names the App may see for records/github-settings.json, changing nothing, while the run's own token, actions read, lists the environments, #3534; clone-report: no permissions, started by hand from One, decodes the clone report it is given and prints it to its log, #3534) |
| Actions sharing | `access_level: none` (no other repository may use these workflows) |
| Allowed actions | all, SHA pinning not required by the setting; the workflows pin every action to a full SHA by their own rule (release.yml) |

## 2. Trust boundaries

1. People who can push (three collaborators) to people who cannot: GitHub.
   Only pushers, and pull requests from branches in this repository, run
   code on the runners. Forks do not.
   A pull request runs the workflow files on its own branch, so its code
   can ask for any label, `thornswood-build` or not. The label split
   decides where jobs go, not what a pusher's branch can reach, which is
   why every runner account gets the outbound limits, the light one (3)
   as well as the build ones.
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
   and signed on One today; decided (Patrick, 11 Oct 2026) to sign in
   release.yml on GitHub's runner through a federated Azure identity
   limited to `v*` tags (docs\SIGNED-RELEASES.md section 8).
7. CI to the engine: engine.yml (#459) records the fork's own build of one
   commit, on GitHub's runner first and on these runners when that is
   refused, and compiles nothing (#3014, #3399), started only by hand,
   with contents read. It sends nothing and
   commits nothing; its records reach main through a pull request.

## 3. Findings

| # | Finding | Evidence | Class |
| --- | --- | --- | --- |
| F1 | Pull request code from any branch in this repository runs on the production box | build.yml: `on: pull_request` and `runs-on: [self-hosted, Windows, thornswood-vps]`. The check reports it as a risk row | Risk while pull request code can run on the VPS; hosted runners become the default (section 6) |
| F2 | Install-Runner.ps1's header says build.yml sends pull requests to the label `thornswood-pr`, which no VPS runner carries. build.yml has never used that label (git log -S finds none) | Install-Runner.ps1 "OFF THE BOX"; build.yml | Resolved by the decision in section 6 |
| F3 | VPS runner accounts have no outbound limit | Install-Runner.ps1 puts firewall rules on with -OffBox, and since #2161 on one VPS runner account at a time with -NetworkOnly; the check counts rules naming each runner SID. On 20 Oct none of 1 to 4 had them (-NetworkOnly -Status). Runner 4 has had them since that evening and ran its builds green after (pip, npm, ruff and eslint all ran) | Risk until the outbound limits in section 6 are on every runner account, measured by the check |
| F4 | A job can read its runner's `.credentials` and leave files for the next job | GitHub's runner design; `_work\_temp` leftovers are counted by the check | Residual, inherent to persistent self-hosted runners |
| F5 | Fork pull requests cannot run here | repository settings above | OK |
| F6 | Runners are not administrators | account groups above | OK, rechecked by every run |
| F7 | Every runner account could read `C:\ProgramData\ssh`, sshd's folder, which the record lists as no-reach | `Check-RunnerIsolation.ps1 -Collect`, 21 Oct 2026 10:37 AM UTC: `read=True write=False` for all eight accounts. Installs and `-Lock` on the box denied only `C:\Thornswood-*` and a hand-given `-AlsoDeny` | Fixed: every install and `-Lock` on the box now also denies the record's no-reach folders outside `C:\Thornswood-*` (`C:\ProgramData\ssh`, `C:\Users\Administrator`); proven by the check's reach rows after `-Lock` |

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

## 6. Decision (Patrick, 11 Oct 2026, final)

Decided by Patrick on 11 Oct 2026, relayed by Smeagle. This replaces the
first write-up of the same day (#2295), which wrongly accepted the missing
outbound limit as residual risk.

1. Outbound limits on the VPS runner accounts. Each runner account may
   reach only what builds need: GitHub (the web, api, git and actions
   ranges) and the package feeds the workflows install from. Everything
   else is blocked. This closes F3. It is a live box change, Claude's, done
   only after the hosting console login is confirmed working (#2182), by
   running `Install-Runner.ps1 -NetworkOnly` (#2161) for each runner
   account: the same outbound rules -OffBox makes, and nothing else
   (`tests\test-runner-offbox.ps1`), not hand written rules.
   The feeds read from the workflows today: `pypi.org` and
   `files.pythonhosted.org` (build.yml and nightly.yml install ruff and the
   bot's requirements with pip, hash pinned), and `registry.npmjs.org`
   (build.yml and nightly.yml install eslint with npm). engine.yml's
   fallback (#459) reads more when it builds on the box: the fork and its
   submodules from GitHub, the sources vcpkg builds each library from, from
   wherever each port fetches them, and yarn's packages from `registry.yarnpkg.com`.
   Its first run on the box is where that list is measured, before these
   limits go on. Measured on 20 Oct 2026 (run 39364911234, thornswood-vps-3,
   the one compile on the box, from an empty cache): besides GitHub,
   mirror.msys2.org, cef-builds.spotifycdn.com, sqlite.org, www.nasm.us,
   download.qt.io, sourceware.org, www.python.org and
   node-embedder-api-prebuilt-vcpkg-port-v2.b-cdn.net. Two of those pass
   each download on to a mirror they pick and two are CDNs, so no address
   list taken in advance holds them, and the limits block a compile on the
   box. On 22 Oct, with the limits on, run 39727871475 stopped before any of
   them, at vcpkg's own cmake from GitHub: Windows' TLS checks each
   certificate with its authority's servers (Let's Encrypt's lencr.org for
   GitHub's release downloads), and the limits block those too. So since
   #3014 (Patrick's A, 22 Oct) engine.yml never compiles on the box: it takes
   the fork's own build, from GitHub alone, or stops before compiling, and a
   pin names a commit the fork built. The limits stay as they are.

   The rollout, one runner account at a time, because a block that misses a
   host turns every build on that runner red: runner 4 first (20 Oct), then
   3, 2 and 1, each proven by a build it then runs green, then 5 to 8, each
   proven by any job it then runs green. 6, 7 and 8 were removed on 21 Oct
   2026 (#3108) with their limits, by `Install-Runner.ps1 -Remove`, and 4
   and 5 at the box restart that evening (#3219); runner 3 today is the old
   5 installed again with `-NetworkOnly`. `scripts\vps\Get-RunnerJobs.ps1`
   reads that off GitHub (every runner carries the same labels, so a build
   cannot be sent to one of them); `-NetworkOnly -Remove` for that one
   account is the way back.
   The signing runner (records\sign-runners.json, runner 3 since #3312)
   also reaches the Microsoft hosts release.yml's sign steps need, each
   held by an Azure service tag in Microsoft's published Service Tags file,
   which that record names; on 22 Oct its rules without them stopped the
   first VPS signing run at api.nuget.org (release.yml run 39838728417).
   Since then every list is read on the box, so a cloud session can run
   `-NetworkOnly` too.
2. GitHub-hosted runners are the default for builds. The VPS runners are a
   backup only: used by hand, or automatically when a hosted run fails
   because the account's Actions minutes or usage ran out. Patrick confirmed
   it on 15 Oct (#2393): the budget is not raised, hosted first, then the VPS.
   build.yml and build-pr.yml wire it that way. Release and Ship jobs stay where they
   are unless the Codex design finds a conflict.

What follows for the check:

- F1 (pull request code on the production box): a fallback job that can
  still run pull request code on `thornswood-vps` is reported as a risk row
  for a person to read, not a failure; the check only fails with -Strict.
  That is deliberate: a backup path on the VPS is allowed by this decision,
  and each run of it should be visible.
- F2 (Install-Runner.ps1 header mismatch): resolved. The header describes
  an off-box pull request runner that build.yml never used; with hosted
  runners as the default, the build check needs no such runner.
- F3 (no outbound limit): risk until Claude's live step above is done; then
  every runner's `outbound` row should read ok.
- Verification: a green build on a VPS runner after the limits are on, and
  the check's network rows ok. Rollback: remove the outbound rule group for
  that account, with `Install-Runner.ps1 -NetworkOnly -Remove`
  for that account.

The three choices that were put to Patrick, kept for the record:
### The choices

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
