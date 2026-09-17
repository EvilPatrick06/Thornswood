# -*- coding: utf-8 -*-
"""
  Everything the build script writes into the read only channels.

  Kept apart from the building so the words can be changed without going near
  the part that creates channels, and so a second run can update the posts
  without making anything twice.
"""

WELCOME = """\
# Thornswood

Skyrim, except everybody's in the same one.

It doesn't touch the Skyrim you already have. It installs its own copy, its own
mods, its own launcher, off to one side, and leaves yours alone.

## We're playtesting

Not open to everyone yet.

Open a ticket in <#TICKETS>. Say who you are and what you're after. A few lines
is fine, somebody will get back to you.

We're letting people in slowly on purpose. Four people find a bug and it's
fixed by the weekend. Two hundred people find it and that's a bad week and a
first impression nobody comes back from.

Not in yet isn't the same as turned away. Stick around, you'll get asked.

## Once you're in

1. Read <#RULES>.
2. Grab both installer files from **https://thornswood.net/downloads**
3. Open Thornswood from the desktop shortcut. Not Steam, not SKSE. It patches
   itself and drops you into the world.

## Everything else

It lives on the site, so it can't go stale in here.

**thornswood.net/help** installing, joining, where your logs are
**thornswood.net/known** what's broken on purpose, and why
**thornswood.net/roadmap** what's being built
**thornswood.net/credits** who made what

Say hello in <#GENERAL>.
"""

RULES = """\
# Rules

Seven, because nobody reads twenty.

**1. Don't be a dick.**
No harassment, no slurs, no bigotry, no going after somebody personally. Argue
about the game as much as you like.

**2. Keep it appropriate.**
Nothing sexual involving minors, ever. Nothing graphic in the public channels.
Adult scenes between people who agreed to them beforehand are fine in private.
The full version of that is at **https://thornswood.net/rules**.

**3. Don't wreck somebody else's game.**
No cheating, no exploiting the server, no griefing. If you find something that
lets you break the world, tell us instead of using it. You'll get thanked.

**4. Don't pass the installer around.**
Send people here instead.

**5. Push to talk.**
An open mic with a fan behind it ruins voice for everyone in the room.

**6. Bugs in <#BUGS>, ideas in <#SUGGESTIONS>.**
They get lost in general. That's not a rule so much as a favour to yourself.

**7. If a Moderator or a Gamemaster tells you to stop, stop.**
You can argue about it afterwards.

You get a word, then a mute, then a removal, depending on what it was. Two and
three skip to the end when they're bad enough.
"""

START = """\
# Getting in

**We're playtesting.** Before anything below, open a ticket in <#TICKETS> and
say hello. A few lines about who you are. Somebody will answer.

The rest of this is for once you're in.

## 1. Two files, same folder

From **https://thornswood.net/downloads**. There's a small **exe** and a large
**zip**, and they have to sit next to each other because the exe reads the zip.
Downloads folder is fine.

Run the exe. Don't unzip anything yourself.

First run copies about twenty gigabytes into place. Start it and go do
something else.

## 2. Open Thornswood

The desktop shortcut. Not Skyrim, not Steam, not SKSE.

It checks for updates, patches whatever moved, and the Play button puts you in.
No address to type, no password to remember.

If an update's waiting it takes that first. Everyone has to be on the same
files or nobody connects.

## Voice

Runs in the launcher, not the game, so leave the launcher open. Push to talk.
Whisper and yell change how far you carry.

## When it breaks

Check **https://thornswood.net/known** first, a lot of it is on that list.

Still stuck? Ticket in <#TICKETS>, and bring:

- what you were doing
- what actually happened
- the crash log, if it closed itself:

```
C:\\Thornswood\\Profile\\SKSE\\CrashLogger\\
```

- or the launcher's own log, if it never got that far:

```
C:\\Thornswood\\Profile\\launcher.log
```

Drag either straight into the channel. They're plain text and they're usually
the difference between a fix and a guess.
"""

NEWS_FIRST = """\
Release notes land here on their own whenever an update goes out, straight from
the launcher, so this channel and the Play button can't disagree.

Same list at **https://thornswood.net/news**.
"""

GAME_RULES = """\
# Rules in the world

<#RULES> is about how we treat each other. This is about playing.

We're looser than the big roleplay servers on purpose. No character sheet to
get approved, no lore exam, nobody blessing your backstory. What you do need is
to not ruin somebody else's evening.

**1. Your character knows what your character knows.**
You read here that somebody got robbed on the road. Your character didn't. The
fun half of this rule: **ask**. "Has word got round about the road?" gets you
an answer in character, and now it's real.

**2. You don't decide what happens to other people.**
Write what you try, not what you land. Swinging at his shoulder leaves him a
choice. Burying the axe in it doesn't.

**3. Nobody dies without agreeing to it.**
Beaten, robbed, broken, left in a ditch, all fine. Death isn't. Say it out of
character first and make sure everyone actually wants it. A death somebody
agreed to is the best thing that happens on a server like this.

**4. Ask before you draw on someone.**
Go get killed by a draugr all you like. Fighting another character takes one
line out of character first. Nobody has ever been annoyed by being asked.

**5. Rob people, don't loot them.**
Pick the lock, lift the key, talk your way in, all fair. Don't empty someone's
house because you caught it open while they were offline. Take a good thing,
leave a trace, and give them a story to come back to.

**6. Play a person, not a legend.**
You can be remarkable. You can't be the Dragonborn, the Listener, the Archmage,
the Harbinger, or the last of anything.

**7. Titles are given, or taken properly.**
Jarl, steward, housecarl, thane, captain, priest of a named temple. Most of them
are sitting empty, and how one comes free is something you find out in
character.

Claiming an empty one is fine within reason. Nobody will stop you calling
yourself captain of a guard nobody else has claimed. High King is not within
reason.

Want one somebody already holds? Take it. Scheme, challenge them, put a knife
somewhere useful. But take it **in the world, with them in it**. Announcing
you're the Jarl of Riften now while the Jarl of Riften is asleep isn't taking
it, it's editing your own name.

**8. Use `/ooc` for out of character talk.**
`/ooc brb, dog`. It only reaches people near you and it comes out in brackets,
so nobody has to guess whether your character said it.

**9. If you wouldn't enjoy being on the other end of it, don't.**
The other eight are made out of this one.

**10. `/ooc can we not` ends anything.**
Immediately, no explanation owed, no argument. Ignore that and you're done
here. It's the only rule with no second chance.

The full thing, including what we're deliberately relaxed about, is at
**https://thornswood.net/rules**
"""

