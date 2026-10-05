# Chat commands

Every line starting with a slash that the game answers, who may use it,
what it does, where it is read, and where people are told about it.

The rule is on [Thornswood systems](../SYSTEMS.md), "Buttons, not
commands". Decided by Patrick on 4 Oct: anything a person does in the
world is a key, a prompt, a panel, or the thing itself activated. Staff
and dev commands stay commands. Each command for people below has an
issue that turns it into buttons, except `/stuck`, `/helpme` and
`/report`, which stay commands (Patrick, later on 4 Oct: "change it to
except the /stuck and the ones for getting help from GMs"), and the
ways of saying a line and `/roll`, which stay commands with no buttons
(Patrick, 4 Oct, #1639: "Allow those commands and don't do buttons").
The umbrella is #1620.

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

Two lists in that block decide what people are told. `WORDS` is every
word the server answers. `PLAYER_WORDS` is the words named to everybody,
and since #1633 it is exactly the commands that stay, the rows below that
say so: `/stuck`, `/helpme`, `/report`, `/me`, `/do`, `/w`, `/s`, `/y`,
`/ooc` and `/roll`. `helpLine` reads it: the answer to `/help` and
`/commands`, and the end of the reply to a word the server does not know,
"No command called ... Help is a panel: F7 opens it ... Typed in the
chat: ...". In the tables below, "the list" means `PLAYER_WORDS`.

The help in the game is a panel since #1633 (`game/ui/thornswood-help.js`):
its own key, HelpKey in `Thornswood.ini` (F7), on the launcher's Controls
page, and Help on the K, P and J panels (Patrick's answer on #1633). Its
topics are talking, people, living, work, land and getting help, written
as keys, prompts and panels, with every key named as that machine has it
bound. It names the commands that stay and no other.

Other places that tell people to type a command: the help panel, the
launcher's Help page (`launcher/app/Help.cs`, "Chat and commands"), the
system pages in this folder, the site's pages in `site/data/site`, and
the server's own answers. Each conversion issue took its commands out of
all of them.

## Commands for people

Each of these becomes buttons, except the rows that say they stay.
The server may keep a line as an internal message that a key or a panel
sends, the way Y, H and L on the look prompt send `/friend`, `/trade`
and `/mute` with the id under the crosshair. Nobody is told to type it,
and help text never lists it.

| Command | Who | What it does | Read at | Where people are told | Buttons today, then to come | Issue |
| --- | --- | --- | --- | --- | --- | --- |
| `/notice <words>`, `/job <words>` | Anybody at a board | Posts a notice for 20 gold or a job for 30 | `post` in the property block | Nowhere. [Notice boards](noticeboards.md) names the buttons | Post a notice and Post a job on the board panel send them. Never in the list or the help. | #1627 |
| `/take <n>`, `/unpin <n>`, `/dropjob <n>` | Anybody at a board | Takes a job, takes your own down, hands a job back | `take`, `unpin`, `dropJob` in the property block | Nowhere. [Notice boards](noticeboards.md), [Trading company](trading-company.md) and [Gold](gold.md) name the buttons | Take, Take down and Put it back on the board panel send them. Never in the list or the help. | #1627 |
| `/board <hold>` | Anybody | Puts any town's board on J, read only, with your jobs under it | `board`, then `boardsView`, in the property block | Nowhere. [Notice boards](noticeboards.md) names J's Boards tab | E on the board opens the panel there. Picking a town under Boards on J sends it. Never in the list or the help. | #1627 |
| `/jobs` | Nobody | Gone. The jobs you have taken, in every town, are Your jobs | `jobsOf` in the property block | Nowhere | Your jobs on the board panel, with Put it back for that board's, and under Boards on J. | #1627 |
| `/haul <pay> <hold> <words>`, `/haul done <hold> <n>` | Anybody at a board; the poster or a steward confirms | Sends a haul, and confirms one at the destination | `gamemode.js`, `haulCmd` in the property block | Nowhere. [Trading company](trading-company.md) names the buttons | Send a haul and Confirm on the board panel send it. Never in the list or the help. | #1393 |
| `/letter "<name>" <words>`, `/deliver <id>` | Anybody | Writes a letter at a board; hands it over and pays the courier | `postLetter`, `deliver` in the property block | Nowhere. [Notice boards](noticeboards.md) names the form and the key | Write a letter on the board panel sends `/letter`. Hand over the letter on the look prompt, E while you carry a letter for the person under the crosshair, sends `/deliver` with their id. Never in the list or the help. | #1595 |
| `/friend <name>`, `/friend`, `/friend remove <name>` | Anybody | Asks to be friends, lists them, drops one | `gamemode.js:44640`, the social branch of `handle` | Nowhere. [Friends](friends.md) names the key and the buttons | Y on the look prompt and Add friend under Near you on P ask; the P panel lists them, and Remove beside a friend drops that friend by profile id. Never in the list or the help. | #1628 |
| `/trade <name>`, `/trade add`, `remove`, `gold`, `ok`, `cancel`, `sale` | Anybody; `sale` is a company worker's | Offers a trade, and works it; `sale` makes it a sale out of Skyrim (#1393) | `gamemode.js:44847` | Nowhere. [Trade](trade.md) names the key and the buttons | H on the look prompt and Trade under Near you on P offer; the trade window sends every verb, and Buy for the company sends `sale`. Asking while in a trade brings its window back. Never in the list or the help. | #1628 |
| `/mute <name>`, `/mute`, `/mute text <name>` | Anybody | Stops hearing somebody, lists who, turns their text off | `gamemode.js:44770`, `44786`, `44895` | Nowhere. [Voice](voice.md) names the key and the buttons | L on the look prompt; Mute and Text on P beside a friend, anybody under Near you, and anybody under Muted and hidden, which is the list. Never in the list or the help. | #1628 |
| `/hidename <name>`, `/hidename`, `/hidename all` | Anybody | Hides a name above a head, lists them, hides every name | `gamemode.js:44795` to `44812` | Nowhere. [Voice](voice.md) names the buttons | Name on P beside a friend, anybody under Near you, and anybody under Muted and hidden, which is the list; Hide every name on P. Never in the list or the help. | #1628 |
| `/yes`, `/no` | Anybody | Answers whatever somebody has offered | `gamemode.js:44651` | Nowhere | Accept and Refuse on the prompt, and on P. Never in the list or the help. | #1628 |
| `/party <name>`, `/party`, `/party leave`, `disband`, `kick <name>`, `lead <name>` | Anybody; the leader kicks, hands the lead and disbands | Asks, lists, leaves and runs a party | `gamemode.js:44722` to `44750`, the offer at 44912 | Nowhere. [Party](party.md) names the key and the buttons | P on somebody not in your party sends the ask with their form id, as the look prompt's "Ask to party" says; P otherwise opens the P panel, which lists the party and has Leave, Disband, Kick, Lead, and Ask beside an online friend, which sends that friend's profile id (#1695). Out of the list, the Help page, the pages and the server's lines. | #1629 |
| `/journal` and its verbs | Anybody | Journals, pages and sharing them | `journalCommand` in the chat commands block | Nowhere. [Journals](journal.md) names J and its buttons | J sends every verb. Out of the list, the pages and the server's own lines. | #1630 |
| `/book` and its verbs | Anybody; founding needs the Business Owner or Faction Owner role, or Dev | Group books: found, invite, leave, roles, prices | The `/book` branch of `handle`, then the books block's `command` | Nowhere. [Factions](factions.md) names J and its buttons | J sends every verb: Invite names the person in front of you when J opens, and each role's permissions are buttons. The board panel submits a price list. The invite reads as one on the P prompt (#1591). Out of the list, `/help people`, the pages and the server's own lines. | #1630 |
| `/rest sit`, `campfire`, `inn`, `up` | Anybody | Where you are resting, for the rest meter | `bedRest` in the property block's beds | Nowhere. [Exhaustion](exhaustion.md) names sitting, lying down and the wheel's Sit | Sitting down sends `/rest sit`, lying down `/rest bed` and getting up `/rest up`, and the server answers by the furniture it saw pressed, whatever the word (#1603). Sit on the emote wheel sends nothing: the server reads the last animation the game sent for the person, and the wheel's Sit is a seat on the ground (#1631). Out of the list, `/help living` and the Help page. | #1631 |
| `/needs` | Nobody | Gone (#1631). The meters, the warmth with its working out and what is counted as worn are the Body page on K | `view` in the needs block, put on the K panel by `writeState` in the character block | Nowhere. [Temperature](temperature.md) and `site/data/known.md` name the Body page. The launcher's line on hiding the bars still names it (`launcher/app/Shell.cs`, which takes a line in #staff-general first) | The four bars, and the Body page on K, with Read again. Out of the list, the help and the pages. | #1631 |
| `/eat`, `/drink`, `/drink ale` | Nobody | Gone (#1631). They gave food or drink with no item | None | Nowhere | Eating or drinking the item, which the front plugin reports as `/ate`. Said on #1382. | #1631 |
| `/bard` | Nobody | Gone (#1631). The bard is somebody the server sees playing | `playing` and `bardSeen` in the needs block | Nowhere. [Exhaustion](exhaustion.md), [Emotes](emotes.md) and [People beside you](people.md) name the wheel | Lute, Flute or Drum on the emote wheel with that instrument in the pack, or Sing (Patrick, 4 Oct), read from the last animation the game sent for the person. | #1631 |
| `/helpme <what>`, `/help-me`, `/report <name> <what>` | Anybody | Reaches staff; reports somebody to staff | The `/helpme` branch of `handle`, then the asking staff block's `ask` | The list; the help panel's Getting help; Help page "Getting staff"; `site/data/site/privacy.md` | Stays a command, and the help names it (Patrick, 4 Oct). | None |
| `/stuck` | Anybody | Out of a wedged spot, a few steps back or to a temple | The `/stuck` branch of `handle`, then the stuck block's `command` | The list; the help panel's Getting help; Help page "Stuck in the world"; `site/data/site/privacy.md` | Stays a command, and the help names it (Patrick, 4 Oct). | None |
| `/help`, `/commands` | Anybody, typed out of habit | Says where the help panel is and names the list; a tester is told theirs as well | The `/help` branch of `handle`, `helpLine` | Nowhere. The Help page, the site's help and the reply to a word nobody has point at the panel | The help panel, on HelpKey (F7) and on Help on the K, P and J panels. Nobody is told to type `/help`. | #1633 |
| `/merchant <id>`, `/merchant buy`, `sell`, `supply`, `close` | Anybody at a guild trader | A trader's wares | The `/merchant` branch of `handle`, then the merchant block's `command` | Nowhere. [Merchant's Guild](merchants-guild.md) names E and the panel | E on a trader opens the panel, which sends the rest. Out of the list and the page (#1633). | #1633 |
| `/apprentice <id> <half>`, `/apprentice end <id> <half>`, `/apprentice leave <half>`, `/apprentice` | A Master takes on; either of them ends it | Takes somebody on, ends it from either side, says who is whose | `apprenticeCommand` in the character block | Nowhere. [Masters and apprentices](apprenticeship.md) names the prompt row and the K page | K on the look prompt, for a Master looking at somebody they could take on, opens the Masters and apprentices page on K with Take on for each half; End there for each side; Accept and Refuse for the learner. Never in the list or the help. | #1634 |
| `/study` | Anybody in the College rooms | A spell point in a semester | Never a word. Study on the K panel's College page sends `/pick study`, below | [Magic](magic.md), [Masters and apprentices](apprenticeship.md) | Study on K, which the server answers only in the College's rooms. | #1387 |
| `/ride`, `/ride <stop>` | Anybody at a driver | Where the driver goes and the fares; pay and go | The `/ride` branch of `handle`, then the carriages block's `command` | Nowhere. [Carriages and ferries](carriages.md) names E and the panel | E on a driver opens the panel of his stops and fares, and its Ride button sends `/ride` and the stop. Never in the list or the help. | #1635 |
| `/plant`, `/plot`, `/claim` at a plot | Anybody with the class | Sows a plot, says what is in it, claims the farm | `command` in the character block, then the farming block's `command` | Nowhere since #1636; [Farmer](classes/farmer.md) names the line and the keys | A crop under the crosshair draws a line of what is in the ground and whose farm it is; E on an empty plot sows it, and X claims the farm when the line says so. Out of the list and the help. | #1636 |
| `/claim` at a door, `/deed`, `/deeds` | Anybody | Claims a building and hands the deed; lists what you hold | `command` in the character block, then the property block's `command` | Nowhere since #1637; [Property](property.md) names the key | X at a door just opened, while its line says Claim, sends `/claim <id>`; the property page on K lists what you hold, with the rent owed and the farm. Out of the list and the help. | #1637 |
| `/lock`, `/unlock` | The holder, or whoever carries the deed, at the door | Locks and unlocks the building | The property block's `command`, `setLock` | Nowhere since #1637; [Property](property.md) names the key | X at a door just opened sends `/lock <id>` or `/unlock <id>`, as its line says. Out of the list and the help. | #1637 |
| `/mold`, `/key` | A smith | A mold at a door, a key at a forge | The property block's `command`, `mold` and `cutKey` | Nowhere since #1637; [Property](property.md) names the keys | U presses a blank mold into the door; X at a forge, carrying a mold that has been pressed into a door, sends `/key <id>` and cuts a key for an iron ingot. Out of the list and the help. | #1637 |
| `/jarl` | The Discord Jarl role, or an admin | Seats the Jarl office on this character | `jarlCmd` in the property block, through the character block's `command`, which hands it on since #1640 | Nowhere. [Offices](offices.md) names the page | Take the office, on the Office page of K, sends it. Never in the list or the help. | #1638 |
| `/steward`, `/steward <id>`, `/steward -<id>` | A Jarl; anybody asks who holds it | Names or removes a steward | `stewardCmd` in the property block | Nowhere. [Offices](offices.md) names the page | Name steward beside a person in the world, and Remove beside a steward, on the Office page of K, send the person's profile id. Never in the list or the help. | #1638 |
| `/evict`, `/rent`, `/box` | A steward; anybody asks the rent or which box | Ends a claim, sets rent, marks the hold's box | `evict`, `rentCmd` and `boxCmd` in the property block | Nowhere. [Property](property.md) names the page | Evict, Set rent and No rent for the door opened in the last minute, and a hold's town for the container opened in the last minute, on the Office page of K. The board panel says what the box has been paid. Never in the list or the help. | #1638 |
| `/board move <hold>`, `/board here` | A steward | Moves a notice board | `board` and `moveBoard` in the property block | Nowhere. [Notice boards](noticeboards.md) names the page | A board's town on the Office page of K, pressed twice, sends `/board move <hold>`. Nothing sends `/board here`. Never in the list or the help. | #1638 |
| `/me`, `/do`, `/whisper`, `/w`, `/shout`, `/s`, `/yell`, `/y` | Anybody | How a line is said, and how far it carries | `voice/voice-server.js:427`, `voice/headlines.js:28` | The list, as `/me`, `/do`, `/w`, `/s` and `/y`; the help panel's Talking; Help page "How a line is said"; [Text chat](chat.md), [People beside you](people.md), [Emotes](emotes.md); the voice service's usage lines | Stays a command, with no buttons, and the help names it (Patrick, 4 Oct). | None |
| `/ooc`, `/o` | Anybody | Out of character, to whoever is near | `gamemode.js:45334` | The list; the help panel's Talking; Help page; [Text chat](chat.md), [Factions](factions.md), [Notice boards](noticeboards.md); `site/data/site/rules.md` | Stays a command, with no buttons, and the help names it (Patrick, 4 Oct). | None |
| `/roll`, `/r` | Anybody | Dice, rolled on the server | `game/ui/thornswood-chat.js:334`, `gamemode.js:45419` | The list; the help panel's Talking; Help page "Dice"; [Text chat](chat.md) | Stays a command, with no buttons, and the help names it (Patrick, 4 Oct). | None |
| `/repair`, `/repair mend <base> <condition> <name>` | Anybody with a repair kit | Opens the repair panel; a row's Mend button mends that piece with a kit | The `/repair` branch of `handle`, then `panel` in the durability block | Nowhere. [Durability](durability.md) names the key and the panel | U in the inventory, with a kit in the pack, opens the panel, and Mend sends `mend`. Never in the list or the help. | #1384 |
| `/treat`, `/treat <id>`, `/treat <me or id> <cloth, bandage, splint, poultice, remedy or set>` | Anybody, on themselves or on somebody hurt within about 4 metres | Opens the wounds panel for you or for them; a row's button gives that treatment | The `/treat` branch of `handle`, then `panel` in the injury and disease block | Nowhere. [Injury](injury.md) names the keys and the panel | H in the inventory, while you have a wound to tend, opens yours; X on somebody hurt, as the look prompt says, opens theirs; each button sends the treatment. Never in the list or the help. | #1383 |
| `/maneuver <name>`, `/maneuver` | A warrior | Starts a warrior's maneuver; with no name, says which you hold | `gamemode.js`, `use` in the warrior maneuvers block | Nowhere. [Warrior](professions/warrior.md) names the key | The maneuver key (9) opens a panel of yours, and a number or a click there sends it. Never in the list or the help. | #1386 |

`/pick` and `/spend` are the K panel's lines (`gamemode.js:40783`):
profession, class, town, spells and points, `/pick perk fontofmagic`
from the Use button beside Font of Magic, `/pick study` from the
Study button on the College page (#1387), and `/pick weave warmth` or
`/pick weave armour` from Warmth and Armour on a Master Weaver's
profession card (#1398). K sends them and nothing tells anybody to
type them, so there is nothing to turn.

## Staff and dev commands

These stay commands. How to run each one, with examples:
[Developer-Guide.md, Q. Staff commands](../../Developer-Guide.md#q-staff-commands).

| Command | Who | What it does | Read at | Where staff are told |
| --- | --- | --- | --- | --- |
| `/tp <place>`, `/goto <place>`, `/tp` | Testers and dev: the Playtester role on Discord (the door's allowed list), the written playtester and dev lists, and the admins | Moves you to a town or a named place; `/tp` alone lists the places | `gamemode.js:45107`, `isPlaytester` (45799) | The reply to `/help` and to a word nobody has adds a line for them, and for nobody else (`helpLine`) |
| `/give <item> [count]`, `/spawn <creature> [count]` | Testers and dev | Makes items in your pack, or creatures beside you | `gamemode.js:45243` | The same line |
| `/where` | Testers and dev, refused to everybody else the way `/give` is (#1633) | The cell, position and angle you stand at | The `/where` branch of `handle`, `isPlaytester` | The same line |
| `/kick`, `/freeze`, `/unfreeze`, `/bring`, `/goto <person>`, `/silence`, `/unsilence`, `/warn`, `/spawnat`, and `/give`, `/spawn` and `/tp` aimed at a person | Staff: Owner, Dev, Gamemaster, Moderator, Loremaster, the admins and the dev list, on a proven connection with a join pass | Moderation in the world | The staff block's `command`, `gamemode.js:53418` | The staff block's header (52661); [Voice](voice.md) for silence |
| `/ban`, `/unban`, `/banaccount`, `/unbanaccount`, `/pk`, `/note` | Staff | Bans, a character killed for good, and notes, kept on the site | `gamemode.js:53478` | The staff pages on the site (`site/public/hub.js`) |
| `/unpk` | Admins only | Undoes a PK made by mistake | `gamemode.js:53477` | The staff pages on the site |
| `/embassy`, `/embassy add <name> [armed]`, `arm`, `disarm`, `remove` | Admins only | Shows and writes the embassy roll: 20, of whom 6 may be marked armed; the 21st and the 7th armed are refused (#1390) | `command` in the embassy and remnant block | [The Imperial Embassy](embassy.md), [Offices](offices.md) |
| `/remnant`, `/remnant add <name>`, `remove` | Admins only | Shows and writes the Thalmor remnant roll, once an application is accepted (#1390) | `command` in the embassy and remnant block | [The Thalmor](thalmor.md) |
| `/hurt <person> [what]` | Staff | A cut, a bite, a break or a disease for a scene, an agreed loss written down after a yes given out of character, or what somebody carries (#1383) | The staff block's `command`, which hands it to `staff` in the injury and disease block | The staff block's header; [Injury](injury.md) |
| `/restart`, `/shutdown` | Nobody | Answers that restarts are not run from chat | `gamemode.js:45207` | Nowhere |
| `/close` (Discord), and the Close ticket button | Staff: the bot's `STAFF_ROLES` (Owner, Dev, Gamemaster, Moderator, Loremaster), by id or name; Manage Threads alone is not staff (#1342) | Closes a ticket, and only in a ticket's own thread; anywhere else it says it only works inside a ticket (#1776) | `close_here`, `is_ticket_thread` and `is_staff` in `bot/bot.py` | Discord's own command list |
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
| `/plot <id>`, `/claim <id>` at a crop | A crop under the crosshair, and X at it (#1636) | Asks for the line at that plot; claims the farm around it | The farming block's `command`, `plotLine` and `claim` |
| `/rest bed`, `/rest sit`, `/rest up` | Lying down, sitting down and getting up | Resting in a bed or on a seat, as the server measures it | `bedRest` in the property block's beds |
| `/sleephere <id>`, `/sleephere stop <profile> <building>` | U on a person inside a building you hold, and Stop on the K panel's property page | Lets them sleep there for a night, or ends their night (#1603) | `sleepHere` in the property block's beds |
| `/ride e <id>`, `/merchant e <id>` | E on a driver or a trader | Which one was pressed | `gamemode.js:44593`, `54951` |
| `/party refresh`, `/trade refresh`, `/pick refresh` | A panel as it opens | Send the panel its view | `gamemode.js:44722`, `44847`, `40783` |
| `/skill` | The client's unused skills menus | Nothing: the page drops it before it is sent | `game/ui/thornswood-bridge.js:72` |
