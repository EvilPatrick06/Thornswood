# The installer

## What it is

This folder holds one file, `Bootstrap.cs`, the source of the small program a
new person runs first, `Thornswood-Setup.exe`. It is not the launcher's source;
that is `tools\app`. It is a WPF window in C# 5, like the launcher, because the
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

`tools\Build-Launcher.ps1` compiles it after the launcher, into
`tools\setup-stub.exe`, which git ignores like every other `.exe`. A failed
compile keeps the last working stub and says so. Build into a scratch root, as
for the launcher:

```
.\tools\Build-Launcher.ps1 -Root "$env:TEMP\ts-build" -NoPause
```

`tools\Package-Thornswood.ps1` copies the stub to `Thornswood-Setup.exe`
beside `Thornswood-Setup.zip`, the payload, and `Sign-Artifact.ps1` signs the
exe when the machine has `tools\signing.json`. Running the stub installs for
real into the folder picked, and asks Skyrim to close first if it is running.

## Where it runs

On the machine of anybody installing Thornswood for the first time.
`Thornswood-Setup.exe` and its zip are put on the site by
`Publish-Installer.ps1`, which `Package-Thornswood.ps1` runs at the end. A main
Ship rebuilds them when it is given `-Package`; a dev Ship never touches the
installer. The address it downloads from is written into `Bootstrap.cs`.
