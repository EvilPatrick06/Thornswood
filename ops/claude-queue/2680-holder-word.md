# 2680 word to a holder when their door is picked or their deed is presented

Issue: https://github.com/EvilPatrick06/Thornswood/issues/2680
Design: https://github.com/EvilPatrick06/Thornswood/issues/2680#issuecomment-6247548456
Lane: Anvil. PR: https://github.com/EvilPatrick06/Thornswood/pull/2694 (HELD 1.2.4 draft, branch anvil/2680-holder-notices).

## Why this is in the queue

The PR touches game\ (the gamemode's property and chat blocks, the front plugin and a new game\data\property-word.json), so it is a held draft under the freeze. Lanes do not run Ship, Deploy or live steps. No engine change and no fork PR.

## Steps for Claude

1. After the freeze lifts, squash-merge the held draft once its CI is green on the current main. If #2693 (furniture) merged first, expect small text conflicts only in tests/test-2582-nothing-personal-served.js (SHIPPED list), docs/systems/property.md and docs/systems/commands.md. Keep both sides.
2. Ship to dev. game\data\property-word.json must reach the server folder next to gamemode.js, the way guild-sites.json does. If it does not, the server log says "word: game/data/property-word.json would not read, so the limits are the defaults" and the defaults (the same numbers) are used.
3. Dev playtest, two characters A and B, B with lockpicks:
   - A claims a house and locks it. B, with no key, picks the front door. A line "property door ... opened on its lock, telling the server" is in B's thornswood-front.log, and the server log has "[property] word: B (profile ...) picked the lock of ... held by A".
   - About 20 minutes later A, in the world, gets a corner notice and a chat line from "the steward's office of <Town>" that names the house and what B looked like, and does not name B.
   - B picks it again at once: the log says "already counted for that person at that door" and A gets no second word.
   - A unlocks the door with the lock key while B stands near it: nothing is reported as a pick.
   - B steals A's deed and carries it through the door. With A logged out, A gets the deed word about 10 minutes later on the next login, not before.
   - Restart the dev server with a word still waiting: it is still delivered after the restart.
4. Check the report lands when the pick takes B through a load door. The server accepts B already inside the building's own cell. If the log says "they are not at that door or inside ..." for a real pick, note the cell B was in and raise it on #2680.
5. Ship to main after the dev playtest passes.

## Numbers

Every number is staff data in game\data\property-word.json:
- pick: on, delayMinutes 20, describe, samePickerMinutes 360
- deed: on, delayMinutes 10, describe
- bundle true, perHolderPerDay 6 (0 is no limit, deeds never capped), maxPending 20, keepDays 14, reach 400, needLockpick true, everySeconds 30

## Release and wipe

The words live in private\property.json under word, so Wipe-Saves already moves them aside with the claims. Rows carry holder and by profile ids, which Delete-Person counts with the rest of the register and does not change.
