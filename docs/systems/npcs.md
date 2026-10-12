# People who are not people

Actors the world placed. They are not characters. They do not wake in
a temple, they do not hold a profession, and a kill of one can be a
warrior's work. A kill of a person cannot. See
[Death](death.md) and [Warrior](professions/warrior.md).

The server must load the surviving cast and own its position, activity,
combat, death and return. The same identity is shown to everyone. Work
continues when nobody is nearby. An actor without safe navigation waits
under server authority instead of walking through a wall.

## Who stays

Bandit camps, bandit ambushes, giant camps, dungeon enemies and wildlife
stay. Skeletons, draugr, wolves, bears and other hostile creatures belong
in suitable places: wilderness, caves, dungeons, sewers and encounters
beside roads. Camps are not removed to make towns smaller.

Specially named animals and enemies are cut too. Their generic species and
enemy families remain. Named traders and transport workers stay as services.
This includes named pets and dungeon bosses whose records lack the Unique flag.

An actor stays in its habitat and home region. Wolves do not roam a city
market. Bears do not populate a farmyard. Horkers belong on suitable
coasts, fish in suitable water, livestock on farms, and sewer creatures
below the streets. A road encounter stays beside its road. Returning
after death uses its home, not the nearest person or a temple.

Only Merchant's Guild traders and a small, suitable animal population
belong inside city walls. Vanilla courts, priests, guards, soldiers and
other town fillers are cut. Wildlife or enemies that vanilla did not
place in the city do not belong on its streets. A dungeon or sewer under
a city is its own habitat, not permission to spawn its enemies above it.
The rule also applies to towns without a separate city worldspace.

Traders you buy from and sell to. They are the merchant's guild of
the hold they stand in. The guild is these NPCs; people cannot join it.
Their prices are the average of the price
lists submitted to that hold's drop box. Their purse starts once,
and after that they buy and sell the way a person does. An empty
purse does not pay. An empty shelf does not sell. Stock is what
they have bought. See [Merchant's Guild](merchants-guild.md) and
[Custom quests](quests.md). A guild trader is handed 250 when they are
first stood up, once, and not again. Supply rewards debit this purse.
Scene rewards create the amount named on the quest, subject to its
cooldown. See [Gold](gold.md). Each hold has one recorded guild site. A later walk can move it.
Traders are not relocated by that record. See [Merchant's Guild](merchants-guild.md).
The 249 traders, by hold and place, are listed in
[Merchant trader counts](merchant-traders.md).

Carriage and ferry drivers stay at stops outside city walls. They are
the workers of the hold the stop sits in. The fare is that hold's. See
[Carriages and ferries](carriages.md).

Thalmor patrols. 2 to 4, on the roads, at most 3 patrols, no coin.
See [The Thalmor](thalmor.md).

Animals in the hunt table, the fish, the seams, the plants, the
crops. Those are the classes, not this cast.

## Difficulty and population

Caves and dungeons have a fixed tier assigned to the place. Entering with
a stronger character does not silently raise it. The location list names
the tier, enemy families, population cap and return interval. A chest in
that place pays from the same tier. A camp enemy carries a little on the
body. Any other dead body rarely carries anything good. See [Dungeon loot](dungeon-loot.md).
Some places have more enemies and stronger ones. Ordinary routes and
beginner places remain usable; higher tiers are a choice, not the whole map.

Bandit camps share one bandit-camp baseline. Giant camps share one
giant-camp baseline. A giant camp can be harder than a bandit camp, but
neither kind has a ladder of tiers between its camps. Road ambushes have
small limits and a shared wait before another can pay out.

The caps count living actors and bodies waiting to return. They do not
grow with each connection or create a second wave for each person. A
return replaces a dead identity at its home; it does not stack another
copy on its body. Return times and shared stock survive a restart.

Hunting and fishing locations list the hold, habitat, species, population
or stock, and replenishment rate. Cold coasts, rivers, lakes, forests,
marshes, farms and caves do not all supply the same animals or fish.
Some locations supply only their named species. See [Hunter](classes/hunter.md)
and [Fisher](classes/fisher.md). Enough common supplies must circulate for
food and trades; rare goods remain limited. There is no fixed gold price
on an animal, fish or item, and increasing density does not mint coin.

## Who does not stay

The jarl's court as the game wrote it, priests who are not a person,
Bethesda guards and soldiers, and other ambient town fillers are cut.
Animals are limited by suitable habitat and a shared cap; they are not
removed as a whole. Bandits and other enemies outside the city surface
stay in their proper encounters.

The embassy's 20 are people on a roll, not actors. See
[The Imperial Embassy](embassy.md).

Guards of a hold, when they are remade, are the hold's. A Thalmor
marker is a reason to start a fight. They do not need a bounty
number the server does not have. There is no crime gold and no
stolen tag the server tracks. Theft is the rule on the site: take
something, take a good thing, leave the rest.

## Where this is

Patrick changed this policy on 1 October: preserve hostile camps,
encounters and wildlife in natural habitats, cut town fillers, limit city
animals, and implement merchant quests. The earlier instruction to remove
bandit camps is superseded. Guild sites are recorded and can move later.

Release 1.2.3 runs the population cut on both dev and main: the shared
controller, population catalogue, habitat limits and difficulty tiers are live.
Guards, courts, priests, town fillers and named creatures are not placed.
Stock controls and merchant quests are still being implemented and verified.
See [Shared NPC activity](../NPC-SERVER-ACTIVITY.md) for verification.
The [population catalogue](../NPC-POPULATION.md) lists authored counts, locations,
caps and return times. Its coordinate files and the server policy come from the
same winning-record inventory.