LORE = """\
# Where you are

**Fourth Era, 252.** Fifty years since the war.

The Stormcloaks won it. The Legion marched out in the first thaw of 203 and the
Moot put the crown on Ulfric. He wore it twenty-six years and died in bed,
which surprised him as much as anyone.

The Moot sat eleven days and didn't pick his kin. It picked **Eirik
Ravensgard** of the Rift, who's had it twenty-two years and is neither loved
nor hated. In Skyrim that's a long reign.

There's a High King of Skyrim and nothing above him. Every hold keeps its own
Jarl, its own court, and its own opinion of everyone else's.

## The Thalmor

Thrown out in 209. Illegal ever since. Still here.

The ones who never made the border went to ground, and their grandchildren are
running gold and poison through the holds under other names. No orders from
home, no cause left, nobody to answer to. That's what makes them dangerous.

## The Empire

Came back in 221 the way empires do when they can't come back with soldiers.
With a ledger.

The White Harbour Accord traded grain for ore and got them one embassy in
Solitude and nothing else. The staff there are polite to a degree that fools
nobody.

## What you can play

A Nord out of any hold. An Imperial, legal and watched. A Thalmor remnant,
hunted by everyone including the Empire. A Jarl, a steward, a housecarl, a
guard, a priest, a smith, a hunter.

Not the Dragonborn. Not the Listener. Not the last of anything. Those belong to
the world.

## The rest

Full history and all nine articles of the Accord at
**https://thornswood.net/world**.

Article Four is the one people argue about in taverns: an Imperial standing on
Skyrim's soil is under Skyrim's law, a Nord standing in the embassy is under
the Empire's, and neither side can reach in and drag somebody out.
"""

FAQ = """\
# Questions

**Do I need to own Skyrim?**
Yes. Special Edition, on Steam. Not Anniversary. If you have it, fine, it just
isn't used.

**Will this mess up the Skyrim I already play?**
No. It installs somewhere else entirely and never touches yours.

**Can I add mods?**
No. Everyone has to be running the identical plugin list or nobody connects.
Want something in? Say so in <#SUGGESTIONS>. It goes in for everybody or not at
all.

**Why can't I save?**
Your character lives on the server, so quit whenever you like, nothing is lost.
The annoying part is that mod settings menus reset every session. There's no
save file for them to write to.

**Why is that NPC just standing there?**
You're not close enough. Whoever is nearest is the one running them. Nobody
nearby, nobody home.

**We fought the same bandit and he did completely different things.**
Yep. Hosting swaps every couple of seconds, so whoever had him at that moment
decided what he did. It's the price of the world being shared.

**Fast travel?**
Off. So is levelling. Difficulty is locked.
**https://thornswood.net/known** says why, for all three.

**Something's broken.**
Check **https://thornswood.net/known** first. A lot of it is on that list and a
lot of that is on purpose. If it isn't there, <#BUGS>.

**Can I bring a friend?**
Ask. We're small, we're still building, and we're letting people in slowly.

**Why can't I get in?**
Closed playtest. Open a ticket in <#TICKETS> and say hello.
"""

LINKS = """\
# Links

**The site** https://thornswood.net
Everything in one place: the installer, help, what is broken, what is coming.

**Install help** https://thornswood.net/help
**What is broken on purpose** https://thornswood.net/known
**What is coming** https://thornswood.net/roadmap
**Report something** https://thornswood.net/report
**Send a screenshot or a log** https://thornswood.net/uploads

## Built on

**SkyMP** the multiplayer engine this runs on. Skyrim was not built to be
played together and SkyMP is what makes it possible at all.

**SKSE** and **Skyrim Platform**, which everything else stands on.

The mod list is long and every author on it made this worth playing. Their
pages are in the launcher, one click each.
"""

NEWS_FIRST = """\
Release notes land here on their own every time an update goes out, straight
from the launcher, so this channel and the Play button never disagree.

The same list, with the file changes, is at **https://thornswood.net/news**.
"""

BUGS_TOPIC = "One post per problem. Logs and screenshots welcome."
SUGGEST_TOPIC = ("Mods and features you want. Nexus link if it's a mod, "
                 "because whether it works here depends on how it's built.")

HOLD_TOPICS = {
    'whiterun':   "Everybody passes through eventually.",
    'solitude':   "Court, trade, and the one Imperial embassy left in Skyrim.",
    'windhelm':   "The High King sits here. Dress warm.",
    'riften':     "Ask no questions.",
    'markarth':   "Stone, silver, and grudges older than the war.",
    'dawnstar':   "Cold. The ships still come in.",
    'morthal':    "Quiet. Too quiet, most would say.",
    'falkreath':  "More graves than people. Always has been.",
    'winterhold': "What's left of it.",
}
