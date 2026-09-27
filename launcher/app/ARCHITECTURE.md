# How the launcher is put together

This page is for somebody opening `launcher\app` for the first time. It says how
the launcher starts, which class owns which files, and exactly what happens
between pressing Play and the game window appearing, with the file and line of
every step. It replaces a finished note about wiring Discord.cs in, which both
long-form documents used to point at as if it were this page.

## Which install this describes

Thornswood's own game folder, the settled design since 18 Sep. The game runs
from `<Root>\Game` (`C:\Thornswood\Game` on the main build,
`C:\Thornswood-DevBuild\Game` on the dev build), which OwnGame made from what
Vortex deployed into the Steam copy: big files as hard links, anything another
program rewrites in place as copies. In this shape `Paths.Collection` is false
and `Paths.Game` is `<Root>\Game`.

The older shared shape, where there is no `<Root>\Game` and the game would run
out of the Steam copy (`Paths.Collection` true), is still in the code for one
reason: so the launcher can recognise it and refuse to Play from it (step 3
below). Where a step behaves differently in that shape, the page says so in
one line. Nothing here describes it as something to run, and the two shapes
must never be mixed in one release.

`<Root>` is the install folder and `Profile` means `<Root>\Profile`. Every file
named below is in `launcher\app` unless the path says otherwise.

## Reading the references, and keeping them true

A reference looks like `Shell.cs:3870 Play()`: the file, the line, and the
name found on that line. A name ending in `()` is where that method is
declared. A name without them is the line that calls it, sets it, or wires it.

Lines move every time somebody edits a file above them. The name is the
anchor: if the line has moved, search the file for the name. Run
`node tests\test-architecture.js` and it prints where every moved reference is
now. It fails when this page names something that is no longer in its file,
or lists the steps of one method in an order the code no longer runs them in.
A line that has only moved is a NOTE, never a failure, however far it moved:
where a name is on more than one line, such as a method's declaration and a
call to it, the harness follows the one that moved with the references around
it, not the nearest.

Whoever changes a step on this page changes the page in the same pull
request. The Play sequence changes more than anything else here, so that is
the part to check first.

## 1. Starting up

### What the exe is

