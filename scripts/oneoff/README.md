# scripts/oneoff

Scripts that did one job once, kept rather than deleted. Nothing in the
repository calls any of them, and none of them is part of a release, a deploy
or a test. They were parked here on 25 September from `tools\` (and one from
the repository root), after the audit of that day found nothing still using
them.

They were written to sit in `tools\` and some of them reach the scripts beside
them from there, so a script moved back to run again goes back into `tools\`
first. Most of them were written for the old layout (`C:\SkyrimTogether`, the
build before the own game folder) and would do the wrong thing on a machine
set up today. Read the header before running anything.

| Script | What it did | Why it is here |
| --- | --- | --- |
| `Move-Install.ps1` | Moved the build from `C:\SkyrimTogether` to `C:\Thornswood`. | Its header says run it once; that was done. |
| `Add-SkyrimUnbound.ps1`, `Run-Unbound.cmd` | Installed Skyrim Unbound Reborn into the old build and published. | The collection installs Unbound now. |
| `Run-Everything.ps1`, `Run Everything.cmd` | Ran the old Add-* installers in one go and published once. | The collection installs the mods now. |
| `RunAll.cmd` | Built and packaged, logging to `C:\Thornswood\_dist`. | `Ship.ps1` builds, and the output is `out\` now. |
| `Clean-Downloads.ps1` | Moved clutter out of one Downloads folder. | A personal clean up. |
| `Fix-Voice.ps1` | Got the voice service running on the VPS on 13 September. | `Install-Voice.ps1` does that job. |
| `Check-RosterScript.ps1` | Parsed the roster script before it was sent. | Named a path on one machine; `Check-Roster.ps1` is the live one. |
| `Add-TempleRespawn.ps1` | Installed Respawn - Death Overhaul. | That mod is out (the known issues page). |
| `Add-JContainers.ps1` | Installed JContainers for SunHelm's meters. | SunHelm is out. |
| `Remove-BodyMods.ps1`, `Remove-FomodLeftovers.ps1` | Cleaned up after the 13 September body mod install. | Done. |
| `Fix-PluginProblems.ps1` | Removed CFTO-JK-Patch.esp and RaceMenuPlugin.esp. | **Do not run it.** The JK's patch went into the collection on 15 September, so this would now take out a plugin that belongs. |
| `Install-Emotes.ps1` | Copied the emote wheel from `tools\emotes` into a game folder. | The wheel is `game\plugins` and `game\ui` now, and `Go.ps1` installs it; the copies it read were 13 September's and are deleted. |
| `Revert.ps1` | Put one day's game folder back after MCMHelper.esp shifted the load order. | Done, and it read the same deleted copies. |
| `Reset-History.ps1` | Replaces the repository's history with one commit of main's files, keeps the hotfix branch live was built from, deletes the other branches, and saves the old history to a bundle first (issue #567). | Made on 25 September to be run once, by Patrick; `-DryRun` first. `tests\test-reset-history.ps1` runs it against a scratch repository. |
| `GourmetFishingVanilla.pas` | The xEdit script that repointed Gourmet's fishing ingredients at vanilla ones (docs\GOURMET-FISHING-PATCH.md). | Applied once; the patched plugin is what ships. |
