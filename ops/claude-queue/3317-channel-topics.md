# 3317 Every channel's description from the plan

- **Issue / PR:** #3317, the pull request this note came in with.
- **Where:** the live Discord (Setup-Discord -OnBox). No bot install, no Ship, no game, no site.
- **Needs first:** nothing. Patrick asked for it on 23 Oct ("We also need to go through and fix old descriptions like this", with #general-chat's description sending bug reports to #unknown).
- **Staff notice:** no. Descriptions change, and nothing staff do.

What it does:

- Every text, forum and announcement channel the plan makes has a description (topic) in `bot/Build-Discord.py`, and each build sets it. #general-chat's topic was hand-written and named a channel deleted since. It keeps Patrick's words, and now sends bug reports to #test-findings and clips to #media.
- A topic names a channel as `<#KEY>`, and the build turns that into a link to the channel the plan has under that key. A rename can no longer leave a link to a deleted channel behind.
- `-Audit` has a "Channel topics" section. It flags any topic that differs from the plan, a topic the plan does not set, and a topic on any channel that names a channel that is gone (which Discord shows as #unknown).

## Run, in this order, from the repository root at main after the merge

1. **What the topics are now, changing nothing.**

       pwsh scripts/deploy/Setup-Discord.ps1 -OnBox -Audit

   The "Channel topics" section lists every channel whose topic is not the plan's, with the live text and the plan's. Put that section on #3317 before step 2, so the old words are on record.

2. **Set them.**

       pwsh scripts/deploy/Setup-Discord.ps1 -OnBox

   It should end with nothing under "did not manage".

3. **The audit again.**

       pwsh scripts/deploy/Setup-Discord.ps1 -OnBox -Audit

   The "Channel topics" section should list nothing, apart from a topic on a channel the plan never makes (#gm), which it names with its text. Put the output on #3317.

## Check afterwards

- #general-chat's description links #test-findings and #media, and no channel's description shows #unknown.

## Risks

- A hand-written topic on a channel the plan now covers is replaced. Step 1 puts the old text on #3317 first.

## Release notes (draft)

none (Discord only)

## News post (draft)

none
