# Chat commands

Every line starting with a slash that the game answers, who may use it,
what it does, where it is read, and where people are told about it.

The rule is on [Thornswood systems](../SYSTEMS.md), "Buttons, not
commands". Decided by Patrick on 4 Oct: anything a person does in the
world is a key, a prompt, a panel, or the thing itself activated. Staff
and dev commands stay commands. Each command for people below has an
issue that turns it into buttons, except `/stuck`, `/helpme` and
`/report`, which stay commands (Patrick, later on 4 Oct: "change it to
except the /stuck and the ones for getting help from GMs"). The
umbrella is #1620.

File and line numbers are main at 9b5a667 on 4 Oct. They move as the
files change, so each row also names the function or block.

## How a line travels

Enter opens the chat box (`game/ui/thornswood-chat.js`). A line that
starts with a slash goes to the voice service, which is not the game
server. The voice service says `/me`, `/do`, `/w` and `/s` itself and
never passes them on (`voice/voice-server.js:427`). Every other slash
line is queued for the game server, which collects the queue in the
chat commands block of `game/gamemode.js`: `dispatch` (43770) first,
then `handle` (44415).

Two lists in that block decide what people are told. `WORDS` (43436) is
every word the server answers. The list at 43514 is the words named to
everybody. `/help` reads it, and so does the reply to a word the server
does not know, "No command called ... Try /help. There is ..." (45653).
In the tables below, "the list" means that second list.

Other places that tell people to type a command: the `/help` topics in
the game (45550, topics talking, people, living, work, land and staff),
the launcher's Help page (`launcher/app/Help.cs`, "Chat and commands"
and "In game"), the system pages in this folder, the site's pages in
`site/data/site`, and the server's own answers ("Say /ride and the
stop"). Each conversion issue takes its commands out of all of them.

## Commands for people

Each of these becomes buttons, except the two rows that say they stay.
The server may keep a line as an internal message that a key or a panel
sends, the way Y, H and L on the look prompt send `/friend`, `/trade`
and `/mute` with the id under the crosshair. Nobody is told to type it,
and help text never lists it.

