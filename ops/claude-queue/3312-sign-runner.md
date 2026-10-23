# 3312: runner 3 signs the release launcher when GitHub has no minutes

Issue: #3312. Pull requests: Thornswood (release.yml hosted first with the
VPS fallback signing on runner 3, release-tag.yml, Ship -FromFeed taking a
new launcher from GitHub), EvilPatrick06/skymp (the manifest job checks
the launcher before it signs), and Thornswood's runner 3 reach (Install-Runner
lets the sign steps' Microsoft hosts through from Microsoft's published
Service Tags). All merged before step 3 runs.

What it needs before a release can fall back to the box: runner 3 carries
the label `thornswood-sign`, has signtool and a .NET runtime (8 or later), and its
outbound rules let the signing hosts through. Until then the box fallback
stops, so a release only builds on GitHub's runner.

## 1. The label on runner 3: done

22 Oct, Cloud Desk: `pwsh scripts/deploy/Set-BuildRunners.ps1` (run
39841030955) put `thornswood-sign` on `thornswood-vps-3`, and `-Check` (run
39841078720) exited 0. Since the runner 3 reach change, `Install-Runner.ps1
-Number 3` registers the label as well, so a reinstall keeps it.

## 2. signtool and the .NET runtime on the box (the Desk, touches the box)

signtool: done on 22 Oct, `C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe`.

The signing client's dlib runs on .NET (its own README, "Install .NET 8.0
Runtime" for x64 signtool; its runtimeconfig asks for net8.0 with
rollForward "Major", so a newer runtime runs it). Read on the box by the
Cloud Desk on 23 Oct: no .NET runtime at all, and no winget. So
`Bootstrap-VPS.ps1 -IncludeSigningRuntime` installs one pinned release,
.NET 10.0.13 (8's support ends 10 Nov 2026, 10's runs to 14 Nov 2028), from
Microsoft's download host, held to the SHA-512 Microsoft publishes for it
and to its Microsoft signature, machine wide:

```
.\scripts\vps\Remote.ps1 -File .\scripts\vps\Bootstrap-VPS.ps1 -Arguments '-IncludeSigningRuntime -SkipFirewall'
```
Prints ".NET runtime 10.0.13, for Microsoft's signing client", "checksum
matched", "signature valid, CN=Microsoft Corporation", then ".NET runtime
10.0.13 in C:\Program Files\dotnet\shared\Microsoft.NETCore.App", and in
its "ready:" report a line `dotnet runtime 10.0.13`. It installs nothing
else the box lacks unless asked (PowerShell 7 and Node are already there,
so it says so and leaves them). If it stops on the checksum or the
signature, nothing was installed: put the line on #3312.

Then read it back the way the runner account will find it:
```
.\scripts\vps\Remote.ps1 "Get-ChildItem 'C:\Program Files\dotnet\shared\Microsoft.NETCore.App' | ForEach-Object Name"
```
Prints `10.0.13`.

## 3. Runner 3's outbound rules (the Desk, touches the box)

Measured 22 Oct (release.yml run 39838728417): the VPS job built on
`thornswood-vps-3` and stopped at "Fetch the signing client
Setup-ShipMachine.ps1 pins", `An attempt was made to access a socket in a
way forbidden by its access permissions. (api.nuget.org:443)`. Runner 3's
`-NetworkOnly` rules (#2161) held GitHub, loopback and the `-AllowHost`
names only.

Every host the sign steps reach, besides GitHub, is in
`records/sign-runners.json` "reach" with the Azure service tag that holds
it: api.nuget.org and timestamp.acs.microsoft.com (AzureFrontDoor.Frontend),
login.microsoftonline.com (AzureActiveDirectory),
wus2.codesigning.azure.net (AzureCloud.westus2) and oneocsp.microsoft.com
(AzureFrontDoor.FirstParty). `-NetworkOnly` for runner 3 now reads those
tags from Microsoft's Service Tags file and lets them through. It rewrites
the whole group, so the package feeds runner 3 had are given again:

```
.\scripts\deploy\Install-Runner.ps1 -NetworkOnly -Number 3 -AllowHost pypi.org,files.pythonhosted.org,registry.npmjs.org -NoPause
```
Prints "Microsoft's Service Tags: https://download.microsoft.com/...", a
line "<host>: inside <tag>, N published range(s)" for each of the five
hosts, then "firewall: thornswood-runner3 may reach GitHub, this machine
and what it was given only, N blocked range(s) in M outbound rule(s)", and
exits 0. It changes runner 3's firewall group only. If it stops naming a
host that "answers from ... which Microsoft's <tag> list does not hold",
nothing was changed: write the line on #3312, and the record moves to the
tag that holds the host now.

```
.\scripts\deploy\Install-Runner.ps1 -NetworkOnly -Number 3 -Status -NoPause
```
Prints the rule count, all on.

Microsoft adds a range to that file at least a week before Azure uses it,
so this step run again each week keeps runner 3's hosts reachable, the
same way GitHub's lists are fetched again.

Not let through, and not measured yet: www.microsoft.com, where the signing
chain's certificate and revocation list addresses point (read off dev
launcher 1.2.6.7's signature on 22 Oct). It is Akamai, which publishes no
ranges. Step 4's sign step is the measurement: if signtool or the read-back
stops on it, put the log line on #3312; the fix is never an address
resolved once and never a retry.

## 4. The proof: a dev Ship from the cloud carrying a launcher

From a cloud session on main, once 1 to 3 are done (Ship -FromFeed, dev):
```
pwsh -NoProfile -File scripts/release/Ship.ps1 -FromFeed -Channel dev -RebuildLauncher "The launcher is built and signed by the release pipeline now."
```
Without a launcher change on main since dev's launcher, `-RebuildLauncher`
builds the same sources under the next dev number. v1.2.6.8 is tagged on
acc0715f from the stopped run of 22 Oct with no release on it, and Ship
climbs past a number tagged on another commit, so this goes out as 1.2.6.9
or later. It prints "asked EvilPatrick06/Thornswood to tag ... as
v<number>", "built, signed and checked on GitHub: <run>", the box accepting
the exe, and the fork's signing run, whose "Check the launcher the release
names" job passes. Risks: dev only; the dev feed's launcher moves to the
new number and every dev launcher updates itself. Put the run, the
release.yml run's url (which runner signed) and the health check on #3312
and in ops/status.md.

Release notes (dev): "The launcher is built and signed by the release
pipeline now." No news post.
