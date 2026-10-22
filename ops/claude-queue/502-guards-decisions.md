# #502 No bounty for anything, Jarls and guards, the jail rules (read, dev gamemode, read, dev Ship, docs)

**Ready: all four pull requests are merged. #2508 merged as 5d57aff6 on 15 Oct 2026.** Run from a checkout at or after 5d57aff6, and take the step 1 read before the deploy: the first start of this gamemode ends the jail claims the read measures.

It can share the gamemode deploy with `502-guards-cells-board.md` if that has not run yet: a checkout with #2508 carries both.

- **Lane:** Claude (overnight run, guards-decisions and guards-decisions-2)
- **Issue / PR:** #502.
  - #2472, no bounty for anything (merged as 1ec70948).
  - #2476, the Jarl of a hold names its guards (merged as 38322137).
  - #2497, the jail rules (merged as 5156bb76).
  - #2508, one Jarl a hold, Give up the office, and jail claims made before the rule end once (merged as 5d57aff6).
- **Channel:** dev. The docs deploy is the live site; see Risks.
- **Staff status updates:** #staff-updates (1549254991082946570)
- **Needs first:** the dev server on the server build main records (`records\server-build.json`). `Deploy-DevGamemode.ps1` refuses any other build and says so before sending anything.

## Run, in this order
From the shared clone, current with origin/main at or after 5d57aff6.

1. **Before: the jail claims as they stand (read only).** Patrick, 12 Oct evening: jail claims made before the jail rule end once if this finds any. The first start of the new gamemode ends them, so this read is the before. It covers the ten jail buildings by id, dev then main:

       ssh Administrator@192.135.112.23 powershell -NoProfile -Command "Select-String -Path C:\Thornswood-Server-Dev\private\property.json,C:\Thornswood-Server\private\property.json -Pattern '(16203|1677a|19ad8|4a376|56e88|5d010|961ff|a8b23|eb440|ef324):(Skyrim|Dragonborn)\.esm' | ForEach-Object { $_.Path + ': ' + $_.Line.Trim() }"

2. **The deploy and the Ship:**

       git fetch origin
       git checkout --detach origin/main
       .\scripts\deploy\Deploy-DevGamemode.ps1
       .\scripts\release\Ship.ps1 -Channel dev "No bounty for anything, and each hold has one Jarl
       - Nothing you do puts a bounty on you any more: not a killing, a blow, a theft, a pickpocket or a trespass.
       - Taking the Jarl office asks which hold it is of, and a hold has one Jarl. The Jarl names that hold's guards on the Office page of K, and can give the office up there.
       - A guard keeps the cells of their own hold's jail. Only that hold's Jarl may claim the jail.
       - The game's old jail keys stay where they lie, and /stuck does not move anybody out of a jail while a guard has a cell there locked."
       .\scripts\deploy\Deploy-Docs.ps1

3. **After: the same read on dev, and the dev server log.**
   - Run the read in step 1 again. Dev's property.json should now hold no claim on a jail building: no Jarl is seated yet, so every earlier jail claim ended. Main is unchanged until main's run.
   - In the dev server log after the restart, look for one line per claim that ended: `law: the jail rule ends <name>'s claim (profile N) on <jail>, made before only the seated Jarl of <hold> could hold it`.
   - Then one line, `law: the jail rule was applied to the claims made before it once: N claim(s) ended`. N should equal the dev lines step 1 printed.
   - Write before, after and N on #502.

