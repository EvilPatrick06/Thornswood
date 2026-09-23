"""
The Thornswood bot. This one stays running, unlike Build-Discord.py which sets
the server up once and exits.

What it does:

  Joins    draws a card and puts it in #welcome
  Tickets  a panel in #tickets, one private thread per ticket, and a copy
           pushed to the site so the inbox has it whether or not anybody was
           looking at Discord
  Watch    asks the site every five minutes over its public name, and says so
           in #dev when it stops answering and when it comes back

Everything it needs is in env:

  DISCORD_TOKEN    the bot token
  THORNSWOOD_SITE  https://thornswood.net
  THORNSWOOD_KEY   shared secret the site checks on /api/ticket
  JOIN_CHANNEL     name of the channel join cards go in, default general
  TICKET_CHANNEL   public channel the panel lives in, comma separated, first wins
  TICKET_LOG       staff only channel closed tickets are recorded in
  STAFF_ROLES      comma separated, who gets pulled into every ticket thread
  CREATOR_ROLES    comma separated, added to Apply: Content Creator only
  WATCH_CHANNEL_ID id of the staff channel the site watcher speaks in,
                   default whatever dev-channel.txt beside this file holds
  WATCH_EVERY      seconds between checks, default 300
  WATCH_MISSES     how many in a row before it says so, default 2

It is written to keep going when a piece of it fails. A card that will not
draw still gets a greeting, a site that is down still gets a thread, and a
thread that cannot be made still gets an answer to the person who asked.
"""
import asyncio
import json
import os
import re
import ssl
import traceback
import typing
import urllib.request

# Windows Server ships with an empty root certificate store and the automatic
# update for it switched off, so Python cannot verify discord.com and the
# handshake dies with "unable to get local issuer certificate". Install-Bot
# normally sets SSL_CERT_FILE for us; this is the belt to that braces, so a bot
# copied somewhere by hand still connects.
if not os.environ.get('SSL_CERT_FILE'):
    try:
        import certifi
        os.environ['SSL_CERT_FILE'] = certifi.where()
        os.environ.setdefault('REQUESTS_CA_BUNDLE', certifi.where())
        ssl.create_default_context()      # picked up on the next context made
    except Exception:
        pass

import discord

import card

TOKEN = os.environ.get('DISCORD_TOKEN', '').strip()
SITE = os.environ.get('THORNSWOOD_SITE', 'https://thornswood.net').rstrip('/')
KEY = os.environ.get('THORNSWOOD_KEY', '').strip()
# Joins go where people actually are, not into the read-only welcome page.
# Change JOIN_CHANNEL in bot.env.json on the VPS to move it.
WELCOME = os.environ.get('JOIN_CHANNEL',
          os.environ.get('WELCOME_CHANNEL', 'general')).strip().lower()
# Names the ticket panel will answer to, in order, first one that exists wins.
#
# This was a single name, and the single name was 'tickets'. The channel was
# then renamed to #tickets-and-applications, which moved nothing and broke
# everything: the panel message stayed where it was and still worked, so the
# server looked fine, while the bot could no longer find the channel. Every
# ticket after the rename had nowhere to open a thread and nowhere to fall back
# to. A list costs nothing and a rename stops mattering.
TICKETS = [n.strip().lower() for n in
           os.environ.get('TICKET_CHANNEL',
                          'tickets-and-applications,applications').split(',')
           if n.strip()]
TICKETS_SAID = ' or #'.join(TICKETS)

# Where a closed ticket is written down, and it is NOT the channel above.
# Everybody who can apply can read that one, so a closed application posted
# there is somebody else's answers sitting in front of the next person
# queueing up, and it buries the panel besides. Staff only, and made if it is
# not there.
TICKET_LOG = [n.strip().lower() for n in
              os.environ.get('TICKET_LOG', 'tickets,ticket-log').split(',')
              if n.strip()]
# Who gets pulled into every ticket thread.
STAFF = [r.strip().lower() for r in
         os.environ.get('STAFF_ROLES', 'Owner,Gamemaster,Dev,Loremaster,Moderator').split(',')
         if r.strip()]

# Roles that see one kind of ticket and not the rest.
#
# Content Creator is not general staff: that role is for social media, and it
# has no reason to be reading somebody's playtest application or a report about
# another person. It does have every reason to read applications to join it,
# so it is added to those threads and no others.
CREATOR = [r.strip().lower() for r in
           os.environ.get('CREATOR_ROLES', 'Content Creator').split(',')
           if r.strip()]
EXTRA_STAFF = {'creator': CREATOR}

# Where the site watcher speaks. Staff, not public: an outage is something to
# fix, not an announcement.
#
# BY ID AND NOT BY NAME, and the reason is the whole point. The staff channel
# is called news and sits in the Staff category. There is also a public news,
# made by Build-Discord.py:154, which is the one releases are announced in. Two
# channels, one name, and by_name hands back whichever the server lists first,
# so a watcher matching on 'news' would eventually tell everybody the site was
# down. A first draft guessed at 'dev-notes' and then 'dev', neither of which
# exists at all, and would have fallen through to whatever did.
#
# dev-channel.txt holds that id, sits beside this file and is tracked in git,
# unlike the webhook files next to it, so the id is not a secret and does not
# need putting anywhere new.
def _dev_channel_id():
    """The staff channel's id, from the file that already records it."""
    here = os.path.dirname(os.path.abspath(__file__))
    try:
        with open(os.path.join(here, 'dev-channel.txt')) as f:
            return int(f.read().strip())
    except Exception:
        return 0


def _int_env(name, fallback):
    """A number from env, and the default when it is missing or nonsense."""
    try:
        n = int(os.environ.get(name, '') or fallback)
        return n if n > 0 else fallback
    except ValueError:
        return fallback


WATCH_ID = _int_env('WATCH_CHANNEL_ID', _dev_channel_id())


# The channel that hears about a session that went wrong.
#
# staff-channel.txt beside this file, the same shape and for the same reason as
# dev-channel.txt: an id rather than a name, because a name lookup hands back
# whichever channel the server lists first and this server already has two
# called news.
#
# With no file it falls back to the watcher's channel, which is a real staff
# channel that already works, rather than guessing at a name or going quiet.
# TROUBLE_CHANNEL_ID in bot.env.json on the VPS overrides both.
def _staff_channel_id():
    here = os.path.dirname(os.path.abspath(__file__))
    try:
        with open(os.path.join(here, 'staff-channel.txt')) as f:
            return int(f.read().strip())
    except Exception:
        return 0


