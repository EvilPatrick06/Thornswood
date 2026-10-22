# 2263: KS Hairdos Lite SE into the collection (Wyrd)

Status: HOLD. Wait for the 1.2.4 freeze to lift and for Wyrd to confirm on #2263 that the evaluation comment is posted. Approved by Patrick (via Smeagle).

## What
KS Hairdos Lite SE, Nexus SE 1932, by Brataccas (KS Hairdos by Kalilies, Stealthic Khaos and Shocky). 20 male and 20 female hairstyles.

## Steps for Claude (Vortex)
1. Pin version 1.3 (the current file, last updated 17 Nov 2016). Do not take a later file in this revision.
2. Take the "No NPCs" file, not the main one. The main file edits Skyrim, Dawnguard and Dragonborn follower NPC records (hair and default clothing, hoods removed), which we do not want in our NPC records or in the plugins Thornswood-Last.esp copies from.
3. Load order, because stored hair ids break when an existing plugin moves (#1930, docs/LIGHT-ORDER-DRIFT.md):
   - If the plugin is ESL-flagged or .esl: put it at the END of the light plugins, after every current light plugin and before Thornswood-Last.esp. Never mid light order: that renumbers every later light plugin, and stored HammerHair and KhisartinBeards head parts would point at the wrong forms.
   - If it is a full plugin: put it after every current full plugin. NEVER a full plugin mid-order.
   - Write down which it was and its exact position in the 2263 comment.
4. Publish the revision, then refresh records/collection-plugins.json with scripts/mods/New-CollectionPluginRecord.ps1.
5. The load order changed, so Thornswood-Last.esp and its catalogue must be rebuilt in the repo before any server runs it (Build-NpcPopulation.py, then Build-LastPlugin.py; test-2468-last-plugin.js fails until then). Hand that back to Wyrd as a repo PR. Do not deploy the new order before that PR merges.
6. After that PR: Deploy-DevGamemode -LoadOrder, then a dev Ship.

## Check on dev
- A pre-existing character that already wears a HammerHair.esp hair or a KhisartinBeards.esp beard comes back from the menu with the same hair and beard.
- A new character can pick a KS hair in RaceMenu, and comes back with it after a relog.
- Session log: client and server agree on the light plugin list.

## Then
Post a Test task: comment on #2263 and close it.
Repo half follow-up: #2659 (rebuild the NPC catalogue and Thornswood-Last.esp after this revision).
