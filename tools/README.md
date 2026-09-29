# tools

Nothing to run here. The scripts are in `scripts\<area>` since 25 September
(issue #440, phase 8): `scripts\release`, `scripts\deploy`, `scripts\vps`,
`scripts\ops`, `scripts\mods` and `scripts\dev`, with `scripts\README.md`
listing every one. The build records and the signing setup are in `records\`.

The forwarding copies that kept `.\tools\Ship.ps1` and the other common
commands working went on 28 September, once main release 1.1.101 had gone
out from the new layout. Type the new path:

| Was | Is |
| --- | --- |
| `.\tools\Ship.ps1` | `.\scripts\release\Ship.ps1` |
| `.\tools\Bump-Version.ps1` | `.\scripts\release\Bump-Version.ps1` |
| `.\tools\Build-Launcher.ps1` | `.\scripts\release\Build-Launcher.ps1` |
| `.\tools\Go.ps1` | `.\scripts\release\Go.ps1` |
| `.\tools\Deploy-DevGamemode.ps1` | `.\scripts\deploy\Deploy-DevGamemode.ps1` |
| `.\tools\Deploy-Gamemode.ps1` | `.\scripts\deploy\Deploy-Gamemode.ps1` |
| `.\tools\Deploy-Server.ps1` | `.\scripts\deploy\Deploy-Server.ps1` |
| `.\tools\Deploy-Docs.ps1` | `.\scripts\deploy\Deploy-Docs.ps1` |
| `.\tools\Install-Bot.ps1` | `.\scripts\deploy\Install-Bot.ps1` |
| `.\tools\Install-Voice.ps1` | `.\scripts\deploy\Install-Voice.ps1` |
| `.\tools\Install-Runner.ps1` | `.\scripts\deploy\Install-Runner.ps1` |
| `tools\Vps.ps1` (dotsourced) | `scripts\vps\Vps.ps1` |

What this folder still holds is only what a machine keeps here and git never
sees. The scripts look for these here:

| File | What it is | Read by |
| --- | --- | --- |
| `signing.json` | Whether this machine signs, and with what. No key in it | Sign-Artifact, Ship, Publish-Installer |
| `setup-stub.exe`, `setup-stub.pdb` | The setup program, compiled by Build-Launcher | Package-Thornswood, Ship |
| `backup-key.txt` | A copy of the backup passphrase, a secret | Restore-Backup |
| `thornswood-front.zip` | The front build, made outside the repository | Go |
| `mod-audit.json` | What Audit-Mods found last time | Audit-Mods |

Moving these out as well, so that `tools\` goes altogether, is the next phase
of issue #440.