# No fallback to the watcher's channel here, and that is the whole point.
#
# It used to read `_staff_channel_id() or _dev_channel_id()`, so with no
# staff-channel.txt it took the watcher's id and never reached the name lookup
# below. The first deploy on 22 September logged "speaking in #news", which is
# the staff news channel: right kind of place, wrong place, and it would have
# put every crash report in with the release announcements.
#
# 0 when there is no file, so _trouble_channel falls through to looking
# staff-general up by name, which is what was wanted.
TROUBLE_ID = _int_env('TROUBLE_CHANNEL_ID', _staff_channel_id())

# Where the site writes the sessions that went wrong. The bot and the site run
# on the same box, so this is a file rather than a request: no ticket, no port
# and nothing to keep in step.
TROUBLE_FILE = os.environ.get(
    'TROUBLE_FILE', r'C:\Thornswood-Docs\data\trouble.json')
TROUBLE_EVERY = _int_env('TROUBLE_EVERY', 120)


WATCH_EVERY = _int_env('WATCH_EVERY', 300)
# Two in a row rather than one. A single timeout is a moment of packet loss and
# nobody wants to read about it. Two, five minutes apart, is the site being
# down. Caddy's own repeating trigger is five minutes as well, so anything that
# clears by itself has had a go at clearing before this says a word.
WATCH_MISSES = _int_env('WATCH_MISSES', 2)

if not TOKEN:
    raise SystemExit('No DISCORD_TOKEN. Install-Bot.ps1 sets it.')

intents = discord.Intents(guilds=True, members=True)


class Thornswood(discord.Client):
    async def setup_hook(self):
        """
        Everything that has to happen once per process, and not once per
        reconnect.

        discord.py runs this inside login(), before the gateway is connected
        and before any event is dispatched. on_ready is the other thing, and
        it is not the same thing: it fires again every time the connection
        drops and comes back, which on a bad evening is repeatedly.

        A persistent view is registered against its custom_id so a button on
        a message from last week still works after a restart. Registering it
        a second time is not free and is not meaningful, and the two lines
        were sitting in on_ready where every reconnect did it again.
        """
        self.add_view(TicketPanel())          # so it keeps working after a restart
        self.add_view(TicketTools())          # and so does Close on every old ticket


client = Thornswood(intents=intents)
tree = discord.app_commands.CommandTree(client)


def log(*a):
    print('[thornswood-bot]', *a, flush=True)


# ------------------------------------------------------------------ site --
def push(kind, title, detail, by, discord_id):
    """Send a ticket to the site. Runs off the event loop, and a failure here
       is never allowed to lose the ticket: the thread in Discord is the
       record, this is the convenience."""
    if not KEY:
        # Silent for as long as this has existed, which means a bot with no key
        # set looked exactly like a working one: the thread appeared, the site
        # inbox stayed empty, and nothing anywhere said why.
        log('THORNSWOOD_KEY is not set, so this ticket did NOT reach the site '
            'inbox. The thread in Discord is the only copy. Install-Bot.ps1 '
            'sets the key in bot.env.json on the VPS.')
        return
    body = json.dumps({
        'key': KEY, 'kind': kind, 'title': title,
        'detail': detail, 'by': by, 'discordId': str(discord_id)
    }).encode()
    req = urllib.request.Request(
        SITE + '/api/ticket', data=body,
        headers={'Content-Type': 'application/json'}, method='POST')
    try:
        with urllib.request.urlopen(req, timeout=12) as r:
            r.read()
    except Exception as e:
        log('site push failed:', e)


async def push_async(*a):
    try:
        await asyncio.get_running_loop().run_in_executor(None, push, *a)
    except Exception as e:
        log('site push failed:', e)


def by_name(guild, names, kind='text'):
    """
    Find a channel by name.

    guild.channels holds categories and voice rooms as well as text channels.
    A server with a category called General sitting above a text channel called
    general hands back the category, which has no send method, and the only
    sign of it is a traceback in this log and nothing at all in Discord. So
    only ever look in the list that can actually be posted in.
    """
    pool = guild.voice_channels if kind == 'voice' else guild.text_channels
    # In the order given, not the order the server happens to list its
    # channels in. With a public #tickets-and-applications and a staff only
    # #tickets both in the server, taking whichever came first down the
    # sidebar would have put the application panel in the staff channel.
    for want in names:
        for ch in pool:
            if ch.name.lower() == want:
                return ch
    return None


async def log_channel(guild, make=True):
    """
    The staff only channel closed tickets are recorded in.

    Made rather than asked for, because the alternative is a feature that
    silently does nothing until somebody thinks to read a log. Deny first:
    @everyone cannot see it and only the staff roles are added back. Content
    Creator is left out on purpose, the same reason it is left out of every
    ticket that is not an application to join it.
    """
    ch = by_name(guild, TICKET_LOG)
    if ch is not None or not make:
        return ch

    if not guild.me.guild_permissions.manage_channels:
        log('there is no #%s to record closed tickets in, and the bot cannot '
            'make one because it does not have Manage Channels. Either give '
            'it that, or make the channel by hand with staff the only ones '
            'who can see it.' % TICKET_LOG[0])
        return None

    try:
        over = {
            guild.default_role: discord.PermissionOverwrite(view_channel=False),
            guild.me: discord.PermissionOverwrite(view_channel=True,
                                                  send_messages=True),
        }
        for r in guild.roles:
            if r.name.lower() in set(STAFF):
                over[r] = discord.PermissionOverwrite(view_channel=True,
                                                      send_messages=True)
        where = by_name(guild, TICKETS)
        ch = await guild.create_text_channel(
            TICKET_LOG[0],
            overwrites=over,
            category=(where.category if where is not None else None),
            topic='Every ticket that gets closed, with a link back to it. Staff only.')
        log('made #%s for closed tickets, staff only' % ch.name)
        return ch
    except Exception:
        log('could not make #%s:\n' % TICKET_LOG[0] + traceback.format_exc())
        return None


