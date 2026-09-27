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

### What Windows shows, for the Downloads page and the FAQ to match

`Thornswood-Setup.exe` is not signed yet (that is issue #390), so until it is,
Windows cannot show a verified publisher and the UAC prompt's publisher line
reads `Unknown`. Everything else the prompt and the file's Properties show is
filled in from a version resource `Bootstrap.cs` carries itself, and is kept
stable so it does not change from one build to the next. The build date rides in
the file name, never in the product identity. Website owns the Downloads and FAQ
copy; these are the exact strings to write it against: Program name
(`FileDescription`), the UAC prompt's first line, is `Thornswood Setup`;
Verified publisher is `Unknown` until #390 signs it; Product name, shown in
Properties and to SmartScreen, is `Thornswood Setup`; Company is `Thornswood`;
Copyright is `Copyright (c) Thornswood`; File version is `1.0.0.0`; Product
version is `1.0.0`; and the Original file name is `Thornswood-Setup.exe`. The
setup window's own title bar says `Thornswood Setup` too, so the name is the
same from the download link through UAC to the window, and the emblem is
compiled in as the file's icon, so the download is not a blank mark in the
browser. `tests\test-setup-stub-identity.ps1` holds all of these to what is
here.
