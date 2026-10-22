# 498 Switch the launcher fully to MSBuild (VPS Build Tools, then the switch)

- **Lane:** Claude
- **Issue / PR:** #498 (open, claimed: Claude); prep #2362 merged as 572a8444; Anvil #2429 closed without merge (superseded by #2453 for #2163)
- **Channel:** VPS install first (Administrator), then a Thornswood PR and a Dev Ship. Main only on Patrick's word.
- **Staff status updates:** #staff-updates (1549254991082946570)
- **Needs first:** the Dev launch check in `498-msbuild-dev-launcher.md` if it has not been done yet (Ship with `-LauncherWith msbuild` and someone starts the Dev launcher). #2163's hosted release path is already on main via #2453 (opt-in until the switch-over).

## Why

Patrick chose option C: switch the launcher fully to MSBuild, and lift the C# 5 rule in the same PR (11 Oct). Prep is merged (#2362): both project files exist, `-With msbuild` works, and the comparison harness passes. The four VPS runners still have no Build Tools, so the default build cannot switch yet. Patrick then chose A (12 Oct): install Build Tools on the VPS runners. Anvil's #2429 (hosted release + MSBuild) was closed without merge; #2453 carried the hosted release work for #2163 instead. This note is what is left on #498 for Claude.

## Run

### 1. Install Build Tools on each VPS runner (Administrator, once per box)

ssh to the VPS as Administrator. The four runners are thornswood-vps, thornswood-vps-2, thornswood-vps-3, thornswood-vps-4 on the same box, so one install covers them. From a remote PowerShell 7 session (Windows will ask for elevation if needed):

    winget install --id Microsoft.VisualStudio.2022.BuildTools -e --accept-package-agreements --accept-source-agreements --override "--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.MSBuildTools --add Microsoft.Net.Component.4.8.1.TargetingPack"

That is the same line as Developer-Guide.md "Setting up a machine". A few GB of free space is enough (the box had about 132 GB free when measured).

Then from One, through ssh, confirm:

    ssh Administrator@192.135.112.23 "powershell -NoProfile -Command & { Set-Location C:\actions-runner; if (Test-Path 'C:\Thornswood-Repo\scripts\release\Find-MSBuild.ps1') { & 'C:\Thornswood-Repo\scripts\release\Find-MSBuild.ps1' -Report } else { Get-ChildItem 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe','C:\Program Files (x86)\Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8.1' -ErrorAction SilentlyContinue | Select-Object FullName } }"

It must name vswhere, an MSBuild.exe under BuildTools (not only Framework64\v4.0.30319\MSBuild.exe), and the 4.8.1 reference assemblies. Put the three lines on #498.

If Find-MSBuild.ps1 is not on that path, copy the Report check from a fresh clone on One over ssh, or run vswhere and a Test-Path of the 4.8.1 folder by hand and paste those paths on #498.

### 2. Dev launch check (if not already recorded on #498)

Follow `wiki/claude-queue/498-msbuild-dev-launcher.md` exactly:

    .\scripts\release\Find-MSBuild.ps1 -Report
    .\scripts\release\Ship.ps1 -Channel dev -LauncherWith msbuild -RebuildLauncher "The launcher is built a new way
    - Nothing should look or work differently. If anything about the launcher seems off after this update, tell staff."

Record on #498 that the Dev launcher updated and opened, with no new error in launcher.log. If anything looks wrong, stop: do not run the switch.

### 3. The switch pull request (one PR, line in #staff-general)

Settled design: Patrick decided the MSBuild switch on 11 Oct. Tip #staff-general with that when the PR opens.

From a clean worktree on origin/main:

