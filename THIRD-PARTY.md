# Third-party notices

This file lists what Thornswood hands to people that somebody else wrote, the
licence each part is under, and where its source is. Every row was read off the
files on 24 September 2026. Licences come from each component's own licence
file or from a font's own name table. Where a file came from was checked by
comparing its sha256 with the copy it came from. Where something could not be
identified, this file says so instead of guessing.

This file does not license Thornswood's own code. The repository has no licence
of its own, and choosing one is Patrick's decision.

`tools\test-third-party.js` checks this file against the build. It covers every
resource Build-Launcher.ps1 compiles into the launcher, every file under
`tools\lib`, the six client files and the commits in `tools\client-build.json`
and `tools\server-build.json`, and the source paragraph on the public credits
page. When a rebuild records a new commit, this file and
`tools\docs-app\data\site\credits.md` have to change in the same pull request,
or the build check goes red.

## How it reaches people

- **The launcher**, `Thornswood.exe`, from the update feed and inside the
  installer. Build-Launcher.ps1 compiles everything it needs into the one file.
- **The client runtime**, the six files in `tools\client-build.json`. They go
  out as `client-runtime-<commit>.zip` on the feed (Publish-Update.ps1), and
  in game packs and the installer.
- **Game packs and the installer payload**: every file in the game folder that
  the collection did not provide and Ship-Rules.ps1 does not hold back.
- **The game server** runs on the VPS. Nobody receives a copy, but the AGPL
  still asks for its source to be offered to everybody who connects.

Everything else Build-Launcher.ps1 compiles into the launcher is Thornswood's
own: `ui.xaml`, `logo.png`, `launcher-header.jpg`, `launcher-header.mp4`,
`app.ico`, `voice-host.html`, `Thornswood.ini` and `client-build.json`. The
setup stub, `Thornswood-Setup.exe`, is `tools\setup\Bootstrap.cs` and
`logo-192.png`, also Thornswood's own.

## Microsoft WebView2 SDK, inside the launcher

Three files from `tools\lib\webview2`. Build-Launcher.ps1 references them for
the compile and embeds them as resources. Voice.cs hands the two managed ones to
the runtime from memory and writes `WebView2Loader.dll` beside the exe on start.
They give the launcher the browser that voice runs in.

| File | Where it sits in the package | sha256 |
|---|---|---|
| `Microsoft.Web.WebView2.Core.dll` | `lib\net462` | `88a3b62f45225a811cdb85df6dfd95c2bff9a0e43e3b04f813b125eaca56cc9f` |
| `Microsoft.Web.WebView2.Wpf.dll` | `lib\net462` | `1c5b6c792916d168093ef9b836f33e818d2d15d0c81f0864b5cddff97d913319` |
| `WebView2Loader.dll` | `runtimes\win-x64\native` | `462b36fd1be6ca9f7563466a89e57c41ef4a4def3e0a84fa885d203aea4a3aaf` |

Version 1.0.2903.40, the file version all three carry. All three are byte for
byte the same files as in Microsoft.Web.WebView2 1.0.2903.40 as nuget.org
serves it, downloaded and compared on 24 September.

Licence: the package's own `LICENSE.txt`, which its nuspec names as the licence
(`<license type="file">LICENSE.txt</license>`). It is a three-clause BSD-style
licence from Microsoft, and the package gives no SPDX identifier for it. Its
second clause asks for the notice to go with every binary copy, so it is
reproduced in full at the end of this file and on the public credits page.

Not shipped by Thornswood: the WebView2 Runtime itself. When a machine has
none, the launcher downloads Microsoft's own bootstrapper from Microsoft's link
(Voice.cs) and runs it, under Microsoft's terms.

## The SkyMP client runtime, built from the fork

The six files recorded in `tools\client-build.json` are built from
https://github.com/EvilPatrick06/skymp, branch `thornswood/engine-changes`,
commit `c8832519` (in full, `c8832519866e6848b9501039940dc2c6f0508668`). That
is upstream skyrim-multiplayer/skymp at `f926944b` with Thornswood's changes on
top. The copies in `C:\Thornswood\Game` matched the recorded sha256 of all six
on 24 September.

