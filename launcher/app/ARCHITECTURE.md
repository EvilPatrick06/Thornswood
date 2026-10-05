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
program rewrites in place as copies. It takes three kinds of file and nothing
else (#1232): Skyrim's own, by the pinned build's list, Vortex's, by Vortex's
record, and Thornswood's own, by its records; a mod the person put into the
Steam copy by hand stays there. In this shape `Paths.Collection` is false
and `Paths.Game` is `<Root>\Game`.

The older shared shape, where there is no `<Root>\Game` and the game would run
out of the Steam copy (`Paths.Collection` true), is still in the code for one
reason: so the launcher can recognise it and refuse to Play from it (step 3
below). Where a step behaves differently in that shape, the page says so in
one line. Nothing here describes it as something to run, and the two shapes
must never be mixed in one release.

Until the folder is made there are two ways in (#1226), chosen in the setup
window. With Thornswood's own folder ticked, Setup-Thornswood.ps1 puts its
payload in `Profile\Payload` and writes nothing into the Steam copy;
`Paths.OwnFirst` is true and `Paths.Game` is `Profile\Payload`, so every writer
below lands there, and Make takes it into `<Root>\Game` and removes it. Not
ticked, the payload goes into the Steam copy with `Profile\installed-into-game.txt`
and `Paths.Game` is the Steam copy, as it always was; once the folder is made,
the next start takes Thornswood's files back out of the Steam copy, once
(`OwnGameClean.cs CleanSteamCopy()`).

`<Root>` is the install folder and `Profile` means `<Root>\Profile`. Every file
named below is in `launcher\app` unless the path says otherwise.

## Reading the references, and keeping them true

A reference looks like `Shell.cs:5105 Play()`: the file, the line, and the
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
`Shell.cs:315 XamlReader.Parse`. The xaml carries no `x:Class` and no event
handlers. So:

- `Shell.cs:689 Bind()` finds each named control with `win.FindName` (the
  helper `F<T>` just above it) and keeps it in a static field.
- `Shell.cs:2078 Wire()` attaches every handler in code.
- `Shell` is therefore a static class, not a `Window` subclass, and it is
  split across eight files: Shell.cs, Pages.cs (the read-only pages),
  ShellOwnGame.cs (the game folder card and offer), ShellSteamUpdates.cs (the
  question about Steam's Updates setting at the start), ShellUninstall.cs
  (the launcher as Windows' Uninstall button opens it), ShellProgress.cs (the
  Play button as a progress bar), Waiting.cs and Stall.cs.

A control renamed in ui.xaml is not a compile error. `F<T>` returns null and
the first unguarded use of it throws, which at startup lands in Main's catch
and shows "Thornswood could not start".

### The startup order

In the order Run takes it. Everything happens on the window's thread unless
it says a pool thread.

| # | Where | What it does and what it leaves behind |
|---|---|---|
| 1 | `Shell.cs:192 Main()` | Takes a mutex named for this install folder (`Shell.cs:264 MutexName()`), so the main and dev builds can both be open. A second copy of the same build says so and exits. Anything thrown out of Run is appended to `Profile\launcher.log` as COULD NOT START and shown in a box. |
| 2 | `Shell.cs:289 Run()` | Reads `-root` and `-uninstall` off the command line. |
| 3 | `Shell.cs:297 Paths.Init` | `Paths.cs:71 Init()` works out Root, Game and every Profile path, once. Nothing recomputes them, which is why making the game folder restarts the launcher. |
| 4 | `Shell.cs:304 Config.Load` | Reads `<Root>\config.json` (`Config.cs:333 Load()`). Then `Stats.Load` reads `Profile\stats.txt`. |
| 5 | `Shell.cs:315 XamlReader.Parse` | Builds the window from the embedded ui.xaml. |
| 6 | `Shell.cs:317 Bind` | Finds the controls, and sets `Discord.Folder` to Profile. |
| 7 | `Shell.cs:318 Themes.Apply` | Colours from config.json's theme. |
| 8 | `Shell.cs:319 Wire` | Attaches every handler, including the Play button, calls `WirePages` and `WireOwnGame`, and starts the two second timer (`Shell.cs:2542 DispatcherTimer`). |
| 9 | `Shell.cs:320 BuildThemeRow` | Then `Shell.cs:322 BuildDisplay`, `Shell.cs:324 BuildStatRow`, `Shell.cs:325 BuildPathRows` and `Shell.cs:326 BuildHelp`: the theme buttons and display rows on Settings, the strip of figures from `Profile\stats.txt` (time played, sessions, last played, last update), the install and game folder rows, and the Help page. They draw controls and write nothing. |
| 10 | `Shell.cs:332 OpenForUninstall` | Only when Windows sent `-uninstall`, which is what Uninstall under Installed apps runs. `ShellUninstall.cs:49 OpenForUninstall()` stops the two second timer before it has ticked, stands down the game folder check, opens on Settings with the Uninstall button in view, and runs the message loop itself. Run returns from here, so no row below this one happens: no update check, no server scan, no client repair, no voice, and the Installed apps entry is not written again. |
| 11 | `Shell.cs:334 BuildModList` | The Mods page's list, then `Shell.cs:335 RefreshDiscord` (the Discord card) and `Shell.cs:339 ShowPage`, which opens on Play. |
| 12 | `Shell.cs:344 Register.Ensure` | Writes this install's entry under `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall` (`Register.cs:78 Ensure()`). |
| 13 | `Shell.cs:357 Discord.SendPendingLogs` | Pool thread. A session that ended without sending its logs (`Profile\logs-pending.txt` still there) sends them now, before a new game start truncates them. |
| 14 | `Shell.cs:363 AutoJoin.Ensure` | Makes `Game\Data\Platform\Plugins\skymp5-client-settings.txt` when there is none (`AutoJoin.cs:52 Ensure()`). |
| 15 | `Shell.cs:372 Checks.GameRunning` | A game still running from before the launcher was restarted is taken over: `Shell.cs:382 Hold.Take` holds our files again and nothing is pulled apart under it. Otherwise `Shell.cs:387 Swap.Restore` takes off any redirect a crash left and `Shell.cs:388 Keep.TakeNote` deletes a stale session note. |
| 16 | `Shell.cs:390 Leaks.Clean` | Deletes the one sign in file a 16 Sep installer shipped, matched by hash. Then `Shell.cs:399 ThornIni.Ensure` writes `Game\Data\SKSE\Plugins\Thornswood.ini` from the template if it is missing, and `Shell.cs:400 ThornIni.UndoShippedFov` runs once per install. A pool thread runs `OwnGame.CleanSteamCopy`, which once the folder is made takes Thornswood's files out of the Steam copy, once, and removes a leftover `Profile\Payload`. Before the folder exists and when no downgrade is needed (`SteamUpdates.LooksAtStart`), `HoldSteamUpdatesOnStart` logs Steam's Updates setting for the Steam copy of Skyrim and sets it when it does not hold the version (see SteamUpdates below). |
| 17 | `Shell.cs:404 Keep.Unpark` | Puts back plugins a crashed session left parked. Then `Shell.cs:408 Keep.Seed` fills `Profile\Keep` from pack records for files it has no copy of yet. |
| 18 | `Shell.cs:417 Display.MatchScreen` | Unless Lock resolution is ticked: the game's resolution and menu scale follow the screen (`Shell.cs:423 Display.ScaleMenus`). |
| 19 | `Shell.cs:437 Icons.Ensure` | Pool thread. The shortcut icon follows the exe. `Shell.cs:454 ClearLeftovers` (pool) ends a windowless Skyrim over three minutes old. `Shell.cs:468 Uninstall.DropScratch` (pool) deletes the installer's leftover `Thornswood-setup` folder. |
| 20 | `Shell.cs:484 RunScan` | `Verify.Run` against the server's manifest, then the Mods card. Then DrawStatus fills the checklist (on Diagnostics since #607), the Play summary and the button (see "The gate" below). |
| 21 | `Shell.cs:490 HealClientBackground` | Pool thread, only when the six client runtime files are not the recorded build: `ClientRuntime.cs:206 Heal()` fetches them. Then `Shell.cs:491 AutoDisplayOnce` marks `config.json` so it never runs again and, on an install that has never played, matches the game's resolution to the screen; `Shell.cs:492 StartPing` asks whether the server is up. |
| 22 | `Shell.cs:496 CheckUpdatesBackground` | Pool thread: the update check (see Updater in section 2). Always: config.json cannot switch it off, and Play stays shut until it answers (#937). |
| 23 | `Shell.cs:512 Voice.Prepare` | Installs the resolver that loads WebView2 out of the exe. `Shell.cs:520 Voice.Start` is queued until the window is idle on screen. |
| 24 | `Shell.cs:529 win.ContentRendered` | Once the window has drawn, on a pool thread, `SelfSwap.cs:192 Settle()` deletes `Launcher\Thornswood.exe.old`, the copy of the previous launcher a self update keeps; that is how the update script knows this one started (see SelfSwap in section 2). A `Thornswood.exe.bad` left by a way back is deleted too, and the log says which version failed. Every start but the first after an update finds neither. |
| 25 | `Shell.cs:571 Application` | A new WPF Application with `ShutdownMode.OnMainWindowClose`, because the hidden voice window would otherwise keep the process alive. `Shell.cs:573 app.Exit` stops voice and presence and releases Hold. `Shell.cs:580 DispatcherUnhandledException` logs a fault and keeps the launcher up. `Shell.cs:618 StartStallWatch` logs when the window stops answering. |
| 26 | `Shell.cs:643 app.Run` | The message loop. Run does not return until the window closes. |
| 27 | `ShellOwnGame.cs:46 ContentRendered` | Once the window is on screen: `ShellOwnGame.cs:65 OwnGameAtStart()` refreshes the game folder by itself when Vortex has deployed since it was made (`OwnGame.cs:662 NeedsRefresh()`), or offers to make it in the shared shape. Play also asks that same test now, through `OwnGameRefreshIfDue`. |

An install made before the terms lock has no Profile\accepted.json. Run asks
before it reads config, unless it was started to uninstall, and returns
without opening when the three boxes are not ticked. A record already on disk
is checked again from a pool thread once the window can show the same boxes,
and declining that change closes the launcher.

### Threads

There is one window thread. Anything that waits on the network or a large file
runs on a pool thread and comes back with `win.Dispatcher.BeginInvoke`. `Log`
(`Shell.cs:1054 Log()`) writes a WPF control as well as `Profile\launcher.log`,
so it throws off the window's thread; code on a pool thread logs through
`PresenceLog` or `SafeLog`. A caught exception that nothing acts on goes to
`Swallow.cs:26 Note()`, one line in `launcher.log` from any thread and never a
throw. `Waiting.cs:30 Waiting()` runs one piece of work on
a pool thread while the window keeps drawing, with the controls off, and
carries on from the next line when it is done. Most of the slow steps in Play
go through it.

### The two second timer

`Shell.cs:2544 timer.Tick` runs every two seconds for the life of the window,
except in a window opened to uninstall, which stops it before it ticks.
Every fifteenth tick it pings the server. While a game is running it reads the
character choice every tick and checks for updates every fifteenth. The tick
that finds the game gone runs the whole close sequence (section 3, "When the
game closes").

## 2. What each part owns

One paragraph per class, naming the files it writes. Profile is
`<Root>\Profile`; Game is `<Root>\Game`.

**Shell** (Shell.cs, Pages.cs, ShellOwnGame.cs, ShellSteamUpdates.cs,
ShellUninstall.cs, ShellProgress.cs, ShellNews.cs, ShellPacks.cs, Waiting.cs, Stall.cs). The window and every flag that
decides the Play button: `playing`, `updatePending`, `updateAnswered`, `checkFailed`,
`collectionBarUp`, `ownGameBusy`, `doorCheckOut`, `feedNotice` (the last
answer FeedNotice gave), and `chosenId`, the character picked at the game's
menu this session. Writes `Profile\launcher.log` through Log and
`Profile\played.flag` at each Play.

**Paths** (Paths.cs). Every path the launcher uses, worked out once in
`Paths.cs:71 Init()` from where the exe is. `Collection` says which shape the
install is; `OwnFirst` that its own folder was chosen at install and is not
made yet, when `Game` is `Profile\Payload` (#1226); `SteamCopy` is the Steam
copy, read for the game's build before the folder exists. Owns no files.

**Acceptance** (Acceptance.cs). `Profile\accepted.json`, the same file the
setup program writes when the terms, the privacy policy and the rules are
ticked. `Acceptance.cs:108 Ensure()` asks when that file has no complete
record, which is an install made before the lock, and writes that file only
after all three are ticked. `Acceptance.cs:119 Recheck()` asks again when a
page's hash is no longer the one in the file, and writes the file again only
after the three are ticked.

**Config** (Config.cs). `<Root>\config.json`, read by `Config.cs:333 Load()`
and written by Save, which encrypts the update token with Windows' DPAPI and
locks the file to this Windows account. The server address, port, collection
link, voice port and update repository in it are facts about the server, not
settings: `ShellUpdate.cs:97 OnVersionDoc()` overwrites them from version.json on
every update check. So is the Skyrim build pin (the exe size the checks look
for and the depots the Downgrade button asks Steam for), taken through
`Downgrade.AdoptPin()` when the feed carries it; the numbers compiled into
Downgrade.cs are the fallback until it does.

**Updater** (Updater.cs). The update feed, the packs and the launcher's own
replacement. `Updater.cs:228 Check()` reads version.json from the site feed
on thornswood.net, asking with the ETag of the copy it keeps in
`Profile\feed-cache.txt` so an unchanged feed answers 304, and falls back to
the releases repository on GitHub. `Updater.cs:733 ApplyPack()` downloads a pack and
`Updater.cs:752 Install()` unpacks it: `game\...` entries into Game (hard link
names dropped first), `profile\...` entries into `Profile\Default`, the list of
what it wrote into `Profile\Packs\<pack id>.files`, the id into
`Profile\applied.txt`, and every Data\Platform file it wrote into Keep.
Since #1050, when the feed names a release record whose files are on the site
(`:record:files`), `Pending()` offers that release as one update instead of
its packs, and `ApplyPack()` hands it to `SyncRecord()` in Sync.cs: the record
is read, every file of ours is compared with it by size and sha256, only the
ones that differ are fetched from beside the record (resumed with a Range
request, each checked against its sha256) into `Profile\Sync`, then put in
place, the plugin list settled, what the record says is gone taken out, and
the release written into `Profile\release.txt` (docs\FEED.md, "Syncing to the
release record").
`Updater.cs:1177 SelfUpdate()` writes `Launcher\Thornswood.exe.new` and a
script in the temp folder, `thornswood-update-<process id>.cmd`, that swaps it in once
this process has gone and keeps the old one until the new one has started
(see SelfSwap below). `Version` at the top of the file is the launcher's
version, moved by `scripts\release\Bump-Version.ps1` before a Ship. In the launcher,
`ShellUpdate.cs:28 CheckUpdatesBackground()` asks, `OnVersionDoc` decides,
`ShellUpdate.cs:367 RunUpdate()` installs, and `ShellUpdate.cs:48 CheckFailed()` keeps
Play shut and asks again every thirty seconds when the source does not answer.
Every document that was read also goes to `ShellUpdate.cs:77 ShowNotice()`, which
asks FeedNotice what the bar above Play says and whether Play is held.

**PlayProgress and PlayBar** (Progress.cs, painted by ShellProgress.cs).
The Play button as a progress bar (#1145). RunUpdate, the client repair and
StartOwnGame open it with `PlayProgress.Begin` and close it with `End`; in
between, `Updater.Download` reports the bytes of each download, Sync the files
it checks and the bytes it fetches, OwnGame.Make and Refresh the files they
bring over, and Verify.Bytes the plugins it checks. A report with nothing open
is dropped, so the same code run by Fix or a Scan leaves the button alone.
`PlayBar` turns the reports into the words and the fill, never backwards
within a phase, and a band that slides while the total is unknown;
ShellProgress.cs redraws it at most every `PlayBar.DrawEveryMs`. It writes
nothing. `tests\test-play-progress.ps1` compiles Progress.cs and drives it.

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

**Signature** (Signature.cs). Whether a downloaded launcher is really ours,
asked by CheckSigner in Updater before the `.new` is written (issue
#912). `Signature.cs:101 Refusal()` has Windows verify the signature and its
chain (WinVerifyTrust, the call behind Get-AuthenticodeSignature's Valid),
takes the chain Windows built from `Signature.cs:294 Trust()`, and then pins
Microsoft's Artifact Signing: the root, an "ID Verified CS" issuer, a
timestamp, and Thornswood's durable identity value in the certificate, which
stays the same when the three day certificate renews. Only then does it look
for `ExpectedSigner` in the Subject. `scripts\release\Assert-PublishSigned.ps1`
runs the same class before a Ship publishes, and
`tests\test-signer-check.ps1` compiles it on its own and points it at signed,
unsigned, self-signed and changed files. `Signature.cs:403 MicrosoftRefusal()`
asks the same of a program Microsoft signed itself, the WebView2 installer
Voice downloads (issue #1330): the same Windows check, then the chain must end
at Microsoft Root Certificate Authority 2011 and the certificate must be
Microsoft Corporation's, for signing programs.

**FeedNotice** (FeedNotice.cs). What the feed says to everybody. Three
optional fields in version.json, set by hand in the releases repository:
`message` (a bar above Play, never a hold on its own), `maintenance` (holds
Play) and `minLauncher` (holds Play in a launcher older than it; since #937
Publish-Update writes it on every publish as the launcher the feed offers, and
the site refuses a join pass below it).
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

**Hold** (Hold.cs). Owns open file handles, not files. `Hold.cs:63 Take()`
opens every kept file and `skymp5-client-settings.txt` read only with read
sharing, so the game can read them and nothing can write, replace or delete
them. Where a parked plugin was, it stands an empty file and holds that too. A
watcher on Plugins and UI logs anything else that tries. The launcher's own
writes to a held file go through `Hold.cs:146 Around()`.
`Hold.cs:112 Release()` lets everything go.

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
plugin list is the server's. `Verify.cs:74 Run()` reads, and writes nothing:
the shipped reference `Profile\Default\plugins.txt`, the live list
`Profile\LocalAppData\plugins.txt`, the server's manifest over HTTP on its
resources port (3000 for the main server, 7788 for dev), and the size and
CRC of each plugin. Only the Fix button writes: the reference list into the
live one, a plugin fetched from the server (the old one kept in
`Profile\Replaced`), and other servers' files moved into `Profile\Isolated`.
`Verify.cs:968 DeployPersonal()` copies `<Root>\Your Mods` into `Game\Data`.

**Vortex profile state** (VortexProfileState.cs). Checks and the PowerShell
load-order scripts share this reader for the named Skyrim profile. It reads
the current LevelDB manifest, compressed tables and sequenced log records
without opening or writing the database. Deleted, ambiguous, corrupt or
incomplete profile metadata is refused. Finish deployment and close Vortex
before a bake or Ship so its exclusively held database can be read.

**Checks** (Checks.cs). The rows on the Play page (`Checks.cs:1105 All()`):
game build, script extender, Address Library, multiplayer, client, mods, mod
list, other servers, auto load, Steam. A failed row shuts Play unless it is
advisory, which is drawn amber and leaves Play alone. Address Library
(`Checks.cs:51 AddressLibraryRow()`) is advisory, because a new row that
blocks and is wrong on somebody's machine locks them out with nothing they
can press. Finding and closing the game's processes
(`Checks.cs:1284 GameRunning()`, `Checks.cs:1433 CloseGame()`). Writes nothing
except when Fix moves a file aside.

**Door and Discord** (Door.cs, Discord.cs). Who is allowed in. The Discord
ticket lives in `Profile\discord.txt`, DPAPI encrypted and locked to this
account, with `discord-name.txt` and `dev-allowed.txt` beside it.
`Door.cs:106 Check()` asks thornswood.net at `/api/play/join` through
`Discord.cs:436 Join()`, holds a yes for five minutes, and writes the site's
last answer to `Profile\door.txt`; when the site cannot be reached, or
answers that it could not ask Discord, a yes in that file less than 72 hours
old still lets the person in. Discord.cs also
sends both ends of every session and its logs (`/api/play/start`, `/end`,
`/logs`), remembering an unsent set in `Profile\logs-pending.txt`.

**Chars, AutoJoin and Roster** (Chars.cs, AutoJoin.cs, Roster.cs). Characters.
There is no class called Creation: the person picks or makes a character at
the game's own main menu, and these three prepare that menu and read its
answer. `Chars.cs:829 Prepare()` owns `Profile\Characters\profiles.txt` (one
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
files in both `Game\Data\Platform` and Profile (`voice-status.txt`, and push
to talk and `voice-muted.txt` written by the game, the second passed on to the
voice page by `Voice.cs:1116 PassMuted()`). `Voice.cs:922 Reconfigure()` tells
it which character is being played. A join token opens one connection and is
good for two minutes (#1322), so nothing keeps one: the voice page asks for a
token before every try (`PageToken()`), and the game's chat asks by writing
`voice-token-ask.txt`, which `PassTokenAsk()` answers by writing a token for
that character to `voice-token.txt`. Both files are emptied when the file
channel starts. The join token is only asked for over https, because the
request carries the Discord ticket; with a voice address that is not https
there is no token. With no WebView2 runtime on the machine,
`Voice.cs:445 Bootstrap()` downloads Microsoft's installer and runs it only
when `Signature.MicrosoftRefusal` says Microsoft signed it (#1330).

**OwnGame** (OwnGame.cs, OwnGameShare.cs, OwnGameKinds.cs and OwnGameClean.cs, with
ShellOwnGame.cs for its card and offer). `<Root>\Game` itself. `OwnGame.cs:692 Make()` builds it in
`<Root>\Game.new` and moves it into place; `OwnGame.cs:815 Refresh()` brings it
up to date with Vortex. Once made, the folder needs nothing from the Steam copy
(#1218): a refresh takes only the files Vortex's record lists, the game's own
files are the folder's own copies, and nothing writes into the Steam copy, so
it can be on any build and modded freely. Skyrim's archives are shared with the
Steam copy only while the bytes are the same (`OwnGameShare.cs:246 Share()`),
and checked before every Play (`OwnGameShare.cs:354 CheckShared()`).
Only three kinds of file go in (#1232, OwnGameKinds.cs): Skyrim's own, which
is a file on the pinned build's list (`records\skyrim-files.json`, read out of
the depot manifests the Downgrade asks Steam for and compiled into the
launcher), Vortex's by its record, and Thornswood's own by its records (packs,
Keep, the installer's list, Payload, the files it writes by name, and the game
files of the release the install synced to, `Profile\release-files.txt`, which
Sync.cs keeps). Make leaves anything else in the Steam copy out, and a refresh
takes it out of a folder made before this, logged, without touching the Steam
copy; on an install an older launcher synced, nothing is taken out until the
check against its release has kept that list (`made.txt` kinds=1 once sorted).
The records are in `Profile\OwnGame`: `files.txt` (every file, linked
or copied, and which kind it is, V Vortex's, O Skyrim's own, T Thornswood's;
Publish-Update reads the V lines), `installed-kept.txt` (the installer's list,
kept by the clean up before it empties it), `generated.txt` (what
`scripts\mods\Build-Generated.ps1` made in the folder on the machine that
ships, the behavior files Pandora makes and the BodySlide bodies, #1247: Thornswood's
own, kept as made by a refresh even where Vortex deploys a file of the same
name (`Owned`), and forgotten when the folder is made anew),
`shared.txt`, `differs.txt` and `changed.txt` (the archives, OwnGameShare.cs),
`made.txt`, `left-out.txt`, `declined.txt`, and Vortex's `plugins.txt` and
`loadorder.txt`. `OwnGame.cs:361 WhyNot()` names the one thing stopping the
folder being made. Every writer into Game calls `OwnGame.cs:1375 Unshare()` or
Detach first, so a write never lands in Vortex's copy through a hard link.
Make takes `Profile\Payload` in too, Thornswood's own files when the folder was
chosen at install, and removes it (#1226). `OwnGameClean.cs CleanSteamCopy()`
runs at every start and, the first time it finds the folder made, takes
Thornswood's files out of the Steam copy: the installer's list and what packs
added to it, Thornswood.ini and the thornswood- files under Data\Platform, and
at paths other SkyMP servers write too (the client runtime, the client's page)
only a file whose bytes are Thornswood's. Nothing Vortex deployed, nothing of
Skyrim's own, the person's own mods and the client's shared settings file
stay. It notes what it did in `Profile\OwnGame\steam-copy-cleaned.txt` and
never runs again; a file it could not delete keeps it running at each start.

**ClientRuntime** (ClientRuntime.cs). The six files that are the SkyMP client,
checked by SHA-256 against `records\client-build.json`, which is compiled into
the exe (`ClientRuntime.cs:179 Good()`), and put back from a pack when they
are not (`ClientRuntime.cs:206 Heal()`).

**Downgrade** (Downgrade.cs). Gets Skyrim 1.6.1170's own files through
Steam's own console, after asking, since it takes over Steam's window and the
keyboard; the question shows the three console lines
(`Downgrade.cs:215 Commands()`). They go into Thornswood's own folder
(`OwnGameShare.cs:451 TakePinned()`), or, before it has one, the folder is
made from them. The Steam copy is never written (#1218).

**SteamUpdates** (SteamUpdates.cs, with ShellSteamUpdates.cs for its
question). Steam's Updates setting for Skyrim, `AutoUpdateBehavior` in
`steamapps\appmanifest_489830.acf` in the library that holds it.
At every start `ShellSteamUpdates.cs:26 HoldSteamUpdatesOnStart()` logs it
(`SteamUpdates.cs:262 Report()`) and, when it is not "Wait until I launch the
game" or the file is marked read only, sets it (#493): `SteamUpdates.cs:328
OnStart()` says write it at once when Steam is closed, or put
`ShellSteamUpdates.cs:61 AskToHoldSteamUpdates()`, whose Yes closes Steam,
waits for it to go, writes and starts Steam again. A No is remembered in
config.json (`SteamUpdatesDeclined`). `SteamUpdates.cs:426 Hold()` changes that one value,
takes off a read-only mark and never writes while Steam runs. The mark is not
what holds the version: Thornswood runs its own folder, whose exe is its own
copy, and Steam puts an update in by moving new files into its own copy. Since
#1218 a made folder does not read the Steam copy's game at all, so an update
costs it nothing; the setting only saves a download before the folder is
made, so it is only looked at until then (`SteamUpdates.LooksAtStart`, #1226):
once the folder exists the Steam copy is the person's to update as they like.
The question no longer follows a downgrade, which never writes the Steam
copy now.
Play is never held on it.

**The settings Play writes every time.** Enforce.cs (`SkyrimSoulsRE.ini` and
`OpenAnimationReplacer.ini`, which those mods rewrite on exit; `SkyrimPlatform.ini`'s
log level and text window; the actor draw distance in `SkyrimPrefs.ini`), ThornIni.cs
(`Thornswood.ini` from the template when missing), Mics.cs (the microphone
name and voice address in `Thornswood.ini`), Display.cs
(`SSEDisplayTweaks.ini`, `SkyrimPrefs.ini`, SkyUI's `config.txt`), and Keys.cs
(key binds, from the Controls page). All in Game except `SkyrimPrefs.ini`,
which is in `Profile\MyGames`. CrashDump.cs (#1191) writes Crash Logger's
own `Crash Log Write Minidump` in `CrashLogger.ini`: on for the dev build
and for a linked account the site says is staff (the `dev` answer of
`/api/play/join`, `dev-allowed.txt`), off for everybody else. The snapshot
it turns on is the game's whole memory, about 1 GB, written beside the
crash log in `Profile\MyGames\SKSE`; only the newest is kept, and nothing
ever sends one anywhere.

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
7787, voice 7789). It is installed and opened from the Server card on the main
build's Play page (`Shell.cs DrawServerPick()`, `SwitchToDev()`), which checks
the person's Discord roles before it offers the install (#605); `MainRoot` and
`MainExe` are the way back the dev build's own Server card opens the main
launcher. It has its own Profile, and makes its own `Game` folder the same way
from its own Settings, under Maintenance.

**Smaller pieces.** Stats.cs (`Profile\stats.txt`), Leaks.cs (the shipped sign
in file), Icons.cs (the shortcut icon), BrowserArgs.cs (switches for the
launcher's WebView2 browsers, such as no mDNS in the voice browser), Stall.cs and Waiting.cs
(section 1), Diag.cs (`Profile\Reports`), Files.cs (saves and logs for the
pages), Secrets.cs (DPAPI and locking a file to this account), Junction.cs
(making and reading junctions without cmd), Steam.cs (finding Steam and its
Skyrim), Online.cs (the headcount the server publishes), Slots.cs (the one
rule for moving a character's slot), Art.cs (the art inside the exe),
Themes.cs, Help.cs (the Help page's text), Links.cs (the Nexus page behind
each mod name), Gallery.cs (the pictures the site shows from the world, read
from `/api/public` for Play's rotating spotlight and the Gallery page; the
Gallery page uploads via `/api/gallery/submit`, reports via
`/api/gallery/report`, and for staff Approves, Rejects and takes an approved
shot down over the same Discord ticket, with a clear message when an older
site still answers those doors 403 without why), Swallow.cs
(a caught exception written to `launcher.log` instead of dropped, section 1).

A new class gets a line on this page in the pull request that adds it.

**ChannelWait** (ChannelWait.cs). Waits for the game to write one of the named voice files, instead of opening those files ten times a second for the whole life of the launcher. When no watcher can be made it sleeps the old 100 ms, so push to talk is never slower than the poll it replaced.

**MenuMusic** (MenuMusic.cs). Plays the launcher menu theme in a hidden WebView2, because the usual WPF playback needs the Media Feature Pack and that pack is missing on the ship PC. The browser is made the first time the music is wanted and closed while the game runs.

**Watched** (Watched.cs). Remembers the processes the last full look found and asks only those, by the handle each already has, whether they are still running. A full look happens again only when all of them have gone, and that look is the same one Checks.GameRunning makes.

**WindowFit** (WindowFit.cs). Keeps a window inside the work area of the monitor it is on, at any display scale. The size and the minimum are clamped to that work area at startup and again when the window lands on a monitor with another scale. Build-Launcher.ps1 compiles this file into the setup program as well.
## 3. The Play sequence

From the button to the game starting, in the order it runs, with what each
step leaves behind. The list of files at the end of it is the answer to
"what is written or locked between pressing Play and the game window
appearing".

### The gate

`Shell.cs:2811 DrawStatus()` runs on every page change, scan and recheck. It
draws a row for each check in `Checks.cs:1105 All()`, and a failed row counts
against Play unless it is advisory (`Shell.cs:2830 c.Blocks`); an advisory row
that fails is drawn amber instead. The rows live in `StatusList` on the
Diagnostics page now (#607); the Play page shows a one line summary of them
(`DrawStatus.UpdateReadySummary`), and both are updated in place rather than
torn down and rebuilt, so an unchanged pass does not flash or re-say itself.
`DrawStatus.StatusRow` builds a row once and `DrawStatus.FillStatusRow` fills
it. Then it sets
`Shell.cs:2959 btnPlay.IsEnabled`, which turns the button on only when no row
counts against Play, none of
`playing`, `updatePending`, `collectionBarUp` or `ownGameBusy` is set, no work
is showing on the button (`playBar.Active`, see PlayProgress in section 2), and the
feed does not hold Play (`feedNotice.Hold`, see FeedNotice in section 2). The
button's words say which one is holding it: while work shows, what it is doing
and how far it has got (UPDATING 41%, 310 OF 740 MB), otherwise PREPARING THE GAME FOLDER,
INSTALL THE MODS FIRST, CHECKING..., UPDATE FIRST, NO ANSWER FROM THE UPDATE
SOURCE, CLOSED FOR MAINTENANCE or UPDATE THE LAUNCHER (the feed's hold, with
the bar above Play saying why), DOWNGRADE FIRST, or in the shared shape MAKE
THORNSWOOD'S OWN FOLDER. `updatePending` starts true and only an answer from
the update source clears it, except in a launcher with no update source
configured at all, which is a developer's own build and never a tester's.

### Pressing it

| # | Where | What happens | Left behind |
|---|---|---|---|
| 1 | `Shell.cs:2191 btnPlay.Click` | Wired in Wire. A game this launcher already started goes to Play; otherwise StartPlay. | |
| 2 | `ShellChars.cs:38 StartPlay()` | | |
| 3 | `ShellChars.cs:43 OwnGameRequired` | `ShellOwnGame.cs:255 OwnGameRequired()` returns straight away in this shape. In the shared shape it offers to make the folder, or says what is in the way, and Play stops. | nothing |
| 3b | `ShellChars.cs:46 OwnGameRefreshIfDue` | `ShellOwnGame.cs:161 OwnGameRefreshIfDue()` asks `OwnGame.NeedsRefresh` under Waiting, then reads `ownGameBusy` again, since a bring-up-to-date queued at startup can begin inside that wait. When Vortex has deployed since the folder was made, it runs the same bring-up-to-date as Diagnostics, Bring it up to date from Vortex, and Play stops for it. When that succeeds, StartPlay runs again from step 1, so one press ends in the game; when it fails, nothing more runs and the reason is shown. A folder that still does not match straight after is said and not refreshed again. When NeedsRefresh cannot be answered, a log line says so and Play goes on. | the game folder, through OwnGame.Refresh, only when due |
| 4 | `ShellChars.cs:53 Door.RecentlyCleared` | A yes from the site in the last five minutes skips the next step. | |
| 5 | `ShellChars.cs:58 Door.Check` | `Door.cs:106 Check()` on a pool thread: `Discord.cs:436 Join()` posts the ticket and the profile id currently in `skymp5-client-settings.txt` to thornswood.net `/api/play/join`. A yes comes back through `ShellChars.cs:72 StartPlay`, which runs StartPlay again from the top and passes this step. A no shows why (`Door.cs:204 Explain()`) and nothing more runs. | `Profile\door.txt` (the answer and when); `discord-name.txt` and `dev-allowed.txt` when they changed |
| 6 | `ShellChars.cs:90 Checks.GameRunning` | A Skyrim started by hand goes straight to Play with nothing under Data touched, because a write to the client settings reloads every plugin in a running game. | |
| 7 | `ShellChars.cs:101 Chars.Prepare` | Under Waiting. `Chars.cs:829 Prepare()`, below in its own table. It throws when the client settings or the character list cannot be written, and Play stops. | see below |
| 8 | `ShellChars.cs:114 Chars.KnownIds` | Every profile id this install could pick, then `ShellChars.cs:120 CheckIn` for each on a pool thread, posting each one to `/api/play/join` so the server's allowed list has it before the person picks. A failure is a log line; the game still starts. | |
| 9 | `ShellChars.cs:127 Play` | Into `Shell.cs:5105 Play()`. Its first lines check `updatePending`, `collectionBarUp`, `ownGameBusy`, `OwnGameRefreshIfDue` and the feed's hold again, because the button is not the only way in. | |
| 9b | `Shell.cs:5120 OwnGameRefreshIfDue` | Same as step 3b, for the ways in that are not the button. | |
| 10 | `Shell.cs:5123 Paths.Loader` | `Game\skse64_loader.exe` has to exist, and `Shell.cs:5124 Paths.MpClient` (`Game\Data\SKSE\Plugins\MpClientPlugin.dll`). | |
| 11 | `Shell.cs:5129 ClearStuckGame` | A Skyrim with no window is closed; one on screen is asked about. Then, under Waiting, `Shell.cs:5141 OwnGame.CheckShared`: every archive the folder shares with the Steam copy still has the bytes on record (the change time is read, and the bytes only when it moved). One that changed stops Play and brings up the Downgrade card. | `Profile\OwnGame\shared.txt` and `changed.txt`, when anything moved |
| 12 | `Shell.cs:5155 Verify.Run` | Under Waiting. Reads the plugin list, the server's manifest and the plugins' bytes. Any problem that would get the person refused: the Diagnostics page (Scan and Fix) opens with a message saying what to do, and Play stops. | nothing |
| 13 | `Shell.cs:5213 Verify.DeployPersonal` | `<Root>\Your Mods` copied into `Game\Data`, never a plugin. | those files in `Game\Data` |
| 14 | `Shell.cs:5227 Display.MatchScreen` | Skipped when Lock resolution is ticked. The game's window size and Display Tweaks' resolution follow the screen, then `Shell.cs:5229 Display.ScaleMenus`. | `Game\Data\SKSE\Plugins\SSEDisplayTweaks.ini`, `Profile\MyGames\SkyrimPrefs.ini`, `Game\Data\Interface\skyui\config.txt` and `config.shipped.txt`, each only when it changes |
| 15 | `Shell.cs:5232 Enforce.Apply` | Settings two mods rewrite on the way out, put back; SkyrimPlatform at its normal log level with no text window; one actor draw distance for everybody (#963). Then `Shell.cs:5236 CrashDump.Apply`: the full crash snapshot on for the dev build and staff, off for everybody else, and snapshots it should not keep deleted (#1191). | `Game\Data\SKSE\Plugins\SkyrimSoulsRE.ini`, `OpenAnimationReplacer.ini`, `SkyrimPlatform.ini`, `CrashLogger.ini`, `Profile\MyGames\SkyrimPrefs.ini`; old `crash-*.dmp` in `Profile\MyGames\SKSE` deleted |
| 16 | `Shell.cs:5243 AutoJoin.Apply` | `AutoJoin.cs:124 Apply()`: the server address and port, and where the client fetches the server's load order, through Hold.Around. SkyMP has no join screen; this file is the whole of joining. | `skymp5-client-settings.txt` when it changes |
| 17 | `Shell.cs:5252 ThornIni.Ensure` | The template, if the file is missing. | `Game\Data\SKSE\Plugins\Thornswood.ini` |
| 18 | `Shell.cs:5255 Mics.Apply` | This machine's microphone name, the voice port and the voice address. | `Thornswood.ini` |
| 19 | `Shell.cs:5260 EnsureServer` | `Shell.cs:5068 EnsureServer()`: `SkyMp.Up` connects to the resources port. A server elsewhere that does not answer is asked about; one on this machine is started. | `Profile\server.pid` and `server.log`, local server only |
| 20 | `Shell.cs:5267 Keep.Restore` | Last thing before the game that can still say no, so nothing is left parked by a refusal. Our Data\Platform files back from `Profile\Keep`; other servers' plugins parked. | changed files in `Game\Data\Platform`; `Profile\Parked\*` and `parked.txt` |
| 21 | `Shell.cs:5269 Keep.LeaveNote` | The note that says this session is ours. The plugins idle without it. | `Game\Data\Platform\thornswood-session.txt` |
| 22 | `Shell.cs:5275 Hold.Take` | Read only handles on every kept file and the client settings, and an empty held stand-in where each parked plugin was. | locks, and the stand-ins |
| 23 | `Shell.cs:5279 Swap.Apply` | Windows' two Skyrim folders pointed at Profile. Throws, with the folder named, when Windows will not let one go. On the next line `playing` goes true, the theme music and the video behind the title stop, the button reads RUNNING and Quit game appears. | two junctions, two `.st-backup` folders, `Profile\swap.json` |
| 24 | `Shell.cs:5298 ProcessStartInfo` | For `Game\skse64_loader.exe`, with Game as the working directory and no arguments, started at `Shell.cs:5321 Process.Start`. The loader starts `SkyrimSE.exe` beside it. Then one log line names the launcher version, the newest pack applied and the display mode. | |
| 25 | `Shell.cs:5348 Discord.NewSession` | An id for this session, then `Shell.cs:5352 Discord.SessionStart` on a pool thread posts it to `/api/play/start`. | `Profile\logs-pending.txt` |
| 26 | `Shell.cs:5359 Presence.Start` | The Discord card, on its own thread. | |
| 27 | `Shell.cs:5361 PlayedFile` | Then `Shell.cs:5363 Stats.StartedPlaying`, a pause of 1.2 seconds, and the window minimises unless Keep launcher open is ticked. | `Profile\played.flag`, `Profile\stats.txt` |

If anything in Play throws, the catch at the end of it undoes the work in
this order: `Shell.cs:5377 Swap.Restore`, `Shell.cs:5378 Hold.Release`,
`Shell.cs:5379 Keep.Unpark`, `Shell.cs:5380 Presence.Stop`,
`Shell.cs:5381 Keep.TakeNote`. A reason longer than one line is shown in a
box.

### Inside Chars.Prepare (step 7)

| Where | What happens | Left behind |
|---|---|---|
| `Chars.cs:829 Prepare()` | The saves folder Skyrim will see, `Profile\MyGames\Saves`, becomes a junction to `Profile\Characters\saves`. A real folder there with files in it is moved aside whole, never deleted. SkyrimPlatform's scaffolding saves are deleted. | `Profile\Characters\saves`, the junction, maybe `Saves-before-Thornswood-<time>` |
| `Chars.cs:918 EnsureSpare` | Mints the spare id for New character when there is none. | `Profile\Characters\profiles.txt` |
| `Chars.cs:935 AutoJoin.SetChooseAtMenu` | `AutoJoin.cs:295 SetChooseAtMenu()`: the id played last and `chooseAtMenu` inside `gameData`, read back, and a throw if the file does not say what was written. | `skymp5-client-settings.txt` |
| `Chars.cs:937 WriteBrowserBackend` | Which in-game browser SkyrimPlatform uses (its log level and text window are Enforce's, step 15). Edited, never rewritten, and only when a value changes. | `Game\Data\SKSE\Plugins\SkyrimPlatform.ini` |
| `Chars.cs:944 Voice.Reconfigure` | Voice fetches a token for that id for its page, when the voice address is https. The game's chat asks for its own (`voice-token-ask.txt`). | |
| `Chars.cs:966 TidySlots` | Only on the site's own answer about how many slots this account has. | `profiles.txt` when a slot moves |
| `Chars.cs:968 WriteCharacters` | Names from the site's roster, then the list the menu draws. Throws when it cannot be written. | `Game\Data\Platform\thornswood-characters.json`, `Game\Data\Platform\UI\thornswood-characters.js` |
| `Chars.cs:972 ChoiceFile` | Last session's choice and forget files deleted, so neither is read as this session's. | |

### What is on disk when the game window appears

Written or rewritten, when anything needed changing:

- `Profile`: `door.txt`, `Characters\profiles.txt`, `Characters\saves`,
  `MyGames\Saves` (a junction), `MyGames\SkyrimPrefs.ini`, `Parked\` and
  `parked.txt`, `swap.json`, `logs-pending.txt`, `played.flag`, `stats.txt`,
  `launcher.log`, and with a local server `server.pid` and
  `server.log`.
- `Game\Data\Platform`: `Plugins\skymp5-client-settings.txt`, any kept file
  put back, `thornswood-session.txt`, `thornswood-characters.json`,
  `UI\thornswood-characters.js`.
- `Game\Data\SKSE\Plugins`: `SkyrimPlatform.ini`,
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

`Shell.cs:2544 timer.Tick` keeps going. `Shell.cs:2558 PollChoice` reads
`Game\Data\Platform\thornswood-choice.txt`, which the menu plugin writes when
the person picks (`Chars.cs:592 ReadChoice()`); a new id is written into
`profiles.txt` (`Chars.cs:617 Chose()`), handed to voice and checked in with
the site. The same tick keeps a join pass for the character picked
(`JoinPass.cs:63 Tick()`, #937): fetched from the site when they pick and
every four minutes after, and left in `Game\Data\Platform	hornswood-pass.txt`
for the front plugin to hand the game server, which ends a session without
one. Nothing in this loop writes the client settings: a write to that
file reloads every plugin in the running game.
`Shell.cs:2563 CheckUpdatesInPlay` looks for a release every thirty seconds
and, four and a half minutes after first seeing one, closes the game so it can
be installed, landing on the server's own five minute warning.

### When the game closes

The first tick that finds no game runs, in order:
`Shell.cs:2579 Presence.Stop`, `Shell.cs:2580 Hold.Release`,
`Shell.cs:2581 Keep.TakeNote` (the session note goes),
`Shell.cs:2582 Swap.Restore` (Windows' folders back, `swap.json` gone),
`Shell.cs:2584 Keep.Unpark` (parked plugins home, or into `Profile\Isolated`
when their launcher has already written a new copy),
`Shell.cs:2587 Stats.StoppedPlaying`, then on a pool thread
`Shell.cs:2598 Discord.SessionEnd` and `Shell.cs:2605 Discord.SessionLogs`
(the session's logs up to the site before the next start truncates them),
`Shell.cs:2613 Chars.AddPlaytime`, `Shell.cs:2621 CrashDump.AfterSession`
(when a crash log was written this session, a line naming it and the
snapshot beside it), `Shell.cs:2628 Checks.LastRunFrom` (a
warning if that session ran some other Skyrim), and `Shell.cs:2641 Verify.Run`
on a pool thread. A game closed for an update then fetches and installs it
(`Shell.cs:2676 CheckUpdatesBackground`).

### Closing the launcher

`Shell.cs:2523 win.Closing` asks first when a game is still running, then
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
