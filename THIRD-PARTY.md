# Third-party notices

This file lists what Thornswood hands to people that somebody else wrote, the
licence each part is under, and where its source is. Every row was read off the
files on 24 September 2026. Licences come from each component's own licence
file or from a font's own name table. Where a file came from was checked by
comparing its sha256 with the copy it came from. Where something could not be
identified, this file says so instead of guessing.

This file does not license Thornswood's own work. That is `LICENSE` at the
root: all rights reserved, with terms every contributor agrees to once
(decided by Patrick on 12 Oct 2026, #1331).

`tests\test-third-party.js` checks this file against the build. It covers every
resource Build-Launcher.ps1 compiles into the launcher, every file under
`launcher\lib`, every font and minified script the site serves from
`site\public`, the six client files and the commits in
`records\client-build.json` and `records\server-build.json`, the two
libraries the fork links that are not permissive, and the source paragraph on
the public credits page. Where Vortex's copy of the Thornswood
Client Runtime and the launcher's `Profile\OwnGame\files.txt` are on the
machine, it also holds the section on that mod to every file in it. When a
rebuild records a new commit, this file and
`site\data\site\credits.md` have to change in the same pull request,
or the build check goes red.

## How it reaches people

- **The launcher**, `Thornswood.exe`, from the update feed and inside the
  installer. Build-Launcher.ps1 compiles everything it needs into the one file.
- **The client runtime**, the six files in `records\client-build.json`. They go
  out as `client-runtime-<commit>.zip` on the feed (Publish-Update.ps1), and
  in game packs and the installer. The zip carries a `README.txt` saying where
  their source is, with `GPL-3.0.txt` and `AGPL-3.0.txt` beside it, and so
  does every pack that carries a SkyMP file, as `SOURCE CODE.txt`
  (Source-Notice.ps1). The launcher takes only the game files out of either.
- **Game packs and the installer payload**: every file in the game folder that
  the collection did not provide and Ship-Rules.ps1 does not hold back.
- **Nexus Mods**, through the collection
  (https://www.nexusmods.com/games/skyrimspecialedition/collections/7essxf).
  Most of what Vortex installs from it is other people's mods, under their own
  terms. Two of them are Thornswood's own uploads, by EvilPatrick06, and
  Vortex installs both for everybody who installs the collection: Thornswood
  Content (mod 192001) and Thornswood Client Runtime (mod 192762). Each has
  its own section below. What the collection provides stays out of the
  installer and the packs (Get-ShipOwnGameCollection in Ship-Rules.ps1), so
  the collection is the only way these reach anybody, with one exception: since
  3 October every pack and the installer, on both channels, carry our own
  `Thornswood-Content.esp`, the repository's file at the commit the release is
  built from, over the collection's copy (`$ShipOursFiles` in Ship-Rules.ps1).
  The Thornswood Content section says which plugin each channel carries.
- **The game server** runs on the VPS. Nobody receives a copy, but the AGPL
  still asks for its source to be offered to everybody who connects.
- **The site**, thornswood.net, hands every visitor's browser the files in
  `site\public`, among them the fonts and the markdown renderer
  listed under "On the site".

Everything else Build-Launcher.ps1 compiles into the launcher is Thornswood's
own: `ui.xaml`, `logo.png`, `logo-dev.png`, `launcher-header.jpg`,
`launcher-header.mp4`, `app.ico`, `app-dev.ico`, `voice-host.html`,
`Thornswood.ini`, `client-build.json`, `skyrim-files.json`, the list of
the pinned Skyrim build's own file names, sizes and SHA-1s read out of Steam's
depot manifests (no Bethesda file is in it), and `ui-gone.json`, the Daedric
menu set and unused fork assets a refresh must not copy back. `logo-dev.png` is the emblem the dev
build shows in place of `logo.png` (Art.cs) and `app-dev.ico` is the icon its
shortcuts carry in place of `app.ico` (Icons.cs); both are drawn for
Thornswood, the same as the two they stand in for. The setup stub,
`Thornswood-Setup.exe`, is `installer\setup\Bootstrap.cs` and `logo-192.png`,
also Thornswood's own.

## Microsoft WebView2 SDK, inside the launcher

Three files from `launcher\lib\webview2`. Build-Launcher.ps1 references them for
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

The six files recorded in `records\client-build.json` correspond to
https://github.com/EvilPatrick06/skymp, branch `thornswood/engine-changes`,
commit `3bdf3d3c` (in full, `3bdf3d3c9926a4dd241b1d1c09dadde808a788d5`). That
is upstream skyrim-multiplayer/skymp at `2849e676` with Thornswood's changes on
top. Check-Secrets.ps1 stops a release whose copy of any of the six is not the
recorded sha256 (client-not-recorded-build), and Sync-Client.ps1 puts in the
recorded build.

The six client files were rebuilt locally. The native server and its
JavaScript bundle were built from the same merged source, including the
atomic quest inventory and state transaction. The generated client and
server records give each file's hash and source commit. The older reuse
described in `records\merchant-runtime-provenance.md` is historical.

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
  SkyrimPlatformCEF and SkyrimPlatformImpl link against. CEF's own runtime
  files do not go out with these six: they are the Thornswood Client Runtime
  mod on Nexus Mods, below. vcpkg copies each
  port's licence text to `build\vcpkg_installed\x64-windows-sp\share\<port>\copyright`
  in the fork's build folder. Read on 24 September, two of them are not
  permissive, antigo and frida-gum, below. The others are permissive texts
  such as MIT, BSD, Boost, Apache 2.0 and zlib. None of those texts travels
  with the client runtime today.

The two libraries whose licences are not permissive, measured on 5 October
against the fork at `0460584e` and the recorded files (#1332). The fork's
triplet links every vcpkg library statically
(`overlay_triplets\x64-windows-sp.cmake`), so a library's code is inside a
file or it is not there at all.

| Library | Licence | Where its code is |
|---|---|---|
| antigo, https://github.com/nic11/antigo at `da15297955935da32e455fc1ca2a12faf564caae` (`overlay_ports\antigo`) | LGPL-3.0, by its `LICENSE` and the port's `vcpkg.json` | Only in `scam_native.node`, the game server's module |
| frida-gum 16.0.19 (`overlay_ports\frida-gum`), Frida's own built devkit, from https://github.com/frida/frida-gum at `698b356fef0ecfc3ac2818f0b387be90e93deeda`, the commit Frida 16.0.19 names for it | wxWindows Library Licence 3.1 | In `SkyrimPlatformImpl.dll` |

antigo is a trace logging library. The build links it into
`MpClientPlugin.dll` as well (`skymp5-server\cpp\CMakeLists.txt` adds it to
every target in `VCPKG_DEPENDENT`), but nothing in the client calls it, so the
linker leaves it out. The only fork files that use it are the server's
`addon\ScampServer.cpp` and `server_guest_lib\MpObjectReference.cpp` and
`WorldState.cpp`. `MpClientPlugin.dll` takes `server_guest_lib` for its
inventory code only, and none of the messages in those two files is in the
recorded `MpClientPlugin.dll`. Nor is any of antigo's own (`resolved context
with`, `stringstream error!`), while the recorded `scam_native.node` has every
one of them. So no file anybody receives carries antigo. The LGPL asks for its
notice, its text and a way to relink only where a copy is handed to somebody,
and running the server hands nobody a copy: it asks nothing of Thornswood
today. #1332 said this repository holds an `LGPL-3.0.txt`. It has none, and
none is owed. The day a client file calls antigo, the LGPL's notice and text
have to go with that file, and `tests\test-third-party.js` fails when a fork
file outside those three starts using it.

frida-gum is Skyrim Platform's function hooking (`FridaHooks.cpp`,
`FridaHookHandler.cpp`), and `GumInterceptor` is in the recorded
`SkyrimPlatformImpl.dll`, so it goes to everybody. Its licence, the `COPYING`
file at that commit, which the port fetches as its copyright file, is the GNU
Library General Public Licence with an exception that lets a binary built with
it go out under the distributor's own terms. So it asks nothing more of
`SkyrimPlatformImpl.dll`, which goes out under the GPL with its source offered
below.

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
| The files beside build.js that it names by hash | Its fonts, sounds and pictures. 26 are byte for byte files in the fork's `skymp5-front\src`. Ship parses the names from build.js at pack time (#1318); it does not keep a count by hand. | As build.js, except the fonts below. |

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

## Thornswood Client Runtime, Thornswood's mod on Nexus Mods

Thornswood publishes this itself, as its own mod: Nexus Mods mod 192762,
https://www.nexusmods.com/skyrimspecialedition/mods/192762, by EvilPatrick06.
Revision 5 of the collection carries version 1.0.0, file 809366, uploaded on
22 September, and it is not optional. The collection's `collection.json`
records the download as 148,896,610 bytes, md5
`c515679068f6563750b1ca1f9260031f`.

It is the largest thing somebody else wrote that Thornswood hands out: 68
files, 366,157,850 bytes, into `Data\Platform\Distribution`, and a README and
six licence texts into `Data\Docs\Thornswood Client Runtime`. Read on
24 September: Vortex's copy, in the staging folder `Thornswood Client Runtime
192762 1.0 2026-09-22T22-17Z`, matched the 68 in `C:\Thornswood\Game` by
sha256, and `Profile\OwnGame\files.txt` gives the collection as the origin of
all 68. 67 of them are byte for byte the files the fork's build puts in
`build\dist\client\Data\Platform\Distribution`. `___systemPolyfill.js` is the
one that is not, and it has its own paragraph below.

`SkyrimPlatformImpl.dll` and `SkyrimPlatformCEF.exe.hidden` are left out of the
mod on purpose. They are two of the six recorded files above, and they come
with the launcher, which checks them against its own record.

What is in it, by path under `Data\Platform\Distribution`. Each version is the
file's own version resource, or for ICU the name inside the data, and each
agrees with the mod's README wherever the README gives one.

| Part | Version | Files | Licence | Its text in the mod |
|---|---|---|---|---|
| Chromium Embedded Framework, and Chromium | CEF 108.4.13+ga98cd4c, Chromium 108.0.5359.125 | `RuntimeDependencies\libcef.dll`, `chrome_elf.dll`, `snapshot_blob.bin` and `v8_context_snapshot.bin`; `CEF\chrome_100_percent.pak`, `chrome_200_percent.pak` and `resources.pak`; 55 `CEF\locales\*.pak` | BSD-3-Clause | `CEF-LICENSE.txt`, `Chromium-LICENSE.txt` |
| ICU data | ICU 71, by the name inside the file, `icudt71l` | `RuntimeDependencies\icudtl.dat` | Unicode's licence, below | `ICU-LICENSE.txt` |
| ANGLE | 2.1.19724, git ceec659ac60b | `RuntimeDependencies\libEGL.dll`, `libGLESv2.dll` | BSD-3-Clause | `ANGLE-LICENSE.txt` |
| Node.js | 23.2.0 | `RuntimeDependencies\libnode.dll` | MIT, with the licences of the libraries built into it | `Node-LICENSE.txt` |
| Microsoft Direct3D HLSL Compiler | 10.0.20348.1 | `RuntimeDependencies\d3dcompiler_47.dll` | Microsoft's own. The file describes itself as "Direct3D HLSL Compiler for Redistribution", by Microsoft Corporation. | None |
| Skyrim Platform | upstream's last copy, below | `___systemPolyfill.js` | GPL-3.0 | `SkyrimPlatform-LICENSE.txt` |

The programs, the ICU data and the script, by sha256:

| File | Bytes | sha256 |
|---|---|---|
| `RuntimeDependencies\libcef.dll` | 191,842,816 | `52aa8b457a5f174d0a51509da4dc8e128b6b4bb476b800bab6c7eb9c109219be` |
| `RuntimeDependencies\libnode.dll` | 109,094,912 | `f22c87fa55e3c0e8b5626fd94c801ba7f1bf581e6fa555ce702c44e553d2d210` |
| `RuntimeDependencies\icudtl.dat` | 10,462,432 | `97b978a19edd4746e9a44d9a44bb4bc519e127a203c247837ec0922f573449e3` |
| `RuntimeDependencies\libGLESv2.dll` | 7,493,120 | `49ee2a4800a8eba183169152ecd5550b8d55989785e2f44a7de04930dcb3d7ef` |
| `RuntimeDependencies\d3dcompiler_47.dll` | 4,891,080 | `e4bc3420a28069bd13dc3be725d46676a7c0e99de221026e8c43cd6f7ed45c0b` |
| `RuntimeDependencies\chrome_elf.dll` | 1,411,072 | `4f5f1dc6d998b07e3919055b6f9cc8befc626d30479c7c2d07722051650491a0` |
| `RuntimeDependencies\libEGL.dll` | 474,624 | `1100398a3fe57da76ea58b9b110be2f6a83a75a3e1863863f086d9218b46cc5a` |
| `___systemPolyfill.js` | 2,605 | `38320fb897314ae7471bdab749f00442c00913f14d7b8f82bc793b3c2b669188` |

Chromium and Node build other people's libraries into these files.
`Node-LICENSE.txt`, 139,053 bytes, carries the licence of every library built
into libnode.dll. For Chromium the README points at Chromium's own source at
108.0.5359.125, where each component keeps its LICENSE file. No list of those
travels with the mod.

`icudtl.dat` is ICU 71's data. The `ICU-LICENSE.txt` beside it is the Unicode
License V3, with a copyright line that runs from 1991 to 2026. That is the text
of a far later ICU than 71, which came out in 2022.

`___systemPolyfill.js`, 2,605 bytes, is the SystemJS module loader that Skyrim
Platform used to run before a plugin's `index.js`. Line endings aside, it is
upstream's `skyrim-platform/tools/system_polyfill/dist/___systemPolyfill.js`,
which did not change from 28 June 2023 until upstream removed that folder on
1 June 2026 (commit `ceba28bc`, "drop system-polyfill, multifile plugins &
other deprecated features", #2711). That removal comes before `2849e676`, the
upstream commit the fork starts from. So the fork at the recorded commit has
no such file, no file there names it, its build does not make it, and nothing
in the client Thornswood ships asks for it. It reaches everybody who installs
the collection anyway. The folder's own `package.json` names no licence. It is
part of skyrim-platform, whose `package.json` says `GPL-3.0`, and the mod's
`SkyrimPlatform-LICENSE.txt` is byte for byte skyrim-platform's `LICENSE`, the
GNU General Public License version 3, 35,149 bytes. Its source is under "Where
the source is".

## Thornswood Content, Thornswood's other mod on Nexus Mods

Nexus Mods mod 192001,
https://www.nexusmods.com/skyrimspecialedition/mods/192001, by EvilPatrick06.
Its one main file is version 1.2, Nexus file 811029, an archive of 660,022
bytes uploaded on 26 September; 1.0 and 1.1 are old files. Collection revision
2 (`7essxf`, published 3 October) pins that exact file and carries a patch of
its own for the plugin, `patches\Thornswood Content\Thornswood-Content.esp.diff`
(207 bytes, bsdiff), which Vortex applies after it installs the mod. Read on
12 October from the 1.2 archive Vortex downloaded, the installed revision 2
collection and Vortex's staging folder on the shipping machine:

| File | Bytes | sha256 |
|---|---|---|
| `Thornswood-Content.esp`, as the 1.2 archive has it | 141,442 | `988b6d00e86d9e58b67a0da5f6ea145976a33a4ecee6bc814505fc98b6fcc112` |
| `Thornswood-Content.esp`, as the collection installs it | 141,023 | `4b004dce782573445381ef013be7e6984c4df09c31a3af7234242f6f2acc7f58` |
| `SKSE\Plugins\SkyrimSoulsRE.ini` | 7,009 | `a787ecc3e13ec6ca55719ff25e544fa8b5bcee09734e2c19d5cf5defebf3815a` |
| `SKSE\Plugins\OpenAnimationReplacer.ini` | 1,165 | `328ce7e0412685bb8cab1fa0d81b5bdbf9f805b6d8f3f76e92662ca2b418403c` |
| `meshes\actors\character\facegendata\facegeom\FishingInSkyrim.esp\00025905.nif` | 286,140 | `5353f567eb73684f48e085e31276db2d33ec5bdbe9cd17d2f1ff264e22f21ba5` |
| `meshes\actors\character\facegendata\facegeom\FishingInSkyrim.esp\0002a07c.nif` | 247,584 | `82d7309d6997cc6cdc63c396ecc18dde35e7b438dc96b756c66491e29120b0cc` |
| `textures\actors\character\facegendata\facetint\FishingInSkyrim.esp\00025905.dds` | 1,048,704 | `0fd4584d9f06ffde6d77adbf1037c4143dde3fca2d082473e73c0536ac109d3c` |
| `textures\actors\character\facegendata\facetint\FishingInSkyrim.esp\0002a07c.dds` | 1,048,704 | `31b0fee7b2aba7d1d6ad26df96995698603a5d021cc35d14fb52a05cfb6b85fb` |

- `Thornswood-Content.esp`, Thornswood's own plugin. The collection's
  `collection.json` patches only the file whose crc32 is `023593E0`, which is
  the archive's copy. Applying the patch to that copy gives the 141,023 bytes
  above exactly, and Vortex's staging copy is the same bytes. That is the
  collection's base: the plugin #954 rebuilt, 382 records, with no Execution
  Block and no editor id or script named for another server (#400). Its
  header's description still names the SkyMP server the records were
  salvaged from, and so does the description of the release plugins in the
  table below. The repository's plugin carries Thornswood's own description
  since 15 October (#400, Patrick: the name is mentioned nowhere): "Thornswood's
  crafting and gathering content: stations, salt, ore, charcoal kilns, skill
  manuals, tools, keys, fishing, repair kits, treatments, the notice board and
  drop box, house parts, and their recipes." The collection's copy keeps the
  old one until a later revision patches it. Until 12 October this
  section gave the 1.1 file as read on 24 September, 141,234 bytes, sha256
  `3b3ecb3bda4b97e312df10a61191cdd2949286007ab03a948b323d4a749af2ae`.
- `SKSE\Plugins\SkyrimSoulsRE.ini`: Skyrim Souls RE's own settings file (mod
  27859) with one line changed, `bTweenMenu = false`. The rest is as that
  mod's author wrote it. Revision 2 removed Skyrim Souls RE itself
  (docs\COLLECTION-REVISION-2.md), so nothing in the collection reads this
  file now.
- `SKSE\Plugins\OpenAnimationReplacer.ini`: the settings file Open Animation
  Replacer (mod 92109, in the collection) writes, holding the values Thornswood
  wants.
- The four face files: the face meshes and face tints the Creation Kit exports
  for two people Fishing In Skyrim Special Edition (mod 47618, in the
  collection) adds, Rybek Kupiecski (`FishingVendorPolish`, 00025905) and
  Lillani (`FISLillani`, 0002A07C). The four are dated 26 September and
  are made from that mod's records.

The settings files and the faces belong with mods that are, or were, in the
collection. This file did not read those mods' permissions.

### The plugin each channel carries

The game does not run the collection's copy of the plugin. Every pack and the
installer put the repository's `game\content\Thornswood-Content.esp`, as it
was at the commit the release was built from, into Thornswood's own game
folder in place of the collection's (How it reaches people). The launcher
refuses Play while a copy differs from the one its server holds, and a Ship
whose plugin changed stops until that channel's server holds the same file
(#2308). Both channels carry the same plugin. Read on 12 October from the
feeds, the release tags, the dev and main game folders on the shipping machine,
both servers' manifests (the size and crc32 each lists match the file below)
and the servers' own copies:

| Channel | Release | Built from | Bytes | sha256 | Records |
|---|---|---|---|---|---|
| main | every main release from `20261012-115531` (launcher 1.2.4, 12 October 11:55 AM); the live server has held it since 11:42 AM | `e34bf423` on | 146,941 | `d05679e76d8dc930b236ebd906274a4c26b7959228d5ebca727cf5800469bf31` | 419 |
| dev | every dev release from `20261012-004958-dev` (12 October 12:49 AM); the dev server has held it since 12:43 AM | `9ec48194` on | 146,941 | `d05679e76d8dc930b236ebd906274a4c26b7959228d5ebca727cf5800469bf31` | 419 |

The repository has held this file since `f8527daa` (#2336). Before it, every
main release from `20261005-125929` (5 October 12:59 PM) to `20261011-175014`
(11 October 5:50 PM), built from `4eebb138` to `7cece557`, carried a
146,446-byte plugin, sha256
`b34abac05c6341087d7df35b095c52b7c8b79b9c6bb5f527cea607e653667e91`, 415
records, which the live server held from 1:00 PM on 5 October. It was the
plugin below without the four HearthFires records, and with the key and the
key mold as they were in the base.

How the release plugin differs from the collection's 141,023-byte base, record
by record. Both name the same five masters, and the release plugin removes no
record of the base. It adds 37 records and changes two:

- Five override Skyrim.esm's Dwarven scrap smelting recipes
  (`RecipeIngotDwarvenScrapBent`, `RecipeIngotDwarvenScrapLarge`,
  `RecipeIngotDwarvenScrapLarge02`, `RecipeIngotDwarvenScrapLarge03`,
  `RecipeIngotDwarvenScrapPlateMetalSmall`), which collapses the scrap smelts
  to one (#613).
- Fourteen are fishing: three poles and a fish trap with their four recipes,
  and six catches (#1379).
- Six are the weapon, armor and sewing kits and their recipes (#1384).
- Eight are the bandage, splint, poultice and remedy and their recipes (#1383).
- Four override HearthFires.esm's house part recipes (`BYOHRecipeFittings`,
  `BYOHRecipeNails`, `BYOHRecipeHinge`, `BYOHRecipeLock`, #2258).
- Two records of the base changed, the key and the key mold
  (`ThornswoodMiscKey`, `ThornswoodMiscKeyMold`), which got their own meshes
  (#2255).

## Shipped today with no licence this file can name

These are neither Thornswood's nor traceable to SkyMP. They ship because they
sit in the game folder and the rules in Ship-Rules.ps1 count them as ours.
Under `Data\Platform\UI` only `index.html`, `build.js`, `thornswood-*` files
and the hashed assets build.js names count as ours (#1318). No rule looks at
`Fonts` or `Images`. The installer built on 23 September carried the files
below that still have no licence this file can name.

- `Data\Platform\UI`: 37 files from Daedric Online's menu (11 .jpg, 22 .png,
  3 EB Garamond fonts whose name table says SIL Open Font License, and
  `menu_theme.mp3`), 16.2 MB, dated 14 September 14:51 to 14:56. Neither
  build.js nor any Thornswood file names them, and none is in the fork.
  Removed and deleted from every install by every pack (#1318). They never
  ship again. A renamed copy still counts, by sha256. The 41 unused
  skymp5-front svgs and `bg.png` beside them (the old "42 more files" row)
  are gone the same way.
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
  the right to hand them on, and this one does not try. Since #1178 packs,
  release records and the installer carry none of them: outside
  `Data\Platform` only what Ship-Rules.ps1 names as Thornswood's ships
  (Test-ShipNotOurs). The files of four Nexus mods the collection does not have
  yet (male face morphs, fitted hoods and robes, children's clothes, a mesh
  fix) shipped until collection revision 2 carried them
  (docs\COLLECTION-REVISION-2.md). The message board Thornswood-Content.esp
  places ships for as long as that plugin names it, since no revision carries
  it (#2298), and 140
  outfit meshes built in BodySlide on another machine ship as ours for now,
  until Thornswood builds them itself from the collection's BodySlide projects
  (#1259, `scripts\release\built-until-1259.txt`). Packs
  and records already on the site, and the installer there, still carry the
  rest until they are scrubbed.
- Bethesda's `MarketplaceTextures.bsa` went out in every pack and in the
  23 September installer. Ship-Rules.ps1 now holds it back from both
  (Test-ShipBethesdaLeftAlone) without deleting anybody's copy, so builds made
  after that change no longer carry it.

## Made for Thornswood by somebody else

- `Data\Platform\UI\thornswood-theme.mp3` (in the repo as
  `game\ui\thornswood-theme.mp3`) is the theme. It was made for Thornswood
  by an artist this repository does not name, and it went to everybody on
  Patrick's word of 22 September (commit ec8d113). The terms are between
  Patrick and the artist and are not written down here.

## On the site

Since entry 247 (#271) the site serves its fonts and its markdown renderer
itself, from `site\public`, instead of sending every visitor to
Google Fonts and cdnjs.cloudflare.com. So each browser that opens a page gets
these from Thornswood, and server.js runs marked to draw the written pages
before it sends them.

| File | What it is | Licence | sha256 |
|---|---|---|---|
| `marked-12.0.2.min.js` | marked 12.0.2, the markdown renderer, by Christopher Jeffrey, https://github.com/markedjs/marked | MIT, by the notice at the top of the file | `15fabce5b65898b32b03f5ed25e9f891a729ad4c0d6d877110a7744aa847a894` |
| `cinzel.woff2` | Cinzel, one variable file for weights 400 to 700 | OFL-1.1 | `09941fb1c169c38fd414536b37690057fc01b3117a5c63dd6571186540c8f370` |
| `spectral-300.woff2` | Spectral Light | OFL-1.1 | `3ff652c63672dac64699f04465d7e679045d8cdddfb2a2a1a8762d28866e2891` |
| `spectral-300-italic.woff2` | Spectral Light Italic | OFL-1.1 | `b1dc3c4e4bebc0768c8bc9b4662ea2ad7f9fb2b19f98b3b023cf2fbb6e8e362e` |
| `spectral-400.woff2` | Spectral | OFL-1.1 | `cf8daee3b83c1e662196c6e34e444bc41344d54bfeb4fb5351e197de6ce94539` |
| `spectral-400-italic.woff2` | Spectral Italic | OFL-1.1 | `db397149a9f73fd6a41dd2fdf3314cf8a9daf0485134465cc268cac578766b71` |
| `spectral-600.woff2` | Spectral SemiBold | OFL-1.1 | `33faca8b5795a0de1af77cbc43a050a3655c4b1e03e04847fdef4d19d2e361d2` |

The hash for marked is of the file as git stores it, with LF line endings. A
Windows checkout adds a CR to each of its six lines, which changes the hash
but not the file. When #271 added it, it was the same file cdnjs served and
npm publishes for 12.0.2.

The fonts are the latin set Google Fonts served on 24 September. Each file's
own name table gives its copyright, "Copyright 2020 The Cinzel Project Authors
(https://github.com/NDISCOVER/Cinzel)" or "Copyright 2017 The Spectral Project
Authors (https://github.com/productiontype/Spectral)", and the licence's
address: https://scripts.sil.org/OFL in Cinzel and https://openfontlicense.org
in the five Spectral files. The name tables give no version. `fonts.css`, beside
them, names the SIL Open Font License, Version 1.1.

## Not shipped by Thornswood

- The rest of the collection. Each person installs every mod from Nexus Mods
  through Vortex, under its author's own terms. The launcher lists every one
  with a link to its page (`launcher\app\Links.cs`), and the public credits page
  says so. The two mods in it that Thornswood uploads itself are not in this
  group: they have their own sections above. The mod files the installer
  carries anyway are entry 168, above.
- SKSE, which is in the collection, and Skyrim Special Edition, which each
  person owns.
- The WebView2 Runtime, which comes from Microsoft.
- texconv, the tool the main menu picture is built with (next section).

## texconv, Microsoft's texture converter, used to build and not shipped

`scripts\dev\Build-Backdrop.py` uses texconv to write the main menu picture,
`game\menu\Mainmenuwallpaper.dds`, as BC7 (issue #994), because Pillow cannot
write that format. The picture ships; texconv does not. It is not in the
repository either: the script fetches this one file the first time it runs,
into `local\texconv\may2026` (ignored by git), and refuses to run any copy
whose sha256 is not the one below.

| File | Release | Download | sha256 |
|---|---|---|---|
| `texconv.exe` | DirectXTex `may2026`, file version 2026.5.8.1, 966,480 bytes | https://github.com/microsoft/DirectXTex/releases/download/may2026/texconv.exe | `dcfdec10244e02cf5037fba089c55fb7e1326b1c8181742d77d15fa5cb5eef06` |

The sha256 is the one GitHub publishes for that release asset, and the file
downloaded on 28 September matched it. Its Authenticode signature is valid,
signed by Microsoft Corporation ("Microsoft 3rd Party Application Component").
Source: https://github.com/microsoft/DirectXTex, tag `may2026`.

Licence: MIT, by the `LICENSE` file at that tag, "Copyright (c) Microsoft
Corporation." Nobody is handed a copy, so its notice has nothing to travel
with.

## On our servers

- The game server's native module, `scam_native.node`, recorded in
  `records\server-build.json`, is AGPL-3.0. That record and the client record
  name `3bdf3d3c9926a4dd241b1d1c09dadde808a788d5` on the public fork. The
  server module and the six client files were built from that commit, which
  adds the 5 October security fixes (the RPC route, request bodies, metrics,
  the login line, the settings files), the server's equipment write for a new
  character, a saved character whose race cannot be read kept under its own
  id, and the build fixes, and on top of those upstream's fixes of 5 October,
  light plugins on the server and in the save the client loads, numbered
  teleports so an old one is never carried out after a newer one, and the
  server reading its source map while it starts. Since the build before it
  (`7feb5dc4`) it also hands the gamemode what a craft used, so a soul gem
  above a rank can be refused, lets the gamemode ask which saved characters
  could not be read, sends a piece's new condition and name to whoever holds
  it at once, and stops a key let go after a panel closes from repeating into
  the page. Since `92848550` it also fences the server's delayed actor work
  by each actor's lifecycle and owner, so a queued combat or quest write
  never lands on an actor that was unloaded or reused (Thornswood #1373).
  Since `9035ea46` it also lets the gamemode weaken a potion before it lands
  (Thornswood #1382), keeps a reference the server holds disabled when it
  streams in again (#2328), names a brew's effects to the gamemode when it is
  made (#1389), proves the offline login on the connection that logs in
  (#1320) and plays a stagger that came over the network on that actor
  (#489). The server module's SHA256 is
  `04b4e40c02abe88efa1e05266c71fc755c5c89849fba91ae96bc74817cd7cb1d`, built
  2026-10-16T02:17:08Z. This is the recorded next release, not a deployment
  claim. Main remains on `928485503333b18c2325fc13cbf781d254b19af0`;
  dev runs that engine too, as reported by Claude on 11 October.
  It goes to the dev server (Publish-Server -Channel dev) and to the dev
  feed's client files (a dev Ship) first.
  Section 13 of the AGPL asks that everybody who connects to a modified server
  over a network be offered its source. The next section is that offer.
  `scam_native.node` is also the one file that carries antigo, under the
  LGPL-3.0 (above). The fork at that commit names antigo's source by commit
  and SHA512 in `overlay_ports\antigo\portfile.cmake`.

## The Discord bot, on the VPS

The bot in `bot\` runs on the VPS (`scripts\deploy\Install-Bot.ps1`). Its
Python packages stay on the server; nobody downloads them with the game or
the launcher. Versions are pinned in `bot\requirements.txt`. Transitive
dependencies of discord.py (aiohttp and friends) come in through pip at those
pin points and are not listed separately here.

| Package | Version | Licence | Source |
|---|---|---|---|
| `discord.py` | 2.7.1 | MIT | https://pypi.org/project/discord.py/2.7.1/ |
| `Pillow` | 12.3.0 | MIT-CMU | https://pypi.org/project/Pillow/12.3.0/ |
| `certifi` | 2026.7.22 | MPL-2.0 | https://pypi.org/project/certifi/2026.7.22/ |

discord.py is by Rapptz. Pillow is by Jeffrey A. Clark (Alex) and contributors
(the Historical Permission Notice and Disclaimer / MIT-CMU text on PyPI).
certifi is the Certifi project (Mozilla CA bundle as an MPL-2.0 package).

## Where the source is

For the six recorded client files and the recorded game server module, the
Corresponding Source is the fork at the commit each record names. The six
client files and the game server module, at the one commit both records name:

https://github.com/EvilPatrick06/skymp/tree/3bdf3d3c9926a4dd241b1d1c09dadde808a788d5

For the earlier engine reported deployed on Main and dev:

https://github.com/EvilPatrick06/skymp/tree/928485503333b18c2325fc13cbf781d254b19af0

It is on the branch `thornswood/engine-changes`, it is public, and the branch
answered an anonymous request on 24 September. It builds with CMake and
vcpkg from the fork's `vcpkg.json`. The licence texts are in that tree:
`skymp5-client/LICENSE`, `skyrim-platform/LICENSE` and `skymp5-server/LICENSE`.

That covers what Thornswood built. It does not cover
`Data\Platform\UI\build.js`. Its source is upstream's `skymp5-front`, at
https://github.com/skyrim-multiplayer/skymp, but nobody recorded which commit
it was built from.

Nor does it cover `___systemPolyfill.js` in the Thornswood Client Runtime,
because the fork no longer has it at the recorded commit. Its source is the
TypeScript it was compiled from, `src/___systemPolyfill.ts`, in the same fork
at the last commit before upstream removed it:

https://github.com/EvilPatrick06/skymp/tree/43eedb568e72d3ea2f04b946b7cf14cbd1139750/skyrim-platform/tools/system_polyfill

That commit is upstream's, the parent of `ceba28bc`. It is an ancestor of the
recorded commit, so it is in the history of the branch above, and the clone
here showed `origin/thornswood/engine-changes` containing it on 24 September.
The licence text is `skyrim-platform/LICENSE` in the same tree.

The rest of that mod is CEF, Chromium, ANGLE, ICU and Node, under permissive
licences that ask for no source offer, and Microsoft's compiler. The mod's
README still gives the source of CEF (https://github.com/chromiumembedded/cef),
Chromium (https://chromium.googlesource.com/chromium/src) and Node
(https://github.com/nodejs/node).

The directions reach people in four places. The installer carries
`SOURCE CODE.txt`, which Package-Thornswood.ps1 writes from the two build
records and Setup-Thornswood.ps1 copies into the install folder (entry 170).
The public credits page has them under "Source code", at
https://thornswood.net/credits#source, which the download page links beside
the installer (entry 170). `tests\test-source-offer.ps1` holds both to the
records. The update feed's own downloads carry them too: the client runtime
zip has a `README.txt` and every pack that carries a SkyMP file has a
`SOURCE CODE.txt`, each naming the recorded commit and the files it carries,
with the GPL and AGPL texts beside it (Source-Notice.ps1, written by
Publish-Update.ps1 from `records\client-build.json`). And the Thornswood
Client Runtime's own README, installed as
`Data\Docs\Thornswood Client Runtime\README.txt`, names the fork, its branch
and upstream SkyMP, but no commit, and `___systemPolyfill.js` is not on that
branch any more.

## What is still missing

- The GPL text reaches people through Nexus: the Thornswood Client Runtime
  installs `Data\Docs\Thornswood Client Runtime\licences\SkyrimPlatform-LICENSE.txt`,
  the GNU General Public License version 3, with the CEF, Chromium, ANGLE, ICU
  and Node texts beside it, for everybody who installs the collection. The
  installer also hands `GPL-3.0.txt`, `AGPL-3.0.txt` and `WebView2-LICENSE.txt`
  into the install folder beside `SOURCE CODE.txt` (Package-Thornswood.ps1
  stages them from `installer\licences`, Setup copies them, Uninstall removes
  them). The update feed's client runtime zip and every pack that carries a
  SkyMP file hand the GPL and AGPL texts with a note naming the recorded
  commit (Source-Notice.ps1). Updates stopped going to GitHub release pages on
  28 September (#907); the launcher's draft release notes in
  `.github/workflows/release.yml` still point at
  https://thornswood.net/credits#source.
- The Client Runtime's README names the fork's branch and no commit, and
  `___systemPolyfill.js` is gone from that branch, so the README's directions
  do not lead to that file's source. The exact place is under "Where the
  source is". Nothing in the shipped client loads that file.
- `d3dcompiler_47.dll` goes out in the Client Runtime with no licence text,
  and this file names none.
- The `ICU-LICENSE.txt` in the Client Runtime is a later ICU's text than the
  ICU 71 data it sits beside.
- The permissive vcpkg licence texts do not travel with the client runtime,
  and the MIT and BSD ones ask for their notice to go with a binary. The two
  that are not permissive ask nothing of what ships today (antigo and
  frida-gum, under "The SkyMP client runtime, built from the fork").
- The MIT and OFL texts are not on the site beside marked and the fonts. The
  files keep their copyright lines and name their licences, as the copies
  from npm and Google Fonts did.
- build.js has no recorded source commit.
- The Futura PT, DIN Pro and Bankir-Retro fonts, and the files under "Shipped
  today with no licence this file can name" that still ship (`Fonts` sprite
  fonts and `Images`), ship with no licence found. The 37 Daedric Online
  menu files do not: they are removed and deleted from installs (#1318).

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
