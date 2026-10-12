# The Thornswood Discord

What `Setup-Discord.ps1` builds, why it is shaped that way, and the handful of
things a bot is not allowed to do for you.

## The shape of it

another server has nine hold channels, two world instances and eighty Thalmor
Inquisitors. That shape is right for eighty thousand people and wrong for six,
because forty channels with nothing in them reads as abandoned rather than
organised. This is the same skeleton with the empty rooms left out, and it
grows by adding to a category rather than by rebuilding.

### Start Here

| Channel | Who writes | What it is |
|---|---|---|
| `#rules` | staff | Seven rules, short on purpose |
| `#welcome` | staff | What this is and the three steps to get in |
| `#start-here` | staff | Installing, joining, where the logs are |
| `#say-hello` | anybody | The one channel somebody who is not approved yet can talk in |

These four and the Applications category are all somebody sees before staff
give them Member. The category itself is open to everybody, and the three
read only ones stay read only.

### Information

| Channel | Who writes | What it is |
|---|---|---|
| `#news` | the launcher | Every release, posted automatically |
| `#updates` | staff | Restarts, notices, anything happening today |
| `#faq` | staff | The questions people actually ask |

Downloads, known issues and credits are all pages on the website. A copy in
Discord is a copy that goes stale, so the welcome post links to them instead.

### Applications

| Channel | Who reads | What it is |
|---|---|---|
| `#tickets-and-applications` | everybody | The bot's ticket panel: applying for any job, reporting somebody, cannot install or connect. Each ticket opens a private thread only the person and staff can read |
| `#tickets` | staff only | Every closed ticket, with a link back to it, and the whole of any ticket whose private thread would not open |

`#tickets` has to stay staff only, because a report about somebody lands there
when its thread fails. The bot checks the channel's permissions rather than
its name, and passes over a `#tickets` anybody else can read.

### Help

| Channel | What it is |
|---|---|
| `#suggestions` | A forum, mods and features, Nexus link included |
| `Support` (voice) | Where a ticket goes when typing is slower than talking |

Installing and connecting problems are a ticket, not a public forum. Half of
them involve somebody's machine, their paths, or their account, and none of
that belongs in a channel everybody reads.

`#bugs` and `#logs-and-crashes` were here and are gone. The builder still
names both so that a prune never deletes a channel of either name, and never
makes them again (`make=False`). A bug goes in a ticket or in `#general-chat`
until somebody decides otherwise.

### Thornswood

`#general-chat`, `#media`, `#welcome-travelers`, `#game-rules`,
`#server-progression-and-economy`.

One general. A second one only ever splits the same conversation in half. It
was `#general` until it was renamed, and the topic on it is written by hand,
so the builder leaves the topic alone. `#welcome-travelers` is where the join
cards go, and the server's system channel points at it.

`#game-rules` sits here rather than in In Character, because that is where it
was moved to. It carries the nine in-world rules, read out of the "In the
World" part of `site\data\site\rules.md`, the /rules page, so the two cannot
disagree.

### In Character

`#character-introductions` (a forum, one post each), `#tales` (a forum, one
story per post), `#lore`, `#rp-appreciation`, `#graveyard`.

### The Holds

`#choose-your-hold` at the top, where the bot's buttons are, then one channel
per hold: `#whiterun` `#solitude` `#windhelm` `#riften` `#markarth`
`#dawnstar` `#morthal` `#falkreath` `#winterhold`.

In character. What is said there is said in the hold. A hold with nowhere to
talk is a line on a map, and it is what makes the onboarding question mean
something.

### Voice

**AFK** and **General**.

Proximity voice is in the launcher, so these are for before, after, and
whoever is not in the world. AFK is set as the server's real AFK channel, so
Discord moves people into it after five minutes of silence rather than hoping
they remember to move themselves.

The support voice channel sits in Help, because that is what it is for.

### Testing

`#test-findings` (a forum, `test-results` until 11 October), `#test-tasks` (a
forum), `#known-issues` and **play-testing** (voice), visible to Playtesters
and staff and to nobody else. `#test-tasks` also lets in the lead gamemaster
role, which may post test tasks and is not otherwise in that gate. It is on
that channel's own line in the builder's plan, so no other channel moved.

`#test-tasks` replaces `#test-these`, which was deleted in the channel cleanup,
and `#test-these` is in the builder's retired list so a re-run does not bring
it back. Until 11 October `#test-tasks` carried the Live smoke checklist
(dated sessions with Pass, Fail, Skip and Fail-known rows, `/live-smoke`).
Patrick's card of that day took all of it out.

