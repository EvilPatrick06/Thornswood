# 3317 The sixteen factions in Discord, and who gets the dev build

- **Issue / PR:** #3317, the pull request this note came in with.
- **Where:** the live Discord (Setup-Discord -OnBox), the bot on the box (Install-Bot -CodeOnly), and the site on the box (Deploy-Docs, then Set-DiscordLogin -Access).
- **Needs first:** #3343 merged and its runs done (Onboarding off, -Give, the council in STAFF_ROLES). Patrick approved the faction lore on 22 Oct, so nothing waits on him.
- **Staff notice:** none. Staff do nothing differently: the factions are in-world, and the dev build gate only narrows who installs it.

## Run, in this order, from the repository root at main after the merge

1. **The bot: the Leader's faction member panel goes up in #seats, and the Faction Leader form lists all 16 factions.**

       pwsh scripts/deploy/Install-Bot.ps1 -CodeOnly -NoPause

   It should print SWAP OK and the bot watching its server. Until step 3 has made #seats, bot.log says the panel waits for it. The panel is posted when the bot next starts, so step 4 restarts it.

2. **Discord: read first.**

       pwsh scripts/deploy/Setup-Discord.ps1 -OnBox -Check

   It should list, and change nothing:
   - **Roles it would make:** the 16 member roles (Imperial Embassy, Thalmor, Companions, College of Winterhold, Bards College, Thieves Guild, Dark Brotherhood, Vigilants of Stendarr, Dawnguard, Silver Hand, Forsworn, Orc Strongholds, Khajiit Caravans, Blades and Volkihar Clan, plus Free Skyrim Trading Company, which is renamed rather than made); the 11 new Leader roles; and Business Owner, unless the hand-made one is already there.
   - **The rename:** the Trading Company role becomes Free Skyrim Trading Company.
   - **The Factions category:** #seats and one channel per faction, 17 channels in all.

3. **Discord: the build.**

       pwsh scripts/deploy/Setup-Discord.ps1 -OnBox

   It should make what step 2 listed and end with nothing under "did not manage".

4. **The bot again, so the faction panel is posted now that #seats exists.**

       pwsh scripts/deploy/Install-Bot.ps1 -CodeOnly -NoPause

   bot.log should say "faction panel posted in #seats".

5. **The site: the dev build goes to Owner, Co-Owner, Dev and the leads only (access.devBuild), access.company names the renamed role, and the rules and /world pages say how a Jarl seat is taken.**

       pwsh scripts/deploy/Deploy-Docs.ps1 -Site

6. **The live access lists, written whole.** Run this right after step 3: until it runs, the live config still names "Trading Company", so no company worker can make a company sale. It restarts the site, which takes a few seconds.

       pwsh scripts/deploy/Set-DiscordLogin.ps1 -NoSecrets -Access 'company=Free Skyrim Trading Company','devBuild=Owner,Co-Owner,Lead Dev,Lead Gamemaster,Lead Loremaster,Lead Moderator,Lead Content Creator,Lead Support,Dev','dev=Owner,Co-Owner,Lead Dev,Dev,Lead Gamemaster,Gamemaster,Trial Gamemaster,Lead Loremaster,Loremaster','admin=Owner,Co-Owner,Lead Dev,Dev','play=Owner,Co-Owner,Lead Dev,Lead Gamemaster,Lead Loremaster,Lead Moderator,Lead Content Creator,Lead Support,Dev,Gamemaster,Trial Gamemaster,Loremaster,Moderator,Content Creator,Support,Playtester'

   It should print one "access <list>:" line for each of the five lists, with the names above.

## Check afterwards

- `pwsh scripts/deploy/Setup-Discord.ps1 -OnBox -Audit`:
  - It reports no difference in Factions.
  - "role Trading Company" is gone, and so is "role Faction Owner is not in the plan". If Faction Owner is still listed, it waits for the faction books change, which reads the Leader roles instead.
- Sign in at thornswood.net as somebody who holds Dev. The account page offers the dev build.
- Somebody who holds only Gamemaster is still staff in the game, and is not offered the dev build.

## Risks

- The site is down for a few seconds in step 6 while it restarts.
- Between steps 3 and 6, a company worker cannot make a company sale (see step 6).
- Nothing is deleted. The Trading Company role is renamed, so everybody holding it keeps it.

## Release notes (draft)

none

## News post (draft)

none
