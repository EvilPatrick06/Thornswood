# Canonical client provenance: e0135f5a

Canonical fork commit: e0135f5a6d721e9626e700d816d212e52e3bc73c. Baseline: 4952dbb6102f9093dfc281ae855b39ee79c6c39c.

MpClientPlugin was actually relinked with isolated native archives. The five changed server library members and changed Browser member were removed from copies of the cached archives, then replaced with objects compiled from the canonical sources. The original client link command uses these archives with normal static-library reachability. Its link map contains none of the six changed server-only members. The cached client entry object, other native archives and their client build inputs are unchanged.

The other five artifacts were reused after checking all six baseline hashes and sizes. No client TypeScript, SkyrimPlatform source, Papyrus, dependency manifest, lockfile or build configuration changed between the two commits. Server startup TypeScript was rebuilt separately. Thus the unchanged artifacts implement the canonical client sources; they are not claimed rebuilt. The bundle retains 18 THORNSWOOD PATCH markers.

The new DLL hash is 84babf5adbc5b3bc9755ccb287f83c1a2c8dff6785a32ecea41154aadf93035c. All six hashes and sizes are in client-build.json. Evidence: build/npc-client-verification in the canonical native worktree, including isolated archives, link-client.rsp and MpClientPlugin.map. Driver: C:/ThornswoodTemps&Worktrees/temp/whiterun-release/Relink-NpcClient.ps1. No game or launcher launch is claimed.
