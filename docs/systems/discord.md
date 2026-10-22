# The Discord layout

Made from `bot/Build-Discord.py` (ROLES and PLAN) by
`python3.12 bot/Build-Discord.py --layout`. Do not edit it by hand:
change the plan and run that, and `bot/test-3317-layout.py` fails when
the two differ. `Setup-Discord.ps1 -OnBox -Audit` says where the live
server differs from this page. Issue #3317 is where it was set out.

## The staff council

Each staff category has a lead, and the leads are the council: they
decide together, and Owner and Co-Owner make the final call. A person
holds at most one rank in a category (Lead Dev and Dev is a double);
ranks of two categories are fine, and Owner or Co-Owner with a lead is
fine. The audit reports every double.

Nobody on staff holds a seat of the world: a Jarl or a faction leader.
A Jarl is a faction leader with its own application, which lists only
the holds with no Jarl. The audit reports anybody holding both.

Leads and Support hold Manage Roles and give only their own
category's roles (Support gives Playtester). Every staff role sits
above every other role.

| Category | Its space | Lead | Ranks under the lead |
|---|---|---|---|
| Dev | Dev | Lead Dev | Dev |
| Gamemasters | Gamemasters | Lead Gamemaster | Gamemaster, Trial Gamemaster |
| Lore | Lore | Lead Loremaster | Loremaster |
| Moderation | Moderation | Lead Moderator | Moderator |
| Content | Content | Lead Content Creator | Content Creator |
| Support | Support | Lead Support | Support |

Holders of Moderator also talk in the Gamemasters space.

## Roles, top of the list first