| File | Built from, in the fork | Licence |
|---|---|---|
| `Data\SKSE\Plugins\MpClientPlugin.dll` | `skymp5-server`, the MpClientPlugin target in `skymp5-server\cpp\CMakeLists.txt`: sources in `cpp\client`, linked with `mp_common` and `server_guest_lib` | AGPL-3.0 |
| `Data\SKSE\Plugins\SkyrimPlatform.dll` | `skyrim-platform`, target skyrim_platform_entry | GPL-3.0 |
| `Data\Platform\Distribution\RuntimeDependencies\SkyrimPlatformImpl.dll` | `skyrim-platform`, target skyrim_platform | GPL-3.0 |
| `Data\Platform\Distribution\RuntimeDependencies\SkyrimPlatformCEF.exe.hidden` | `skyrim-platform`, target SkyrimPlatformCEF | GPL-3.0 |
| `Data\Platform\Plugins\skymp5-client.js` | `skymp5-client` | GPL-3.0 |
| `Data\Scripts\TESModPlatform.pex` | `skyrim-platform`, from `src\platform_se\psc\TESModPlatform.psc` | GPL-3.0 |

MpClientPlugin.dll is the one to notice. It goes to every client, and it is
built from skymp5-server, whose licence is the AGPL, not the GPL.

The licence names are the ones each subproject's `package.json` declares:
`GPL-3.0` for skymp5-client, skyrim-platform and skymp5-front, and `AGPL-3.0`
for skymp5-server. The `LICENSE` file in the first three is the GNU General
Public License version 3 of 29 June 2007. The one in skymp5-server is the GNU
Affero General Public License version 3 of 19 November 2007. No source file in
those four subprojects carries a notice saying "only" or "or any later
version", so this file does not say either.

What is compiled into them:

- Upstream's `THIRD_PARTY_LICENSES`, at the root of the fork, names TiltedUI,
  TiltedCore, TiltedHooks and TiltedReverse: "Copyright (c) 2019 Tilted
  Phoques. All Rights Reserved.", made available "AS IS", and "Do not remove or
  modify any license notices." Their code is under `skyrim-platform\src\tilted`.
- The fork's own libraries. SkyrimPlatformImpl links `papyrus-vm` and `viet`
  (MIT, by their LICENSE files), `savefile` (GPL-3.0) and `serialization`,
  which has no licence file of its own.
- The libraries in the fork's `vcpkg.json`, linked in by the build. Among them
  is the Chromium Embedded Framework (cef-prebuilt 108.4.13), which
  SkyrimPlatformCEF and SkyrimPlatformImpl link against. vcpkg copies each
  port's licence text to `build\vcpkg_installed\x64-windows-sp\share\<port>\copyright`
  in the fork's build folder. Read on 24 September, two of them are worth
  knowing about: antigo's is the GNU Lesser General Public License version 3,
  and frida-gum's is the wxWindows Library Licence 3.1. The others are
  permissive texts such as MIT, BSD, Boost, Apache 2.0 and zlib.
  None of those texts travels with the client runtime today.

## From upstream SkyMP, not built here

These ship in packs and the installer. Each was compared by sha256 with the
fork wherever the fork has a copy.

