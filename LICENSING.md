# Licensing

Thornswood's own code is under the MIT licence in `LICENSE`. Its own lore,
art and music are under Creative Commons Attribution-NonCommercial-ShareAlike
4.0 International (CC BY-NC-SA 4.0). The Thornswood name and logo are under
neither. This file says what each licence covers and what neither does, and
holds the terms every contributor agrees to.

`LICENSE` holds the MIT text and nothing else, so GitHub can read it as MIT:
anything added to that file stops GitHub naming the licence (measured with
licensee 10.1.0, the library GitHub uses, on 26 October 2026, #3688).

Patrick decided both on 26 October 2026: MIT for the code (#3688, #3721), and
CC BY-NC-SA 4.0 for the lore, art and music Thornswood owns, with the name and
logo all rights reserved. Contributor term 2 below is what lets what
contributors made move from all rights reserved to these licences.

## What the MIT licence covers

Thornswood's own code and the documents that come with it: the launcher, the
installer and its setup program, the game plugins and overlays (the
JavaScript and HTML under `game`), the gamemode and its scripts, the
website's code, the Discord bot, the voice service, the scripts, the tests
and the documents (but not the public pages under `site/data/site`, which go
with the lore).

## What MIT does not cover

1. **The SkyMP fork in `engine/skymp`.** It keeps its own licences, which
   are in its own files: its `TERMS.md` and a `LICENSE` in each subproject's
   folder. skymp5-client, skyrim-platform, skymp5-front, skymp5-scripts and
   savefile are under the GNU General Public License version 3, skymp5-server
   is under the GNU Affero General Public License version 3, and libespm,
   papyrus-vm, skymp5-functions-lib and viet are under MIT. Upstream's
   `CLA.md` covers only code sent back to upstream SkyMP.
2. **Every file `THIRD-PARTY.md` lists**, whether it ships or only sits in
   this repository. Each stays under its own licence, and `THIRD-PARTY.md`
   says which, and where its source is.
3. **Other people's records inside Thornswood's plugins and data.**
   `game/content/Thornswood-Last.esp` copies cells, worldspaces, quests,
   locations and recipes from the collection's plugins, and
   `game/content/Thornswood-WoodworkerTrail.esp` overrides 53 recipes of five
   of them. The data files built from the load order (under `game/data`)
   hold what was read out of those plugins. Those records and that data stay
   their authors' (#2791). Every plugin also overrides records of Bethesda's
   masters, which stay Bethesda's.
4. **Bethesda's files and the mods on Nexus Mods.** They are not in this
   repository and are never put in it. Each person gets the game from
   Bethesda and each mod from its own page, under its author's terms. The
   files the launcher makes from a person's own game or mods are made on
   their machine and never handed on (`THIRD-PARTY.md`, "Bethesda's own
   files, made on each machine").
5. **Thornswood's lore, art and music.** Those are under CC BY-NC-SA 4.0
   (next part).
6. **The Thornswood name and logo.** They stay all rights reserved:
   Copyright (c) 2026 Patrick (EvilPatrick06). Neither licence here grants
   any right to the name or the logo, in any form, and CC BY-NC-SA 4.0
   itself does not license trademarks (its section 2(b)(2)). The files
   whose picture is the logo stay all rights reserved as a whole:
   `launcher/logo.png`, `logo-dev.png`, `logo-192.png`, `app.ico` and
   `app-dev.ico`; `site/public/logo.png`, `logo-28.webp`, `logo-56.webp`,
   `logo-84.webp`, `favicon.ico`, `icon-192.png`, `presence.png` and
   `og.png`; and `bot/thornswood-bot-1024.png`, `thornswood-bot-512.png`
   and `server-icon-512.png`.
7. **Thornswood's own records in its .esp plugins**
   (`game/content/Thornswood-Content.esp`, `Thornswood-Last.esp` and
   `Thornswood-WoodworkerTrail.esp`). They are neither code nor lore, art or
   music, and the 26 October choice does not name them, so they stay all
   rights reserved until a licence is chosen for them. What Thornswood hands
   people, the content plugin on Nexus Mods among it, may be used to play on
   Thornswood's servers.

## Lore, art and music: CC BY-NC-SA 4.0

Lore, art and music Thornswood owns are under the Creative Commons
Attribution-NonCommercial-ShareAlike 4.0 International licence:
https://creativecommons.org/licenses/by-nc-sa/4.0/ (the legal code is at
https://creativecommons.org/licenses/by-nc-sa/4.0/legalcode). Anybody may
share and adapt them, not for money, if they credit "Thornswood
(thornswood.net)", link the licence, say what they changed, and put what they
make from them under the same licence. That covers:

- the lore, under `lore`, and the public pages under `site/data/site`;
- the pictures, meshes and textures `records/asset-provenance.json` marks as
  Thornswood's own (`ours`, or `derived` from one of those): the art under
  `launcher` and `launcher/art`, `site/public`, `bot`, `game/ui` and
  `game/menu`, except the logo files in point 6 above. Where a picture shows
  the Thornswood name or logo, the picture is under CC BY-NC-SA 4.0 and the
  name and logo in it are not.

It does not cover:

- art whose maker is not recorded (`not-published` or `unconfirmed` in
  `records/asset-provenance.json`, such as `launcher/art/thornswood-art-1536.png`
  and `thornswood-banner-1672.png`). Thornswood cannot license what it cannot
  show it owns; each goes under CC BY-NC-SA 4.0 once its maker and terms are
  recorded.
- the theme, `game/ui/thornswood-theme.mp3`. An artist made it for
  Thornswood, and the terms between Patrick and the artist are not written
  down (`THIRD-PARTY.md`, "Made for Thornswood by somebody else"), so
  Thornswood does not own it to license. It stays the artist's until written
  terms say otherwise. Thornswood owns no other music today.

`records/asset-provenance.json` records, for each picture, sound, mesh and
plugin in the repository, who made it, under what terms, and what is still
unknown.

## Contributor terms

Everybody who contributes to this repository (code, text, art, data or any
other change, by commit, pull request or any other way) agrees to these
terms once, in #staff-updates, before their first contribution. Agreeing
covers what they contributed before that as well. Until 26 October 2026
these terms were in `LICENSE`; they are the same terms.

1. You keep the copyright in what you contribute.
2. You give the owner of Thornswood a permanent, worldwide, free,
   non-exclusive and irrevocable licence to use, copy, change, publish,
   distribute and sublicense what you contribute, as part of Thornswood or
   on its own, and to put it under any other licence later, an open one
   included.
3. You have the right to give that licence: the work is your own, or its
   owner has given you leave, and the pull request says whose it is.
4. You give it as it is, with no warranty of any kind.

Each pull request says whose the work is on the "Whose work" line of its
template (`.github/pull_request_template.md`).

Somebody outside the team, who cannot say so in #staff-updates, agrees to
these terms by opening the pull request, and signs off every commit in it
(`git commit -s`, which adds a `Signed-off-by:` line with their name and
email) to certify the Developer Certificate of Origin 1.1
(https://developercertificate.org) for it.
