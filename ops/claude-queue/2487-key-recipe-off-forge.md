# 2487: Key recipe off the forge list (Wyrd)

Status: HOLD. Not ready until the #2487 PR is merged (it touches game\ and records\, so it waits for the 1.2.4 freeze to lift). Branch wyrd/2487-key-at-forge, local commit 6c901cf6.

## What changed
- Thornswood-Content.esp: COBJ ThornswoodRecipeKey (15497) now carries a never-true condition (GetItemCount gold < 0), the same one #2258 put on the Hearthfire house parts. No forge lists the Key any more. Size 132,868 -> 132,906 bytes, sha256 e01025a8d605fef036ecfe82836e683677c7c26096027de5c2e0ea16473bf762.
- Gamemode refuses the menu Key for anyone on an older plugin and points at the forge's lock key (cutKey), which already cuts the key named. The 250 ms naming timer is gone.

## Steps for Claude, after merge
1. The plugin's size changed, and the launcher refuses Play when a plugin's size differs from the server's. So the collection must carry the new Thornswood-Content.esp (Nexus mod 192001, Thornswood Content) BEFORE any game server runs this main. Upload the new file and include it in the next collection revision.
2. Refresh records/collection-plugins.json for that revision (scripts/mods/New-CollectionPluginRecord.ps1).
3. Then deploy the server as usual (dev first). Do not deploy this main to live ahead of the collection revision.
4. Check on dev: the forge menu has no Key row; Key Mold is still listed; the lock key at a forge with a stamped mold gives "Key to <house>" and takes one iron ingot.
5. Post a Test task: comment on #2487 and close it.