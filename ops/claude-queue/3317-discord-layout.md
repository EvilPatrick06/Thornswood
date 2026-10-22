# 3317 The Discord layout: a category per faction, the ticket split, the bot keeps Administrator

- **Issue / PR:** #3317, the pull request this note came in with.
- **Where:** the live Discord (Setup-Discord -OnBox), then the bot on the box (Install-Bot -CodeOnly). No Ship, no game, no site.
- **Needs first:** nothing for steps 1 to 5. Step 6 (-Prune) waits on Patrick's yes on the page, after step 5 says what it would delete.
- **Staff notice:** yes, after step 4, because where staff answer tickets changes (step 4 has the line).

What it does, all from the plan in `bot/Build-Discord.py` (docs/systems/discord.md is the plan in words):

- **A category per faction** (Patrick, 22 Oct; page card q-3317-faction-category, A, built while it waits): each of the 16 factions gets a category named after it with `#<faction>-announcements`, its chat (moved from Factions by name), `#<faction>-court`, `#<faction>-seats` and its voice room (moved from Factions). 32 new roles: `<short> Court` and `Steward of <short>` per faction. The Leader's panel goes in each `#<faction>-seats`, with Add and Remove for members, Court and Steward. The shared #seats and the Factions category are retired.
- **The ticket split** (page card q-3317-ticket-split, A): a Tickets category under Start Here with #get-help and #report-someone, and #apply-to-playtest, #apply-for-a-seat and #apply-for-staff in Applications, each with its own panel. #tickets-and-applications and the old #tickets are retired. #ticket-log stays.
- **The Voice category goes** (q-3317-discord-order, A): General, AFK and the jukebox to Out of Character, Help Voice becomes Support in the Support category, Support Voice becomes Support Staff, and each hold gets a `<Hold> Court` voice.
- **The sidebar order** is set every run, and **the role order** in one request, Patreon and Server Booster included, which fixes the seven role-order differences the audit listed.
- **The bot keeps Administrator** (Patrick, 22 Oct: "the bot will keep admin"). Nothing says to untick it, and the audit counts it as planned.
- The read-only posts' links to the site are real links, and they point at #apply-to-playtest and #get-help instead of #tickets-and-applications.

## Run, in this order, from the repository root at main after the merge

1. **Say what the build would do, changing nothing.**

       pwsh scripts/deploy/Setup-Discord.ps1 -OnBox -Check

   It should list the 16 faction categories and their channels as would make, each faction's chat and voice as would move from Factions, the Tickets category, the three apply channels, the 32 Court and Steward roles as would make, and "would move" for the role and channel order. It should print no failed line. If it does, stop and put the output on #3317.

2. **Build it, with the read-only posts.**

       pwsh scripts/deploy/Setup-Discord.ps1 -OnBox -Posts

   It should end with nothing under "did not manage". Each faction's chat and voice moved keep their history.

3. **The bot: a panel per ticket channel and per faction.**

       pwsh scripts/deploy/Install-Bot.ps1 -CodeOnly

   It should print SWAP OK and the bot watching its server. bot.log then says "ticket panel posted" in each of #get-help, #report-someone, #apply-to-playtest, #apply-for-a-seat and #apply-for-staff, "faction panel posted" in each `#<faction>-seats`, and that the old panels in #tickets-and-applications and #seats now say where the panels went.

4. **Tell staff where tickets are now.**

       pwsh scripts/ops/Say-Staff.ps1 -From claude -Text "Tickets have moved. Help tickets open from #get-help and reports from #report-someone, in the new Tickets category under Start Here. Applications open from #apply-to-playtest, #apply-for-a-seat and #apply-for-staff. Closed tickets still go to #ticket-log. Each faction now has its own category, and its Leader gives members, Court and Steward from the faction's seats channel. Open tickets in the old channel stay where they are until they are closed. <the pull request's link>"

   It prints the notice's id. `pwsh scripts/ops/Say-Staff.ps1 -Check <id>` should exit 0.

5. **The audit, and what -Prune would delete.**

       pwsh scripts/deploy/Setup-Discord.ps1 -OnBox -Audit
       pwsh scripts/deploy/Setup-Discord.ps1 -OnBox -Prune -Check

   The audit should say the bot holds Administrator, which it keeps, and list no role-order difference. The second should list #seats, #tickets-and-applications, #tickets, the stray #game-rules in In Character and the empty Factions, Voice and Help categories as would remove, and "left" for any of them with a ticket thread still open. Put both outputs on #3317, so Patrick's -Prune card can name exactly what goes.

6. **Only after Patrick's yes on the page:** delete what step 5 listed.

       pwsh scripts/deploy/Setup-Discord.ps1 -OnBox -Prune

   It should remove what step 5 listed and say "left" for any channel with an open thread in it, which stays until its tickets are closed.

## Check afterwards

- As somebody with only a faction's member role: the faction's category shows announcements (read only), its chat and its voice, and not its court or seats channel. Another faction's category does not show.
- As that faction's Leader: the seats channel shows the panel with six buttons, and Add to Court refuses somebody who is not a member.
- As somebody who just joined: Start Here, Tickets and Applications show, and each ticket channel has only its own kinds of ticket.

## Risks

- Setup-Discord -Posts rewrites #welcome, #rules, #start-here, #faq and #factions with their changelog lines; the words are the approved ones, only the links and channel mentions changed.
- A ticket open in #tickets-and-applications stays open there. -Prune leaves a channel with an open thread in it.
- Discord could refuse moving the Patreon or Server Booster role in the one order request; the run then lists it under "did not manage", and the audit says which roles are out of place.

## Release notes (draft)

none (Discord only)

## News post (draft)

none
