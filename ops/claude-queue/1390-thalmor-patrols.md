# 1390 + 2697 Thalmor patrols on the roads, with a cap per world stage

Issues: https://github.com/EvilPatrick06/Thornswood/issues/1390 and https://github.com/EvilPatrick06/Thornswood/issues/2697
Designs: https://github.com/EvilPatrick06/Thornswood/issues/1390#issuecomment-6248107602 and https://github.com/EvilPatrick06/Thornswood/issues/2697#issuecomment-6248523772
Lane: Herald. PR: https://github.com/EvilPatrick06/Thornswood/pull/2698 (HELD 1.2.4 draft, branch herald/1390-thalmor-patrols, tip fdbf9172).

## Why this is in the queue

The PR touches game\:
- the NPC population policy;
- the NPC startup;
- a new Thalmor patrols block, placed after the custom quests block;
- a new game\data\thalmor-patrols.json.

That makes it a held draft under the freeze. Lanes don't run Ship, Deploy or live steps. No engine change and no fork PR.

## Merge order and conflicts (post-1.2.4, Codex's order)

Codex test-merged each step in sequence against main 518d9c05 (https://github.com/EvilPatrick06/Thornswood/pull/2698#pullrequestreview-5562552498 and the room). Update branches via REST, never rebase. Squash-merge #2698 once "Launcher builds (VPS fallback)" is green on its updated branch.

1. #2685 (Wyrd, world stage register): clean. It goes first because #2697 reads worldStage() and stages().
2. #2698 (this PR). Against #2685:
   - .github/workflows/build.yml and build-pr.yml: neighbouring harness lines, keep both.
   - docs/systems/thalmor.md needs a real edit, not keep-both: drop #2685's paragraph "No patrol is spawned by the server yet. ..." and reword its closing "The patrols above are #1390's, and the war does not change their numbers." to say the war can change their numbers: staff may give each world stage its own cap (stageMost in game/data/thalmor-patrols.json, #2697), read at each start. W3 in the harness fails if the "No patrol is spawned" line survives.
3. #2694: in the SHIPPED list of tests/test-2582-nothing-personal-served.js, keep both property-word.json and thalmor-patrols.json.
4. #2693: clean.
5. #2699 (Wyrd): one conflict in gamemode.js's never-typed words list, keep both '/furniture' and '/hairdye'.
6. #2684: clean.
7. The stack under #2688: #2651, then #2663, #2670 and #2674. #2651 is claude/2351-release-registers, so that part is up to its owners.
8. #2678: clean.
9. #2688, retargeted to main. Against main expect:
   - gamemode.js, two conflicts: keep both whole blocks after "end thornswood season"; in save(), take #2694's dropbox/word fields plus #2688's return true.
   - Wipe-Saves.ps1: keep the stack's $Moves and add #2693's private\furniture.json.
   - GAMEMODE.md: take #2688's private row.

Stage id rule, must stay matched: stageMost keys here are 1 to 32 of a-z, 0-9 and - (/^[a-z0-9-]{1,32}$/, gamemode.js thalmorPatrolTable). Wyrd is changing #2685 so its stage ids get the same 32-character rule and its stage list refuses longer ids. If either side's rule changes, change the other with it; S5 in the harness pins this side.

## Steps for Claude (dev only, after the freeze)

1. Run Deploy-DevGamemode. game\data\thalmor-patrols.json has to reach the server folder next to gamemode.js, the way guild-sites.json does. If it doesn't, the log says "[patrols] game/data/thalmor-patrols.json would not read, so no patrol is stood up or taken down", and nothing else happens.
2. With the file as shipped (on: false), the dev log should have "[patrols] off - stage peace cap 3 - 0 road(s) may stand; 0 stood up, 0 already there, 0 taken down". It says "stage (none)" if #2685 isn't on dev yet.
3. Set "on": true in the dev server's copy of the file, then restart dev or reload the gamemode.
   - The log should say "on - stage peace cap 3 - 3 road(s) may stand; 12 stood up". The private folder gets thalmor-patrol-slots.json with 4 slots each for pale, haafingar and hjaalmarch.
   - Visit each road: the Pale near (42300, 60500), Haafingar near (-96250, 90600), Hjaalmarch near (-55150, 60200). There should be four Thalmor Justiciars that keep to their stretch of road and fight.
   - Kill one. It should come back at its point after 45 minutes, and no second group should appear. The body can't be opened and gives no coin.
   - Restart dev. The log should say "0 stood up, 12 already there".
4. Stage cap check: set "stageMost": {"peace": 1} and restart. The log should say "stage peace cap 1 - 1 road(s) may stand; ... 8 taken down", leaving only the Pale group. Set it back to {} and restart: 8 stood up again.
5. Unknown stage key check: set "stageMost": {"peaec": 1} and restart. The log should say "[patrols] stageMost names peaec but the world stage list has no such stage, so that cap is never used" once, and the cap stays 3. Set it back to {}.
6. Put "on" back to false on dev and restart. The log should say "12 taken down".
   If the world stage register ever fails at a start, the log says "[patrols] the world stage register failed (...), so no patrol is stood up or taken down", and the members already out stay as they are.
7. If a member falls through the ground or never moves at a point, note the road and slot on #1390. Points are staff data, so the fix is a new point in the file.
8. Main ships with the file off. Nothing changes there until staff turn it on.

## Settings

All of them are staff data in game\data\thalmor-patrols.json:
- on (false)
- most (3)
- stageMost ({}; a cap per war-stages.json stage id, 0 to 10)
- returnMinutes (45) and leash (1536), which a road can override
- tier (null)
- roads, each with an id, a name, its own on, world (3c:Skyrim.esm), bases and points (2 to 4)

The stage is read once per start or reload, through worldStage().id only (stages() is read once too, only to log stageMost keys it does not list), so a stage move staff confirm takes effect the next time the gamemode loads.

## Release and wipe

private\thalmor-patrol-slots.json holds only road, slot and form id, and names nobody. Wipe-Saves doesn't need it: if the world is wiped, the forms are gone, and the next start fills the same slots again.