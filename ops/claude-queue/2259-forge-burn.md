# 2259 A crafting station warms you and no longer sets you on fire (client plugin)

**Dev ran 11 Oct 2026 in dev Ship 20261011-221215-dev at 10:12 PM. #2259 closed with its test task. Left: the next main client release, on Patrick's word.**

Status: QUEUED (lane: Codex). Written 11 Oct 2026. PR #2287 (Refs #2259), squash 7193595 on main. Issue #2259 stays open and claimed until this runs.

## What changed
- game/plugins/thornswood-front.js (client): sitting down at a forge, skyforge, smelter, kiln or cooking spit counted as standing in the coals, so the Whiterun forge set people alight and gave a Bad Burn within seconds. The 11 crafting station rows in FIRE_BASES are now marked 'craft': they still warm you, but only a real flame (campfire, fire pit, brazier) can set you on fire.
- tests/test-2259-forge-burn.js (Launcher builds) fails if the marks drift from game/data/fires.json, so a Build-FireTable rebuild cannot undo it. tests/test-temp.js updated for the marked rows.
- No gamemode or server change.

## Before anything
- Box: ship PC One. Pull first: `git fetch origin; git checkout main; git pull; git status` must be clean at origin/main (the fresh checkout guard refuses otherwise).
- Do not run Install-Bot until #2158 is fixed. Nothing here needs it.

## 1. What to run
1. Dev: `.\scripts\release\Ship.ps1 -Channel dev "<notes>"` (use the patch note below). Ride along with the next dev ship if one is planned.
2. Check on dev: use the forge by Whiterun's gate for 20 seconds: no "you are standing in the fire", no burning, no Bad Burn, and the temperature still warms. Then step into a campfire: you still catch fire.
3. Live: the next main client release (`.\scripts\release\Ship.ps1` on the main channel, as usual for a client release). Patrick decides when.

## 2. Order and risk
- Client only: people get it with the next launcher update; no server restart needed.
- Low risk. If a forge's flames are a separate fire effect placed right next to the station, standing in those flames can still burn, which is intended.
- Pairs with #2260 (gamemode, claude-queue/2260-burn-relog.md); either order works.
- After it runs on live: comment on #2259 with what ran, then close it.

## 3. Draft release note
- Using a forge, smelter or cooking spit no longer sets you on fire. They still keep you warm.

## 4. Draft news / Discord post
Smiths, rejoice: the Whiterun forge no longer sets you on fire when you use it. Forges, smelters and cooking spits still keep you warm on a cold night, but only an actual fire will burn you now.

## 5. Before closing the issue
New rule (9:11 PM 11 Oct): the closing comment must be a test task the bot posts to #test-tasks. First line exactly `Test task:`, an optional `Server: Dev` or `Server: Main` line, then a short plain-English body (no issue numbers, links or code). Draft:

```text
Test task:
Server: Dev
Go to the forge by Whiterun's front gate and use it for about twenty seconds. You should stay warm but never catch fire or get a burn. Then step into a lit campfire: you should catch fire as before.
```

