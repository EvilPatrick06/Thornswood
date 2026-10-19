# The installer

## What it is

This folder holds three files. `Bootstrap.cs` is the source of the small program
a new person runs first, `Thornswood-Setup.exe`. `Setup.manifest` is that
program's application manifest (issue #463): sharp at any display scale and on
every monitor (per-monitor DPI), never asking for administrator (asInvoker),
and named `Thornswood.Installer.Setup` at the launcher's version, which
`Build-Launcher.ps1` writes into the copy it embeds. The window also keeps
inside the screen at any scale with the launcher's `WindowFit.cs`, which the
build compiles in beside it. `tests\test-app-manifest.ps1` reads the manifest
back out of the built exe. Its colours are the launcher's too (#2851): the build
compiles `launcher\app\Themes.cs` in as well, the window is drawn in Forge
from it, and Bootstrap.cs holds no colour of its own, so the first window a
new tester sees has the launcher's 4.5 to 1 text. `tests\test-2771-text-contrast.js`
holds it to that. It is not the launcher's source;
that is `launcher\app`. It is a WPF window in C# 13, like the launcher, built
with MSBuild from `Setup.csproj` beside it (#498). It asks
which drive to install to, reads the
payload attached to its own end, or downloads it from the site
(`https://thornswood.net/api/payload`), carrying on from where a dropped
download stopped and checking it against the SHA-256 the site gives, then
unpacks it and runs the install script inside, the one `Setup.bat` runs, with
the chosen folder.

Since issue #1365 both halves of that check are refusals rather than
allowances, the standard `Updater.cs` already holds the launcher to. The
address the site gives is fetched only when it is a relative path, which is
joined onto the site as before, or an absolute `https` one; plain `http`, and
every other scheme, stops the install. And a reply with no SHA-256 on it stops
it before a byte is fetched, where it used to install unmeasured so that a new
installer still worked against a site from before the hash.
`tests\test-payload-hash.ps1` holds all of that.

Since issue #889 that script runs inside this window, not in a console of its
own. It is started the way `Setup.bat` starts it (the same PowerShell, the same
`-MovePayload -Root`), hidden, with `-NonInteractive`; every line it prints
shows in the window and in `setup-log.txt` beside the unpacked payload, its
exit code decides whether the window closes or says what stopped it, and its
one question, the Steam depot downloads on a standalone install, comes up as a
box in this window. The window will not close while the script is moving
files. `tests\test-setup-in-window.ps1` holds all of that.

It never uses a zip it finds on the disk. Until 25 September it took an old
setup zip from beside itself or the
Downloads folder ahead of everything else, unchecked, and a tester got an old
install that way. `tests\test-installer-own-payload.ps1` holds it to that.

## On your machine

`scripts\release\Build-Launcher.ps1` compiles it after the launcher, into
`out\setup-stub.exe`, which git ignores like every other `.exe`. A failed
compile keeps the last working stub and says so. That copy is what a dev Ship
and a hand-run `Package-Thornswood.ps1` build around. A main Ship with
`-Package` does not use it: `.github\workflows\release.yml` builds the stub
beside the launcher from the tagged commit and lists both in `SHA256SUMS`,
and Ship downloads it, checks it, and passes it as
`Package-Thornswood.ps1 -Stub` (issue #932). Build into a scratch root, as
for the launcher:

```
.\scripts\release\Build-Launcher.ps1 -Root "$env:TEMP\ts-build" -NoPause
```

`scripts\release\Package-Thornswood.ps1` copies the stub to `Thornswood-Setup.exe`
beside `Thornswood-Setup.zip`, the payload, and `Sign-Artifact.ps1` signs the
exe when the machine has `records\signing\signing.json`. Running the stub installs for
real into the folder picked, and asks Skyrim to close first if it is running.

## Where it runs

On the machine of anybody installing Thornswood for the first time.
`Thornswood-Setup.exe` is put on the site by `Publish-Installer.ps1`, which
`Package-Thornswood.ps1` runs at the end. A main Ship rebuilds it when it is
given `-Package`; a dev Ship never touches the installer.

The site carries the one file shape: the payload attached to
`Thornswood-Setup.exe`, nothing beside it (`/file/Thornswood-Setup.exe` was
252,624,384 bytes on 29 September, with no `Thornswood-Setup.zip` and an empty
`/api/payload`). A main Ship with `-Package` builds that shape, passing
`Package-Thornswood.ps1 -OneFile` (issue #1213), and so does a hand-run
`Package-Thornswood.ps1 -OneFile`. Without `-OneFile` it builds the two file
shape, a small exe that downloads `Thornswood-Setup.zip` from
`/api/payload`, at the address written into `Bootstrap.cs`; Bootstrap reads
either. Which shape the site carries is the owner's call, asked on #1213.

### VirusTotal (optional, manual)

Publish no longer sends the installer to VirusTotal. Code signing (#390) is the
trust path; the website is separately removing site VT warnings. Soft-skip and
`VT_API_KEY` requirements are gone from `Publish-Installer.ps1`, Package, and
Ship's post-tip block.

`scripts\release\Publish-VirusTotal.ps1` and
`scripts\release\Add-VirusTotalComment.ps1` stay in the repo as optional
manual tools when somebody wants a report by hand:

```
.\scripts\release\Publish-VirusTotal.ps1 -Path <file>
.\scripts\release\Publish-VirusTotal.ps1 -Path <file> -Sha256 <hex>
```

They still read `VT_API_KEY` from the environment and nowhere else.
`tests\test-virustotal-upload.ps1` holds the skip and fail-soft paths for that
manual script.

### What Windows shows, for the Downloads page and the FAQ to match

`Thornswood-Setup.exe` is signed when the build machine has `records\signing\signing.json`
(#390 done). The UAC publisher line then shows the signed publisher rather than
`Unknown`. The product NAME strings the prompt and the file's Properties show
come from a version resource `Bootstrap.cs` carries itself, and those names are
kept stable so they do not change from one build to the next. File version and
Product version are not hardcoded in Bootstrap; `Build-Launcher.ps1` stamps them
at compile time from `launcher\app\Updater.cs` (`Version = "x.y.z"`), so the
stub tracks the launcher release number (e.g. File version `1.1.95.0`, Product
version `1.1.95` when the launcher is at 1.1.95). The build date rides in the
file name, never in the product name. Website owns the Downloads and FAQ copy;
these are the exact strings to write it against: Program name
(`FileDescription`), the UAC prompt's first line, is `Thornswood Setup`;
Verified publisher is the signed publisher when signing.json is present;
Product name, shown in Properties and to SmartScreen, is `Thornswood Setup`;
Company is `Thornswood`; Copyright is `Copyright (c) Thornswood`; File version
and Product version match the current launcher release from Updater.cs; and the
Original file name is `Thornswood-Setup.exe`. The setup window's own title bar
says `Thornswood Setup` too, so the name is the same from the download link
through UAC to the window, and the emblem is compiled in as the file's icon, so
the download is not a blank mark in the browser.
`tests\test-setup-stub-identity.ps1` holds the name strings and the
Build-Launcher version-stamping wiring to what is here.

### Version resource after signing

`Build-Launcher.ps1` leaves `out\setup-stub.exe` unsigned. `Package-Thornswood.ps1`
copies it to `Thornswood-Setup.exe`, for a one-file build appends the payload and
a trailer, then signs the final Setup (a pre-signed stub cannot be signed again
after attach). `Publish-Installer.ps1` only uploads it. Neither rewrites the exe or
strips its version resource, so what a person downloads carries the exact fields
above. Checked on the live tip: `FileDescription`/`ProductName` `Thornswood
Setup`, `Company` `Thornswood`, `Copyright` `Copyright (c) Thornswood`,
`OriginalFilename`/`InternalName` `Thornswood-Setup.exe`, and matching File and
Product version.

Signing is the trust path (#390). Friend-facing copy about SmartScreen or
Defender, if any remains, is on the site (`site\data\help.md`).

## Which drive it offers

The drive it starts on is the one Steam's copy of Skyrim Special Edition is on,
found the way the launcher finds it (`launcher\app\Steam.cs`: Steam's folder
from the registry, then every path in `config\libraryfolders.vdf`, then the
first library holding `steamapps\common\Skyrim Special Edition\SkyrimSE.exe`).
`C:\Thornswood` is only the fallback when there is no Steam copy to find.

That is not a preference. Thornswood runs from its own game folder, built out
of the Steam copy mostly as hard links, and a hard link cannot cross a drive,
so an install on another drive is one the launcher refuses to play from
(`OwnGame.WhyNot`). The drive Skyrim is on is marked on its button, the line
under the buttons says what a different drive costs, and pressing Install on a
different drive asks once more before anything is written. It asks and does not
refuse: whether the launcher may fall back to copies instead, at about 26 to 41
GB, is the team's call in #staff-general (issue #473).
`tests\test-setup-skyrim-drive.ps1` holds all of that to what is here.

## Thornswood's own Skyrim folder

Issue #906, 28 September: "let's offer the own folder during install as
well". Under the drive card is a card with the words of the
launcher's Settings, Maintenance panel (`launcher\ui.xaml`, `PnlOwnGame`), a
tick box, "Give Thornswood a Skyrim folder of its own", and Choose Vortex's
folder.

The installer does not make the folder. The launcher does (`OwnGame.Make`),
out of what Vortex has deployed, and nothing is deployed while this window is
up. So the tick answers the launcher's own question in advance: it goes to the
script as `-MakeOwnGame`, into `config.json` as `MakeOwnGame`, and the launcher
then makes the folder without asking once Vortex has deployed. Nothing asks
for administrator: the firewall rule it used to ask for is gone (#911). Left unticked,
which is the default, nothing changes: no argument, no field, and the launcher
asks as it did before. A chosen Vortex folder is checked the way
`OwnGame.PointAt` checks it (SkyrimSE.exe and `Data\vortex.deployment.json`)
and saved as `VortexGame`, the field the Settings button writes. A standalone
install has its Game folder already and writes neither.
`tests\test-setup-own-folder.ps1` holds all of that to what is here.


## What a person agrees to before Install

Issue #1009, asked for on 28 September: "check boxes that lock the install for
reading and accepting terms and conditions, privacy policy, and agreeing to
the rules", "and links to all 3". Beside Install are four boxes, all unticked:
the age box, then "I have read and accept the Terms and Conditions", "I have
read and accept the Privacy Policy" and "I have read and agree to the Rules".
Install stays greyed out until all four are ticked. Each of the three has a
link beside it that opens the page on the site in the browser
(`https://thornswood.net/terms`, `/privacy`, `/rules`), so what a person
reads is the current text, never a copy inside the installer.

When Install is pressed, the setup program writes `Profile\accepted.json` in
the install: the time in UTC, and for each page its address and the SHA-256
of its text as `https://thornswood.net/api/page/<name>` serves it at that
moment, which is the version accepted. The site can hash its own page the same
way to say which version somebody agreed to. A page the site did not answer
for is recorded with an empty hash, and the install carries on: the boxes
were ticked either way. Nothing about the person or the machine goes in it.
`tests\test-setup-agreements.ps1` holds all of that, and with `-Live` also
checks the three links answer and the hashes match the pages served now.

An install made before that lock has no `Profile\accepted.json`, and nothing
else in the install records the three. The launcher reads the same file
(`launcher\app\Acceptance.cs`). When the file is missing, or a page's hash is
not the one recorded, it shows the same three boxes and the same three links
and writes the same record. Declining closes the launcher and writes nothing.
`tests\test-prior-acceptance.ps1` holds that.
