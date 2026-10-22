# #2252 #2253 #2257 #2255 Deed, key mold and key show plain names, and the key and mold are the same charcoal stick

**Dev ran 11 Oct 2026: content plugin and client in dev Ship 20261011-221215-dev at 10:12 PM, dev server got the 146,381-byte plugin at 10:20 PM (Deploy-DevGamemode -LoadOrder, .prev-20261011-222021). #2252, #2253, #2255, #2257 closed with test tasks. Left: the main client Ship and the live plugin, on Patrick's word.**

Status: queued, not live. PR #2293, merge d62ce7145f36313c86d84cfb381da1780458963c. Written by Herald (Website lane) for Claude to run. NOT DONE.

## 1. What to run

From One, from a checkout current with origin/main:

1. Content rebuild. game/content/Thornswood-Content.esp changed: the key (0x5015494) now uses Clutter\Key01.nif and the key mold (0x5015495) uses Clutter\SilverMold01.nif, both vanilla Skyrim.esm meshes, so no new art is needed. The plugin went from 146,446 to 146,381 bytes. Rebuild the content package the way you normally do for a plugin change (scripts\deploy\Install-ThornswoodContent.ps1 is the install side) so every client downloads the new plugin.
2. Client Ship on engine pin >= 92848550 (fork #56, the client applies server renames; main's engine/skymp pin is 928485503333b18c2325fc13cbf781d254b19af0 at the time of writing). Use `.\scripts\release\Ship.ps1`. Confirm the pin before building, and announce the heavy build on One in the room first.

No gamemode deploy is needed; the server already names these items.

Dev check (on dev, after the Ship, a Smith):
- Claim a building at its door: the deed in the pack reads "Deed to <building>".
- Cut a mold at the door with the holder present: it reads "Key mold for <building>".
- Cut a key at a forge with that mold (and craft one in the menu): it reads "Key to <building>".
- Drop the key and pick it up again (#1719): still "Key to <building>", and it still opens the door.
- Models: the key on the ground and in the inventory preview is a key, the mold is the silver mold, and the two no longer look the same. Plain charcoal still looks like charcoal.

If a name still shows plain after the Ship, say so on the issue: the offline harness shows the server names it and the post-#56 compare picks up the rename, so what is left would be the client's apply path.

## 2. Risk

- The new plugin makes every client download content again.
- A client Ship drops people on dev for the update.
- Do NOT run scripts\deploy\Install-Bot.ps1 until Waystone's #2158 lands.
- Ship only from a checkout current with main.

## 3. Draft release notes

- Property: deeds, key molds and keys show their building's name in your inventory.
- Property: a key looks like a key, and a key mold looks like a mold.

## 4. News post

Not needed beyond the release notes.
