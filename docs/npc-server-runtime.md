# Dev NPC loading and first unattended activity

Issue #504 stays open for broader NPC simulation. The current cast is preserved.

Dev indexes winning placed NPC references before accepting connections, then
loads eight candidates every ten milliseconds through the existing inclusion
and saved-state policies. No new placements are created. Existing loaded
identities survive subsequent chunk discovery.

Hulda in the Bannered Mare is the first declared server activity. The server
revokes her human host and moves her at 60 units per second inside two adjacent
walkable triangles, through their shared edge midpoint, with ten-second pauses
at the centers. This is an authored local inn activity, not a vanilla package
schedule. Door, water, deleted, overlap and external-link triangles are excluded.
Reciprocal internal links are required. Surface height follows barycentric
interpolation; the actor's initial height above the surface is retained.

Private route and phase state persist alongside the native transform and
authority flag. Recovery validates ordered route geometry and the current
segment. Invalid phase rebuilds from the current triangle. Unexpected
displacement replans within the same mesh or releases authority. Death and
disablement pause movement. Hot reload cancels the old timer before registering
the new runtime. New observers receive a reliable complete movement snapshot.

Geometry format reference: the NVNM definitions in
[xEdit TES5](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas)
and [shared definitions](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsCommon.pas).

Validation: native suite 478,932 assertions in 293 cases; authority/loading
subset 1,725 assertions in 15 cases; TypeScript check; runtime regression
harness including disconnected edges, slopes, concave phase recovery,
unattended activity, hot reload, death and displacement. The real 48-plugin
load order loaded 11,253 eligible placements from 14,640 candidates. Startup
indexing measured 259 ms, with the slowest subsequent eight-candidate batch
12.2 ms. Real native state advanced through several cycles without connections.

Client authority review and runtime geometry review found no remaining blockers.
Two-person in-game visual checks remain necessary. Other NPCs still use their
existing hosted behavior; full server combat and wider authored routines are
not supplied by this change. Existing EvaluateTemplateChain empty-map warnings
remain under #504 and are not attributed to the reported crashes without evidence.
