# 2652 merchant ledger release: Claude's sign-off on Delete-Person.ps1

Issue: https://github.com/EvilPatrick06/Thornswood/issues/2652
Root cause and design: https://github.com/EvilPatrick06/Thornswood/issues/2652#issuecomment-6244361712
PR: https://github.com/EvilPatrick06/Thornswood/pull/2663 (HELD 1.2.4 draft, branch anvil/2652-merchant-release, tip 508e1ef5)
Built on: https://github.com/EvilPatrick06/Thornswood/pull/2651 (Claude's, claude/2351-release-registers, 51e63016), merged in normally, so #2663 carries #2651's two commits until #2651 merges.
Parent: https://github.com/EvilPatrick06/Thornswood/issues/2351
Lane: Anvil.

## Why this is in the queue

#2663 edits scripts\vps\Delete-Person.ps1, which is Claude's area (#2583, #2351, #2651). It should not merge without Claude's sign-off on that file. The ask is a yes, or what to change, written on #2663. Nothing else in the PR needs Claude, beyond the merge order below.

## What changed in Delete-Person.ps1 (the part to sign off)

Diff against #2651's tip, not main:

1. RELEASED gains merchant-ledger.json:
   `/^(property|law|beds|farm-claims|embassy|books|dungeon-rewards-ledger|merchant-ledger)\.json$/i`
   So a dry run counts the ledger as `release` instead of `left`. A real run treats it like the other registers: if it names the person, that server gets private\deleted-characters.json, is stopped, and is started again.
2. The header comment drops the merchant ledger from "the game's registers that it does not let go". Only the old copies a game server kept in data are left there.
3. The comment above LIST and RELEASED says the merchant ledger is released like the rest, by the purse service at NPC startup (#2652).

Nothing else in the script moves. The list format, the stop and start, -Reapply and the copies set aside are #2651's, unchanged.

## What the gamemode does with it (context, in game\gamemode.js)

- release(who) on the purse service, under its writer lease. It runs for every entry, retired traders included:
  - A supply wait keyed by a listed form id or profile goes.
  - A waiting trade on a listed character is cleared. In debit the trader stays at previous, as a refused debit does. In credit it keeps the next it already holds, and no supply wait is stamped.
- Purse and stock are never touched. Changed entries get revision + 1 and go out in one acknowledged save before memory changes. A failed save revokes the service and the part waits for the next start.
- NPC startup asks for 'merchants' right after the purses are read, before trading is installed. 'merchants' joins PARTS. __thornswoodReleaseWaiting() moves to after the NPC startup.

## The two doc and note changes

- docs\WEBSITE-OPERATIONS.md: the guild traders' ledger moves out of "What the game does not let go of yet" into its own paragraph. The dry run counts it as release. The server lets go of the waits and clears a waiting trade, the trader keeping what it held. The purses and shelves name nobody and stay, like a hold's ledger. The crop paragraph stays under "does not let go of yet".
- scripts\ops\Wipe-Saves.ps1, help note only: a deleted character's supply waits and waiting trade are let go by the purse service from the list (#2351, #2652). A wipe writes no list, so a trade waiting on a wiped character stays waiting. The script's behaviour is unchanged.

## Merge order (from Codex)

1. #2651 (Claude's) first.
2. Then #2663 (this one). Once #2651 is in, #2663's diff shrinks to its own commit. Bring main in by a normal merge, never a rebase or force-push, and let CI go green again.
3. Then #2670 (anvil/2668-reset-wipe-release, stacked on #2663's tip 508e1ef5).
4. Then #2674 (waystone/2673-new-character-release, stacked on #2670).

All four touch game\ or launcher\ or ride on a PR that does, so all wait for the 1.2.4 freeze to lift.

## Live step

None of its own. A deletion already restarts the game server through Delete-Person, and the release runs at that start. The gamemode change reaches the servers with the next Deploy after 1.2.4 (Deploy-DevGamemode for dev, then main as usual). No Ship step and no engine change.

## Risks

- The ledger is the guild traders' coin and goods. requireMerchantEvidence refuses to start without it. release never changes a purse or stock, so no coin or goods are made or lost. The harness checks this coin for coin.
- Credit phase: the trade is cleared and the trader keeps next. What was due to the deleted character goes with their pack, which is deleted anyway. A wrong list would take goods somebody is owed, so only the list from Delete-Person (and later #2670, #2674) is ever trusted. Nothing guesses that a character is gone from resolve answering 0.
- A failed save revokes the purse service, the way a failed commit does. Trading stops on that server until the next start, and the part stays waiting in the list. This should be rare; check the start's log line for merchants on the first deletion after the Deploy.
- Startup order: the release runs before trading is installed and before any tick, so no trade can start against an entry being cleared.
- A second start with the same list writes nothing (done marks), which the harness checks.
- Logs are counts only, no names, profiles or form ids.

## Resets and wipes (covered by #2670 and #2674)

A character thrown away by Reset-Character.ps1 or New-Character.ps1, or everything by Wipe-Saves.ps1, writes no list in #2663, so a trade waiting on one still never closes here. Smeagle has ruled that no Patrick decision is needed: releasing merchant waits and trades for a character a reset or wipe has already thrown away is a bug fix, not a policy call (https://github.com/EvilPatrick06/Thornswood/issues/2668#issuecomment-6244623181). This replaces the "needs Patrick's call" wording in the #2652 root-cause comment. #2670 (#2668, Reset-Character and Wipe-Saves) and #2674 (#2673, New-Character) cover it with a characters-only list, as held drafts, and stay in Codex's order after #2663.

## #2670 has no Delete-Person.ps1 edits of its own

Checked 18 Oct 2026, about 5:45 AM MDT: #2670 (anvil/2668-reset-wipe-release, tip db7846bc) has #2663's tip 508e1ef5 as an ancestor. Its two own commits (43adf1b5, db7846bc) do not touch scripts\vps\Delete-Person.ps1. Any Delete-Person.ps1 change it shows comes from #2663 and #2651, so this note's sign-off covers it, and #2670 needs no separate Claude sign-off on that file. Its own change is scripts\ops\Release-List.ps1 (new), Reset-Character.ps1, Wipe-Saves.ps1, scripts\README.md, docs\GAMEMODE.md, tests and the workflows. To check:

`git diff 508e1ef5 db7846bc -- scripts/vps/Delete-Person.ps1` (empty)

## Tests (on One, 508e1ef5)

- tests\test-2652-merchant-release.js 32/0, new, in build.yml and build-pr.yml.
- test-2351-release-registers 73/0, test-2351-delete-person 79/0 (now expects release), test-2351-wipe-registers 32/0, test-2513 9/0.
- The merchant suites, test-one-mint 95/0, test-2166-retention-fixes 15/0, Build-MerchantGamemode --check and Build-Gamemode --check all pass.

## Steps for Claude

1. Read the Delete-Person.ps1 diff against #2651 (`git diff origin/claude/2351-release-registers...508e1ef5 -- scripts/vps/Delete-Person.ps1`).
2. Write on #2663: signed off, or what to change. Anvil makes any change by a new commit on the branch.
3. Merge #2651 when its own checks are done. After the freeze lifts, #2663 merges next, then #2670 and #2674.
4. After the next Deploy after 1.2.4, the first real Delete-Person run against a server whose ledger names the person should show merchants among the released parts at that server's start.

## Draft release-notes line

Deleting your account now also clears you from the guild traders' books: any supply wait or unfinished trade tied to your character is let go when the server next starts.
