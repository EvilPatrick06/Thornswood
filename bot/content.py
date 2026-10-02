# -*- coding: utf-8 -*-
"""
  Everything the build script writes into the read only channels.

  Kept apart from the building so the words can be changed without going near
  the part that creates channels, and so a second run can update the posts
  without making anything twice.
"""

import os
import re

# HOW TO GET IN IS READ OUT OF THE JOIN PAGE, NOT WRITTEN HERE A SECOND TIME.
#
# From the To Do List, entry 185: the start channel promised the old
# installer's exe and zip, "and that the Skyrim you already play will not be
# touched; the person then meets Vortex, a collection and a downgrade."
# #start-here, #welcome and #faq were written by hand for the old installer
# and the site's join page moved on without them. Not one of them said
# Vortex, Nexus or collection.
#
# So #start-here is site\data\site\join.md, and the welcome and the
# questions take what you need and what happens to your own Skyrim out of its
# "What you need" section. Change the page and the next Setup-Discord.ps1
# -Posts says the same thing. join.md rather than help.md because the site's
# pages go out from the repo with Deploy-Docs.ps1 -Site, while help.md is
# edited in the hub and a redeploy never overwrites it, so the repo copy of
# help.md is not always the one people read.
#
# The only words here are the ones the page cannot have: which channel a
# ticket goes in and where logs go, as the <#KEY> mentions Build-Discord.py
# fills in.
_JOIN = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                     '..', 'site', 'data', 'site', 'join.md')
_SITE = 'https://thornswood.net'

# Build-Discord.py packs paragraphs into messages of up to 1900 characters
# and never splits one, and it deletes the old messages before it sends. A
# paragraph past 2000 would be refused by Discord with the channel already
# half emptied, so a long one is refused here instead, when content.py
# loads and before anything is deleted. 1800 leaves room for the <#KEY>
# mentions growing into real channel ids.
LONGEST_PARAGRAPH = 1800

# THE ONE SWITCH (#428). The site's config.json "open", off unless it says
# true, and handed to this by Setup-Discord.ps1 as THORNSWOOD_OPEN, which reads
# it off https://thornswood.net/api/public so there is one copy of it. Off, the
# posts say what is true today: an alpha, open by application. On, they say
# anyone in the Discord can play, and there is no application to make.
OPEN = os.environ.get('THORNSWOOD_OPEN', '').strip().lower() in ('1', 'true', 'yes', 'open')


def for_mode(md, open_=None):
    """A page with only the wording for this mode. The same markers as
       forMode in site/server.js: <!-- alpha --> ... <!-- /alpha --> and
       <!-- open --> ... <!-- /open --> on lines of their own."""
    if open_ is None:
        open_ = OPEN
    drop = 'alpha' if open_ else 'open'
    md = md.replace('\r\n', '\n')
    md = re.sub(r'(?ms)^<!-- ' + drop + r' -->[ \t]*\n.*?^<!-- /' + drop +
                r' -->[ \t]*(?:\n|\Z)', '', md)
    return re.sub(r'(?m)^<!-- /?(?:alpha|open) -->[ \t]*(?:\n|\Z)', '', md)


def as_discord(md, where='join.md'):
    """A site page as Discord shows it. Links on the site are relative, so
       each becomes the full address, in angle brackets so Discord does not
       put a preview card of the site under every one of them. Discord has no
       horizontal rule, so a --- line would be three dashes on their own."""
    md = md.replace('\r\n', '\n')
    md = '\n'.join(line for line in md.split('\n') if line.strip() != '---')
    md = re.sub(r'\]\((/[^)\s]*)\)', lambda m: '](<' + _SITE + m.group(1) + '>)', md)
    md = re.sub(r'\n{3,}', '\n\n', md).strip()
    for para in md.split('\n\n'):
        if len(para) > LONGEST_PARAGRAPH:
            raise ValueError('%s has a paragraph of %d characters, and Discord '
                             'takes %d at most in one message: "%s..."'
                             % (where, len(para), LONGEST_PARAGRAPH, para[:60]))
    return md


def section(md, heading, where='join.md'):
    """The body under one ## heading, up to the next one."""
    m = re.search(r'^## ' + re.escape(heading) + r'[ \t]*\n(.*?)(?=^## |\Z)',
                  md, re.M | re.S)
    if not m:
        raise ValueError('%s has no "## %s" section, and the Discord text is '
                         'read out of it' % (where, heading))
    return m.group(1).strip()


with open(_JOIN, encoding='utf-8') as _f:
    JOIN = as_discord(for_mode(_f.read()))

# The page without its own "# How to join", which the channel replaces.
_JOIN_BODY = re.sub(r'\A# [^\n]*\n+', '', JOIN)

# "What you need" is four paragraphs, and the one about your own Skyrim is
# the answer to a question of its own. Picked by what it says rather than
# where it sits, and refused if it has gone, because the welcome would
# otherwise quietly lose it. bot\test-read-channels.py runs on
# every pull request, so an edit to join.md that does this goes red there.
_NEED = section(JOIN, 'What you need').split('\n\n')
_YOURS = [p for p in _NEED if 'the Skyrim you already have' in p]
if len(_YOURS) != 1:
    raise ValueError('join.md "What you need" should have one paragraph about '
                     '"the Skyrim you already have", and has %d' % len(_YOURS))
