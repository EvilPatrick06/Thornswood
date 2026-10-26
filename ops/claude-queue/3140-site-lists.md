# 3140 The site's Known Issues page and roadmap come from the issue board

- **Issue / PR:** #3140, the pull request this note came in with.
- **Where:** the live site (Deploy-Docs) and the live bot (Install-Bot, a full run so the bot gets its new folder rights). No Ship, no game server.
- **Needs first:** nothing. Run the steps in this order: the bot cannot be installed until the site has made the folder it writes.
- **Staff notice:** no. Two public pages change where their words come from, and nothing staff do changes.

What it does:

- The bot writes `C:\Thornswood-Docs\data\from-bot\lists.json` after every pass over the board: the #known-issues list word for word, and a roadmap built from the `roadmap: now`, `roadmap: next` and `roadmap: later` labels and each issue's last `Roadmap:` comment, with closed-as-done issues under Done.
- /known, /api/page/known, /roadmap, /api/roadmap and the front page's roadmap read that file. The known and roadmap boards in board.json, and the hub's /hub/known page, are gone.
- A merged pull request takes a known post down only when it says `Refs #N` or a closing word for that issue. The five posts #3437's body named were taken down by a mention alone; the bot's first pass on this code reads every finding again (`KNOWN_CHANGED_FORM` 2) and puts back the ones nothing has been done about.

## Run, in this order, from the repository root at main after the merge

1. **The site: the app, which makes `data\from-bot`.**

       pwsh scripts/deploy/Deploy-Docs.ps1

   It should end with the site answering. Until step 2 runs, /known and /roadmap say the list could not be read from the issue board; that is expected for those few minutes.

2. **The bot: a full run, so Bot-Service gives it Modify on `data\from-bot`.**

       pwsh scripts/deploy/Install-Bot.ps1 -NoToken

   It should print a line granting `the bot's account Modify, on the known issues and roadmap it writes for the site`, then the swap and PASS. If it stops with "the site has not made ... data\from-bot yet", step 1 did not run on the box; run it again.

## Check afterwards

- `pwsh scripts/vps/Show-BotLog.ps1` shows no `could not write the site's lists` line, and the `known issues:` lines name the posts it put back.
- https://thornswood.net/api/page/known ends with "Read from the issue board" and a time from the last few minutes, and lists what #known-issues holds.
- https://thornswood.net/api/roadmap has `unread` false and a lane for each roadmap label in use, with Done last.
- #known-issues in Discord has the open findings again, each with no merged `Refs` pull request and no `Test task:` comment.
- Then delete this note, put what ran on #3140, and move #3140 to Done once both checks hold.

## Risks

- The site restarts for a few seconds in step 1, and the bot for under a minute in step 2. Discord is not left without the bot: Install-Bot puts the old code back if the new one does not come up.
- The live board.json still holds the old known and roadmap boards. Nothing reads them, and the hub cannot open them; they are left for the follow-up that retires the hub's boards.

## Release notes (draft)

none (site and bot only)

## News post (draft)

none
