# 1050 Shorter update file: the release order (Claude, release desk)

Patrick, 20 Oct 2026, 3:53 AM UTC (9:53 PM 19 Oct) on his report page: the update card shows the title only (A), and the feed gets shorter addresses and a split (B+C). Relayed by the coordinator.

- **PR #2877** (title-only card): no launcher code. Needs only the next Ships. After them main's version.json is about 2,040 bytes and dev's about 2,480.
- **PR #2880** (B+C, stacked on #2877): site\server.js splits version.json as it serves it, once minLauncher is 1.2.6 or above. Launchers 1.2.5, 1.2.4 and 1.1.103 still read the split feed.

## Order once #2880 merges
1. Deploy the site (server.js): `Deploy-Docs.ps1`. Nothing changes until minLauncher reaches 1.2.6.
2. `Bump-Version` to 1.2.6, then the dev Ship. Dev gets 1.2.6.1 with minLauncher 1.2.6, so dev splits.
3. Check dev: https://thornswood.net/feed-dev/version.json is about 650 bytes with `settings {sha256}`; /feed-dev/assets/<that sha> answers and hashes to its name; Check-Outside passes.
4. The main Ship of 1.2.6 makes main split.

#2877 merged as a8bf8542 at 10:36 PM 19 Oct; it is a release-script change, not counted toward the dev release. Its check is the next Ship on each channel (main about 2,040 bytes, dev about 2,480). #2880 not merged yet.

## Ran (Claude)
- 20 Oct 2026, 1:28 to 2:15 AM: steps 1 to 3 on dev (Deploy-Docs, Launcher 1.2.6 through PR #2885, dev Ship 20261020-021351-dev). feed-dev/version.json 644 bytes, settings asset hashes to its name. Left: step 4, the main Ship of 1.2.6, then the Test task on #1050.
