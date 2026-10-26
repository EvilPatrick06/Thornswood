# The installer

## What it is

What a new person gets before they have a launcher. `setup\Bootstrap.cs` is the
small program they download and run first, `Thornswood-Setup.exe`; its own
README says what it does. The rest is the installer's payload, which that
program downloads and unpacks: `Setup-Thornswood.ps1`, which the setup program
runs inside its own window; `Setup.bat` and `Install.bat`, which start the same
script in a console for a person running an unpacked payload by hand, where
the script asks the setup window's four questions itself (18 or over, the
terms, the privacy policy, the rules) and writes the same
`Profile\accepted.json` before it installs anything (issue #1018); and
`READ ME FIRST.txt`, the page a person reads
beside them. `Setup-Thornswood.ps1` runs inside the unpacked payload, so its
paths are the payload's layout and not this repository's.

## On your machine

`scripts\release\Build-Launcher.ps1` compiles `setup\Bootstrap.cs` into
`out\setup-stub.exe` after the launcher. `scripts\release\Package-Thornswood.ps1`
builds the payload: it copies the four files here beside the launcher and the
game files and stops if any of them is missing. With `-OneFile` it attaches
the payload to the stub; otherwise the stub downloads it from the site.
Nothing here is run from the checkout; to try a change, package into a
scratch folder and run what comes out, on a machine that is not your own
install.

## Where it runs

On a new person's machine, once, from the site's download. The payload and the
stub reach the site through `scripts\release\Publish-Installer.ps1`, which
`scripts\release\Package-Thornswood.ps1` runs at its end unless it is told not to.
Moved here from `tools\` on 25 September (issue #440, phase 7).
