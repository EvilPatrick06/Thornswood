# The installer

## What it is

This folder holds one file, `Bootstrap.cs`, the source of the small program a
new person runs first, `Thornswood-Setup.exe`. It is not the launcher's source;
that is `launcher\app`. It is a WPF window in C# 5, like the launcher, because the
same .NET Framework 4 csc compiles both and understands nothing newer. It asks
which drive to install to (`C:\Thornswood` unless another is picked), reads the
payload attached to its own end, or downloads it from the site
(`https://thornswood.net/api/payload`), carrying on from where a dropped
download stopped and checking it against the SHA-256 the site gives, then
unpacks it and starts the `Setup.bat` inside with the chosen folder.

It never uses a zip it finds on the disk. Until 25 September it took an old
`SkyrimTogether-Setup.zip` or `Thornswood-Setup*.zip` from beside itself or the
Downloads folder ahead of everything else, unchecked, and a tester got an old
install that way. `tests\test-installer-own-payload.ps1` holds it to that.

## On your machine

`scripts\release\Build-Launcher.ps1` compiles it after the launcher, into
`tools\setup-stub.exe`, which git ignores like every other `.exe`. A failed
compile keeps the last working stub and says so. Build into a scratch root, as
for the launcher:

```
.\scripts\release\Build-Launcher.ps1 -Root "$env:TEMP\ts-build" -NoPause
```

`scripts\release\Package-Thornswood.ps1` copies the stub to `Thornswood-Setup.exe`
beside `Thornswood-Setup.zip`, the payload, and `Sign-Artifact.ps1` signs the
exe when the machine has `tools\signing.json`. Running the stub installs for
real into the folder picked, and asks Skyrim to close first if it is running.

## Where it runs

On the machine of anybody installing Thornswood for the first time.
`Thornswood-Setup.exe` and its zip are put on the site by
`Publish-Installer.ps1`, which `Package-Thornswood.ps1` runs at the end. A main
Ship rebuilds them when it is given `-Package`; a dev Ship never touches the
installer. The address it downloads from is written into `Bootstrap.cs`.

### The VirusTotal report the Downloads page links to

The page prints the exe's SHA-256 with a link to VirusTotal's report on that
hash, and a file nobody has sent to VirusTotal has no report, so that link
landed on an "item not found" page from 24 September until the upload was
wired up. `Publish-Installer.ps1` now sends the exe through
`scripts\release\Publish-VirusTotal.ps1`, which Ship can also call on its own
for any file:

```
.\scripts\release\Publish-VirusTotal.ps1 -Path <file>
.\scripts\release\Publish-VirusTotal.ps1 -Path <file> -Sha256 <hex>
```

It reads the key from the environment variable `VT_API_KEY` and from nowhere
else. That is set on the machine that ships. A machine without it, which is
every other machine and every pull request build, prints
`VirusTotal: skipped (VT_API_KEY not set)` and carries on: the upload cannot
fail a publish, so the worst a missing key costs is a link that says item not
found until somebody sends that build by hand. VirusTotal takes files up to
650 MB, so a one-file installer above that is refused by VirusTotal rather
than by us, and the line says so. `tests\test-virustotal-upload.ps1` holds the
skip and the fail-soft paths to what is written here.

### What Windows shows, for the Downloads page and the FAQ to match

`Thornswood-Setup.exe` is not signed yet (that is issue #390), so until it is,
Windows cannot show a verified publisher and the UAC prompt's publisher line
reads `Unknown`. The product NAME strings the prompt and the file's Properties
show come from a version resource `Bootstrap.cs` carries itself, and those names
are kept stable so they do not change from one build to the next. File version
and Product version are not hardcoded in Bootstrap; `Build-Launcher.ps1` stamps
them at compile time from `launcher\app\Updater.cs` (`Version = "x.y.z"`), so
the stub tracks the launcher release number (e.g. File version `1.1.95.0`,
Product version `1.1.95` when the launcher is at 1.1.95). The build date rides
in the file name, never in the product name. Website owns the Downloads and FAQ
copy; these are the exact strings to write it against: Program name
(`FileDescription`), the UAC prompt's first line, is `Thornswood Setup`;
Verified publisher is `Unknown` until #390 signs it; Product name, shown in
Properties and to SmartScreen, is `Thornswood Setup`; Company is `Thornswood`;
Copyright is `Copyright (c) Thornswood`; File version and Product version match
the current launcher release from Updater.cs; and the Original file name is
`Thornswood-Setup.exe`. The setup window's own title bar says `Thornswood Setup`
too, so the name is the same from the download link through UAC to the window,
and the emblem is compiled in as the file's icon, so the download is not a blank
mark in the browser. `tests\test-setup-stub-identity.ps1` holds the name
strings and the Build-Launcher version-stamping wiring to what is here.