_YOURS = _YOURS[0]
_NEED = '\n\n'.join(p for p in _NEED if p != _YOURS)

_GETTING_IN_ALPHA = """\
## It's an alpha, open by application

Anyone can download it. Getting into the world is an application, and it's
short.

1. Read <#RULES>. The application asks if you accept them.
2. Open a ticket in <#TICKETS> and pick **Apply to be an alpha playtester**.
   It asks if you're 18 or over, if you accept the rules, and a few lines
   about who you want to play. Somebody reads it and gets back to you.
3. Once you're accepted you get the Playtester role, and that's what lets you
   press Play.

It's an alpha, so things break. Four people find a bug and it's fixed by the
weekend, so tell us when you find one.

## How to install

Follow <#START>. It's **https://thornswood.net/join** word for word, read out
of the same file, so the two can't disagree. You can install while you wait."""

_GETTING_IN_OPEN = """\
## It's open

Anyone can download it and anyone here can play.

1. Read <#RULES>. Being here and in the world means accepting them.
2. Follow <#START>. It's **https://thornswood.net/join** word for word, read
   out of the same file, so the two can't disagree."""

WELCOME = """\
# Thornswood

Skyrim, except everybody's in the same one.

""" + _YOURS + """

""" + (_GETTING_IN_OPEN if OPEN else _GETTING_IN_ALPHA) + """

## Everything else

It lives on the site, so it can't go stale in here.

**thornswood.net/help** installing, joining, where your logs are
**thornswood.net/known** what's broken on purpose, and why
**thornswood.net/roadmap** what's being built
**thornswood.net/credits** who made what

Say hello in <#GENERAL>.
"""

_ACCEPTING_ALPHA = """\
**Accepting them.** The application in <#TICKETS> asks whether you accept
these rules and the ones at **https://thornswood.net/rules**, and your answer is
kept against your Discord account. Applying means accepting them."""

_ACCEPTING_OPEN = """\
**Accepting them.** Being here and in the world means accepting these rules and
the ones at **https://thornswood.net/rules**."""

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

""" + (_ACCEPTING_OPEN if OPEN else _ACCEPTING_ALPHA) + "\n"

START = """\
# Getting in

This is **https://thornswood.net/join**, read out of the same file, so the two
can't disagree.""" + ("" if OPEN else " Step 1 happens in <#TICKETS>.") + """ Logs and crash files go in
<#LOGS>.

""" + _JOIN_BODY + "\n"

NEWS_FIRST = """\
Release notes land here on their own whenever an update goes out, straight from
the launcher, so this channel and the Play button can't disagree.

Same list at **https://thornswood.net/news**.
"""

# THE RULES IN THE WORLD ARE READ OUT OF THE RULES PAGE, NOT WRITTEN HERE.
#
# Issue #430: #game-rules, lore\game-rules.md and site\data\site\rules.md
# were three copies of the rules for playing, and they disagreed on the one
# people get removed over: this channel and the lore copy had a fight with
# another character agreed first, the site had it start freely. Patrick
# decided on 28 Sep that fights start freely, and that the site page is the
# only copy. So
# #game-rules is that page's "# In the World" part, to the end of the page,
# and an edit there reaches the channel with the next Setup-Discord.ps1
# -Posts. Paragraphs past LONGEST_PARAGRAPH are refused by as_discord, as
# they are for join.md.
#
# RULES above is a different document, the Discord conduct rules posted in
# #rules, and is left as it is.
_RULES_MD = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                         '..', 'site', 'data', 'site', 'rules.md')


def in_the_world(md, where='rules.md'):
    """The rules page's "# In the World" part, from under its heading to the
    next top level heading or the end of the page."""
    md = md.replace('\r\n', '\n')
    m = re.search(r'^# In the World[ \t]*\n(.*?)(?=^# |\Z)', md, re.M | re.S)
    if not m:
        raise ValueError('%s has no "# In the World" part, and #game-rules is '
                         'read out of it' % where)
    return m.group(1).strip()


with open(_RULES_MD, encoding='utf-8') as _f:
    GAME_RULES = """\
# Rules in the world

This is **https://thornswood.net/rules** from "In the World" on, read out of
the same file, so the two can't disagree. <#RULES> is the Discord half.

""" + as_discord(in_the_world(_f.read()), 'rules.md') + "\n"


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

_FAQ_IN_ALPHA = """\
**Can I bring a friend?**
Yes. Send them to the Discord. They apply the same way you did.

**Why can't I get in?**
It's an alpha, open by application. Anyone can download it, and the
Playtester role is what lets you press Play. Open a ticket in <#TICKETS>, pick
**Apply to be an alpha playtester**, and say yes to the rules. Somebody reads
it and gets back to you."""

_FAQ_IN_OPEN = """\
**Can I bring a friend?**
Yes. Send them to the Discord and they can play.

**Why can't I get in?**
Anyone here can play, so it's something else. Open a ticket in <#TICKETS> and
pick **I need help**."""

FAQ = """\
# Questions

**What do I need?**
""" + _NEED + """

**Will this mess up the Skyrim I already play?**
""" + _YOURS + """

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

""" + (_FAQ_IN_OPEN if OPEN else _FAQ_IN_ALPHA) + "\n"

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
