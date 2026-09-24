# Credits

Thornswood is a free fan project. Nobody is paid and nothing is sold.

## Standing on

**SkyMP** is the multiplayer engine underneath all of this. Skyrim was never
built to be played together, and SkyMP is the reason it can be at all.

**SKSE** and **Skyrim Platform**, which everything else in turn stands on.

**Bethesda Game Studios**, for the game. Thornswood is not affiliated with or
endorsed by Bethesda Softworks. The Elder Scrolls and Skyrim are their
trademarks, and you need your own copy to play.

## The mod list

Every mod in Thornswood was made by somebody who gave it away. The full list is
in the launcher, and each one links to its own page. Go and endorse the ones
you like.

<a id='source'></a>

## Source code

SkyMP is free software, and Thornswood ships part of it. The installer and the
launcher's updates put six SkyMP files into your Skyrim folder, and the server
you connect to runs on SkyMP as well. All of it is built from Thornswood's
public copy of SkyMP, with Thornswood's changes on top:

**[github.com/EvilPatrick06/skymp](https://github.com/EvilPatrick06/skymp)**, on
the branch `thornswood/engine-changes`. Anybody can read it or download it,
with no account.

The current release is built from commit
[`c8832519`](https://github.com/EvilPatrick06/skymp/tree/c8832519866e6848b9501039940dc2c6f0508668),
the six files and the server's engine alike. That commit starts from
[SkyMP](https://github.com/skyrim-multiplayer/skymp) at `f926944b`, and
[every change Thornswood made](https://github.com/EvilPatrick06/skymp/compare/f926944b...c8832519)
is the difference between the two.

| File | Built from | Licence |
|---|---|---|
| `skymp5-client.js` | `skymp5-client` | GNU GPL version 3 |
| `SkyrimPlatform.dll` | `skyrim-platform` | GNU GPL version 3 |
| `SkyrimPlatformImpl.dll` | `skyrim-platform` | GNU GPL version 3 |
| `SkyrimPlatformCEF.exe.hidden` | `skyrim-platform` | GNU GPL version 3 |
| `TESModPlatform.pex` | `skyrim-platform` | GNU GPL version 3 |
| `MpClientPlugin.dll` | `skymp5-server` | GNU AGPL version 3 |
| `scam_native.node`, the server's engine | `skymp5-server` | GNU AGPL version 3 |

Each licence is the `LICENSE` file in that folder of the repository.
