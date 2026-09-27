# The engine: building the SkyMP fork

`engine\skymp` is Thornswood's fork of SkyMP. The game server module
(`scam_native.node`) and the six client runtime files every release carries
are built from it. This page says how to fetch, configure, build and record
each half, with the file and line for each step.

## The submodule

`.gitmodules:11-15` names the fork, `https://github.com/EvilPatrick06/skymp.git`,
on the branch `thornswood/engine-changes`, at `engine/skymp`. The repository
pins a commit, not the branch: `git submodule status` prints
`5c54e8b92fea2db1d2c1414c53bcb757fd4dd8df`, the commit `records\client-build.json:6`
and `records\server-build.json:10` now both name. The binary that server record
hashes is still the earlier build from `3cbf2f8779f512ab571009e9bcbd1274c39d9874`:
the VPS has not been rebuilt against the pin, and `Deploy-Server.ps1` refuses a
rebuilt `scam_native.node` until `New-ServerBuildRecord.ps1` records it (see
"Rebuilding the same commit").

`ignore = dirty` (`.gitmodules:15`) keeps a build inside the fork from showing
as a change here. A different commit checked out in it still shows, and is
committed here together with the new build records (`.gitmodules:7-10`).

Scripts ask `scripts\release\Where.ps1` where things are: `Engine` is `engine\skymp`
once it has a `CMakeLists.txt`, else the old `C:\Thornswood-Dev\skymp`
(`Where.ps1:56-62`); `ServerDist` and `ClientDist` are `build\dist\server` and
`build\dist\client` in it (`Where.ps1:74-75`); `Out` is the ignored `out`.

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
(`docs\archive\todo-list-2026-09-25.md:2987`). NOT CHECKED against the fork's
own `CMakeLists.txt`: the submodule was not fetched where this page was
written. `OFFLINE_MODE`, `BUILD_CLIENT`, `BUILD_SKYRIM_PLATFORM` and
`SKYRIM_DIR` are named in that cache reading; the variable carrying the
triplet is assumed to be `VCPKG_TARGET_TRIPLET`. Check both against
`engine\skymp\CMakeLists.txt` and the `cmake` folder beside it.

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
- Builds one project, `build\skymp5-server\skymp5-server.vcxproj`, in parallel
  (`Build-Server.ps1:129`, `142`). Everything the addon needs builds as a
  dependency; the client is not built here.
- Checks that `build\dist\server\scam_native.node` came out and says whether
  its sha256 differs from the one there before (`Build-Server.ps1:134-165`).
- Without `-NoRecord` it runs `New-ServerBuildRecord.ps1`
  (`Build-Server.ps1:171-188`). With it, `records\server-build.json` is left
  alone, and `Deploy-Server.ps1` refuses the new binary until the record
  names it (`Build-Server.ps1:167-170`). It sends nothing anywhere.

`scripts\release\New-ServerBuildRecord.ps1` writes `records\server-build.json`: the
binary's sha256, size and build time, and the fork's origin, branch, commit,
upstream and merge base (`New-ServerBuildRecord.ps1:98-112`). It warns when
the fork has uncommitted changes (`:69-74`) or a source file under
`skymp5-server\cpp` or `ts` is newer than the binary (`:80-97`).

## The client

The client runtime is six files (`New-ClientBuildRecord.ps1:50-57`):
`MpClientPlugin.dll`, `SkyrimPlatform.dll`, `SkyrimPlatformImpl.dll`,
`SkyrimPlatformCEF.exe.hidden`, `skymp5-client.js` and `TESModPlatform.pex`.
The bundle comes from `npx webpack` in `engine\skymp\skymp5-client`; the other
five from the native build with `BUILD_CLIENT` and `BUILD_SKYRIM_PLATFORM` on.
NOT CHECKED here: which MSBuild targets produce the five, and that webpack
writes into `build\dist\client`, which is where `Where.ps1 ClientDist` and
every script below look.

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

Since 27 September the source pin in both records is `5c54e8b9` while this
recorded server binary is still the `3cbf2f87` build above: the client was
rebuilt against the new pin and the server was not. The live server carries the
older binary until a rebuild from `5c54e8b9` is recorded here and shipped with
`Deploy-Server.ps1`.

So the recorded binaries stay unless the engine changed:

- To prove the toolchain builds, copy `build\dist` to
  `local\engine-dist-<commit>` first (`local` is ignored by git,
  `.gitignore:101`), run `Build-Server.ps1 -NoRecord`, then put the backup
  back and check it:
  ```powershell
  (Get-FileHash engine\skymp\build\dist\server\scam_native.node -Algorithm SHA256).Hash.ToLower() -eq (Get-Content records\server-build.json -Raw | ConvertFrom-Json).sha256
  ```
  It prints True when the recorded binary is back.
- When the engine did change: commit and push on `thornswood/engine-changes`
  in the fork, run `Build-Server.ps1` without `-NoRecord`, build the client
  and run `New-ClientBuildRecord.ps1`, then commit the new submodule commit
  and both records in one pull request here. The server then goes up with
  `Deploy-Server.ps1`, and the client files with the next Ship.
