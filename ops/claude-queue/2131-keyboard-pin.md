# 2131 Keyboard lock: fork #58 merged; needs engine pin and Dev Ship

- **Lane:** Claude
- **Issue / PR:** Thornswood #2131 (open, claimed: Codex); EvilPatrick06/skymp#58 merged as cb03ea322f883f5f584206e8e920763c944e1273 on thornswood/engine-changes
- **Channel:** engine pin on Thornswood, then Dev Publish-Server and Ship. Main only on Patrick's word.
- **Staff status updates:** #staff-updates (1549254991082946570)
- **Needs first:** nothing on the fork. #58 is done. Do not redo the keyboard change.

## Why this note exists

Patrick approved the merge of skymp#58 (15 Oct, via Smeagle). Codex undrafted and merged it. Claude should not reopen or rewrite that work. The fix is client/native (DInputHook): it only reaches people after an engine pin and a Ship, the same path as every other fork merge (engine\README.md "One engine").

## What landed on the fork

- Dead RegisterRawInputDevices path removed (null hwndTarget stole the keyboard from DirectInput).
- CheckAgainstWindows is measurement only (no SetFocus / SetEnabled repair).
- VPS metrics that cleared the merge gate: 178 sessions, 167 with input lines, 0 with [repair].

## What Claude still does

1. Build and pin the current fork head. Head after #58 is cb03ea32, which sits on top of skymp#62 (3bdf3d3c, eatItemScale). Prefer one pin of head so #2131 and #2423 ride together. Exact build and record commands are in `1382-potion-window.md` (steps 1 to 3), with checkout `cb03ea322f883f5f584206e8e920763c944e1273` (or current origin/thornswood/engine-changes after fetch) instead of 3bdf3d3c alone.
2. After that pin is on main: Publish-Server -Channel dev, then a Dev Ship (client carries the keyboard fix).
3. Then merge Thornswood #2423 (still held for eatItemScale) and Deploy-DevGamemode, still per `1382-potion-window.md`.
4. Comment on #2131 what was pinned and shipped; Codex or Claude closes #2131 then.

## Check afterwards

- records/server-build.json and records/client-build.json name the same commit as engine/skymp (cb03ea32 or later head that includes #58 and #62).
- Dev client from that Ship: no new keyboard lock in normal play; if a lock returns, thornswood-input.log shows a [keyboard] meter line, not a [repair] mend.

## Risks and how to put it back

- Pinning without a matching client Ship leaves live/dev on the old DLL; the fork merge alone does nothing for people.
- Put back: Publish-Server -Channel dev -PutBack and a Ship of the previous client record.

## Release notes (draft)

Keyboard stuck less often
- A stuck keyboard that needed alt-tab should be rarer. If it happens again, tell staff and keep the install's input log.

## News post (draft)

none until Main

## Test task (draft, for closing #2131 once the fix is on main)

Test task: Keyboard stays with the game
Server: Main
1. Play for ten minutes: open and close the inventory, the map, and chat; alt-tab out and back once.
2. Walk, fight, and type in chat.
What should happen: Keys keep working without needing alt-tab to wake the keyboard. If they stick, say so and keep the input log from that session.