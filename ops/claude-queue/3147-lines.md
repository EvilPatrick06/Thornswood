# 3147 One file of hints and lore lines, on the site's front page and the bot's status

- **Issue / PR:** #3147, #3447 (merged 5fe98cf9). This note was added after the merge by the Cloud Desk.
- **Where:** the live site (Deploy-Docs -Site) and the live bot (Install-Bot -CodeOnly). No game server, no Discord layout change.
- **Needs first:** the next main Ship, and 3138-site-refresh.md's step 1 in the same sitting. Deploy-Docs sends main's site whole, and main carries #3445's pages, which wait on that Ship. Run this note right after 3138's step 1, which sends lines.md, server.js and home.html too.
- **Staff notice:** no.

## Run, in this order, from the repository root at main after the main Ship

1. **The site.** 3138-site-refresh.md's step 1 (`Deploy-Docs.ps1 -Site`, with or without `-Docs help` as that note says) carries this change. Skip this step only if that step has run in the same sitting.

       pwsh scripts/deploy/Deploy-Docs.ps1 -Site

2. **The bot.** It already runs #3447's code: the #3140 install at 4:43 PM
   on 26 Oct went out from main 38e8baaf, and since then it logs "status
   lines: the site handed out none" every fifteen minutes, as it should with
   no `lines` on the live site. So after step 1 nothing needs installing; it
   picks the lines up on its next pass, within fifteen minutes. Run this
   only if bot.py has changed on main since 38e8baaf:

       pwsh scripts/deploy/Install-Bot.ps1 -CodeOnly

   It should end with PASS and SWAP OK.

## Check afterwards

- https://thornswood.net/api/public has `lines` with `hints` and `lore`.
- The front page's quote under The World is a lore line with its source, and changes between reloads.
- `pwsh scripts/vps/Show-BotLog.ps1` has no `status lines:` line saying it could not set one or that the site handed out none.
- Then delete this note and put what ran on #3147. #3147 stays open for its Main test task, which is in #3447's body.
