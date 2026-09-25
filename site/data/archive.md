# Archive

Closed problems and their real causes. Kept for the causes, not the fixes.

## 14 September 2026

**Looting armour stripped worn gear.** The server validates every equipment change and rejects it if any two worn items claim the same body slot, unequipping all of them. Vanilla already uses slots 44 to 47 and cloak mods reach for the same free ones. Fixed by making the slot check a setting and turning it off. Searched for days on the client. The server had been logging the exact item IDs the whole time.

**World had no NPCs.** A hardcoded list in the server's C++ banned ten race IDs, which are the ten playable races, covering every human, elf, orc, khajiit and argonian. The NPC setting was already enabled. Fixed by moving the list into server settings and emptying it. The trace log named every skipped actor and the reason, and trace was never switched on.

**Enemy health mirrored your own.** The function reporting health ran once for your character and once per hosted NPC, but read values off your character every time. Fixed with an early return unless reporting your own character.

**Every door and chest unlocked.** Upstream unlocks every reference the server tracks, because it also blocks activation on containers, and locked plus blocked is unopenable by any means. Fixed by letting a locked reference keep its own handling until opened normally.

**Keyboard locked on load.** A browser focus flag blanks all keyboard reads. The bindings that raised it were removed, but another service still raised it and removing the bindings had deleted the only code that lowered it. Fixed by having Escape and menu open lower it again. Six wrong explanations, each shipped as a build. Alt tabbing out and back cured it, which was the clue, because leaving the process dropped the flag.

**Launcher would not reopen.** The launcher holds a single instance lock. Voice runs in a hidden window, and WPF closes an app when the last window closes, not the main one. Closing the launcher left the process alive holding the lock. Fixed by tying shutdown to the main window.

**Voice indicator stuck on LISTENING ONLY.** Audio moved to the launcher but the indicator still asked the game browser whether it had a microphone. The replacement request could fail silently because the error handler was empty. Fixed by pushing state in through the plugin, and the empty catch is gone.

**Load order check had never run.** The client asked a public master server that has never heard of this server, got a 404, and compared against an empty list, which passes. Fixed by having the server publish its own manifest. The yellow warning everyone ignored for weeks was that failed lookup.

**Server would not start after deploy.** Plugin paths in the server settings were written from the development machine and copied to the VPS, where the game lives elsewhere. The sync script takes the server path as an argument now.

**Start point pointed at the wrong mod.** The configured start point encodes a plugin's load order position. The order grew by two entries and the value was not updated. Must be rechecked whenever anything is added before Skyrim Unbound.

**Enchantment damage did nothing to anyone else.** The client accepted weapons, spells and scrolls as hit sources and dropped enchantments before reporting.

## Earlier, confirmed working

**Handles, levers and pull chains.** Blocked activation stopped the game running its own scripts on them, and the server has no scripts to run instead. Activators and furniture are no longer blocked.

**Voice chat.** The game's browser has no permission UI, an autoplay policy needing a click nobody can give, and a focus flag that takes the keyboard. Audio never worked there. Moved into the launcher, which is a real browser.
