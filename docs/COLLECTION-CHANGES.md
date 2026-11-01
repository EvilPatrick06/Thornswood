# Changing the collection

The collection on Nexus (7essxf) is written down in one record,
`records/collection.json`. A mod change is a pull request to that record.
Its check says yes or no with no key and nothing on Nexus touched, and
merging it drafts the revision on Nexus, holds the draft to the record and
publishes it (#5189). Nobody works out a `New-NexusRevision.ps1` line by hand
any more.

## What the record holds

- `mods`: one line per Nexus file the collection installs, in modId then
  fileId order: `modId`, `fileId`, `name` (for people only), and `plugins`,
  the plugins that file puts in Data, spelled as the plugin list spells them.
  `dropPatch` is only for a file that moves and leaves patches of its old
  file behind (`New-NexusRevision.ps1 -DropPatch`).
- `plugins`: every plugin of the collection in its load order: `name`,
  `master` and `light` (what the game reads it as), `masters` (what its
  header names), `after` (the collection's load-after rule for it), and
  `"enabled": false` only for a plugin the collection's own list leaves out,
  so it is installed but switched off. Revision 6 has two, `CBBE.esp` and
  `RaceMenuMorphsCBBE.esp`. The servers load both, and the launcher's plugin
  list switches them on, so a rule may name them.
- `dropped`: the plugins the servers load that this change takes out, each
  with `name`, `mod` and `why` (why every form it added can go from a world
  that keeps running). Empty when nothing goes.
- `wipe`: only when a change moves a full plugin the servers load to another
  place. It says whose decision it is that both worlds are wiped for it. Only
  Patrick makes that decision.
- `revision`: the newest published revision the record has followed. A
  change leaves it alone.

## Adding a mod

1. Read the mod's own Nexus page, Permissions and credits, in a browser,
   and add its reading to `records/collection-permissions.json` the way the
   entries there are written. The check refuses a mod with no reading, or one
   whose page does not allow it in a collection.
2. Add its line under `mods`, in modId order. The file id is the number in
   the file's download link on the mod's Files tab.
3. For each plugin it brings, print the plugin's line from the file itself
   (Vortex's staging folder has it once the mod is downloaded):

   ```
   pwsh scripts/release/New-CollectionRecord.ps1 -Plugin <path to the plugin>
   ```

   Paste the line under `plugins` where the plugin loads. A new plugin goes
   at the end of its own kind, so nothing the servers already load moves.
4. Fill in its `after`: at least the plugin right above it, so no two full
   plugins sit next to each other with nothing keeping them in that order.
5. Check it, and see what the merge will ask of Nexus:

   ```
   pwsh scripts/release/Check-CollectionRecord.ps1 -Base origin/main
   ```

## Taking a mod out

Take out its line under `mods`, its plugins under `plugins`, and every
`after` that names them. When the servers load one of its plugins, add it
under `dropped` with why it can go. A whole mod goes or stays: taking out
some of a file's plugins is refused, because Nexus installs the whole file.

## Moving a mod to a new file

Change its `fileId`, and its plugins if the new file brings others. Name
under `dropPatch` any patch of the old file that has to go with it.

## Changing the order or a rule

Change the plugin's `after`, or move its line. The check refuses an order a
rule breaks, a rule that goes round with the order the game sets, and a full
plugin the servers load that moves to another place, unless `wipe` says
whose decision that is.

## What the check holds

`Check-CollectionRecord.ps1`, run by `tests/test-5189-collection-record.ps1`
in the gate, reads only the repository:

- the record's own shape: every plugin put in Data by exactly one file, and
  each plugin's facts as its name allows;
- the load order: every rule names a plugin the list enables, the list keeps
  every rule, no rule loops with the game's order, and a chain of rules holds
  every full plugin under the one above it;
- each mod's page reading (`collection-permissions.json`);
- the servers: a plugin they load that the record takes out is under
  `dropped`, and no full plugin they load moves without `wipe`;
- the record and `records/collection-plugins.json` name the same revision.

It also says, without failing, which plugins the change adds and takes out,
and which of them the Last plugin's recipe reads.

## What the merge does

`.github/workflows/collection-record.yml` runs
`scripts/release/Publish-CollectionRecord.ps1` on main with the Nexus key:

1. the record passes its check and names the revision Nexus has published;
2. the published revision and the record give the change; no change, and
   it stops with nothing written;
3. `New-NexusRevision.ps1` drafts the next revision with all of it;
4. `Install-NexusRevision.ps1` lays the draft out;
5. the record that layout makes, read from each plugin's own header, is held
   to the merged record. Where they part the draft is discarded and the run
   stops, naming each difference;
6. only then is the draft published, and the rebuild on the new revision is
   put on the board.

To see what a merge would do without writing anything to Nexus, run the
workflow by hand with "whatif" left on.

## After the publish

The records follow the new revision in a pull request of their own:
`collection-plugins.json`, `collection-dropped.json` (from the record's
`dropped`), `collection-permissions.json`, the Last plugin's recipe, and the
record's `revision`. The run's `collection-record` artifact holds what they
are made from. The Last plugin is built again on the box, which has the
base game files. Then a dev release names the new revision.

On a tester's machine, the launcher's collection card opens Vortex straight
at that revision through Nexus's own link, when Vortex is what answers
Nexus links there, and the revision's page otherwise. When Vortex is done
the card comes down by itself and Scan and Fix run (#5200).

## Not done by the record yet

- A mod with an installer (FOMOD): `New-NexusRevision.ps1` refuses them, so
  one is still added by hand.
- Switching a plugin's light flag, or switching a plugin off: the draft is
  not made from these, so the merge discards a draft that would need them.
- The records that follow a publish and the box rebuild of the Last plugin
  are not started by the publish yet. The rebuild issue it files says what
  to run.
