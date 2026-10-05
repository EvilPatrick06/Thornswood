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
`build\dist\client` in it (`layout.json:10-11`); `Out` is the ignored `out`.
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
`C:\ThornswoodTemps&Worktrees`, for one) builds too (issue #1025). vcpkg sets
itself up through `bootstrap-vcpkg.bat`, and cmd.exe cuts a path at a bare
`&`, so `Build-Engine.ps1 -Fork <that fork>` gives the fork's parent folder a
free drive letter for the run (`subst`), configures and builds through it,
and removes the letter when it ends, however it ends. It is the parent and not
the fork itself because the fork's `CMakeLists.txt` compares the build folder
with `<fork>/build`, and a drive root gives `J://build`. A build configured
that way is built through the same letter next time; when that letter has
become another drive, it stops and says to free it or delete the build
folder. By hand, the same thing is `subst J: "C:\ThornswoodTemps&Worktrees\worktrees"`,
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
each one was read against the fork's own CMake files at a247ef27, the
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

NOT CHECKED: that this line configures cleanly at the current pin, and with
which CMake version. That needs Windows, Visual Studio and a Skyrim folder,
and the reading above had none of them. `Build-Engine.ps1` runs this line;
whoever runs it next puts `cmake --version` and the configure's last line
here.

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
25 September: `scam_native.node` rebuilt from 3cbf2f87 at the new place
hashed `ecb029cb...`, not the recorded `de74c582...`. The recorded binary was
put back from `local\engine-dist-3cbf2f87`, so neither record changed and
`Deploy-Server.ps1` still takes it (`docs\archive\todo-list-2026-09-25.md:2987`).

From 27 September both records named `5c54e8b9`. Then the client record and
the pin moved on (#1016 to `10841f40`, #898 to `b4543a86`) and the server record
did not, so the servers ran the `5c54e8b9` build while every later server fix
sat in the fork unused (issue #1200). On 29 September the pin and both
records were put back on one commit, `1a2e5995`, built together, and "One
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
   in `THIRD-PARTY.md` and `site\data\site\credits.md`.
5. After it merges: the server to the dev server with `Publish-Server.ps1
   -Channel dev`, the client with the next dev Ship.

Two harnesses hold it. `tests\test-one-engine.js`, in the build check on every
pull request, is red when the pin and the two records do not name one commit,
or name another branch or fork than `.gitmodules`, or when the server record
leaves out a server file or says one was built from another commit. `tests\test-engine-at-fork-head.js`,
in the nightly checks, asks GitHub whether the pin is the head of the branch
(or the head is only merge commits over it with the same files), and is red
when a fork change has been merged and not pinned here.
