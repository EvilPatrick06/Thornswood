# 2454 Fitted Bosmer armour built by Build-Generated, its .tri morphs stop shipping

- **Lane:** Anvil (Installer)
- **Issue / PR:** #2454, draft PR #2570 (branch anvil/2454-fitted-outfits, tip a8e973c9). Not merged: held for the 1.2.4 freeze (touches records\generated.json), and part two (travel clothes, executioner) still has to go in this same PR.
- **Box:** One, dev release folder C:\Thornswood-Repo\local\release-devbuild (Anvil may not touch that repo, so this is yours).
- **Needs first:** PR #2570 merged after the freeze, with part two in it. Part two waits on 2454-ccaa-3ba-mce-bodyslide.md (Wyrd's queue note).

Patrick, 15 Oct: build the Bosmer armour from the collection's Immersive Armours SSE CBBE.osp and drop the 18 .tri morphs (keeps #1004). Travel clothes and the executioner follow once the CCAA 3BA and MCE BodySlide projects are deployed.

## Order and risk
1. Run 2454-ccaa-3ba-mce-bodyslide.md (Vortex deploy of the two BodySlide projects). Tell Anvil on #2454 so part two can be coded and pushed to PR #2570.
2. After PR #2570 is merged (freeze lifted), refresh the dev release folder per #2019. It still holds the 3 Oct CBBE 3BA install, so building before the refresh would fit outfits to the wrong body.
3. Run Build-Generated in that folder (below). It refuses on its own if a set breaks the body rules, writes a body, builds a .tri file, or builds a missing or stray outfit file. Nothing is recorded then.
4. Next dev Ship. Ship-Rules refuses unless generated.txt lists every body and fitted outfit .nif with a matching sha.

Risk: if step 4 runs without step 3, Ship refuses (generated files are stale), which is safe. Once part two deletes built-until-1259.txt, the old travel clothes and executioner meshes stop shipping, so step 3 has to come before the first Ship after that merge.

## Run
From a worktree at the merge commit or later:

    .\scripts\release\Setup-ShipMachine.ps1 -Channel dev -Root C:\Thornswood-Repo\local\release-devbuild
    .\scripts\mods\Build-Generated.ps1 -Root C:\Thornswood-Repo\local\release-devbuild -DryRun
    .\scripts\mods\Build-Generated.ps1 -Root C:\Thornswood-Repo\local\release-devbuild
    .\scripts\release\Check-ShipReady.ps1 -Channel dev -Root C:\Thornswood-Repo\local\release-devbuild
    .\scripts\release\Ship.ps1 -Channel dev "<release note below>"

Check that the dry run lists one BodySlide group for each of the 9 IA CBBE - Bosmer sets after the 3 bodies, plus the CCAA and MCE sets once part two is in.

## Check afterwards
- Profile\OwnGame\generated.txt lists the 18 files under Data\meshes\armor\bosmerarmormaty743 (torsof, torsofengraved, torsometalf, bracersf, bracersengravedf, metalglovesf, cape\fullcapef, cape\shouldercapef, cape\shoulderengravedcapef, each _0 and _1).
- No .tri under bosmerarmormaty743 is in the release record.
- In game on dev: the Bosmer armour (all variants, capes, bracers, gauntlets) fits the body with no gaps or clipping, women's and men's. The travel clothes and executioner checks go in the closing Test task comment once part two lands.

## Draft release notes
Bosmer armour from Immersive Armours is now built by Thornswood to fit the server's body, so it lines up properly instead of using meshes made somewhere else.

## Draft news post
Elven gear that fits. The Bosmer armour from Immersive Armours is now built for Thornswood's own body, so the armour, capes and bracers sit where they should. More outfits follow soon.
