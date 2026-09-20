# Handoff, 17 September 2026

Written for whoever picks this up in Claude Code. Read CLAUDE.md first (the
rules), then this, then AUDIT-2026-09-17.md (the findings this work list comes
from). SECOND-DEVELOPER.md is the long form of how the pieces fit.

## Where things stand

- main is at 9b0c294, which is 1.1.45, shipped by Gavin from his machine on
  17 Sep. Live launcher: 1.1.45. Live server (C:\Thornswood-Server on the
  VPS): the 1.1.45 gamemode, deployed 09:24 on the VPS clock (the VPS and
  Gavin are UTC-06:00; server.log times are VPS local).
- `git status` shows every .ps1 and .md as modified. That is line endings
  only: `git diff --ignore-cr-at-eol` is empty. The working copies are CRLF,
  the commits are LF. Do not "fix" it and do not commit it.
- The dev server (C:\Thornswood-Server-Dev, port 7787, resources 7788, task
  'Thornswood Dev Server') still runs the 16 Sep gamemode. Nothing has gone
  to the dev channel yet. C:\Thornswood-DevBuild may not exist on Gavin's
  machine; `Ship.ps1 -Channel dev` needs it (installed from the main
  launcher's Settings page) and the Thornswood-Releases clone beside the repo.
- Live and confirmed with the actual bytes: the server publishes every
  non-storefront plugin as /api/servers/thornswood/plugins/<index>.bin
  (index = position in the manifest's mods array), and Scan compares size
  and CRC-32 of every plugin against the manifest, Fix downloads the
  server's copy. 10.bin answered 200 with all 3,157,818 bytes of
  JKs Skyrim.esp.

## What Gavin asked for, in his words

"let's apply all of the fixes for the server and launcher + game to the dev
launcher + server, for the website+discord stuff go ahead and apply them now"
and "I like all of those suggestions aswell follow the same method of dev
build + website and discord go live now".

So: every bug and every suggestion in AUDIT-2026-09-17.md. Launcher, gamemode
and plugin changes go out on the dev channel (a dev Ship plus a dev server
deploy), not main. Website and Discord changes go live at once. Main gets
nothing until he says so. CLAUDE.md still holds: the person runs Ship,
Deploy-*, Request-Restart, git push and gh pr create; a Claude prepares
everything, compiles, and shows the command.

## The work list

Numbers are the audit's. "Fix" is what was decided; where a call is his, it
says so.

### Launcher (tools\app, C# 5, one complete dev release)

1. Shell.cs startup: if `Checks.GameRunning()`, set `playing = true`, re-take
   Hold, skip `Swap.Restore()`, `Keep.TakeNote()`, `Keep.Unpark()`. The exit
   tick already does them.
2. Updater.cs delete.txt: `Path.GetFullPath` before `Inside`, like the
   entries loop already does.
3. Creation.cs Send: stop sending `ticket` in the /choose body. The voice
   service never reads it.
4. Shell.cs: set `updatePending = true` in the closed-for-update branch before
   `CheckUpdatesBackground(true)`; Play() refuses while `updatePending`,
   `collectionBarUp` or `ownGameBusy`.
5. Shell.cs StartAs: a static in-flight flag cleared in onDone; disable
   `charBar` while the Door check is out.
6. Shell.cs CheckUpdatesInPlay: a separate `failed` flag; only a real "no
   update" resets `updateSeenAt`; a thrown check (GitHub 403) does not.
7. Shell.cs btnFix: refuse with "Close Skyrim first." when the game runs.
8. Updater.cs RemovePack: collect the removed game\ rels and call
   `Keep.Forget`; on an own-folder install also remove them from the Steam
   copy.
9. Junction.Create: delete the folder it made when Set fails. Swap.Restore:
   when `win` is an empty real folder and `bak` exists, delete `win` and move
   `bak` back. Uninstall: refuse while a `.st-backup` folder exists.
10. Self-update batch: loop the `move /y` until it succeeds (tasklist wait,
    as Uninstall.Finish does).
11. Voice.cs: keep the change check on `lastStatusLine`, republish
    voice-status.txt on a 2 s timer, not every 100 ms.
12. Chars.cs Use: after `AutoJoin.SetProfileId(id)` require
    `GetProfileId() == id`, otherwise stop before Play with a note.
13. Verify.cs FetchPlugin and DeployPersonal write through the hard link into
    Vortex's staging. His call: keep write-through (the persistent fix for a
    person who only plays Thornswood) or `OwnGame.Unshare(dest)` first (keeps
    it to our folder, leaves the wrong bytes in staging). Present both in
    #dev; do not pick quietly. Default until he answers: leave as is.
14. Voice.cs Reconfigure: skip the Post when host, port and profile match the
    last one; the voice page closes the old WebSocket before opening a new
    one.
15. Account.cs: confirm against the deployed C:\Thornswood-Voice\voice-server.js
    whether /whoami and /claim exist. If not, drop the 7 s WaitForSync at
    Play. If they do, note they key on a public Steam id with no ticket.
16. Shell.cs Play: run `Chars.WaitForSync`, `Creation.Send`,
    `Verify.DeployPersonal` and `SkyMp.Start` through Waiting. Also the
    startup RunScan in a try/catch.
17. Uninstall.Begin: `Hold.Release(); Keep.Unpark();` after Kill, before
    anything under Profile is deleted.
18. Every generated .cmd (Uninstall.cs, Updater.cs, ShellOwnGame.cs,
    DevBuild.cs): first line `chcp 65001 >nul`.
19. Pages.cs colour line: test `last == -2` before `last < 0`.
20. Shell.cs voice probe: `if (port <= 0) port = 7778;` after the TryParse.

Suggestions that are launcher work: Door.cs fail closed once the door is
enforcing (cache the last signed answer, grace period, then refuse);
Updater.cs per-file pack ownership in RemovePack (skip a path any other pack
or Vortex's deployment still lists); Mics.cs send the device id in the config
message and pick it by label in the voice page; Downgrade apply and
Uninstall.OurGameFiles use `OwnGame.DeployedIn` instead of reading only
Data\vortex.deployment.json; Updater.Check gets a timeout (Quick) and 403
wording; a partial install refreshes pendingPacks; Keep.IsOurs accepts the
thornswood- prefix; ClearLeftovers skips young processes; Downgrade's
twenty-minute fallback only fires when this run's log showed the depot start
and the marker equals the manifest.

### Gamemode (tools\gamemode.js, dev server)

22. `/restart` off the chat path (restart.json still works); `/tp` admin only.
    Later: a per-login token the page passes on join.
23. `mp.setRaceMenuOpen(actorId, false)` in applyLauncherChoice and wherever a
    done state is written.
24. On a new arrival in the appearance stage clear `liveSince`, `where`,
    `askedAt`, `nudged`, `waitedForChoice`; set `askAt = now + 4000`.
25. Login: if `isDead`, spawn at the temple point, not the default.
26. Solstheim: compare against `'800:dragonborn.esm'`.
27. The three unstored `setInterval`s (position feed, online.json writer,
    roster writer): store on globalThis and clear on hot reload like the
    others.
28. `arm()`: mark every MARK >= seconds as said.
29. `onDeath`: return unless the actor has a profileId.
30. Movement test: about 32 units or 10 degrees across two consecutive
    samples.
31. `placeName`: prefer EDID; accept FULL only when printable ASCII.
32. Log noise: a gamemode-side thornswood.log with only Thornswood's lines,
    or filter the three noise families (Script not found, Negative
    Magicka/Health/Stamina for eight NPC bases, Skipping non-Sweet scripts).
Suggestions: a hot-reload guard around the commands block; write
`restarting: true` into online.json during a countdown for the probe (see 33).

### Plugins (tools\ts-plugins is canonical; Go.ps1 copies them into the game folder; Ship packages from there)

33. thornswood-front.js probe: 12 strikes instead of 4, and honour
    `restarting: true` in online.json. Clear `__thornswoodInWorld` where it is
    set on leaving the world (nothing reads it today; that agent claim was
    wrong).
34. Skip the ACTI re-activation for bases the server handles, so
    `mp.onActivate` runs once per press.
35. Controls watchdog: skip while dead or in furniture; stuck detector counts
    only isDown.
36. Emotes wheel: one side owns Escape, Tab and the digits (Plugins vs UI
    copy).
37. Throttle the per-frame `Ui.isMenuOpen` and controls natives to 250 ms;
    stop the log append on every activation.

### Website and Discord (live now)

38. The Discord invite in config.json on the VPS (C:\Thornswood-Docs\config.json,
    `discord.invite`) expires 15 October 2026. Every door on the site, the
    /discord redirect and the launcher's /api/public use it. Replace it with
    one that never expires. The script prompts for the link so it is never in
    a command:

    ```powershell
    cd $env:USERPROFILE\Downloads\Thornswood-Repo
    .\tools\Set-DiscordLogin.ps1 -NewInvite
    ```

    (Discord: right click the server, Invite People, Edit invite link, Expire
    after Never, Max uses No limit. The bot's stored token could also create
    one from the VPS; never print that token.) Check afterwards that Discord's
    public invite endpoint reports `expires_at: null`.
39. data\site\join.md ("The long version") contradicts /downloads. Rewrite
    to the real story: Vortex collection required, one installer of about
    700 MB into the Skyrim already there, 1.6.1170 and the Downgrade button.
    Deploy with `Deploy-Docs.ps1 -Site` (only data\site\*.md).
40. /known and /help public: server.js `PUBLIC_PAGES` (line 164) plus the
    document route for those two pages, and a link from rule 6 and /join.
41. HEAD answers 404: every route tests `req.method === 'GET'`. Treat HEAD as
    GET without a body (one place near the top of the handler).
42. Mark Why-Keizaal.ps1 `hidden` in the files feed (server.js 289-294 is
    where hidden is read).
43. and 44. and 45. known.md and help.md (live copies on the VPS under
    C:\Thornswood-Docs\data\, edited on the site, never overwritten by a
    deploy unless -SeedDocs; repo seeds under tools\docs-app\data\): the
    install story, 1.6.1170 and Downgrade, Scan compares bytes and Fix
    downloads the server's copy, what happens around Play (trade and town are
    chosen in the launcher before Play, then the hall, the race menu for the
    face, then the chosen town's inn with the kit; books are only the
    gamemode's fallback when no launcher choice arrived, nobody reads books),
    log paths for both layouts (Steam copy and C:\Thornswood\Profile), Start
    On Save present but inert, and settle the Tavern Games and Respawn
    contradiction between the 15 Sep news and known.md (ask Gavin which is
    true).
46. Check-Site.ps1: add HTTP GET and HEAD of / and every PUBLIC_PAGES route,
    /api/public status, the invite's `expires_at`, and stop hardcoding the
    VPS address and admin user.
Suggestions: og:title, og:description, og:image in home.html;
Strict-Transport-Security; robots.txt; /download and /install redirect to
/downloads; /world#accord scrolls after the body loads.

/support is gone as of 20 September. It existed to say what a tier cost
while there was nowhere else to read it; the Patreon is set up and says it
now, so the nav button and the footer link both go straight there. The
address 404s rather than redirecting, so an old link shared in a channel
lands on 'not here'.

server.js changes need the full `Deploy-Docs.ps1` (no switch); it copies
server.js and public\, restarts the 'Thornswood Docs' task, and leaves the
documents alone. Verify each page with a real GET after.

## How to build, check and ship

Compile (csc, the .NET Framework 4 one in Windows; the same check GitHub
runs on every pull request):

```powershell
cd $env:USERPROFILE\Downloads\Thornswood-Repo
.\tools\Build-Launcher.ps1 -NoPause
node --check .\tools\gamemode.js
node --check .\tools\ts-plugins\thornswood-front.js
node --check .\tools\ts-plugins\thornswood-emotes.js
node --check .\tools\ts-plugins\thornswood-chargen.js
node --check .\tools\ts-plugins\thornswood-mark.js
node --check .\tools\ts-plugins\thornswood-voice.js
```

Patch-Client.ps1 has a -Check mode; test it against a copy of the bundle, not
the live one.

Dev launcher release (Gavin or Djinn runs it; says so in #dev; version becomes
1.1.45.N; announces to the dev server's data folder, no source commit):

```powershell
cd $env:USERPROFILE\Downloads\Thornswood-Repo
.\tools\Ship.ps1 -Channel dev "what changed, in one line"
```

Dev server gamemode. Do not point Deploy-Server.ps1 at the dev root: it sends
server-settings.json rewritten from the local build (port 7777, the live
name), which would put the dev server on the live port, and its stop step
kills every node process whose command line contains skymp5-server, which is
the live server too. tools\Deploy-DevGamemode.ps1 (new, 17 Sep, parses, not
yet run against the box) sends gamemode.js alone, stops only the process on
the dev port, refuses a root whose settings say 7777, keeps the old gamemode
beside the new one, restarts the dev task and tails its log:

```powershell
cd $env:USERPROFILE\Downloads\Thornswood-Repo
.\tools\Deploy-DevGamemode.ps1
```

The dev server is up when the tail shows the "plugin files published" line
and the script reports the UDP 7787 listen. A gamemode change that also
changes the load order or CHARGEN needs Deploy-Gamemode.ps1 -Vortex first;
code-only changes do not.

Site:

```powershell
cd $env:USERPROFILE\Downloads\Thornswood-Repo
.\tools\Deploy-Docs.ps1 -Site
.\tools\Deploy-Docs.ps1
.\tools\Check-Site.ps1
```

Main release, only ever from Gavin's machine, only when he says main:
`.\tools\Deploy-Server.ps1 -Now` first when the gamemode changed, then
`.\tools\Ship.ps1 "notes"`.

## Facts you would otherwise spend a night rediscovering

- The resources server on port 3000 (and 7788 on dev) serves any file under
  data\ except a name containing .esp, .esm or .esl, which gets a 403.
  That is why plugins are published as <index>.bin. HEAD is not supported
  there either.
- Manifest: /api/servers/thornswood/manifest.json, `mods[]` with `filename`,
  `size`, `crc32` (zlib CRC-32 as a signed int32) and `loadOrder`. 60
  plugins, the first five are Bethesda masters, the storefront set is
  skipped by Scan. JKs Skyrim.esp is index 10.
- The SkyMP client bundle (Data\Platform\Plugins\skymp5-client.js) is
  patched, not built. Facts about it: createActor for our own actor runs the
  in-world path (moveRefrToPosition) or the main-menu path (loadGame after
  two ticks); nobody listens to connectionDisconnect, NetworkingService just
  reconnects; verifyLoadOrder runs on the first update and checks name, size
  and crc32 by position, skipping the storefront set; the difficulty service
  writes iDifficulty every 60 updates (Patch-Client sets 3, Expert); LoadGame
  writes a synthetic save TESMODPLATFORM-<guid>.ess into the live Saves
  folder; nothing in the bundle reads `__thornswoodInWorld`.
- Start On Save (po3, v2.8) loads the newest valid save at the first
  LoadWaitSpinner unless `sCharacterName` in its ini names a character with
  no matching save. The launcher writes `sCharacterName = Thornswood-Nobody`,
  so it is present but inert. That was the crash on a fresh install with old
  single player saves.
- The kick problem: a kick from the gamemode while the server process stays
  up leaves that character's server-side actor in a state where the
  reconnecting client is never sent the world (13 of 13 reconnects dead on
  17 Sep, "all the NPCs are gone"). A process restart clears it; fresh
  characters always worked. The re-attach path is
  `PartOne::SetUserActor` in skymp5-server\cpp\server_guest_lib\PartOne.cpp
  (clears hoster, UnsubscribeFromAll, RemoveFromGridAndUnsubscribeAll,
  ForceSubscriptionsUpdate in MpObjectReference.cpp); the upstream comment
  says untested. 1.1.45 stopped the update countdown from kicking; the
  restart countdown still kicks because a process restart follows. The real
  fix is in scam_native. The SkyMP checkout is under C:\Thornswood-Dev\skymp
  (Deploy-Server's Dist default is C:\Thornswood-Dev\skymp\build\dist\server).
  A full `find` over it times out; grep server_guest_lib only.
- Downgrade: the three depot commands in Downgrade.cs are correct
  (download_depot 489830 with depots 489831, 489832, 489833 and the 1.6.1170
  manifests; confirmed against the dwemermods guide and SteamDB). Every
  failure so far was the command not landing on the Steam console's command
  line. 1.1.43 clicks the command line first; 1.1.45 logs the exact command
  and Steam's content log tail when a part does not start. Djinn (D:\Thornswood,
  game on 1.7.104) is the live test; the launcher.log from his next attempt
  says which it was.
- The profile 1 chain (fixed in 1.1.45): Adopt moved single player saves
  into slot 1, Header read them as a character, Claim(1, false) returned
  profile 1, every such install logged in as one shared character. Now Claim
  always takes a new id, a slot with saves and no profiles.txt row reads as
  empty, and a real Saves folder is set aside as
  Saves-before-Thornswood-<stamp>, never deleted.
- Server log on 17 Sep: 78 percent noise (951 "Script not found",
  785 "Negative Magicka/Health/Stamina" for eight NPC bases: a91a0, 4359c,
  ec968, fa6d9, 23ab1, 422b2, ec96a, 1003025, and 3,412 "Skipping non-Sweet
  scripts").
- Site: server.js reads C:\Thornswood-Docs\config.json (`discord.invite`,
  `patreon`, `access`); public pages are one shell, public\home.html, with
  DISCORD_URL replaced by the invite; page text is data\site\<name>.md served
  by /api/page/<name>; the docs site runs as the 'Thornswood Docs' task, node
  on 3001, Caddy in front for https://thornswood.net. HEAD returns 404
  because every route tests for GET; the fallthrough is `send(res, 404,
  'not here')` at the end of the handler.
- VPS layout: C:\Thornswood-Server (7777, resources 3000, 'Thornswood
  Server'), C:\Thornswood-Server-Dev (7787, 7788, 'Thornswood Dev Server'),
  C:\Thornswood-Voice (7778), C:\Thornswood-Voice-Dev (7789, 'Thornswood Dev
  Voice'), C:\Thornswood-Docs (3001, 'Thornswood Docs'). Server data under
  <root>\data: api\servers\thornswood\manifest.json, plugins\<index>.bin,
  allowed.json, characters.json, online.json, door.log, restart.json.
  SSH as Administrator with the key; passwords live in the VPS configs and
  are never printed.
- Testers: OnlyChromes was the only machine with the LOAD ORDER ERROR
  (bytes differed, names matched) and the dead reconnects (characters
  ff000011, ff000015). Mattythrill's fresh install hit the Start On Save
  crash and the profile 1 card. Djinn is the Downgrade test.
- Gavin's machine is on 1.6.1170 with the collection; the launcher installs
  into the Steam copy today (the own-game-folder branch is Djinn's, not on
  main). Test with fresh characters every time; never launch through Steam.

## How Gavin wants the work done (beyond CLAUDE.md)

- Full copy and paste command blocks, with no example value in any command
  block; a value he has to supply is described in prose or prompted for by
  the script.
- No unsolicited next-step advice. Command blocks he asked for are wanted;
  "you should now" is not.
- Measure before claiming a cause, and label findings verified, likely or
  measured. If something could not be checked, say so.
- Every change goes out complete in one release, launcher, game files and
  server together.
- Anything to be removed from his machine goes into `_to_delete\`; he
  deletes. The patch scripts from this session are there
  (`_to_delete\patch-*.py`): each one documents a change with its evidence
  and was applied with an exact-anchor edit. That pattern was for editing
  from a Linux shell; in Claude Code on Windows, edit the files directly.
- Testing phase: broken and fixable is acceptable, excessive caution is not.

## Not verified yet

- Whether Djinn's Downgrade click landed (his launcher.log after 1.1.45).
- Whether the dead reconnect is the server not sending or the client not
  applying (a skyrim-platform.log from a kick-reconnect settles it).
- The timing findings 4, 5, 6 and 10 in the audit each have a one-line
  repro in their text.
- Whether C:\Thornswood-DevBuild is installed on Gavin's machine.
