# The PowerShell scripts

Every `.ps1` under this folder, 174 of them, by area: `release` builds and
ships, `deploy` puts things on the VPS, `vps` looks after the box, `ops` runs
the world day to day, `mods` works on the collection and the plugins, `dev`
is for whoever is changing this repository. `oneoff` holds finished one time
scripts and has its own README. Each row is the one line that says
what each one is for. New-ScriptIndex.ps1 writes this file from the scripts
themselves: the line is a script's .SYNOPSIS where it has one, and otherwise
the first sentence of the comment at its top. Do not edit it by hand. Change
the script, then run

    .\scripts\dev\New-ScriptIndex.ps1

and commit this file with it. tests\test-script-index.ps1, which the nightly
checks run, fails when this file is not what that would write.

A script's options are not listed here. Get-Help reads them off its param
block, so they are always all of them:

    Get-Help .\scripts\release\Ship.ps1 -Full

The node and Python scripts beside these (`Build-*.js`, `Audit-*.py` and the
rest) and the `test-*.js` harnesses are not in this list.

| Script | What it is for |
| --- | --- |
| [deploy/Add-VoiceFeed.ps1](deploy/Add-VoiceFeed.ps1) | Adds the position feed to gamemode.js and redeploys it. |
| [deploy/Artifact.ps1](deploy/Artifact.ps1) | What a deploy sends, built from a commit rather than copied off a working tree, and what the box keeps to say which commit each part runs. |
| [deploy/Deploy-DevGamemode.ps1](deploy/Deploy-DevGamemode.ps1) | Sends game\gamemode.js to the dev server on the VPS and restarts only that server. |
| [deploy/Deploy-Docs.ps1](deploy/Deploy-Docs.ps1) | Puts the Thornswood docs site on the VPS and keeps it running. |
| [deploy/Deploy-Gamemode.ps1](deploy/Deploy-Gamemode.ps1) | Puts gamemode.js into the built server and writes a server load order that actually lines up with the client's. |
| [deploy/Deploy-Server.ps1](deploy/Deploy-Server.ps1) | Sends the built server up to the VPS and restarts it. |
| [deploy/DeployedBuild.ps1](deploy/DeployedBuild.ps1) | What each server actually runs, where the site can read it. |
| [deploy/Install-Backup.ps1](deploy/Install-Backup.ps1) | Puts the nightly backup on the VPS: sends vps-nightly-backup.ps1 up, makes a passphrase if there is not one yet, and registers the scheduled task that runs it. |
| [deploy/Install-Bot.ps1](deploy/Install-Bot.ps1) | Puts the Thornswood bot on the VPS and keeps it running. |
| [deploy/Install-Runner.ps1](deploy/Install-Runner.ps1) | Puts a GitHub Actions runner on the VPS, so the build check runs on every pull request without paying for minutes. |
| [deploy/Install-ThornswoodContent.ps1](deploy/Install-ThornswoodContent.ps1) | Drops Thornswood-Content.esp into the game folder and inserts it into the load order ahead of the city overhauls. |
| [deploy/Install-ThornswoodServer.ps1](deploy/Install-ThornswoodServer.ps1) | Run this ON THE VPS, after Bootstrap-VPS.ps1, as Administrator. |
| [deploy/Install-Voice.ps1](deploy/Install-Voice.ps1) | Puts the proximity voice service on the VPS beside the game server and opens the one port it needs. |
| [deploy/MaxOnline.ps1](deploy/MaxOnline.ps1) | How many people a Thornswood server holds at once: read from the one place it is written, records\most-online.json, and put into server-settings.json. |
| [deploy/Remirror-Site-Feed.ps1](deploy/Remirror-Site-Feed.ps1) | Puts the release feed on the site, so https://thornswood.net/feed/version.json is the same file as this machine's working copy of the feed and every asset it names can be downloaded from thornswood.net. |
| [deploy/Rotate-BotToken.ps1](deploy/Rotate-BotToken.ps1) | Puts a new Discord bot token into both places on the VPS that use it, in one go, and restarts both programs that read it. |
| [deploy/Rotate-ServerPassword.ps1](deploy/Rotate-ServerPassword.ps1) | Changes the server password and hands the new one to the site, so the launcher can fetch it after checking Discord. |
| [deploy/ServerBuild.ps1](deploy/ServerBuild.ps1) | Which server files come from the fork, and whether a folder, a zip or a stage holds the build records\server-build.json names. |
| [deploy/ServerOrder.ps1](deploy/ServerOrder.ps1) | The server's load order once the engine loads light plugins (#1715), and the full index a form id is computed from. |
| [deploy/ServerReadyWait.ps1](deploy/ServerReadyWait.ps1) | How long a started game server has to answer on its ports before a deploy puts the old files back. |
| [deploy/ServerSettings.ps1](deploy/ServerSettings.ps1) | Which settings a game server install takes from the release, and which it keeps from the server it replaces. |
| [deploy/Set-DiscordLogin.ps1](deploy/Set-DiscordLogin.ps1) | Points the site at your Discord, which is what decides who gets in anywhere. |
| [deploy/Set-DiscordOnboarding.ps1](deploy/Set-DiscordOnboarding.ps1) | Sets Discord's onboarding (Server Settings, Onboarding) with the bot, from bot\Build-Onboarding.py: the default channels, the questions and what each answer gives, every role and channel looked up by name on the server when it runs. |
| [deploy/Setup-Discord.ps1](deploy/Setup-Discord.ps1) | Builds the Thornswood Discord: roles, categories, channels, permissions and the words in the read only channels, in one run. |
| [deploy/Setup-Domain.ps1](deploy/Setup-Domain.ps1) | Puts thornswood.net in front of the docs site, with a real certificate. |
| [deploy/Swap.ps1](deploy/Swap.ps1) | Stages a deploy beside what is running, checks it there, and only then swaps it in, keeping what it replaced for a one-command put-back. |
| [dev/Allow-Claude.ps1](dev/Allow-Claude.ps1) | Adds the folders and the script paths a Claude working in this repo needs, to the Claude Code settings file, and reports exactly what it changed. |
| [dev/Build-HarvestTable.ps1](dev/Build-HarvestTable.ps1) | Builds game\data\harvests.json: the table the server needs to say who may pick which plant. |
| [dev/Build-HuntTable.ps1](dev/Build-HuntTable.ps1) | Builds game\data\hunts.json: the table the server needs to answer a carcass. |
| [dev/Build-OreTable.ps1](dev/Build-OreTable.ps1) | Builds game\data\ores.json: the table the server needs to answer an ore vein. |
| [dev/Build-RecipeTable.ps1](dev/Build-RecipeTable.ps1) | Builds game\data\recipes.json: the table the server needs to answer "may this person make this". |
| [dev/Build-SpellTable.ps1](dev/Build-SpellTable.ps1) | Builds game\data\spells.json: the table the server needs to hand somebody a spell. |
| [dev/Check-Backdrop.ps1](dev/Check-Backdrop.ps1) | Read only. Says what the main menu backdrop is in a game folder: the two logo meshes (their hashes, how many shapes each carries, and whether logo01ae.nif's one shape is hidden, which decides whether a second plate draws and whether the game crashes at the main menu) and the wallpaper texture (size, mip levels, format), against what the repo carries in game\menu. |
| [dev/Check-Balance.ps1](dev/Check-Balance.ps1) | Reads the five generated tables and says whether the ladders line up. |
| [dev/Check-Controls.ps1](dev/Check-Controls.ps1) | Every control in the launcher is found at runtime by name. |
| [dev/Check-Outside.ps1](dev/Check-Outside.ps1) | Walks the path a first install takes through the things this project does not run itself, and says which of them is broken or has moved. |
| [dev/Check-Secrets.ps1](dev/Check-Secrets.ps1) | Read only. Looks for anything that must never leave a machine: in the files this repository tracks, in a pack or installer zip, in the installer's staged folder, or in a built program. |
| [dev/Check-Swallow.ps1](dev/Check-Swallow.ps1) | Counts the silent catches in the launcher, file by file, and fails when any file has more than scripts\dev\swallow-baseline.txt allows, or fewer than it allows with its line not yet lowered. |
| [dev/Check-Words.ps1](dev/Check-Words.ps1) | The writing rules in Developer-Guide.md, checked on every file people read instead of hoped for; each hit names the file, the line and the rule. |
| [dev/Close-Launcher.ps1](dev/Close-Launcher.ps1) | Shared by every script that writes into the build. |
| [dev/Install-Thornswood.ps1](dev/Install-Thornswood.ps1) | Everything the client needs, in one run, in the order it has to happen in. |
| [dev/Measure-Reclaim.ps1](dev/Measure-Reclaim.ps1) | How much disk deleting a folder would ACTUALLY free. |
| [dev/New-ScriptIndex.ps1](dev/New-ScriptIndex.ps1) | Writes scripts\README.md, the list of every PowerShell script under scripts\ and the one line that says what each one is for. |
| [dev/Nightly-Issue.ps1](dev/Nightly-Issue.ps1) | Keeps one issue on the board for a failing nightly, and closes it the night the checks pass. |
| [dev/Nightly-Stray.ps1](dev/Nightly-Stray.ps1) | Names every pull request open more than two days and every branch other than main with no open pull request, reading every page GitHub has. |
| [dev/Start-Thornswood.ps1](dev/Start-Thornswood.ps1) | Launches the game the way the launcher's Play() does, without the launcher. |
| [dev/Watch-Foreground.ps1](dev/Watch-Foreground.ps1) | Which window Windows is giving the keyboard to, sampled from outside the game. |
| [mods/Add-Accuracy.ps1](mods/Add-Accuracy.ps1) | RETIRED. DO NOT RUN. Issue #1179: hand-installed Core Impact Framework and Accuracy, then Ships. |
| [mods/Add-Bodies.ps1](mods/Add-Bodies.ps1) | RETIRED. DO NOT RUN. Issue #405: every run poured the nude CBBE and 3BA female body (femalebody_0.nif and _1.nif, shapes 3BA, 3BA_Vagina and 3BA_Anus, no Bra or Panty) back over Game\Data, whatever body had been put there since. |
| [mods/Add-CartTravel.ps1](mods/Add-CartTravel.ps1) | RETIRED. DO NOT RUN. Issue #1179: hand-installed CFTO and its patch, rewrote plugin lists, then Ships. |
| [mods/Add-McmShortcut.ps1](mods/Add-McmShortcut.ps1) | RETIRED. DO NOT RUN. Issue #1179: hand-installed MCM Shortcut NG, then Ships. |
| [mods/Align-LoadOrder.ps1](mods/Align-LoadOrder.ps1) | The client counts its own plugins with Game.GetModCount, which skips every ESL-flagged one because Skyrim gives those no normal index. |
| [mods/Audit-Leftovers.ps1](mods/Audit-Leftovers.ps1) | Measures. Deletes nothing, moves nothing, renames nothing. |
| [mods/Audit-Mods.ps1](mods/Audit-Mods.ps1) | Measures the build and says which parts carry a plugin and which are pure assets, because only the second kind can ever be optional. |
| [mods/Build-Generated.ps1](mods/Build-Generated.ps1) | Builds Thornswood's animation and body files (the behavior files, with Pandora Behaviour Engine+, and BodySlide's body meshes) in Thornswood's own game folder, and records them as Thornswood's, so the next Ship carries them. Never writes into the Steam copy. |
| [mods/Check-CleanInstall.ps1](mods/Check-CleanInstall.ps1) | After installing the Nexus collection into a clean Vortex profile: does the plugin list that install wrote give the game the load order the server checks, with the server's files? |
| [mods/Check-CollectionRules.ps1](mods/Check-CollectionRules.ps1) | Whether the plugin rules the Nexus collection carries hold a clean install to a plugin list's order. |
| [mods/Check-CoveredBodies.ps1](mods/Check-CoveredBodies.ps1) | Says whether every body the game folder shows people is covered by underwear, men and women alike, and exits 2 when one is not. |
| [mods/Check-Editions.ps1](mods/Check-Editions.ps1) | Does anything in the load order need the paid Anniversary upgrade? |
| [mods/Check-Manifest.ps1](mods/Check-Manifest.ps1) | Says what load order the game server is actually handing out, and how it compares to the one you play with. |
| [mods/Check-Plugins.ps1](mods/Check-Plugins.ps1) | What is enabled that should not be, and what is missing that should be there. |
| [mods/Clean-Everything.ps1](mods/Clean-Everything.ps1) | Finds the old installers, build leftovers, temp files, stale backups and old GitHub release assets across this machine, the server and the source repository, adds up what they are costing, and prints it. |
| [mods/Clean-Leftovers.ps1](mods/Clean-Leftovers.ps1) | The other half of Audit-Leftovers.ps1. That one measures and never touches anything; this one removes what it found. |
| [mods/Enable-MCM.ps1](mods/Enable-MCM.ps1) | RETIRED. DO NOT RUN. Issue #1179: patched SkyUI_SE.esp's light flag by hand. |
| [mods/Find-MissingMasters.ps1](mods/Find-MissingMasters.ps1) | Reads the TES4 header of every plugin in Data and reports any master that is no longer present. |
| [mods/Fix-Icons.ps1](mods/Fix-Icons.ps1) | Windows keeps the picture it once drew for a shortcut in a cache, and goes on showing it long after the icon inside the exe changed. |
| [mods/Fix-MaleBody.ps1](mods/Fix-MaleBody.ps1) | RETIRED. DO NOT RUN. Issue #1179: moved the collection's HIMBO male body aside by hand. |
| [mods/Fix-QuickLoot.ps1](mods/Fix-QuickLoot.ps1) | RETIRED. DO NOT RUN. Issue #1179: switched on MCMHelper.esp in server-settings.json and plugins.txt by hand. |
| [mods/Generated.ps1](mods/Generated.ps1) | What Thornswood's generated files are, what they were built from, and whether the ones in a game folder are still current. Dot-sourced by Build-Generated.ps1, Ship.ps1 and Check-ShipReady.ps1. |
| [mods/LoadOrder.ps1](mods/LoadOrder.ps1) | The load order as the game counts it, and how to put a plugin list into the server's order. |
| [mods/Remove-DeadRecords.ps1](mods/Remove-DeadRecords.ps1) | Deletes records from Thornswood-Content.esp that nothing uses any more, and refuses to delete one that anything still points at. |
| [mods/Remove-Plugin.ps1](mods/Remove-Plugin.ps1) | RETIRED. DO NOT RUN. Issue #1179: took one plugin out of the build by hand. |
| [mods/Rename-ContentRecords.ps1](mods/Rename-ContentRecords.ps1) | Renames the editor ids in Thornswood-Content.esp that still carry the naming of the server the content came from, and changes nothing else about the file. |
| [mods/Set-UnboundMenu.ps1](mods/Set-UnboundMenu.ps1) | RETIRED. DO NOT RUN. Issue #1179: swapped Skyrim Unbound's MCM script by hand. |
| [mods/Show-EslCascade.ps1](mods/Show-EslCascade.ps1) | Answers one question: if the server load order drops every ESL-flagged plugin, how much else has to go with it? |
| [mods/Sync-LoadOrder.ps1](mods/Sync-LoadOrder.ps1) | Build the server's load order from the client's. |
| [ops/Chargen-Log.ps1](ops/Chargen-Log.ps1) | What the server thinks is happening to your character. |
| [ops/Check-Chargen.ps1](ops/Check-Chargen.ps1) | Preflight for character creation. Everything it looks at is something that silently produces a broken first join rather than an error message, so it is worth thirty seconds before starting the server. |
| [ops/Check-DevRosterSeed.ps1](ops/Check-DevRosterSeed.ps1) | Expand the roster seed here-string exactly as Publish-Server would and parse the text that would actually be sent. |
| [ops/Check-Roster.ps1](ops/Check-Roster.ps1) | What is in each server's private folder, by name and size only. |
| [ops/Discord-Hook.ps1](ops/Discord-Hook.ps1) | The Discord webhooks releases post through, kept in one place on the VPS instead of a file on each machine that ships. |
| [ops/Mark-Spot.ps1](ops/Mark-Spot.ps1) | Reads the spots you marked in game and prints them in the shape the content table wants. |
| [ops/New-Character.ps1](ops/New-Character.ps1) | Throws the test character away so the next connect builds a fresh one. |
| [ops/Publish-Discord.ps1](ops/Publish-Discord.ps1) | Posts the newest release into the Discord #news channel. |
| [ops/Publish-News.ps1](ops/Publish-News.ps1) | Copies the launcher's news feed onto the docs site, so the News page there is the same list of changes people see in the launcher rather than a second one written by hand that immediately falls behind. |
| [ops/Reset-Appearance.ps1](ops/Reset-Appearance.ps1) | Puts a character back into the race menu without deleting them. |
| [ops/Reset-Character.ps1](ops/Reset-Character.ps1) | Throws away the character on the server so the next launch runs creation from the top. |
| [ops/Set-Collection.ps1](ops/Set-Collection.ps1) | Asks for the collection address and publishes it, in the two places that decide it, the same two Set-Server.ps1 uses. |
| [ops/Set-DevNews.ps1](ops/Set-DevNews.ps1) | Points dev releases at the Discord channel for dev build updates, so they stop being something only the dev launcher ever mentions and stay out of #news, where everybody reads about the build they actually play. |
| [ops/Set-Door.ps1](ops/Set-Door.ps1) | Turns the game server's door on, off, or tells you what it has been seeing. |
| [ops/Set-Server.ps1](ops/Set-Server.ps1) | Sets the server everyone connects to, in the two places that decide it, and sends the feed to the VPS (#907). |
| [ops/Wipe-Saves.ps1](ops/Wipe-Saves.ps1) | Starts the world over. Everybody begins again, nothing is claimed, nothing has been looted, and every container in the province is holding what Bethesda put in it. |
| [release/Add-VirusTotalComment.ps1](release/Add-VirusTotalComment.ps1) | Optional manual tool: leaves one community comment on a build's VirusTotal report, or says plainly that it is not commenting and carries on. |
| [release/Assert-PublishSigned.ps1](release/Assert-PublishSigned.ps1) | Helpers for the publish sign gate. Dot-source this from Ship.ps1 and Publish-Installer.ps1. |
| [release/Build-Engine.ps1](release/Build-Engine.ps1) | Takes a machine from a fresh clone to a built engine: the SkyMP server and the client runtime, out of the fork in engine\skymp. |
| [release/Build-Launcher.ps1](release/Build-Launcher.ps1) | Compiles the launcher into a real Thornswood.exe. |
| [release/Build-Server.ps1](release/Build-Server.ps1) | Compiles the game server out of our fork and puts the result where Deploy-Server.ps1 and Publish-Server.ps1 expect to find it. |
| [release/BuildStamp.ps1](release/BuildStamp.ps1) | What a server's gamemode is, written down beside it. |
| [release/Bump-Version.ps1](release/Bump-Version.ps1) | Moves the launcher's version number, commits that one file, and stops. |
| [release/Check-Build.ps1](release/Check-Build.ps1) | The server does not check plugin names. It checks size and crc32 of every plugin it names, so the wrong version of a mod is the same to it as not having the mod. |
| [release/Check-ShipReady.ps1](release/Check-ShipReady.ps1) | Whether THIS machine can run a release, and what is missing if it cannot. |
| [release/Dev-News.ps1](release/Dev-News.ps1) | Which notes on the dev feed are marked DEV, worked out from main's feed, and the one place that writes those marks and the dev feed's mainVersion. |
| [release/EngineJobs.ps1](release/EngineJobs.ps1) | How many projects an engine build compiles at once, and whether a compile that failed ran the machine out of memory. |
| [release/Export-ServerPayload.ps1](release/Export-ServerPayload.ps1) | Packages everything the VPS needs into one zip. |
| [release/Feed-Rules.ps1](release/Feed-Rules.ps1) | Which packs on the update feed a launcher can actually download. |
| [release/Feed-Store.ps1](release/Feed-Store.ps1) | Where each channel's feed, its release baseline and their history are kept, and the only code that reads or writes them there (#907). |
| [release/Get-ScratchDir.ps1](release/Get-ScratchDir.ps1) | Says where a short-lived build scratch folder goes, so Ship and Install-Thornswood take their launcher build (and the CI setup stub) from one place instead of each calling [IO.Path]::GetTempPath(). |
| [release/Go.ps1](release/Go.ps1) | Installs the front, the overlays and the plugins, then reports what the server is doing. |
| [release/Install-Launcher.ps1](release/Install-Launcher.ps1) | Puts a launcher that Build-Launcher.ps1 has already built into an install, and does the things around it that only an install should do. |
| [release/New-ClientBuildRecord.ps1](release/New-ClientBuildRecord.ps1) | Records what the client runtime is and which fork commit it was built from, into records\client-build.json. |
| [release/New-ServerBuildRecord.ps1](release/New-ServerBuildRecord.ps1) | Records every server file the fork builds and the one commit they were built from, into records\server-build.json. |
| [release/New-SkyrimFilesRecord.ps1](release/New-SkyrimFilesRecord.ps1) | Records every file of the pinned Skyrim build, from the depot manifests the Downgrade asks Steam for, into records\skyrim-files.json. |
| [release/Note-Rules.ps1](release/Note-Rules.ps1) | What release notes may say. Ship.ps1 dot-sources this and refuses notes that break it, before anything is built. tests\test-note-rules.ps1 drives the same function, so the rule and its test cannot disagree. |
| [release/Package-ClientRecord.ps1](release/Package-ClientRecord.ps1) | The client runtime an installer is held to. |
| [release/Package-Thornswood.ps1](release/Package-Thornswood.ps1) | Turns the built install at C:\Thornswood into the single file your friends run. |
| [release/Publish-Installer.ps1](release/Publish-Installer.ps1) | Puts the current installer on the docs site so friends always have the newest one without anybody sending files around. |
| [release/Publish-Pack.ps1](release/Publish-Pack.ps1) | Builds the optional packs listed in optional-packs.txt, sends them to the site, and adds them to version.json so every launcher offers them under Add-ons on its Diagnostics page. |
| [release/Publish-PostShip.ps1](release/Publish-PostShip.ps1) | Runs what follows a published tip: the host feed remirror. VirusTotal is no longer part of publish; use Publish-VirusTotal.ps1 by hand if you want a report. |
| [release/Publish-Server.ps1](release/Publish-Server.ps1) | Run this ON YOUR LAPTOP. It packs the server, sends it to the VPS, installs it there and checks it came up. |
| [release/Publish-Update.ps1](release/Publish-Update.ps1) | Diffs the current build against the last published state, packs only what changed, sends it to the site (thornswood.net/feed[-dev]/assets/<sha256>, #897), and updates version.json so everyone's launcher picks it up. |
| [release/Publish-VirusTotal.ps1](release/Publish-VirusTotal.ps1) | Optional manual tool: sends a file to VirusTotal, or says plainly that it is not sending and carries on. Not called from publish. |
| [release/Read-JsonFile.ps1](release/Read-JsonFile.ps1) | ConvertFrom-ThornswoodJson: JSON text read from a file, parsed, or a stop that names the file. |
| [release/Refresh-DevNews.ps1](release/Refresh-DevNews.ps1) | Marks the dev feed's notes DEV again against what main has published, and sets its mainVersion, with no release. |
| [release/Release-Baseline.ps1](release/Release-Baseline.ps1) | What a release is diffed against, and the record each release publishes of what it left installed (#441). |
| [release/Release-Name.ps1](release/Release-Name.ps1) | One name for each release, recorded in the feed and the store, and a git tag on the commit it was built from (#444). |
| [release/Repair-Manifest.ps1](release/Repair-Manifest.ps1) | Takes packs with no download url back out of version.json and sends the fix. |
| [release/Rollback-Feed.ps1](release/Rollback-Feed.ps1) | Puts a channel's feed back to an earlier release, so every launcher on that channel moves its game files back to what that release installed, with no hand editing of version.json (#442). |
| [release/Scrub-Feed.ps1](release/Scrub-Feed.ps1) | Takes Bethesda's files and one machine's own files out of what a channel's feed has already published: every pack that carries one is rebuilt without it, every release record that names one is written again without it, the feed and the store's baseline are sent through Feed-Store.ps1 like any other feed edit, and the old bytes are then deleted from the site once no feed names them (#1152, #1227, #1229, #1239). |
| [release/Setup-ShipMachine.ps1](release/Setup-ShipMachine.ps1) | Checks and prepares a Windows machine to Ship dev, and says what is left for a person to do. |
| [release/Ship-Rules.ps1](release/Ship-Rules.ps1) | The one list of what never leaves a machine inside a Thornswood pack or installer. |
| [release/Ship-Stack.ps1](release/Ship-Stack.ps1) | One Dev or Main command that runs gamemode deploy, the installer package, and the host feed remirror. |
| [release/Ship.ps1](release/Ship.ps1) | Builds the launcher and publishes everything that changed, launcher and mods both, in a single release, to the main build or the dev build. |
| [release/Sign-Artifact.ps1](release/Sign-Artifact.ps1) | Signs a built binary, or says plainly that it is not signing and carries on. |
| [release/Source-Notice.ps1](release/Source-Notice.ps1) | The note and licence texts that go inside every download on the update feed that carries SkyMP files. |
| [release/Sync-Client.ps1](release/Sync-Client.ps1) | Puts the client runtime built from the fork into the game folder, and refuses any file that is not the recorded build. |
| [release/Where.ps1](release/Where.ps1) | Says where the engine fork and the build output are, so every script asks one place instead of carrying its own copy of a path. |
| [vps/Add-VpsKey.ps1](vps/Add-VpsKey.ps1) | Puts another person's public SSH key on the VPS, so they can run the scripts that talk to it from their own machine without ever holding the Administrator password. |
| [vps/Backup-Server.ps1](vps/Backup-Server.ps1) | Pulls everything off the server that could not be rebuilt from the repo, and puts it in a dated zip on this machine: in local\backups in the repository (Where.ps1 Backups), or the folder -Out names. |
| [vps/Bootstrap-VPS.ps1](vps/Bootstrap-VPS.ps1) | Run this ON THE VPS, once, in the PowerShell 5.1 that ships with Windows Server 2022. |
| [vps/Bot-Service.ps1](vps/Bot-Service.ps1) | Runs the Thornswood bot as a Windows service under its own account, and stops and starts it by name (issue #465). |
| [vps/Check-LiveGamemode.ps1](vps/Check-LiveGamemode.ps1) | Says whether the gamemode running on the VPS is the one in this repo. |
| [vps/Check-Load.ps1](vps/Check-Load.ps1) | Answers the only question worth asking before paying for a bigger server: what is this one actually running out of. |
| [vps/Check-Site.ps1](vps/Check-Site.ps1) | Asks whether thornswood.net is actually working: from the outside first, the way a visitor or an uptime monitor sees it, and then from the box, the way the site sees Discord. |
| [vps/Check-VoiceInstall.ps1](vps/Check-VoiceInstall.ps1) | Expand Install-Voice's here-string exactly as the script does and look at the text that would actually be sent. |
| [vps/Clear-OldWorldCopies.ps1](vps/Clear-OldWorldCopies.ps1) | Removes the copies of the world that every server install before #446 left in the VPS temp folder, keeping the newest of each kind (issue #1074). |
| [vps/Fetch-Backups.ps1](vps/Fetch-Backups.ps1) | Brings the nightly backups off the VPS onto this machine, and checks that what arrived is readable. |
| [vps/Get-Logs.ps1](vps/Get-Logs.ps1) | Brings the server's own logs down to this machine so they can be read whole. |
| [vps/Harden-VPS.ps1](vps/Harden-VPS.ps1) | Closes the VPS to everything but ssh with a key: proves key login works, then turns ssh password login off and turns Remote Desktop off. |
| [vps/Lock-Folder.ps1](vps/Lock-Folder.ps1) | The one place the creators of the VPS service folders get their lock from (follow-up to issues #1183 and #1691): Watch-Services.ps1 and Watch-Load.ps1 for C:\Thornswood-Watch, Setup-Domain.ps1 for C:\Thornswood-Caddy, and Artifact.ps1 and Swap.ps1 for C:\Thornswood-Deploys. |
| [vps/Lock-VpsFolders.ps1](vps/Lock-VpsFolders.ps1) | Takes the rule that lets every account on the box read them off the game servers', the voice services' and the backups' folders, now rather than at each one's next install (issues #1105 and #1173). |
| [vps/Prove-SecretOffCommandLines.ps1](vps/Prove-SecretOffCommandLines.ps1) | Proves, on one real run, that a secret-sending script keeps the value off every command line on the VPS (issue #1212, the person check of #451). |
| [vps/Read-Load.ps1](vps/Read-Load.ps1) | Says which service is using the box, from the record vps-load.ps1 keeps on it. |
| [vps/Remote.ps1](vps/Remote.ps1) | Runs a bit of PowerShell on the VPS, properly. |
| [vps/Request-Restart.ps1](vps/Request-Restart.ps1) | Tells the live server to warn everybody and then clear them out, without needing to be standing in the world to type /restart. |
| [vps/Restart-Server.ps1](vps/Restart-Server.ps1) | Restarts a Thornswood service on the VPS. Nothing is copied and nothing is built: this only stops it and starts it again. |
| [vps/Restore-Backup.ps1](vps/Restore-Backup.ps1) | Opens one of the nightly backups: checks it has not been tampered with, decrypts it, and unpacks it into a folder you name. |
| [vps/Restore-Box.ps1](vps/Restore-Box.ps1) | Puts a nightly backup back onto a new VPS, run from this machine. |
| [vps/Restore-Server.ps1](vps/Restore-Server.ps1) | Puts a nightly backup's world back into a game server folder and checks the result would start: the load order resolves and the characters are there. |
| [vps/Roll-Log.ps1](vps/Roll-Log.ps1) | Rolls a log just before the service that writes it starts. |
| [vps/Send-Script.ps1](vps/Send-Script.ps1) | The one way a script here runs PowerShell on the VPS. |
| [vps/Send-Secret.ps1](vps/Send-Secret.ps1) | How a secret goes to the VPS: on ssh's standard input, never on a command line. |
| [vps/Set-Vps.ps1](vps/Set-Vps.ps1) | Points everything at a different server box. |
| [vps/Setup-SshKey.ps1](vps/Setup-SshKey.ps1) | Type the VPS password one last time. |
| [vps/Show-BotLog.ps1](vps/Show-BotLog.ps1) | What the bot has been saying, without redeploying it to find out. |
| [vps/vps-dev-instance.ps1](vps/vps-dev-instance.ps1) | Runs ON the VPS. Makes the dev game server and the dev voice server beside the live ones, from copies of the live installs, on their own ports, with their own scheduled tasks, firewall rules and watchdog entries. |
| [vps/vps-freeze.ps1](vps/vps-freeze.ps1) | Runs ON the old VPS on the day the server moves: stops everything that writes what a backup takes, then takes the last backup. |
| [vps/vps-harden.ps1](vps/vps-harden.ps1) | Runs ON THE VPS, sent there by Harden-VPS.ps1: turns ssh password login off and turns Remote Desktop off, leaving ssh on port 22 alone. |
| [vps/vps-load.ps1](vps/vps-load.ps1) | Runs ON the VPS, every five minutes, as the scheduled task that Watch-Load.ps1 -Install puts there. |
| [vps/vps-nightly-backup.ps1](vps/vps-nightly-backup.ps1) | Runs on the VPS, once a night, as the scheduled task that Install-Backup.ps1 puts there. |
| [vps/vps-restore-services.ps1](vps/vps-restore-services.ps1) | Runs ON the VPS, sent there by Restore-Box.ps1: puts the site's, the bot's and Caddy's half of an unpacked nightly backup back into their folders. |
| [vps/Vps.ps1](vps/Vps.ps1) | The one place every script gets the VPS address, user, and ports from. |
| [vps/Watch-Load.ps1](vps/Watch-Load.ps1) | The website, the game server, the voice service and the bot share one five core box, and nothing kept a number for any of them. |
| [vps/Watch-Outside.ps1](vps/Watch-Outside.ps1) | Watches, from outside the VPS, the things the project needs that the VPS cannot watch for itself, and tells staff in Discord when one breaks and again when it is fixed. |
| [vps/Watch-Services.ps1](vps/Watch-Services.ps1) | Everything runs on one box now. The website, the game, the bot and the voice server are four things that can stop on their own, and nothing up there notices when one does. |
| [vps/Write-BotToken.ps1](vps/Write-BotToken.ps1) | The one writer of the Discord bot token. |
