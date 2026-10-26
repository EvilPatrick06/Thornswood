# 3137 Known Issues holds only real bugs, and Help holds what is on purpose

- **Issue / PR:** #3137, the pull request this note came in with.
- **Where:** the live site (Deploy-Docs) and the live Discord (Setup-Discord -OnBox). No Ship, no game server, no bot install.
- **Changed by #3140:** the two boards this note replaced are gone; see step 1.
- **Needs first:** the main Ship. Main's join.md and rules.md carry #3445's words since 26 Oct, and #start-here, #welcome, #faq and #game-rules are read out of them, so step 2 would put those words in Discord before the release they describe (measured 26 Oct, see #3137). Step 1's `-Docs help` also puts #2705's hair dye section live (see step 1).
- **Staff notice:** no. Pages and two Discord posts change, and nothing staff do.

What it does:

- The known board (thornswood.net/known) goes from fourteen rows and three prose sections to the five things actually broken, each naming its board issue (#503, #2710, #3434, #3435, #3436) in the row's `issue` field, which the page does not show. Since #3140 the page is those issues' `Known issue:` comments, the same as #known-issues, and no step here puts it live.
- The roadmap loses its Later row "Bard instruments", which is a bug on the board now (#3434). Since #3140 the roadmap is built from `roadmap:` labels, and that issue carries none.
- help.md's Things that are normal here takes what is on purpose (what the server owns, fishing with a pole, mods in batches) and the old launcher paragraph; the menus that still reset come off that list, since they are a bug.
- join.md, the /known link preview and the home page say what /known is now.
- The Discord welcome and FAQ stop calling /known "broken on purpose", and the FAQ's NPC answers say what #504 made true (the server runs the NPCs). Both carry their changelog line.

## Run, in this order, from the repository root at main after the merge

1. **The site: app, public pages and Help.**

       pwsh scripts/deploy/Deploy-Docs.ps1 -Site -Docs help

   The site should answer. Since #3140 the known board and the roadmap board are gone: /known and /roadmap are written from the issue board by the bot (3140-site-lists.md), so there is no `-Board` step here, and the rows #3137 cleaned are the `Known issue:` comments on #503, #2710, #3434, #3435 and #3436. help.md on main already carries #2705's "Dyeing your hair" section, so this puts that live too. Run this step only once 2705-hair-dye-help.md's first step holds (the live server runs the hair dye code); until then run it without `-Docs help`, leave `-Docs help` for the run of 2705's note, and say so on #3137.

2. **Discord: the welcome and the FAQ.**

       pwsh scripts/deploy/Setup-Discord.ps1 -OnBox -Audit
       pwsh scripts/deploy/Setup-Discord.ps1 -OnBox -Posts

   Without `-Posts` no post changes. The audit should name only the
   changelog lines -Posts adds, and the second should end with nothing under
   "did not manage". It refuses before asking anything of Discord when a doc
   has words with no change line; then the change line goes in content.py
   first. Patrick said yes to this step on 26 Oct, so it needs no second ask.

## Check afterwards

- Once 3140-site-lists.md has run: https://thornswood.net/api/page/known has one section, Broken right now, with the issues #known-issues holds, and names no SunHelm, no creation hall and no load order rule.
- https://thornswood.net/help has the server owns, fishing and batches lines under Things that are normal here, and the launcher before 26 September paragraph under When something goes wrong.
- #welcome's known issues line and #faq's Fast travel and Something's broken answers read as content.py has them.
- Then delete this note, put what ran on #3137, and close #2703 as completed (its sentence and its failing harness went with the removed mods table; 2703-known-page-removed-mods.md went in this pull request).

## Risks

- None beyond a site restart of a few seconds.

## Release notes (draft)

none (site and Discord text only)

## News post (draft)

none