**Test tasks.** One thread per test task, from a title and a body, with the
forum's Dev or Main tag on it:

    /test-task title body tag     in Discord: Owner, Dev and Lead Gamemaster
    python bot.py --env-file C:\Thornswood-Bot\bot.env.json --post-task --title "..." --body-file task.txt --tag Dev

Who may post is `TEST_TASK_ROLES` in `bot.env.json`, by role id (preferred) or
name, Owner, Dev, Lead Gamemaster and Lead GM by default. A `bot.env.json`
that still carries `LIVE_SMOKE_ADMIN_ROLES` is read for it. A thread already
open under the same title is handed back rather than made twice.

**Known issues.** One bot post in `#known-issues` per open issue in
`EvilPatrick06/Thornswood` labelled Dev Findings or Main Findings, linking the
issue. When the issue is closed as completed (confirmed fixed) the post is
struck through and says Fixed; closed any other way it says Closed, not fixed;
reopened, it goes back. The bot reads GitHub every five minutes
(`KNOWN_ISSUES_EVERY`, never under a minute) with `GITHUB_TOKEN` from
`bot.env.json`, a read only token for that repository's issues. No token, no
posts, said once in the log. Issue number to message id is kept in
`data\known-issues.json`, written straight after each post, and the bot's own
recent posts in the channel are read on start, so neither a restart nor a crash
between a post and its save posts twice.

**The one-time setup.** Moving a server from the old shape is the only channel
change the bot makes, Patrick's explicit exception for these three changes. It
runs only when asked, never on a start:

    python bot.py --env-file C:\Thornswood-Bot\bot.env.json --setup-channels           (preview, changes nothing)
    python bot.py --env-file C:\Thornswood-Bot\bot.env.json --setup-channels --apply   (does it, once)

It turns `#test-tasks` into a forum with the Dev and Main tags. Discord cannot
convert a text channel to a forum, so when it refuses, a new forum is made in
the same category and position with the old channel's permission overwrites,
and the old channel is renamed `#test-tasks-archive` with sending switched off
for everyone but the bot. Nothing is deleted. It renames `#test-results` to
`#test-findings`, and makes `#known-issues` beside it with the same
overwrites. A finished apply is written to `data\channel-setup.json` and a
second run does nothing; an apply that stopped part way does only what is left.
`test-testing-channels.py` holds all of this.

### Staff

A staff `#news` where the site watcher speaks, `dev-test-results` (a forum),
`#staff-general` and a Staff Room. Invisible to everybody else.

`#dev-notes`, `#deploys` and `#reports` were here and are gone, and like
`#bugs` the builder keeps their names so that a prune cannot take a channel of
that name and no run makes them again.

## Roles

Top of the list downwards. They are Thornswood's own names rather than job
titles, because "Moderator" sitting beside "Jarl of Whiterun" reads like two
different servers stitched together.

| Role | Colour | What it means |
|---|---|---|
| Owner | gold | Runs the place. You |
| Lead Gamemaster | deep blue | Runs the gamemasters, and posts test tasks |
| Dev | violet | Builds and deploys it |
| Gamemaster | blue | Runs things in world |
| Loremaster | teal | Writes the world |
| Trial Gamemaster | pale blue | A gamemaster on trial. Sees every hold, not the staff channels |
| Moderator | green | Moderates |
| Content Creator | rust | Makes videos about it |
| Server Booster | pink | Boosted the server. Discord's own role, never made here |
| Playtester | copper | Tests the builds |
| Milk Drinker, Talos Worshiper, Thalmor Boot-Licker | | The three Patreon tiers |
| Jarl of *hold* | bright gold | Holds that hold. Nine of them, one each |
| Citizen of *hold* | slate | Where your character lives |
| Member | grey | Given by staff after an application is accepted |
| Banned | grey | What the site keys a ban off. No permissions, not hoisted |
| Patreon, News Pings, Updates Pings | | Made by Patreon and by the bot, never here. They are in the builder's list for their place in the order and nothing else |

Owner, Dev, Moderator and Gamemaster are staff as far as the channels are
concerned: they see the staff channels and can post in the read only ones.
Lead Gamemaster and Trial Gamemaster are not in that list, so neither opens
`#reports`; both see every hold, and the lead gamemaster role is named on
`#test-tasks` by that channel's own line in the plan. Loremaster sees every
hold as well.

