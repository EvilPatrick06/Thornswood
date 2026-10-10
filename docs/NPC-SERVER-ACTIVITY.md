# Shared NPC activity on dev

The server owns the retained winning placed identities and their movement,
combat, health and return timers. The population policy runs before loading,
including later saved-form loads. Main does not start this controller.

The 48-plugin catalogue contains 14,641 placements: 5,072 retained and 9,569
excluded. Named pets and enemies are cut even without a Unique flag. Fourteen
old Justiciars and the embassy soldier are excluded too. Remnant patrols are
not placed by this catalogue. Traders, outside transport services, ecological
wildlife and generic hostile encounters remain under habitat caps.
Authored corpses are excluded from live encounters.
The native eligibility filter excludes mannequins and permits retained vampires
and their traders. Humans, profiles and connected identities are protected.

[Population counts and locations](NPC-POPULATION.md),
[exact NPC spawn coordinates](NPC-SPAWNS.csv),
[hunting yields and access gates](HUNTING-SPOTS.csv),
[existing fishing locations](FISHING-SPOTS.csv) and
[hanging game locations](HANGING-GAME-SPOTS.csv) come from these inputs.
The existing fishing placements are a source inventory, before the new fishery
allocation, poles, traps and scarce quest gates in the Fisher specification.

The hunting list reads no plugin: it is every retained animal from
`game/data/npc-population.json` with what `game/data/hunts.json` gives for its
body. A population rebuild writes it, and so does
`python scripts/dev/Build-ResourceLocations.py --hunting-only` after a hunt
table rebuild. `tests/test-1874-hunting-spots.js` fails the build when it is not
what those two tables say.

Loading advances one candidate every 10 ms. Native record and navigation indexes
are prepared during startup. Navigation preparation shares raw geometry and a
spatial index across overlapping regions, yields after bounded work, and creates
reciprocal portal links only when a route needs them. Background activity continues
with no connections. Nearby activity uses the same authority and state.

Movement follows walkable triangles in the local region. It retains the saved
height above the navigation surface and crosses only verified reciprocal edges.
Missing or corrupt geometry, an unsuitable saved position, or a displacement
outside the prepared region pauses activity. The NPC remains loaded and owned by
the server. A reliable stopped snapshot prevents continued walking extrapolation.
Dead, disabled, and immobile NPCs also pause safely.

An NPC the game placed off walkable ground (a goat on a ledge, a horker on a
rock, a deer just past a mesh edge) is set down on the walkable point nearest
its placement, searched out to 8,192 units, the way the game moves an actor
onto its navmesh. It happens only while nobody is within 4,096 units, and only
in a tick that read where everybody is. When that point is past its home
radius, the point becomes its home. An ambush (a base named ...Ambush..., such
as a draugr in a burial alcove) waits where it was placed until somebody comes
within 1,024 units, then walks straight out onto the floor beside it; one more
than 256 units from any floor (a pipe or a ceiling the game empties by script)
stays put. A race that swims and cannot walk (the slaughterfish) moves only over
water triangles, at its height above the bed and never higher than the depth it
was placed at. The searches run a few tiles at a time on their own tick. The
catalogue leaves out the game's test worldspaces and its test and holding
interiors. Issue #2067 has the measurements.

Movement also respects the authored home radius, including local routes on slopes
and inside small home ranges. Dynamic encounters and farm births must pass habitat
and shared density checks before their creation is reported as successful.
Destroyed dynamic identities release their slots; bodies awaiting return retain
theirs.

Native inherited aggression, confidence, and current faction membership inform
target selection. Common membership and ally or friend reactions suppress
spontaneous hostility. Accepted damage can provoke temporary retaliation.
Confidence zero flees along safe local navigation. Targets are read again before
an attack; disconnected human identities and profiles are protected immediately.
Melee uses owned equipped weapons, or unarmed damage, with the existing native
reach, cooldown, damage, block, health, and death pipeline. Health, death, attack,
and terminal stop messages are reliable. Ordinary movement is unreliable, with
one message per directly connected observer.

Authority and private activity progress survive world saves. A gamemode reload
cancels the old controller's timers and reconstructs routes from current saved
positions. Temporary combat targets are not persisted. Saved faction removals,
including an empty faction list, remain removed after reconstruction.

Fixed cave and dungeon tiers scale maximum health and outgoing weapon or spell
damage. Tier 1 uses the source baseline, tier 2 uses 1.25 health and 1.10 damage,
tier 3 uses 1.50 health and 1.20 damage, and tier 4 uses 2.00 health and 1.35 damage.
Bandit camps and giant camps have separate source baselines without camp tiers.
Health percentages and return deadlines survive saves. Loading a newer saved
deadline invalidates an older pending return timer. Invalid saved values fail
before publishing resurrection. Native life generations distinguish each actual
return, so missed callbacks cannot award another dressing of the same corpse.
Fishing and hanging racks use shared persisted waits.

This is shared local activity and melee combat. It does not implement every
vanilla package, doorway transition, flying behavior, ranged projectile, magic
decision, or authored work and sleep schedule. NPCs without safe local navigation
remain stationary rather than moving through unverified geometry. Merchant
economy, custom quest offers and the new fishery content remain separate
capabilities. Exact guild relocation is deferred.

Verification uses the native suite, the shared runtime fixtures, and an offline
run against the installed 48-plugin load order. The offline acceptance fixture
requires all retained identities owned and accounted for within five simulated
minutes, actual activity before and after a gamemode reload, saved sequence
recovery, stationary position preservation, and less than 2 GiB RSS. Scheduled
activity callbacks must finish within 50 ms. A single cold native record load is
indivisible and has a separate 100 ms ceiling; it cannot accumulate into a batch.
No game or launcher is started by these checks. A real dev restart and a later
two-person session are separate evidence for persistence and visible agreement.

The original full-cast baseline contained 11,253 native identities. The dev proof
below is the run before the fifteen old Thalmor were removed from the catalogue.
The mannequin-only filter admits 11,388 before the cut; all 5,087 retained source
identities were eligible in that run.
The policy excludes 6,301 native eligible identities
and 9,554 catalogue identities overall. The recorded population run owned all
5,087 before and after reload. After reload, 4,750 were active and 337 remained
safely stationary. All 4,732 eligible identities moved during the final activity
window. Eleven attackers landed accepted attacks before reload. Peak RSS was
1,798.16 MiB, the worst callback 28.46 ms and the worst cold load 9.47 ms.
This final run used the enabled ElysiumEstate.esp file and verified the policy
and encounter tiers before and after reload.
