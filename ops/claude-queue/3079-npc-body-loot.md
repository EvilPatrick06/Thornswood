# 3079 NPC body loot only

**Patrick stopped ChatGPT and authorized Claude takeover.** See [[3079-chatgpt-takeover]] first. Native98 is unmerged; final-head local build was interrupted and its Windows CI cancellation requested. This draft is not a release-ready instruction. DONE remains unset.

- **Lane:** ChatGPT
- **Issue / PRs:** Thornswood3079; companion3103 squash-merged asb1e15c18cdf8c3b3d1429163e7c0b6e9d1419cb6 at05:49:25UTC22Oct from18fb458a8dcac4d53c6420f043e1ad60de5a0ef2; engine EvilPatrick06/skymp98 at1960248b, required Windows CI pending.
- **Channel:** Dev first, Main after the normal release process.
- **Staff status updates:** staff-updates1549254991082946570, never staff-general.
- **Status:** Source work in progress. DONE unset. Claude owns all operations. No lane deployment, installation, server access, Vortex action or playtest ran.

## Needs first and order

1. Engine98 must pass its exact-head Thornswood PR Windows/build and merge. Companion3103 is merged after exact-head Launcher builds (VPS fallback) passed39669430542. Its helper is inert on the older engine; do not announce it alone as the NPC fix.
2. The release desk owns engine.yml, its recorded build and the pin PR. When98 merges and its push build completes, from current main on One, dispatch the record build with the actual merged40-character commit:

```powershell
gh workflow run engine.yml --repo EvilPatrick06/Thornswood -f commit=<ENGINE98_MERGE_COMMIT>
```

This note will replace that placeholder after merge. The release desk opens and merges the normal pin/record PR after green Launcher builds. Do not hand-edit release hashes or package an unrecorded local build.

3. **Fresh alpha NPC state is required.** Older saved NPC inventories are unmarked. The source adds no migration or post-death stripping. An ordinary update preserves them. Preserve profile-owned characters and unrelated private registers; the all-servers Wipe-Saves command is not an NPC-only reset and is not queued here. Claude must establish fresh alpha NPC records for acceptance and record the concrete reset scope/command before its first run. This operational prerequisite remains outstanding.
4. Once the matching pin/records and fresh NPC state are ready, Claude on One runs the matching Dev rollout from C:\Thornswood-Repo current clean main:

```powershell
./scripts/release/Get-EngineArtifact.ps1 -NoPause
./scripts/release/Publish-Server.ps1 -Channel dev -FromStore -ServerBuild -NoPause
$note = @'
Assigned loot on bodies
- Bodies give the supplies assigned to them, without extra pockets of old coins or gear.
- An enemy keeps its clothes and weapons for fighting. Those pieces cannot be taken or dropped as loot.
- Hunting yields, guild shelves and deliberately assigned goods keep their own rules.
'@
./scripts/deploy/Deploy-DevGamemode.ps1 -LoadOrder -LoadOrderRefuse -Note $note
./scripts/release/Ship.ps1 -Channel dev -Notes $note -NoPause
```

These are instructions for Claude, not commands this lane ran. No Bot install is needed; full Install-Bot has the known bot.env.json read-access risk until2158's fix is present.

## Evidence and remaining acceptance

An isolated native fixture with the real masters transferred four vanilla entries out of an initialized Draugr and created another vanilla death item. This was a local port-zero native measurement, not a connected E-menu session.

Regressions reproduce seven missing transfer/drop/pocket protections, a typed merchant-transfer bypass and three Papyrus negative/oversized/named-stack failures. The corrected implementation passes508 native cases with481938 assertions, including real master-backed combat, counterfeit ownership rejection, save/JSON provenance, original binary wire layout, Papyrus equip reuse and timed return. Upstream integration is being verified again; required CI remains the merge gate. Companion grant, merchant, dungeon and97 hair-dye checks pass. Independent implementation and narrow correction reviews are reconciled.

Claude's connected acceptance still needs alive/dead bandit and guard searches, a dropped weapon pickup attempt, timed return, unchanged appearance/combat and the exact assigned body/Hunter pile. Also sell an explicitly assigned same-base weapon without spending the inherited weapon. Do not claim these connected checks passed from saved markers alone.

## Deliberate assignments

- Merchant purses and shelves remain in their existing private ledger. Typed native settlement preserves marked gear in its snapshot and spends only assigned stock.
- Guards and Thalmor patrols keep inherited equipment and native combat ownership. Explicit script grants remain separate ordinary stacks, including on the same base ID.
- Trade-ship crews retain equipment and identity. Ship cargo stays in its existing cargo register, not a body inventory.
- Body/Hunter reward amounts, odds, cooldowns and locations are unchanged. No new NPCs, habitat changes, guild relocation or clothing work is included.

## Risks and rollback

Do not mix unrecorded engine/server artifacts or release against old unmarked NPC state. Native initialization omits vanilla pockets, and death lists are prevented at their origin. Gear provenance is server JSON, never a new binary packet field. An explicit script deletion can destroy gear; an explicit new grant remains assigned goods. Revert source and release matching recorded engine/server/client files together if needed; do not introduce a live inventory migration.

## Draft news

Bodies now carry their assigned loot. Enemies keep the equipment they fight with, but it is not extra loot to take off them. Hunting yields and guild trading keep their own supplies.

## Draft Main test task, only after Main delivery

Test task: Assigned loot on bodies
Server: Main
1. Search an enemy after defeating it, then have someone else search it.
2. Look for extra coins or equipment, including any weapon dropped nearby.
3. Return after that enemy comes back and repeat the search.
4. Hunt an animal and trade deliberately assigned goods with a guild specialist.
What should happen: Only the assigned body or hunting pile is paid, once per life. Worn and fighting gear is not loot. Enemies still look equipped and fight normally. Guild goods can still be traded.