Neither is staff to the bot either. Closing a ticket, with `/close` or the
Close ticket button, and skipping the one open ticket rule and the cooldown
take one of the `STAFF_ROLES` roles in `bot.env.json` (Owner, Dev, Gamemaster,
Moderator and Loremaster by default), matched by id or name, and nothing
else. The Manage Threads that both of them carry on every channel used to
count as staff there, and it no longer does (#1342). `test-staff-gate.py`
runs every staff and admin command and button as somebody who is not staff
for it, and fails on any new one whose gate is not written down in it.

Both close a ticket and nothing else: a thread off a `TICKET_CHANNEL`
channel, where the panel opens them. In any other thread, a `#test-tasks`
post or a `#tales` post, they answer that they only work inside a ticket
and archive and write down nothing (#1776, `test-1776-close-tickets-only.py`).

Staff roles are job titles on purpose. Thane, Steward, Warden and Housecarl are
all things somebody should be able to play, and a moderator wearing one makes
every in-world use of the word ambiguous.

The hold roles grant nothing at all. Somebody playing a Jarl still needs Member
to get through the door, which means a Jarl can be banned like anyone else
without unpicking their title first.

Eighteen hold roles sounds like a lot for a small server. Discord only shows a
hoisted group in the member list when somebody in it is online, so the empty
ones stay invisible until they are not.

Owner and Dev are administrators. Moderator can time out, kick, ban and delete.
Gamemaster can time out and manage threads but not ban. The rest is ordinary.

Give the people testing with you **Playtester**. That role is access.play,
and it is what opens the game. Staff give **Member** after an application is
accepted. Discord has no default-role setting. Then the person picks a hold.

## The three things the bot cannot do

1. **Turn on Community.** Server Settings, Enable Community. Without it there
   are no forum channels, no announcement channel and no rules screen. Run
   `Setup-Discord.ps1` again afterwards and the text channels standing in for
   forums are replaced with real ones.

2. **Point the rules screen at the rules.** Community, then Safety Setup. That
   is what makes people accept the rules before they can type.

3. **Hand Member out on join.** It cannot. Discord has no default-role
   setting, so there is nothing to turn on under Server Settings, Roles.
   Staff give Member after an application is accepted. Playtester
   (access.play) is what opens the game.

## Changing the words later

`content.py` holds every read only post. Edit it, run `Setup-Discord.ps1`
again, and the posts are rewritten in place. It deletes what the bot wrote last
time rather than adding a second copy, so the rules never end up posted twice.

## Putting a bot change on the VPS

From a checkout of main that has just been pulled, never from a copy of the
repository that was downloaded earlier:

    git checkout main
    git pull
    .\scripts\deploy\Install-Bot.ps1 -CodeOnly

The pull comes first because a deploy sends what the commit holds. A stale
folder sends the bot as it was before the change and says nothing about it,
and the same folder builds the Discord as it was before the change if
`Setup-Discord.ps1` is run from it. That is how a live smoke went out of a
folder in Downloads that had not been pulled for days.

`-CodeOnly` stages the code beside the running bot and checks it there, then
stops the service, renames the new files in, starts it again by its name and
waits for it to say it is watching the server. If it does not, the old files
go back and it is started on those. Python, the libraries, the token and the
service itself are left alone.

So a library moved in `requirements.txt`, by a Dependabot pull request or by
hand, does not reach the box with `-CodeOnly`: that sends the file and leaves
`py-libs` as it was. The full run, `.\scripts\deploy\Install-Bot.ps1 -NoToken`,
installs the pinned versions into a new `py-libs` and swaps it in with the
code, so a bump that stops the bot from starting puts the old libraries back.
The pull request build only parses the bot; the nightly runs its harnesses.
So before merging a bump, install the new pins and run `bot\test-*.py` on
them, the way [Setting up a machine](../Developer-Guide.md#setting-up-a-machine)
installs them (#1401).

What goes up with it: `bot.py`, `card.py`, the channel ids, the card artwork,
and `requirements.txt`. A file the bot reads and this list does
not name is a file that is only ever on main, never on the box.

Nothing else stays in the bot's folder (#1184). It holds what that list sends
and what is the bot's own: `bot.env.json`, `thornswood-deploy.json` (the
record of what runs there), `data`, `service`, `webhooks`, `py-libs`, and,
until a full run moves them into `data` or takes them off, the log, the
records and the old loop's `run.ps1` and `roll-log.ps1` from before the
service. Every run moves anything else there aside into `.prev-<stamp>`, with
the code it replaced, and names each one; `Get-ThornswoodBotOwned` in
`scripts\vps\Bot-Service.ps1` is that rule. `-PutBack` puts them back with
that code, and they leave the box with that `.prev` folder two deploys later.
So a file copied in by hand, `backfill.py` or `redraw.py` for a run of it,
is copied from the repository for that run, and the next install moves it
aside, rather than sitting on the bot's import path from then on.

The bot's log is `C:\Thornswood-Bot\data\bot.log`: in the data folder under
the bot's folder, the one folder its account writes, rather than beside the
code where it used to be. Every `-CodeOnly` run leaves that file on the box,
empty if the bot has not written to it yet, so the path is always something to
look at. `.\scripts\vps\Show-BotLog.ps1` reads whichever of the two files the
bot is really writing, which on a box whose service program is older is still
the one beside the code.

Those paths are on the VPS, not on the machine you run the deploy from, so
`Test-Path C:\Thornswood-Bot\data\bot.log` there answers for a folder that
machine does not have. `Show-BotLog.ps1` and `.\scripts\vps\Get-Logs.ps1` are
how to look at them.

You do not have to check by hand at all. Once the swap has answered, every
run asks the box itself and prints one line per file, under the heading
"What the box has, at the folder the swap moved them to":

```text
asked of THORNSWOOD-VPS, where the bot runs from C:\Thornswood-Bot
Test-Path C:\Thornswood-Bot\bot.py  True
Test-Path C:\Thornswood-Bot\card.py  True
Test-Path C:\Thornswood-Bot\data\bot.log  True
```

A run that ends green has printed True for every file it sent and for
`data\bot.log`. A file that is not there turns the run red and names it by
its full path on the box, so a swap that says SWAP OK while something is
missing from the install root cannot pass for a good deploy. If a line says
False, that is the box talking and it is worth looking at; a False you typed
yourself on the deploy machine is only that machine saying it has no such
folder.

## Release notes posting themselves

The build makes a webhook in `#news` and saves it to `news-webhook.txt` beside
these files. `Ship.ps1` calls `Publish-Discord.ps1` at the end of every
release, which reads the newest entry out of `version.json` and posts it.

The same entry goes to `thornswood.net/news` at the same moment, from the same
source, so the launcher, the site and the Discord cannot disagree about what
shipped.

`news-webhook.txt` is a one way address into that one channel. It is not a
password and it cannot read anything, but anybody holding it can post as
Thornswood, so do not put it in the repository or paste it anywhere.

## Being told when the bot or the VPS stops, from outside

The watchdog on the VPS tells the staff channel when something there dies,
and One watches the site from outside (issue #448). Neither can say anything
when the whole VPS is off or cut off while One is off too. So the bot pings an
outside uptime monitor once a minute while it is on Discord, and when the
pings stop for five minutes the monitor emails you (issue #449). That covers
a bot that stopped, hung or lost Discord, and a VPS that went down.

The monitor is **Cronitor** (cronitor.io): its free plan needs no card, keeps
five checks, and you sign in with GitHub. The bot only needs a web address to
ping, so healthchecks.io (free, no card, signs in by an emailed link) works the
same way if Cronitor ever does not suit.

Once, on One:

1. Go to cronitor.io, Sign up, **Sign up with GitHub**, and sign in as
   EvilPatrick06. If it offers a trial that asks for a card, pick the free
   plan instead; it needs none.
2. Make a new monitor of the kind **Heartbeat**. Name it `Thornswood bot`.
   Expected every **5 minutes**, grace period **5 minutes**. Cronitor's
   free Hacker plan lists its fastest check frequency as 5 minutes
   (https://cronitor.io/pricing), so do not set this to 1 minute. The bot
   still pings about once a minute, which is inside that window.
3. Alerts: leave the default notification list, which emails the address on
   the account. To hear it in Discord as well, add a Discord webhook to that
   list; the monitor posts it itself, so it arrives even when the VPS is
   down.
4. Save, then copy the monitor's ping address (its telemetry URL, starting
   `https://cronitor.link/p/`). It is a secret: whoever has it can keep the
   monitor quiet. Do not paste it anywhere but the prompt below.
5. From the repository folder, once the pull request that added this is
   merged and pulled:

   ```
   .\scripts\deploy\Install-Bot.ps1 -NoToken
   .\scripts\deploy\Install-Bot.ps1 -SetPing
   ```

   The first is the full run, which installs the service and sends the
   bot code that pings. -CodeOnly refuses until that service exists. The
   second asks for the address hidden, puts it in
   `C:\Thornswood-Bot\bot.env.json` as `PING_URL` over ssh's standard
   input, restarts the bot by name, and prints the bot's first line about
   it: `reached the outside monitor` is right. The monitor's page then
   shows a ping a minute.

To stop it, run `-SetPing` again and type `off`, then pause or delete the
check on the monitor, or it emails you that the bot went quiet. A full
`Install-Bot.ps1` run keeps the address. The bot says in `bot.log` once when a
ping fails and once when they work again, never the address; a slow or dead
monitor never holds up anything the bot does on Discord.

## Community setup, field by field

These three are on the Enable Community screen and none of them can be set by
a bot.

| Field | Now | After the build |
|---|---|---|
| Rules or guidelines channel | `#rules` | leave it |
| Community Updates Channel | `#general-chat`, because nothing else exists yet | `#staff-general` |
| Safety Notifications Channel | `#general-chat` | `#staff-general` |

Both of the last two carry moderation and safety notices about your own server,
some of it about specific people, so they do not belong in a channel everybody
reads. Come back and move them the moment `Setup-Discord.ps1` has made the
Staff category.

**Server description.** This is what shows in the embed whenever somebody
pastes your invite link anywhere, so it is worth more than it looks:

> A Skyrim roleplay server set fifty years after the civil war. Fewer NPCs, not
> none, so the world is still alive at three in the morning. Free, and Special
> Edition is all you need.

## Onboarding

Server Settings, Onboarding. This is the thing that turns a wall of channels
into a door. `Build-Onboarding.py` sets it with the bot, from the rows it was
written out in (issue #427, the board's "Discord onboarding, field by field"),
so the words live in one file and every role and channel is looked up by name
on the server when it runs:

    .\scripts\deploy\Set-DiscordOnboarding.ps1 -Check    says what it would set, changes nothing
    .\scripts\deploy\Set-DiscordOnboarding.ps1 -Off      writes it, leaves it off for Preview
    .\scripts\deploy\Set-DiscordOnboarding.ps1           writes it and switches it on

Run `-Check` first, every time. It names every channel Discord would refuse
and why, and sends nothing while anything fails. The bot needs Manage Server
and Manage Roles for the write: tick Administrator on its role for the run and
untick it after.

Discord will not switch onboarding on until it has **at least 7 default
channels and at least 5 of them that everybody can post in**, and it only
takes channels everybody can see. Read only channels do not count toward the
five.

What it sets:

- **Default channels**: `#welcome` `#rules` `#start-here` `#news`, read only,
  and `#general` `#media` `#character-introductions` `#tales`
  `#rp-appreciation`, where people talk. Nine, five writable, which is exactly
  the minimum.
- **What are you here for?** Pick several, optional, channels only: Roleplay
  shows `#tales`, Just playing `#general`, I want to help test
  `#tickets-and-applications` (testing starts with an application), I make
  videos `#media`.

`Build-Onboarding.py` still names `general` and `test-these`, which the server
no longer has: they are `#general-chat` and `#test-tasks` now. It looks every
channel up by name on the server, so `-Check` names both and sends nothing
until the script is caught up. That is its own change and its own issue on the
board.
- **Which hold does your character call home?** Only with `-GrantMember`. Pick
  one, members must answer. Each hold gives Member and its own Citizen role,
  which opens that hold's channel; Not decided yet gives Member only. Off by
  default, because Member is what staff give once an application is accepted
  (the gate in `Build-Discord.py`), and a hold is picked in `#choose-your-hold`
  after that.
- **Rules and age.** `-Rules` and `-Age` each add one required question, off
  by default until it is decided that they belong here (entry 181).

It never hands out anything but Member and the Citizen roles, and refuses one
that carries a power such as Administrator or Manage Roles. The role that opens
the game is given by a person when an application is accepted. The Server
Guide (the welcome sign, the to do list and the resource pages) has no bot
side, so it stays a by hand step.

Then walk it: Server Settings, Onboarding, **Preview** at the top right, and
check every answer gives the role you meant.