| Role | Colour | Shown on its own | Permissions | Made by | What it is |
|---|---|---|---|---|---|
| Owner | #C9A24B | yes | Administrator | the build | Final decision with Co-Owner. Administrator. |
| Co-Owner | #C9A24B | yes | Administrator | the build | Final decision with Owner. Administrator. |
| Lead Dev | #9B7BD4 | yes | council set | the build | Leads the developers; on the council. |
| Lead Gamemaster | #3E8FBF | yes | council set | the build | Leads the gamemasters; on the council. |
| Lead Loremaster | #57B8A0 | yes | council set | the build | Leads the loremasters; on the council. |
| Lead Moderator | #6FA05A | yes | council set | the build | Leads the moderators; on the council. |
| Lead Content Creator | #D2603F | yes | council set | the build | Leads Thornswood's own content; on the council. |
| Lead Support | #B8A04E | yes | council set | the build | Leads support; on the council. |
| Dev | #9B7BD4 | yes | nothing of its own | the build | Builds the game, the launcher, the site and the bot. Plays the dev build. |
| Gamemaster | #4F9BC7 | yes | gamemaster set | the build | Runs scenes and events in the world. |
| Loremaster | #57B8A0 | yes | nothing of its own | the build | Makes and watches the lore, helps with events, and checks that gamemasters keep to the lore. |
| Trial Gamemaster | #79BCDB | yes | gamemaster set | the build | A gamemaster on trial; where every accepted GM starts. |
| Moderator | #6FA05A | yes | moderator set | the build | Moderates the Discord only. No staff powers in the game. |
| Content Creator | #D2603F | yes | nothing of its own | the build | Thornswood's own social media and content, not community creators. |
| Support | #C9B46A | yes | support set | the build | Answers help tickets and playtest applications, and gives Playtester. |
| Jarl of Whiterun | #E0C56A | yes | nothing of its own | the build | The seat of Whiterun. Applied for on its own application. |
| Jarl of Solitude | #E0C56A | yes | nothing of its own | the build | The seat of Solitude. Applied for on its own application. |
| Jarl of Windhelm | #E0C56A | yes | nothing of its own | the build | The seat of Windhelm. Applied for on its own application. |
| Jarl of Riften | #E0C56A | yes | nothing of its own | the build | The seat of Riften. Applied for on its own application. |
| Jarl of Markarth | #E0C56A | yes | nothing of its own | the build | The seat of Markarth. Applied for on its own application. |
| Jarl of Dawnstar | #E0C56A | yes | nothing of its own | the build | The seat of Dawnstar. Applied for on its own application. |
| Jarl of Morthal | #E0C56A | yes | nothing of its own | the build | The seat of Morthal. Applied for on its own application. |
| Jarl of Falkreath | #E0C56A | yes | nothing of its own | the build | The seat of Falkreath. Applied for on its own application. |
| Jarl of Winterhold | #E0C56A | yes | nothing of its own | the build | The seat of Winterhold. Applied for on its own application. |
| Jarl of Raven Rock | #E0C56A | yes | nothing of its own | the build | The seat of Raven Rock. Applied for on its own application. |
| Imperial Embassy Leader | #D9B45A | yes | nothing of its own | the build | Leads Imperial Embassy. Applied for as Faction Leader. |
| Thalmor Leader | #D9B45A | yes | nothing of its own | the build | Leads Thalmor Remnant. Applied for as Faction Leader. |
| Dark Brotherhood Leader | #D9B45A | yes | nothing of its own | the build | Leads Dark Brotherhood. Applied for as Faction Leader. |
| Companions Leader | #D9B45A | yes | nothing of its own | the build | Leads The Companions. Applied for as Faction Leader. |
| Free Skyrim Trading Company Leader | #D9B45A | yes | nothing of its own | the build | Leads Free Skyrim Trading Company. Applied for as Faction Leader. |
| Server Booster | #D98FB0 | yes | left to what makes it | Discord | Boosted the server. |
| Patreon | #F96854 | yes | left to what makes it | Patreon | Supports Thornswood on Patreon; Patreon gives and takes it. |
| Playtester | #C07A4E | yes | nothing of its own | the build | Plays the main build. Opens the Discord past Information. |
| Thalmor Boot-Licker | #9FBE6B | no | nothing of its own | the build | A Patreon tier; Patreon gives and takes it. |
| Talos Worshiper | #D8B24C | no | nothing of its own | the build | A Patreon tier; Patreon gives and takes it. |
| Milk Drinker | #BFD3DE | no | nothing of its own | the build | A Patreon tier; Patreon gives and takes it. |
| Citizen of Whiterun | #8FA9B8 | no | nothing of its own | the build |  |
| Citizen of Solitude | #8FA9B8 | no | nothing of its own | the build |  |
| Citizen of Windhelm | #8FA9B8 | no | nothing of its own | the build |  |
| Citizen of Riften | #8FA9B8 | no | nothing of its own | the build |  |
| Citizen of Markarth | #8FA9B8 | no | nothing of its own | the build |  |
| Citizen of Dawnstar | #8FA9B8 | no | nothing of its own | the build |  |
| Citizen of Morthal | #8FA9B8 | no | nothing of its own | the build |  |
| Citizen of Falkreath | #8FA9B8 | no | nothing of its own | the build |  |
| Citizen of Winterhold | #8FA9B8 | no | nothing of its own | the build |  |
| Whiterun Court | #A8977A | no | nothing of its own | the build |  |
| Steward of Whiterun | #A8977A | no | nothing of its own | the build |  |
| Guard of Whiterun | #A8977A | no | nothing of its own | the build |  |
| Solitude Court | #A8977A | no | nothing of its own | the build |  |
| Steward of Solitude | #A8977A | no | nothing of its own | the build |  |
| Guard of Solitude | #A8977A | no | nothing of its own | the build |  |
| Windhelm Court | #A8977A | no | nothing of its own | the build |  |
| Steward of Windhelm | #A8977A | no | nothing of its own | the build |  |
| Guard of Windhelm | #A8977A | no | nothing of its own | the build |  |
| Riften Court | #A8977A | no | nothing of its own | the build |  |
| Steward of Riften | #A8977A | no | nothing of its own | the build |  |
| Guard of Riften | #A8977A | no | nothing of its own | the build |  |
| Markarth Court | #A8977A | no | nothing of its own | the build |  |
| Steward of Markarth | #A8977A | no | nothing of its own | the build |  |
| Guard of Markarth | #A8977A | no | nothing of its own | the build |  |
| Dawnstar Court | #A8977A | no | nothing of its own | the build |  |
| Steward of Dawnstar | #A8977A | no | nothing of its own | the build |  |
| Guard of Dawnstar | #A8977A | no | nothing of its own | the build |  |
| Morthal Court | #A8977A | no | nothing of its own | the build |  |
| Steward of Morthal | #A8977A | no | nothing of its own | the build |  |
| Guard of Morthal | #A8977A | no | nothing of its own | the build |  |
| Falkreath Court | #A8977A | no | nothing of its own | the build |  |
| Steward of Falkreath | #A8977A | no | nothing of its own | the build |  |
| Guard of Falkreath | #A8977A | no | nothing of its own | the build |  |
| Winterhold Court | #A8977A | no | nothing of its own | the build |  |
| Steward of Winterhold | #A8977A | no | nothing of its own | the build |  |
| Guard of Winterhold | #A8977A | no | nothing of its own | the build |  |
| Raven Rock Court | #A8977A | no | nothing of its own | the build |  |
| Steward of Raven Rock | #A8977A | no | nothing of its own | the build |  |
| Guard of Raven Rock | #A8977A | no | nothing of its own | the build |  |
| Trading Company | #B08D57 | no | nothing of its own | the build |  |
| Member | #8D9682 | no | nothing of its own | the build | Joined and answered the rules and age questions. Sees Start Here, Applications and Information. |
| Banned | #4A4A4A | no | nothing of its own | the build | Takes the site and the game away (site/server.js, access.banned). |
| News Pings | #8D9682 | no | left to what makes it | bot.py |  |
| Updates Pings | #8D9682 | no | left to what makes it | bot.py |  |

