# 3438 A #known-issues post comes down only when its issue says so

- **Issue / PR:** #3438, the pull request this note came in with.
- **Where:** the live bot on the box (Install-Bot -CodeOnly). No Ship, no game server, no site, no Discord layout change.
- **Needs first:** nothing. If `3140-site-lists.md` has not run yet when this merges, its Install-Bot carries this change too: run that note, then delete both, and put what ran on #3438 as well as #3140.
- **Staff notice:** no. The bot restarts for a few seconds, and nothing staff do changes.

What it does: when GitHub's list of open Dev Findings or Main Findings leaves an issue out, the bot reads that issue itself before taking its #known-issues post down, and keeps the post when the issue is still open and labelled. On 22 Oct the lists left issues out and the same ten posts came down and went back up as a set three times.

## Run, from the repository root at main after the merge

    pwsh scripts/deploy/Install-Bot.ps1 -CodeOnly

It should end with the service running and the bot logged in (Show-BotLog.ps1 shows `up as` after the restart).

## Check afterwards

- `pwsh scripts/vps/Show-BotLog.ps1` a few minutes later: no `known issues: a pass failed` line, and no `took #N down` line for an issue that is still open with a Findings label.
- #known-issues still has one post per open finding with no merged change and no test task.
- A line `the open findings GitHub listed left out #N ... its post stays` means GitHub's list answered short again: put the time and the line on #3438.
- Then delete this note and put what ran on #3438.

## Risks

- The bot is down for the few seconds of the restart; tickets and buttons answer again once it is up.
- Each issue a list leaves out costs one more GitHub read that pass, so a pass that loses a whole list reads at most a few dozen issues, far inside the token's 5,000 an hour.