1. `Build-Launcher.ps1`: delete the csc block and the reference hunting, drop `-With` (and `-LauncherWith` from Ship). Keep the record checks, the exe-in-use check, the stub move and the signing.
2. `LangVersion` in `launcher\app\Thornswood.csproj` and `installer\setup\Setup.csproj` moves off 5 to the newest Build Tools offers (13.0 on 17.14). On .NET Framework, features that need runtime types Framework lacks stay unavailable (default interface members, static abstract interface members, ref fields, init/records/required without hand-written attributes, ranges without System.Index/Range, async streams without IAsyncEnumerable).
3. Harnesses that compile launcher files with the in-box csc at `/langversion:5` move to the Roslyn csc beside MSBuild (`<MSBuild folder>\Roslyn\csc.exe`). The list is on #498 (issuecomment-612836... / the overnight comment of 12 Oct 8:27 AM): test-1252-leftover-settings, test-2210-refresh-scope, test-address-library, test-bans-pk.js, test-chat-settings, test-collection-draw, test-crash-snapshot, test-discord-forget, test-door-invite, test-door-outage, the five test-downgrade-*.ps1, test-feed-conditional, test-feed-notice, test-own-folder-alone, test-own-folder-first, test-picked-character.js, test-play-progress, test-play-stuck-game, test-record-sync, test-scrub-feed, test-self-update, test-shortcut-icons, test-signer-check, test-spare-owner, test-steam-updates, test-update-download, test-updater, test-vortex-collection-state, test-vortex-folder, test-vortex-profile-state, test-runtime-keep, test-native-stderr. Grep-style harnesses that forbid newer C# syntax drop that part (list on the same comment). C# inside PowerShell `Add-Type` (Check-Secrets.ps1, Bot-Service.ps1) stays C# 5.
4. `Setup-ShipMachine.ps1`, `Check-ShipReady.ps1` and `Install-Runner.ps1` check MSBuild instead of the in-box csc.
5. `tests\test-498-msbuild.ps1` becomes a check of the one build (parts 1 and 5 to 8 still hold).
6. Rule text: every place that still says "until the switch" or "C# 5" for the launcher is updated. PowerShell Add-Type stays called out as C# 5.
7. Wait for green VPS `Launcher builds`, then merge.
8. A Dev Ship of the new default build (no `-LauncherWith` needed after the switch).

### 4. Close #498 when

The switch is on main, a Dev Ship of that launcher has been started by someone, and the VPS runners report MSBuild. No Main Ship from this note without Patrick.

## Check afterwards

- `Find-MSBuild.ps1 -Report` on the VPS names Build Tools MSBuild and 4.8.1 refs.
- A VPS `Launcher builds` job builds the launcher with MSBuild (log line "Compiling with MSBuild" or the new single path) and is green.
- Dev launcher after the switch opens and reaches the game the same as before.
- `tests\test-498-msbuild.ps1` passes on One and on CI.

## Risks and how to put it back

- Installing Build Tools is a box change. If winget fails halfway, finish or repair with the Visual Studio Installer on the VPS; do not leave the runners mid-install.
- A bad switch PR: revert the merge commit; the previous default is csc until then. Dev: an ordinary Ship of the reverted main puts the old launcher back on the Dev feed.
- Harnesses still pointing at `/langversion:5` and the in-box csc will fail on CI after LangVersion moves. Move them in the same PR.
- Main and live stay on the previous launcher until Patrick says Ship main.
- Do not merge #2423 as part of this work.

## Release notes (draft)

The launcher is built a new way
- Nothing should look or work differently. If anything about the launcher seems off after this update, tell staff.

## News post (draft)

none (people should not notice)

## Test task (draft, for closing once the fix is on main)

none: nothing in play changes when the switch lands. Close #498 with a comment that the VPS has MSBuild, the switch PR merged, and the Dev launcher was started cleanly.
## Ran
- Dev release 20261016-010446-dev at 1:04 AM 16 Oct (Claude), from ops-batch at 7a02caa0, after Publish-Server dev (engine 3bdf3d3c, 10:45 PM 15 Oct), dev voice (-long-command-1) and Deploy-DevGamemode -LoadOrder (103 plugins, 10:48 PM). The MSBuild-built launcher (the switch, #2550) is on dev as 1.2.4.5. Left: somebody starts the dev launcher once and says it opened cleanly; then #498 closes.
