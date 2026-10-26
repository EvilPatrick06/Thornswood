# Licensing

Thornswood's own code is under the MIT licence in `LICENSE`. This file says
what that licence does not cover, and holds the terms every contributor
agrees to. `LICENSE` holds the MIT text and nothing else, so GitHub can read
it as MIT; anything added to that file stops GitHub naming the licence
(measured with licensee 10.1.0, the library GitHub uses, on 26 October
2026, #3688).

Patrick decided on 26 October 2026 that Thornswood's own code goes under MIT
(#3688, #3721). Contributor term 2 below is what lets the code move from all
rights reserved to MIT.

## What the MIT licence covers

Thornswood's own code and the documents that come with it: the launcher, the
installer and its setup program, the game plugins and overlays (the
JavaScript and HTML under `game`), the gamemode and its scripts, the
website's code, the Discord bot, the voice service, the scripts, the tests
and the documents.

## What it does not cover

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
5. **Thornswood's lore, art and music, its game plugins, and the Thornswood
   name and logo.** These are not under MIT. Until Patrick chooses a licence
   for them, they stay all rights reserved: Copyright (c) 2026 Patrick
   (EvilPatrick06). That covers:
   - the lore, under `lore`, and the public pages under `site/data/site`;
   - the pictures, icons, meshes and textures (`launcher/art`, the launcher's
     icons and logos, the pictures under `site/public` and `bot`, the
     pictures under `game/ui`, and `game/menu`);
   - the music, `game/ui/thornswood-theme.mp3`, which an artist made for
     Thornswood (`THIRD-PARTY.md`, "Made for Thornswood by somebody else");
   - Thornswood's own records in `game/content/Thornswood-Content.esp`,
     `Thornswood-Last.esp` and `Thornswood-WoodworkerTrail.esp`;
   - the name Thornswood and its logo, in any form.

   MIT, once given, cannot be taken back, so none of these is put under it
   before that choice is made. A collaborator may use them to work on
   Thornswood. What Thornswood hands people (the launcher, the installer,
   the game files, the content plugin on Nexus Mods) may be used to play on
   Thornswood's servers.

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
