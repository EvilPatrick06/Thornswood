# 3312: runner 3 signs the release launcher when GitHub has no minutes

Issue: #3312. Pull requests: Thornswood (release.yml hosted first with the
VPS fallback signing on runner 3, release-tag.yml, Ship -FromFeed taking a
new launcher from GitHub) and EvilPatrick06/skymp (the manifest job checks
the launcher before it signs). Both merged before this runs.

What it needs before a release can fall back to the box: runner 3 carries
the label `thornswood-sign`, has signtool, and its outbound rules let the
signing hosts through. Until then the box fallback waits for a runner with
the label, so a release only builds on GitHub's runner.

## 1. Put the label on runner 3 (anywhere, the cloud included)

Touches GitHub's runner settings only. Since #3107 (PR #3327) the box's
admin service changes runner labels to match every `records/*-runners.json`
on main, and a push to main that changes a runner record asks it by itself,
so the merge of `records/sign-runners.json` may already have done this. It
needs the #3107 run note done first (the service on the box and its App
installed); until then this goes red saying there is no App yet.

```
pwsh scripts/deploy/Set-BuildRunners.ps1
```
Prints MATCHES, or CHANGED with `thornswood-vps-3` gaining
`thornswood-sign`, and exits 0.

```
pwsh scripts/deploy/Set-BuildRunners.ps1 -Check
```
Exits 0.

## 2. Is signtool on the box (the Desk, read only)

```
.\scripts\vps\Remote.ps1 "Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin' -Recurse -Filter signtool.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName"
```
Prints at least one path under `\x64\`, version 10.0.22621 or later (older
ones cannot drive the signing client). If none: the Windows SDK comes with
`Bootstrap-VPS.ps1 -IncludeEngineTools` (several GB); write the measurement
on #3312 and pick the smallest install that brings signtool before running
anything.

## 3. Runner 3's outbound rules (the Desk, touches the box)

Runner 3 carries `-NetworkOnly` (#2161): its account reaches GitHub,
loopback and the `-AllowHost` names only, resolved to addresses when the
rules are written. Signing needs, besides GitHub: `api.nuget.org` (the
signing client), `login.microsoftonline.com` (the token exchange),
`wus2.codesigning.azure.net` (records\signing\metadata.json's endpoint) and
`timestamp.acs.microsoft.com`, and Windows' certificate checks of each
(`oneocsp.microsoft.com`, `crl.microsoft.com`, `www.microsoft.com`).
The first fallback run is the measurement: start one (step 4) and read the
sign step's log. If it stops at a host, that host is the finding: put it on
#3312 with the log line. `login.microsoftonline.com` answers from many
addresses that change, so a list resolved once may not hold; the fix for
that is in Install-Runner.ps1 (Microsoft's published ranges, the way
GitHub's are read), never a retry.

## 4. The proof: a dev Ship from the cloud carrying a launcher

From a cloud session on main, once 1 to 3 are done (Ship -FromFeed, dev):
```
pwsh -NoProfile -File scripts/release/Ship.ps1 -FromFeed -Channel dev -RebuildLauncher "The launcher is built and signed by the release pipeline now."
```
Without a launcher change on main since dev's launcher, `-RebuildLauncher`
builds the same sources under the next dev number. It prints "asked
EvilPatrick06/Thornswood to tag ... as v<number>", "built, signed and
checked on GitHub: <run>", the box accepting the exe, and the fork's
signing run, whose "Check the launcher the release names" job passes.
Risks: dev only; the dev feed's launcher moves to the new number and every
dev launcher updates itself. Put the run, the release.yml run's url (which
runner signed) and the health check on #3312 and in ops/status.md.

Release notes (dev): "The launcher is built and signed by the release
pipeline now." No news post.
