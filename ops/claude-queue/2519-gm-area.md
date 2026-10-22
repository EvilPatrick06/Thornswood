HOLD CLEARED (Patrick, 21 Oct 2026, on the board review page). NOT RUN YET, 21 Oct 11:35 PM: Setup-Discord.ps1 asks for the bot token with Read-Host -AsSecureString (line 95). The Releases desk runs non-interactively and never types a secret, so it cannot run this. Either a person runs it in a terminal and pastes the token, or Setup-Discord learns to take the token the bot already holds on the box (C:\Thornswood-Bot\bot.env.json, the way Install-Bot reads it) and run there.

# 2519 GM-only Gamemasters category on the live Discord

- **Lane:** Herald (Website / Discord setup)
- **Issue / PR:** #2519, #2547 (merged as 1db6327b)
- **Channel:** live Discord guild (Setup-Discord). No Ship, no deploy, no VPS bot install, no site.
- **Staff status updates:** #staff-updates (1549254991082946570)
- **Needs first:** nothing. The plan is on main. Do not run Setup-Discord against a scratch guild only and call it done: the live Thornswood guild is the target.

## Run
From a fresh worktree at origin/main at or after the merge of #2547, with the bot token ready (Setup-Discord asks for it without showing it):

    .\scripts\deploy\Setup-Discord.ps1

No `-Posts`, no `-Prune`. It only adds what is missing: the **Gamemasters** category, #gm, #gm-discipline and GM Voice, with `gm` overwrites. Existing channels are left alone.

## Check afterwards
- Setup-Discord prints that it made category Gamemasters and the three channels (or "already there" if a second run).
- In Discord, as someone with only Member (and no GM rank): the Gamemasters category is invisible.
- As Lead Gamemaster, Gamemaster or Trial Gamemaster: the category shows #gm, #gm-discipline and GM Voice; nothing else is in it; nothing public.
- As Moderator (without a GM rank): still invisible.
- Owner / Dev: visible through Administrator.

## Risks and how to put it back
- Setup-Discord never deletes unless `-Prune` is passed; this note does not pass it.
- To remove the category by hand later, drag the channels out or delete them in Discord; do not re-run with `-Prune` unless Patrick asks.
- `scripts\oneoff\Undo-DiscordBuild.ps1` is not for this; leave it alone.

## Release notes (draft)
none (Discord layout only; people do not see the GM area)

## News post (draft)
none

## Test task (draft, for closing #2519 once Setup-Discord has run on the live guild)
Test task: The GM area is only for gamemasters
1. As a gamemaster, open Discord and find the Gamemasters category.
2. Confirm it has a GM text room, a discipline room, and a GM voice room, and nothing public.
3. As a regular member (no GM rank), confirm that category does not appear at all.
What should happen: only gamemaster ranks see the category; members and moderators without a GM rank do not.
