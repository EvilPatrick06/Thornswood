# Splitting the gamemode's source

This page is the plan for issue #2181: how `game\gamemode.js` could be
written as many source files and still reach the server as the one file it
needs. It is a plan only. Nothing here has been split, and no behaviour
changes until Patrick picks an option (the decision is on #2181). How the file
is laid out today is [GAMEMODE.md](GAMEMODE.md).

Measured on 12 Oct, about 1:30 AM, at origin/main 55c22556, with the engine
fork at its pin 1afaf2ef.

## What the file is today

- **Size.** 6,073,192 bytes and 64,664 lines. GAMEMODE.md still says about
  24,000 lines; it was written on 25 Sep and the file has grown 2.7 times since.
- **Generated against written by hand.** About 18,700 lines and 3.9 MB (64% of
  the bytes) are tables that scripts write and nobody edits: the one-line tables
  at lines 23 to 30, `ORES_BY_BASE`, the harvest, fish, game and crop tables,
  `HUNTS_BY_BASE`, `RECIPES_BY_ID` (0.61 MB), `ITEM_NAMES` and `ADMIN_NAMES`
  (1.24 MB, lines 11186 to 26319), the door and bench tables, `SPELL_IDS`,
  `STAFF_SPELLS`, the NPC population data (one line of 1.14 MB at 62021) and
  the merchant catalogues. About 45,900 lines and 2.2 MB are written by hand.
  Nineteen scripts in `scripts\dev` (`Build-*` and `Install-GamemodeConsts.js`)
  each rewrite their own region of the file; GAMEMODE.md "Generated tables"
  lists them.
- **Sections.** About 50. The first 28,127 lines are split by dashed comment headers
  (`// small helpers`, `// gathering stations`, `// crafting` and so on). From
  line 28128 on, 32 blocks sit between `// ==== thornswood X ====` and
  `// ==== end thornswood X ====`, plus seven `// NAME BEGIN` and `// NAME END`
  regions for the NPC and merchant code. About 2,300 lines are not inside a
  well-formed marker: the books block (`/* BOOKS-START */`, after line 47720), the
  containers and take limit (51699 to 52363), and the seats block, whose
  opening banner has three slashes (30570).
- **Modules already exist once.** `game\merchant-trading.js`,
  `game\merchant-settlement.js` and `game\quest-transactions.js` are written as
  ordinary files. `scripts\dev\Build-MerchantGamemode.js` wraps them, with two
  catalogues, into the region between `// MERCHANT TRADING BUNDLE BEGIN` and
  `END`, and `--check` fails when the region is not what the sources make
  (`tests\test-merchant-deployment.js` runs it; the check takes 0.3 seconds).
  That is this plan, done once.

## Who edits it, and whether they collide

Read from the 1,053 pull requests merged between 25 Sep and 12 Oct
(GitHub's list of closed pull requests, and each one's merge commit):

- **188 of them (18%) changed `game\gamemode.js`.** The busiest days were
  5 Oct (58) and 29 Sep (29). Together they added 74,436 lines and removed
  9,772; the median one added 66 and removed 10.
- **By branch prefix:** claude 115, github 22, codex 15, herald 7, smeagle 5,
  cursor 4, and 20 more from other prefixes (djinn, patrick, launcher, vortex,
  installer, single-purpose branch names).
- **Where they edit.** 78 touched one section, 110 touched two or more (two
  touched nine). The most edited sections: chat commands 57, code outside any
  banner 35, property 28, scripted activators 28, character 26, the benches 24,
  the starting tools 20, social 19, crafting 16, needs 13. 37 of the 46
  sections that were touched were touched from more than one branch prefix.
  So nobody owns a section; ownership by lane would not match how work is done.
- **Merge conflicts: none at merge time.** For each of the 188, the pull
  request's own head (GitHub keeps `refs/pull/N/head`) was merged with main as
  it stood just before the merge (`git merge-tree`). 0 of 188 conflicted, in
  `gamemode.js` or any other file. In 57 of them main had changed `gamemode.js`
  under the branch (up to 6 commits), and git merged those cleanly. This is a
  lower bound: a branch that was rebased to resolve a conflict before it merged
  shows its resolved head here, so conflicts met and fixed along the way are
  not counted. No other record of them exists in the repository or the vault.

So the measured cost of one file is not merge conflicts. It is size: a file of
6 MB is past what editors, review pages and the tools the team uses read
comfortably in one go, the map in GAMEMODE.md has fallen behind it, and every
test that reads it (240 files under `tests` name it; 128 name a block's banner
and 98 run code from it with Node's `vm` module) depends on banner text staying
exactly as it is.

## What the server needs (the loader)

Read from the fork, `skymp5-server/ts/index.ts` at 1afaf2ef:

1. **One file.** `gamemodePath` in `server-settings.json` names one file.
   `requireTemp` reads it as text, writes it to a new temporary folder under a
   random name, `require`s that copy, and deletes the folder.
2. **No relative requires.** A `require('./x')` resolves beside the temporary
   copy, where nothing is, and fails. Node's own modules (`fs`, `path`,
   `crypto`) work.
3. **No other file of ours at run time.** An absolute `require` of another file
   would load once and stay in Node's module cache: a hot reload re-requires
   only the new temporary copy, so the other file would keep its old code. And
   the watcher (`chokidar.watch(absoluteGamemodePath)`) watches the one file, so
   changing the other file reloads nothing.
4. **Reload only on change.** `requireUncached` compares the text with what it
   last loaded and reloads only when it differs, after `mp.clear()`.
5. **Line numbers.** An error names the temporary copy and a line in it, which
   is the line in `gamemode.js`. No source map is read.

What our own scripts need, all of which read the committed file:

- `scripts\deploy\Artifact.ps1` builds the gamemode artifact from
  `game/gamemode.js` as the commit holds it, and `Deploy-DevGamemode.ps1`,
  `Deploy-Server.ps1` and `Publish-Server.ps1` send that.
- `gamemodeId` (`gamemode.js`, around line 208) logs the git blob id of the
  file the server loaded, and `scripts\vps\Check-LiveGamemode.ps1` compares it
  with the repository.
- The 240 test files read `game\gamemode.js`.

So whatever the source looks like, `game\gamemode.js` stays one committed file
with everything inlined.

## The options

**A. Do nothing.** Keep one file. Cost: none now. The file keeps growing (2.7
times in 17 days), the map keeps falling behind, and 128 tests keep depending
on banner text inside one 6 MB file. What it would need anyway: GAMEMODE.md's
line numbers brought up to date, and the three-slash seats banner fixed.

**B. Source files, joined into the committed `gamemode.js` (recommended).**
The code is written in `game\gamemode\` as one file per section, in order, and
a build script joins them, byte for byte, into `game\gamemode.js`, which stays
committed. The join is plain concatenation in a listed order, not a bundler, so
the sections keep sharing one scope exactly as they do now: no code changes, no
`require`, no `module.exports` needed. The generated tables move into files of
their own that their `Build-*` scripts write, instead of regions of the big
file. Deploys, records, the blob id and every test keep reading the same file.

**C. Source files, `gamemode.js` built at deploy time and not committed.** The
same sources, but the joined file is made by the artifact step. This is the only
option that takes `gamemode.js` out of reviews and merges altogether. It changes
`Artifact.ps1`, the server records, `Check-LiveGamemode.ps1` (the blob id would
no longer be a blob in git) and all 240 tests, and since no conflict was
measured in the joined file, it buys little that B does not.

**D. Real modules with `require`.** Refused by the loader: relative requires
fail (point 2) and absolute ones go stale on a hot reload (point 3).

**E. A bundler (esbuild, which the fork already uses for its own server code).**
Turns modules into one file, but rewrites the code it joins, so the output is
no longer the sections as written, a line in an error no longer matches a line
in a source file, and a byte-identical first step is impossible. Not needed
while the sections already share one scope.

## How option B would work

**Layout.**

```
game\gamemode\
  order.txt                 the files, in the order they are joined
  00-header.js              'use strict', the contract comment
  01-tables.generated.js    DATA, STATIONS, ITEMS, WATERS ... (lines 23-30)
  02-small-helpers.js
  ...
  40-needs.js               the "thornswood needs" block, banners included
  ...
  data\recipes.generated.js RECIPES_BY_ID, written by Build-RecipeTable.ps1
  ...
```

A file whose name ends `.generated.js` is written only by its `Build-*` script,
and says which one in its first line. Every other file is edited by hand.

**The build.** `scripts\dev\Build-Gamemode.js` reads `order.txt`, joins the
files, and writes `game\gamemode.js`. `--check` fails, naming the first line
that differs, when the committed file is not what the sources make. Launcher
builds runs `--check`, the way `test-merchant-deployment.js` runs the merchant
bundle's. `--where 41233` prints the source file and line for a line of
`gamemode.js`, for reading an error in the server log.

**Equivalence.** The first split must produce the same bytes. That is provable
with nothing running: `game\gamemode.js` keeps the same git blob id, so the
server's "gamemode.js is git blob" log line, `Check-LiveGamemode.ps1` and every
test are unchanged, and no deploy is needed for any of the split's pull
requests.

**Editing after the split.** A change goes in the source file, then the build
runs, and both are committed together. Hand edits to `game\gamemode.js` are
refused by `--check`. A merge conflict in `gamemode.js` is resolved by
resolving the source files and building again, never by editing the joined
file.

**Debugging.** Lines in errors stay lines in `gamemode.js`; `--where` maps one
back. No source map is involved, because the server reads none.

**Rollback.** At every stage the committed `gamemode.js` is the file that runs,
so going back is reverting the pull request. Until stage 4, reverting a stage
leaves the server's file byte for byte the same.

## The stages

Each stage is one pull request, and each must leave `game\gamemode.js` byte for
byte as it was (same blob id).

1. **The build, splitting nothing.** `Build-Gamemode.js` with `order.txt`
   naming one file, `game\gamemode\all.js`, which is today's file; `--check` in
   Launcher builds; a test that the join of the parts is the committed file.
   The three-slash seats banner and the unbannered regions get banners first,
   in their own pull request, because that does change the file.
2. **The generated tables out.** Each `Build-*` script writes its own
   `.generated.js` file instead of rewriting a region of the big one. This takes
   about 3.9 MB out of the file people edit, and is the largest gain for the
   least risk.
3. **The blocks out.** One file per `// ==== thornswood X ====` block and per
   `BEGIN`/`END` region, in their current order.
4. **The early part out.** Lines 1 to 28127 split by their dashed headers. This
   is the part that shares the most top-level names, so it goes last, and only
   by cutting at existing headers.
5. **Tests read the source files** (optional). Tests that cut a block out by
   its banner can read the block's own file instead. They keep working without
   this step, because the joined file still holds every banner.

What stays the same throughout: the server, the deploy scripts, the records and
the blob id check. What is new: one build script, one check in Launcher builds,
and the rule that `game\gamemode.js` is never edited by hand.

## What is not known yet

- How long the build takes on a 6 MB join. The merchant bundle check, which
  reads and compares the whole file, takes 0.3 seconds; the full join has not
  been timed.
- Whether any tool the team relies on writes into `game\gamemode.js` outside
  the 19 `Build-*` scripts (an editor's format on save, a lane's own script).
  Stage 1's `--check` is what would find out.
- Conflicts met and fixed before merging, which the measurement above cannot
  see.