def thread_block(guild, ch):
    """
    Why a private thread cannot be opened in this channel, in words, or None.

    Discord answers every one of these with the same 50013 Forbidden, and the
    only place it lands is a traceback in a log on the VPS. Sending a message
    and opening a thread are separate permissions, so a bot that posted the
    panel perfectly well can still be unable to open a single ticket, and the
    symptom is an apology to the person applying and nothing anywhere else.
    Naming it here is the difference between a five minute fix and an evening.
    """
    try:
        p = ch.permissions_for(guild.me)
    except Exception:
        return None
    missing = [n for n, ok in (
        ('View Channel',             getattr(p, 'view_channel', True)),
        ('Send Messages',            getattr(p, 'send_messages', True)),
        ('Create Private Threads',   getattr(p, 'create_private_threads', True)),
        ('Send Messages in Threads', getattr(p, 'send_messages_in_threads', True)),
    ) if not ok]
    if not missing:
        return None
    return ('the bot does not have ' + ', '.join(missing) + ' in #' + ch.name)


# ----------------------------------------------------------------- joins --
@client.event
async def on_member_join(member):
    # First line in, before anything can go wrong, so the log can tell a join
    # that never reached the bot apart from one that reached it and failed.
    log('join: %s arrived in "%s"' % (member, member.guild.name))

    ch = by_name(member.guild, [WELCOME])
    if ch is None:
        log('no text channel called #%s to greet in' % WELCOME)
        return

    number = member.guild.member_count
    name = member.display_name or member.name

    png = None
    try:
        avatar = member.display_avatar.replace(size=256, format='png')
        data = await avatar.read()
        png = await asyncio.get_running_loop().run_in_executor(
            None, card.render, name, data, number, None, member.name)
    except Exception:
        log('card failed:\n' + traceback.format_exc())

    line = '%s came up the road.' % member.mention
    try:
        if png is not None:
            await ch.send(line, file=discord.File(png, 'welcome.png'))
        else:
            await ch.send(line)
    except Exception:
        log('greeting failed:\n' + traceback.format_exc())


# --------------------------------------------------------------- tickets --
# 'Apply to play' is not here on purpose. Everybody in the world right now is
# a playtester, so that is the one application to be in it, and when the doors
# open there will be no application to play at all. Leaving both up asked
# people to guess which one they wanted and half of them guessed wrong.
KINDS = [
    ('playtest',    'Apply to playtest',    'How you get in. Break it on purpose and write down how.'),
    ('jarl',        'Apply: Jarl',          'A seat in a hold. In character, and the first ones come out of these.'),
    ('gamemaster',  'Apply: Gamemaster',    'Run events, settle disputes, hold the line in character.'),
    ('loremaster',  'Apply: Loremaster',    'Keep the history straight and write the rest of it.'),
    ('moderator',   'Apply: Moderator',     'The unglamorous one. Tickets, reports, difficult people.'),
    ('dev',         'Apply: Dev',           'Server, launcher, site, mods. Anything that compiles.'),
    ('creator',     'Apply: Content Creator', 'Video, streams, screenshots, writing about the place.'),
    ('report',      'Report somebody',      'Something happened and it should not have.'),
    ('help',        'I need help',          'It will not install, will not start, or will not connect.'),
]

# The role each application is asking for, so the thread and the site inbox say
# what it is without anybody reading three answers first. None of these grant
# anything: giving out the role is still a person deciding.
ROLE_FOR = {
    'playtest':   'Playtester',
    'jarl':       'Jarl of the hold named below',
    'gamemaster': 'Gamemaster',
    'loremaster': 'Loremaster',
    'moderator':  'Moderator',
    'dev':        'Dev',
    'creator':    'Content Creator',
}

# Every job asks the same three things, because the answers that matter are the
# same three every time: what you have done, how much time you really have, and
# whether you want the job or the title.
def _job(what, examples):
    return [
        ('What experience do you have?',
         examples, True),
        ('How much time can you give it?',
         'Hours a week, and which days. Honest beats keen.', True),
        ('Why this role?',
         'What draws you to ' + what + ' rather than the rest.', True),
    ]

# Asked first, on the two tickets that are a way IN. Everything else on the
# panel is for somebody already here, who answered this to get here.
#
# It is a typed answer rather than a box to tick because Discord modals have no
# box to tick. What it is worth is the record: their own words, against their
# Discord id, at a time, kept in the thread and in the site inbox.
AGE_Q = ('Are you 18 or over?', 'Thornswood is an adult server. Yes or no.', False)
AGE_KINDS = ('playtest',)

_NO  = ('no', 'nope', 'nah', 'not ', 'under', 'minor')
_YES = ('yes', 'yep', 'yeah', 'yup', 'y ', 'ye', 'i am', 'im ', "i'm ", 'sure',
        'correct', 'of course', 'affirmative', 'over', 'above')


def said_yes(text):
    """
    Whether an answer to the age question reads as a yes.

    Generous on purpose, and it never rejects anything by itself. Somebody
    typing "27" or "im 34" has answered the question; somebody typing "no", or
    nothing at all, is the case this exists to catch. A guess about how a
    stranger types is not a good enough reason to throw an application away,
    so the worst this does is put a line at the top of the thread and leave it
    to a person.
    """
    t = (text or '').strip().lower()
    if not t:
        return False

    # A NUMBER BEATS A WORD, and this order is the whole fix.
    #
    # It used to check the yes words first, and "I'm 16" starts with "i'm ",
    # which is in that list. So a sixteen year old answering in a sentence
    # read as a yes and the thread was never flagged, which is the one answer
    # this function exists to catch.
    #
    # An age is 1 to 120. Anything bigger is a year, a postcode or a number of
    # hours, and treating "born in 2009" as an age of 2009 would be a yes for
    # the same person. A text with no age-like number in it falls through to
    # the words below exactly as before.
    #
    # ANY NUMBER UNDER EIGHTEEN IS A NO, even beside a bigger one. "my brother
    # is 30, im 16" is not an answer anybody should be reading as a yes, and
    # this function never rejects anybody by itself: a no here puts a line at
    # the top of the thread for a person to read.
    #
    # It costs the occasional honest answer a flag: "34 and have been for 2
    # years" reads as a no because of the 2. That is deliberate and is the
    # cheap direction to be wrong in. A flag costs somebody five seconds of
    # reading; a miss lets a minor through with nothing saying so.
    ages = []
    for n in re.findall(r'\d+', t):
        try:
            v = int(n)
        except Exception:
            continue
        if 1 <= v <= 120:
            ages.append(v)
    if ages:
        if min(ages) < 18:
            return False
        return True

    if t == 'n' or t.startswith(_NO):
        return False
    if t.startswith(_YES):
        return True
    return False


