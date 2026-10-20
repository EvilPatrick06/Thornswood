# The engine: building the SkyMP fork

`engine\skymp` is Thornswood's fork of SkyMP. The game server module
(`scam_native.node`) and the six client runtime files every release carries
are built from it. This page says how to fetch, configure, build and record
each half, with the file and line for each step.

## The submodule

`.gitmodules:11-15` names the fork, `https://github.com/EvilPatrick06/skymp.git`,
on the branch `thornswood/engine-changes`, at `engine/skymp`. The repository
pins a commit, not the branch. This page does not name that commit or the
hashes built from it, because every engine change moves them: twice it named
a pin the records had already left (issue #1346). Read them where they are
written:

```powershell
git ls-tree HEAD engine/skymp                                                    # the pin
(Get-Content records\client-build.json -Raw | ConvertFrom-Json).forkCommit       # the client build
(Get-Content records\server-build.json -Raw | ConvertFrom-Json).source.commit    # the server build
```

All three name one commit. `records\server-build.json` also holds the server
executable's SHA256 and build time, and `records\README.md` lists the
provenance note for any build that kept an earlier build's bytes.
`Deploy-Server.ps1`, `Export-ServerPayload.ps1`, `Publish-Server.ps1` and the
installer refuse server files that differ from the record. The build check
requires the pin and both records to name one source commit and the server
record to include every artifact (see "One engine"), and this page to name no
commit or hash in full.

`ignore = dirty` (`.gitmodules:15`) keeps a build inside the fork from showing
as a change here. A different commit checked out in it still shows, and is
committed here together with the new build records (`.gitmodules:7-10`).

Scripts ask `scripts\release\Where.ps1` where things are, and it reads
`layout.json` at the repository root: `Engine` is `engine\skymp`, fetched or
not (`layout.json:6`); `ServerDist` and `ClientDist` are `build\dist\server` and
`build\dist\client` under `EngineBuild` (`layout.json:11-12`), which is this
machine's engine build (see "One engine") and `engine\skymp` on a machine that
records none; `Out` is the ignored `out`.
The old `C:\Thornswood-Dev\skymp` is not looked at any more (issue #440).

## Fetching it

```powershell
git submodule update --init engine/skymp
git -C engine/skymp submodule update --init --recursive
git -C engine/skymp remote add upstream https://github.com/skyrim-multiplayer/skymp.git
git -C engine/skymp fetch upstream
```

The fork at the pinned commit, then its own submodules, vcpkg among them
(`docs\OWNERSHIP.md:38`), then the `upstream/main` the record scripts measure
against (`New-ServerBuildRecord.ps1:62`, `New-ClientBuildRecord.ps1:87`).
A machine that only copies server binaries can leave the fork unfetched.

The checkout is on a detached HEAD at the pinned commit. To change the
engine, `git -C engine/skymp checkout thornswood/engine-changes` first, and
check that branch is still at the pinned commit before building.

## What a machine needs

- Visual Studio 2022 or its Build Tools, with "Desktop development with C++".
  `Build-Server.ps1` finds MSBuild through `vswhere.exe` and stops without it
  (`Build-Server.ps1:109-121`).
- CMake (that workload installs it), node for `npx webpack`, and the Steam
  copy of Skyrim Special Edition on 1.6.1170 for `SKYRIM_DIR`. vcpkg builds
  every library in the fork's `vcpkg.json` into
  `build\vcpkg_installed\x64-windows-sp` (`THIRD-PARTY.md:127`).

## Building it on your machine

Any developer builds the engine on their own machine, and needs to before a
dev Ship: Ship checks the client runtime against `records\client-build.json`
(issue #545). From the repository folder:

```powershell
.\scripts\release\Build-Engine.ps1 -Check   # what is missing; changes nothing
.\scripts\release\Build-Engine.ps1          # fetch, configure, build, compare
```

It checks the tools above and says what to install, fetches the fork at the
pinned commit and its submodules, configures `engine\skymp\build` the first
time with the line below (`SKYRIM_DIR` is `C:\Thornswood\Game` unless
`-SkyrimDir` says otherwise), builds everything in Release, and compares the
six client files with the record. The first run builds every vcpkg library
and takes a long while; after that only what changed is rebuilt, so after a
fork change somebody else made, `git submodule update engine/skymp` and run it
again. When it says the build is not the recorded one and you did not change
the engine, the fork is not at the pinned commit; when you did, run
`New-ClientBuildRecord.ps1` and put the record in your pull request.

How many projects it compiles at once (issue #1203). The fork compiles every
C++ project with `/MP`, one compiler per core, and a bare `/m` started one
project per core on top of that: on 29 September a build with 7.5 GB free on
22 cores failed in every `skyrim_platform` source with C3859 and C1076,
nothing wrong with the code. So `Build-Engine.ps1` and `Build-Server.ps1` give
MSBuild `/m:N /p:CL_MPCount=2`: two compilers in each project, and N from the
memory free when the build starts, 4 GB to each project, never more compilers
than cores (`scripts\release\EngineJobs.ps1` says how the numbers were
measured). `-Jobs N` on either script sets N by hand. A compile that runs the
machine out of memory anyway (C3859, C1076, C1060, LNK1102) stops saying so,
with the line to run again with fewer at once, instead of pointing at the
first error.

A fork in a folder whose path has an `&` in it (every worktree under
`C:\ThornswoodTemps&Worktrees` on One until #2900, for one) builds too (issue
#1025). vcpkg sets itself up through `bootstrap-vcpkg.bat`, and cmd.exe cuts a
path at a bare `&`, so `Build-Engine.ps1 -Fork <that fork>` gives the fork's parent folder a
free drive letter for the run (`subst`), configures and builds through it,
and removes the letter when it ends, however it ends. It is the parent and not
the fork itself because the fork's `CMakeLists.txt` compares the build folder
with `<fork>/build`, and a drive root gives `J://build`. A build configured
that way is built through the same letter next time; when that letter has
become another drive, it stops and says to free it or delete the build
folder. By hand, the same thing is `subst J: "<the folder that holds the fork>"`,
then `-Fork J:\<name>`, then `subst J: /d`.

## Configuring

`Build-Engine.ps1` runs this line. `Build-Server.ps1` never configures and
stops when `build\CMakeCache.txt` is missing (`Build-Server.ps1:32-35`,
`100-104`). By hand, once, from the repository folder:

```powershell
cmake -S engine\skymp -B engine\skymp\build -G "Visual Studio 17 2022" -A x64 `
  -DCMAKE_TOOLCHAIN_FILE="$PWD\engine\skymp\vcpkg\scripts\buildsystems\vcpkg.cmake" `
  -DVCPKG_TARGET_TRIPLET=x64-windows-sp `
  -DOFFLINE_MODE=ON -DBUILD_CLIENT=ON -DBUILD_SKYRIM_PLATFORM=ON `
  -DSKYRIM_DIR="<Steam library>\steamapps\common\Skyrim Special Edition"
```

These are the settings read off the shipping machine's `CMakeCache.txt` on
24 September (`docs\OWNERSHIP.md:68-71`) and used again for the configure at
`engine\skymp` on 25 September, which took 24.2 seconds
(`docs\archive\todo-list-2026-09-25.md:2987`). On 5 October (issue #1357)
each one was read against the fork's own CMake files at 0460584e, the
commit pinned that day:

| Setting | Where the fork reads it | Without it |
| --- | --- | --- |
| `-G "Visual Studio 17 2022"` | `CMakeLists.txt:78-83` stops the configure with any other generator when the compiler is MSVC | stops |
| `-A x64` | CMake's own platform switch; the triplet below is x64 too (`overlay_triplets\x64-windows-sp.cmake:1`) | the generator's default |
| `CMAKE_TOOLCHAIN_FILE` | `CMakeLists.txt:28-35` sets it itself before `project()`: the fork's `vcpkg\scripts\buildsystems\vcpkg.cmake`, or `C:/vcpkg/...` when the environment has `CI=true` on Windows. The value passed is not the one used; off a CI machine they are the same file | the same file |
| `VCPKG_TARGET_TRIPLET` | `CMakeLists.txt:7-15`, from `overlay_triplets` (`:17`) | `x64-windows-sp` on Windows |
| `OFFLINE_MODE` | `option`, `CMakeLists.txt:94`: offline mode in the server and client settings files the build generates | ON |
| `BUILD_CLIENT` | `option`, `CMakeLists.txt:90`; `skymp5-client\CMakeLists.txt:5` builds the bundle only when it is on | ON |
| `BUILD_SKYRIM_PLATFORM` | `option`, `CMakeLists.txt:92`; `skyrim-platform\CMakeLists.txt:3` | ON |
| `SKYRIM_DIR` | `option`, `CMakeLists.txt:117`; a folder with no `SkyrimSE.exe` in it stops the configure (`:138-142`) | the server settings get no plugin paths (`:133-135`) |

So every name is one the fork reads, and all but `SKYRIM_DIR` repeat what the
fork does without them; they are passed so a changed default upstream does
not quietly change our build. The fork also stops unless the build folder is
`<fork>\build` (`CMakeLists.txt:46-56`), and asks for CMake 3.19 or newer
(`:74`).

Checked on 10 October (issue #1357) on Ship PC One, at pin 7feb5dc4, with
CMake 4.4.3 (`cmake --version`) and Visual Studio 17 2022 Build Tools: the
line numbers above still hold at that commit, and the `CMakeCache.txt` of a
configure of this line at 7feb5dc4 the same day holds every setting as passed
(generator `Visual Studio 17 2022`, platform `x64`, triplet
`x64-windows-sp`, `OFFLINE_MODE`, `BUILD_CLIENT` and
`BUILD_SKYRIM_PLATFORM` ON, `SKYRIM_DIR` the game folder) and a generated
solution. No flag is wrong, missing or dead. `SKYRIM_DIR` is declared with
`option()`, so the cache stores it as `BOOL` holding the path; that is the
fork's own quirk and works. The cached toolchain path is the substituted
drive letter (`T:/skymp/...`) described above.

Never move a configured build folder: CMake writes absolute paths into it,
which is why the move to `engine\skymp` needed this configure again.

## The server: Build-Server.ps1

```powershell
.\scripts\release\Build-Server.ps1               # Release, then records it
.\scripts\release\Build-Server.ps1 -NoRecord     # compile only
```

- Reports the fork's branch and commit and any uncommitted file, and never
  changes the branch (`Build-Server.ps1:81-98`). On a detached HEAD it prints
  a NOTE that the branch is not `thornswood/engine-changes`.
- Installs `skymp5-server`'s packages from its `yarn.lock`
  (`yarn install --frozen-lockfile`), because the JavaScript half bundles them.
- Removes `dist_back\skymp5-server.js` and its map, then builds
  `build\skymp5-server\skymp5-server.vcxproj`, which builds
  `skymp5-server-ts` (the JavaScript half) first, and
  `build\skymp5-scripts\skymp5-scripts.vcxproj` (the compiled Papyrus in
  `data\scripts`). The fork's CMake runs the TypeScript build only when a
  `.ts` file is newer than the bundle, never for a package or lockfile change,
  so the bundle is always written again; esbuild writes the same bytes for the
  same sources (issue #1214). Everything else builds as a dependency; the
  client is not built here.
- Compiles as many projects at once as the memory free allows, two
  compilers each, or `-Jobs N` of them, the same as `Build-Engine.ps1`
  (issue #1203).
- Lists every server file that came out, with its hash, and says which changed.
- Without `-NoRecord` it runs `New-ServerBuildRecord.ps1` on the build and the
  fork it just built. With it, `records\server-build.json` is left alone, and
  every publish and deploy refuses the new files until the record names them.
  It sends nothing anywhere.

`scripts\release\New-ServerBuildRecord.ps1` writes `records\server-build.json`: every
server file `scripts\deploy\ServerBuild.ps1` names, each with its sha256, size and
the fork commit, the binary's sha256 and build time at the top, and the fork's
origin, branch, commit, upstream and merge base. It records only files it can
tie to the fork: every TypeScript source in the bundle's map is the fork's word
for word (`scripts\release\server-bundle-sources.js`), the packages are the
lockfile's (`yarn check --integrity`), `package.json`, `yarn.lock` and
`data\scripts` are the fork's byte for byte, and `launch_server.bat` is the
configure's. Anything else stops it and nothing is written. It warns when the
fork has uncommitted changes or a source file under `skymp5-server\cpp` or `ts`
is newer than the binary.

## The client

The client runtime is six files (`New-ClientBuildRecord.ps1:50-57`):
`MpClientPlugin.dll`, `SkyrimPlatform.dll`, `SkyrimPlatformImpl.dll`,
`SkyrimPlatformCEF.exe.hidden`, `skymp5-client.js` and `TESModPlatform.pex`.
The bundle comes from `npx webpack` in `engine\skymp\skymp5-client`; the other
five from the native build with `BUILD_SKYRIM_PLATFORM` on (MpClientPlugin is
built on Windows whatever `BUILD_CLIENT` says, `skymp5-server\cpp\CMakeLists.txt:9-22`).
The bundle goes into `build\dist\client\Data\Platform\Plugins`
(`skymp5-client\webpack.config.js:8-9`), and `build\dist\client` is where
`Where.ps1 ClientDist` and every script below look. NOT CHECKED here: which
MSBuild targets produce the five and which step puts them in that folder.

Then, in order:

1. `.\scripts\release\New-ClientBuildRecord.ps1` hashes the six into
   `records\client-build.json`. It refuses a bundle with no `THORNSWOOD PATCH`
   block or with another server's markers (`New-ClientBuildRecord.ps1:75-79`),
   and warns when the fork is dirty or a source file is newer than the build
   (`:109-113`).
2. `.\scripts\release\Sync-Client.ps1` checks all six in the build against the record
   and copies nothing until all six pass, then copies them into the game
   folder, `C:\Thornswood\Game` by default (`Sync-Client.ps1:40`, `66-109`).
   `Go.ps1` runs it.
3. `.\scripts\release\Sync-Client.ps1 -Check` compares only: exit 0 all in place, 2
   something differs, 1 the build is not the recorded one or is missing
   (`Ship.ps1:726-733`). Ship runs it and refuses to go on otherwise
   (`Ship.ps1:742-750`).

The launcher carries `records\client-build.json` inside it
(`Build-Launcher.ps1:306-310`) and checks the same six by hash
(`launcher\app\ARCHITECTURE.md:301-304`).

## Rebuilding the same commit

A rebuild of the same commit is not byte for byte the same. Measured on
25 September: `scam_native.node` rebuilt from c8832519 at the new place
hashed `ecb029cb...`, not the recorded `de74c582...`. The recorded binary was
put back from `local\engine-dist-c8832519`, so neither record changed and
`Deploy-Server.ps1` still takes it (`docs\archive\todo-list-2026-09-25.md:2987`).

From 27 September both records named `d0006351`. Then the client record and
the pin moved on (#1016 to `44366c7e`, #898 to `c63fe637`) and the server record
did not, so the servers ran the `d0006351` build while every later server fix
sat in the fork unused (issue #1200). On 29 September the pin and both
records were put back on one commit, `1ed42585`, built together, and "One
engine" below has kept them on one commit since.

So the recorded binaries stay unless the engine changed:

- To prove the toolchain builds, copy `build\dist` to
  `local\engine-dist-<commit>` first (`local` is ignored by git,
  `.gitignore:101`), run `Build-Server.ps1 -NoRecord`, then put the backup
  back and check it:
  ```powershell
  (Get-FileHash engine\skymp\build\dist\server\scam_native.node -Algorithm SHA256).Hash.ToLower() -eq (Get-Content records\server-build.json -Raw | ConvertFrom-Json).sha256
  ```
  It prints True when the recorded binary is back.
- When the engine did change: see "One engine" below.

## One engine

Decided by Patrick on 29 September (issue #1200): "we should always be using
the new one ... What's the point in the changes if we aren't using them." There
is one engine, the head of `thornswood/engine-changes` in the fork, and the pin
here, `records\client-build.json` and `records\server-build.json` all name that
one commit. No change to the engine lives anywhere else: not on a local branch
of somebody's `engine\skymp`, not as an uncommitted edit, not in a build nobody
recorded.

A change to the engine goes like this:

1. A branch in the fork, from the head of `thornswood/engine-changes`, in a
   worktree of the fork, and a pull request in the fork, merged with a merge
   commit. A merge commit has the same files as the branch it merges, so a
   build of the branch's last commit is a build of the head.
2. Build both halves from that commit: `Build-Engine.ps1 -Fork <that worktree>`,
   then `Build-Server.ps1 -Fork <that worktree>`, which builds every server file
   again from it (the JavaScript half included) and records them. A fork under
   a path with an `&` in it is reached through the drive letter it was
   configured through (`K:\<fork>`).
3. `New-ClientBuildRecord.ps1 -Dist <fork>\build\dist\client -Clone <fork>`; the
   server record came out of step 2.
4. One pull request here with the new pin (`git -C engine/skymp checkout
   <commit>`, then `git add engine/skymp`), both records, and the commit named
   in `THIRD-PARTY.md` (its fork section, "On our servers" with the server's
   SHA256, and the link in "Where the source is") and in
   `site\data\site\credits.md`. `tests\test-third-party.js` is red when any of
   those is not the commit `records\server-build.json` names.
5. After it merges: the server to the dev server with `Publish-Server.ps1
   -Channel dev`, the client with the next dev Ship. A machine without that
   build puts it on from the store on the box, where the publish or deploy
   that sent it kept it: `Publish-Server.ps1 -Channel dev -FromStore`, and
   for live `Deploy-Server.ps1 -FromStore` (#459). `-ServerBuild <zip>` sends a
   server build made elsewhere to the store first, held to the record.

Which build a machine's scripts read (issue #2019). The build of step 2 is in
the fork worktree, not in any checkout's `engine\skymp`, so a machine records
that worktree once: `.\scripts\release\Setup-ShipMachine.ps1 -EngineBuild
<that worktree>` writes `%LOCALAPPDATA%\Thornswood\engine-build.json`, and
`Where.ps1` (and `where.js`) answer `ClientDist`, `ServerDist`,
`ServerSettings` and `ChangeForms` under it for every clone and worktree on
the machine. Until then each checkout read its own `engine\skymp\build`, and
on 15 October a dev Ship from a worktree whose build was three days old
refused against the record. A record naming a folder with no `build\dist`
stops the script that asks, with a sentence; it never falls back to another
folder. After building a new engine commit in another worktree, record that
one. On One the recorded build is
`C:\Thornswood-Repo\worktrees\engine-3d2cb747`.

Two harnesses hold it. `tests\test-one-engine.js`, in the build check on every
pull request, is red when the pin and the two records do not name one commit,
or name another branch or fork than `.gitmodules`, or when the server record
leaves out a server file or says one was built from another commit. `tests\test-engine-at-fork-head.js`,
in the nightly checks, asks GitHub whether the pin is the head of the branch
(or the head is only merge commits over it with the same files), and is red
when a fork change has been merged and not pinned here.

One more, a level up (issue #1791). `tests\test-fork-upstream.js`, in the
nightly checks, asks GitHub for the commits on upstream
skyrim-multiplayer/skymp `main` that `thornswood/engine-changes` does not
have, and is red naming each one. Patrick, 5 Oct: the nightly goes red when
upstream has fixes the fork does not. It goes green when each is merged into
the fork branch (a fork pull request, then the steps above), or when
`records\upstream-not-taken.json` lists it with the reason it is not being
taken and who decided.

## The engine built in CI

Decided by Patrick on 15 October (issue #459, "C, then B"): the engine is
built in CI on GitHub's own runner first, and on the VPS runners when GitHub
refuses it, the way the build check falls back (#2407). That is
`.github\workflows\engine.yml`, whose header says each choice and why.

It runs the steps of "One engine" above on a runner, from this repository's
scripts: the fork checked out at one commit of `thornswood/engine-changes`,
`Build-Engine.ps1 -NoSkyrim`, then `Build-Server.ps1`, which records the
server, then `New-ClientBuildRecord.ps1`. A runner has no game, so
`-NoSkyrim` configures without `SKYRIM_DIR`: the fork then puts its committed
Papyrus into the build, as upstream's own CI build does, and the records
hold the build to it. Every runner sets `CI=true`, which makes the fork's
`CMakeLists.txt` take `C:/vcpkg` instead of its own vcpkg, so both scripts
take it out of their own environment first (`EngineJobs.ps1`,
`Clear-EngineCiSwitch`). There is no drive letter to keep and no Store
PowerShell to lose on a runner: its checkout path has no `&` in it, and its
pwsh is an installed one.

The fork's own build comes first (Patrick's B on #459, 16 October). The
fork is public, so GitHub builds it at no cost: since fork #79 every push to
`thornswood/engine-changes` builds the engine on GitHub's runner
(`.github\workflows\thornswood-pr-windows.yml` in the fork) and keeps what
the records need as the artifact `thornswood-engine-<commit>`, with
`fork-build.json` naming the run and each file's sha256 and time. Before
anything is compiled, `engine.yml` looks for that build of the commit
(`scripts\release\ForkEngineBuild.ps1`), holds it to the commit, the run and
every file, puts it in the fork's build folder, and makes both records from
it with `-BuiltBy` naming the fork's run. The engine is compiled here, on
GitHub's runner and then the VPS, only when the fork has no build of the
commit (one from before fork #79, or one whose 90 days are over). A fork
build still running, or one that ended red, stops the run with its link.
Both check the fork out as committed, LF, as One does: the image's git turns
text to CR LF, and the records hold the server's `package.json`, `yarn.lock`
and bundle to the fork's bytes.

Start it from the Actions tab, or from the repository folder:

```powershell
gh workflow run engine.yml --ref main -f commit=<the fork commit>
```

With no commit it builds the one the branch pins. It runs only when started
by hand: a pull request's code reaches the box through the build check alone
(#1306). One artifact of the run, `engine-<fork commit, 12>`,
holds `records\server-build.json` and `records\client-build.json`, the server
build as the store on the box keeps it (`server\server-<fork commit
12>-<zip hash 16>.zip` and its `.json`, `scripts\deploy\ServerArtifact.ps1`),
the six client files under `client\` at the paths the record names,
`fork-build.json` when the fork built it, and `SHA256SUMS` over all of it.
The run commits nothing and sends nothing.

The pin pull request from it, step 4 of "One engine" with the records CI
made instead of a machine's own build, from the repository folder on a branch:

```powershell
gh run download <the run's id> -n engine-<fork commit 12> -D out\engine-<fork commit 12>
Copy-Item out\engine-<fork commit 12>\records\server-build.json, out\engine-<fork commit 12>\records\client-build.json records\
git -C engine/skymp fetch origin
git -C engine/skymp checkout <the fork commit>
git add engine/skymp records\server-build.json records\client-build.json
```

then the commit in `THIRD-PARTY.md` and `site\data\site\credits.md`, as step 4
says. The six client files go into a game folder with
`.\scripts\release\Sync-Client.ps1 -Dist out\engine-<fork commit 12>\client`,
which holds each to the record first.

A rebuild is never the same bytes ("Rebuilding the same commit", above), so a
pin takes the records of the one build whose files are then sent: CI's, or
one machine's, never a mix.

On the VPS the fallback needs the C++ half of the Build Tools, CMake and
yarn, which the box did not have on 16 October:
`.\scripts\vps\Remote.ps1 -File .\scripts\vps\Bootstrap-VPS.ps1 -Arguments '-IncludeEngineTools -SkipFirewall'`
puts them there. Until it has run, the fallback stops at Build-Engine's tool
check and says what is missing. `tests\test-459-engine-workflow.ps1` holds the
workflow's shape and these two scripts' part in it, and
`tests\test-459-fork-build.ps1` which fork build is taken, what it is held
to, and the records' `-BuiltBy`.
