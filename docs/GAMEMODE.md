# How gamemode.js is put together

This page is for somebody opening `game\gamemode.js` for the first time. It
is the whole of Thornswood's server side: about 24,000 lines in one file,
loaded by skymp5-server. It says where each system lives, which generated
table each script writes into it, how it reaches the server, how it talks to
the plugins, what it keeps on disk, and which tests read it.

References look like `gamemode.js:3618 character creation`: the line and the
name or banner on it. Lines were read on 25 September at origin/main 044b737.
They move whenever somebody edits above them, so search for the name when a
line has moved.

## Why it is one file

`requireTemp()` in skymp5-server copies the file to a temp folder and requires
the copy, so a relative `require` would look beside the copy and fail. So
every rule and every table is inlined (`gamemode.js:6` header). The server
watches the file and reloads it on change after `mp.clear()`, so every block
registers its handlers at load and keeps timers and state on `globalThis`
(`g.__thornswood*`) so a reload does not lose them or double them.

A handler returns `false` to block an event and anything else to let it
through. Every handler is wrapped in `guard()` (`gamemode.js:267`), so a throw
is logged and the event goes on. Form ids cross the boundary as descriptors,
`"<low 24 bits in hex>:<plugin>"`, never as load order positions.

## How the blocks find each other

The file runs top to bottom. The early part is plain functions and the `mp.on*`
handlers. From line 10459 on, each system is an immediately run function
between `// ==== thornswood X ====` and `// ==== end thornswood X ====`,
which publishes its interface on `globalThis`, for example
`g.__thornswoodProgression` (`gamemode.js:13057`),
`g.__thornswoodProperty` (`gamemode.js:16789`) and
`g.__thornswoodSpoils` (`gamemode.js:17230`). A handler defined earlier, such
as `mp.onActivate` at `gamemode.js:7139`, looks those up when it is called, not
at load, which is why it can reach blocks that sit below it.

## The map