QUESTIONS = {
    # The one application to be in the world. It asks about the character,
    # because that is what somebody is here for, and about testing, because
    # that is what being in it means today. It does not ask who they are
    # outside the game: that is answered by them being in the Discord.
    'playtest': [
        AGE_Q,
        ('Have you roleplayed before, and where?', 'No is a perfectly good answer.', True),
        ('Who do you want to play?', 'A sentence about the character, not a biography.', True),
        ('How much time can you give it?', 'Hours a week, and which days.', True),
        ('Describe a bug you have run into', 'What you did, what happened, what should have happened. Short.', True),
    ],
    # The only application here that is answered in character. The seats are
    # empty and the first people to hold them are picked out of these, so the
    # questions ask about the character rather than about the person, and the
    # last one asks the thing that actually decides it: whether they can lose
    # the seat and keep playing.
    'jarl': [
        ('Which hold? Second choice if you have one',
         'Whiterun, Solitude, Windhelm, Riften, Markarth, Dawnstar, Morthal, Falkreath, Winterhold.', False),
        ('Who is your character?',
         'Name, where they come from, what they have been doing until now. In character.', True),
        ('What is their claim to the seat?',
         'Blood, a war record, coin, or being the one who stayed. Something a hold would accept.', True),
        ('What would they change in the hold?',
         'What they actually do with it. Answer as them, not as you.', True),
        ('What happens if they lose the seat?',
         'A seat that cannot be lost is not a seat. Say how you play that.', True),
    ],
    'gamemaster': _job('running events',
        'Events you have run, groups you have led, tables you have DMed.'),
    'loremaster': _job('the lore',
        'Worldbuilding, wikis, writing, anything you have kept consistent over time.'),
    'moderator': _job('moderating',
        'Servers or forums you have moderated, and roughly how big.'),
    'dev': _job('the code',
        'Languages, projects, a repo link. Papyrus and C# are the useful ones here.'),
    'creator': _job('making things about Thornswood',
        'Channel, streams, a portfolio, anything you have put out.'),
    'report': [
        ('Who, and where?', 'Name and the channel or the place in the world.', False),
        ('What happened?', 'What they did, what you did, and roughly when.', True),
        ('Anything we can look at?', 'Screenshots, a clip, a time to check the log against.', True),
    ],
    'help': [
        ('What is going wrong?', 'One line.', False),
        ('What were you doing when it broke?', 'Installing, launching, connecting, playing.', True),
        ('What did it say, if anything?', 'Paste the error.', True),
    ],
}


class TicketModal(discord.ui.Modal):
    def __init__(self, kind, label):
        super().__init__(title=label[:45])
        self.kind = kind
        self.label_text = label
        self.fields = []
        for q, ph, long in QUESTIONS[kind]:
            item = discord.ui.TextInput(
                label=q[:45],
                placeholder=ph[:100],
                style=discord.TextStyle.paragraph if long else discord.TextStyle.short,
                required=not long,
                max_length=1000 if long else 200)
            self.fields.append(item)
            self.add_item(item)

    async def on_submit(self, interaction):
        await interaction.response.defer(ephemeral=True, thinking=True)
        guild = interaction.guild
        who = interaction.user

        lines = []
        for item, (q, _, _) in zip(self.fields, QUESTIONS[self.kind]):
            lines.append('**%s**\n%s' % (q, (item.value or '').strip() or 'nothing said'))
        detail = '\n\n'.join(lines)

        asking = ROLE_FOR.get(self.kind)
        if asking:
            detail = '**Asking for:** ' + asking + '\n\n' + detail

        # Anything that does not read as a yes says so at the top, in words, on
        # the line staff read first. It never stops the ticket: losing somebody's
        # application over how they phrased one answer would be worse than a
        # person spending two seconds reading it.
        if self.kind in AGE_KINDS:
            gave = ''
            for item, (q, _, _) in zip(self.fields, QUESTIONS[self.kind]):
                if q == AGE_Q[0]:
                    gave = (item.value or '').strip()
                    break
            if not said_yes(gave):
                detail = ('**CHECK THIS ONE.** Asked if they are 18 or over they '
                          'said "%s".\n\n' % (gave or 'nothing')) + detail

        title = ('%s, %s' % (self.label_text, who.display_name))[:96]

        # Mentioning a role does not put anybody in a private thread. Only
        # people who have been added to one can see it, so a ticket opened
        # without this was visible to the applicant and to nobody else, and the
        # @mention went into a room staff were not in. They are added one at a
        # time, which is the only way Discord offers.
        want = set(STAFF) | set(EXTRA_STAFF.get(self.kind, []))
        staff_roles = [r for r in guild.roles if r.name.lower() in want]
        if not staff_roles:
            log('no role matched %r, so nobody will be pulled into this ticket. '
                'Set STAFF_ROLES in bot.env.json to the role names this server '
                'actually uses.' % (sorted(want),))
        head = '%s opened this. %s' % (who.mention,
                                       ' '.join(r.mention for r in staff_roles))

        ch = by_name(guild, TICKETS)
        why = None
        opened = None
        posted = False

        if ch is None:
            why = ('there is no text channel called #%s in this server' % TICKETS_SAID)
            log(why)
        else:
            why = thread_block(guild, ch)
            if why:
                log('no ticket thread: %s' % why)
            else:
                try:
                    opened = await ch.create_thread(
                        name=title,
                        type=discord.ChannelType.private_thread,
                        invitable=False,
                        auto_archive_duration=10080)
                except Exception as e:
                    why = 'Discord refused to open the thread (%s)' % e
                    log('the ticket thread could not be created:\n'
                        + traceback.format_exc())
                    opened = None

        # From here the thread exists. Everything after it is allowed to fail
        # on its own without throwing the thread away, which is what used to
        # happen: one member who could not be added took the whole ticket down
        # and left an empty thread nobody was in.
        if opened is not None:
            try:
                await opened.add_user(who)
            except Exception as e:
                log('could not add %s to their own ticket: %s' % (who, e))

            added = 0
            seen = set()
            for r in staff_roles:
                for m in r.members:
                    if m.id == who.id or m.id in seen or m.bot:
                        continue
                    seen.add(m.id)
                    try:
                        await opened.add_user(m)
                        added += 1
                    except Exception as e:
                        log('could not add %s to the ticket thread: %s' % (m, e))

            if staff_roles and added == 0:
                log('staff roles %r matched but nobody was added to the ticket '
                    'thread. If those roles have members, the bot is missing '
                    'permissions in #%s.'
                    % ([r.name for r in staff_roles], ch.name))

            try:
                await opened.send(head[:1900], view=TicketTools())
                for chunk in _chunks(detail, 1900):
                    await opened.send(chunk)
                posted = True
            except Exception as e:
                why = 'the thread opened but nothing could be written in it (%s)' % e
                log('writing the ticket into the thread failed:\n'
                    + traceback.format_exc())

        # A ticket nobody can see is the same as no ticket. If the thread could
        # not be made, or could not be written in, the whole application goes
        # into the tickets channel as an ordinary message instead. That channel
        # is already the one the panel lives in, so it is no more public than
        # the thread would have been, and it means an application is never lost
        # to one permission somebody forgot to tick. The reason rides along
        # with it, so whoever reads it can fix the cause without going to the
        # VPS for a log.
        fell_back = False
        if not posted and ch is not None:
            note = ''
            if why:
                note = '\n_No private thread for this one: %s._' % why
            try:
                await ch.send(('**%s**\n%s%s' % (title, head, note))[:1900])
                for chunk in _chunks(detail, 1900):
                    await ch.send(chunk)
                fell_back = True
            except Exception:
                log('the ticket could not be posted in #%s either:\n'
                    % ch.name + traceback.format_exc())

        # And whatever happened in Discord, the person gets told something
        # true. The old wording promised a message that nothing ever sent.
        if not posted and not fell_back:
            try:
                await who.send(
                    'Your ticket reached staff, but Discord would not let the '
                    'bot open a thread for it. Nothing is lost: it is in the '
                    'staff inbox. Somebody will get back to you.')
            except Exception as e:
                log('could not even DM %s about the failed ticket: %s' % (who, e))

        await push_async(self.kind, '%s: %s' % (self.label_text, who.display_name),
                         detail, str(who), who.id)

        if posted:
            await interaction.followup.send(
                'Opened %s. Everything else goes in there.' % opened.mention,
                ephemeral=True)
        elif fell_back:
            await interaction.followup.send(
                'Sent. A private thread would not open, so it has gone to staff '
                'in the channel instead. Somebody will answer you.',
                ephemeral=True)
        else:
            await interaction.followup.send(
                'Sent to staff. Discord would not let a thread open for it, so '
                'the answer will come by message rather than in here.',
                ephemeral=True)


