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
also Thornswood's own. Djinn made the emblems, the icons, the header strip and
its video for Thornswood, and the rest of Thornswood's art too (the site's
pictures, the main menu backdrop's picture, the start screen's scrolls and
the Discord pictures), under the contributor terms in `LICENSE` (Patrick,
15 Oct 2026, #2177). `records\asset-provenance.json` has each file.

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
commit `d39a9a93` (in full, `d39a9a935359a530c51f885f42e279e873aa2544`). That
is upstream skyrim-multiplayer/skymp at `2849e676` with Thornswood's changes on
top. Check-Secrets.ps1 stops a release whose copy of any of the six is not the
recorded sha256 (client-not-recorded-build), and Sync-Client.ps1 puts in the
recorded build.

The six client files and the native server were built by the fork's own
Windows build (fork run 39224220993) and recorded by Thornswood's engine.yml
(run 39227946118, #459). The native server and its
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
`WorldState.cpp`. One more fork file names it and uses none of it:
`misc\tests\node\test_save_completion_addon.cpp`, a test fixture (fork #77)
that writes stand-ins of its own for antigo's names so the server's addon
code compiles without it, and that only the fork's own node test builds.
Nothing under `misc\tests` goes into a file anybody receives.
`MpClientPlugin.dll` takes `server_guest_lib` for its
inventory code only, and none of the messages in those two files is in the
recorded `MpClientPlugin.dll`. Nor is any of antigo's own (`resolved context
with`, `stringstream error!`), while the recorded `scam_native.node` has every
one of them. So no file anybody receives carries antigo. The LGPL asks for its
notice, its text and a way to relink only where a copy is handed to somebody,
and running the server hands nobody a copy: it asks nothing of Thornswood
today. #1332 said this repository holds an `LGPL-3.0.txt`. It has none, and
none is owed. The day a client file calls antigo, the LGPL's notice and text
have to go with that file, and `tests\test-third-party.js` fails when a fork
file outside those three and the fork's tests starts using it.

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
| `Data\Platform\UI\build.js`, in main's releases until its next one | A development build of `skymp5-front`, dated 13 September 04:33 in the game folder. It was not built here, and nobody recorded the commit it came from. It bundles npm packages under their own licences, among them React 16.13.1 and 17.0.2, MIT by the `@license` comments inside it. Since 20 October every release carries the fork's own build in its place ("SkyMP's interface, built from the fork", below). | GPL-3.0 |
| The files beside that build.js that it names by hash | Its fonts, sounds and pictures. 26 are byte for byte files in the fork's `skymp5-front\src`. Ship parses the names from build.js at pack time (#1318); it does not keep a count by hand. | As build.js, except the fonts below. |

The fonts in that older front build, from their own name tables. All six are
byte for byte the files in upstream's `skymp5-front\src\fonts`:

| File | Font | What the file says |
|---|---|---|
| `6f802bf60c545304b09e.ttf` | Futura PT Cond Book | "ParaType Ltd", licence http://www.paratype.com/eula |
| `00e4a2200c3e5ae71d67.ttf` | Futura PT Cond Medium | "ParaType Ltd", licence http://www.paratype.com/eula |
| `268a0df3f0e2c23d1ea6.ttf` | DIN Pro Regular | "FSI FontShop International GmbH", licence http://www.fontfont.com/eula/license.html |
| `fdf086661e1600f95a34.ttf` | DIN Pro Condensed Bold Italic | "FSI FontShop International GmbH", licence http://www.fontfont.com/eula/license.html |
| `855bfaf67c57745958d3.ttf` | Bankir-Retro, by Gophmann A.L., 2006 | "Copyright (c) Gophmann A.L., 2006. All rights reserved." and "Bankir-Retro is a trademark of Gophmann A.L.", with no licence field. Upstream's `THIRD_PARTY_LICENSES` calls a modified copy, "Black Horse Courier", "free". |
| `d213051bb6f28a25fb26.ttf` | icomoon, made with the IcoMoon app | "Font generated by IcoMoon.", and no copyright or licence. |

Futura PT and DIN Pro point at their foundries' end user licences. This file
found nothing that gives SkyMP or Thornswood the right to hand them on, and
upstream names none. Upstream SkyMP ships them the same way. The fork's own
build has none of the four (below), so they leave with main's next release;
installs that already have them keep them until a release lists them as gone,
which is #1317.

Bankir-Retro and icomoon keep shipping, credited to SkyMP and to their makers
(Patrick, 15 Oct 2026, #2177): they came to Thornswood with SkyMP's
`skymp5-front`, where both have been in `src\fonts` since 13 October 2021
(upstream commit 34d8ca12, #329), and the public credits page names both.
build.js draws SkyMP's buttons and text boxes in Bankir-Retro, and the dots of
a hidden password in icomoon. What each one carries, read on 16 October:

- **Bankir-Retro** is by Gophmann A.L., 2006, by its own name table, which
  reserves all rights and names no licence. Upstream added its font notes on
  4 April 2022 (#1086); the line there is "Black Horse Courier - modified
  Bankir-Retro by A. L. Gopfmann 2006, free", about a modified copy under
  another name, and the file shipped calls itself Bankir-Retro. No licence
  text was found, so none is claimed here.
- **icomoon** was made with IcoMoon, the icon font app: its name table says
  "Font generated by IcoMoon." and nothing else about who made it. It names
  no copyright or licence, upstream's font notes do not mention it, and
  `skymp5-front`'s `package.json` gives GPL-3.0 for the package as a whole.
  Which icon set its glyphs come from is not recorded, so no licence is
  claimed here either.

## SkyMP's interface, built from the fork

Since 20 October 2026 (#2754, #2931) every Ship builds `Data\Platform\UI\build.js`
and the fonts, sounds and pictures beside it from the fork's `skymp5-front`
at the engine pin, with webpack, and holds what it built to
`records\front-build.json`: 68 files, 8,434,780 bytes, from commit
`d39a9a93`, the commit the client record names. Read on 21 October (#421):
the dev feed's release `20261021-104809-dev` carries that build.js, 2,448,900
bytes, sha256
`d35838544dd8c65704db86171f46d7ef7b788ec61ba6f2e0da0535db1ddc91ae`, and every
font in it is one the record names. Main's release `20261017-205912` still
carries the 13 September build in the table above until main's next release.

The licence is skymp5-front's, `GPL-3.0` by its `package.json`, and its source
is the fork at that commit, under "Where the source is". It bundles npm
packages under their own licences, among them React 16.13.1 and 17.0.2, MIT
by the `@license` comments inside it, read from the dev feed's copy.

The fonts in it, from their own name tables:

| File | Font | What the file says |
|---|---|---|
| `855bfaf67c57745958d3.ttf` | Bankir-Retro, by Gophmann A.L., 2006 | The same file as in the older build, above. |
| `d213051bb6f28a25fb26.ttf` | icomoon, made with the IcoMoon app | The same file as in the older build, above. |
| `dc3cbd21104d40477da6.ttf` | Barlow SemiBold, version 1.408, by Jeremy Tribby (Tribby Type) | "Copyright 2017 The Barlow Project Authors (https://github.com/jpt/barlow)", and in its licence field "This Font Software is licensed under the SIL Open Font License, Version 1.1." with http://scripts.sil.org/OFL. 108,348 bytes, sha256 `86577cb32f8abe3673db53ca0f4221e6856751a4f6730c867e00f720f8bb1fc5`, the fork's `skymp5-front\src\fonts\Barlow-SemiBold.ttf`. |

Barlow came into the fork on 9 October (fork #40, for #1317) in place of DIN
Pro, from Google Fonts' `google/fonts` at `2eb0b48d`, and the same change
took out the Futura PT and DIN Pro faces. The OFL lets a font travel with its
copyright notice and licence in its own metadata, which this one carries;
the fork keeps the full text beside it as `skymp5-front\src\fonts\OFL.txt`.

## Thornswood Client Runtime, Thornswood's mod on Nexus Mods

Thornswood publishes this itself, as its own mod: Nexus Mods mod 192762,
https://www.nexusmods.com/skyrimspecialedition/mods/192762, by EvilPatrick06.
Revision 4 of the collection (`7essxf`, published 21 October 2026, revision id
813945) carries version 1.0.1, file 823485, uploaded on 20 October, and it is
not optional. Nexus gives that file as 152,002,702 bytes, and the archive it
serves has md5 `74ef6a9f5cf0a5ba7dbab9c00cb67491`, the md5 the collection
pins. Revision 3 carries the same file; revisions 1 and 2 carry version
1.0.0, under "Version 1.0.0, which revisions 1 and 2 still install" below.

It is the largest thing somebody else wrote that Thornswood hands out: 67
files, 366,155,245 bytes, into `Data\Platform\Distribution`, and a README and
five licence texts into `Data\Docs\Thornswood Client Runtime`, 73 entries in
all. Read on 21 October 2026 (#421) from that archive, downloaded from Nexus
with its md5 checked, and from the record of revision 3 as
`Install-NexusRevision.ps1 -Record` laid it out (files.txt, every file of
file 823485 by sha256), which revision 4 changes only in nine plugins (#2979).
The 67 are byte for byte the 67 of 1.0.0 that, read on 24 September, were the
files the fork's build puts in `build\dist\client\Data\Platform\Distribution`.

`SkyrimPlatformImpl.dll` and `SkyrimPlatformCEF.exe.hidden` are left out of the
mod on purpose. They are two of the six recorded files above, and they come
with the launcher, which checks them against its own record.

What is in it, by path under `Data\Platform\Distribution`. Each version is the
file's own version resource, or for ICU the name inside the data, and each
agrees with the mod's README wherever the README gives one.

| Part | Version | Files | Licence | Its text in the mod |
|---|---|---|---|---|
| Chromium Embedded Framework, and Chromium | CEF 108.4.13+ga98cd4c, Chromium 108.0.5359.125 | `RuntimeDependencies\libcef.dll`, `chrome_elf.dll`, `snapshot_blob.bin` and `v8_context_snapshot.bin`; `CEF\chrome_100_percent.pak`, `chrome_200_percent.pak` and `resources.pak`; 55 `CEF\locales\*.pak` | BSD-3-Clause | `CEF-LICENSE.txt`, `Chromium-LICENSE.txt` |
| ICU data | ICU 71, by the name inside the file, `icudt71l` | `RuntimeDependencies\icudtl.dat` | Unicode's licence, as ICU 71 carries it | `ICU-LICENSE.txt` |
| ANGLE | 2.1.19724, git ceec659ac60b | `RuntimeDependencies\libEGL.dll`, `libGLESv2.dll` | BSD-3-Clause | `ANGLE-LICENSE.txt` |
| Node.js | 23.2.0 | `RuntimeDependencies\libnode.dll` | MIT, with the licences of the libraries built into it | `Node-LICENSE.txt` |
| Microsoft Direct3D HLSL Compiler | 10.0.20348.1 | `RuntimeDependencies\d3dcompiler_47.dll` | Microsoft's, handed on under the Windows SDK's terms for Distributable Code, below | None; the README says the terms |

The programs and the ICU data, by sha256:

| File | Bytes | sha256 |
|---|---|---|
| `RuntimeDependencies\libcef.dll` | 191,842,816 | `52aa8b457a5f174d0a51509da4dc8e128b6b4bb476b800bab6c7eb9c109219be` |
| `RuntimeDependencies\libnode.dll` | 109,094,912 | `f22c87fa55e3c0e8b5626fd94c801ba7f1bf581e6fa555ce702c44e553d2d210` |
| `RuntimeDependencies\icudtl.dat` | 10,462,432 | `97b978a19edd4746e9a44d9a44bb4bc519e127a203c247837ec0922f573449e3` |
| `RuntimeDependencies\libGLESv2.dll` | 7,493,120 | `49ee2a4800a8eba183169152ecd5550b8d55989785e2f44a7de04930dcb3d7ef` |
| `RuntimeDependencies\d3dcompiler_47.dll` | 4,891,080 | `e4bc3420a28069bd13dc3be725d46676a7c0e99de221026e8c43cd6f7ed45c0b` |
| `RuntimeDependencies\chrome_elf.dll` | 1,411,072 | `4f5f1dc6d998b07e3919055b6f9cc8befc626d30479c7c2d07722051650491a0` |
| `RuntimeDependencies\libEGL.dll` | 474,624 | `1100398a3fe57da76ea58b9b110be2f6a83a75a3e1863863f086d9218b46cc5a` |

Chromium and Node build other people's libraries into these files.
`Node-LICENSE.txt`, 139,053 bytes, carries the licence of every library built
into libnode.dll. For Chromium the README points at Chromium's own source at
108.0.5359.125, where each component keeps its LICENSE file. No list of those
travels with the mod.

`icudtl.dat` is ICU 71's data, and the `ICU-LICENSE.txt` beside it is ICU 71's
own text, 25,505 bytes, sha256
`af3e84c401f1a35e8d32d6eb1a33fe587c3981aa5cd206033d9527c1855b57a2`, ICU's
`icu4c/LICENSE` at its tag `release-71-1`. Until 1.0.1 the mod carried the
Unicode License V3 of a far later ICU in its place.

### d3dcompiler_47.dll, Microsoft's shader compiler

Read on 20 October 2026 (#421). The file is Microsoft's and unmodified: its
Authenticode signature is valid, signed by Microsoft Corporation, its version
resource says "Direct3D HLSL Compiler for Redistribution", version
10.0.20348.1, "© Microsoft Corporation. All rights reserved.", and its sha256
is the one in the table above. It is the copy the Chromium Embedded
Framework's own binary download carries beside `libEGL.dll` and
`libGLESv2.dll`, for ANGLE. It is not the copy a newer Windows SDK carries:
the 10.0.26100 SDK's `Redist\D3D\x64\d3dcompiler_47.dll` on the shipping
machine has another sha256 (`3e56c1a0`).

Its terms are the Windows SDK's licence. Microsoft's list of the SDK's
redistributable files, which the licence's "Distributable Code" section
points at (https://learn.microsoft.com/en-us/legal/windows-sdk/redist,
"Windows SDK redist lists", updated 21 October 2024), names
`Redist\D3D\x64\d3dcompiler_47.dll` among the files that "may only be
redistributed with your Classic Windows applications". The licence itself
(`sdk_license.rtf` in the 10.0.26100 SDK, section 2.a) lets that code be
copied and handed on in its object code form, with these conditions, read
from that file:

- Add significant primary functionality to it in your programs, and hand it
  on only with them. Here it goes out with the client the Thornswood
  collection installs, which loads it through Chromium.
- Do not alter any copyright, trademark or patent notice in it, and do not
  use Microsoft's trademarks in a program's name or in a way that suggests
  Microsoft made or endorses it. It goes out byte for byte as Microsoft
  signed it.
- Only for Windows, and never in a malicious, deceptive or unlawful program.
- Never modify or hand it on so that any part of it falls under a licence
  that requires its source to be disclosed or lets others modify it. It goes
  out as its own file beside GPL code, not built into it, so the GPL does not
  reach it.
- Display your own valid copyright notice on your programs.
- Indemnify Microsoft against claims arising from handing it on or using the
  programs it goes out with.
- Require distributors and external end users to agree to terms that
  protect it at least as much as the licence does. Patrick decided on
  20 October 2026 (#421, option A) that the Client Runtime's README says so,
  and the README of 1.0.1, the version revisions 3 and 4 install, does: by
  installing the file you accept Microsoft's terms for it, use it only with
  the Thornswood client, keep its copyright and other notices as they are,
  do not hand it on apart from the mod, and Microsoft gives no warranty for
  it and it remains Microsoft's property.

No licence text travels with it, and the SDK licence does not ask for one.
Windows 8.1 and later carry their own `d3dcompiler_47.dll` in `System32`
(the shipping machine's is 10.0.26100.9711), and Steam, which the game runs
through, has needed Windows 10 or later since 1 January 2024. Whether Chromium in the game draws the same
without the copy in `RuntimeDependencies` has not been measured.

### Version 1.0.0, which revisions 1 and 2 still install

Version 1.0.0, file 809366, uploaded on 22 September, is archived on Nexus
and still served: revisions 1 and 2 of the collection pin it, and Nexus gave
a download for it on 21 October. Revision 2 records it as 148,896,610 bytes, md5
`c515679068f6563750b1ca1f9260031f`.
It is 1.0.1 with two more files and two older ones. Its README names the fork
and its branch but no commit, and says nothing of Microsoft's terms for
`d3dcompiler_47.dll`; its `ICU-LICENSE.txt` is the later ICU's text above.
The two more are `___systemPolyfill.js` and
`Data\Docs\Thornswood Client Runtime\licences\SkyrimPlatform-LICENSE.txt`,
which Patrick dropped from the mod on 28 September because nothing in the
client loads the script.

`___systemPolyfill.js`, 2,605 bytes, sha256
`38320fb897314ae7471bdab749f00442c00913f14d7b8f82bc793b3c2b669188`, is the
SystemJS module loader that Skyrim Platform used to run before a plugin's
`index.js`. Line endings aside, it is upstream's
`skyrim-platform/tools/system_polyfill/dist/___systemPolyfill.js`, which did
not change from 28 June 2023 until upstream removed that folder on 1 June 2026
(commit `ceba28bc`, "drop system-polyfill, multifile plugins & other
deprecated features", #2711). That removal comes before `2849e676`, the
upstream commit the fork starts from, so the fork at the recorded commit has
no such file. It is part of skyrim-platform, whose `package.json` says
`GPL-3.0`, and 1.0.0's `SkyrimPlatform-LICENSE.txt` is byte for byte
skyrim-platform's `LICENSE`, the GNU General Public License version 3, 35,149
bytes. While 1.0.0 is served, its source stays offered, under "Where the
source is".

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
  since 15 October (#400, Patrick: the name is mentioned nowhere), and since
  21 October (#2993) `scripts\mods\Add-ContentRecords.py` builds it from the
  records the plugin holds, so it names what is in it and nothing that left.
  The collection's copy keeps the old one until a later revision patches it.
  Since 16 October (#2553, Patrick, 15 October, option B on #2177) the
  repository's plugin is remade as Thornswood's own; its bytes and sha256 are
  the ones `records\asset-provenance.json` registers, which
  `tests\test-asset-provenance.js` holds to the file. `scripts\mods\Add-ContentRecords.py` writes every record of it from
  its own numbers, or copies Bethesda's own, and places the kiln, the salt
  quarry, the hive and the alchemy lab where `scripts\dev\Build-StationSites.py`
  measured Thornswood's own spots (`game\data\station-sites.json`). The other
  server's placements, its 57 of those stations included, and its changes to
  Skyrim's own are gone.
  `scripts\mods\content-salvaged.json` lists every salvaged record and what
  became of it. The collection's copy and the release plugins in the table
  below still carry the salvaged records until they carry this one. Until 12 October this
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
and the hashed assets build.js names count as ours (#1318). In `Fonts` and
`Images` only the five files below that nothing uses are held back (#2177).
The installer built on 23 September carried the files below that still have
no licence this file can name.

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
  or under what licence. ChainLink, NoticeIcon and VoiceIcon, icon fonts of
  four, one and one glyphs, stop shipping and every pack deletes them from
  installs (Patrick, 15 Oct 2026, #2177; `$ShipPlatformUnused` in
  Ship-Rules.ps1, and OwnGame.Foreign so a refresh cannot bring them back).
  Futura.spritefont still ships, with #1317.
- `Data\Platform\Images\lock.png` and `speaking.png`, dated 12 September 13:40.
  They are not in the fork, and nothing names them. They stop shipping and
  every pack deletes them from installs the same way (#2177).
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
  it (#2298), and 122
  outfit meshes built in BodySlide on another machine (the travel clothes and
  More Craftable Equipment's executioner) ship as ours for now, until
  Thornswood builds them itself from the collection's BodySlide projects
  (#1259, #2454, `scripts\release\built-until-1259.txt`). The 18 Bosmer
  armour morphs leave in the next release, and nothing built from Immersive
  Armors is handed on: it is used as-is through the collection (Patrick,
  17 Oct, #2454). What each mod's page permits for that built output is in
  `records\asset-provenance.json`. Packs
  and records already on the site, and the installer there, still carry the
  rest until they are scrubbed.
- Bethesda's `MarketplaceTextures.bsa` went out in every pack and in the
  23 September installer. Ship-Rules.ps1 now holds it back from both
  (Test-ShipBethesdaLeftAlone) without deleting anybody's copy, so builds made
  after that change no longer carry it.

## Bethesda's own files, made on each machine

`Data\Interface\startmenu.swf` is Skyrim's own `interface\startmenu.swf` from
`Skyrim - Interface.bsa`, edited so the main menu shows no Bethesda logo and
no button list. Compared on 15 October: the same 871 SWF tags in the same
order, only DefineShape tags differing, by a byte or two each, and no strings
added or removed. It is Bethesda's work, edited, and recorded as that
(Patrick, 15 Oct 2026, #2177); who edited it is not recorded. The notice
board and drop box meshes, `Data\meshes\thornswood\noticeboard01.nif` and
`dropbox01.nif`, are not the game's files but are put together from pieces of
them (`scripts\mods\Build-NoticeBoard.py`, #2502).

Until #2827 every pack and the installer carried all three, from
`game\ours`. Since #2827 none of them ships (Patrick, 19 Oct 2026, option 2):
the launcher makes them before every Play from the person's own game
archives, byte for byte the files that shipped (`launcher\app\FromGame.cs` and
`MadeFromGame.cs`), and `scripts\release\Go.ps1` does the same for a hand-run
install. What the repository holds is the recipe, not the files: for the menu
the bytes the edit changes (`FromGameMenu.cs`), for the meshes which game
meshes they are put together from and where each piece goes, with
Thornswood's own collision (`FromGameBoard.cs`). `Ship-Rules.ps1`
`$ShipMadeFromGame` keeps the three out of every pack, release record and
installer, and the terms page says Thornswood ships no game files.

Bethesda's terms for Skyrim Special Edition mods are the Creation Kit End User
License Agreement (https://store.steampowered.com/eula/1946180_eula_0, Steam
app 1946180), read on 19 October 2026 for #2792. What it says that bears on
these three files:

- Its preamble: "Any rights not granted to You in this Agreement are reserved
  by ZeniMax."
- 1.D.a: a mod goes out free, and "only ... to users who have purchased the
  Product through authorized and legitimate distribution channels, solely for
  use with such users' own authorized copies". Thornswood is free and needs
  the game.
- 2.B: every mod says ZeniMax is not its author and carries "THIS MOD IS NOT
  MADE, GUARANTEED OR SUPPORTED BY ZENIMAX OR ITS AFFILIATES." The site's
  terms and credits pages carry it; the two Nexus pages are #2829.
- 3: whoever releases a mod represents "that each Game Mod is originally
  created by You".

No clause grants a right to hand on ZeniMax's own files, edited or not, or
meshes put together from them. Free mods hand on edited game files all the
time and ZeniMax does not act against them, but that is tolerance, not a
written grant, so Thornswood stopped handing the three on (#2827), and
`records\asset-provenance.json` records them as made from the game. The same section 1.D.a forbids
crowd funding for making mods, which is #2828.

The other main menu files beside it are Thornswood's own:
`game\menu\logo.nif`, the plate the backdrop is drawn on, which
`scripts\dev\Build-Backdrop.py --logo` has built since 16 October in place of
a wallpaper replacer's plate whose maker was never found, `logo01ae.nif`
made from it, and `Data\music\special\mus_maintheme.xwm`, made new as
silence.

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

The licence texts are served beside them, since 21 October 2026 (#421), each
the copy the project's own Google Fonts folder keeps with its copyright line:

| File | What it is | sha256 |
|---|---|---|
| `marked-LICENSE.txt` | marked's `LICENSE.md` at its tag `v12.0.2`: the MIT licence for marked, and the BSD-style licence of the original Markdown it names | `8e3a3f82f59a60958f56ca08f445647c32a4733dc7ca6c2c46f6eb898471ab9c` |
| `cinzel-OFL.txt` | `ofl/cinzel/OFL.txt` in https://github.com/google/fonts, the OFL 1.1 under Cinzel's copyright line | `f2b3029aba64c378bf0963b62945eee15e564fe4330b934c8f2eb058282b5e83` |
| `spectral-OFL.txt` | `ofl/spectral/OFL.txt` there, the OFL 1.1 under Spectral's copyright line | `501d6ceca8e552630fe3aa9442b9a818565680a1a2f79f3fb8c13d6f309a9e98` |

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
  name `d39a9a935359a530c51f885f42e279e873aa2544` on the public fork. The
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
  (#489). Since `3bdf3d3c` it also measures the keyboard instead of putting
  focus back on a timer (#2131), and keeps every save it accepted until it is
  written or said to have failed, through form destruction, index reuse and a
  world's shutdown, with the outcome handed back to the gamemode (#1373). Since
  `877113d7` it also gives the gamemode a write that replaces a whole file at
  once, which readers never see half written, and its resource port serves
  each file from the one handle it opened (#2740). Since `c4ada9c7` it also
  decides a block before it hands the gamemode the hit, so the hit's blocked
  flag is the server's own and a block against a character the server runs is
  seen (#1386), and lets a plugin keep a character from being slowed by what it
  carries, here and on everybody else's screen (#1385). Since `9d3139ca` it also
  has a kept NPC take the reference its plugin placed instead of spawning a
  second one (#2483), lets a cast hold its effects longer, counted on the
  caster's machine and agreed by the server (#2848), and keeps the cursor
  menu's queued show and hide until the game handles it (#2384). Since
  `90591081` it also redraws a character's hair when the server changes its
  colour (#2867), since `3d2cb747` its front end is written with LF line
  endings on every machine that builds it (#2754), since `57fd87d8` it
  lets the gamemode name what a craft gives, so a cook can come out burnt or
  fine (#2906), since `049d4c26` the name the item is given with too, so a
  Master Weaver's garment is made with its mark (#3026), since
  `d9bee9ea` the engine's AddItems keeps every entry after one that joins a
  stack (#3069), and since `d39a9a93` it refuses a stack past 4,294,967,295
  before anything moves (#3074). The server module's SHA256
  is `fc9f18973c9ab5ba8b0a655c0c87871376ae7963aea5cdc61a0ec32aa3d38e87`, built
  2026-10-21T17:54:14Z. This is the recorded next release, not a deployment
  claim. Main remains on `3bdf3d3c9926a4dd241b1d1c09dadde808a788d5` until this goes
  out.
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
| `Pillow` | 13.0.0 | MIT-CMU | https://pypi.org/project/Pillow/13.0.0/ |
| `certifi` | 2026.10.19 | MPL-2.0 | https://pypi.org/project/certifi/2026.10.19/ |

discord.py is by Rapptz. Pillow is by Jeffrey A. Clark (Alex) and contributors
(the Historical Permission Notice and Disclaimer / MIT-CMU text on PyPI).
certifi is the Certifi project (Mozilla CA bundle as an MPL-2.0 package).

## Where the source is

For the six recorded client files and the recorded game server module, the
Corresponding Source is the fork at the commit each record names. The six
client files and the game server module, at the one commit both records name:

https://github.com/EvilPatrick06/skymp/tree/d39a9a935359a530c51f885f42e279e873aa2544

For the engine Main runs until then:

https://github.com/EvilPatrick06/skymp/tree/3bdf3d3c9926a4dd241b1d1c09dadde808a788d5

It is on the branch `thornswood/engine-changes`, it is public, and the branch
answered an anonymous request on 24 September. It builds with CMake and
vcpkg from the fork's `vcpkg.json`. The licence texts are in that tree:
`skymp5-client/LICENSE`, `skyrim-platform/LICENSE` and `skymp5-server/LICENSE`.

That covers what Thornswood built, and since 20 October that includes
`Data\Platform\UI\build.js` and the files beside it: `records\front-build.json`
names the same commit. It does not cover the older build.js main's releases
carry until main's next one. Its source is upstream's `skymp5-front`, at
https://github.com/skyrim-multiplayer/skymp, but nobody recorded which commit
it was built from.

Nor does it cover `___systemPolyfill.js`, which version 1.0.0 of the
Thornswood Client Runtime carries (revisions 1 and 2 of the collection still
install it; 1.0.1 does not), because the fork no longer has it at the
recorded commit. Its source is the TypeScript it was compiled from,
`src/___systemPolyfill.ts`, in the same fork at the last commit before
upstream removed it:

https://github.com/EvilPatrick06/skymp/tree/43eedb568e72d3ea2f04b946b7cf14cbd1139750/skyrim-platform/tools/system_polyfill

That commit is upstream's, the parent of `ceba28bc`. It is an ancestor of the
recorded commit, so it is in the history of the branch above, and the clone
here showed `origin/thornswood/engine-changes` containing it on 24 September.
The licence text is `skyrim-platform/LICENSE` in the same tree.

The rest of that mod, and all of 1.0.1, is CEF, Chromium, ANGLE, ICU and
Node, under permissive licences that ask for no source offer, and Microsoft's
compiler. The mod's README gives the source of CEF (https://github.com/chromiumembedded/cef),
Chromium (https://chromium.googlesource.com/chromium/src) and Node
(https://github.com/nodejs/node).

The fork says it is modified (GPL and AGPL section 5(a)): its README on
`thornswood/engine-changes` opens with a dated notice that the branch is
SkyMP as changed by Thornswood since 17 September 2026, with a link to every
change since upstream's `2849e676` (#421).

The offer is also made where the server is used (AGPL section 13), not only
where files are handed out (#421). The launcher's sidebar has Source code
under its version lines, which opens the fork at the commit the launcher's
own `client-build.json` names (`ClientRuntime.SourceUrl`), and the game's
help panel says under Getting help where the source is.
`tests\test-421-source-offer-ui.js` holds both.

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
`Data\Docs\Thornswood Client Runtime\README.txt`, names the fork, its branch,
upstream SkyMP and https://thornswood.net/credits#source. It names no commit,
and since 1.0.1 it needs none: nothing in that version is built from the
fork.

The GPL and AGPL texts go with the files they cover. The installer hands
`GPL-3.0.txt`, `AGPL-3.0.txt` and `WebView2-LICENSE.txt` into the install
folder beside `SOURCE CODE.txt` (Package-Thornswood.ps1 stages them from
`installer\licences`, Setup copies them, Uninstall removes them). The update
feed's client runtime zip and every pack that carries a SkyMP file hand the
GPL and AGPL texts with a note naming the recorded commit (Source-Notice.ps1).
Updates stopped going to GitHub release pages on 28 September (#907); the
launcher's draft release notes in `.github/workflows/release.yml` still point
at https://thornswood.net/credits#source. Version 1.0.0 of the Client Runtime
also installs
`Data\Docs\Thornswood Client Runtime\licences\SkyrimPlatform-LICENSE.txt`
beside its `___systemPolyfill.js`.

## What is still missing

- The permissive vcpkg licence texts do not travel with the client runtime,
  and the MIT and BSD ones ask for their notice to go with a binary. The two
  that are not permissive ask nothing of what ships today (antigo and
  frida-gum, under "The SkyMP client runtime, built from the fork").
- Main's releases carry the older build.js, with no recorded source commit,
  until main's next release carries the fork's own (#2754).
- The Futura PT and DIN Pro fonts in main's older build.js, the Bankir-Retro
  and icomoon fonts in both builds, and `Futura.spritefont` under "Shipped
  today with no licence this file can name", ship with no licence found. The 37 Daedric Online menu files do not:
  they are removed and deleted from installs (#1318), and so are the two
  pictures in `Images` and the ChainLink, NoticeIcon and VoiceIcon sprite
  fonts (#2177).
- `Data\Interface\startmenu.swf` is Bethesda's file, edited, and the notice
  board and drop box meshes are built from Bethesda's ("Bethesda's own files,
  made on each machine"). Bethesda's terms for mods were read on 19 October
  and grant no right to hand any of the three on, so since #2827 none ships:
  the launcher makes them from each person's own game.

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