@everyone keeps what the server gives it; the build does not change it,
and the audit prints it. Every other role opens exactly the channels
below that name it.

### The permission sets

- **Administrator**: administrator
- **council set**: attach_files, ban_members, connect, create_events, deafen_members, embed_links, kick_members, manage_events, manage_messages, manage_nicknames, manage_roles, manage_threads, mention_everyone, moderate_members, move_members, mute_members, read_message_history, send_messages, speak, view_audit_log, view_channel
- **moderator set**: attach_files, ban_members, connect, deafen_members, embed_links, kick_members, manage_messages, manage_threads, moderate_members, move_members, mute_members, read_message_history, send_messages, speak, view_channel
- **gamemaster set**: attach_files, connect, embed_links, manage_messages, manage_threads, moderate_members, move_members, mute_members, read_message_history, send_messages, speak, view_channel
- **support set**: manage_roles, manage_threads

## Who a mode lets in

Every category and channel has a mode. Reads means sees and reads back;
talks means posts as well; posts in a read only place means writes and
tidies there. A staff space mode is said for the space it names.

| Mode | Sees | Talks | Posts |
|---|---|---|---|
| public | everybody | everybody | everybody |
| read | everybody | the council | the council |
| membersread | everybody on staff, Member, Playtester | the council | the council |
| open | everybody on staff, Playtester | everybody on staff, Playtester | - |
| pathfind | everybody on staff, Playtester | everybody on staff, Playtester | - |
| testersread | everybody on staff, Playtester | the council | the council |
| staff | everybody on staff | everybody on staff | - |
| staffread | everybody on staff | the council | the council |
| council | the council | the council | - |
| hold (Whiterun) | the council, Dev, Gamemaster, Trial Gamemaster, Loremaster, Moderator, Jarl of Whiterun, Citizen of Whiterun | the council, Dev, Gamemaster, Trial Gamemaster, Loremaster, Moderator, Jarl of Whiterun, Citizen of Whiterun | - |
| space (Lore) | the council, Loremaster | the council, Loremaster | - |
| spaceread (Lore) | the council, Loremaster | the council | the council |
| spacerules (Lore) | the council, Loremaster | Owner and Co-Owner, Lead Loremaster | Owner and Co-Owner, Lead Loremaster |

## Categories and channels, in order

### Start Here

Category mode: public.

| Channel | Kind | Mode | Sees | Talks | Notes |
|---|---|---|---|---|---|
| #rules | text | read | everybody | the council | posts: the council; written by the build from content.py RULES, with its Changelog thread; topic: Seven rules. Read them. |
| #welcome | text | read | everybody | the council | posts: the council; written by the build from content.py WELCOME, with its Changelog thread; topic: Start here. |
| #start-here | text | read | everybody | the council | posts: the council; written by the build from content.py START, with its Changelog thread; topic: How to actually get in and play. |
| #say-hello | text | public | everybody | everybody | posts: everybody; topic: New here? Say hi and tell us a little about yourself. Slowmode is on. |

### Applications

Category mode: public.

| Channel | Kind | Mode | Sees | Talks | Notes |
|---|---|---|---|---|---|
| #tickets-and-applications | text | read | everybody | the council | posts: the council |

### Information

