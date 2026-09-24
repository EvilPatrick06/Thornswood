# The PowerShell scripts in tools

Every `.ps1` in this folder, 148 of them, with the one line that says
what each one is for. New-ScriptIndex.ps1 writes this file from the scripts
themselves: the line is a script's .SYNOPSIS where it has one, and otherwise
the first sentence of the comment at its top. Do not edit it by hand. Change
the script, then run

    .\tools\New-ScriptIndex.ps1

and commit this file with it. The build check on every pull request runs
tools\test-script-index.ps1, which goes red when this file is not what that
would write.

A script's options are not listed here. Get-Help reads them off its param
block, so they are always all of them:

    Get-Help .\tools\Ship.ps1 -Full

The node and Python scripts beside these (`Build-*.js`, `Audit-*.py` and the
rest) and the `test-*.js` harnesses are not in this list.

| Script | What it is for |
| --- | --- |
| [Add-Accuracy.ps1](Add-Accuracy.ps1) | Localised combat damage. Where you hit somebody starts to matter, on top of what Precision already does for where your weapon actually is. |
| [Add-Bodies.ps1](Add-Bodies.ps1) | Bodies, genitals and physics. Skeleton, female body, male body, and the jiggle that hangs off both. |
| [Add-CartTravel.ps1](Add-CartTravel.ps1) | Carriages and ferries between the holds, so turning fast travel off leaves people with a way to get about. |
| [Add-Characters.ps1](Add-Characters.ps1) | Installs Start On Save into the build. |
| [Add-JContainers.ps1](Add-JContainers.ps1) | Installs JContainers SE and switches on the MCM recording that sets everyone's survival meters up for them. |
| [Add-McmShortcut.ps1](Add-McmShortcut.ps1) | Installs MCM Shortcut NG, which is what lets Skyrim Unbound open its own config menu. |
| [Add-SkyrimUnbound.ps1](Add-SkyrimUnbound.ps1) | Installs Skyrim Unbound Reborn and PapyrusUtil into the isolated build, so nobody has to sit through the Helgen cart ride. |
| [Add-TempleRespawn.ps1](Add-TempleRespawn.ps1) | Stops people respawning on the spot where they died. |
| [Add-VoiceFeed.ps1](Add-VoiceFeed.ps1) | Adds the position feed to gamemode.js and redeploys it. |
| [Add-VpsKey.ps1](Add-VpsKey.ps1) | Puts another person's public SSH key on the VPS, so they can run the scripts that talk to it from their own machine without ever holding the Administrator password. |
| [Align-LoadOrder.ps1](Align-LoadOrder.ps1) | The client counts its own plugins with Game.GetModCount, which skips every ESL-flagged one because Skyrim gives those no normal index. |
| [Allow-Claude.ps1](Allow-Claude.ps1) | Adds the folders and the script paths a Claude working in this repo needs, to the Claude Code settings file, and reports exactly what it changed. |
| [Audit-Leftovers.ps1](Audit-Leftovers.ps1) | Measures. Deletes nothing, moves nothing, renames nothing. |
| [Audit-Mods.ps1](Audit-Mods.ps1) | Measures the build and says which parts carry a plugin and which are pure assets, because only the second kind can ever be optional. |
| [Backup-Server.ps1](Backup-Server.ps1) | Pulls everything off the server that could not be rebuilt from the repo, and puts it in a dated folder on this machine. |
| [Bootstrap-VPS.ps1](Bootstrap-VPS.ps1) | Run this ON THE VPS, once, in the PowerShell 5.1 that ships with Windows Server 2022. |
| [Build-HarvestTable.ps1](Build-HarvestTable.ps1) | Builds tools\harvests.json: the table the server needs to say who may pick which plant. |
| [Build-HuntTable.ps1](Build-HuntTable.ps1) | Builds tools\hunts.json: the table the server needs to answer a carcass. |
| [Build-Launcher.ps1](Build-Launcher.ps1) | Compiles the launcher into a real Thornswood.exe. |
| [Build-OreTable.ps1](Build-OreTable.ps1) | Builds tools\ores.json: the table the server needs to answer an ore vein. |
| [Build-RecipeTable.ps1](Build-RecipeTable.ps1) | Builds tools\recipes.json: the table the server needs to answer "may this person make this". |
| [Build-Server.ps1](Build-Server.ps1) | Compiles the game server out of our fork and puts the result where Deploy-Server.ps1 and Publish-Server.ps1 expect to find it. |
| [Build-SpellTable.ps1](Build-SpellTable.ps1) | Builds tools\spells.json: the table the server needs to hand somebody a spell. |
| [Bump-Version.ps1](Bump-Version.ps1) | Moves the launcher's version number, commits that one file, and stops. |
| [Chargen-Log.ps1](Chargen-Log.ps1) | What the server thinks is happening to your character. |
| [Check-Backdrop.ps1](Check-Backdrop.ps1) | Read only. Says what the main menu backdrop is in a game folder: the two logo meshes (their hashes and the root scale that decides whether the second plate draws) and the wallpaper texture (size, mip levels, format), against what the repo carries in tools\art\menu. |
| [Check-Balance.ps1](Check-Balance.ps1) | Reads the five generated tables and says whether the ladders line up. |
| [Check-Build.ps1](Check-Build.ps1) | The server does not check plugin names. It checks size and crc32 of every plugin it names, so the wrong version of a mod is the same to it as not having the mod. |
| [Check-Chargen.ps1](Check-Chargen.ps1) | Preflight for character creation. Everything it looks at is something that silently produces a broken first join rather than an error message, so it is worth thirty seconds before starting the server. |
| [Check-CollectionRules.ps1](Check-CollectionRules.ps1) | Whether the plugin rules the Nexus collection carries hold a clean install to a plugin list's order. |
| [Check-Controls.ps1](Check-Controls.ps1) | Every control in the launcher is found at runtime by name. |
| [Check-DevRosterSeed.ps1](Check-DevRosterSeed.ps1) | Expand the roster seed here-string exactly as Publish-Server would and parse the text that would actually be sent. |
| [Check-Editions.ps1](Check-Editions.ps1) | Does anything in the load order need the paid Anniversary upgrade? |
| [Check-LiveGamemode.ps1](Check-LiveGamemode.ps1) | Says whether the gamemode running on the VPS is the one in this repo. |
| [Check-Load.ps1](Check-Load.ps1) | Answers the only question worth asking before paying for a bigger server: what is this one actually running out of. |
| [Check-Manifest.ps1](Check-Manifest.ps1) | Says what load order the game server is actually handing out, and how it compares to the one you play with. |
| [Check-Outside.ps1](Check-Outside.ps1) | Walks the path a first install takes through the things this project does not run itself, and says which of them is broken or has moved. |
| [Check-Plugins.ps1](Check-Plugins.ps1) | What is enabled that should not be, and what is missing that should be there. |
| [Check-Roster.ps1](Check-Roster.ps1) | What is in each server's private folder, by name and size only. |
| [Check-RosterScript.ps1](Check-RosterScript.ps1) | Expand Check-Roster's here-string exactly as the script does and parse the text that would actually be sent. |
| [Check-ShipReady.ps1](Check-ShipReady.ps1) | Whether THIS machine can run a release, and what is missing if it cannot. |
| [Check-Site.ps1](Check-Site.ps1) | Asks whether thornswood.net is actually working: from the outside first, the way a visitor or an uptime monitor sees it, and then from the box, the way the site sees Discord. |
| [Check-VoiceInstall.ps1](Check-VoiceInstall.ps1) | Expand Install-Voice's here-string exactly as the script does and look at the text that would actually be sent. |
| [Clean-Downloads.ps1](Clean-Downloads.ps1) | Moves known-safe clutter out of Downloads into a quarantine folder. |
| [Clean-Everything.ps1](Clean-Everything.ps1) | Finds the old installers, build leftovers, temp files, stale backups and old GitHub release assets across this machine, the server and both repositories, adds up what they are costing, and prints it. |
| [Clean-Leftovers.ps1](Clean-Leftovers.ps1) | The other half of Audit-Leftovers.ps1. That one measures and never touches anything; this one removes what it found. |
| [Close-Launcher.ps1](Close-Launcher.ps1) | Shared by every script that writes into the build. |
| [Deploy-DevGamemode.ps1](Deploy-DevGamemode.ps1) | Sends tools\gamemode.js to the dev server on the VPS and restarts only that server. |
| [Deploy-Docs.ps1](Deploy-Docs.ps1) | Puts the Thornswood docs site on the VPS and keeps it running. |
| [Deploy-Gamemode.ps1](Deploy-Gamemode.ps1) | Puts gamemode.js into the built server and writes a server load order that actually lines up with the client's. |
| [Deploy-Server.ps1](Deploy-Server.ps1) | Sends the built server up to the VPS and restarts it. |
| [Enable-MCM.ps1](Enable-MCM.ps1) | Make MCM Helper work, on both sides, properly. |
| [Export-ServerPayload.ps1](Export-ServerPayload.ps1) | Packages everything the VPS needs into one zip. |
| [Fetch-Backups.ps1](Fetch-Backups.ps1) | Brings the nightly backups off the VPS onto this machine, and checks that what arrived is readable. |
| [Find-MissingMasters.ps1](Find-MissingMasters.ps1) | Reads the TES4 header of every plugin in Data and reports any master that is no longer present. |
| [Fix-Icons.ps1](Fix-Icons.ps1) | Windows keeps the picture it once drew for a shortcut in a cache, and goes on showing it long after the icon inside the exe changed. |
| [Fix-MaleBody.ps1](Fix-MaleBody.ps1) | The male body mesh in the game folder is a genital-slotted one, left behind when The New Gentleman was taken out. |
| [Fix-PluginProblems.ps1](Fix-PluginProblems.ps1) | Removes two plugins that are actively breaking things. |
| [Fix-QuickLoot.ps1](Fix-QuickLoot.ps1) | Turn MCMHelper.esp on, on both sides, in one go. |
| [Fix-Voice.ps1](Fix-Voice.ps1) | Get the voice service running on the VPS and keep it running. |
| [Get-Logs.ps1](Get-Logs.ps1) | Brings the server's own logs down to this machine so they can be read whole. |
| [Go.ps1](Go.ps1) | Installs the front, the overlays and the plugins, then reports what the server is doing. |
| [Install-Backup.ps1](Install-Backup.ps1) | Puts the nightly backup on the VPS: sends vps-nightly-backup.ps1 up, makes a passphrase if there is not one yet, and registers the scheduled task that runs it. |
| [Install-Bot.ps1](Install-Bot.ps1) | Puts the Thornswood bot on the VPS and keeps it running. |
| [Install-Emotes.ps1](Install-Emotes.ps1) | Lays down the emote wheel: a SkyrimPlatform plugin and the page it draws. |
| [Install-SkyMPClient.ps1](Install-SkyMPClient.ps1) | Switches the game folder from Skyrim Together Reborn to SkyMP. |
| [Install-Thornswood.ps1](Install-Thornswood.ps1) | Everything the client needs, in one run, in the order it has to happen in. |
| [Install-ThornswoodContent.ps1](Install-ThornswoodContent.ps1) | Drops Thornswood-Content.esp into the game folder and inserts it into the load order ahead of the city overhauls. |
| [Install-ThornswoodServer.ps1](Install-ThornswoodServer.ps1) | Run this ON THE VPS, after Bootstrap-VPS.ps1, as Administrator. |
| [Install-Voice.ps1](Install-Voice.ps1) | Puts the proximity voice service on the VPS beside the game server and opens the one port it needs. |
| [LoadOrder.ps1](LoadOrder.ps1) | The load order as the game counts it, and how to put a plugin list into the server's order. |
| [Mark-Spot.ps1](Mark-Spot.ps1) | Reads the spots you marked in game and prints them in the shape the content table wants. |
| [MaxOnline.ps1](MaxOnline.ps1) | How many people a Thornswood server seats: read from the one place it is written, and put into server-settings.json as the engine's own maxPlayers. |
| [Measure-Reclaim.ps1](Measure-Reclaim.ps1) | How much disk deleting a folder would ACTUALLY free. |
| [Move-Install.ps1](Move-Install.ps1) | Moves the build off the old name. Run it once. |
| [New-Character.ps1](New-Character.ps1) | Throws the test character away so the next connect builds a fresh one. |
| [New-ClientBuildRecord.ps1](New-ClientBuildRecord.ps1) | Records what the client runtime is and which fork commit it was built from, into tools\client-build.json. |
| [New-ScriptIndex.ps1](New-ScriptIndex.ps1) | Writes tools\README.md, the list of every PowerShell script in tools and the one line that says what each one is for. |
| [New-ServerBuildRecord.ps1](New-ServerBuildRecord.ps1) | Records what the server binary is and which commit it was built from, into tools\server-build.json. |
| [Package-Thornswood.ps1](Package-Thornswood.ps1) | Turns the built install at C:\Thornswood into the single file your friends run. |
| [Publish-Discord.ps1](Publish-Discord.ps1) | Posts the newest release into the Discord #news channel. |
| [Publish-Installer.ps1](Publish-Installer.ps1) | Puts the current installer on the docs site so friends always have the newest one without anybody sending files around. |
| [Publish-News.ps1](Publish-News.ps1) | Copies the launcher's news feed onto the docs site, so the News page there is the same list of changes people see in the launcher rather than a second one written by hand that immediately falls behind. |
| [Publish-Pack.ps1](Publish-Pack.ps1) | Builds the optional packs listed in optional-packs.txt, uploads them as release assets, and adds them to version.json so the Add-ons tab in every launcher offers them. |
| [Publish-Server.ps1](Publish-Server.ps1) | Run this ON YOUR LAPTOP. It packs the server, sends it to the VPS, installs it there and checks it came up. |
| [Publish-Update.ps1](Publish-Update.ps1) | Diffs the current build against the last published state, packs only what changed, uploads it as a release asset, and updates version.json so everyone's launcher picks it up. |
| [Remote.ps1](Remote.ps1) | Runs a bit of PowerShell on the VPS, properly. |
| [Remove-BodyMods.ps1](Remove-BodyMods.ps1) | Pulls the male and female genitalia mods out of the Thornswood game folder. |
| [Remove-DeadRecords.ps1](Remove-DeadRecords.ps1) | Deletes records from Thornswood-Content.esp that nothing uses any more, and refuses to delete one that anything still points at. |
| [Remove-FomodLeftovers.ps1](Remove-FomodLeftovers.ps1) | Clears the FOMOD option folders that the body mod install left sitting in Game\Data. |
| [Remove-Plugin.ps1](Remove-Plugin.ps1) | Takes one plugin out of the Thornswood build, reversibly. |
| [Rename-ContentRecords.ps1](Rename-ContentRecords.ps1) | Renames the editor ids in Thornswood-Content.esp that still carry the naming of the server the content came from, and changes nothing else about the file. |
| [Repair-Manifest.ps1](Repair-Manifest.ps1) | Takes packs with no download url back out of version.json and pushes the fix. |
| [Request-Restart.ps1](Request-Restart.ps1) | Tells the live server to warn everybody and then clear them out, without needing to be standing in the world to type /restart. |
| [Reset-Appearance.ps1](Reset-Appearance.ps1) | Puts a character back into the race menu without deleting them. |
| [Reset-Character.ps1](Reset-Character.ps1) | Throws away the character on the server so the next launch runs creation from the top. |
| [Restart-Server.ps1](Restart-Server.ps1) | Restarts a Thornswood service on the VPS. Nothing is copied and nothing is built: this only stops it and starts it again. |
| [Restore-Backup.ps1](Restore-Backup.ps1) | Opens one of the nightly backups: checks it has not been tampered with, decrypts it, and unpacks it into a folder you name. |
| [Revert.ps1](Revert.ps1) | Put the game back to the state it was working in. |
| [Rotate-ServerPassword.ps1](Rotate-ServerPassword.ps1) | Changes the server password and hands the new one to the site, so the launcher can fetch it after checking Discord. |
| [Run-Everything.ps1](Run-Everything.ps1) | One run that installs everything waiting, checks each piece actually landed, and publishes once at the end instead of once per mod. |
| [Set-Collection.ps1](Set-Collection.ps1) | Asks for the collection address and publishes it, in the two places that decide it, the same two Set-Server.ps1 uses. |
| [Set-DevNews.ps1](Set-DevNews.ps1) | Points dev releases at the Discord channel for dev build updates, so they stop being something only the dev launcher ever mentions and stay out of #news, where everybody reads about the build they actually play. |
| [Set-DiscordLogin.ps1](Set-DiscordLogin.ps1) | Points the site at your Discord, which is what decides who gets in anywhere. |
| [Set-Door.ps1](Set-Door.ps1) | Turns the game server's door on, off, or tells you what it has been seeing. |
| [Set-Server.ps1](Set-Server.ps1) | Sets the server everyone connects to, in the two places that decide it, and pushes. |
| [Set-UnboundMenu.ps1](Set-UnboundMenu.ps1) | Switches Skyrim Unbound's config menu between the locked version and the full one. |
| [Set-UpdateToken.ps1](Set-UpdateToken.ps1) | Puts the GitHub token the launcher uses to see releases into this machine's config.json, then proves it works before you walk away. |
| [Set-Vps.ps1](Set-Vps.ps1) | Points everything at a different server box. |
| [Setup-Discord.ps1](Setup-Discord.ps1) | Builds the Thornswood Discord: roles, categories, channels, permissions and the words in the read only channels, in one run. |
| [Setup-Domain.ps1](Setup-Domain.ps1) | Puts thornswood.net in front of the docs site, with a real certificate. |
| [Setup-SshKey.ps1](Setup-SshKey.ps1) | Type the VPS password one last time. |
| [Setup-Thornswood.ps1](Setup-Thornswood.ps1) | Puts Thornswood on this machine. |
| [Ship-Rules.ps1](Ship-Rules.ps1) | The one list of what never leaves a machine inside a Thornswood pack or installer. |
| [Ship.ps1](Ship.ps1) | Builds the launcher and publishes everything that changed, launcher and mods both, in a single release, to the main build or the dev build. |
| [Show-BotLog.ps1](Show-BotLog.ps1) | What the bot has been saying, without redeploying it to find out. |
| [Show-EslCascade.ps1](Show-EslCascade.ps1) | Answers one question: if the server load order drops every ESL-flagged plugin, how much else has to go with it? |
| [Sign-Artifact.ps1](Sign-Artifact.ps1) | Signs a built binary, or says plainly that it is not signing and carries on. |
| [Start-Thornswood.ps1](Start-Thornswood.ps1) | Launches the game the way the launcher's Play() does, without Skyrim Together. |
| [Sync-Client.ps1](Sync-Client.ps1) | Puts the client runtime built from the fork into the game folder, and refuses any file that is not the recorded build. |
| [Sync-LoadOrder.ps1](Sync-LoadOrder.ps1) | Build the server's load order from the client's. |
| [test-bot-wrapper.ps1](test-bot-wrapper.ps1) | The bot's wrapper on the VPS gives up after three quick exits in a row, instead of starting a bot that cannot start every fifteen seconds for ever. |
| [test-check-outside.ps1](test-check-outside.ps1) | Check-Outside.ps1 walks what a first install needs that this project does not run: the feed on GitHub, every address in it, the downloads, Steam's public build and the Nexus collection. |
| [test-collection-newest.ps1](test-collection-newest.ps1) | Which revision of the collection Vortex knows is out, read out of its own state.v2. |
| [test-collection-rules.ps1](test-collection-rules.ps1) | Check-CollectionRules.ps1, which reads the plugin rules the Nexus collection carries against a plugin list. |
| [test-dev-deploy-warning.ps1](test-dev-deploy-warning.ps1) | Deploy-DevGamemode.ps1 says who is on the dev server and warns them in the game before it stops anything. |
| [test-dev-ships-our-plugin.ps1](test-dev-ships-our-plugin.ps1) | A dev release carries our own plugin; a main release leaves it to the Nexus collection; every other file the collection provides stays out of both. |
| [test-dev-version.ps1](test-dev-version.ps1) | A dev build has to outrank what main has published, or nobody can take it. |
| [test-door-outage.ps1](test-door-outage.ps1) | The launcher's half of "Discord did not answer is not a no". |
| [test-feed-notice.ps1](test-feed-notice.ps1) | What the update feed says to everybody, and when it may hold Play. |
| [test-load-order.ps1](test-load-order.ps1) | The rule the pack's plugin list is put through before it ships, driven with stubs so it needs no game folder, no Data and no server. |
| [test-master-flag.ps1](test-master-flag.ps1) | The master flag in the plugin header, which the game honours BEFORE the list order, and which Deploy-Gamemode.ps1 never read until 22 September. |
| [test-max-online.ps1](test-max-online.ps1) | One number for how many a server seats, entry 281. |
| [test-package-release-dir.ps1](test-package-release-dir.ps1) | The installer has to find the releases feed on whichever machine builds it, and has to stop rather than guess when the feed is not there. |
| [test-pinned-downloads.ps1](test-pinned-downloads.ps1) | What a fresh VPS downloads is one exact version, checked against the checksum its vendor published for it, and nothing is installed when the download does not match. |
| [test-public-news.ps1](test-public-news.ps1) | What a stranger reads on the site's News page. |
| [test-publish-resume.ps1](test-publish-resume.ps1) | Runs the real resume helpers out of Publish-Update.ps1 against a temp folder. |
| [test-release-prerelease.ps1](test-release-prerelease.ps1) | A dev build goes up to GitHub marked prerelease, on every path the upload can take, and a main build does not. |
| [test-remote-length.ps1](test-remote-length.ps1) | No script sends the VPS more than a command line can hold. |
| [test-script-index.ps1](test-script-index.ps1) | Ship.ps1 says every option it takes where Get-Help can read it, and tools\README.md lists every script in this folder exactly as New-ScriptIndex.ps1 writes it. |
| [test-ship-rules.ps1](test-ship-rules.ps1) | Two rules in Ship-Rules.ps1 that decide what leaves this machine in a pack or the installer. |
| [test-steam-updates.ps1](test-steam-updates.ps1) | Steam's Updates setting for Skyrim, which nothing in the launcher read or set until 24 September (entry 271 on the To Do List, "Nothing stops Steam putting Skyrim back on the wrong build"). |
| [test-voice-ticket.ps1](test-voice-ticket.ps1) | The Discord ticket only goes to the voice service over https. |
| [vps-dev-instance.ps1](vps-dev-instance.ps1) | Runs ON the VPS. Makes the dev game server and the dev voice server beside the live ones, from copies of the live installs, on their own ports, with their own scheduled tasks, firewall rules and watchdog entries. |
| [vps-nightly-backup.ps1](vps-nightly-backup.ps1) | Runs on the VPS, once a night, as the scheduled task that Install-Backup.ps1 puts there. |
| [Watch-Foreground.ps1](Watch-Foreground.ps1) | Which window Windows is giving the keyboard to, sampled from outside the game. |
| [Watch-Services.ps1](Watch-Services.ps1) | Everything runs on one box now. The website, the game, the bot and the voice server are four things that can stop on their own, and nothing up there notices when one does. |
| [Wipe-Saves.ps1](Wipe-Saves.ps1) | Starts the world over. Everybody begins again, nothing is claimed, nothing has been looted, and every container in the province is holding what Bethesda put in it. |
