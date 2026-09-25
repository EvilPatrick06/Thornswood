# Patrick

## Now

1. Fresh install, end to end, on a machine that has never had Thornswood on it.
   This is the one thing nothing else can stand in for. Watch for three lines:
   `built for the collection` when packaging, `moved to C:\Thornswood\Game-old-...`
   if there was an old install, and `165 packs marked as already in this build`.
   Then the launcher should open on 96 plugins, no collection bar, Play live.

2. Find out what the server itself caps people at. The launcher says 25 now,
   in two places so it reaches fresh installs and existing ones both, but that
   is only the number the launcher shows. SkyMP has its own limit in
   `server-settings.json` on the VPS and nobody has looked at it.

3. Delete NirnLabUIPlatform. 356 MB of another server's interface framework
   that nothing in the 96 plugins asks for. It no longer ships in the
   installer either way, this is just getting it off the disk.

```
That script is gone as of 20 Sep with the rest of the other-server support.
Delete the folder by hand, or purge and redeploy in Vortex, which rewrites
Data from staging and leaves nothing that was not deployed.
```

## Next

4. The door on the game server. The check in front of Play is real and works:
   the launcher asks the site, the site asks Discord, no role means no launch.
   The backstop on the server is not built. `allowed.json` has nothing in it
   because nothing writes it: the site has no endpoint to serve the list, the
   launcher never sends the profile id it is about to play as, and nothing on
   the VPS refreshes it. Three pieces. It only matters against somebody
   connecting without the launcher at all, so it is not blocking testers.
   Do not run `-Enforce` until the list has names in it.

5. Sign the installer. Windows warns on it because it is unsigned, and an
   unsigned file builds reputation against its own hash, so a new build every
   release means the warning never goes away. Azure Artifact Signing is about
   ten dollars a month, no hardware token, and individuals are supported in the
   USA. EV certificates stopped skipping SmartScreen in 2024, so the expensive
   option buys nothing. The stub already scans backwards for its payload
   trailer, so signing will not break the installer when you get to it.

6. The alt tabbed keyboard leak. Same cause as typing in Docs reaching game
   chat. Two people have reported it.

7. Retest chains and cage doors. Reported still dead after the handle fix and
   never looked at again.

8. Run the armour slot audit, to find out whether the gear strip was one mod or
   a group. The path is the Steam copy now, not a Game folder of our own.

```
python .\tools\Audit-ArmorSlots.py "C:\Program Files (x86)\Steam\steamapps\common\Skyrim Special Edition\Data"
```

## Later

9. Decide about the loose assets. 0.96 GB under the Steam Data folder that
   Vortex did not put there, and after NirnLabUIPlatform goes it is mostly
   `textures` and `meshes`. Some of that is another server's leftovers and some
   of it is your own BodySlide builds, and only one of those comes back by
   reinstalling something. Needs your eyes, not a script's.

```
The listing script is gone as of 20 Sep. To see what Vortex did not put
there: purge in Vortex, then whatever is left under Data is loose, and a
redeploy brings the collection back.
```

10. Set up a TURN relay on the VPS so voice has a fallback when two people both
    fail ICE.

11. Bard instruments. They still render wrong and they are not playable yet.

12. Intro music. Something of our own over the main menu, so the first thing
    anybody hears is Thornswood rather than vanilla Skyrim.

13. The professions themselves. Character creation asks for all three and
    vanilla levelling is off, so nothing anybody does now is wasted, but what
    each half of a profession can actually make, what only a class can do, and
    the four ranks are all still to build.

## Done, and worth remembering why

- Emote wheel. It was on this list as never investigated. It has been in
  `thornswood-emotes.js` the whole time: G opens it, Tab steps to the next
  category, N stops, thirty four emotes in six categories. G is WheelKey = 34
  in `launcher\Thornswood.ini`; the plugin falls back to B only when that
  line is missing, which is where the B in this note used to come from.
- The installer is one small file now and fetches its own payload, which is
  what lets the icon render, lets a dropped download resume, and lets a
  signature accumulate reputation later.
- The news feed. PowerShell hands a one item list out of a function as a bare
  string, so any release with a single detail line published as text instead
  of a list and the page threw on it.
- Release notes reach the Discord. `Publish-Discord.ps1` said it was called by
  Ship for as long as it has existed and nothing ever called it.

## Commands

Server deploy. Warns the room, disconnects nobody.

```
.\tools\Deploy-Server.ps1
```

Server going down for a while. Counts down and empties the room first.

```
.\tools\Deploy-Server.ps1 -Mode restart -Minutes 10
```

Announce on its own.

```
.\tools\Request-Restart.ps1 -Mode notice -Minutes 5 -Why "a server update"
```

Ship a release. Builds the launcher, publishes it, tells the site, posts to
the Discord, then gives the world five minutes.

```
.\tools\Ship.ps1 "what changed, in a sentence"
```

Rebuild the installer. `-Vortex` builds out of the Steam copy and leaves out
everything the collection provides, which is what makes it half a gigabyte
instead of fourteen.

```
.\tools\Package-Thornswood.ps1 -Vortex
```

The public pages and the boards.

```
.\tools\Deploy-Docs.ps1 -Site -Boards
```

Load order, after adding or removing any mod.

```
python .\tools\Sync-LoadOrder.py --server-data "C:/Thornswood-Server/plugins" --dry-run
```

Build the server, then the Skyrim Platform DLL.

```
cmake --build C:\Thornswood-Dev\skymp\build --target skymp5-server --config Release
cmake --build C:\Thornswood-Dev\skymp\build --target skyrim-platform --config Release
```

## Where things are

The game is the Steam copy now, not a folder of our own. Vortex deploys the
collection into it and the launcher only reads it while `C:\Thornswood\Game`
does not exist.

```
C:\Program Files (x86)\Steam\steamapps\common\Skyrim Special Edition
C:\Thornswood\Profile\launcher.log
C:\Thornswood\Profile\SKSE\CrashLogger\
```