4. **Jail keys already in a pack (read only).** Any character holding one of the 11 jail keys (form ids in decimal, Dragonborn's at load index 04):

       ssh Administrator@192.135.112.23 powershell -NoProfile -Command "Select-String -Path C:\Thornswood-Server-Dev\world\changeForms\*.json,C:\Thornswood-Server\world\changeForms\*.json -Pattern 'baseId.{0,3}(645697|1030412|1052582|109405|923560|1067020|398008|516121|372420|1030413|67325847)[^0-9]' -List | ForEach-Object Path"

   A file it names is a character whose game opens a guard's cell with the key. It goes on #502 with the file.

The Ship carries the front plugin (#2472), the K panel's Office page (#2476, #2508) and the help panel (#2497). It can share a Ship with other page or front plugin notes; merge the lines.

## Check afterwards
- **Front log after joining dev:** `no bounty for any crime: 83 of 83 crime factions now ignore murder, assault, theft, trespass, pickpocketing and werewolves`. A `REFUSED` or `not in this load order` names the faction; read that first.
- **Dev server log at boot:** `law: read N guard(s), M cell door(s) a guard has turned, and J seated Jarl(s)`, then the jail rule's line from step 3, then the property block's ready line, with no error.
- **The Office page on dev, from an account with the Jarl role:**
  - K, Office shows the ten holds. One pressed twice takes the office of that hold, and the Guards of <hold> card appears.
  - The log has `law: seated jarl office on actor ... the seat of <hold>`.
  - A second Jarl-role account sees that hold held by the first Jarl, by name, and has no button for it.
  - Give up the office, pressed twice, frees it.
  - Name guard beside somebody logs `law: the Jarl of <hold> (profile ...) named ... a guard of <hold>`.
- **/stuck:** in Dragonsreach Dungeon, with a cell locked by a guard, it answers that it does not move anybody out of the jail.
- **The site:** the home page law card reads "Nothing in the game puts a price on your head".

## Risks and how to put it back
- **The restart.** The gamemode restart drops anybody on dev; the script warns them. `.\scripts\deploy\Deploy-DevGamemode.ps1 -PutBack` puts the gamemode back.
- **The ended jail claims stay ended.** PutBack does not bring back a claim the step ended, and nothing should. The step writes `steps.jailRule` into property.json and never runs again there. The read in step 1 is the record of what was there.
- **Jarls start unseated.** Nobody is a seated Jarl after the deploy, including a character that held the office before. A Jarl-role character takes their hold again on the Office page, and the first to press a hold holds it.
- **The docs deploy is the live site.** `Deploy-Docs.ps1` sends the home page law card, the tester list's TEST 10 and a roadmap line. All three only stop promising or testing a bounty. If they should wait for main, leave that line for the main run.
- **To put the Ship back,** ship the previous release; that restores the front plugin and the pages.
- **On main, later:** the same step runs once at main's first start with this gamemode. Take main's line from step 1 again just before that run.

## Release notes (draft)
No bounty for anything, and each hold has one Jarl
- Nothing you do puts a bounty on you any more: not a killing, a blow, a theft, a pickpocket or a trespass.
- Taking the Jarl office asks which hold it is of, and a hold has one Jarl. The Jarl names that hold's guards on the Office page of K, and can give the office up there.
- A guard keeps the cells of their own hold's jail. Only that hold's Jarl may claim the jail.
- The game's old jail keys stay where they lie, and /stuck does not move anybody out of a jail while a guard has a cell there locked.

## News post (draft)
none beyond the release note

## Test task (draft, for closing #502 once all of it is on main; replaces the drafts in 502-kill-bounty.md and 502-guards-cells-board.md)
Test task: Jarl, guards and the jail
Server: Main
1. Two testers have the Jarl role. The first opens K, Office, presses Whiterun twice, and names a third tester a guard there.
2. The second Jarl opens K, Office and looks for Whiterun.
3. The guard walks a fourth tester into a cell in Dragonsreach Dungeon, closes it and presses the lock key on it.
4. The fourth tester tries the cell door, then types /stuck.
5. The fourth tester steals something a trader owns in plain sight, strikes a trader, then opens the Journal, General Stats.
6. The guard takes down one of the fourth tester's notices on the Whiterun board, then tries the same at the Riften board.
7. The fourth tester tries to claim Dragonsreach Dungeon at its door. The first Jarl tries it too.
8. The first Jarl presses Give up the office twice. The second Jarl presses Whiterun twice.
What should happen: The second Jarl sees Whiterun held by the first and cannot take it until step 8, then can. The cell stays shut for the fourth tester, and /stuck says it does not move anybody out of the jail. Every bounty in the Journal stays at 0. The guard takes the notice down in Whiterun and has no Take down in Riften. Only the first Jarl is offered the claim on the jail.
