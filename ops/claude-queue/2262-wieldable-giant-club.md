# 2262: A wieldable Giant's Club in the collection (Wyrd)

Status: HOLD. Wait for the 1.2.4 freeze to lift and for Wyrd's evaluation comment on #2262. Approved by Patrick (via Smeagle). Collection only: no asset-provenance entry.

## What
Dragonborn's Giant Club, Nexus SE 37815, by Thomas Marfleet (Marfleet1987). One new playable club weapon of its own. It does not edit the vanilla giant clubs, giants, NPC or race records. Permissions: upload, modification and asset use allowed with credit; not in paid mods.

## Steps for Claude (Vortex)
1. Pin version 1.0 (the only file, 30 Jun 2020).
2. Before adding it, open the plugin in SSEEdit and post on #2262:
   - whether it is ESP or ESL-flagged;
   - every record it adds or overrides (expected: one WEAP, plus an edit to Belethor's vendor stock). If it overrides any NPC_, RACE or vanilla giant club record (000461DA, 000CDEC9, Dragonborn's frost giant club), stop and tell Wyrd;
   - the club's form id, its weight, damage and speed;
   - whether it has a COBJ. Any new COBJ needs recipes.json ownership later.
3. Load it last of its own type (#1930, docs/LIGHT-ORDER-DRIFT.md): an ESL at the END of the light plugins, before Thornswood-Last.esp; a full plugin after every current full plugin. NEVER mid-order. Write down which type and its position on #2262.
4. Publish the revision, then refresh records/collection-plugins.json with scripts/mods/New-CollectionPluginRecord.ps1.
5. The load order changed, so hand back to Wyrd for the repo PR that rebuilds the NPC catalogue and Thornswood-Last.esp (Build-NpcPopulation.py, then Build-LastPlugin.py). Do not deploy the new order before that PR merges.
6. After it merges: Deploy-DevGamemode -LoadOrder, then a dev Ship.

## Check on dev
- A character can equip the club and swing it. Existing characters keep their hair and beard.
- With #2262's gamemode rule in, a character below Might 5 is refused the club if it weighs 45 or more.

## Then
Post a Test task: comment on #2262. Wyrd closes it when the gamemode half is in.