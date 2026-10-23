# 3296: NPCs carry on through a dev gamemode reload, and the measurement

Issue: #3296 (Refs #3196, #3181). Pull request: the one that adds
`tests/test-3296-npc-handover.js` and this note. Dev only. Main never reloads
its gamemode in place (a main deploy restarts the server), so nothing here
waits on a main Ship.

What changes: when the dev server loads a new gamemode while it runs, the old
NPC runtime and population hand what they know to the new ones, which go on
from it, when both loads have the same NPC code and catalogue. Before, the new
runtime took the whole cast back from nothing (3 min 50 s after a restart on
22 Oct, not yet measured after a reload).

The issue asks for the reload measured before and after. Two dev deploys give
both, because the first one replaces a gamemode that has no handover:

- Deploy A, this change going onto dev: the old load hands nothing over, so
  this is the full load in a warm process, the "before".
- Deploy B, the next gamemode-only dev deploy after it whose change leaves the
  NPC blocks alone (any later merge): the NPCs carry on, the "after".

## 1. Deploy A (dev, touches the dev server)

From the repository root, on main at the merge commit of this pull request.
Nobody needs to be off: a gamemode-only deploy reloads in place.

```
pwsh scripts/deploy/Deploy-DevGamemode.ps1 "NPCs carry on through a dev update
- After a dev server update to the game's rules, the people and creatures of the world keep doing what they were doing instead of standing still for a few minutes. This starts with the update after this one."
```

Add `-ShipFollows` if a dev Ship carries this change straight after, so the
note is posted once. It should print that the reload loaded the new git blob
(`RELOAD OK`). A restart instead means the reload's own conditions were not
met; the measurement then is a restart's and says nothing about this change,
so write that on #3296 and take the measurement at the next reload.

Then read the dev server.log (read only):

```
pwsh scripts/vps/Remote.ps1 "Select-String -Path 'C:\Thornswood-Server-Dev\server.log' -Pattern 'gamemode.js is git blob','gamemode loaded','Shared NPC' | Select-Object -Last 14 | ForEach-Object Line"
```

Expected after Deploy A: `Shared NPC runtime starts over: the previous
gamemode load handed nothing over`, then `Shared NPC loading complete: <n>
existing identities; cast preserved`, then `Shared NPC activity` minute lines
until about 4,820 active with 0 mesh jobs pending. Take from the log: the
time of the new `gamemode.js is git blob` line, of `Shared NPC loading
complete`, and of the first minute line at the steady active count with 0
mesh jobs. Those two gaps are the "before".

## 2. Deploy B (dev, touches the dev server)

The next gamemode-only `Deploy-DevGamemode.ps1` run for any later merge, with
its own note. Afterwards the same read as above. Expected: no `starts over`
line, and `Shared NPC runtime carried on from the previous gamemode load:
<active> active, <loaded> loaded, <w> waiting off walkable ground, <p>
preparing, 0 mesh jobs pending; loading complete` within a second of the
git blob line, and the next `Shared NPC activity` minute line at the same
active count with 0 mesh jobs pending. No `Shared NPC loading complete` line
follows, because nothing is loaded again.

If B's change did touch the NPC blocks or the catalogue, the log says
`starts over: the previous gamemode load had other NPC code or another
catalogue`, which is right; take the measurement at the deploy after.

## 3. Risks and what to check

- Nothing goes down: a reload keeps everybody connected (#3196).
- A carried load that went wrong shows as NPCs that stand still or a
  `remains loaded; activity unavailable` line for many of them in server.log
  after B. Then: `pwsh scripts/deploy/Deploy-DevGamemode.ps1 -Restart` with
  the same note brings the cast back by a full load, and the log lines go on
  #3296 as a finding.

## 4. Afterwards

Put both measurements (the times and the lines) on #3296 and in
`ops/status.md`, then close #3296 as completed: nobody on main notices the
change, so it takes no `Test task:` comment, and a Desk reading the log is
the check (the Dev test task rule). Delete this note in the batch pull
request.

No news post: the dev deploy's own note says it.
