# 2260 A fire still alight at logout leaves its bad burn (gamemode)

Status: QUEUED (lane: Codex). Written 11 Oct 2026. PR #2282 (Refs #2260), squash 7b3a020 on main. Issue #2260 stays open and claimed until this runs.

## What changed
- game/gamemode.js, injury and disease block: a burn used to be written only when the client sent /burn 0, so logging out while on fire dodged the Bad Burn. A fire with no report for 6 seconds is now settled at its last report, by the next /burn or by the hurt tick, and written as a burn.
- Test: tests/test-2260-burn-relog.js (runs in Launcher builds).

## Before anything
- Box: ship PC One. Pull first: `git fetch origin; git checkout main; git pull; git status` must be clean at origin/main.
- Do not run Install-Bot until #2158 is fixed. Nothing here needs it.

## 1. What to run
1. Dev: `.\scripts\deploy\Deploy-DevGamemode.ps1`
2. Check on dev: stand in a campfire (a lit campfire or a fire pit, not a forge: after #2259 ships a forge no longer sets you alight) for over 5 seconds and log out while still burning, then log back in: the condition shows Bad burn.
3. Live: `.\scripts\deploy\Deploy-Server.ps1 -GamemodeOnly`

## 2. Order and risk
- Gamemode deploys warn and restart the targeted server.
- Low risk: only fires never put out change. Can share a gamemode deploy with any other queued gamemode note.
- After it runs: comment on #2260 with what ran, then close it.

## 3. Draft patch notes
- Logging out while on fire no longer dodges a bad burn.

## 4. Draft Discord post
None needed.
## Claude, 11 Oct 8:35 PM MT
Dev done: Deploy-DevGamemode from main 97409bf7 at 8:24 PM, SWAP OK, posted. Live (Deploy-Server -GamemodeOnly) waits for Patrick's word; put to him.

## 5. Before closing the issue
New rule (9:11 PM 11 Oct): the closing comment must be a test task the bot posts to #test-tasks. First line exactly `Test task:`, an optional `Server: Dev` or `Server: Main` line, then a short plain-English body (no issue numbers, links or code). Draft:

```text
Test task:
Server: Dev
Stand in a lit campfire until you catch fire, keep burning for more than five seconds, then log out while still on fire. Log back in and check your condition: it should show a bad burn.
```