Category mode: membersread.

| Channel | Kind | Mode | Sees | Talks | Notes |
|---|---|---|---|---|---|
| #news | announce | membersread | everybody on staff, Member, Playtester | the council | posts: the council; written by the build from content.py NEWS, with its Changelog thread; topic: What changed, every time it changes. |
| #updates | text | membersread | everybody on staff, Member, Playtester | the council | posts: the council; topic: Restarts and outages. Check here before asking why you can't connect. |
| #faq | text | membersread | everybody on staff, Member, Playtester | the council | posts: the council; written by the build from content.py FAQ, with its Changelog thread; topic: Read this before you ask. |

### Roleplay Guide

Category mode: testersread.

| Channel | Kind | Mode | Sees | Talks | Notes |
|---|---|---|---|---|---|
| #game-rules | text | testersread | everybody on staff, Playtester | the council | posts: the council; written by the build from content.py GAMERULES, with its Changelog thread; was #game-rules in Thornswood; was #game-rules in In Character; topic: How roleplay works here. Nine rules, and what we let slide. |
| #lore | text | testersread | everybody on staff, Playtester | the council | posts: the council; written by the build from content.py LORE, with its Changelog thread; was #lore in In Character; topic: 4E 252. What happened and who you can be. |

### Out of Character

Category mode: open. It was Thornswood.

| Channel | Kind | Mode | Sees | Talks | Notes |
|---|---|---|---|---|---|
| #general-chat | text | open | everybody on staff, Playtester | everybody on staff, Playtester | was #general-chat in Thornswood |
| #media | text | open | everybody on staff, Playtester | everybody on staff, Playtester | was #media in Thornswood; topic: Screenshots and clips. Talk about one in a thread under it. |
| #welcome-travelers | text | open | everybody on staff, Playtester | everybody on staff, Playtester | was #welcome-travelers in Thornswood |
| #server-progression-and-economy | text | open | everybody on staff, Playtester | everybody on staff, Playtester | was #server-progression-and-economy in Thornswood |
| #suggestions | forum | open | everybody on staff, Playtester | everybody on staff, Playtester | was #suggestions in Help; topic: Mods and features you want. Nexus link if it's a mod, because whether it works here depends on how it's built. |
| #bugs | forum | open | everybody on staff, Playtester | everybody on staff, Playtester | never made by the build; topic: One post per problem. Logs and screenshots welcome. |
| #logs-and-crashes | text | open | everybody on staff, Playtester | everybody on staff, Playtester | never made by the build; topic: Drag the log in. Explain it after. |

### In Character

Category mode: open.

| Channel | Kind | Mode | Sees | Talks | Notes |
|---|---|---|---|---|---|
| #character-introductions | forum | open | everybody on staff, Playtester | everybody on staff, Playtester | topic: Who are you playing? One post each. |
| #tales | forum | open | everybody on staff, Playtester | everybody on staff, Playtester | topic: What happened out there. One post per story. |
| #rp-appreciation | text | open | everybody on staff, Playtester | everybody on staff, Playtester | topic: Somebody played a blinder. Say so. |
| #graveyard | text | open | everybody on staff, Playtester | everybody on staff, Playtester | topic: They had it coming. Probably. |

### The Holds

Category mode: hold.