def _chunks(s, n):
    while s:
        cut = s[:n]
        if len(s) > n:
            at = cut.rfind('\n')
            if at > n // 2:
                cut = s[:at]
        yield cut
        s = s[len(cut):].lstrip('\n')


def is_staff(who, ch):
    """Staff, or anybody the channel itself trusts with threads."""
    try:
        names = set(r.name.lower() for r in getattr(who, 'roles', []))
        if names & (set(STAFF) | set(CREATOR)):
            return True
    except Exception:
        pass
    try:
        return bool(ch.permissions_for(who).manage_threads)
    except Exception:
        return False


async def close_here(interaction, why=None):
    """
    Close the ticket this was used in.

    Archived and locked rather than deleted. A ticket is the record of what
    somebody was told and when, and the one time anybody goes looking for it
    is the argument afterwards, so nothing here removes anything. Locked means
    it takes a staff member to open it again, not a stray message.
    """
    ch = interaction.channel
    if not isinstance(ch, discord.Thread):
        await interaction.response.send_message(
            'This one only works inside a ticket.', ephemeral=True)
        return

    if not is_staff(interaction.user, ch):
        await interaction.response.send_message(
            'Staff close these. Say what you need in here and somebody will.',
            ephemeral=True)
        return

    line = 'Closed by %s.' % interaction.user.mention
    if why:
        line += ' ' + why.strip()
    line += ('\nNothing is deleted. Everybody who was in here can still read it, '
             'and staff can open it again.')
    await interaction.response.send_message(line[:1900])

    # Archiving drops a thread out of the sidebar and out of the channel's
    # active list, and a private one is then behind two clicks nobody finds. A
    # closed ticket nobody can find again is barely better than a lost one, so
    # a line is written down somewhere searchable with a link straight back to
    # it. Somewhere being the staff channel, not the one people apply in.
    try:
        book = await log_channel(interaction.guild)
        if book is not None:
            note = 'Closed: **%s**. By %s.' % (
                ch.name, interaction.user.display_name)
            if why:
                note += ' ' + why.strip()
            note += '\n' + ch.jump_url
            await book.send(note[:1900])
    except Exception:
        log('could not write the ticket down:\n' + traceback.format_exc())

    # Sent first, then archived. The other way round the message never lands,
    # because an archived thread will not take one.
    try:
        await ch.edit(archived=True, locked=True)
    except Exception:
        try:
            await ch.edit(archived=True)
        except Exception:
            log('could not archive the ticket thread:\n' + traceback.format_exc())


class TicketTools(discord.ui.View):
    """Sits on the ticket's first message. Persistent, so it still works after
       the bot restarts rather than going dead the moment anything updates."""
    def __init__(self):
        super().__init__(timeout=None)

    @discord.ui.button(label='Close ticket', style=discord.ButtonStyle.secondary,
                       custom_id='thornswood:close')
    async def close(self, interaction, button):
        await close_here(interaction)


@tree.command(name='close', description='Close this ticket. Staff only.')
@discord.app_commands.describe(why='Optional. What was decided.')
async def close_cmd(interaction: discord.Interaction,
                    why: typing.Optional[str] = None):
    await close_here(interaction, why)


class TicketPanel(discord.ui.View):
    def __init__(self):
        super().__init__(timeout=None)
        self.add_item(TicketPicker())


class TicketPicker(discord.ui.Select):
    def __init__(self):
        super().__init__(
            custom_id='thornswood:ticket',
            placeholder='What do you need?',
            options=[discord.SelectOption(label=lab, value=k, description=desc[:100])
                     for k, lab, desc in KINDS])

    async def callback(self, interaction):
        k = self.values[0]
        lab = dict((a, b) for a, b, _ in KINDS)[k]
        await interaction.response.send_modal(TicketModal(k, lab))


PANEL = ('**Open a ticket**\n\n'
         'Pick the one that fits. It asks a few questions, then opens a thread '
         'only you and staff can see. Nothing here is public and nobody else in '
         'the server can read it.\n\n'
         '**Apply to playtest** is the one everybody starts with, and it is how '
         'you get into the world. **Apply: Jarl** is '
         'answered in character: the seats are empty, and the first people to '
         'hold them are picked out of what is written there.\n\n'
         'The jobs below that are open to anybody already in, and they are jobs '
         'rather than titles: each one is work somebody is currently doing '
         'instead of you.\n\n'
         'Applying for one does not give you it. Somebody reads it and answers.')


