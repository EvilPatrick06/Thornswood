# 3140 A known post comes down when its fix lands, not for any merged pull request

- **Issue / PR:** #3140, the pull request this note came in with. Patrick picked this on the report page card q-3140-known-takedown (option B, 26 Oct).
- **Where:** the live bot (Install-Bot -CodeOnly). No site deploy, no Ship, no game server.
- **Needs first:** nothing.
- **Staff notice:** no. Discord posts change, and nothing staff do changes.

What it does:

- #known-issues and /known keep a finding until it has a `Test task:` comment or the `board: Done` label (done-on-merge.yml puts both on a merged fix), or it closes. A merged pull request alone, Refs or not, no longer takes a post down.
- The bot's first pass drops the old rule's record (`known_changed` in `data\known-issues.json`), so the open findings that rule kept off come back, each with its `Known issue:` words. On 26 Oct those were #503, #516, #613, #1626 and #2244 (#385 has a test task and stays off).

## Run, from the repository root at main after the merge

1. **The bot.**

       pwsh scripts/deploy/Install-Bot.ps1 -CodeOnly

   It should end with the swap and PASS.

## Check afterwards

- `pwsh scripts/vps/Show-BotLog.ps1` shows the known pass posting the findings named above, and no `known issues: took #N down` line for any of them.
- https://thornswood.net/api/page/known lists them within five minutes (the bot writes the site's list on the same pass).
- Then delete this note and put what ran on #3140.

## Risks

- The bot restarts for under a minute; Install-Bot puts the old code back if the new one does not come up.

## Release notes (draft)

none (bot only)

## News post (draft)

none
