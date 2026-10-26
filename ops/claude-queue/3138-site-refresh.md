# 3138 Every site page says how the world works on main, with one copy of each text

- **Issue / PR:** #3138, the pull request this note came in with.
- **Where:** the live site (Deploy-Docs). No game server, no bot install, no Discord.
- **Needs first:** the next main Ship, the first one cut from main at or after this pull request's merge. The pages describe main's game (the nine town start spots, kits that mend, tempering cut, the apprentice prompt, the cut town fillers), and the live server runs release 1.2.5 until that Ship, so the pages go live with it, not before. Step 1's `-Docs help` also puts #2705's hair dye section live, so it waits on 2705-hair-dye-help.md's first step as well (see step 1).
- **Staff notice:** no. Pages change, and nothing staff do.

What it does:

- Join, Help, Classes, Rules, Privacy, Cookies, Terms, Credits and the home page are rewritten against main's code: no "being built" or "not yet" line is left, because the roadmap and Known Issues say what is coming and what is broken.
- Privacy says that voice shows each launcher's internet address to the others in the room (#3431), and who on staff reads what since #3317. Rules says who reads chat. Cookies lists every cookie and every browser storage key the site uses (#2763), and Privacy points at it instead of keeping a second list.
- The link previews and tab titles come only from `BLURB` in site/server.js; home.js no longer carries a copy.
- Terms, Privacy and Rules show Last changed: 26 October 2026, with their new wordings in site/public/page-versions.json.

## Run, in this order, from the repository root at main after the main Ship

1. **The site: app, public pages and Help.**

       pwsh scripts/deploy/Deploy-Docs.ps1 -Site -Docs help

   The site should answer at the end. Run it with `-Docs help` only once 2705-hair-dye-help.md's first step holds (the live server runs the hair dye code), because help.md on main carries #2705's "Dyeing your hair" section. Until then, if the main Ship has gone out, run `pwsh scripts/deploy/Deploy-Docs.ps1 -Site` alone, leave `-Docs help` for the run of 2705's note, and say so on #3138.

## Check afterwards

- https://thornswood.net/join says your first character arrives at the town's start spot, not its inn, and names the nine towns.
- https://thornswood.net/cookies has two tables, Cookies and Browser storage, and https://thornswood.net/privacy has no cookie table, only the line pointing at /cookies.
- https://thornswood.net/api/page/terms, /privacy and /rules each return a `changed` of 2026-10-26.
- The home page has no "Being built" block, only the line pointing at the roadmap.
- Pasting https://thornswood.net/cookies into Discord shows "Every cookie and piece of browser storage this site uses".
- Then delete this note, put what ran on #3138, and close #3138 as completed, with #2763 and #3431 if the pages read as above.

## Risks

- None for the game. The site restarts for a moment, as every Deploy-Docs -Site does.

## Release notes (draft)

none (site text only)

## News post (draft)

none
