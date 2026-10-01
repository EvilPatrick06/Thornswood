# Canonical client provenance: 4952dbb6

Canonical fork commit: 4952dbb6102f9093dfc281ae855b39ee79c6c39c. Baseline record: 1a2e5995dc3a50c1f79d830c8b4474624c423a45, recorded 2026-09-29T19:42:02Z.

MpClientPlugin was actually relinked, not copied or relabeled. Two changed server library objects were compiled from this clean canonical checkout with the recorded MSVC 14.44.35207 compile flags and canonical source/header overrides. An isolated copy of server_guest_lib.lib had both original members removed, then the new objects added. Both members occur exactly once. The original client target link command uses this canonical archive; normal static-library reachability is preserved. The link map contains neither changed server-only member. Baseline cached client entry object and all other native archives are reused; their tracked sources, dependencies, and build configuration are unchanged between the two commits.

The remaining five artifacts are reused with explicit source equivalence, not claimed rebuilt. Every cached artifact was checked against all six baseline record hashes and byte counts before staging. The complete tracked-source diff contains only ActionListener.cpp, MpObjectReference.cpp, HostAttemptTest.cpp, and HostedActivationTest.cpp. All client JS, SkyrimPlatform/native hook, Papyrus script, dependency manifests/lockfiles, and build configuration inputs are identical. Thus the five unchanged artifacts implement the canonical client sources exactly as at the baseline pin. Bundle retains 18 THORNSWOOD PATCH markers.

| Artifact | Method | SHA256 |
| --- | --- | --- |
| Data\SKSE\Plugins\MpClientPlugin.dll | actually relinked from canonical library | df95b00b82f796c12e04b7268744f8f808129ea87eb7ab6475e30e3fce4455e9 |
| Data\SKSE\Plugins\SkyrimPlatform.dll | reused unchanged | f8b4a0d248f2bc726fd63ccf9aabe6e238c93014ca892bf4835ccf45bd93c022 |
| Data\Platform\Distribution\RuntimeDependencies\SkyrimPlatformImpl.dll | reused unchanged | cf4bffc3627b83259b75b51bbe096c066a11394f19c105c6ab4f2f3a105c3a5e |
| Data\Platform\Distribution\RuntimeDependencies\SkyrimPlatformCEF.exe.hidden | reused unchanged | e5fc4d146c0abb0aeea6e8a7ac22e03c72a486099a2e2a5df84262186a7b0dd8 |
| Data\Platform\Plugins\skymp5-client.js | reused unchanged | 18833d23f1c5da2e89b23caa49248e8ca0803b6d007d88ec656c6c4158da2e35 |
| Data\Scripts\TESModPlatform.pex | reused unchanged | 841c588ba784359e1badce2635bc48265835d2ff6fccacdf9274353c5f6b0545 |

Validation: archive membership checks; link map reachability; identical baseline/canonical export names and imported DLL names; actual LoadLibrary and MpCommonGetVersion export returns 2.0.0. Existing MenuOpenKeyBlocks native tests passed 22 assertions across 8 cases. No in-game test or launch is claimed.

Evidence is in build/canonical-client-verification: compile response files, isolated archives and member list, link-client.rsp, MpClientPlugin.map, baseline/canonical EXPORTS and DEPENDENTS, native-client-smoke.txt, compiled-source-hashes.json, client-build.json. Build driver is C:/Users/you/Downloads/Thornswood-Repo/canonical-client-build.ps1; log is canonical-client-build.log. No cached build input was modified.