| Lines | Section | What is there |
|---|---|---|
| 1-35 | Header and one-line tables | The contract (1-21), then `DATA`, `STATIONS`, `ITEMS`, `WATERS`, `WEATHER`, `WARMTH`, `FOODS`, `RACES` (23-30), each one line. See "Generated tables". |
| 37-334 | Small helpers and logging | `rollLog` (82), `sayLogState` (110), `logPath` (124), `log` (139); `gamemodeId` (208), which logs the git blob id of the loading file (222); `voicePort` (249), `guard` (267), `notify` (294), `say` (312). |
| 335-638 | Respawn resolution | A port of `respawnResolver.ts`: `arrive` (391), `resolveArrival` (415). `ensureProperties` (467) declares the actor properties the early blocks use. |
| 639-1497 | Gathering stations | `ORES_BY_BASE` (686-1271), the stations' cooldown (`COOLDOWN_MS` 1285), `addItem`, `takeItem` (1436-1493). |
| 1498-1650 | Class and profession gates | `classGate` (1515), `halfGate` (1530), `creditWork` (1549), `rankStep` (1639). |
| 1651-3617 | Starting tools, mining, chopping, charcoal | `TOOLS` (1739) and tool wear (1810-2113); salt (`mineSalt` 2114); the swing animation (2632-2898); ore deposits (`DEPOSIT_SIZE` 2255, 2959-3058); `mineOre` (3059); chopping blocks (3342-3549, `chopWood` 3463); the kiln (`burnCharcoal` 3553). |
| 3618-5070 | Character creation (chargen) | See "Character creation" below. |
| 5071-5232 | Event handlers | `mp.onDeath` (5090), `mp.onRespawn` (5223). `ensureProperties()` and `startChargenTimer()` run at load here (5078-5079). |
| 5233-7466 | Scripted activators, harvesting, fishing, hunting | The generated `HARVESTS_BY_BASE`, `FISH_BY_BASE`, `GAME_BY_BASE`, `CROPS_BY_BASE`, `HUNTS_BY_BASE` blocks; `harvest` (6165), `fish` (6236), `game` (6343), `loot` for carcasses (6996), `farmActivate` (7102); `mp.onActivate` (7139), which routes every press; `publishServerBases` (7393). |
| 7467-9556 | Crafting | `RECIPES_BY_ID` (7549-9499), `isRecipe` (9507), `professionName` (9527). |
| 9557-9600 | Property doors | `BUILDING_BY_DOOR`, `BUILDING_NAME`, `WAY_OUT`. |
| 9601-10305 | Benches | `BENCH_BY_BASE` (9627-9633), `raceOf` (9664), `raceGate` (9718), `BENCH_ACCESS` (9735), `benchGate` (9748), `craftAnswer` (9834), `recipelessCraft` (10033). |
| 10306-10458 | `mp.onCraft` | Key recipe (10306), the handler (10309), and the "gamemode loaded" line (10454). |
| 10459-10643 | Voice feed | Positions to the voice service; the `online.json` writer (10561). |
| 10644-10992 | Character roster | `private\characters.json` (10708), sent to the site. |
| 10994-11515 | The door | The allowed list. See "The door". |
| 11517-11671 | Server manifest | `data\manifest.json` (11564), `publish` (11570). |
| 11674-13071 | Progression | The rulebook: `RANKS` (11715), `SPELL_IDS` (11826-11930), `TUNING` (11945), state (12365), rules (12577), the spell book (12885), `TABLE` (12361), `canDo` (13052). |
| 13073-14363 | Farming | Plots, rank and time (13360), the land (13425), claims in `private\farm-claims.json` (13527), pressing (13746), commands `/plant`, `/claim`, `/plot` (14031). |
| 14365-16818 | Property | See "Property, offices and rent". |
| 16820-17238 | Spoils | Nothing weapon, armour, tool or gold is spawned in the world; `strip` (17029), purses (`isPurse` 16990, `purse` 17191), where gold comes from (17157). |
| 17242-18512 | Character | Stores the answer as `thornswoodCharacter` (17291) and pushes the panel; `gate` (18061), `gateHalf` (18076), `credit` (18129), `/pick` and `/spend` in `command` (18212). |
| 18514-20800 | Chat commands | See "Chat and commands". |
| 20802-21085 | Containers and the audit | `mp.onPutItem` (20814), `mp.onTakeItem` (21075), `mp.onDropItem` (21080), audit helpers (21032-21069), lines `take:` and `drop:` in `thornswood.log`. |
| 21086-22922 | Needs | See "Needs". |
| 22924-23757 | Social | Friends, parties, mutes, journals, the panel, `thornswoodNear` (22983). |
| 23759-24247 | Trade | Two people, two offers, both confirm: `begin` (23851), `gold` (24012), `confirm` (24025), `swap` (24048). |
| after Trade | Mod settings | Issue #488, added 28 September. The 176 GLOB records of five classic mod menus (`MOD_GLOBALS`), kept per profile in `private\mod-settings.json` from the plugin's `/modset` lines and put back at login through `thornswoodModSettings` and its updateOwner script. `tests\test-mod-settings.js`. |

## Startup and settings

At load, in file order: the tables at 23-35; the git blob id is logged
(`gamemode.js:222`); the respawn properties are declared and the chargen timer
starts (`gamemode.js:5078-5079`); `publishServerBases` writes
`data\server-bases.json` (`gamemode.js:7458`); `gamemode.js:10454` logs
"gamemode loaded" with cell, station and town counts; then each later block
runs its own start. The last log line of a load is the list of chat words
(`gamemode.js:20798`).

Settings come from `server-settings.json` in the server's own folder, the
working directory (`gamemode.js:125-127`). The gamemode reads `dataDir`
(`gamemode.js:116`), `privDir` (`gamemode.js:10678`), `thornswoodVoicePort`
(`gamemode.js:253`), `thornswoodChargen` (`gamemode.js:3652`),
`thornswoodAdmins` (`gamemode.js:20300`) and `loadOrder`
(`gamemode.js:11623`). `Deploy-Gamemode.ps1` writes that file on every deploy
(`scripts\deploy\Deploy-Gamemode.ps1:-NotePropertyName dataDir -NotePropertyValue 'data'`).

## Character creation

`gamemode.js:3618` explains why there is a timer and no menu: SkyMP gives the
gamemode no connect event. `chargenTick` (`gamemode.js:4365`) runs every
`CHARGEN_TICK_MS` (`gamemode.js:3687`) and moves each person through the
stages kept in the actor property `thornswoodChargen` (`gamemode.js:3668`):