| Channel | Kind | Mode | Sees | Talks | Notes |
|---|---|---|---|---|---|
| #choose-your-hold | text | testersread | everybody on staff, Playtester | the council | posts: the council |
| #whiterun | text | hold (Whiterun) | the council, Dev, Gamemaster, Trial Gamemaster, Loremaster, Moderator, Jarl of Whiterun, Citizen of Whiterun | the council, Dev, Gamemaster, Trial Gamemaster, Loremaster, Moderator, Jarl of Whiterun, Citizen of Whiterun | topic: Everybody passes through eventually. |
| #solitude | text | hold (Solitude) | the council, Dev, Gamemaster, Trial Gamemaster, Loremaster, Moderator, Jarl of Solitude, Citizen of Solitude | the council, Dev, Gamemaster, Trial Gamemaster, Loremaster, Moderator, Jarl of Solitude, Citizen of Solitude | topic: Court, trade, and the one Imperial embassy left in Skyrim. |
| #windhelm | text | hold (Windhelm) | the council, Dev, Gamemaster, Trial Gamemaster, Loremaster, Moderator, Jarl of Windhelm, Citizen of Windhelm | the council, Dev, Gamemaster, Trial Gamemaster, Loremaster, Moderator, Jarl of Windhelm, Citizen of Windhelm | topic: The High King sits here. Dress warm. |
| #riften | text | hold (Riften) | the council, Dev, Gamemaster, Trial Gamemaster, Loremaster, Moderator, Jarl of Riften, Citizen of Riften | the council, Dev, Gamemaster, Trial Gamemaster, Loremaster, Moderator, Jarl of Riften, Citizen of Riften | topic: Ask no questions. |
| #markarth | text | hold (Markarth) | the council, Dev, Gamemaster, Trial Gamemaster, Loremaster, Moderator, Jarl of Markarth, Citizen of Markarth | the council, Dev, Gamemaster, Trial Gamemaster, Loremaster, Moderator, Jarl of Markarth, Citizen of Markarth | topic: Stone, silver, and grudges older than the war. |
| #dawnstar | text | hold (Dawnstar) | the council, Dev, Gamemaster, Trial Gamemaster, Loremaster, Moderator, Jarl of Dawnstar, Citizen of Dawnstar | the council, Dev, Gamemaster, Trial Gamemaster, Loremaster, Moderator, Jarl of Dawnstar, Citizen of Dawnstar | topic: Cold. The ships still come in. |
| #morthal | text | hold (Morthal) | the council, Dev, Gamemaster, Trial Gamemaster, Loremaster, Moderator, Jarl of Morthal, Citizen of Morthal | the council, Dev, Gamemaster, Trial Gamemaster, Loremaster, Moderator, Jarl of Morthal, Citizen of Morthal | topic: Quiet. Too quiet, most would say. |
| #falkreath | text | hold (Falkreath) | the council, Dev, Gamemaster, Trial Gamemaster, Loremaster, Moderator, Jarl of Falkreath, Citizen of Falkreath | the council, Dev, Gamemaster, Trial Gamemaster, Loremaster, Moderator, Jarl of Falkreath, Citizen of Falkreath | topic: More graves than people. Always has been. |
| #winterhold | text | hold (Winterhold) | the council, Dev, Gamemaster, Trial Gamemaster, Loremaster, Moderator, Jarl of Winterhold, Citizen of Winterhold | the council, Dev, Gamemaster, Trial Gamemaster, Loremaster, Moderator, Jarl of Winterhold, Citizen of Winterhold | topic: What's left of it. |

### Voice

Category mode: open.

| Channel | Kind | Mode | Sees | Talks | Notes |
|---|---|---|---|---|---|
| General | voice | open | everybody on staff, Playtester | everybody on staff, Playtester |  |
| Help Voice | voice | open | everybody on staff, Playtester | everybody on staff, Playtester | was Support in Help |
| AFK | voice | open | everybody on staff, Playtester | everybody on staff, Playtester |  |
| #jukebox | text | open | everybody on staff, Playtester | everybody on staff, Playtester | never made by the build |

### Playtesters

Category mode: pathfind. It was Testing.

| Channel | Kind | Mode | Sees | Talks | Notes |
|---|---|---|---|---|---|
| #playtester-announcements | text | testersread | everybody on staff, Playtester | the council | posts: the council; topic: Announcements for playtesters. The council posts here. |
| #playtester-rules | text | testersread | everybody on staff, Playtester | the council | posts: the council; written by the build from content.py TESTERRULES, a draft waiting on approval; topic: How playtesting works here. |
| #playtest-sessions | text | pathfind | everybody on staff, Playtester | everybody on staff, Playtester | topic: Call a session and say you are coming. |
| #test-tasks | forum | pathfind | everybody on staff, Playtester | everybody on staff, Playtester | was #Test-Tasks in Testing; was #test-tasks in Testing; topic: One thread per test task, tagged Main. |
| #test-findings | forum | pathfind | everybody on staff, Playtester | everybody on staff, Playtester | was #test-findings in Testing; topic: Pass, fail, and what went wrong. |
| #known-issues | text | pathfind | everybody on staff, Playtester | everybody on staff, Playtester | was #known-issues in Testing; topic: Known issues the team is working on. Kept by the bot. |
| #playtester-chat | text | pathfind | everybody on staff, Playtester | everybody on staff, Playtester | topic: Talk about testing: what you are trying and what you found. |
| Playtester Voice | voice | pathfind | everybody on staff, Playtester | everybody on staff, Playtester | was play-testing in Testing |

