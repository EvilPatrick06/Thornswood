# 1382 Water activators at wells, rivers and lakes (content plugin)

- **Lane:** Claude (from Codex, 12 Oct)
- **Issue / PR:** #1382, server side merged in #2477 as 383c7557 (from Codex's #2428). What the content build needs, measured, is on #1382 (issuecomment-6134003171).
- **Approved:** Patrick, 12 Oct 2026 (via Smeagle): activators at the wells and at river and lake drawing spots.
- **Kind:** a content-plugin build for Claude. No gamemode deploy from this note.

## Why

Water is collected in the world, never by a command. The 30 vanilla wells are statics, and standing in water raises nothing, so the server never hears either (#1382, issuecomment-6129142274). Something activatable has to be there. #2428 already fills a bottle when somebody activates a listed activator base (NEEDS.wellActivators in game/gamemode.js, empty today).

## What to build

1. One activator at each of the 30 wells in game/data/wells.json (cell or world, x, y, z, from scripts/dev/Build-WellTable.py), at the well, activatable from the normal activation range.
2. Activators at river and lake drawing spots: banks, docks and shores where a person can reach the water. Spot choice is Claude's.
3. Each activator says its water kind, by its base or a keyword: well, river or lake. Well water is safe. River and lake water must be boiled before it is safe.
4. Put the activator base form ids (or the keyword ids) in this note or on #1382 when they exist. Codex then fills in the server list by kind and adds a test; that is a lane PR, not part of this build.

## Run

Content build through the usual plugin route, Dev first, on Patrick's go for the content release. No Main until Dev is checked.

## Check on Dev

- At a well, activate with an empty wine bottle: it fills and the chat says it is clean. Again at the same well: refused with the minutes left. Another well: works.
- At a river or lake spot, activate with an empty bottle: it fills and the chat says to boil it. Activate a cooking pot and stay a minute: boiled.
- Activating with no empty bottle says so.

## Risks

- Cell edits at wells, riverbanks and docks can clash with other plugins in the load order that touch the same cells.
- ElysiumEstateSSE.esp is in plugins.txt but not in One's Data folder, so a well it moves was not read into wells.json. Rerun Build-WellTable.py where it is installed if that matters.
- An activator placed badly can block a path or sit under water or terrain; check each on Dev.
- Until the server list is filled in (the follow-up lane PR), the activators do nothing.
- Frostreach ice water quenches 20, a placeholder until Patrick answers.

## Draft release notes

Fill an empty bottle at any village or farm well, or at a riverbank or lakeshore. Well water is clean. River and lake water must be boiled at a cooking pot first. Each well gives you water once a day.

## Draft news post

Thirsty work. Look for drawing spots on rivers and lakes, and at the wells in towns and farms. Fill an empty bottle there. Well water is safe to drink; river and lake water will make you ill unless you boil it, so take it to a cooking pot and stay by the fire for a minute. Each well only fills your bottle once a day, so plan your route.