1. `appearance`, set by `beginAppearance` (`gamemode.js:4323`) in the hall
   (`HALL` 3833, `sendToHall` 4290), while the face is made.
2. `choosing`, set by `beginChoosing` (`gamemode.js:3991`): the choice is made
   on K in the character panel.
3. `done`, set by `arriveAt` (`gamemode.js:4055`), which moves the person to
   the inn of the town they picked (`CHARGEN.towns` as `PASSAGES`, 3893).

An old `arriving` state is folded into `done` (`gamemode.js:4668-4671`).
`"thornswoodChargen": false` in `server-settings.json` switches the hall off.

Body shape is height and weight only (#993, "BODY SHAPE" in `gamemode.js`).
`mp.onUpdateAppearanceAttempt` holds the weight in a sent appearance to 0 to
100 and drops any field the engine does not know. `thornswoodBodyReset` in
`server-settings.json` puts every character made before this through the same
check once when it comes online; it is on unless it is `false`.

## The door

`gamemode.js:10994`. It compares each connection's profile id with
`private\allowed.json` (`gamemode.js:11059`), fetched from the site with the
key in `private\door.json` (`gamemode.js:11364`) and refreshed on a timer
(`gamemode.js:11497-11503`). It turns somebody away only when that file says
`"enforce": true`; otherwise it writes WOULD TURN AWAY in `private\door.log`
(`gamemode.js:11060`). `scripts\ops\Set-Door.ps1` sets both. Developer-Guide.md,
"Who gets into the game", says what it can and cannot keep out.

## Professions, benches and BENCH_ACCESS

The rulebook is `TABLE` in progression (`gamemode.js:12361`). Stations ask
`classGate`/`halfGate` early in the file and `gate`/`gateHalf` in the
character block. A crafting bench is allowed or refused by `benchGate`
(`gamemode.js:9748`): `BENCH_BY_BASE` turns a furniture base into its bench
keyword, and `BENCH_ACCESS` says for each keyword whether anyone may use it
and otherwise which profession halves may, from which rank. `craftAnswer`
(`gamemode.js:9834`) then checks the recipe in `RECIPES_BY_ID`, and
`raceGate` (`gamemode.js:9718`) the race lock on a people's own dress.

## Spells, tomes and staff spells

The rules are in progression and the three blocks after the character block.

- **A mage's spells.** Spell points are `spells.points` (two to start, one per
  rank of a school, two at Master). `pickSpell` (K panel, `/pick spell`) and
  `learnFromTome` (reading a tome) ask the same three things: a point, the
  rank in the spell's school, and a spell of that school one rank down.
  Somebody a Master mage taught (`teach`) holds `LIMITS.outsiderSpells`
  places instead of points, and their school never leaves Novice.
- **Spell tomes** (`thornswood spell tomes`). `mp.onReadBook` asks `read`,
  which resolves the tome's spell from the records and runs `learnFromTome`;
  answering false keeps the tome and takes the spell back.
