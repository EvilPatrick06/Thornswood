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

## What Thornswood hands you that somebody else wrote

**The launcher** carries three files from Microsoft's WebView2 SDK, version
1.0.2903.40. They give it the browser that voice runs in. Microsoft's licence
for them is at the bottom of this page.

**The multiplayer client** is six files built from Thornswood's copy of SkyMP.
Five of them come from skymp5-client and Skyrim Platform, under the GNU General
Public License version 3 (GPL-3.0). The sixth, MpClientPlugin.dll, comes from
skymp5-server, under the GNU Affero General Public License version 3
(AGPL-3.0).

**The game server** runs on skymp5-server from the same copy, under the
AGPL-3.0.

**SkyMP's in-game interface**, which Thornswood's own panels sit on top of, is
a build of SkyMP's skymp5-front, under the GPL-3.0. It was not built by
Thornswood, and which version of SkyMP it came from was not recorded.

**Tavern**, the font Skyrim Platform draws its text in, is Typey McTypeface by
Paul J. Miller and Dieter Steffmann, under the SIL Open Font License. It comes
with SkyMP.

## Where the source is

The source for the client files and the server is public, at the exact version
Thornswood runs:

https://github.com/EvilPatrick06/skymp/tree/c8832519866e6848b9501039940dc2c6f0508668

That is commit c8832519 on the branch thornswood/engine-changes: SkyMP with
Thornswood's changes on top. The licence texts are in the same place, in each
part's LICENSE file. The source of SkyMP's in-game interface is SkyMP's own,
at https://github.com/skyrim-multiplayer/skymp.

## Microsoft WebView2 SDK licence

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
