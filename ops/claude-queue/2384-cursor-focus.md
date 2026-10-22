> HOLD: frozen paths (engine/skymp, game\). Do not merge or run any of this until Claude posts 1.2.4.

# 2384 The cursor is kept in the fork, not by a focus flip in the front plugin

- **Lane:** Waystone
- **Issue / PRs:** #2384. Fork: EvilPatrick06/skymp#68 (branch waystone/2384-cursor-focus into thornswood/engine-changes, head 0b0a379c). Thornswood: #2600 (branch waystone/2384-cursor-focus, head c8859bc8). Both are ready and held, and neither is merged.
- **Channel:** engine build and pin, then a dev Ship. Main only when Patrick asks.
- **Needs first:** 1.2.4 posted (freeze lifted), and both PRs green.

## What changes
- Fork: `BrowserApiTilted::SetFocused` keeps a queued Cursor Menu show or hide pending until the game's Cursor Menu open or close event arrives (new `CursorFocus.h`). It no longer queues a second show behind one still waiting. `EventHandler`'s existing MenuOpenCloseEvent sink calls `BrowserApiTilted::OnCursorMenu`, and a Cursor Menu that closes while browser focus is up and no hide of ours is waiting is shown again once, from that event. There are no timers or retries.
- Plugin: `keepCursor` and the J block's lower and raise are removed from `game/plugins/thornswood-front.js`. The log lines "the cursor was down, raised it again (n of 4)" and "J: the game's journal took the cursor with it" stop.

## Order
1. Merge skymp#68 into thornswood/engine-changes (squash).
2. Bump the `engine/skymp` pin to that merge, together with #2060. Waystone did not bump it.
3. Build the engine (client, skyrim-platform) at the new pin, as for #2060.
4. Merge #2600 into main (squash), after step 2 is on main or in the same change.
5. Dev Ship that carries both the new engine and the plugin.
6. Post the Test task on #2384 and close it.

## Risk
- **#2600 without the new engine:** a panel loses its cursor whenever a game menu that uses the cursor (the console was seen) closes under it, until F6. Do not ship the plugin change on the old engine.
- **The new engine without #2600:** this is safe. keepCursor still fires on its first frame, and the fork now copes with its lower and raise. It just keeps the extra focus flips.
- **Re-show on a foreign close:** it fires on any Cursor Menu close while focus is up. Watch the race menu and loading screens on dev. If the cursor shows over a load screen or flickers in character creation, the guard belongs in `CursorFocus::OnCursorMenu` (the fork), not in the plugin.
- **Not measured in game yet.** Chat's claim never fired keepCursor in the 15 Oct log, and that was not explained. Watch chat in the Test task.

## Draft release note (dev)
Panels that take the keyboard (skills, trade, journal, party, board, chat) now get their mouse cursor straight away, and keep it if the console opens and closes on top of them. The client no longer drops and re-raises focus several times each time a panel opens. (#2384)
