# 2163 Signed releases: hosted pilot, switch-over, phase B on dev

**Rewritten 18 Oct 2026, about 10:30 PM MT, by Claude's "Hosted release signing" thread. Everything older in this note was out of date and is gone; #2163's comments keep the history.**

Status: WAITING on GitHub's hosted minutes (Patrick's 3.A, 18 Oct). Issue #2163 stays open, claimed: Claude.

## Where it stands

- Why every hosted run failed (12 Oct runs 38309982460 and 38313723433, and the 18 Oct pilot run 39192804622): GitHub refuses the hosted job on billing before any step runs ("recent account payments have failed or your spending limit needs to be increased"). No code was at fault. The repository is private and the spending limit is $0, so GitHub refuses instead of charging.
- Patrick, 18 Oct (3.A): keep pull request builds on the VPS (`BUILD_RUNNER=vps`) so the free minutes go to release builds, and pilot when they are back. Whether they are used up for the month or blocked by a failed payment is on his billing page; he will look.
- #2756 merged: a draft's notes describe the files a later run put in it, and the VPS notes say MSBuild.
- Phase B (the signed release manifest) merged 19 Oct as #2808 (956cdae3). It reaches dev with the next dev Ship, which is the first to sign a manifest (step 3 below, ready now).

## What to run, in order

1. **The hosted pilot**, once Patrick says the minutes are back, or the billing month turns over. Tag on main's commit, so no `expected_sha`:
   - `git tag v0.0.2163-pilot3 origin/main` then `git push origin refs/tags/v0.0.2163-pilot3` (leaves the machine). The push starts the usual VPS build. **Let it finish. Never cancel a VPS job**: a cancel during checkout leaves git locks that break that runner (#2751).
   - `gh workflow run release.yml --ref v0.0.2163-pilot3 -f tag=v0.0.2163-pilot3 -f runner=hosted` (leaves the machine).
   - Pass: the hosted job's log says "building with MSBuild on a github-hosted runner", the Azure sign in, "signed by" ThornswoodRelease; `verify` is green; the draft's notes say signed. Rename the draft "PILOT 2163, not a release" while it exists. Then delete the draft (`gh api -X DELETE repos/EvilPatrick06/Thornswood/releases/<id>`) and the tag (`git push origin --delete refs/tags/v0.0.2163-pilot3`).
   - Refused on billing again: delete the VPS draft and the tag, write the date here and on #2163.
2. **The switch-over PR**, after a green pilot (docs/SIGNED-RELEASES.md section 7): the hosted job's `if` becomes `${{ vars.BUILD_RUNNER != 'vps' && inputs.runner != 'vps' }}`, the runner input's default becomes hosted, and the two "until the switch-over" checks in tests/test-release-workflow.ps1 change. Note: while `BUILD_RUNNER` is `vps` (Patrick's 3.A) releases stay on the box even after it, so this also needs a way for releases to go hosted while pull requests stay on the VPS. That is a release.yml change to its own `if`, not `BUILD_RUNNER`.
3. **Phase B on dev**: after the manifest PR merges, the next dev Ship signs one catalog more. Check the dev feed names `signedManifest`, and that both files answer at `/feed-dev/assets/<sha256>`.

## Still not done, outside this note

- Runner 2's stale git locks (#2751): cleared 19 Oct, 11:02 AM MT. The cause (cancel in progress on persistent runner workspaces) stays open on #2751.
- Minutes: 3,000 of 3,000 used on 19 Oct, reset in 13 days (about 1 Nov). Storage: #2834 (19 Oct) stopped the unread exe artifact that held 1.30 GB of the 2 GB.

## What changes once hosted signing is the default

- A main Ship no longer signs the launcher on One; it takes the signed launcher from the draft.
- One still signs: the installer (Package signs the finished Setup after the OneFile attach) and, from phase B, each release's manifest catalog. So `records\signing\signing.json` stays on the shipping machine, and the project instructions about it stay true.

## Draft patch notes

None yet. At the switch-over: "The launcher you download is now built and signed by our build service, and its checksum is published with it."