def _panel_options(msg):
    """
    The value and label of every option the POSTED dropdown is offering.

    Read off the message rather than off KINDS, because the two are exactly
    what can drift: the options a dropdown offers live in the message that was
    posted, not in the View this process builds on startup.

    An empty list when the components cannot be read, which does not match the
    wanted list, so the panel is edited. That is the right way round to fail:
    an edit nobody needed costs one audit log line, and a kind that never
    appears costs somebody a ticket they cannot open.
    """
    pairs = []
    try:
        for row in getattr(msg, 'components', None) or []:
            for item in getattr(row, 'children', None) or []:
                for o in getattr(item, 'options', None) or []:
                    pairs.append((getattr(o, 'value', ''), getattr(o, 'label', '')))
    except Exception:
        return []
    return pairs


def _panel_wanted():
    return [(k, lab) for k, lab, _ in KINDS]


def panel_is_current(msg):
    """
    True when the posted panel already says what it should, text and options.

    Its own function so it can be run without a Discord to run it against:
    tools/discord/test-ready.py drives it with a made up message. The decision
    is the part worth pinning, because getting it wrong in either direction is
    a real fault: too eager and the panel is edited on every reconnect, too
    lazy and a ticket kind added later never appears for anybody.
    """
    return getattr(msg, 'content', None) == PANEL and _panel_options(msg) == _panel_wanted()


async def ensure_panel(guild):
    ch = by_name(guild, TICKETS)
    if ch is None:
        names = ', '.join('#' + c.name for c in guild.text_channels) or 'none'
        log('there is no text channel called #%s in "%s", so there is no panel '
            'and no tickets. Text channels there: %s. Set TICKET_CHANNEL in '
            'bot.env.json to one of those and run Install-Bot.ps1 again.'
            % (TICKETS_SAID, guild.name, names))
        return

    # Said at startup rather than the first time somebody applies, because the
    # first time somebody applies is the worst moment to find out.
    # Slash commands are a permission of their own, and it is granted per
    # channel. The server owner bypasses every overwrite, so /close looked
    # fine to the one person who could never have been blocked by it while
    # staff saw nothing at all. Named here rather than left to be discovered.
    try:
        blocked = []
        for r in guild.roles:
            if r.name.lower() not in (set(STAFF) | set(CREATOR)):
                continue
            if not getattr(ch.permissions_for(r), 'use_application_commands', True):
                blocked.append(r.name)
        if blocked:
            log('%s cannot use /close in #%s: Use Application Commands is off '
                'for them there. Turn it on in that channel\'s permissions. The '
                'Close button on the ticket works for them either way.'
                % (', '.join(blocked), ch.name))
    except Exception:
        pass

    book = await log_channel(guild)
    if book is not None:
        log('closed tickets are written down in #%s' % book.name)

    why = thread_block(guild, ch)
    if why:
        log('tickets in "%s" will NOT get a private thread: %s. Tick it in '
            'that channel\'s permissions, or on the bot\'s role server wide. '
            'Until then every ticket goes into #%s as a plain message.'
            % (guild.name, why, ch.name))
    else:
        log('ticket threads look fine in #%s' % ch.name)

    try:
        async for m in ch.history(limit=30):
            if m.author.id == client.user.id and m.components:
                # The options a dropdown offers live in the message that was
                # posted, not in the View this process builds on startup. So
                # leaving the old message alone is exactly why a ticket kind
                # added later never appeared for anybody: the code had it, the
                # message did not. Editing in place keeps the same message and
                # its spot in the channel and puts the current list on it.
                #
                # BUT ONLY WHEN THERE IS SOMETHING TO CHANGE. This ran on every
                # reconnect, so a flaky evening was a stream of edits to the
                # same message, each one an entry in the audit log and a write
                # against the rate limit the bot is already fighting. The text
                # and the option list are compared first, and both are
                # compared: comparing the text alone puts back the bug above,
                # where a kind added later never appeared because the words
                # around it had not changed.
                if panel_is_current(m):
                    log('ticket panel is already current in #%s' % ch.name)
                    return
                await m.edit(content=PANEL, view=TicketPanel())
                log('ticket panel updated in #%s' % ch.name)
                return
        await ch.send(PANEL, view=TicketPanel())
        log('ticket panel posted in #%s' % ch.name)
    except Exception:
        log('panel failed:\n' + traceback.format_exc())


# ----------------------------------------------------------- the watcher --
#
# WHY THE BOT DOES THIS AND NOT THE BOX.
#
# On 21 September thornswood.net was down and stayed down. Caddy, which holds
# 443, had stopped, and the task that runs it had one startup trigger, so
# nothing restarted it and nothing ever looked again. It surfaced hours later
# as two testers reporting launcher faults, because the launcher checks people
# in through the site and voice runs on the same hostname. A site that is down
# looks to everybody like the launcher being broken, which is the worst kind of
# outage: the reports point at the wrong thing.
#
# Caddy restarts itself now. This is the other half, which is somebody being
# told.
#
# It lives in the bot because the bot is already running on that box, already
# authenticated, and already written to keep going when a piece of it fails. A
# watcher anywhere else needs a webhook put somewhere new, and the webhook
# files are kept out of git deliberately.
#
# WHAT IT CANNOT CATCH is the box itself going down, which takes this with it.
# That needs something off the machine and is not this.


def site_answers():
    """
    Ask the site the way somebody's browser would.

    Over the public name and the certificate, deliberately, so this fails when
    Caddy is down and not only when node is. Asking 127.0.0.1:3001 would have
    said the site was perfectly fine all through the outage this was written
    for.

    HEAD rather than GET: the answer is the status code, and there is no reason
    to pull the front page down every five minutes forever.

    Blocking, so it is called through an executor. Never raises.
    """
    req = urllib.request.Request(
        SITE + '/', method='HEAD',
        headers={'User-Agent': 'thornswood-watch'})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            code = r.getcode()
            if 200 <= code < 400:
                return True, 'HTTP %d' % code
            return False, 'HTTP %d' % code
    except Exception as ex:
        # The class name matters when the message is empty, which is what a
        # bare socket timeout gives you.
        return False, str(ex) or ex.__class__.__name__