| File | What it is | Licence |
|---|---|---|
| `Data\Scripts\MpClientPlugin.pex` | Byte for byte the fork's `client-deps\common\Data\Scripts\MpClientPlugin.pex`. | `client-deps` has no licence file of its own. Upstream's `TERMS.md` says SkyMP is "primarily distributed under the GPLv3 and AGPLv3 licenses". |
| `Data\Platform\Fonts\Tavern.ttf` and `Tavern.spritefont` | Byte for byte the fork's `client-deps\common\Data\Platform\Fonts` copies. The font calls itself Typey McTypeface, by Paul J. Miller (2016) and Dieter Steffmann (1995). | SIL Open Font License, by the font's own licence field and by upstream's `THIRD_PARTY_LICENSES`. Neither gives the version. |
| `Data\Platform\Fonts\DIN-Pro-bold.spritefont` | Byte for byte the fork's `client-deps` copy: a sprite font whose name says DIN Pro Bold. | None found. DIN Pro is FSI FontShop's typeface, whose own files point at FontFont's end user licence (below), and upstream names no licence for this file. |
| `Data\Platform\Modules\skyrimPlatform.ts` | skyrim-platform's TypeScript declarations, an older copy (136,561 bytes) than the fork builds (136,768). | GPL-3.0 |
| `Data\Platform\UI\build.js` | A development build of `skymp5-front`, dated 13 September 04:33 in the game folder. It was not built here, and nobody recorded the commit it came from. It bundles npm packages under their own licences, among them React 16.13.1 and 17.0.2, MIT by the `@license` comments inside it. | GPL-3.0 |
| The 68 files beside build.js that it names by hash | Its fonts, sounds and pictures. 26 are byte for byte files in the fork's `skymp5-front\src`. | As build.js, except the fonts below. |
| 42 more files beside build.js that it does not name | Byte for byte pictures from the fork's `skymp5-front\src` (41 dated 14 September, `bg.png` dated 13 September). They are dead weight. | GPL-3.0 |

The fonts in that front build, from their own name tables. All six are byte for
byte the files in upstream's `skymp5-front\src\fonts`:

| File | Font | What the file says |
|---|---|---|
| `6f802bf60c545304b09e.ttf` | Futura PT Cond Book | "ParaType Ltd", licence http://www.paratype.com/eula |
| `00e4a2200c3e5ae71d67.ttf` | Futura PT Cond Medium | "ParaType Ltd", licence http://www.paratype.com/eula |
| `268a0df3f0e2c23d1ea6.ttf` | DIN Pro Regular | "FSI FontShop International GmbH", licence http://www.fontfont.com/eula/license.html |
| `fdf086661e1600f95a34.ttf` | DIN Pro Condensed Bold Italic | "FSI FontShop International GmbH", licence http://www.fontfont.com/eula/license.html |
| `855bfaf67c57745958d3.ttf` | Bankir-Retro | "Copyright (c) Gophmann A.L., 2006. All rights reserved." Upstream's `THIRD_PARTY_LICENSES` calls it "free". |
| `d213051bb6f28a25fb26.ttf` | icomoon | An icon font with no copyright or licence in it. |

Futura PT and DIN Pro point at their foundries' end user licences. This file
found nothing that gives SkyMP or Thornswood the right to hand them on, and
upstream names none. Upstream SkyMP ships them the same way.

## Shipped today with no licence this file can name

These are neither Thornswood's nor traceable to SkyMP. They ship because they
sit in the game folder and the rules in Ship-Rules.ps1 count them as ours.
Under `Data\Platform\UI` every flat file counts as ours (the UI rule in
Test-ShipOtherServer), and no rule looks at `Fonts` or `Images`. The installer
built on 23 September carries every one of them.

- `Data\Platform\UI`: 37 files, 16.2 MB, dated 14 September 14:51 to 14:56.
  Three are EB Garamond fonts, whose own name table says SIL Open Font License.
  The rest are 11 .jpg, 22 .png and `menu_theme.mp3`. Neither build.js nor any
  Thornswood file names them, and none is in the fork. They look like another
  server's menu.
- `Data\Platform\Fonts\ChainLink.spritefont`, `Futura.spritefont`,
  `NoticeIcon.spritefont` and `VoiceIcon.spritefont`, dated 14 September
  14:44. skyrim-platform loads every .spritefont in that folder
  (DX11RenderHandler.cpp), but neither skymp5-client nor any Thornswood script
  asks for these by name. Nothing in them says what font they were made from
  or under what licence.
