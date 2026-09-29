# Required Data plugins

Files here are third-party (or otherwise not Vortex-named) plugins that the
server load order and the shipped plugins.txt enable by exact filename, but
that the current Vortex / Nexus collection does not deploy under that name.

Go.ps1 and every Ship pack / installer build copy each file (except this
README) into `Data\` in the game folder before scanning what to ship. They are
not in Profile\OwnGame\files.txt as Vortex-origin, so packs carry them. When
the collection deploys the same path, take the file out of this folder so
Vortex owns it again.

## Why ElysiumEstateSSE.esp is here

Tonight (27 Sep 2026) the lists and the server enable `ElysiumEstateSSE.esp`.
Vortex still stages Elysium Estate 4.3.5 as `ElysiumEstate.esp` into Steam
Data. OwnGame links that old name; one of 94 plugins was missing from the Steam
path until a manual copy. Other people hit the same launcher warning.

The bytes here match the server payload plugin of the same name
(sha256 A450BE33F0DF4C0E36DB8718A8523921D97F4C5B7C5998C614D707158DC467B2).
Do not invent a substitute. The lasting fix is the next Vortex / Nexus
collection revision shipping / deploying `ElysiumEstateSSE.esp` (replace or
add alongside the old `ElysiumEstate.esp`). Until then this folder keeps packs
and OwnGame playable.
