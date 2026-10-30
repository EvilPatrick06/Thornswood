# Collection revision 6: Thornswood Content 1.3, Atlas out, and the cheddars_mashups.esl rule

Revision 6 carries three changes in one run, so everybody updates once:

- Thornswood Content 1.3 (Nexus file 828696), through -DropPatch (#2793);
- Atlas Map Markers SE taken out with -Remove 24104, because its page does
  not allow it in a collection (#3649);
- cheddars_mashups.esl loading after RaceCompatibility.esm (#4070), from
  [COLLECTION-REVISION-6-RULE.json](COLLECTION-REVISION-6-RULE.json).

## Why the rule changes

Revision 5's -Add gave cheddars_mashups.esl the rule "load after Immersive
Weapons.esp, Hothtrooper44_ArmorCompilation.esp and ZIA_Complete Pack.esp".
The game loads an .esl as a master, before every plugin that is not one, so
the rule can never hold. On every install LOOT showed a "Cyclic interaction"
box for each of the three and offered to remove the rule. Measured on
27 October over the headers of all 98 enabled plugins: revision 5 has exactly
those three loops, and with the new rule it has none. RaceCompatibility.esm is
the last master, so the .esl goes on the end of the masters
(LIGHT-ORDER-DRIFT.md: a new plugin goes on the end of its own kind).

The server order does not change. ServerOrder.ps1 puts every plugin the game
loads as a master first, in the order it has, so cheddars_mashups.esl gets the
same light index wherever the list puts it.

## The run, from main on One

The first draft of revision 6 (823950, 30 October) had the first two changes
and not the rule, and a draft cannot be changed once it is made. So:

1. `pwsh scripts/release/New-NexusRevision.ps1 -Discard 6 -WhatIf`, then the
   same without -WhatIf, which throws draft 823950 away.
2. One New-NexusRevision run with the -Mod 192001 -FileId 828696 -Archive
   and -DropPatch arguments used for draft 823950, plus `-Remove 24104` and
   `-Rule docs/COLLECTION-REVISION-6-RULE.json`, first with -WhatIf.
3. `pwsh scripts/release/Install-NexusRevision.ps1 -Revision 6 -Record <folder>`.
   It stops on any rule that goes round with the game's own order, as draft
   823950's would.
4. `-Publish 6` only once #4158 has merged and its rebuild on One is in.
