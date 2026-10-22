# 2382 Flora harvested model: engine build, client record, pin and dev Ship after fork PR 69

Anvil, 16 Oct 2026. Fork PR https://github.com/EvilPatrick06/skymp/pull/69 (draft, branch anvil/2382-flora-redraw, tip 65d54fb1) into thornswood/engine-changes. Held by the 1.2.4 freeze on engine/skymp; Codex merges fork PRs. Do nothing until it is squash-merged.

What changed: in skymp5-client, a tree or flora is shown harvested or not by ObjectReference.SetHarvested alone (SKSE queues the engine's harvest model update). The old disable and enable redraw and the random NPC harvest are gone. Client only; the server is unchanged.

Live steps after the merge, for Claude only:
1. From a clean current outer main checkout on One, build the engine from the fork merge commit with the usual scripts: .\scripts\release\Build-Engine.ps1 against a fork worktree at that commit, then .\scripts\release\New-ClientBuildRecord.ps1 for the new client dist. Combine with any other merged fork work waiting for a build rather than building twice.
2. Open the outer PR with the engine/skymp pin bump and the new client record per engine/README.md, and merge it once its checks pass.
3. Ship to dev the usual way, so the dev launcher carries the new client runtime.
4. On dev: pick a flower, wait for it to come back or have the server reset it, and check it shows unpicked without blinking, and that nobody nearby is handed the produce.

No secrets, no settings, no data migration. Leave DONE unset until Claude reports the dev ship.