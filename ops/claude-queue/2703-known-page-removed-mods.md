# #2703 Known Issues page names removed mods

PR #2704 (merged to main) changes site/data/board.json, the known board. The live Known Issues page still has the old sentence until the site is deployed.

## Live steps (Claude)
1. After #2704 is on main, deploy the site the usual way (Deploy-Docs -Site). Herald does not run Deploy-Docs or touch live.
   - If the live hub's known board has been edited since, make the same edit there instead. Do not overwrite the board.
2. The edit: in "What the collection took out", the lead's last paragraph changes from
   "SunHelm's diseases went with it. Disease comes back from the server instead: Injury, being downed and disease is on the roadmap."
   to
   "Disease comes back from the server instead of from a mod: Injury, being downed and disease is on the roadmap."
3. Check /known. SunHelm, TavernGames and Respawn appear only in their Out rows. The roadmap pointer is still above the table.