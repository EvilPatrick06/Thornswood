# Claude takeover: every Grok lane has stopped (24 Oct 2026)

On 24 Oct at 12:05 PM MT, Patrick stopped every Grok lane: Waystone, Anvil, Herald, Codex, Wyrd and Smeagle. Their claims are gone, and nothing they had running carries on. This note holds everything they left. It lives in the repo because the vault is no longer the source of truth (#3311). Claude needs nothing from the vault beyond the "Stale vault notes" list at the end.

Verified on GitHub and on One at about 12:30 PM MT on 24 Oct. main HEAD is `83ee2d42` (#3379), which pins `engine/skymp` at `7ae58fea`, the engine-changes tip.

## What was stopped and unclaimed

- One label removed: #2701 lost `claimed: Codex`, so its labels are now `area: Voice`.
- Comments: every other lane claim was a comment. Each issue below got "Unclaimed: lane stopped by Patrick 24 Oct; see the Claude handoff in the repo."
- No issue was closed or reopened, and no label was deleted.
- No PR was merged, closed or converted to draft. They are all where the lanes left them.
- **Left alone:**
  - Claude's own claims: #2166, #2578, and the takeovers #1178 and #2163.
  - #2564 (no GitHub claim; see Codex below).
  - #2519 (Djinn's).
  - skymp#41 (WiccanDjinn's).
  - Anything belonging to ChatGPT or Jhinswife.

| Lane | Issues unclaimed |
|---|---|
| Wyrd | #2484, #2487, #2486, #516, #2675, #2479, #513, #2264 |
| Herald | #512, #1383, #1390, #2697, #2705, #2302, #2613, #2703, #2483 |
| Waystone | #511, #2673, #2440, #2384, #2262, #1688, #1649, #2620 |
| Codex | #2701 (label), #2475, #2183, #2181, #2131, #1287 |
| Anvil | #2454, #1046, #507, #2652, #2662, #2299, #2573, #2563, #2599, #2668, #2680, #2382, #1384 |

That makes 44 issues, all still open.

## Runs still going when the lanes stopped: cancel them

At 11:56–11:58 MT, five skymp `Thornswood PR Windows` runs started after the lanes' last rebases. The connector the lanes used cannot cancel a run, so cancel these with `gh run cancel <id> -R EvilPatrick06/skymp`, or let them finish and read the result:

| Run | Branch | PR |
|---|---|---|
| 40118543953 | codex/1287-spawn-stages | skymp#80 |
| 40118536535 | codex/2262-equip-item-attempt | skymp#73 |
| 40118528214 | waystone/1649-crafted-as-data | skymp#78 |
| 40118425791 | anvil/1384-condition-120 | skymp#82 |
| 40118425190 | anvil/2382-flora-redraw | skymp#69 |

The PRs those runs build show `UNSTABLE` only because the runs haven't finished.

## Fork (EvilPatrick06/skymp) PRs and the pin

All of these are mergeable. Codex had planned this merge order:

1. **#73** `codex/2262-equip-item-attempt` @ `9dc87cce`, ready. Adds the `onEquipItemAttempt` event (#2262's engine half).
2. **#76** `waystone/1688-player-record-spells` @ `780b0188`, ready, CLEAN (#1688).
3. **#69** `anvil/2382-flora-redraw` @ `a8218f10`, ready (#2382).
4. **#82** `anvil/1384-condition-120` @ `83caae1c`, ready (#1384).
5. **#53** `herald/1294-rpc-local-test` @ `f6701340`, ready, CLEAN (#1294).
6. **#80** `codex/1287-spawn-stages` @ `7ce9d9ff`, ready (#1287). #71, the PR it was stacked on, already merged, so there is no stack any more.
7. **#78** `waystone/1649-crafted-as-data` @ `2b8639dc`, ready (#1649). It was DIRTY earlier on 24 Oct and was rebased at about 11:56 MT.
8. **#81** `herald/1383-brewed-bottle` @ `a6e0492c`, draft, CLEAN (#1383).

Not lane work:
- **#98** `codex/3079-npc-body-loot` @ `1960248b`, draft. Already Claude's from the ChatGPT takeover (`ops/claude-queue/3079-chatgpt-takeover.md`).
- **#41** is WiccanDjinn's. Don't touch it.

**Pin bump (nobody has opened it yet):** once the fork PRs are in, open one PR on main that:
- moves `engine/skymp` to the new engine-changes tip;
- adds `equipItemAttemptEnabled` (default off) to `scripts/deploy/ServerSettings.ps1` near lines 80–82, and to `records/remote-commands.json` if it should be switchable live.

The key exists nowhere on main today. Its old home, T#2060, closed. Don't bring back the closed T#2610 pin; its content is already in `7ae58fea`.

## Thornswood PRs the lanes left

- **#2621** `waystone/2262-strength-weapons` @ `db1b4190`, draft. GitHub reports it mergeable/clean against main today. On main's engine the handler is never called, though, so it must rebase onto the pin-bump PR and merge after it (#2262).
- **#2618** `anvil/2573-cuffs` @ `5474db76` on GitHub, draft, **DIRTY** (conflicts with main). Labelled `held`; that label is stale, because the 1.2.4 freeze it waited on is over. The real hold: per Claude on 19 Oct, the cuffs' client scripts repair state every frame and on a 5-second timer. The list of changes is on #2573 (design comment 6227464007).
  - Anvil was partway through on One: in `C:\ThornswoodTemps&Worktrees\2573-cuffs`, the local commit `dce5f6d5` (24 Oct 12:00 MT, "Guards cuff and free people…") sits 1 ahead of origin/main and is **not pushed**. `game/gamemode.js` also has uncommitted edits.
  - Six fixes remain from the #2573 list. Rebase #2618 on main, take or redo `dce5f6d5`, then do the six fixes.
- **#2632** `waystone/2620-remove-watchdogs` @ `f116df51`, draft, based on `anvil/2573-cuffs`. It lands after #2618: retarget to main, rebase, take the #2620 rewordings (root cause: #2620 comment 6238635847).

## Per lane: what's left

### Codex
- **#2701**, voice as words, client half. Nothing is on GitHub yet. Plan: comment 6253092282 (six parts). Patrick's answers: 6252949415. Four local branches on One are **unpushed** (no remote branch), each with a clean worktree under `C:\Thornswood-Repo\worktrees\`:
  - `codex/2701-game` @ `36ece351`: "HELD 1.2.4: voice as words above heads, two switches on P, either mute hides them"
  - `codex/2701-voice-wording` @ `95dec379`: the service notes plus a harness proving no caption is kept
  - `codex/2701-privacy` @ `540e24ca`: privacy page wording
  - `codex/2701-launcher` @ `3dea8184`: run note (speech model on the site, captions on for dev voice)

  Push them, or rebuild them from the plan, then open PRs. Herald's credits line for #2701 (the MIT notice for the speech model) still has to be added.
- **#1287**: land skymp#80, then the pin bump.
- **#2262** engine half: skymp#73, then the pin bump plus `equipItemAttemptEnabled`, then #2621.
- **#2131, #2181, #2183, #2475**: reopened on 22 Oct only for the Test task. No code is left. Claude closes them once each test is done. #2183 still needs Claude's live steps: `Watch-Outside -Install`, then run the reader.
- **#2564** (`tests/test-afk.js` fails on main): no GitHub claim. Codex had a local fix commit, `6c641839`, on One. It is on no branch and was never pushed, so `git -C C:\Thornswood-Repo show 6c641839` before it is garbage-collected, and cherry-pick it onto a fresh branch.

### Waystone
- **#511** (trade ships): decisions are recorded on the issue but nothing is built. The local worktree `worktrees\waystone-511-take-and-dropbox` (branch `waystone/511-take-and-dropbox`, at main `83ee2d42`, **10 uncommitted files**, not pushed) holds the start of it. Read it before redoing anything.
- **#2620**: PR #2632 (above). **#2262**: PR #2621 (above). **#1688**: skymp#76. **#1649**: skymp#78.
- **#2673, #2440, #2384**: claimed but no PR. #2384 has `2384-cursor-focus.md`; #2262 has `2262-wieldable-giant-club.md`.
- Rebase worktrees `worktrees\waystone-2262-rebase` and `worktrees\waystone-2620-rebase` match their pushed heads, so they're safe to remove.

### Anvil
- **#2382**: skymp#69, plus the queue note `2382-flora-harvest-model.md`. **#1384**: skymp#82.
- **#2573/#2618/#2632**: see above.
- **#1046**: the restore-from-backup rehearsal (start a restored server and connect). Due before 3 Nov.
- **#2680** (tell a holder when their door is picked or their deed shown): queue note `2680-holder-word.md`. A key check still needs doing on dev.
- **#2454, #507, #2652, #2662, #2299, #2563, #2599, #2668**: claimed, no open PR. Queue notes: `2454-fitted-outfits.md`, `2454-ccaa-3ba-mce-bodyslide.md`, `2563-journal-length.md`. `1046-restore-rehearsal.md` covers #1046; `1384-condition-120-pin-and-shut-benches.md` covers #1384.
- Anvil's skymp checkout on One is broken. Re-clone it rather than trust it.

### Herald
- **#1383**: skymp#81 (draft). **#1294**: skymp#53.
- **#512** (trading company): Patrick decided on 22 Oct (comment 6335277509) that a ship's hold pays a freight fee per load. Split out as **#3380** (open, `area: triage`): `game/data/trading-company.json` still has `"freightPerLoad": 0`. Patrick has to set the amount.
- **#1390, #2697, #2705, #2302, #2613, #2703, #2483**: claimed, no open PR. Queue notes: `2703-known-page-removed-mods.md`, `2705-hair-dye-help.md`, `1383-limbs-brews.md`, `1390-thalmor-patrols.md`, `2695-trading-company.md`. #2703 is the Known Issues page naming removed mods, which turns `test-known-page.js` red on nightly.

### Wyrd
- **#513** (the Thalmor war): design at comment 6387653497. Rev6 dependencies are listed there.
- Also left: #2659 (rebuild the NPC catalogue and `Thornswood-Last.esp` for KS Hairdos Lite) and #2660 (rebuild `recipes.json` for Cheddar's Mashups).
- **#2484, #2487, #2486, #516, #2479**: queue notes `2484-town-gates-unlocked.md`, `2487-key-recipe-off-forge.md`, `2486-last-esp-from-repo.md`, `516-woodworker-cobj.md`, `2479-cut-outs-held-back.md`. **#2264**: `2264-improved-eyes.md`. #2659/#2660 have `2263-ks-hairdos-lite.md` and `2265-cheddars-mashups.md`. **#2675**: suggestion, no work started.

### Smeagle
- No GitHub claims were open at the stop.

## Stale vault notes (C:\Thornswood Vault\Thornswood; read only, never edited)

Nothing in the vault is newer than 22 Oct 09:48. Treat all of it as history; the repo wins.

- `wiki\lanes\status.md` and `wiki\lanes\claude-queue.md`: banner says moved to the repo. Use `ops/status.md` and `ops/claude-queue/` instead.
- Lane pages, 22 Oct 09:48: `Installer.md`, `Launcher.md`, `Website.md`, `Vortex.md`, `Smeagle.md`, `GitHub.md`, `codex-npc-world.md`. Their "Open work" sections are from late Sept and early Oct, so they're wrong:
  - Vortex lists #690, #476, #479 and #394/#490 as open.
  - GitHub lists #738 and PR #732.
  - Launcher lists #617, #729 and PR #730.
- `claude-landing-lane-prs.md` (20 Oct): the 19–20 Oct landing. Still true: #2618/#2632 held for the cuffs fixes, #2621 waits on fork #73, don't close an issue before its PR is on main, don't bring back the #2610 pin.
- Early-Oct lane prep notes, all superseded by the issues themselves:
  - `wyrd-1181-preset-source-prep`, `wyrd-1178-collection-rev2-prep`, `wyrd-1258`, `wyrd-1178-loose-trace`
  - `waystone-1268-engine-pin` (#1268 is closed)
  - `temp-journal2-1016`, `temp-fish2-1379-water-draft`, `temp-chop-376-leftovers`
  - `installer-ship-umbrella`, `umbrella-ship-contract`, `one-only-jobs` (19 Oct release-desk jobs)
  - `installer-1318-menu-assets-prep`, `613-smith-leftovers`, `goblin-614/956`, `github-claim-workflow`
- `d\output\2026-10-05-claude-code-handoff.md`, `wiki\claude-queue\README.md`, and the vault's own `AGENTS.md`/`CLAUDE.md`: older copies. The repo's `CLAUDE.md` is current.

## Housekeeping on One once the work above is safe

These local worktrees belong to the stopped lanes. Remove each one only after its unpushed work has been pushed or deliberately dropped:
- `worktrees\codex-2701-*` (4)
- `worktrees\waystone-511-take-and-dropbox`
- `worktrees\waystone-2262-rebase`, `worktrees\waystone-2620-rebase`
- `C:\ThornswoodTemps&Worktrees\2573-cuffs`
