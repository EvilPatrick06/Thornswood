# 3140 The roadmap has no Done section, and a merged fix takes its known post down

- **Issue / PR:** #3140, the pull request this note came in with. Patrick asked for it on 26 Oct: "Done section needs removed from the roadmap".
- **Where:** the live bot (Install-Bot -CodeOnly). No site deploy (the site changes in this pull request are comments only), no Ship, no game server.
- **Needs first:** nothing.
- **Staff notice:** no. Nothing staff do changes.

What it does:

- The bot builds the roadmap from open issues only, so `data\from-bot\lists.json` carries the lanes Being built now, Next and Later and no Done lane. A roadmap issue that closes leaves the roadmap.
- The site draws whatever lanes the bot wrote, so /roadmap and the home page's roadmap lose Done on the bot's next pass.
- #known-issues and /known drop a finding once Done on merge has written its `Pull request #N merged (...)` comment on it. Until now only the `board: Done` label counted, and board-status.yml takes that off within a minute, so findings in Done stayed up. On 26 Oct those were #613 (forge list) and #1626 (Cheat Death); both waited on a main Ship. KNOWN_FORM goes to 5, so every finding's comments are read once on the first pass.

## Run, from the repository root at main after the merge

1. **The bot.**

       pwsh scripts/deploy/Install-Bot.ps1 -CodeOnly

   It should end with the swap and PASS.

2. **#3539 takes over what #613's known post still warns about**, once the bot log shows #613 taken down (the forge list's unsorted rows, the six Dwarven Metal Ingot rows and the pack popup, which #3302 did not fix). Write the comment first, then the labels, so the first pass that sees the issue posts these words:

       gh api -X POST repos/EvilPatrick06/Thornswood/issues/3539/comments -f body="Known issue: Forge menu repeats rows, unsorted
       The forge menu lists every recipe, including ones your character cannot make yet, in no helpful order. Dwarven Metal Ingot shows up six times, because six kinds of scrap each have their own recipe, and the box that pops up when something goes into your pack is too wide and sits in the wrong place. A recipe your character cannot make is refused when you try it, and nothing is used up. No need to report these again, but a recipe that gets made when it should have been refused is still worth a post."
       gh api -X POST repos/EvilPatrick06/Thornswood/issues/3539/labels -f "labels[]=Main Findings" -f "labels[]=Dev Findings"

   Each prints the comment or the labels as JSON.

## Check afterwards

- https://thornswood.net/api/roadmap within five minutes lists the lanes Being built now, Next and Later and no Done.
- https://thornswood.net/roadmap shows no Done section.
- `pwsh scripts/vps/Show-BotLog.ps1` shows `known issues: took #613 down` and `took #1626 down`, each with "done-on-merge wrote its merged fix on it", and https://thornswood.net/api/page/known no longer lists "Forge list is messy" or "Cheat Death perk never saves you".
- Within five minutes of step 2, https://thornswood.net/api/page/known lists "Forge menu repeats rows, unsorted".
- Then delete this note and put what ran on #3140 and #3539.

## Risks

- The bot restarts for under a minute; Install-Bot puts the old code back if the new one does not come up.

## Release notes (draft)

none (bot only)

## News post (draft)

none
