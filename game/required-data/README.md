# Required Data plugins

Files here are third-party (or otherwise not Vortex-named) plugins that the
server load order and the shipped plugins.txt enable by exact filename, but
that the current Vortex / Nexus collection does not deploy under that name.

Go.ps1 and every Ship pack / installer build copy each file (except this
README) into `Data\` in the game folder before scanning what to ship. They are
not in Profile\OwnGame\files.txt as Vortex-origin, so packs carry them. When
the collection deploys the same path, take the file out of this folder so
Vortex owns it again.

Empty is the usual state, and it is empty now.

## ElysiumEstateSSE.esp, 27 to 29 September 2026

From 27 September this folder carried `ElysiumEstateSSE.esp` (Elysium Estate
4.3.5), because the servers loaded that plugin while the collection installs
Elysium Estate 5.0.1, whose plugin is `ElysiumEstate.esp` (#689).

On 29 September Patrick settled which side moves: the servers match the
collection, except where we changed something on purpose later (#690,
docs\COLLECTION-REVISION-2.md). So the servers load `ElysiumEstate.esp` from
the collection, the file came out of this folder, and every pack deletes
`Data\ElysiumEstateSSE.esp` (Ship-Rules.ps1, $ShipDeleteAlways).