- `Data\Platform\Images\lock.png` and `speaking.png`, dated 12 September 13:40.
  They are not in the fork, and nothing names them.
- Files from other people's mods (loose textures, meshes, scripts and interface
  files). That is To Do List entry 168. A notices file does not give anybody
  the right to hand them on, and this one does not try. Package-Thornswood.ps1
  names the loose textures and meshes it is about to ship, a folder at a time
  with its size (Get-ShipLooseArt in Ship-Rules.ps1), and refuses none of them.
- Bethesda's `MarketplaceTextures.bsa` went out in every pack and in the
  23 September installer. Ship-Rules.ps1 now holds it back from both
  (Test-ShipBethesdaLeftAlone) without deleting anybody's copy, so builds made
  after that change no longer carry it.

## Made for Thornswood by somebody else

- `Data\Platform\UI\thornswood-theme.mp3` (in the repo as
  `tools\ts-ui\thornswood-theme.mp3`) is the theme. It was made for Thornswood
  by an artist this repository does not name, and it went to everybody on
  Patrick's word of 22 September (commit ec8d113). The terms are between
  Patrick and the artist and are not written down here.

## Not shipped by Thornswood

- The collection. Each person installs every mod from Nexus Mods through
  Vortex, under its author's own terms. The launcher lists every one with a
  link to its page (`tools\app\Links.cs`), and the public credits page says so.
  The mod files the installer carries anyway are entry 168, above.
- SKSE, which is in the collection, and Skyrim Special Edition, which each
  person owns.
- The Chromium Embedded Framework and Node runtime under
  `Data\Platform\Distribution` (`libcef.dll`, `libnode.dll` and the rest). The
  collection deploys them: their origin is V in `Profile\OwnGame\files.txt`.
  Only `SkyrimPlatformImpl.dll` and `SkyrimPlatformCEF.exe.hidden` in that
  folder are Thornswood's builds.
- The WebView2 Runtime, which comes from Microsoft.

## On our servers

- The game server's native module, `scam_native.node`, recorded in
  `tools\server-build.json`. It is built from `skymp5-server` in the fork at the
  same commit, `c8832519866e6848b9501039940dc2c6f0508668`, and it is AGPL-3.0.
  Section 13 of the AGPL asks that everybody who connects to a modified server
  over a network be offered its source. The next section is that offer.

## Where the source is

For the six client files and the game server module, the Corresponding Source
is the fork at the recorded commit:

https://github.com/EvilPatrick06/skymp/tree/c8832519866e6848b9501039940dc2c6f0508668

It is on the branch `thornswood/engine-changes`, it is public, and it answered
an anonymous request on 24 September. It builds with CMake and vcpkg from the
fork's `vcpkg.json`. The licence texts are in the same tree:
`skymp5-client/LICENSE`, `skyrim-platform/LICENSE` and `skymp5-server/LICENSE`.

That covers what Thornswood built. It does not cover
`Data\Platform\UI\build.js`. Its source is upstream's `skymp5-front`, at
https://github.com/skyrim-multiplayer/skymp, but nobody recorded which commit
it was built from.

## What is still missing

- Nothing hands a person the GPL or AGPL text, this list or the WebView2 notice
  together with the files. The installer's `READ ME FIRST.txt` and the release
  pages say nothing about source. That is entry 170.
- The vcpkg licence texts do not travel with the client runtime.
- build.js has no recorded source commit.
- The Futura PT, DIN Pro and Bankir-Retro fonts, and the files under "Shipped
  today with no licence this file can name", ship with no licence found.

## Microsoft WebView2 SDK licence

The text of `LICENSE.txt` in Microsoft.Web.WebView2 1.0.2903.40, as the package
carries it.

```
Copyright (C) Microsoft Corporation. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

   * Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.
   * Redistributions in binary form must reproduce the above
copyright notice, this list of conditions and the following disclaimer
in the documentation and/or other materials provided with the
distribution.
   * The name of Microsoft Corporation, or the names of its contributors
may not be used to endorse or promote products derived from this
software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```
