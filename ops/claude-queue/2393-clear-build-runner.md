# 2393 Clear BUILD_RUNNER (restore hosted-first)

- **Lane:** Codex (GitHub / CI)
- **Issue / PR:** #2393 (closed via #2548 as e8bf7c9e). Policy docs already say hosted first, VPS when hosted has no usage. This note only clears the temporary force.
- **Channel:** GitHub repo settings only (Actions variable). No Ship, no deploy, no VPS, no Discord.
- **Staff status updates:** #staff-updates (1549254991082946570)
- **Needs first:** nothing. Patrick asked for Claude to clear it (15 Oct 2026).

## Current state
Repo variable `BUILD_RUNNER` on `EvilPatrick06/Thornswood` is still **`vps`** (set 12 Oct for the #2393 billing skip). While it is `vps`, build.yml / build-pr.yml / release.yml skip the hosted Windows job and stay on the VPS, even when free hosted minutes exist. Clearing it restores hosted-first -> VPS fallback.

Confirmed just before this note: `gh variable list --repo EvilPatrick06/Thornswood` shows `BUILD_RUNNER	vps`.

## Run
From any machine with `gh` signed in as an account that can manage Actions variables on EvilPatrick06/Thornswood (Claude on One is fine):

1. Confirm it is still forced:

       gh variable list --repo EvilPatrick06/Thornswood

   Expect a row `BUILD_RUNNER` with value `vps`.

2. Delete the variable (this is the clear; do not set it to empty string):

       gh variable delete BUILD_RUNNER --repo EvilPatrick06/Thornswood

3. Confirm it is gone:

       gh variable list --repo EvilPatrick06/Thornswood
       gh api repos/EvilPatrick06/Thornswood/actions/variables/BUILD_RUNNER

   The list must not show `BUILD_RUNNER`. The API call should return 404 / Not Found.

4. Optional smoke: start a main build and confirm the hosted job is attempted (not skipped solely because of BUILD_RUNNER):

       gh workflow run build.yml --ref main
       gh run list --workflow build.yml --limit 3

   Hosted may still skip or fail on billing/quota; that is fine -- the VPS fallback job is meant to pick those up. The point is the force-to-VPS override is gone.

5. Record on #2393 (or a short staff-updates line): variable cleared, when, and that hosted-first is live again. Then delete this note.

## Check afterwards
- `BUILD_RUNNER` is absent from `gh variable list`.
- Workflow comments in `.github/workflows/build.yml` (and build-pr.yml / release.yml): hosted runs when `vars.BUILD_RUNNER != 'vps'`; VPS fallback still runs when hosted fails, when a manual run asks for `runner: vps`, or if someone sets `BUILD_RUNNER=vps` again on purpose.
- Nothing in the freeze paths (game\, records\, etc.) is touched.

## Risks and how to put it back
- **Hosted still out of minutes / billing:** builds try hosted first, then fall through to VPS. Slightly more noise and a failed/skipped hosted job before the green VPS fallback. That is the designed path, not a break.
- **Want VPS-only again** (hosted outage, or Patrick says so): put the force back with

       gh variable set BUILD_RUNNER --repo EvilPatrick06/Thornswood --body vps

  That restores the previous VPS-only override. Do not leave a blank value; delete or set explicitly to `vps`.
- This does not change workflow YAML, secrets, runners, or Ship. It only removes the temporary force that replaced hosted-first.

## Release notes (draft)
none (CI routing only)

## News post (draft)
none

## Test task (draft)
none