async def watch_say(text):
    """
    Say it once, in the staff channel, found by id.

    Nothing is guessed and nothing falls back to another channel. If that id is
    not a channel this bot can see, it says so in the bot log and stays quiet in
    Discord, because the only channel it could fall back to by name is the
    public one.
    """
    if not WATCH_ID:
        log('watch: no channel id, so nothing was said. dev-channel.txt is '
            'missing or unreadable, or set WATCH_CHANNEL_ID in bot.env.json '
            'on the VPS.')
        return
    ch = client.get_channel(WATCH_ID)
    if ch is None:
        log('watch: channel %d is not one this bot can see, so nothing was '
            'said.' % WATCH_ID)
        return
    try:
        await ch.send(text)
    except Exception:
        log('watch: could not post in #%s:\n' % getattr(ch, 'name', WATCH_ID)
            + traceback.format_exc())


async def watch_site():
    """
    Ask every WATCH_EVERY seconds, and speak only when the answer changes.

    SILENCE IS THE POINT. A line every five minutes saying the site is up is a
    channel nobody reads, and a channel nobody reads is the same as no watcher
    at all. So it says the site went down, once, and says it came back, once.

    Nothing in here is allowed to end the loop. A watcher that dies quietly is
    worse than no watcher, because from the outside it looks exactly like
    everything being fine.
    """
    await client.wait_until_ready()
    misses = 0
    said_down = False
    log('watch: asking %s every %ds, speaking up after %d miss(es), in channel '
        '%d' % (SITE, WATCH_EVERY, WATCH_MISSES, WATCH_ID))

    while not client.is_closed():
        try:
            ok, what = await asyncio.get_running_loop().run_in_executor(
                None, site_answers)
            if ok:
                if said_down:
                    said_down = False
                    await watch_say('The site is answering again. %s' % what)
                    log('watch: back up, %s' % what)
                elif misses:
                    log('watch: answered after %d miss(es), %s' % (misses, what))
                misses = 0
            else:
                misses += 1
                log('watch: no answer from %s, %d in a row: %s'
                    % (SITE, misses, what))
                if misses >= WATCH_MISSES and not said_down:
                    said_down = True
                    await watch_say(
                        'The site is not answering. %d checks in a row, %d '
                        'seconds apart, and the last one said: %s\n'
                        'Caddy holds 443 and now restarts itself every five '
                        'minutes, so if this does not clear on its own then it '
                        'is the box, the certificate, or something in front of '
                        'both. People will be told they could not be checked '
                        'in, and voice will sit on connecting, until it does.'
                        % (misses, WATCH_EVERY, what))
        except Exception:
            log('watch: the check itself failed, carrying on:\n'
                + traceback.format_exc())
        await asyncio.sleep(WATCH_EVERY)


async def watch_trouble():
    """
    Say in the staff channel when a session goes wrong.

    The site reads every session's logs as they arrive and appends the ones
    that went wrong to trouble.json. This reads that file and says each new one
    once. A file rather than a request because both run on this box.

    WHAT IT REMEMBERS AND WHY. The session ids already in the file when this
    starts are treated as said. Without that, every restart of the bot would
    re-announce the last two hundred, which is the fastest way to make a staff
    channel unreadable and therefore unread. It means a session that went wrong
    while the bot was down is not announced, and that is the right trade: it is
    still on the page, in red, which is where somebody looks.

    Nothing in here may end the loop, for the same reason as the site watcher:
    a watcher that dies quietly looks exactly like everything being fine.
    """
    await client.wait_until_ready()

    def read_all():
        try:
            with open(TROUBLE_FILE, encoding='utf-8') as f:
                rows = json.load(f)
            return rows if isinstance(rows, list) else []
        except Exception:
            return []

    loop = asyncio.get_running_loop()
    said = set()
    for row in await loop.run_in_executor(None, read_all):
        if isinstance(row, dict) and row.get('session'):
            said.add(row['session'])
    ch = _trouble_channel()
    log('trouble: watching %s every %ds, speaking in %s, %d already there and '
        'treated as said'
        % (TROUBLE_FILE, TROUBLE_EVERY,
           ('#' + ch.name) if ch is not None else 'NOWHERE, see above',
           len(said)))

    while not client.is_closed():
        try:
            for row in await loop.run_in_executor(None, read_all):
                if not isinstance(row, dict):
                    continue
                sid = row.get('session') or ''
                if not sid or sid in said:
                    continue
                said.add(sid)

                who = row.get('name') or row.get('who') or 'somebody'
                where = row.get('channel') or ''
                where = {'dev': 'the dev build', 'main': 'the main build'}.get(
                    where, 'a build it did not name')
                line = (row.get('line') or '').strip()
                await trouble_say(
                    '**A session went wrong.** %s, on %s%s.\n%s\n%s\n'
                    'The logs are on the sessions page under that session, '
                    'and it is the red one.'
                    % (who,
                       where,
                       (', launcher %s' % row['version']) if row.get('version') else '',
                       row.get('why') or 'something went wrong',
                       ('```\n%s\n```' % line[:400]) if line else ''))
        except Exception:
            log('trouble: the check itself failed, carrying on:\n'
                + traceback.format_exc())
        await asyncio.sleep(TROUBLE_EVERY)


def _trouble_channel():
    """
    The channel a session that went wrong is announced in.

    An id wins, from staff-channel.txt or TROUBLE_CHANNEL_ID, because an id
    cannot be ambiguous. With no id it falls back to the name staff-general,
    AND ONLY WHEN EXACTLY ONE CHANNEL HAS THAT NAME.

    That last part is the whole rule. This server has two channels called news,
    one staff and one public, and discord.py's by-name lookup hands back
    whichever is listed first, so a watcher matching on a name would eventually
    announce staff business in public. One match is safe; two is not, and two
    is silence plus a line in the log saying so rather than a guess.
    """
    if TROUBLE_ID:
        ch = client.get_channel(TROUBLE_ID)
        if ch is not None:
            return ch
        log('trouble: channel id %d is not one this bot can see.' % TROUBLE_ID)

    found = []
    for g in client.guilds:
        for ch in getattr(g, 'text_channels', []):
            if ch.name == 'staff-general':
                found.append(ch)
    if len(found) == 1:
        return found[0]
    if len(found) > 1:
        log('trouble: %d channels are called staff-general, so nothing was '
            'said. Put the right id in staff-channel.txt or set '
            'TROUBLE_CHANNEL_ID.' % len(found))
        return None

    log('trouble: no channel called staff-general and no id given.')
    return None


