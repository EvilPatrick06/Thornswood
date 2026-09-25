# tools

The scripts that were here are in `scripts\<area>` since 25 September (issue
#440, phase 8): `scripts\release`, `scripts\deploy`, `scripts\vps`,
`scripts\ops`, `scripts\mods` and `scripts\dev`, with `scripts\README.md`
listing every one. The build records and the signing setup are in `records\`.

What is left here are forwarding copies of the commands people type most:
Ship, Bump-Version, the four Deploy scripts, Install-Bot, Install-Voice,
Install-Runner, Go and Build-Launcher. Each runs the real one with the same
arguments. They go after the next main release.

Files a machine keeps here and git never sees (`setup-stub.exe`,
`signing.json`, `backup-key.txt`, `thornswood-front.zip`) stay where they
are; the scripts still look for them in this folder.
