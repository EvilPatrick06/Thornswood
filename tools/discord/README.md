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

### Help

| Channel | What it is |
|---|---|
| `#tickets` | Cannot install, cannot connect, a problem with somebody, anything private |
| `Support` (voice) | Where a ticket goes when typing is slower than talking |
| `#applications` | Playtester, gamemaster, loremaster, content creator, dev |
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

`#game-rules` carries all ten in-world rules. `#lore` carries the setting.
`#character-introductions`, `#tales` (a forum), `#rp-appreciation` and
`#graveyard`.

### Voice

**The Bannered Mare**, **The Road**, and **AFK**.

Proximity voice is in the launcher, so these are for before, after, and
whoever is not in the world. AFK is set as the server's real AFK channel, so
Discord moves people into it after five minutes of silence rather than hoping
they remember to move themselves.

The support voice channel sits in Help, next to the tickets, because that is
what it is for.

### Testing

`#test-these` and `#test-results`, visible to Pathfinders and staff. This is
the Discord end of what the site already does at `thornswood.net/testthese`.

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
into a door, and it is also the tidiest way to hand out the hold roles without
anybody asking a moderator.

Discord will not let you finish until you have **at least 7 default channels
and at least 5 of them let everybody post**. That trips most people up, because
a server full of announcement channels fails the check.

### Default channels

The ones everybody lands in:

`#welcome` `#rules` `#start-here` `#general` `#screenshots`
`#character-introductions` `#clips` `#logs-and-crashes` `#tickets`

Nine, six of which anybody can post in, so it passes with room to spare.

### Question one: where your character is from

Set it to **pick one**, and mark it as a question everybody answers.

> **Which hold does your character call home?**
> You can change this later, and it does not stop you going anywhere.

Nine options, each granting the matching `Citizen of` role:

| Option | Grants | Worth saying |
|---|---|---|
| Whiterun | Citizen of Whiterun | The middle of everything |
| Solitude | Citizen of Solitude | Court, trade, and the embassy |
| Windhelm | Citizen of Windhelm | The High King's seat |
| Riften | Citizen of Riften | Ask no questions |
| Markarth | Citizen of Markarth | Stone, silver and old grudges |
| Dawnstar | Citizen of Dawnstar | Cold, and the ships come in |
| Morthal | Citizen of Morthal | Quiet. Too quiet |
| Falkreath | Citizen of Falkreath | More graves than people |
| Winterhold | Winterhold | What is left of it |

Nobody has to be from anywhere yet, so an "I have not decided" option granting
nothing is worth adding as a tenth.

### Question two: what you are here for

Set it to **pick as many as you like**, and optional.

> **What are you here for?**

| Option | Shows them |
|---|---|
| Roleplay | `#character-introductions`, `#tales` |
| Just playing | `#general`, your hold's channel |
| I want to help test | `#bugs`, `#tickets` |
| I make videos | `#clips`, `#screenshots` |

None of these grant a role. Playtester, Loremaster and Content Creator are
given out by a person, because each one is somebody being trusted with
something rather than somebody clicking a button.

### What onboarding cannot do

It cannot hand out `Member`. That is the default role setting in Server
Settings, Roles, and it has to be on or somebody who answered the questions
still cannot get into the game.
