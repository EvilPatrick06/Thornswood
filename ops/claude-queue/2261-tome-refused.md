# 2261 A refused spell tome goes back into your pack (gamemode)

**Dev ran 11 Oct 2026: Deploy-DevGamemode at 10:20 PM (gamemode 154aa7bb). #2261 closed with its test task. Left: Deploy-Server.ps1 -GamemodeOnly on live, on Patrick's word.**

Status: QUEUED (lane: Codex). Written 11 Oct 2026. PR #2290 (Refs #2261), squash 748d44e on main. Issue #2261 stays open and claimed until this runs.

## What changed
- game/gamemode.js, mp.onReadBook: a tome refused under the Mage rules (no spell point, not a mage, rank) was already kept on the server, but the reader's own game had removed it from their pack when they read it and was never told otherwise, so it looked consumed. On a refusal the server now sends the reader's pack again as it has it (immediately and once more 750 ms later), so the tome reappears. A learned tome is still spent.
- Test: tests/test-2261-tome-refused.js (Launcher builds).

## Before anything
- Box: ship PC One. Pull first: `git fetch origin; git checkout main; git pull; git status` must be clean at origin/main.
- Do not run Install-Bot until #2158 is fixed. Nothing here needs it.

## 1. What to run
1. Dev: `.\scripts\deploy\Deploy-DevGamemode.ps1`
2. Check on dev: on a character with no spell points (or not a mage), read a spell tome you cannot learn: the refusal line says you keep the tome and it is still in your inventory. Then read one you can learn: the spell is learned and the tome is gone.
3. Live: `.\scripts\deploy\Deploy-Server.ps1 -GamemodeOnly`

## 2. Order and risk
- Gamemode deploys warn and restart the targeted server.
- Low risk: only the refused branch changes. Can share a gamemode deploy with other queued gamemode notes (2260-burn-relog.md).
- After it runs: comment on #2261 with what ran, then close it.

## 3. Draft patch notes
- A spell tome you are not allowed to learn from stays in your pack instead of vanishing.

## 4. Draft Discord post
None needed (Ataxayk could be told on #2261's report thread that refused tomes now stay put).

## 5. Before closing the issue
New rule (9:11 PM 11 Oct): the closing comment must be a test task the bot posts to #test-tasks. First line exactly `Test task:`, an optional `Server: Dev` or `Server: Main` line, then a short plain-English body (no issue numbers, links or code). Draft:

```text
Test task:
Server: Dev
On a character with no spell points or who is not a mage, read a spell tome you are not allowed to learn. You should be told why and the tome should still be in your inventory. Then read a tome you can learn: you learn the spell and the tome is used up.
```