`scripts\release\Build-Launcher.ps1` compiles every `launcher\app\*.cs` with the .NET
Framework 4 csc (C# 5 only) into `<Root>\Launcher\Thornswood.exe`. It embeds,
as resources: `launcher\ui.xaml`, the emblem, header art and video, the WebView2
DLLs, `launcher\voice-host.html`, the `Thornswood.ini` template from
`launcher`, and `records\client-build.json`. The update system publishes
this one exe and nothing beside it, which is why everything rides inside.

### There is no compiled window

There is no App.xaml, no code-behind and no `InitializeComponent`. The window
is `launcher\ui.xaml`, read out of the exe's resources as a string and turned into
a live `Window` object at run time by
`Shell.cs:263 XamlReader.Parse`. The xaml carries no `x:Class` and no event
handlers. So:

- `Shell.cs:531 Bind()` finds each named control with `win.FindName` (the
  helper `F<T>` just above it) and keeps it in a static field.
- `Shell.cs:1021 Wire()` attaches every handler in code.
- `Shell` is therefore a static class, not a `Window` subclass, and it is
  split across seven files: Shell.cs, Pages.cs (the read-only pages),
  ShellOwnGame.cs (the game folder card and offer), ShellSteamUpdates.cs (the
  question about Steam's Updates setting after a downgrade), ShellUninstall.cs
  (the launcher as Windows' Uninstall button opens it), Waiting.cs and
  Stall.cs.

A control renamed in ui.xaml is not a compile error. `F<T>` returns null and
the first unguarded use of it throws, which at startup lands in Main's catch
and shows "Thornswood could not start".

### The startup order

In the order Run takes it. Everything happens on the window's thread unless
it says a pool thread.

| # | Where | What it does and what it leaves behind |
|---|---|---|
| 1 | `Shell.cs:154 Main()` | Takes a mutex named for this install folder (`Shell.cs:219 MutexName()`), so the main and dev builds can both be open. A second copy of the same build says so and exits. Anything thrown out of Run is appended to `Profile\launcher.log` as COULD NOT START and shown in a box. |
| 2 | `Shell.cs:244 Run()` | Reads `-root` and `-uninstall` off the command line. |
| 3 | `Shell.cs:252 Paths.Init` | `Paths.cs:39 Init()` works out Root, Game and every Profile path, once. Nothing recomputes them, which is why making the game folder restarts the launcher. |
| 4 | `Shell.cs:253 Config.Load` | Reads `<Root>\config.json` (`Config.cs:289 Load()`). Then `Stats.Load` reads `Profile\stats.txt`. |
| 5 | `Shell.cs:263 XamlReader.Parse` | Builds the window from the embedded ui.xaml. |
| 6 | `Shell.cs:265 Bind` | Finds the controls, and sets `Discord.Folder` to Profile. |
| 7 | `Shell.cs:266 Themes.Apply` | Colours from config.json's theme. |
| 8 | `Shell.cs:267 Wire` | Attaches every handler, including the Play button, calls `WirePages` and `WireOwnGame`, and starts the two second timer (`Shell.cs:1516 DispatcherTimer`). |
| 9 | `Shell.cs:268 BuildThemeRow` | Then `Shell.cs:269 BuildDisplay`, `Shell.cs:271 BuildStatRow`, `Shell.cs:272 BuildPathRows` and `Shell.cs:273 BuildHelp`: the theme buttons and display rows on Settings, the strip of figures from `Profile\stats.txt` (time played, sessions, last played, last update), the install and game folder rows, and the Help page. They draw controls and write nothing. |
| 10 | `Shell.cs:279 OpenForUninstall` | Only when Windows sent `-uninstall`, which is what Uninstall under Installed apps runs. `ShellUninstall.cs:49 OpenForUninstall()` stops the two second timer before it has ticked, stands down the game folder check, opens on Settings with the Uninstall button in view, and runs the message loop itself. Run returns from here, so no row below this one happens: no update check, no server scan, no client repair, no voice, and the Installed apps entry is not written again. |
| 11 | `Shell.cs:281 BuildModList` | The Mods page's list, then `Shell.cs:282 RefreshDiscord` (the Discord card) and `Shell.cs:283 ShowPage`, which opens on Play. |
| 12 | `Shell.cs:288 Register.Ensure` | Writes this install's entry under `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall` (`Register.cs:78 Ensure()`). |
| 13 | `Shell.cs:301 Discord.SendPendingLogs` | Pool thread. A session that ended without sending its logs (`Profile\logs-pending.txt` still there) sends them now, before a new game start truncates them. |
| 14 | `Shell.cs:307 AutoJoin.Ensure` | Makes `Game\Data\Platform\Plugins\skymp5-client-settings.txt` when there is none (`AutoJoin.cs:52 Ensure()`). |
| 15 | `Shell.cs:316 Checks.GameRunning` | A game still running from before the launcher was restarted is taken over: `Shell.cs:326 Hold.Take` holds our files again and nothing is pulled apart under it. Otherwise `Shell.cs:331 Swap.Restore` takes off any redirect a crash left and `Shell.cs:332 Keep.TakeNote` deletes a stale session note. |
| 16 | `Shell.cs:334 Leaks.Clean` | Deletes the one sign in file a 16 Sep installer shipped, matched by hash. Then `Shell.cs:335 ThornIni.Ensure` writes `Game\Data\SKSE\Plugins\Thornswood.ini` from the template if it is missing, and `Shell.cs:336 ThornIni.UndoShippedFov` runs once per install. When no downgrade is needed, `Shell.cs:338 SteamUpdates.Report` logs Steam's Updates setting for the Skyrim the downgrade looks after, and writes nothing. |
| 17 | `Shell.cs:340 Keep.Unpark` | Puts back plugins a crashed session left parked. Then `Shell.cs:344 Keep.Seed` fills `Profile\Keep` from pack records for files it has no copy of yet. |
| 18 | `Shell.cs:353 Display.MatchScreen` | Unless Lock resolution is ticked: the game's resolution and menu scale follow the screen (`Shell.cs:359 Display.ScaleMenus`). |
| 19 | `Shell.cs:370 Icons.Ensure` | Pool thread. The shortcut icon follows the exe. `Shell.cs:393 ClearLeftovers` (pool) ends a windowless Skyrim over three minutes old. `Shell.cs:407 Uninstall.DropScratch` (pool) deletes the installer's leftover `Thornswood-setup` folder. |
| 20 | `Shell.cs:423 RunScan` | `Verify.Run` against the server's manifest, then the Mods card. Then DrawStatus fills the checklist (on Diagnostics since #607), the Play summary and the button (see "The gate" below). |
| 21 | `Shell.cs:429 HealClientBackground` | Pool thread, only when the six client runtime files are not the recorded build: `ClientRuntime.cs:206 Heal()` fetches them. Then `Shell.cs:430 AutoDisplayOnce` marks `config.json` so it never runs again and, on an install that has never played, matches the game's resolution to the screen; `Shell.cs:431 StartPing` asks whether the server is up. |
| 22 | `Shell.cs:433 CheckUpdatesBackground` | Pool thread: the update check (see Updater in section 2). With no update source configured, `Shell.cs:435 Unblock` frees Play instead. |
| 23 | `Shell.cs:451 Voice.Prepare` | Installs the resolver that loads WebView2 out of the exe. `Shell.cs:453 Voice.Start` is queued until the window is idle on screen. |
| 24 | `Shell.cs:460 win.ContentRendered` | Once the window has drawn, on a pool thread, `SelfSwap.cs:192 Settle()` deletes `Launcher\Thornswood.exe.old`, the copy of the previous launcher a self update keeps; that is how the update script knows this one started (see SelfSwap in section 2). A `Thornswood.exe.bad` left by a way back is deleted too, and the log says which version failed. Every start but the first after an update finds neither. |
| 25 | `Shell.cs:488 Application` | A new WPF Application with `ShutdownMode.OnMainWindowClose`, because the hidden voice window would otherwise keep the process alive. `Shell.cs:490 app.Exit` stops voice and presence and releases Hold. `Shell.cs:497 DispatcherUnhandledException` logs a fault and keeps the launcher up. `Shell.cs:504 StartStallWatch` logs when the window stops answering. |
| 26 | `Shell.cs:505 app.Run` | The message loop. Run does not return until the window closes. |
| 27 | `ShellOwnGame.cs:43 ContentRendered` | Once the window is on screen: `ShellOwnGame.cs:62 OwnGameAtStart()` refreshes the game folder by itself when Vortex has deployed since it was made (`OwnGame.cs:431 NeedsRefresh()`), or offers to make it in the shared shape. |

### Threads

There is one window thread. Anything that waits on the network or a large file
runs on a pool thread and comes back with `win.Dispatcher.BeginInvoke`. `Log`
(`Shell.cs:763 Log()`) writes a WPF control as well as `Profile\launcher.log`,
so it throws off the window's thread; code on a pool thread logs through
`PresenceLog` or `SafeLog`. A caught exception that nothing acts on goes to
`Swallow.cs:26 Note()`, one line in `launcher.log` from any thread and never a
throw. `Waiting.cs:30 Waiting()` runs one piece of work on
a pool thread while the window keeps drawing, with the controls off, and
carries on from the next line when it is done. Most of the slow steps in Play
go through it.

### The two second timer

`Shell.cs:1518 timer.Tick` runs every two seconds for the life of the window,
except in a window opened to uninstall, which stops it before it ticks.
Every fifteenth tick it pings the server. While a game is running it reads the
character choice every tick and checks for updates every fifteenth. The tick
that finds the game gone runs the whole close sequence (section 3, "When the
game closes").

## 2. What each part owns

One paragraph per class, naming the files it writes. Profile is
`<Root>\Profile`; Game is `<Root>\Game`.

**Shell** (Shell.cs, Pages.cs, ShellOwnGame.cs, ShellSteamUpdates.cs,
ShellUninstall.cs, Waiting.cs, Stall.cs). The window and every flag that
decides the Play button: `playing`, `updatePending`, `updateAnswered`, `checkFailed`,
`collectionBarUp`, `ownGameBusy`, `doorCheckOut`, `feedNotice` (the last
answer FeedNotice gave), and `chosenId`, the character picked at the game's
menu this session. Writes `Profile\launcher.log` through Log and
`Profile\played.flag` at each Play.

**Paths** (Paths.cs). Every path the launcher uses, worked out once in
`Paths.cs:39 Init()` from where the exe is. `Collection` says which shape the
install is. Owns no files.

**Config** (Config.cs). `<Root>\config.json`, read by `Config.cs:289 Load()`
and written by Save, which encrypts the update token with Windows' DPAPI and
locks the file to this Windows account. The server address, port, collection
link, voice port and update repository in it are facts about the server, not
settings: `Shell.cs:4540 OnVersionDoc()` overwrites them from version.json on
every update check.

**Updater** (Updater.cs). The update feed, the packs and the launcher's own
replacement. `Updater.cs:152 Check()` reads version.json from the releases
repository on GitHub. `Updater.cs:479 ApplyPack()` downloads a pack and
`Updater.cs:496 Install()` unpacks it: `game\...` entries into Game (hard link
names dropped first), `profile\...` entries into `Profile\Default`, the list of
what it wrote into `Profile\Packs\<pack id>.files`, the id into
`Profile\applied.txt`, and every Data\Platform file it wrote into Keep.
`Updater.cs:945 SelfUpdate()` writes `Launcher\Thornswood.exe.new` and a
script in the temp folder, `st-update-<process id>.cmd`, that swaps it in once
this process has gone and keeps the old one until the new one has started
(see SelfSwap below). `Version` at the top of the file is the launcher's
version, moved by `scripts\release\Bump-Version.ps1` before a Ship. In the launcher,
`Shell.cs:4457 CheckUpdatesBackground()` asks, `OnVersionDoc` decides,
`Shell.cs:4903 RunUpdate()` installs, and `Shell.cs:4477 CheckFailed()` keeps
Play shut and asks again every thirty seconds when the source does not answer.
Every document that was read also goes to `Shell.cs:4520 ShowNotice()`, which
asks FeedNotice what the bar above Play says and whether Play is held.

**SelfSwap** (SelfSwap.cs). The launcher's own replacement, and the way back
when the new one will not start. `SelfSwap.cs:67 Script()` is the cmd script
SelfUpdate writes. It waits for this launcher to be gone, renames
`Launcher\Thornswood.exe` to `Thornswood.exe.old`, moves the `.new` into its
place, starts it, and watches for up to five minutes. The new launcher deletes
the `.old` once its window has drawn (`SelfSwap.cs:192 Settle()`, startup step
24). A new launcher that exits with the `.old` still there did not start, so
the script moves it aside as `Thornswood.exe.bad`, puts the `.old` back and
starts that; the launcher that comes back logs which version failed and
deletes the `.bad`. It is kept apart from Updater so that
`tests\test-self-update.ps1` can compile it on its own and run the real script
against stand-in launchers.

**FeedNotice** (FeedNotice.cs). What the feed says to everybody. Three
optional fields in version.json, set by hand in the releases repository:
`message` (a bar above Play, never a hold on its own), `maintenance` (holds
Play) and `minLauncher` (holds Play in a launcher older than it).
`FeedNotice.cs:45 From()` turns a document into the bar's words and, when
Play is held, the reason and the button's words. It owns no files and holds
nothing on a check that did not answer; a value it cannot read leaves Play
open.

**Keep** (Keep.cs). Thornswood's own files under `Game\Data\Platform`, kept
pristine in `Profile\Keep` and put back before every Play by
`Keep.cs:323 Restore()`. Which files are ours is learned from the packs that
wrote them (`Keep.cs:175 Remember()`), plus the fixed `Core` list and any
plugin named `thornswood-*.js`. Any other script in
`Game\Data\Platform\Plugins` is parked in `Profile\Parked`, listed in
`Profile\Parked\parked.txt`, until `Keep.cs:406 Unpark()` puts it back. Also
writes and deletes the session note `Game\Data\Platform\thornswood-session.txt`
(`Keep.cs:474 LeaveNote()`), which the plugins read to know the session is
ours. `Profile\developer.flag` makes a newer game copy win over the kept one;
nothing writes it since 25 September, when `Go.ps1` started refreshing the kept
copies of what it installs, so the machine that ships repairs the way a
tester's does.

**Hold** (Hold.cs). Owns open file handles, not files. `Hold.cs:56 Take()`
opens every kept file and `skymp5-client-settings.txt` read only with read
sharing, so the game can read them and nothing can write, replace or delete
them. Where a parked plugin was, it stands an empty file and holds that too. A
watcher on Plugins and UI logs anything else that tries. The launcher's own
writes to a held file go through `Hold.cs:139 Around()`.
`Hold.cs:105 Release()` lets everything go.

**Swap** (Swap.cs). Where Skyrim keeps its settings and saves.
`Swap.cs:107 Apply()` moves `Documents\My Games\Skyrim Special Edition` and
`%LOCALAPPDATA%\Skyrim Special Edition` aside with `.st-backup` on the end and
puts junctions in their place pointing at `Profile\MyGames` and
`Profile\LocalAppData`, then writes `Profile\swap.json`.
`Swap.cs:40 Restore()` undoes it and is safe to call at any time, including
after a crash.
In the shared shape Apply does nothing, because Vortex owns those folders
there.

**Verify and LoadOrder** (Verify.cs, LoadOrder.cs). Whether this install's
plugin list is the server's. `Verify.cs:60 Run()` reads, and writes nothing:
the shipped reference `Profile\Default\plugins.txt`, the live list
`Profile\LocalAppData\plugins.txt`, the server's manifest over HTTP on its
resources port (3000 for the main server, 7788 for dev), and the size and
CRC of each plugin. Only the Fix button writes: the reference list into the
live one, a plugin fetched from the server (the old one kept in
`Profile\Replaced`), and other servers' files moved into `Profile\Isolated`.
`Verify.cs:750 DeployPersonal()` copies `<Root>\Your Mods` into `Game\Data`.

**Checks** (Checks.cs). The rows on the Play page (`Checks.cs:668 All()`):
game build, script extender, Address Library, multiplayer, client, mods, mod
list, other servers, auto load, Steam. A failed row shuts Play unless it is
advisory, which is drawn amber and leaves Play alone. Address Library
(`Checks.cs:64 AddressLibraryRow()`) is advisory, because a new row that
blocks and is wrong on somebody's machine locks them out with nothing they
can press. Finding and closing the game's processes
(`Checks.cs:774 GameRunning()`, `Checks.cs:873 CloseGame()`). Writes nothing
except when Fix moves a file aside.

**Door and Discord** (Door.cs, Discord.cs). Who is allowed in. The Discord
ticket lives in `Profile\discord.txt`, DPAPI encrypted and locked to this
account, with `discord-name.txt` and `dev-allowed.txt` beside it.
`Door.cs:106 Check()` asks thornswood.net at `/api/play/join` through
`Discord.cs:315 Join()`, holds a yes for five minutes, and writes the site's
last answer to `Profile\door.txt`; when the site cannot be reached, or
answers that it could not ask Discord, a yes in that file less than 72 hours
old still lets the person in. Discord.cs also
sends both ends of every session and its logs (`/api/play/start`, `/end`,
`/logs`), remembering an unsent set in `Profile\logs-pending.txt`.

**Chars, AutoJoin and Roster** (Chars.cs, AutoJoin.cs, Roster.cs). Characters.
There is no class called Creation: the person picks or makes a character at
the game's own main menu, and these three prepare that menu and read its
answer. `Chars.cs:694 Prepare()` owns `Profile\Characters\profiles.txt` (one
row per profile id, plus a spare on slot 0 for New character),
`retired.txt`, the saves folder `Profile\Characters\saves`, the menu's list
`Game\Data\Platform\thornswood-characters.json` and
`Game\Data\Platform\UI\thornswood-characters.js`, and the two files the menu
writes back, `thornswood-choice.txt` and `thornswood-forget.txt` in
`Game\Data\Platform`. AutoJoin owns what the launcher writes into
`skymp5-client-settings.txt`: the server address and port, the manifest
location, `gameData.profileId`, and `gameData.chooseAtMenu`. Roster asks the
site for this account's character names and keeps them in memory.

**Voice** (Voice.cs). Proximity voice runs in the launcher, not in the game:
a WebView2 window that is never shown, loading `voice-host.html`. At start it
writes `WebView2Loader.dll` and `voice-host.html` beside the exe and keeps the
browser's data in `Profile\VoiceBrowser`. It talks to the game through small
files in both `Game\Data\Platform` and Profile (`voice-token.txt`,
`voice-status.txt`, and push to talk and `voice-muted.txt` written by the
game, the second passed on to the voice page by
`Voice.cs:953 PassMuted()`). `Voice.cs:798 Reconfigure()` tells it which
character is being played. The join token is only asked for over https,
because the request carries the Discord ticket; with a voice address that is
not https there is no token.

**OwnGame** (OwnGame.cs, with ShellOwnGame.cs for its card and offer).
`<Root>\Game` itself. `OwnGame.cs:477 Make()` builds it in `<Root>\Game.new`
and moves it into place; `OwnGame.cs:554 Refresh()` brings it up to date with
Vortex. The records are in `Profile\OwnGame`: `files.txt` (every file, linked
or copied, and whether Vortex deployed it, which Publish-Update reads),
`made.txt`, `left-out.txt`, `declined.txt`, and Vortex's `plugins.txt` and
`loadorder.txt`. `OwnGame.cs:327 WhyNot()` names the one thing stopping the
folder being made. Every writer into Game calls `OwnGame.cs:717 Unshare()` or
Detach first, so a write never lands in Vortex's copy through a hard link.

**ClientRuntime** (ClientRuntime.cs). The six files that are the SkyMP client,
checked by SHA-256 against `records\client-build.json`, which is compiled into
the exe (`ClientRuntime.cs:179 Good()`), and put back from a pack when they
are not (`ClientRuntime.cs:206 Heal()`).

**Downgrade** (Downgrade.cs). Puts the Steam copy back on Skyrim 1.6.1170
through Steam's own console when Steam has updated it, after asking, since it
takes over Steam's window and the keyboard; the question shows the three
console lines (`Downgrade.cs:154 Commands()`). The game folder is then
refreshed from it.

**SteamUpdates** (SteamUpdates.cs, with ShellSteamUpdates.cs for its
question). Steam's Updates setting for Skyrim, `AutoUpdateBehavior` in
`steamapps\appmanifest_489830.acf` in the library that holds it.
`SteamUpdates.cs:190 Report()` reads it into the log at every start. Only
after a downgrade works does `ShellSteamUpdates.cs:22 AskToHoldSteamUpdates()`
offer to set it to wait until the game is launched, and only on Yes, with
Steam closed, does `SteamUpdates.cs:226 Hold()` change that one value. Play is
never held on it.

**The settings Play writes every time.** Enforce.cs (`SkyrimSoulsRE.ini` and
`OpenAnimationReplacer.ini`, which those mods rewrite on exit), ThornIni.cs
(`Thornswood.ini` from the template when missing), Mics.cs (the microphone
name and voice address in `Thornswood.ini`), Display.cs
(`SSEDisplayTweaks.ini`, `SkyrimPrefs.ini`, SkyUI's `config.txt`), and Keys.cs
(key binds, from the Controls page). All in Game except `SkyrimPrefs.ini`,
which is in `Profile\MyGames`.

**SkyMp** (SkyMp.cs). Whether the server answers (`SkyMp.cs:74 Up()`, a TCP
connect to the resources port), and on a machine whose address is this
machine, starting the server (`Profile\server.pid`, `Profile\server.log`).

**Presence** (Presence.cs). "Playing Thornswood" on the person's Discord
profile, over the Discord app's local pipe. No files.

**Register** (Register.cs). This install's entry in Windows' Installed apps,
under `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall`, one key per
install folder, rewritten at every start.

**Uninstall** (Uninstall.cs). Removing the install. Swap.Restore always runs
first, because deleting Profile with the junctions live would follow them
into the person's real Skyrim folders. It only ever deletes under Root, and
the last part runs from a script in the temp folder after the launcher exits.
Uninstall under Windows' Installed apps runs the exe with `-uninstall`, and
the launcher opens on Settings without starting up to play (startup step 10,
ShellUninstall.cs).

**DevBuild** (DevBuild.cs). The second launcher in `<Root>-DevBuild`, made
from the main one's files with the channel set to dev and the dev ports (game
7787, voice 7789). It has its own Profile, and makes its own `Game` folder the
same way from its own Settings, under Maintenance.

**Smaller pieces.** Stats.cs (`Profile\stats.txt`), Leaks.cs (the shipped sign
in file), Icons.cs (the shortcut icon), Firewall.cs (the rule for the game's
browser, asked for when the game folder is made), Stall.cs and Waiting.cs
(section 1), Diag.cs (`Profile\Reports`), Files.cs (saves and logs for the
pages), Secrets.cs (DPAPI and locking a file to this account), Junction.cs
(making and reading junctions without cmd), Steam.cs (finding Steam and its
Skyrim), Online.cs (the headcount the server publishes), Slots.cs (the one
rule for moving a character's slot), Art.cs (the art inside the exe),
Themes.cs, Help.cs (the Help page's text), Links.cs (the Nexus page behind
each mod name), Swallow.cs (a caught exception written to `launcher.log`
instead of dropped, section 1).

A new class gets a line on this page in the pull request that adds it.

## 3. The Play sequence

From the button to the game starting, in the order it runs, with what each
step leaves behind. The list of files at the end of it is the answer to
"what is written or locked between pressing Play and the game window
appearing".

### The gate

`Shell.cs:1775 DrawStatus()` runs on every page change, scan and recheck. It
draws a row for each check in `Checks.cs:668 All()`, and a failed row counts
against Play unless it is advisory (`Shell.cs:1783 c.Blocks`); an advisory row
that fails is drawn amber instead. The rows live in `StatusList` on the
Diagnostics page now (#607); the Play page shows a one line summary of them
(`DrawStatus.UpdateReadySummary`), and both are updated in place rather than
torn down and rebuilt, so an unchanged pass does not flash or re-say itself.
`DrawStatus.StatusRow` builds a row once and `DrawStatus.FillStatusRow` fills
it. Then it sets
`Shell.cs:1885 btnPlay.IsEnabled`, which turns the button on only when no row
counts against Play, none of
`playing`, `updatePending`, `collectionBarUp` or `ownGameBusy` is set, and the
feed does not hold Play (`feedNotice.Hold`, see FeedNotice in section 2). The
button's words say which one is holding it: PREPARING THE GAME FOLDER,
INSTALL THE MODS FIRST, CHECKING..., UPDATE FIRST, NO ANSWER FROM THE UPDATE
SOURCE, CLOSED FOR MAINTENANCE or UPDATE THE LAUNCHER (the feed's hold, with
the bar above Play saying why), DOWNGRADE FIRST, or in the shared shape MAKE
THORNSWOOD'S OWN FOLDER. `updatePending` starts true and only an answer from
the update source clears it, except in a launcher with no update source
configured at all, which is a developer's own build and never a tester's.

### Pressing it

| # | Where | What happens | Left behind |
|---|---|---|---|
| 1 | `Shell.cs:1136 btnPlay.Click` | Wired in Wire. A game this launcher already started goes to Play; otherwise StartPlay. | |
| 2 | `Shell.cs:4195 StartPlay()` | | |
| 3 | `Shell.cs:4200 OwnGameRequired` | `ShellOwnGame.cs:165 OwnGameRequired()` returns straight away in this shape. In the shared shape it offers to make the folder, or says what is in the way, and Play stops. | nothing |
| 4 | `Shell.cs:4207 Door.RecentlyCleared` | A yes from the site in the last five minutes skips the next step. | |
| 5 | `Shell.cs:4212 Door.Check` | `Door.cs:106 Check()` on a pool thread: `Discord.cs:315 Join()` posts the ticket and the profile id currently in `skymp5-client-settings.txt` to thornswood.net `/api/play/join`. A yes comes back through `Shell.cs:4226 StartPlay`, which runs StartPlay again from the top and passes this step. A no shows why (`Door.cs:200 Explain()`) and nothing more runs. | `Profile\door.txt` (the answer and when); `discord-name.txt` and `dev-allowed.txt` when they changed |
| 6 | `Shell.cs:4244 Checks.GameRunning` | A Skyrim started by hand goes straight to Play with nothing under Data touched, because a write to the client settings reloads every plugin in a running game. | |
| 7 | `Shell.cs:4255 Chars.Prepare` | Under Waiting. `Chars.cs:694 Prepare()`, below in its own table. It throws when the client settings or the character list cannot be written, and Play stops. | see below |
| 8 | `Shell.cs:4267 Chars.KnownIds` | Every profile id this install could pick, then `Shell.cs:4273 CheckIn` for each on a pool thread, posting each one to `/api/play/join` so the server's allowed list has it before the person picks. A failure is a log line; the game still starts. | |
| 9 | `Shell.cs:4278 Play` | Into `Shell.cs:3870 Play()`. Its first four lines check `updatePending`, `collectionBarUp`, `ownGameBusy` and the feed's hold again, because the button is not the only way in. | |
| 10 | `Shell.cs:3887 Paths.Loader` | `Game\skse64_loader.exe` has to exist, and `Shell.cs:3888 Paths.MpClient` (`Game\Data\SKSE\Plugins\MpClientPlugin.dll`). | |
| 11 | `Shell.cs:3893 ClearStuckGame` | A Skyrim with no window is closed; one on screen is asked about. | |
| 12 | `Shell.cs:3899 Verify.Run` | Under Waiting. Reads the plugin list, the server's manifest and the plugins' bytes. Any problem that would get the person refused: the Mods page opens with a message saying what to do, and Play stops. | nothing |
| 13 | `Shell.cs:3943 Verify.DeployPersonal` | `<Root>\Your Mods` copied into `Game\Data`, never a plugin. | those files in `Game\Data` |
| 14 | `Shell.cs:3957 Display.MatchScreen` | Skipped when Lock resolution is ticked. The game's window size and Display Tweaks' resolution follow the screen, then `Shell.cs:3959 Display.ScaleMenus`. | `Game\Data\SKSE\Plugins\SSEDisplayTweaks.ini`, `Profile\MyGames\SkyrimPrefs.ini`, `Game\Data\Interface\skyui\config.txt` and `config.shipped.txt`, each only when it changes |
| 15 | `Shell.cs:3962 Enforce.Apply` | Settings two mods rewrite on the way out, put back. | `Game\Data\SKSE\Plugins\SkyrimSoulsRE.ini`, `OpenAnimationReplacer.ini` |
| 16 | `Shell.cs:3969 AutoJoin.Apply` | `AutoJoin.cs:124 Apply()`: the server address and port, and where the client fetches the server's load order, through Hold.Around. SkyMP has no join screen; this file is the whole of joining. | `skymp5-client-settings.txt` when it changes |
| 17 | `Shell.cs:3978 ThornIni.Ensure` | The template, if the file is missing. | `Game\Data\SKSE\Plugins\Thornswood.ini` |
| 18 | `Shell.cs:3981 Mics.Apply` | This machine's microphone name, the voice port and the voice address. | `Thornswood.ini` |
| 19 | `Shell.cs:3986 EnsureServer` | `Shell.cs:3833 EnsureServer()`: `SkyMp.Up` connects to the resources port. A server elsewhere that does not answer is asked about; one on this machine is started. | `Profile\server.pid` and `server.log`, local server only |
| 20 | `Shell.cs:3993 Keep.Restore` | Last thing before the game that can still say no, so nothing is left parked by a refusal. Our Data\Platform files back from `Profile\Keep`; other servers' plugins parked. | changed files in `Game\Data\Platform`; `Profile\Parked\*` and `parked.txt` |
| 21 | `Shell.cs:3995 Keep.LeaveNote` | The note that says this session is ours. The plugins idle without it. | `Game\Data\Platform\thornswood-session.txt` |
| 22 | `Shell.cs:4001 Hold.Take` | Read only handles on every kept file and the client settings, and an empty held stand-in where each parked plugin was. | locks, and the stand-ins |
| 23 | `Shell.cs:4005 Swap.Apply` | Windows' two Skyrim folders pointed at Profile. Throws, with the folder named, when Windows will not let one go. On the next line `playing` goes true, the theme music and the video behind the title stop, the button reads RUNNING and Quit game appears. | two junctions, two `.st-backup` folders, `Profile\swap.json` |
| 24 | `Shell.cs:4023 ProcessStartInfo` | For `Game\skse64_loader.exe`, with Game as the working directory and no arguments, started at `Shell.cs:4046 Process.Start`. The loader starts `SkyrimSE.exe` beside it. Then one log line names the launcher version, the newest pack applied and the display mode. | |
| 25 | `Shell.cs:4073 Discord.NewSession` | An id for this session, then `Shell.cs:4077 Discord.SessionStart` on a pool thread posts it to `/api/play/start`. | `Profile\logs-pending.txt` |
| 26 | `Shell.cs:4084 Presence.Start` | The Discord card, on its own thread. | |
| 27 | `Shell.cs:4086 PlayedFile` | Then `Shell.cs:4088 Stats.StartedPlaying`, a pause of 1.2 seconds, and the window minimises unless Keep launcher open is ticked. | `Profile\played.flag`, `Profile\stats.txt` |

If anything in Play throws, the catch at the end of it undoes the work in
this order: `Shell.cs:4102 Swap.Restore`, `Shell.cs:4103 Hold.Release`,
`Shell.cs:4104 Keep.Unpark`, `Shell.cs:4105 Presence.Stop`,
`Shell.cs:4106 Keep.TakeNote`. A reason longer than one line is shown in a
box.

### Inside Chars.Prepare (step 7)

| Where | What happens | Left behind |
|---|---|---|
| `Chars.cs:694 Prepare()` | The saves folder Skyrim will see, `Profile\MyGames\Saves`, becomes a junction to `Profile\Characters\saves`. A real folder there with files in it is moved aside whole, never deleted. SkyrimPlatform's scaffolding saves are deleted. | `Profile\Characters\saves`, the junction, maybe `Saves-before-Thornswood-<time>` |
| `Chars.cs:766 EnsureSpare` | Mints the spare id for New character when there is none. | `Profile\Characters\profiles.txt` |
| `Chars.cs:769 AutoJoin.SetChooseAtMenu` | `AutoJoin.cs:295 SetChooseAtMenu()`: the id played last and `chooseAtMenu` inside `gameData`, read back, and a throw if the file does not say what was written. | `skymp5-client-settings.txt` |
| `Chars.cs:771 WriteStartIni` | Start On Save told to load nothing. | `Game\Data\SKSE\Plugins\po3_StartOnSave.ini` |
| `Chars.cs:772 WriteBrowserBackend` | Which in-game browser SkyrimPlatform uses, then `Chars.cs:773 KeepPlatformLogReadable` stops its log being switched off. Edited, never rewritten, and only when a value changes. | `Game\Data\SKSE\Plugins\SkyrimPlatform.ini` |
| `Chars.cs:778 Voice.Reconfigure` | Voice fetches a token for that id, when the voice address is https. | `voice-token.txt` in `Game\Data\Platform` and Profile |
| `Chars.cs:800 TidySlots` | Only on the site's own answer about how many slots this account has. | `profiles.txt` when a slot moves |
| `Chars.cs:802 WriteCharacters` | Names from the site's roster, then the list the menu draws. Throws when it cannot be written. | `Game\Data\Platform\thornswood-characters.json`, `Game\Data\Platform\UI\thornswood-characters.js` |
| `Chars.cs:806 ChoiceFile` | Last session's choice and forget files deleted, so neither is read as this session's. | |

### What is on disk when the game window appears

Written or rewritten, when anything needed changing:

- `Profile`: `door.txt`, `Characters\profiles.txt`, `Characters\saves`,
  `MyGames\Saves` (a junction), `MyGames\SkyrimPrefs.ini`, `Parked\` and
  `parked.txt`, `swap.json`, `logs-pending.txt`, `played.flag`, `stats.txt`,
  `voice-token.txt`, `launcher.log`, and with a local server `server.pid` and
  `server.log`.
- `Game\Data\Platform`: `Plugins\skymp5-client-settings.txt`, any kept file
  put back, `thornswood-session.txt`, `thornswood-characters.json`,
  `UI\thornswood-characters.js`, `voice-token.txt`.
- `Game\Data\SKSE\Plugins`: `po3_StartOnSave.ini`, `SkyrimPlatform.ini`,
  `SSEDisplayTweaks.ini`, `SkyrimSoulsRE.ini`, `OpenAnimationReplacer.ini`,
  `Thornswood.ini`.
- `Game\Data\Interface\skyui\config.txt` and `config.shipped.txt`, and
  anything from `<Root>\Your Mods`.
- Windows' `Documents\My Games\Skyrim Special Edition` and
  `%LOCALAPPDATA%\Skyrim Special Edition` are junctions into Profile, with the
  real folders beside them as `.st-backup`.

Deleted: `Game\Data\Platform\thornswood-choice.txt` and `thornswood-forget.txt`.

Locked read only until the game closes: every file in `Game\Data\Platform`
that has a kept copy in `Profile\Keep`, `skymp5-client-settings.txt`, and the
empty stand-ins where parked plugins were.

### While the game runs

`Shell.cs:1518 timer.Tick` keeps going. `Shell.cs:1529 PollChoice` reads
`Game\Data\Platform\thornswood-choice.txt`, which the menu plugin writes when
the person picks (`Chars.cs:476 ReadChoice()`); a new id is written into
`profiles.txt` (`Chars.cs:501 Chose()`), handed to voice and checked in with
the site. Nothing in this loop writes the client settings: a write to that
file reloads every plugin in the running game.
`Shell.cs:1534 CheckUpdatesInPlay` looks for a release every thirty seconds
and, four and a half minutes after first seeing one, closes the game so it can
be installed, landing on the server's own five minute warning.

### When the game closes

The first tick that finds no game runs, in order:
`Shell.cs:1549 Presence.Stop`, `Shell.cs:1550 Hold.Release`,
`Shell.cs:1551 Keep.TakeNote` (the session note goes),
`Shell.cs:1552 Swap.Restore` (Windows' folders back, `swap.json` gone),
`Shell.cs:1554 Keep.Unpark` (parked plugins home, or into `Profile\Isolated`
when their launcher has already written a new copy),
`Shell.cs:1557 Stats.StoppedPlaying`, then on a pool thread
`Shell.cs:1568 Discord.SessionEnd` and `Shell.cs:1575 Discord.SessionLogs`
(the session's logs up to the site before the next start truncates them),
`Shell.cs:1583 Chars.AddPlaytime`, `Shell.cs:1592 Checks.LastRunFrom` (a
warning if that session ran some other Skyrim), and `Shell.cs:1605 Verify.Run`
on a pool thread. A game closed for an update then fetches and installs it
(`Shell.cs:1640 CheckUpdatesBackground`).

### Closing the launcher

`Shell.cs:1497 win.Closing` asks first when a game is still running, then
runs Swap.Restore, Hold.Release and, when no game is running, Keep.Unpark.

## 4. The six shared files

CLAUDE.md asks for a line in #staff-general before any of these is edited, because both
machines work in them.

| File | What it is | Why both machines are in it |
|---|---|---|
| `launcher\app\Shell.cs` | The window, startup and the whole Play sequence. | Nearly every change that adds a button or a step touches it. |
| `launcher\app\Checks.cs` | The rows that gate Play, and finding and closing the game. | A new requirement for Play is a new row here. |
| `launcher\app\Keep.cs` | Our Data\Platform files put back and other plugins parked. | Anything new the plugins ship under Data\Platform, and how the main and dev builds share a game. |
| `launcher\app\Hold.cs` | The read-only hold while the game runs. | It holds exactly what Keep keeps, so they change together. |
| `launcher\app\Updater.cs` | The feed, the packs, the self update, and `Version`. | Every release moves `Version`, from whichever machine ran Bump-Version. |
| `scripts\release\Publish-Update.ps1` | Diffs the build, packs what belongs by Ship-Rules.ps1, uploads, writes version.json. | Ship runs it on whichever machine ships: main from Patrick's, dev from either. |
