# 2454 Common Clothes and Armors 3BA BodySlide + MCE CBBE BodySlide into the collection

- **Lane:** Wyrd (Vortex/collection), for Anvil's #2454 (Anvil holds the claim)
- **Issue / PR:** #2454 (Anvil's outfit-build PR stays unmerged until this lands), no Wyrd PR
- **Channel:** Vortex (collection revision). No dev load-order change: no plugin.
- **Staff status updates:** #staff-updates (1549254991082946570)
- **Needs first:** Patrick's 15 Oct scope (on #2454). **Do it in the SAME Vortex revision as #2264** (`2264-improved-eyes.md`): one publish, one record refresh.

## Run
1. In Vortex, add both to the collection:
   - Common Clothes and Armors -3BA- Bodyslide (Nexus SE 83980, file "Common Clothes and Armors 3BA Bodyslide 1.0", 95.2 MB). Its requirements are already in: CommonClothes.esp, 3BBB.esp (CBBE 3BA), BodySlide.
   - More Craftable Equipment - CBBE Bodyslide (Nexus SE 44666, optional file, v1.2.0, 15.5 MB). NOT "Vanilla Bodyslide". The MCE main file is already in (MoreCraftableEquipment.esp).
2. Both should be BodySlide projects only (CalienteTools\BodySlide\SliderSets / ShapeData, plus reference meshes). **If either archive carries a plugin, do not enable it.** Neither should add anything to the load order.
3. Let both overwrite nothing of ours. If Vortex reports a file conflict with Common Clothes and Armors' own meshes, let the 3BA BodySlide win. Built output replaces those meshes anyway.
4. Publish (with #2264's changes). Run .\scripts\mods\New-CollectionPluginRecord.ps1 once for the revision. Expect only #2264's plugin to change in records\collection-plugins.json, nothing from these two.
5. Post on #2454 that the projects are deployed, so Anvil can refresh local\release-devbuild (#2019 caveat) and build.

## Check afterwards
- C:\Thornswood\Game\Data\CalienteTools\BodySlide\SliderSets has the CCAA 3BA .osp and the MCE CBBE .osp.
- The load order and records\collection-plugins.json are unchanged by these two.
- Anvil's Build-Generated builds the travel clothes (120 files) and the executioner (2) from them.

## Risks and how to put it back
- Load position: none. No plugins means no renumbering. They can't collide with #2264's late full plugin.
- MCE's CBBE project targets plain CBBE, not 3BA. It builds against our 3BA body (same slider names) without 3BA physics weights. The executioner fit is part of Anvil's in-game check.
- To revert, drop both from the collection. The 122 meshes then stop being buildable (Anvil's PR is not merged until they build).

## Permissions (never repack)
- Collection links the Nexus downloads only. Never put these projects or their source meshes in our packs.
- Our BUILT output does ship (Anvil's PR). Common Clothes and Armors allows asset use with credit (Nexus 21305; meshes by Franklin Zunge). The 3BA BodySlide says "follow the permissions of the original mod" and credits 3BA Vanilla Clothes and Armor (51610). MCE's permissions for built meshes were not read: Anvil records that in records\asset-provenance.json before the first release that ships them.

## Release notes (draft)
none from this step (Anvil's build PR carries the notes)

## News post (draft)
none

## Test task (draft)
none from this step (Anvil's #2454 has the in-game fit check)