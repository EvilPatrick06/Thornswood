# 1383 broken limbs, a brewed cure disease, and the six temple shrines

- **Lane:** Herald (17 Oct, slug 1383-limbs-brews)
- **Issue / PR:** #1383 (closed "Needs playtest."); held draft #2684 (game\, HELD 1.2.4); held draft fork EvilPatrick06/skymp#81 (test only now; Waystone's fork #78 makes a brewed bottle drinkable); split #2681 (going down, blocked on #1626) and #2682 (meal help, needs Patrick)
- **Channel:** dev only
- **Needs first:** #2684 merged after 1.2.4 (run 2). Run 3 also needs skymp#78 merged, an engine build and a pin-only PR. Run 1 needs nothing but a session.

## Run

### 1. Which shrine stands in each of the six temples (session, read only)
The temple rite in `game/gamemode.js` (`rite`, `inTemple`) counts any shrine pressed inside one of the temple cells the wake uses (`__thornswoodStuck.TEMPLES`). Nobody has written down which shrine is actually in each one. On dev, walk into each of the six temples and press its shrine. Then copy the server.log line for the press (the shrine base form and the cell desc) onto #1383, or onto #2681 if #1383 is closed. Raven Rock matters most, because its temple may hold none of the nine Divines' shrines. If a temple has no shrine the activation reaches, say so. That's a finding, not a fix for this note.

### 2. Broken limbs on dev (after #2684 merges; Deploy-DevGamemode plus a dev Ship, because thornswood-front.js changed)
Two people, one of them staff:
- Staff: `/hurt <person> break leg`. The person holds sprint: no sprint, and "Your broken leg will not take a sprint." shows once. A sprint already running stops. The Thornswood client log has no "bSprintOK was shut ... held open" line for them.
- Staff: `/hurt <person> break arm`. The other person hits them while they block. Each blocked hit costs about twice the stamina it costs with a sound arm (compare before and after `/hurt <person> clear`). The client log says once: `broken arm: a blocked hit cost N stamina and was taken again (#1383).`
- Splint the break from the wounds panel (H in the inventory). Both costs stay until it heals, the same as the -8 speed.

### 3. A brewed potion of cure disease (after skymp#78 merges, the engine is rebuilt, and a pin-only PR names it; then Publish-Server -Channel dev, Deploy-DevGamemode and a dev Ship together)
- An advanced Physicker brews Cure Disease at Skyrim's own alchemy lab (two ingredients that share Cure Disease, e.g. Charred Skeever Hide and Hawk Feathers). The brew is no longer refused as off the mixtures list (the effect is keyed ae722 in #2684).
- Staff: `/hurt <them> fever`, wait 10 minutes, then drink the brewed bottle. "The wound fever is gone." is said. server.log shows `cured of wound fever by a brewed potion`, and the bottle is gone from the pack after a relog (before skymp#78 it came back).
- Brew Restore Health in the same session and drink it with a disease: it cures nothing.

## Ran (Claude)
- 19 Oct 2026, 5:58 to 6:05 PM: dev, Deploy-DevGamemode at 490f4d85 and dev Ship 20261019-180339-dev (SHIP EXIT 0). In-game checks are the Test task at main.