- **Staff spells** (`thornswood staff spells`, #1128). What a staff binds is
  unlocked into `staffSpells` (spell descs), and `craftAnswer` refuses a staff
  whose spell is not there. An Enchanter unlocks on K with staff spell points
  (`staffPoints`: two to start, one per Bladebinder rank, two at Master),
  their Bladebinder rank capping the spell's rank and a staff spell of the
  rank below needed (`pickStaffSpell`, `/pick staffspell <desc or name>`), no
  tome. Somebody a Master Bladebinder taught learns one only from its tome,
  under `LIMITS.outsiderSpells` and Novice only (`learnStaffFromTome`). Each
  staff spell's rank is the rulebook's when `SPELLS` lists it, else the one
  `Build-RecipeTable.ps1` read from the records into `STAFF_SPELLS`. An
  unlocked staff spell is put on the character with `spellOn` (and again on
  every spawn in `grantKnown`), because Skyrim's crafting menu lists a staff
  only for somebody who knows its spell.

## Property, offices, rent and gold

The register is `private\property.json` (`registerPath`, `gamemode.js:14529`;
`save`, 14591). A claim is made at the door (`touched` 14730, `claim` 14888)
and carried by the deed (`giveDeed` 14869). Locks and keys start at 14958
(`lockScript` 15032, `mold` 15284, `cutKey` 15525). A Jarl, the one admin
grant, names stewards (`loadStewards` 14635, `stewardCmd` 16708), and only a
steward can `evict` (16763). A hold's box takes gold only (`putIn` 15948);
rent (`rentDue` 15996, `rentCmd` 16033) and board fees (`takeGold` 16348)
land in it. Notice boards are 16100-16700. Coin enters the world in one
place, the starting purse (`purse` 17191, `test-one-mint.js`), and otherwise
moves by trade (`gold` 24012). The spoils block strips spawned gold from the
world (16820), and a coin purse found in it counts as gold (16961).

## Needs

Hunger, thirst and exhaustion, with warmth, in one block. The whole balance
is `NEEDS` (`gamemode.js:21152`), `COST` (21530) and `TEMP_COST` (21563).
Warmth: `warmthTarget` (21784), `fireWarmth` (21839), `exposure` (21878),
`weatherRow` (21920) off `WEATHER`, `insulation` (22134) off `WARMTH`. Food
and drink: `foodKind` (21972) off `FOODS`, `waterKind` (21862) off `WATERS`,
`consumed` (21997). The bard (22198), which the tick reads off the emote
wheel (`bardSeen`, #1631), `/rest` (22329), the tick (22518), the HUD script (22579) and burning (22782). State
is `thornswoodNeeds` (21137).

## Chat and commands

`WORDS` (`gamemode.js:18537`) is every word the server answers, and the list
at `gamemode.js:18584` is the part everybody is told about. `handle`
(`gamemode.js:19277`) answers each one. The teleport is here
(`gamemode.js:18608`), because the client forwards only five console commands
and `coc` is not one of them. Roles are `admins`, `isDev`, `isPlaytester`
(`gamemode.js:20297-20395`). The restart countdown is 20280-20720: Ship and
the Deploy scripts drop `restart.json` in the data folder
(`gamemode.js:20617`), and the gamemode warns at the marks in `MARKS`
(20295), on screen at 60 and 30 seconds.

## How it talks to the plugins

There is no custom packet. Two paths:

- **Commands in.** A line typed in the game's chat starting with `/` goes up
  the voice socket, and the voice service queues it
  (`voice\voice-server.js:1488-1527`). Every 1.5 seconds the gamemode
  asks `GET /commands?ack=1` on `127.0.0.1:<voice port>`
  (`gamemode.js:20746`), runs each one through `dispatch`
  (`gamemode.js:18798`), which holds a line for a character not yet back in
  the world, and acknowledges with `POST /commands/ack`. Ids already run are
  remembered so a command offered twice runs once (`gamemode.js:20716-20744`).
- **Answers and state out.** Chat replies go back through the same service,
  `POST /say` (`toProfile`, `gamemode.js:18677`). Everything a panel or HUD
  draws is an actor property made with `mp.makeProperty`
  (`thornswoodCharacter`, `thornswoodNeeds`, `thornswoodTrade` and the rest),
  which the client scripts in the property read.

The voice feed (`gamemode.js:10459`) posts every position to
`POST /positions` every 200 ms. `voicePort()` reads the port from
`server-settings.json`, so the dev server talks to the dev voice service.
Do not run `scripts\deploy\Add-VoiceFeed.ps1`: it writes the older
`voice\gamemode-voice.js` over this block, with 7778 written in and no
party field (`voice\README.md:12-18`).

## Where its data lives on the VPS

In the server's folder, `C:\Thornswood-Server` live and
`C:\Thornswood-Server-Dev` dev:

| Folder | What the gamemode keeps there | Served to anybody? |
|---|---|---|
| `data` | `online.json`, `manifest.json`, `server-bases.json`, `thornswood-log.json`, `restart.json` | Yes: the resources port (3000 live, 7788 dev) hands out anything under it over plain HTTP (`gamemode.js:55-58`) |
| `private` | `characters.json`, `allowed.json`, `door.json`, `door.log`, `property.json`, `farm-claims.json`, `mod-settings.json` (the first six moved from `data` on 25 September, issue #541, because they carry profile ids; the gamemode carries an old copy across on first load) | No |
| `world` | Not the gamemode's: SkyMP's changeform database, every reference the server has written to (`scripts\ops\Wipe-Saves.ps1:the changeform database. Every reference the server has ever written to`; `scripts\release\Where.ps1 ChangeForms` names its folder in the server build) | No |
| the folder itself | `thornswood.log`, rolled at 4 MB with five kept (`gamemode.js:74-108`) | No |

`scripts\ops\Wipe-Saves.ps1` starts the world over by moving `world`,
`private\characters.json`, `private\property.json` and `private\farm-claims.json` (and the old copies in `data`, for a server still on the older gamemode).

## Generated tables

Never hand edit these. Each script writes its json in `game\data` and then
replaces its own block or line in `game\gamemode.js`. Run the Build-Recipe step
after the ore, harvest, hunt and race tables, and Build-Bench after it,
because each reads the one before.

| In gamemode.js | Script | Json | Where the script installs it |
|---|---|---|---|
| `WATERS` line 26 | `Build-WaterTable.js` | `waters.json` | `Build-WaterTable.js:257-272` |
| `WEATHER` line 27 | `Build-WeatherTable.js` | `weather.json` | `Build-WeatherTable.js:212-218` |
| `WARMTH` line 28 | `Build-WarmthTable.js` | `warmth.json` | `Build-WarmthTable.js:398-399` |
| `FOODS` line 29 | `Build-FoodTable.js` | `food.json` | `Build-FoodTable.js:324-335` |
| `RACES` line 30 | `Build-RaceTable.js` | `races.json` | `Build-RaceTable.js:274-289` |
| `ORES_BY_BASE` 686-1271 | `Build-OreTable.ps1` | `ores.json` | `Build-OreTable.ps1:// ==== end ORES_BY_BASE ====` |
| `HARVESTS_BY_BASE` 5341-5454, `FISH_BY_BASE` 5509-5528, `GAME_BY_BASE` 5644-5655, `CROPS_BY_BASE` 5901-5920 | `Build-HarvestTable.ps1` | `harvests.json` | `Build-HarvestTable.ps1:All four installs work on the text of gamemode.js` |
| `HUNTS_BY_BASE` 6491-6857 | `Build-HuntTable.ps1` | `hunts.json` | `Build-HuntTable.ps1:// ==== end HUNTS_BY_BASE ====` |
| `RECIPES_BY_ID` 7549-9499 | `Build-RecipeTable.ps1`, which also reads `docs/systems/cut-items.json` for what leaves the open book | `recipes.json` | `Build-RecipeTable.ps1:// ==== end RECIPES_BY_ID ====` |
| `STAFF_SPELLS` (staff spells block) | `Build-RecipeTable.ps1`, with each spell's school and rank | none | the STAFF_SPELLS markers |
| `BUILDING_BY_DOOR` 9575-9582, `BUILDING_NAME` 9584-9590, `WAY_OUT` 9592-9599 | `Build-DoorTable.py` | `doors.json` | `Build-DoorTable.py:450-483` |
| `BENCH_BY_BASE` 9627-9633, `BENCH_ACCESS` 9635-9736 | `Build-BenchTable.py`, from `recipes.json` | none | `Build-BenchTable.py:362-376` |
| `SPELL_IDS` 11826-11930 | `Build-SpellTable.ps1` | `spells.json` | `Build-SpellTable.ps1:// ==== end SPELL_IDS ====` |
| `DATA` 23 | `Install-GamemodeConsts.js` | `data.json` | `Install-GamemodeConsts.js` |
| `STATIONS` 24 | `Install-GamemodeConsts.js` | `stations.json` | `Install-GamemodeConsts.js` |
| `ITEMS` 25 | `Install-GamemodeConsts.js` | `items.json` | `Install-GamemodeConsts.js` |
| `CHARGEN` ~3878 | `Install-GamemodeConsts.js` | `chargen.json` | `Install-GamemodeConsts.js` |

`DATA`, `STATIONS`, `ITEMS` (lines 23-25) and `CHARGEN` (around line 3878)
are installed from checked-in JSON by `scripts\dev\Install-GamemodeConsts.js`
(`data.json`, `stations.json`, `items.json`, `chargen.json` under `game\data`).
They are not read out of the plugins: the values were recovered into JSON when
`tools\thornswood-src` was retired (5d1f3f0). Edit the JSON, then run the
installer. `--check` proves the gamemode matches. Older comments named
`respawn-holds.json`; that file never lived in this repository.
`fires.json` is not in the gamemode: it goes into `thornswood-front.js`.

## Deploying it

Everything goes to the dev server first.

- **Dev:** `.\scripts\deploy\Deploy-DevGamemode.ps1`. It checks the file parses with
  `node --check` (`scripts\deploy\Deploy-DevGamemode.ps1:& node --check $Gamemode`),
  and on a machine without node it skips that check with a warning
  (`scripts\deploy\Deploy-DevGamemode.ps1:so the syntax check was skipped`), reads how many are
  on, warns them, sends `gamemode.js` alone to `C:\Thornswood-Server-Dev` and
  restarts only the process on the dev port. `-LoadOrder` brings the dev load
  order up to the built server's; a change to the CHARGEN records needs
  `Deploy-Gamemode.ps1 -Vortex` first (`scripts\deploy\Deploy-DevGamemode.ps1:changes the CHARGEN records needs Deploy-Gamemode.ps1 -Vortex first`).
- **Live:** `.\scripts\deploy\Deploy-Gamemode.ps1` copies `gamemode.js` into the local
  server build (`scripts\release\Where.ps1 ServerDist`, `scripts\deploy\Deploy-Gamemode.ps1:Copy-Item -LiteralPath $Gamemode -Destination (Join-Path $Dist 'gamemode.js')`)
  and writes `server-settings.json` and the load order; it does not talk to
  the VPS (`scripts\deploy\Deploy-Gamemode.ps1:This script does not stop the live server and does not talk to the VPS`). Then `.\scripts\deploy\Deploy-Server.ps1`
  stages the build on the VPS, warns, swaps and restarts
  (`scripts\deploy\Deploy-Server.ps1:game\gamemode.js as the commit holds it`: it takes `gamemode.js` from `game` as committed, not the copy in the build).

Ship does not carry `gamemode.js`. `.\scripts\vps\Check-LiveGamemode.ps1` says
whether the live server runs the file in this repository, by hash.

## Tests that read it

CI runs every `tests\test-*` harness (`.github/workflows/build.yml:110-119`).
These read `gamemode.js`, most by running one block against a stubbed `mp`.

| Area | Tests |
|---|---|
| Logging and identity | `test-thornswood-log.js`, `test-gamemode-id.js`, `test-build-stamp.ps1` |
| Chargen and arrival | `test-arrivals.js`, `test-arrival-line.js`, `test-creation-close.js`, `test-creation-lines.js`, `test-creation-quiet.js`, `test-new-character.js`, `test-stuck-in-the-hall.js` |
| Gathering and mining | `test-deposit.js`, `test-chopping-gate.js`, `test-cooldown-sweep.js`, `test-mine-buildings.js`, `test-farming.js`, `test-eggs.js` |
| Crafting and rules | `test-rulebook.js`, `test-nobody-makes.js`, `test-race-gate.js`, `test-race-table.js`, `test-recipeless-craft.js`, `test-bard-instruments.js`, `test-staff-spells.js`, `test-spell-tomes.js`, `test-enchanter-staff-spells.js`, `test-classes-page.js` |
| Property and economy | `test-deed-title.js`, `test-locks.js`, `test-key-chain.js`, `test-mold-key.js`, `test-cut-key.js`, `test-offices.js`, `test-coffers.js`, `test-boards.js`, `test-unpin.js`, `test-spoils.js`, `test-one-mint.js` |
| Needs | `test-needs.js`, `test-temp.js`, `test-food-table.js`, `test-hud.js` |
| Chat, commands, door | `test-command-ack.js`, `test-held-commands.js`, `test-help.js`, `test-tp.js`, `test-dice.js`, `test-door.js`, `test-allowed-failed.js`, `test-audit-handlers.js` |
| Social | `test-social.js`, `test-party-markers.js` |
