# 3930 only a run of main's own workflow signs

- **Lane:** Claude (cloud thread, 27 Oct)
- **Issue / PR:** #3930 and #3890, the pull request that adds this note (#3924)
- **Channel:** GitHub settings (the `release` environment) only; no game server, site, bot, voice or box change
- **Staff status updates:** none (nothing staff see or do changes)
- **Needs first:** step 1 runs BEFORE the pull request merges. After the merge, release.yml asks for the `release` environment only in a run on `refs/heads/main`, and today the environment's deployment rule allows `v*` tags alone (docs/SIGNED-RELEASES.md section 7, read 12 Oct), so until main is added every signed release fails at the environment. Steps 1 and 3 need gh signed in as a repository admin: the cloud proxy refuses `repos/.../environments` (measured on #3890), so they run on One, from the Local Desk. Step 2 is the merge. Step 4 runs anywhere.

## Run
From any folder, in PowerShell 7, on One.

1. **Before the merge.** Read the `release` environment's rule, then let the branch main use it as well as the `v*` tags it has:

       gh api repos/EvilPatrick06/Thornswood/environments/release --jq '{policy: .deployment_branch_policy, rules: [.protection_rules[].type]}'

   It should print `"custom_branch_policies":true` and `"protected_branches":false`. If the policy is `null` or `protected_branches` is `true`, stop here and write what it printed into this note and on #3930: the rule is not what section 7 recorded, and changing its kind is a PUT of the whole environment, which is not written here.

       gh api repos/EvilPatrick06/Thornswood/environments/release/deployment-branch-policies --jq '.branch_policies[] | {id, name, type}'

   It should list `{"name":"v*","type":"tag"}` with its id. Keep that id for step 3.

       gh api -X POST repos/EvilPatrick06/Thornswood/environments/release/deployment-branch-policies -f name=main -f type=branch --jq '{id, name, type}'

   It must print `"name":"main","type":"branch"` and a new id. Then tell the coordinator the pull request may merge.

2. The Cloud Desk merges the pull request once `Launcher builds (VPS fallback)` is green.

3. **Right after the merge.** Take the `v*` tag rule off, so a tag's own copy of release.yml can no longer reach the identity:

       gh api -X DELETE repos/EvilPatrick06/Thornswood/environments/release/deployment-branch-policies/<the v* id from step 1>
       gh api repos/EvilPatrick06/Thornswood/environments/release/deployment-branch-policies --jq '.branch_policies[] | {name, type}'

   The second line must print `{"name":"main","type":"branch"}` and nothing else.

4. The proof, on the next release (a dev or main Ship that carries a new launcher, or a pilot tag on main): the tag push run of release.yml has one job, `Hand the tag to main's release workflow`, on a build runner (`thornswood-vps-1` or `-2`), green, and its log says `started main's release.yml for v<number>`. Then a run titled `Release launcher v<number>` with head branch `main` builds, signs and verifies:

       gh run list --repo EvilPatrick06/Thornswood --workflow release.yml --limit 4 --json databaseId,displayTitle,headBranch,event,conclusion
       gh api repos/EvilPatrick06/Thornswood/actions/runs/<the main run's databaseId>/jobs --jq '.jobs[] | {name, runner_name, conclusion}'

   The main run's build job is green with a `Sign the launcher` step that succeeded, `Check the signed draft on a second machine (VPS)` is green, and the draft's notes say `the launcher signed by ThornswoodRelease`. A build job that says `Branch "main" is not allowed to deploy to release` means step 1 did not take.

## Risks
- Between the merge and step 1, if step 1 was skipped, no release signs: the build stops at the environment, visibly, and nothing unsigned is published (Ship refuses an unsigned launcher). Step 1 first avoids it.
- Between step 1 and step 3 both main and `v*` tags may use the environment, which is today's state plus main: no wider than now.
- A run of release.yml on a tag ref made before the merge (a manual `--ref v<tag>` run) builds unsigned after step 3. Every starter in the repository now asks for `--ref main` (release-tag.yml, Sign-OnGitHub.ps1, Ship's message, docs/SIGNED-RELEASES.md).

## Afterwards
Put what ran, when, what it printed and the proof on #3930 and in `ops/status.md`. Close #3930 and #3890 (no test task: nothing in the game changes), and delete this note. Once #3908 is in, `release` joins `mainOnlyEnvironments` in `records/runner-isolation.json` (noted on #3923).