async def trouble_say(text):
    """Say it once, in the staff channel. Same rules as watch_say."""
    ch = _trouble_channel()
    if ch is None:
        return
    try:
        await ch.send(text[:1900])
    except Exception:
        log('trouble: could not post in #%s:\n' % getattr(ch, 'name', '?')
            + traceback.format_exc())


# on_ready fires again on every reconnect, and a second loop would double every
# message this ever sends.
_watching = False


# What was last registered with Discord, so a restart does not do it all
# again. Next to the code, because that folder is the bot's own and a deploy
# that replaces it is a deploy that may have changed the commands anyway.
STAMP = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                     'commands-synced.json')

# Set FORCE_COMMAND_SYNC=1 in bot.env.json to make the next start register them
# whatever the stamp says. For the case where Discord has them and this file
# does not, which is a deploy that landed on a fresh folder.
FORCE_SYNC = _int_env('FORCE_COMMAND_SYNC', 0)


def _command_names():
    return sorted(c.name for c in tree.get_commands())


def _stamp_read():
    try:
        with open(STAMP) as f:
            d = json.load(f)
        return list(d.get('commands') or []), [int(x) for x in (d.get('guilds') or [])]
    except Exception:
        return [], []


def _stamp_write(names, guilds):
    try:
        with open(STAMP, 'w') as f:
            json.dump({'commands': names, 'guilds': sorted(guilds)}, f)
    except Exception:
        log('could not write ' + STAMP + ', so the commands will be registered '
            'again on the next start:\n' + traceback.format_exc())


async def register_commands():
    """
    Put the slash commands on every server, once, and not again until they
    change.

    A global sync can take an hour to reach everybody, and it reaches people
    unevenly while it does, which looks exactly like one person's Discord
    being broken. Copying the commands onto the server itself and syncing that
    is immediate and the same for everyone in it.

    Registering both, which is what this did first, puts the command in the
    picker twice: Discord lists the server copy and the global copy as two
    separate entries and there is no way to tell them apart. So the guild copy
    is the one kept, and the global list is emptied straight after. Clearing
    globals is done last because copy_global_to reads that same list, and
    clearing it first would copy nothing.

    WHY IT IS BEHIND A STAMP. This was three writes to Discord per reconnect,
    doing nothing new every time, and a sync is one of the calls Discord rate
    limits hardest. A reconnect is not a new set of commands; a deploy is. So
    the names that were registered are written down beside the code, and this
    runs when that list differs, when a server appears that is not in it, or
    when FORCE_COMMAND_SYNC says to. A rate limited sync used to write a
    traceback on an evening that was already going badly.
    """
    want = _command_names()
    had, done = _stamp_read()
    fresh = [g for g in client.guilds if g.id not in done]

    if want == had and not fresh and not FORCE_SYNC:
        log('slash commands already registered: %s' % (', '.join(want) or 'none'))
        return

    synced = list(done)
    for g in client.guilds:
        try:
            tree.copy_global_to(guild=g)
            await tree.sync(guild=g)
            if g.id not in synced:
                synced.append(g.id)
            log('/close is registered in "%s"' % g.name)
        except Exception:
            log('could not register /close in "%s", the Close button still '
                'works:\n' % g.name + traceback.format_exc())
    try:
        tree.clear_commands(guild=None)
        await tree.sync()
    except Exception:
        log('could not clear the global commands, so /close may appear twice '
            'in the picker:\n' + traceback.format_exc())

    _stamp_write(want, synced)


@client.event
async def on_ready():
    global _watching
    if not _watching:
        _watching = True
        asyncio.create_task(watch_site())
        asyncio.create_task(watch_trouble())

    log('up as %s' % client.user)

    await register_commands()

    for g in client.guilds:
        await ensure_panel(g)
    log('watching %d server(s)' % len(client.guilds))

    # Three separate things have to be true for a join card to appear, and
    # when one of them is not, the only symptom is silence. So check all three
    # at startup and say which one is wrong, by name.

    # One: Discord has to be sending joins at all.
    if not client.intents.members:
        log('member joins: OFF. No join cards will ever fire. Turn on Server '
            'Members Intent at discord.com/developers, Bot page, then restart.')
        return
    log('member joins: on')

    for g in client.guilds:
        # Two: the channel has to exist, and be a text channel.
        ch = by_name(g, [WELCOME])
        if ch is None:
            names = ', '.join('#' + c.name for c in g.text_channels) or 'none'
            log('there is no text channel called #%s in "%s", so join cards '
                'have nowhere to go. Text channels there: %s. Either make one '
                'with that name, or set JOIN_CHANNEL in bot.env.json on the '
                'VPS to one of those and run Install-Bot.ps1 again.'
                % (WELCOME, g.name, names))
            continue

        # Three: the bot has to be allowed to post, and to attach the card.
        p = ch.permissions_for(g.me)
        missing = [n for n, ok in (('View Channel', p.view_channel),
                                   ('Send Messages', p.send_messages),
                                   ('Attach Files', p.attach_files)) if not ok]
        if missing:
            log('cannot post in #%s in "%s": the bot is missing %s there. Fix '
                'it in that channel\'s permissions, or give the bot role those '
                'permissions server wide.' % (ch.name, g.name, ', '.join(missing)))
        else:
            log('join cards will go to #%s in "%s"' % (ch.name, g.name))


# Under a main guard, so that importing this file reads it instead of running
# it. Without one, `import bot` connects to Discord with whatever token is in
# env, which is why nothing in here had ever been tested: there was no way to
# get at a function without starting a bot. Install-Bot.ps1 launches it as
# `python bot.py`, where __name__ is __main__, so this changes nothing about
# how it runs on the VPS.
if __name__ == '__main__':
    try:
        client.run(TOKEN)
    except discord.PrivilegedIntentsRequired:
        log('Discord refused the connection because Server Members Intent is off.')
        log('Go to discord.com/developers, open the Thornswood application, Bot in')
        log('the left menu, switch on SERVER MEMBERS INTENT, save, then run')
        log('Install-Bot.ps1 again.')
        raise SystemExit(1)
    except discord.LoginFailure:
        log('Discord rejected the bot token. Reset it on the Bot page and run')
        log('Install-Bot.ps1 again to paste the new one.')
        raise SystemExit(1)