### Gamemasters

Category mode: space (Gamemasters).

| Channel | Kind | Mode | Sees | Talks | Notes |
|---|---|---|---|---|---|
| #gm-announcements | text | spaceread | the council, Gamemaster, Trial Gamemaster, Moderator, Loremaster | the council | posts: the council; topic: Announcements for Gamemasters. The council posts here. |
| #gm-rules | text | spacerules | the council, Gamemaster, Trial Gamemaster, Moderator | Owner and Co-Owner, Lead Gamemaster | posts: Owner and Co-Owner, Lead Gamemaster; topic: The GM Rules. Lead Gamemaster, Owner and Co-Owner post here. |
| #gm-event-plans | text | space | the council, Loremaster, Gamemaster, Trial Gamemaster, Moderator | the council, Gamemaster, Trial Gamemaster, Moderator | topic: What an event will be, before it runs. Loremasters read it. |
| #gm-scene-summaries | text | space | the council, Loremaster, Gamemaster, Trial Gamemaster, Moderator | the council, Gamemaster, Trial Gamemaster, Moderator | topic: What happened in a scene you ran, after it ends. |
| #gm-chat | text | space | the council, Gamemaster, Trial Gamemaster, Moderator | the council, Gamemaster, Trial Gamemaster, Moderator | topic: Planning, handoffs and questions between gamemasters. |
| #gm-suggestions | text | space | the council, Gamemaster, Trial Gamemaster, Moderator | the council, Gamemaster, Trial Gamemaster, Moderator | topic: Ideas for scenes, events and how we run them. |
| #gm-discipline | text | space | the council, Gamemaster, Trial Gamemaster, Moderator | the council, Gamemaster, Trial Gamemaster, Moderator | topic: Reprimands, punishments and bans only. Nothing else. |
| GM Voice | voice | space | the council, Gamemaster, Trial Gamemaster, Moderator | the council, Gamemaster, Trial Gamemaster, Moderator |  |
| #gm | text | space | the council, Gamemaster, Trial Gamemaster, Moderator | the council, Gamemaster, Trial Gamemaster, Moderator | never made by the build |

### Dev

Category mode: space (Dev).

| Channel | Kind | Mode | Sees | Talks | Notes |
|---|---|---|---|---|---|
| #dev-announcements | text | spaceread | the council, Dev | the council | posts: the council; topic: Announcements for Dev. The council posts here. |
| #dev-rules | text | spacerules | the council, Dev | Owner and Co-Owner, Lead Dev | posts: Owner and Co-Owner, Lead Dev; written by the build from content.py DEVRULES, a draft waiting on approval; topic: How Dev works. Lead Dev, Owner and Co-Owner post here. |
| #dev-test-tasks | forum | space | the council, Dev | the council, Dev | never made by the build; was #dev-test-tasks in Staff; topic: Test tasks someone on dev has to measure, from the board. Kept by the bot: a post goes when its issue closes as fixed or its test task no longer says Server: Dev. |
| #dev-test-findings | forum | space | the council, Dev | the council, Dev | was #dev-test-findings in Staff; was #dev-test-results in Staff |
| #dev-coordination | text | space | the council, Dev | the council, Dev | topic: Developers only: a shared file being edited, the dev feed taken. Say it here before you do it. |
| #dev-chat | text | space | the council, Dev | the council, Dev | topic: Talk between Dev. |
| Dev Voice | voice | space | the council, Dev | the council, Dev |  |

### Lore

Category mode: space (Lore).

| Channel | Kind | Mode | Sees | Talks | Notes |
|---|---|---|---|---|---|
| #lore-announcements | text | spaceread | the council, Loremaster | the council | posts: the council; topic: Announcements for Lore. The council posts here. |
| #lore-rules | text | spacerules | the council, Loremaster | Owner and Co-Owner, Lead Loremaster | posts: Owner and Co-Owner, Lead Loremaster; written by the build from content.py LORERULES, a draft waiting on approval; topic: How Lore works. Lead Loremaster, Owner and Co-Owner post here. |
| #lore-chat | text | space | the council, Loremaster | the council, Loremaster | topic: Talk between Lore. |
| Lore Voice | voice | space | the council, Loremaster | the council, Loremaster |  |

