# Splitting the gamemode's source

This page is the plan for issue #2181: how `game\gamemode.js` could be
written as many source files and still reach the server as the one file it
needs. Patrick chose option D on 12 Oct 2026 (on #2181). Nothing has been split yet; each stage must leave the running gamemode's behaviour the same until that stage's proof says otherwise. How the file
is laid out today is [GAMEMODE.md](GAMEMODE.md).

Measured on 12 Oct, about 1:30 AM, at origin/main 55c22556, with the engine
fork at its pin f1e18a4a.

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

Read from the fork, `skymp5-server/ts/index.ts` at f1e18a4a:

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

## Decision (Patrick, 12 Oct 2026): D

Generated tables move out of the code into data files; the hand-written code
splits into small modules by system; a bundler joins them into the **one file**
the server loads when the **gamemode artifact** is made (the versioned artifact
every deploy already builds and checks). Git holds **sources and data only**.
The server's proof of what runs is the **artifact hash**. Tests load the built
artifact.

This is not option B below (committed joined `gamemode.js`). It is closer to
building at artifact time, with a real split and a bundler, and with proof
moved off the git blob of a committed `gamemode.js`.

### Why not the other shapes

- **A (do nothing):** the file keeps growing; the map stays stale.
- **B (sources joined into a committed `gamemode.js`):** keeps blob-id proof and
  every test on a committed file, but Patrick's call was D.
- **C (join only at deploy, no bundler/modules):** takes the file out of git but
  does not define modules or data-at-source the way D does.
- **Real `require` of our files at run time:** refused by the loader (relative
  requires fail beside the temp copy; absolute ones go stale on hot reload).
- **Bundler alone without artifact proof:** still leaves "what runs" ambiguous.

### How D meets the loader

The live server still receives **one** file. Sources and `game/data/*.json`
live in git. `scripts/dev/Build-Gamemode.js` (and the artifact step that calls
it) bundle them into that file. No relative `require` at run time. Hot reload
still watches one path. Until proof moves to the artifact hash, each stage
keeps behaviour identical to today's committed file.

### What already exists

- Many tables already have `game/data/*.json`; their `Build-*` scripts still
  also inline them into `gamemode.js`.
- `game/merchant-trading.js`, `merchant-settlement.js`, `quest-transactions.js`
  and `kill-contracts.js` are already modules; `Build-MerchantGamemode.js`
  inlines them (and catalogues) into a marked region. That is the pattern to
  generalize.

## Stages (each one pull request)

1. **Docs and scaffold (this change).** This page records D. `Build-Gamemode.js`
   exists with `--check` so Launcher builds can hold the bundle contract once
   sources appear. No split yet.
2. **Tables out.** Selected `Build-*` scripts stop rewriting regions of
   `gamemode.js`. The bundler embeds the matching `game/data/*.json` so the
   server still sees the same consts. Behaviour unchanged; the committed file
   (or the artifact, once we stop committing the join) shrinks for editors.
3. **Modules and bundler.** Hand-written blocks move under `game/gamemode/` by
   system; the bundler joins them in a listed order into the one server file.
4. **Tests on the artifact.** The 240 tests that read `game/gamemode.js` run
   against the built output (or a cached build in CI).
5. **Proof on the artifact hash.** `gamemodeId`, `Check-LiveGamemode.ps1` and
   deploy records name the artifact, not a git blob of a committed join.
   Git stops holding the joined file.

## Scaffold

`scripts/dev/Build-Gamemode.js` is the entry. Today it only `--check`s that
the merchant bundle is current (delegates to `Build-MerchantGamemode.js
--check`) and prints that the full split is not started. Later it will read
`game/gamemode/order.txt`, embed data, and write the artifact file.

## Rollback

Until stage 5, going back is reverting the pull request. While the server still
loads a file whose text matches today's behaviour, a revert does not need a
special deploy beyond the usual gamemode put-back.