| Command | Who | What it does | Read at | Where people are told | Buttons today, then to come | Issue |
| --- | --- | --- | --- | --- | --- | --- |
| `/notice <words>`, `/job <words>` | Anybody at a board | Posts a notice for 20 gold or a job for 30 | `gamemode.js:37286`, `post` | The list; [Notice boards](noticeboards.md) | The board panel posts both. Out of the help. | #1627 |
| `/take <n>`, `/unpin <n>`, `/dropjob <n>` | Anybody at a board | Takes a job, takes your own down, hands a job back | `gamemode.js:37289`, `37292`, `37291` | The list; [Notice boards](noticeboards.md), [Trading company](trading-company.md), [Gold](gold.md) | The board panel has Take, Take down and Put it back. Out of the help. | #1627 |
| `/board`, `/board <hold>` | Anybody | Reads the board you are at, or any hold's board from anywhere | `gamemode.js:37288`, `board` (36792) | The list; [Notice boards](noticeboards.md); the server's lines (36980 and others) | E on the board opens the panel there. To come: another hold's board away from a board. | #1627 |
| `/jobs` | Anybody | The jobs you have taken, in every hold | `gamemode.js:37290`, `jobs` (36951) | The list; [Notice boards](noticeboards.md) | None. To come: Your jobs on a panel. | #1627 |
| `/haul <pay> <hold> <words>`, `/haul done <hold> <n>` | Anybody at a board; the poster or a steward confirms | Sends a haul, and confirms one at the destination | `gamemode.js`, `haulCmd` in the property block | Nowhere. [Trading company](trading-company.md) names the buttons | Send a haul and Confirm on the board panel send it. Never in the list or the help. | #1393 |
| `/letter <name> <words>`, `/deliver <name>` | Anybody | Writes a letter at a board; hands it over and pays the courier | `gamemode.js:37293`, `37294` | The list; [Notice boards](noticeboards.md) | None. To come: on the board panel and the look prompt. | #1595 |
| `/friend <name>`, `/friend`, `/friend remove <name>` | Anybody | Asks to be friends, lists them, drops one | `gamemode.js:44640`, the social branch of `handle` | The list; [Friends](friends.md), [Factions](factions.md), [Text chat](chat.md) | Y on the look prompt; the P panel lists and drops. Out of the help. | #1628 |
| `/trade <name>`, `/trade add`, `remove`, `gold`, `ok`, `cancel`, `sale` | Anybody; `sale` is a company worker's | Offers a trade, and works it; `sale` makes it a sale out of Skyrim (#1393) | `gamemode.js:44847` | The list; [Trade](trade.md), [Text chat](chat.md) | H on the look prompt; the trade window sends every verb, and Buy for the company sends `sale`. Out of the help. | #1628 |
| `/mute <name>`, `/mute`, `/mute text <name>` | Anybody | Stops hearing somebody, lists who, turns their text off | `gamemode.js:44770`, `44786`, `44895` | The list; [Voice](voice.md), [People beside you](people.md) | L on the look prompt; Mute and Text on P beside a friend. To come: text and the list for anybody. | #1628 |
| `/hidename <name>`, `/hidename`, `/hidename all` | Anybody | Hides a name above a head, lists them, hides every name | `gamemode.js:44795` to `44812` | The list; [Voice](voice.md), [People beside you](people.md) | Name and Hide every name on P, for friends. To come: for anybody. | #1628 |
| `/yes`, `/no` | Anybody | Answers whatever somebody has offered | `gamemode.js:44651` | The list; `/help people` | Accept and Refuse on the prompt. Out of the help. | #1628 |
| `/party <name>`, `/party`, `/party leave`, `disband`, `kick <name>`, `lead <name>` | Anybody; the leader kicks, hands the lead and disbands | Asks, lists, leaves and runs a party | `gamemode.js:44722` to `44750`, the offer at 44912 | The list; `/help people`; Help page "Parties"; [Party](party.md), [Text chat](chat.md); the server's line at 44728 | The P panel has Leave, Disband, Kick, Lead, and Ask beside an online friend. To come: P on the look prompt asks. | #1629 |
| `/journal` and its verbs | Anybody | Journals, pages and sharing them | `gamemode.js:44712`, `journalCommand` (44324) | The list; [Journals](journal.md); the server's line at 44329 | J sends every verb. Out of the help. | #1630 |
| `/book` and its verbs | Anybody; founding needs the Business Owner or Faction Owner role, or Dev | Group books: found, invite, leave, roles, prices | `gamemode.js:44631`, the books block's `command` (43205) | The list; `/help people`; [Factions](factions.md), [Text chat](chat.md) | J sends every verb; the board panel submits a price list. To come: inviting the person in front of you, if J lacks it. | #1630 |
| `/rest sit`, `campfire`, `inn`, `up` | Anybody | Where you are resting, for the rest meter | `bedRest` in the property block's beds | [Thirst](thirst.md), [Hunger](hunger.md) | Sitting down sends `/rest sit`, lying down `/rest bed` and getting up `/rest up`, and the server answers by the furniture it saw pressed, whatever the word (#1603). Out of the list, `/help living` and the Help page. To come: the wheel's Sit. | #1631 |
| `/needs` | Anybody | The meters, the warmth with its working out, what is counted as worn | `gamemode.js:44946` | The list; Help page; [Temperature](temperature.md); `site/data/known.md` | The four bars. To come: the rest of it on a panel. | #1631 |
| `/eat`, `/drink`, `/drink ale` | Anybody | Food or drink with no item | `gamemode.js:45030` to `45040` | The list; `/help living`; Help page; [Emotes](emotes.md) | Eating or drinking the item is already reported as `/ate`. To come: taken out. | #1631 |
| `/bard` | Anybody | +25 rest for everyone resting in the cell, for 5 minutes | `gamemode.js:44993` | The list; [Exhaustion](exhaustion.md), [Emotes](emotes.md), [People beside you](people.md), [Text chat](chat.md); `site/data/site/classes.md` | None. To come: a button, asked on the issue. | #1631 |
| `/helpme <what>`, `/help-me`, `/report <name> <what>` | Anybody | Reaches staff; reports somebody to staff | `gamemode.js:45537`, the asking staff block's `ask` (52023) | The list; `/help staff`; Help page "Getting staff"; `site/data/site/privacy.md` | Stays a command, and the help names it (Patrick, 4 Oct). | None |
| `/stuck` | Anybody | Out of a wedged spot, a few steps back or to a temple | `gamemode.js:45522`, the stuck block's `command` (52595) | The list; `/help staff`; `site/data/site/privacy.md` | Stays a command, and the help names it (Patrick, 4 Oct). | None |
| `/help [topic]`, `/commands` | Anybody | The help in the game | `gamemode.js:45550` | Help page "Everything else is on /help"; the unknown word reply | None. To come: a help panel. | #1633 |
| `/merchant <id>`, `/merchant buy`, `sell`, `supply`, `close` | Anybody at a guild trader | A trader's wares | `gamemode.js:44619`, then `command` (54951) | The list; [Merchant's Guild](merchants-guild.md) | E on a trader opens the panel, which sends the rest. Out of the list and the page. | #1633 |
| `/where` | Anybody today; a dev's tool | The cell, position and angle you stand at | `gamemode.js:45073` | The list | Stays a command, for dev and testers only. | #1633 |
| `/apprentice <name> [half]`, `/apprentice end <name>`, `/apprentice` | A Master; anybody asks who is whose | Takes somebody on, ends it, says who is whose | `gamemode.js:40758`, `apprenticeCommand` (40656) | The list; `/help work`; [Masters and apprentices](apprenticeship.md), [Professions](professions.md), [Warrior](professions/warrior.md); the server's lines | Accept and Refuse for the learner. To come: a look prompt row for a Master, and the list on K. | #1634 |
| `/study` | Anybody in the College rooms | A spell point in a semester | Never a word. Study on the K panel's College page sends `/pick study`, below | [Magic](magic.md), [Masters and apprentices](apprenticeship.md) | Study on K, which the server answers only in the College's rooms. | #1387 |
| `/ride`, `/ride <stop>` | Anybody at a driver | Where the driver goes and the fares; pay and go | `gamemode.js:44593`, the carriages block's `command` (37864) | The list; [Carriages and ferries](carriages.md); the server's lines at 37782 and 37811 | E on a driver lists the stops in the chat. To come: a panel of stops. | #1635 |
| `/plant`, `/plot`, `/claim` at a plot | Anybody with the class | Sows a plot, says what is in it, claims the farm | `gamemode.js:40701`, then the farming block's `command` (33866) | The list; `/help work`, `/help land`; [Farmer](classes/farmer.md) | Bringing a crop in is the press. To come: a line and keys at the plot. | #1636 |
| `/claim` at a door, `/deed`, `/deeds` | Anybody | Claims a building and hands the deed; lists what you hold | `command` in the character block, then the property block's `command` | Nowhere since #1637; [Property](property.md) names the key | X at a door just opened, while its line says Claim, sends `/claim <id>`; the property page on K lists what you hold, with the rent owed and the farm. Out of the list and the help. | #1637 |
| `/lock`, `/unlock` | The holder, or whoever carries the deed, at the door | Locks and unlocks the building | The property block's `command`, `setLock` | Nowhere since #1637; [Property](property.md) names the key | X at a door just opened sends `/lock <id>` or `/unlock <id>`, as its line says. Out of the list and the help. | #1637 |
| `/mold`, `/key` | A smith | A mold at a door, a key at a forge | The property block's `command`, `mold` and `cutKey` | Nowhere since #1637; [Property](property.md) names the keys | U presses a blank mold into the door; X at a forge, carrying a mold that has been pressed into a door, sends `/key <id>` and cuts a key for an iron ingot. Out of the list and the help. | #1637 |
| `/jarl` | The Discord Jarl role, or an admin | Seats the Jarl office on this character | `gamemode.js:37280`, never reached today (#1640) | The list | None. To come: a button. | #1638 |
| `/steward`, `/steward <id>`, `/steward -<id>` | A Jarl; anybody asks who holds it | Names or removes a steward | `gamemode.js:37281` | The list; [Offices](offices.md) | None. To come: picking the person. | #1638 |
| `/evict`, `/rent`, `/box` | A steward; anybody asks the rent or which box | Ends a claim, sets rent, marks the hold's box | `gamemode.js:37282` to `37284` | The list; `/help land`; [Property](property.md) | None. To come: lines at the door and the container. | #1638 |
| `/board move <hold>`, `/board here` | A steward | Moves a notice board | `board` (`gamemode.js:36792`) | [Notice boards](noticeboards.md) | None. To come: Move the board here, on the board panel. | #1638 |
| `/me`, `/do`, `/whisper`, `/w`, `/shout`, `/s`, `/yell`, `/y` | Anybody | How a line is said, and how far it carries | `voice/voice-server.js:427`, `voice/headlines.js:28` | [Text chat](chat.md), [People beside you](people.md), [Emotes](emotes.md); the voice service's usage lines | None. To come: buttons on the chat box. | #1639 |
| `/ooc`, `/o` | Anybody | Out of character, to whoever is near | `gamemode.js:45334` | The list; `/help talking`; Help page; [Text chat](chat.md), [Factions](factions.md), [Notice boards](noticeboards.md); `site/data/site/rules.md` | None. To come: a button on the chat box. | #1639 |
| `/roll`, `/r` | Anybody | Dice, rolled on the server | `game/ui/thornswood-chat.js:334`, `gamemode.js:45419` | The list; `/help talking`; Help page "Dice" | None. To come: a dice button. | #1639 |
| `/repair`, `/repair mend <base> <condition> <name>` | Anybody with a repair kit | Opens the repair panel; a row's Mend button mends that piece with a kit | The `/repair` branch of `handle`, then `panel` in the durability block | Nowhere. [Durability](durability.md) names the key and the panel | U in the inventory, with a kit in the pack, opens the panel, and Mend sends `mend`. Never in the list or the help. | #1384 |
| `/maneuver <name>`, `/maneuver` | A warrior | Starts a warrior's maneuver; with no name, says which you hold | `gamemode.js`, `use` in the warrior maneuvers block | Nowhere. [Warrior](professions/warrior.md) names the key | The maneuver key (9) opens a panel of yours, and a number or a click there sends it. Never in the list or the help. | #1386 |

`/pick` and `/spend` are the K panel's lines (`gamemode.js:40783`):
profession, class, town, spells and points, `/pick perk fontofmagic`
from the Use button beside Font of Magic, and `/pick study` from the
Study button on the College page (#1387). K sends them and nothing tells
anybody to type them, so there is nothing to turn.

## Staff and dev commands

These stay commands.

| Command | Who | What it does | Read at | Where staff are told |
| --- | --- | --- | --- | --- |
| `/tp <place>`, `/goto <place>`, `/tp` | Testers and dev: the Playtester role on Discord (the door's allowed list), the written playtester and dev lists, and the admins | Moves you to a town or a named place; `/tp` alone lists the places | `gamemode.js:45107`, `isPlaytester` (45799) | The `/help` menu adds a line for them (45552) |
| `/give <item> [count]`, `/spawn <creature> [count]` | Testers and dev | Makes items in your pack, or creatures beside you | `gamemode.js:45243` | The same line |
| `/kick`, `/freeze`, `/unfreeze`, `/bring`, `/goto <person>`, `/silence`, `/unsilence`, `/warn`, `/spawnat`, and `/give`, `/spawn` and `/tp` aimed at a person | Staff: Owner, Dev, Gamemaster, Moderator, Loremaster, the admins and the dev list, on a proven connection with a join pass | Moderation in the world | The staff block's `command`, `gamemode.js:53418` | The staff block's header (52661); [Voice](voice.md) for silence |
| `/ban`, `/unban`, `/banaccount`, `/unbanaccount`, `/pk`, `/note` | Staff | Bans, a character killed for good, and notes, kept on the site | `gamemode.js:53478` | The staff pages on the site (`site/public/hub.js`) |
| `/unpk` | Admins only | Undoes a PK made by mistake | `gamemode.js:53477` | The staff pages on the site |
| `/hurt <person> [what]` | Staff | A cut, a bite, a break or a disease for a scene, an agreed loss written down after a yes given out of character, or what somebody carries (#1383) | The staff block's `command`, which hands it to `staff` in the injury and disease block | The staff block's header; [Injury](injury.md) |
| `/restart`, `/shutdown` | Nobody | Answers that restarts are not run from chat | `gamemode.js:45207` | Nowhere |
| `/close` (Discord) | Staff | Closes a ticket | `bot/bot.py:1440` | Discord's own command list |
| `/live-smoke start`, `reset`, `refresh`, `report` (Discord) | Owner, Dev and Lead Gamemaster | The Live smoke checklist in #test-tasks | `bot/bot.py:2565` | Discord's own command list |

## Lines the game sends itself

Nobody types these, and nothing tells anybody to. They are how the
client reports what only it can see. They stay.

| Line | Sent by | What it reports | Read at |
| --- | --- | --- | --- |
| `/joinpass <pass>` | The front plugin | The launcher's join pass | `gamemode.js:43776` |
| `/line`, `/line leave`, `hand`, `gone` | The front plugin at the menu, and the voice service | The line to get in while the world is full | `gamemode.js:43807` |
| `/afk active`, `here`, `out` | The front plugin | Whether somebody is at the game | `gamemode.js:43822` |
| `/face done`, `/racemenu` | The front plugin | The race menu closed, or is up | `gamemode.js:44425`, `44441` |
| `/modset` | The front plugin | Mod settings menu values that changed | `gamemode.js:44463` |
| `/ate <id>` | The front plugin | Something was eaten or drunk | `gamemode.js:44546` |
| `/place`, `/burn` | The front plugin | Where you stand for warmth, and being on fire, which is also timed for a burn wound | `gamemode.js:44558`, `44580` |
| `/chopped` | The front plugin | A fall of the axe at a chopping block | `gamemode.js:45042` |
| `/loadorder` | The front plugin | The client's load order | `gamemode.js:45054` |
| `/tspicks <n>` | The front plugin | Lockpicks that broke | `gamemode.js:45064` |
| `/moldhere <id>` | U at a door | A key mold pressed into that door | `gamemode.js:37271` |
| `/claim <id>`, `/lock <id>`, `/unlock <id>`, `/key <id>` | X at a door just opened, or at a forge (#1637) | Claims, locks or unlocks the building of the door just opened; cuts a key from the mold in the pack | The property block's `command`, `forgeHere` |
| `/rest bed`, `/rest sit`, `/rest up` | Lying down, sitting down and getting up | Resting in a bed or on a seat, as the server measures it | `bedRest` in the property block's beds |
| `/sleephere <id>`, `/sleephere stop <profile> <building>` | U on a person inside a building you hold, and Stop on the K panel's property page | Lets them sleep there for a night, or ends their night (#1603) | `sleepHere` in the property block's beds |
| `/ride e <id>`, `/merchant e <id>` | E on a driver or a trader | Which one was pressed | `gamemode.js:44593`, `54951` |
| `/party refresh`, `/trade refresh`, `/pick refresh` | A panel as it opens | Send the panel its view | `gamemode.js:44722`, `44847`, `40783` |
| `/skill` | The client's unused skills menus | Nothing: the page drops it before it is sent | `game/ui/thornswood-bridge.js:72` |