### Moderation

Category mode: space (Moderation).

| Channel | Kind | Mode | Sees | Talks | Notes |
|---|---|---|---|---|---|
| #mod-announcements | text | spaceread | the council, Moderator | the council | posts: the council; topic: Announcements for Moderation. The council posts here. |
| #mod-rules | text | spacerules | the council, Moderator | Owner and Co-Owner, Lead Moderator | posts: Owner and Co-Owner, Lead Moderator; written by the build from content.py MODRULES, a draft waiting on approval; topic: How Moderation works. Lead Moderator, Owner and Co-Owner post here. |
| #mod-chat | text | space | the council, Moderator | the council, Moderator | topic: Talk between Moderation. |
| Moderation Voice | voice | space | the council, Moderator | the council, Moderator |  |

### Content

Category mode: space (Content).

| Channel | Kind | Mode | Sees | Talks | Notes |
|---|---|---|---|---|---|
| #content-announcements | text | spaceread | the council, Content Creator | the council | posts: the council; topic: Announcements for Content. The council posts here. |
| #content-rules | text | spacerules | the council, Content Creator | Owner and Co-Owner, Lead Content Creator | posts: Owner and Co-Owner, Lead Content Creator; written by the build from content.py CONTENTRULES, a draft waiting on approval; topic: How Content works. Lead Content Creator, Owner and Co-Owner post here. |
| #content-chat | text | space | the council, Content Creator | the council, Content Creator | topic: Talk between Content. |
| Content Voice | voice | space | the council, Content Creator | the council, Content Creator |  |

### Support

Category mode: space (Support).

| Channel | Kind | Mode | Sees | Talks | Notes |
|---|---|---|---|---|---|
| #support-announcements | text | spaceread | the council, Support | the council | posts: the council; topic: Announcements for Support. The council posts here. |
| #support-rules | text | spacerules | the council, Support | Owner and Co-Owner, Lead Support | posts: Owner and Co-Owner, Lead Support; written by the build from content.py SUPPORTRULES, a draft waiting on approval; topic: How Support works. Lead Support, Owner and Co-Owner post here. |
| #support-chat | text | space | the council, Support | the council, Support | topic: Talk between Support. |
| Support Voice | voice | space | the council, Support | the council, Support |  |

### Staff

Category mode: staff.

| Channel | Kind | Mode | Sees | Talks | Notes |
|---|---|---|---|---|---|
| #staff-announcements | announce | staffread | everybody on staff | the council | posts: the council; was #news in Staff; topic: Announcements for every staff member. The council posts here. |
| #staff-general | text | staff | everybody on staff | everybody on staff | topic: Nobody else can see this. |
| #staff-updates | text | staff | everybody on staff | everybody on staff | never made by the build |
| #council | text | council | the council | the council | topic: The council: Owner, Co-Owner and the leads. |
| #council-decisions | text | staffread | everybody on staff | the council | posts: the council; topic: Every council decision, with its date. The council posts here. |
| #ticket-log | text | council | the council | the council | was #tickets in Applications |
| Staff Room | voice | staff | everybody on staff | everybody on staff |  |
| #dev-notes | text | staff | everybody on staff | everybody on staff | never made by the build; topic: What we’re on, and what broke doing it. |
| #deploys | text | staff | everybody on staff | everybody on staff | never made by the build; topic: Every ship and restart lands here. |
| #reports | text | staff | everybody on staff | everybody on staff | never made by the build; topic: Reports about people. Staff only. |

## Retired

Categories retired by the plan, removed by `-Prune` once empty: Help.

Channel names the build no longer wants, removed by `-Prune`: tech-help, looking-for-group, off-topic, downloads, links-and-credits, Small Table, The Longhouse, Away, screenshots, clips, bot-commands, The Bannered Mare, The Road, test-these, test-tasks-archive.

Channels never deleted by anything in the build: council, council-decisions, dev-test-findings, dev-test-results, dev-test-tasks, general-chat, gm, gm voice, gm-chat, gm-discipline, gm-rules, gm-scene-summaries, gm-suggestions, help voice, jukebox, known-issues, news, play-testing, playtester voice, server-progression-and-economy, staff-announcements, staff-updates, suggestions, support, test-findings, test-results, test-tasks, ticket-log, tickets, welcome-travelers.

Roles never deleted: every Jarl, Citizen and office role.
