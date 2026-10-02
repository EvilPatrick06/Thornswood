# The Thornswood Discord

What `Setup-Discord.ps1` builds, why it is shaped that way, and the handful of
things a bot is not allowed to do for you.

## The shape of it

another server has nine hold channels, two world instances and eighty Thalmor
Inquisitors. That shape is right for eighty thousand people and wrong for six,
because forty channels with nothing in them reads as abandoned rather than
organised. This is the same skeleton with the empty rooms left out, and it
grows by adding to a category rather than by rebuilding.

### Top, no category

| Channel | Who writes | What it is |
|---|---|---|
| `#welcome` | staff | What this is and the three steps to get in |
| `#rules` | staff | Seven rules, short on purpose |
| `#start-here` | staff | Installing, joining, where the logs are |

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
| `Support` (voice) | Where a ticket goes when typing is slower than talking |
| `#bugs` | A forum, one post per problem |
| `#suggestions` | A forum, mods and features, Nexus link included |
| `#logs-and-crashes` | Drag the file straight in |

Installing and connecting problems are a ticket, not a public forum. Half of
them involve somebody's machine, their paths, or their account, and none of
that belongs in a channel everybody reads.

### Thornswood

`#general`, `#screenshots`, `#clips`, `#bot-commands`.

One general. A second one only ever splits the same conversation in half.

### In Character

`#character-introductions`, `#tales` (a forum, one story per post),
`#graveyard`.

### The Holds

One channel per hold: `#whiterun` `#solitude` `#windhelm` `#riften` `#markarth`
`#dawnstar` `#morthal` `#falkreath` `#winterhold`.

In character. What is said there is said in the hold. A hold with nowhere to
talk is a line on a map, and it is what makes the onboarding question mean
something.

### In character, the rest

`#game-rules` carries the nine in-world rules, read out of the "In the World"
part of `site\data\site\rules.md`, the /rules page, so the two cannot
disagree. `#lore` carries the setting.
`#character-introductions`, `#tales` (a forum), `#rp-appreciation` and
`#graveyard`.

### Voice

**The Bannered Mare**, **The Road**, and **AFK**.

Proximity voice is in the launcher, so these are for before, after, and
whoever is not in the world. AFK is set as the server's real AFK channel, so
Discord moves people into it after five minutes of silence rather than hoping
they remember to move themselves.

The support voice channel sits in Help, because that is what it is for.

### Testing

`#test-tasks` and `#test-results`, visible to testers and staff and to nobody
else. `#test-tasks` also lets in the lead gamemaster role, because that role
may open a Live smoke session and the rest of that gate does not include it.
It is on that channel's own line in the builder's plan, so no other channel
moved.

`#test-tasks` replaces `#test-these`, which was deleted in the channel cleanup.
It is a new channel rather than that one renamed, and `#test-these` is in the
builder's retired list so a re-run does not bring it back.

It carries the living Live smoke checklist. The rows are not written in
Discord: they are the Live slice of the acceptance criteria in the vault,
exported to `live-smoke-discord-export.json`, which is deployed beside
`bot.py`. Staff open a dated session and the bot posts one message per row,
each with Pass, Fail, Skip and Fail-known on it, in a thread off the opener:

    /live-smoke start    settings version and live channel, opens a session
    /live-smoke reset    closes the session open now and opens a fresh one
    /live-smoke refresh  reads the export again and updates the checklist post

Those three are **Owner, Dev and Lead Gamemaster**, which is wider than Owner
and Dev and narrower than the staff roles: a Moderator alone does not open or
reset a session. They are matched by role name, never by id, so a renamed role
is fixed by setting `LIVE_SMOKE_ADMIN_ROLES` in `bot.env.json` rather than by a
deploy. Testers and staff mark their own rows. Agents do not.

A mark is an edit to the Discord message it was pressed on. Nothing writes a
mark, a name or an account id to the site, to a database, to a file or to the
bot's log, and nothing posts a named fail anywhere outside the session thread.
Everybody who can read the thread can read the marks in it, and the opener
says so. Going further than that, keeping marks anywhere off Discord, needs
the Privacy page changed first.

When the Live set moves, the export changes in the vault and the copy in `bot`
changes with it in the same pull request. Then
`.\scripts\deploy\Install-Bot.ps1 -CodeOnly` puts it on the VPS, and
`/live-smoke refresh` updates the post people read. A session already open
keeps the rows it was opened with; the next `start` uses the new set.

### Staff

`#staff-general`, `#dev-notes`, `#deploys`, `#reports`, and a Staff Room.
Invisible to everybody else.

## Roles

Top of the list downwards. They are Thornswood's own names rather than job
titles, because "Moderator" sitting beside "Jarl of Whiterun" reads like two
different servers stitched together.

| Role | Colour | What it means |
|---|---|---|
| Owner | gold | Runs the place. You |
| Dev | violet | Builds and deploys it |
| Moderator | green | Moderates |
| Gamemaster | blue | Runs things in world |
| Loremaster | teal | Writes the world |
| Content Creator | rust | Makes videos about it |
| Playtester | copper | Tests the builds |
| Milk Drinker, Talos Worshiper, Thalmor Boot-Licker | | The three Patreon tiers |
| Jarl of *hold* | bright gold | Holds that hold. Nine of them, one each |
| Citizen of *hold* | slate | Where your character lives |
| Member | grey | Everybody, handed out on the way in |

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

Give the people testing with you **Playtester**. Everyone gets **Member** on the
way in, then picks a hold.

## The three things the bot cannot do

1. **Turn on Community.** Server Settings, Enable Community. Without it there
   are no forum channels, no announcement channel and no rules screen. Run
   `Setup-Discord.ps1` again afterwards and the text channels standing in for
   forums are replaced with real ones.

2. **Point the rules screen at the rules.** Community, then Safety Setup. That
   is what makes people accept the rules before they can type.

3. **Hand out Member on join.** Server Settings, Roles, edit Member, and
   turn on the default role option, or use whatever bot you like for it. A
   rules screen plus an auto role means somebody who has not accepted the rules
   cannot post anywhere.

## Changing the words later

`content.py` holds every read only post. Edit it, run `Setup-Discord.ps1`
again, and the posts are rewritten in place. It deletes what the bot wrote last
time rather than adding a second copy, so the rules never end up posted twice.

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
   Expected every **1 minute**, grace period **5 minutes**.
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
   .\scripts\deploy\Install-Bot.ps1 -CodeOnly
   .\scripts\deploy\Install-Bot.ps1 -SetPing
   ```

   The first puts the bot code that pings on the VPS. The second asks for the
   address hidden, puts it in `C:\Thornswood-Bot\bot.env.json` as `PING_URL`
   over ssh's standard input, restarts the bot by name, and prints the bot's
   first line about it: `reached the outside monitor` is right. The
   monitor's page then shows a ping a minute.

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
| Community Updates Channel | `#general`, because nothing else exists yet | `#staff-general` |
| Safety Notifications Channel | `#general` | `#staff-general` |

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
