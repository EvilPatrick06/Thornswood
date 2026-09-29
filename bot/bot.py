"""
The Thornswood bot. This one stays running, unlike Build-Discord.py which sets
the server up once and exits.

What it does:

  Joins    draws a card and puts it in #welcome
  Tickets  a panel in #tickets-and-applications, one private thread per
           ticket, and a copy pushed to the site so the inbox has it whether
           or not anybody was looking at Discord. #tickets is the staff only
           channel closed tickets are written down in, and where a ticket
           goes when its thread will not open
  Watch    asks the site every five minutes over its public name, and says so
           in #dev when it stops answering and when it comes back
  Services reads the VPS watchdog's watch.log every minute and says in the
           same channel when a service needs a look, could not be started,
           or did not come back after a restart
  Reports  says each thing sent in on the site's public report page in the
           staff channel, the day it arrives
  Holds    a panel in #choose-your-hold where a Member picks their hold
           and which announcements ping them

Everything it needs is in env:

  DISCORD_TOKEN    the bot token
  THORNSWOOD_SITE  https://thornswood.net
  THORNSWOOD_KEY   shared secret the site checks on /api/ticket
  JOIN_CHANNEL     name of the channel join cards go in, default general
  TICKET_CHANNEL   public channel the panel lives in, comma separated, first wins
  TICKET_LOG       staff only channel closed tickets are recorded in, and where
                   a ticket goes when its thread will not open. Checked by its
                   permissions, never trusted by its name
  STAFF_ROLES      comma separated, who gets pulled into every ticket thread
  CREATOR_ROLES    comma separated, added to Apply: Content Creator only
  TICKET_COOLDOWN  seconds between one person's tickets, default 300
  WATCH_CHANNEL_ID id of the staff channel the site watcher speaks in,
                   default whatever dev-channel.txt beside this file holds
  WATCH_EVERY      seconds between checks, default 300
  WATCH_MISSES     how many in a row before it says so, default 2
  WATCH_LOG        the watchdog's log, default the one Watch-Services.ps1
                   writes on the VPS
  WATCH_LOG_EVERY  seconds between reads of it, default 60
  HOLD_CHANNEL     channel the hold panel lives in, default choose-your-hold
  MEMBER_ROLE      role that may pick a hold, default Member

It is written to keep going when a piece of it fails. A card that will not
draw still gets a greeting, a site that is down still gets a thread, and a
thread that cannot be made still gets an answer to the person who asked.
"""
import asyncio
import datetime
import json
import os
import re
import ssl
import time
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
# not there. A ticket whose private thread will not open goes here too, so a
# report about somebody is never posted where that somebody can read it.
# log_channel checks that by the channel's permissions, not by these names.
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

# Where the site writes what people send in on its public report page, read
# the same way as trouble.json and said in the same staff channel.
REPORTS_FILE = os.environ.get(
    'REPORTS_FILE', r'C:\Thornswood-Docs\data\inbox.json')
REPORTS_EVERY = _int_env('REPORTS_EVERY', 120)
# More than this many in one look is a script, not five people, because the
# site takes five an hour from any one place. Then one line says how many.
REPORTS_AT_ONCE = 5


WATCH_EVERY = _int_env('WATCH_EVERY', 300)
# Two in a row rather than one. A single timeout is a moment of packet loss and
# nobody wants to read about it. Two, five minutes apart, is the site being
# down. Caddy's own repeating trigger is five minutes as well, so anything that
# clears by itself has had a go at clearing before this says a word.
WATCH_MISSES = _int_env('WATCH_MISSES', 2)

# What the watchdog Watch-Services.ps1 puts on the VPS writes down. The bot
# runs on the same box as the same SYSTEM account, so it can read it.
WATCH_LOG = os.environ.get('WATCH_LOG', r'C:\Thornswood-Watch\watch.log')
# Once a minute. The watchdog itself runs every five, so this is never more
# than a minute behind it, and the file is two thousand short lines at most.
WATCH_LOG_EVERY = _int_env('WATCH_LOG_EVERY', 60)

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
        # The one switch (#428), before the panel is built from KINDS.
        set_open(await asyncio.get_running_loop().run_in_executor(None, site_open))
        log('the world is %s' % ('open to everybody' if OPEN else 'in alpha, open by application'))
        self.add_view(TicketPanel())          # so it keeps working after a restart
        self.add_view(TicketTools())          # and so does Close on every old ticket
        self.add_view(HoldPanel())            # and the hold and ping buttons


client = Thornswood(intents=intents)
tree = discord.app_commands.CommandTree(client)


def log(*a):
    print('[thornswood-bot]', *a, flush=True)


# ------------------------------------------------------------------ site --
def push(kind, title, detail, by, discord_id, rules=None):
    """Send a ticket to the site. Runs off the event loop, and a failure here
       is never allowed to lose the ticket: the thread in Discord is the
       record, this is the convenience.

       rules is the application's answer to the rules question, as
       {'said': their words, 'yes': whether it read as a yes}, or None on a
       ticket that does not ask it. The site keeps the latest one against the
       Discord id (#428), because the inbox is trimmed and the record of who
       accepted the rules should not be."""
    if not KEY:
        # Silent for as long as this has existed, which means a bot with no key
        # set looked exactly like a working one: the thread appeared, the site
        # inbox stayed empty, and nothing anywhere said why.
        log('THORNSWOOD_KEY is not set, so this ticket did NOT reach the site '
            'inbox. The thread in Discord is the only copy. Install-Bot.ps1 '
            'sets the key in bot.env.json on the VPS.')
        return
    sent = {
        'key': KEY, 'kind': kind, 'title': title,
        'detail': detail, 'by': by, 'discordId': str(discord_id)
    }
    if rules is not None:
        sent['rules'] = rules
    body = json.dumps(sent).encode()
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


# Site copies still on their way. The event loop holds a task only weakly, so a
# task nothing else refers to can be collected before it has finished. This
# set holds each one until it is done, and each one takes itself out.
_pushes = set()


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


def private_channel_ok(guild, ch):
    """
    True when nobody outside staff can read this channel, by its permissions
    and not by its name.

    @everyone must be denied it, and so must every role that is not staff.
    Content Creator counts as outside, for the reason log_channel gives. Two
    kinds of role are skipped because no channel could ever keep them out: a
    role with Administrator reads every channel whatever its overwrites say,
    and a bot's own role is software somebody added to the server, this bot
    included. Counting either would make no channel private at all.

    A person given the channel by name, in a member overwrite, counts too,
    unless they hold a staff role or are a bot.

    Anything it cannot read is a no. The cost of a wrong no is a ticket that
    reaches the site inbox and not Discord; the cost of a wrong yes is a report
    about somebody in front of the person it is about.
    """
    try:
        staff = set(STAFF)
        if ch.permissions_for(guild.default_role).view_channel:
            return False
        roles = list(guild.roles)
        for r in roles:
            if r == guild.default_role or r.name.lower() in staff:
                continue
            if getattr(r.permissions, 'administrator', False):
                continue
            if getattr(r, 'is_bot_managed', lambda: False)():
                continue
            if ch.permissions_for(r).view_channel:
                return False
        for who, ow in (getattr(ch, 'overwrites', None) or {}).items():
            if who in roles or getattr(who, 'bot', False):
                continue
            held = set(x.name.lower() for x in (getattr(who, 'roles', None) or []))
            if ow.view_channel and not (held & staff):
                return False
        return True
    except Exception:
        log('could not read the permissions on #%s, so it is treated as '
            'public:\n' % getattr(ch, 'name', '?') + traceback.format_exc())
        return False


async def log_channel(guild, make=True):
    """
    The staff only channel closed tickets are recorded in, and where a ticket
    goes when its private thread will not open.

    Made rather than asked for, because the alternative is a feature that
    silently does nothing until somebody thinks to read a log. Deny first:
    @everyone cannot see it and only the staff roles are added back. Content
    Creator is left out on purpose, the same reason it is left out of every
    ticket that is not an application to join it.

    CHECKED, NOT TRUSTED BY NAME. TICKET_LOG's first name is tickets. Until
    24 September Build-Discord.py's PLAN made a #tickets in Help with
    mode='open', which everybody in the server could read. The PLAN now makes
    #tickets staff only, in Applications beside the panel, and that is the
    channel this is meant to find. But the PLAN's modes only apply to a
    channel it makes, never to one already there, so a #tickets left over
    from the old PLAN, or made by hand, keeps whatever permissions it had.
    This used to take the first channel with a TICKET_LOG name, so a public
    one would have become the log, and every closed application and every
    report that missed its thread would have gone into it. Now a channel with
    the right name and the wrong permissions is passed over and said so, and
    the next free name is made instead.
    """
    taken = set()
    for want in TICKET_LOG:
        for ch in guild.text_channels:
            if ch.name.lower() != want:
                continue
            taken.add(want)
            if private_channel_ok(guild, ch):
                return ch
            log('#%s is named in TICKET_LOG, but people outside staff can read '
                'it, so nothing from a ticket goes there.' % ch.name)
    if not make:
        return None

    free = [n for n in TICKET_LOG if n not in taken]
    if not free:
        log('every TICKET_LOG name (#%s) is a channel people outside staff can '
            'read, so there is nowhere private in Discord to put a ticket. '
            'Make one of them staff only, or add another name to TICKET_LOG '
            'in bot.env.json on the VPS.' % ', #'.join(TICKET_LOG))
        return None

    if not guild.me.guild_permissions.manage_channels:
        log('there is no #%s to record closed tickets in, and the bot cannot '
            'make one because it does not have Manage Channels. Either give '
            'it that, or make the channel by hand with staff the only ones '
            'who can see it.' % free[0])
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
            free[0],
            overwrites=over,
            category=(where.category if where is not None else None),
            topic='Every ticket that gets closed, with a link back to it, and '
                  'any ticket whose private thread would not open. Staff only.')
        log('made #%s for closed tickets, staff only' % ch.name)
        return ch
    except Exception:
        log('could not make #%s:\n' % free[0] + traceback.format_exc())
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
# Which arrival each person was, on disk beside the code.
#
# Patrick, 24 September, with a screenshot of #welcome-travelers: "#28 twice".
# Daggerio came up the road at 19:41 and VENUS at 22:45, and both cards said
# "The 28th to walk in". The number was guild.member_count, the server's size
# at that moment, and the size falls whenever anybody leaves or is removed, so
# one departure between two joins handed the second arrival the first one's
# number, and it could go on doing that for ever.
#
# So the numbers are written down: the last one given out on each server, and
# the one each person got. A new arrival gets the next one, and somebody who
# leaves and comes back keeps theirs. It never goes below member_count, since
# anybody who joined while the bot was down was never counted here. And it
# never goes below JOIN_FLOOR, the highest number known to be on a card
# already: 28, off that screenshot, which is the one number the first join
# after this goes up has to get past, with no record yet and a member count
# that may by then be under it. Set JOIN_NUMBER_FLOOR in bot.env.json on the
# VPS if a later card went higher before this was installed.
#
# Install-Bot.ps1 sends a fixed list of files and deletes nothing in this
# folder, so neither the full run nor -CodeOnly can overwrite or remove it,
# and .gitignore keeps it out of the repo, like open-tickets.json.
JOINS = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'joins.json')
JOIN_FLOOR = _int_env('JOIN_NUMBER_FLOOR', 28)


def _joins_read():
    """
    The record, or {} when there is none yet. Raises when there is one and it
    cannot be read, so a file that is there and unreadable is never taken for
    an empty one and written over, which would start the numbers again.
    """
    if not os.path.exists(JOINS):
        return {}
    with open(JOINS, encoding='utf-8') as f:
        d = json.load(f)
    if not isinstance(d, dict):
        raise ValueError(JOINS + ' is not a JSON object')
    return d


def _joins_write(d):
    """Written to a file beside it and swapped in, so a write that fails half
       way leaves the old record whole rather than half of a new one."""
    tmp = JOINS + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(d, f)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, JOINS)


def _joins_of(rec, guild):
    """This server's part of the record, and the numbers in it by member id,
       each made empty when it is missing or not the shape it should be."""
    g = rec.get(str(guild.id))
    if not isinstance(g, dict):
        g = {}
    ids = g.get('members')
    if not isinstance(ids, dict):
        ids = {}
    return g, ids


def _joins_number(ids, member_id):
    """The number the record holds for this member, or None."""
    had = ids.get(str(member_id))
    return had if type(had) is int and had > 0 else None


def joins_given(guild):
    """
    {member id: number} for everybody the record has numbered on this server,
    read and never written.

    backfill.py and redraw.py read the record through this and the two above,
    so a card they draw carries the number on_member_join gave, by the same
    reading of the file. Until 24 September they numbered by join order among
    the members still here and never opened it, so redraw.py --all would have
    put numbers on old cards that disagree with the record. Raises, like
    _joins_read, when the record is there and cannot be read.
    """
    g, ids = _joins_of(_joins_read(), guild)
    out = {}
    for k in ids:
        n = _joins_number(ids, k)
        if n is not None and str(k).isdigit():
            out[int(k)] = n
    return out


def arrival_number(guild, member):
    """
    Which arrival this member is on this server: the number they were given
    before, or the next one. When the record cannot be read or written this
    says so in the log and answers member_count, which is what every card
    said before, because a greeting never waits on a file.

    Called on the event loop and not in an executor, so two joins a moment
    apart cannot both read the same last number.
    """
    count = guild.member_count
    try:
        rec = _joins_read()
        g, ids = _joins_of(rec, guild)
        had = _joins_number(ids, member.id)
        if had is not None:
            n, said = had, 'came back and keeps number %d' % had
        else:
            last = g.get('last')
            if type(last) is not int:
                last = 0
            n = max(last + 1, JOIN_FLOOR + 1, count or 0)
            ids[str(member.id)] = n
            g['members'] = ids
            g['last'] = n
            rec[str(guild.id)] = g
            _joins_write(rec)
            said = 'is number %d, with %s members' % (n, count)
    except Exception:
        log('join numbers: could not read or write %s, so this card says the '
            'member count, %s, which can repeat a number:\n%s'
            % (JOINS, count, traceback.format_exc()))
        return count
    log('join: %s %s' % (member, said))
    return n


@client.event
async def on_member_join(member):
    # First line in, before anything can go wrong, so the log can tell a join
    # that never reached the bot apart from one that reached it and failed.
    log('join: %s arrived in "%s"' % (member, member.guild.name))

    ch = by_name(member.guild, [WELCOME])
    if ch is None:
        log('no text channel called #%s to greet in' % WELCOME)
        return

    number = arrival_number(member.guild, member)
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
# 'Apply to play' is not here on purpose. Patrick, 28 Sep: "we are in alpha so
# the world is open by application". Anyone can download it, and the one way
# into the world is this application, which gives the Playtester role when it
# is accepted. A second 'Apply to play' asked people to guess which one they
# wanted and half of them guessed wrong. The key stays 'playtest' because the
# site inbox and ROLE_FOR file it under that name.
KINDS = [
    ('playtest',    'Apply to be an alpha playtester',
                    'How you get into the world. Anyone can apply. Break it and write down how.'),
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

# #428: before this, nobody ever accepted the rules. Somebody could join for the
# invite, be let in, press Play and have agreed to nothing. Asked on the same
# tickets as the age question, for the same reason and in the same way: their
# own words against their Discord id, at a time, in the thread, the site inbox
# and the site's record of who accepted (push, then /api/ticket on the site).
# Anything that does not read as a yes goes at the top of the thread for staff,
# and nobody is given the role without somebody reading it.
RULES_Q = ('Do you accept the rules in #rules?',
           'Read #rules and thornswood.net/rules first. Yes or no.', False)
RULES_KINDS = AGE_KINDS

_ACCEPT = ('yes', 'yep', 'yeah', 'yup', 'y ', 'ye', 'i do', 'i accept', 'accept',
           'i agree', 'agree', 'i have', "i've", 'sure', 'of course', 'ok',
           'okay', 'absolutely', 'definitely', 'read and', 'correct', 'affirmative')


def accepted_rules(text):
    """
    Whether an answer to the rules question reads as a yes.

    Generous, like said_yes, and it never refuses anybody by itself: a no only
    puts a line at the top of the thread for a person to read. A no word
    anywhere at the start wins, so "no, not yet" is never taken for a yes.
    """
    t = (text or '').strip().lower()
    if not t:
        return False
    if t == 'n' or t.startswith(_NO) or t.startswith(("don't", 'dont', 'do not',
                                                     'i do not', "i don't", 'i dont',
                                                     'haven', 'have not', 'not yet')):
        return False
    return t == 'y' or t.startswith(_ACCEPT)

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
    #
    # Discord takes five questions on a form and no more, so the rules
    # question (#428) took the place of "Have you roleplayed before", which
    # now rides along in the character question's hint.
    'playtest': [
        AGE_Q,
        RULES_Q,
        ('Who do you want to play?',
         'A sentence about the character, and where you have roleplayed before, if anywhere.', True),
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
        # Checked again here, and counted here rather than on the panel, so a
        # form opened by mistake and cancelled costs nobody five minutes. See
        # TICKET_COOLDOWN for why there is a limit at all.
        no = ticket_refusal(interaction)
        if no:
            await interaction.response.send_message(no, ephemeral=True)
            return
        # Before the first await, so two forms sent in the same moment cannot
        # both get past the check above.
        _last_ticket[_ticket_key(interaction.guild, interaction.user)] = _now()
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

        # The rules answer, flagged the same way, and kept for the site's
        # record of who accepted them.
        rules = None
        if self.kind in RULES_KINDS:
            said = ''
            for item, (q, _, _) in zip(self.fields, QUESTIONS[self.kind]):
                if q == RULES_Q[0]:
                    said = (item.value or '').strip()
                    break
            rules = {'said': said[:200], 'yes': accepted_rules(said)}
            if not rules['yes']:
                detail = ('**CHECK THIS ONE.** Asked if they accept the rules they '
                          'said "%s".\n\n' % (said or 'nothing')) + detail

        title =('%s, %s' % (self.label_text, who.display_name))[:96]

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
            remember_ticket(guild, who, opened)
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

        # A ticket nobody can see is the same as no ticket, and a ticket
        # everybody can see is worse. If the thread could not be made, or could
        # not be written in, the whole ticket goes to the staff only log
        # channel instead, with the reason riding along so whoever reads it can
        # fix the cause without going to the VPS for a log.
        #
        # IT USED TO GO INTO THE PANEL CHANNEL, on the argument that the panel
        # channel was no more public than the thread. It was far more public. A
        # private thread is readable by the person who opened it and the staff
        # added to it; the panel channel is readable by everybody who can open
        # a ticket, which is the whole server. A report about somebody would go
        # up in front of the person it was about. From the To Do List: "A
        # reported member reading the report in the channel is a safety
        # problem, not a formatting one."
        #
        # log_channel checks the channel really is staff only before handing it
        # back. When there is no such channel, nothing goes into Discord at
        # all: the site inbox still gets the ticket below, and the person is
        # told by DM.
        fell_back = False
        if not posted:
            try:
                book = await log_channel(guild)
            except Exception:
                log('could not look for the staff only log channel:\n'
                    + traceback.format_exc())
                book = None
            if book is None:
                log('no staff only channel to put this ticket in, so Discord '
                    'has no copy of it. It goes to the site inbox only.')
            else:
                note = ''
                if why:
                    note = '\n_No private thread for this one: %s._' % why
                try:
                    await book.send(('**%s**\n%s%s' % (title, head, note))[:1900])
                    for chunk in _chunks(detail, 1900):
                        await book.send(chunk)
                    fell_back = True
                except Exception:
                    log('the ticket could not be posted in #%s either:\n'
                        % book.name + traceback.format_exc())

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

        # The site copy is bookkeeping, and nobody waits on it. It used to be
        # awaited here, before the reply, and push gives the site twelve
        # seconds to answer, so with the site down a stranger pressing Submit
        # watched the bot think for twelve seconds before hearing their ticket
        # was open. To Do List 253: "A spinner that sits for ten seconds reads
        # as broken to somebody who has never used the server, and the site
        # copy still lands." It is started here rather than after the replies
        # so that a reply Discord refuses cannot take the site copy with it.
        # push_async logs its own failure, so nothing is lost by not awaiting.
        task = asyncio.create_task(push_async(
            self.kind, '%s: %s' % (self.label_text, who.display_name),
            detail, str(who), who.id, rules))
        _pushes.add(task)
        task.add_done_callback(_pushes.discard)

        if posted:
            await interaction.followup.send(
                'Opened %s. Everything else goes in there.' % opened.mention,
                ephemeral=True)
        elif fell_back:
            await interaction.followup.send(
                'Sent. A private thread would not open, so it has gone straight '
                'to staff instead, somewhere only staff can read it. Somebody '
                'will answer you by message.',
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


# ------------------------------------------------------- one at a time --
# From the To Do List: "A public panel that auto-adds staff to every thread is
# otherwise a free way to ping every moderator fifty times a minute". One
# ticket is a thread, every member of every staff role added to it one at a
# time, a post that mentions them all and a row in the site inbox, and the
# panel sits in a channel everybody can see. Before this nothing counted any of
# it. So a person gets one open ticket at a time, and one new ticket every five
# minutes. Staff are held to neither.
TICKET_COOLDOWN = _int_env('TICKET_COOLDOWN', 300)

# When each person last sent one. In memory, so a restart forgets it, and that
# is fine for a cooldown. The one open ticket rule is the one that has to
# survive a restart, and it does not live here.
_last_ticket = {}

# Which thread is each person's open ticket. On disk beside the code, for the
# same reason as STAMP further down: the process restarts in a loop, and a rule
# that forgets on every restart is not a rule. The thread name cannot carry it,
# because the name is the label and a display name, and a display name is
# neither unique nor fixed.
OPEN_TICKETS = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            'open-tickets.json')


def _now():
    return time.monotonic()


def _ticket_key(guild, who):
    return '%s:%s' % (getattr(guild, 'id', 0), who.id)


def _open_tickets():
    try:
        with open(OPEN_TICKETS) as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except Exception:
        return {}


def _open_thread(guild, tid):
    """
    The thread, if it is still open, or None.

    get_thread reads the bot's own cache and asks Discord nothing, which
    matters on a click that has three seconds to be answered in. discord.py
    drops a thread from that cache the moment it is archived, and Close
    archives, so a closed ticket and a deleted one both come back None and
    the person is let through.
    """
    try:
        t = guild.get_thread(int(tid))
    except Exception:
        return None
    if t is None or getattr(t, 'archived', False):
        return None
    return t


def remember_ticket(guild, who, thread):
    """
    Write down that this thread is this person's open ticket.

    Entries for threads that are no longer open are dropped on the way, so the
    file stays the size of the queue rather than the size of everybody who
    ever asked for anything.
    """
    try:
        mine = '%s:' % getattr(guild, 'id', 0)
        keep = {}
        for k, v in _open_tickets().items():
            if k.startswith(mine) and _open_thread(guild, v) is None:
                continue
            keep[k] = v
        keep[_ticket_key(guild, who)] = thread.id
        with open(OPEN_TICKETS, 'w') as f:
            json.dump(keep, f)
    except Exception:
        log('could not write down which ticket %s has open, so they can open '
            'a second one:\n' % who + traceback.format_exc())


def ticket_refusal(interaction):
    """
    Why this person cannot open a ticket right now, in words, or None.

    Asked twice: when somebody picks from the panel, so they hear it before
    typing anything, and again when the form comes back, because the form can
    be opened several times before any of them is sent.

    Anything that goes wrong in here lets them through. A bug that refused
    every ticket would refuse every playtest application with it, and that is
    the only way in.
    """
    try:
        who = interaction.user
        guild = interaction.guild
        if guild is None or is_staff(who, interaction.channel):
            return None
        key = _ticket_key(guild, who)
        tid = _open_tickets().get(key)
        t = _open_thread(guild, tid) if tid else None
        if t is not None:
            return ('You already have a ticket open: %s. Say it in there and '
                    'staff will see it.' % t.mention)
        at = _last_ticket.get(key)
        if at is not None:
            left = TICKET_COOLDOWN - (_now() - at)
            if left > 0:
                mins = int((left + 59) // 60)
                return ('You have only just sent a ticket. You can send '
                        'another in %d minute%s.'
                        % (mins, '' if mins == 1 else 's'))
        return None
    except Exception:
        log('the ticket limit could not be checked, so this one was let '
            'through:\n' + traceback.format_exc())
        return None


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
        # Told here, before the form opens, so nobody types out a whole
        # application only to be turned away at the end of it.
        no = ticket_refusal(interaction)
        if no:
            await interaction.response.send_message(no, ephemeral=True)
            return
        k = self.values[0]
        lab = dict((a, b) for a, b, _ in KINDS)[k]
        await interaction.response.send_modal(TicketModal(k, lab))


_PANEL_TOP = ('**Open a ticket**\n\n'
              'Pick the one that fits. It asks a few questions, then opens a thread '
              'only you and staff can see. Nothing here is public and nobody else in '
              'the server can read it.\n\n')
_PANEL_JOBS = ('**Apply: Jarl** is '
               'answered in character: the seats are empty, and the first people to '
               'hold them are picked out of what is written there.\n\n'
               'The jobs below that are open to anybody already in, and they are jobs '
               'rather than titles: each one is work somebody is currently doing '
               'instead of you.\n\n'
               'Applying for one does not give you it. Somebody reads it and answers.')
PANEL_ALPHA = (_PANEL_TOP +
               'Thornswood is in alpha, and the world is open by application. Anyone '
               'can download it. **Apply to be an alpha playtester** is the one '
               'everybody starts with: once it is accepted you get the Playtester '
               'role, and that is what lets you press Play. It asks whether you are '
               '18 or over and whether you accept the rules, so read #rules first. '
               'Your answers are kept against your Discord account.\n\n' +
               _PANEL_JOBS)
PANEL_OPEN = (_PANEL_TOP +
              'Thornswood is open: anyone in the Discord can play, so there is '
              'nothing to apply for to get in. Read #rules, because being here '
              'and in the world means accepting them.\n\n' +
              _PANEL_JOBS)
PANEL = PANEL_ALPHA

# THE ONE SWITCH (#428), read off the site so there is one copy of it: the
# site's config.json "open", which /api/public hands out. Off, which is today,
# the panel is the alpha one above and the application asks the age and rules
# questions. On, anybody in the Discord can play, so the application goes from
# the panel, and with it the age and rules questions, which were only ever
# asked on the way in. THORNSWOOD_OPEN in bot.env.json overrides the site, for
# a dev bot or a site that is down. Read once, in setup_hook, before the panel
# view is registered; flipping it means restarting the bot.
KINDS_ALPHA = list(KINDS)
OPEN = False


def site_open():
    """Whether the world is open to everybody, from THORNSWOOD_OPEN when it is
       set and otherwise from the site. Anything that goes wrong answers no,
       the alpha, which is what is true until somebody flips the switch."""
    env = os.environ.get('THORNSWOOD_OPEN', '').strip().lower()
    if env in ('1', 'true', 'yes', 'open'):
        return True
    if env in ('0', 'false', 'no', 'alpha', 'closed'):
        return False
    try:
        with urllib.request.urlopen(SITE + '/api/public', timeout=8) as r:
            return json.loads(r.read().decode('utf-8')).get('open') is True
    except Exception as e:
        log('could not ask the site whether the world is open, so the panel is '
            'the alpha one:', e)
        return False


def set_open(on):
    """Point the panel, its kinds and the age and rules questions at one mode."""
    global OPEN, KINDS, AGE_KINDS, RULES_KINDS, PANEL
    OPEN = on is True
    KINDS = [k for k in KINDS_ALPHA if not (OPEN and k[0] == 'playtest')]
    AGE_KINDS = () if OPEN else ('playtest',)
    RULES_KINDS = AGE_KINDS
    PANEL = PANEL_OPEN if OPEN else PANEL_ALPHA


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
    bot/test-ready.py drives it with a made up message. The decision
    is the part worth pinning, because getting it wrong in either direction is
    a real fault: too eager and the panel is edited on every reconnect, too
    lazy and a ticket kind added later never appears for anybody.
    """
    return getattr(msg, 'content', None) == PANEL and _panel_options(msg) == _panel_wanted()


# Which servers staff have been told cannot open ticket threads, and why, so
# a reconnect does not tell them again.
_told_blocked = set()


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
        if book is not None:
            where = '#%s, which only staff can read' % book.name
        else:
            where = ('the site inbox and nowhere in Discord, because there is '
                     'no staff only channel to put it in')
        fix = ('%s. Tick it in that channel\'s permissions, or on the bot\'s '
               'role server wide. Until then every ticket goes to %s.'
               % (why, where))
        log('tickets in "%s" will NOT get a private thread: %s' % (guild.name, fix))

        # Said in the staff channel too, because the log is on the VPS and
        # nobody reads it until something is already wrong. Once per process:
        # this runs on every reconnect, and a flaky evening would say it ten
        # times.
        #
        # THE PANEL STAYS UP. The To Do List asked for the bot to refuse to
        # start here, "so the permission gets fixed before a stranger finds
        # out". With the fallback staff only there is nothing left for a
        # stranger to find. Refusing would not take the panel down either: the
        # posted one keeps answering through the view setup_hook registers.
        # All it would do is take away the one way to report somebody, on the
        # night that way is broken.
        if (guild.id, why) not in _told_blocked:
            _told_blocked.add((guild.id, why))
            await trouble_say('**Tickets cannot open a private thread:** ' + fix)
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


# ------------------------------------------------------ holds and pings --
#
# #choose-your-hold, where a Member picks the hold their character calls home
# and which announcements they want a ping for.
#
# The hold channels are private: each one is open to its own Citizen and Jarl
# roles and to staff, so picking a hold here is what opens its channel. One
# hold per person. Picking another takes the old Citizen role away, and
# pressing the one you already have leaves it. Jarl roles are never touched
# here; a Jarl is appointed, not picked.
#
# Only somebody with the Member role, or a staff role, can use it. The channel
# is hidden from everybody else already, and this is the second lock, so a
# button reached some other way still does nothing for somebody not yet in.
#
# The two ping roles are made if they are missing, and made not mentionable,
# so only staff who can already mention everyone can ping them.
HOLD_CHANNEL = [n.strip().lower() for n in
                os.environ.get('HOLD_CHANNEL', 'choose-your-hold').split(',')
                if n.strip()]
MEMBER_ROLE = os.environ.get('MEMBER_ROLE', 'Member').strip().lower()
HOLDS = ['Whiterun', 'Solitude', 'Windhelm', 'Riften', 'Markarth',
         'Dawnstar', 'Morthal', 'Falkreath', 'Winterhold']
# key, role name, button label
PINGS = [('news', 'News Pings', 'News pings'),
         ('updates', 'Updates Pings', 'Updates pings')]

HOLD_PANEL = ('**Choose your hold**\n\n'
              'Pick the hold your character calls home and its channel opens '
              'to you. One hold at a time: picking another moves you there, '
              'and pressing the one you have leaves it.\n\n'
              '**Pings**\n\n'
              'News pings you when a release goes out in #news. Updates pings '
              'you for restarts and notices in #updates. Press either again '
              'to stop.')


def _citizen(hold):
    return 'Citizen of ' + hold


def _role(guild, name):
    want = name.lower()
    for r in guild.roles:
        if r.name.lower() == want:
            return r
    return None


def _may_pick(member):
    names = set(r.name.lower() for r in getattr(member, 'roles', []))
    return MEMBER_ROLE in names or bool(names & set(STAFF))


def _can_give(guild, role):
    """
    Discord refuses a role at or above the bot's own highest role with a
    Forbidden and nothing else, so it is checked first and said in words.
    """
    me = guild.me
    return bool(me.guild_permissions.manage_roles) and role < me.top_role


async def _say(interaction, text):
    await interaction.response.send_message(text, ephemeral=True)


async def pick_hold(interaction, hold):
    guild, who = interaction.guild, interaction.user
    if guild is None or not _may_pick(who):
        await _say(interaction, 'Holds open once your application is approved '
                                'and you have the Member role.')
        return
    role = _role(guild, _citizen(hold))
    if role is None or not _can_give(guild, role):
        log('cannot give %s: the role is missing, or the bot has no Manage '
            'Roles, or its own role is not above it.' % _citizen(hold))
        await _say(interaction, 'That hold cannot be given out right now. Ask '
                                'staff to give it to you.')
        return
    try:
        if role in who.roles:
            await who.remove_roles(role, reason='Left their hold in #choose-your-hold')
            await _say(interaction, 'You are no longer a citizen of %s.' % hold)
            return
        old = [r for r in who.roles
               if r.name.lower().startswith('citizen of ') and r != role
               and _can_give(guild, r)]
        if old:
            await who.remove_roles(*old, reason='Moved hold in #choose-your-hold')
        await who.add_roles(role, reason='Picked in #choose-your-hold')
        said = 'You are now a citizen of %s. Its channel is open to you.' % hold
        if old:
            said += ' You are no longer a citizen of %s.' % ', '.join(
                r.name[len('Citizen of '):] for r in old)
        await _say(interaction, said)
    except Exception:
        log('hold pick failed:\n' + traceback.format_exc())
        await _say(interaction, 'That did not go through. Try again, or ask staff.')


async def toggle_ping(interaction, name):
    guild, who = interaction.guild, interaction.user
    if guild is None or not _may_pick(who):
        await _say(interaction, 'Pings open once your application is approved '
                                'and you have the Member role.')
        return
    role = _role(guild, name)
    if role is None or not _can_give(guild, role):
        log('cannot give %s: the role is missing, or the bot has no Manage '
            'Roles, or its own role is not above it.' % name)
        await _say(interaction, 'Pings cannot be changed right now. Ask staff.')
        return
    try:
        if role in who.roles:
            await who.remove_roles(role, reason='Turned off in #choose-your-hold')
            await _say(interaction, '%s off.' % name)
        else:
            await who.add_roles(role, reason='Turned on in #choose-your-hold')
            await _say(interaction, '%s on.' % name)
    except Exception:
        log('ping toggle failed:\n' + traceback.format_exc())
        await _say(interaction, 'That did not go through. Try again, or ask staff.')


class HoldButton(discord.ui.Button):
    def __init__(self, hold, row):
        super().__init__(label=hold, style=discord.ButtonStyle.secondary,
                         custom_id='thornswood:hold:' + hold.lower(), row=row)
        self.hold = hold

    async def callback(self, interaction):
        await pick_hold(interaction, self.hold)


class PingButton(discord.ui.Button):
    def __init__(self, key, name, label):
        super().__init__(label=label, style=discord.ButtonStyle.primary,
                         custom_id='thornswood:ping:' + key, row=2)
        self.role_name = name

    async def callback(self, interaction):
        await toggle_ping(interaction, self.role_name)


class HoldPanel(discord.ui.View):
    """Persistent, like the ticket panel, so the buttons outlive a restart."""
    def __init__(self):
        super().__init__(timeout=None)
        for i, hold in enumerate(HOLDS):
            self.add_item(HoldButton(hold, 0 if i < 5 else 1))
        for key, name, label in PINGS:
            self.add_item(PingButton(key, name, label))


def _hold_ids_wanted():
    return (['thornswood:hold:' + h.lower() for h in HOLDS] +
            ['thornswood:ping:' + k for k, _, _ in PINGS])


def _hold_ids(msg):
    ids = []
    try:
        for row in getattr(msg, 'components', None) or []:
            for item in getattr(row, 'children', None) or []:
                ids.append(getattr(item, 'custom_id', ''))
    except Exception:
        return []
    return ids


def hold_panel_is_current(msg):
    return (getattr(msg, 'content', None) == HOLD_PANEL and
            _hold_ids(msg) == _hold_ids_wanted())


async def ensure_hold_panel(guild):
    ch = by_name(guild, HOLD_CHANNEL)
    if ch is None:
        log('there is no #%s in "%s", so there is no hold panel. Set '
            'HOLD_CHANNEL in bot.env.json to the right channel.'
            % (HOLD_CHANNEL[0], guild.name))
        return

    missing = [_citizen(h) for h in HOLDS if _role(guild, _citizen(h)) is None]
    if missing:
        log('these hold roles are missing, so those buttons will say so: %s'
            % ', '.join(missing))

    for _, name, _ in PINGS:
        if _role(guild, name) is not None:
            continue
        if not guild.me.guild_permissions.manage_roles:
            log('there is no %s role and the bot cannot make one without '
                'Manage Roles.' % name)
            continue
        try:
            await guild.create_role(name=name, mentionable=False,
                                    reason='Ping role for #choose-your-hold')
            log('made the %s role' % name)
        except Exception:
            log('could not make %s:\n' % name + traceback.format_exc())

    try:
        async for m in ch.history(limit=30):
            if m.author.id == client.user.id and m.components:
                if hold_panel_is_current(m):
                    log('hold panel is already current in #%s' % ch.name)
                    return
                await m.edit(content=HOLD_PANEL, view=HoldPanel())
                log('hold panel updated in #%s' % ch.name)
                return
        await ch.send(HOLD_PANEL, view=HoldPanel())
        log('hold panel posted in #%s' % ch.name)
    except Exception:
        log('hold panel failed:\n' + traceback.format_exc())


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


def _clock(ms):
    """
    A unix-ms stamp as 'HH:MM on D Month', in this box's own time.

    The site stamps a session's start, end and a log's arrival with the same
    clock the server log uses, so a time named here reads the same as the
    lines on the sessions page.     fromtimestamp is local time, which is what the
    box runs on. %-d is not on Windows, where this runs, so the day is built by
    hand and carries no leading zero. Anything that is not a number, and 0
    itself (the site's stamp for a start or end it never saw), gives '', so a
    row without these fields drops the phrase rather than naming 1970.
    """
    try:
        n = int(ms)
    except (TypeError, ValueError):
        return ''
    if not n:
        return ''
    try:
        t = datetime.datetime.fromtimestamp(n / 1000)
    except (OSError, OverflowError, ValueError):
        return ''
    return '%02d:%02d on %d %s' % (t.hour, t.minute, t.day, t.strftime('%B'))


# A log that arrives within this long of the session ending is the launcher's
# own end-of-session upload, not a backlog, so its arrival is not called out.
TROUBLE_LATE_MS = 5 * 60 * 1000


def _trouble_line(row):
    """
    The staff-channel line for one session that went wrong.

    NAMES THE SESSION'S OWN TIME, not the moment the alert fires. Issue #532:
    a 401 held Patrick's 23 September logs until 14:09 the next day, when a
    newer launcher uploaded the backlog, and the alert read ~14:10 as if the
    crash had just happened. The session had started 20:07 the evening before.
    So the start is named, and when the logs arrived well after the session
    ended (a late upload, not the launcher's own end-of-session send) that is
    said too, so a backlog no longer looks like a fresh failure.

    A pure function of the row, so the harness can check the wording without a
    Discord, a clock or the file. A row with no start or end (older rows, or a
    session whose ends were never seen) simply drops those phrases.
    """
    who = row.get('name') or row.get('who') or 'somebody'
    where = row.get('channel') or ''
    where = {'dev': 'the dev build', 'main': 'the main build'}.get(
        where, 'a build it did not name')
    line = (row.get('line') or '').strip()

    started = _clock(row.get('start'))
    when = (' It started %s.' % started) if started else ''

    late = ''
    try:
        end = int(row.get('end') or 0)
        arrived = int(row.get('at') or 0)
    except (TypeError, ValueError):
        end = arrived = 0
    if end and arrived and arrived - end > TROUBLE_LATE_MS:
        got = _clock(arrived)
        if got:
            late = (' The logs did not arrive until %s, well after it ended, '
                    'so this is a late upload rather than a new failure.' % got)

    return (
        '**A session went wrong.** %s, on %s%s.%s%s\n%s\n%s\n'
        'The logs are on the sessions page under that session, '
        'and it is the red one.'
        % (who,
           where,
           (', launcher %s' % row['version']) if row.get('version') else '',
           when,
           late,
           row.get('why') or 'something went wrong',
           ('```\n%s\n```' % line[:400]) if line else ''))


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
                await trouble_say(_trouble_line(row))
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


# ------------------------------------------------------ the box's watchdog --
#
# Watch-Services.ps1 puts a watchdog on the VPS that restarts whatever stops
# answering, three times an hour at most, and then stops and writes that the
# service needs a look. That sentence went to watch.log on the box and nowhere
# else. From the To Do List: "the sentence it writes when it gives up
# currently goes to a file on the box that may itself be the thing that is
# gone". Nobody reads a log on the VPS until they already know something is
# wrong, so the one line written for a person was the one line no person saw.
#
# This reads that file and says the three lines that need a person, in the
# staff channel the site watcher uses, found by id through watch_say. Never a
# public channel: watch_say has no fallback to one.
#
#   needs a look          restarted three times this hour and still down
#   could not be started  Windows would not run the service's task
#   did not come back     restarted, and still not answering afterwards
#
# A file and not a webhook, for the same reason as watch_trouble: both run on
# this box, so there is no new secret to make, place or keep out of git.
#
# WHAT IT CANNOT CATCH is the box going down, or the bot being the thing that
# is down. Both take this with them. That needs something off the machine.

# How long with no line about a service before its next line is a new outage
# rather than more of the same one. The watchdog writes at least one line
# about every service that is down on every run, five minutes apart, give or
# take the minute or so a run spends restarting whatever it checks first. It
# writes nothing about a service that is up, so a gap of ten minutes is one run
# that found it answering, and seven and a half sits between the two.
#
# ONE CLEAN RUN IS ENOUGH, and it was twenty minutes until 24 September. A
# reviewer traced a fix made by hand that held for one run and then fell over
# again: the watchdog wrote "needs a look" ten minutes after its last line, the
# outage had never ended, and nobody was told for as long as it stayed down.
# The person who fixed it believed it was fixed. A fix by hand is the one way a
# service comes back with nothing written, so one run finding it up is all the
# evidence there will ever be.
WATCH_LOG_QUIET = int(7.5 * 60)

# How long "needs a look" stays said while the lines keep coming. A fix that
# falls over again inside five minutes leaves no gap at all, and without this
# it would be silent for as long as the service stayed down. Once an hour is a
# reminder, where every five minutes was the noise this whole thing avoids.
WATCH_LOG_REMIND = 60 * 60

# The watchdog's own words, from its Note() lines in Watch-Services.ps1, tried
# in this order. test-watch-services.py renders those lines out of that script
# and checks each one lands here, so changing the wording there fails a
# harness instead of quietly silencing this.
_WATCH_LINE = re.compile(r'^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\s+(\S.*?)\s*$')
_WATCH_KINDS = [
    ('look',    re.compile(r'^(.+?) is still down after (\d+) restarts this hour\..*needs a look')),
    ('refused', re.compile(r'^(.+?) could not be started\.')),
    ('stuck',   re.compile(r'^(.+?) did not come back in time')),
    ('trying',  re.compile(r'^(.+?) is not answering\. Starting ')),
    ('back',    re.compile(r'^(.+?) is back$')),
]


def _watch_log_message(kind, name, hit, line, since=None):
    """
    What is said for one watchdog line, with the line itself under it.

    since is how many minutes ago "needs a look" was last said for this
    service, when this is the hourly reminder of it, and None otherwise.
    """
    who = name[:1].upper() + name[1:]
    if kind == 'look' and since is not None:
        head = ('**%s still needs a look.** That was said here %d minutes ago, '
                'and the watchdog has found it down on every run since and is '
                'still leaving it. If somebody worked on it in that time, it '
                'did not stay up. This is said again every hour it stays down.'
                % (who, since))
    elif kind == 'look':
        head = ('**%s is down and the watchdog has stopped restarting it.** It '
                'was restarted %s times this hour and would not stay up, so it '
                'needs a person. The watchdog writes this to watch.log every '
                'five minutes while it stays down, and it is said here again '
                'every hour.'
                % (who, hit.group(2)))
    elif kind == 'refused':
        head = ('**%s could not be started.** The watchdog on the VPS found it '
                'not answering and Windows would not run its task, which '
                'usually means the task is missing or was renamed.' % who)
    else:
        head = ('**%s did not come back after a restart.** The watchdog on the '
                'VPS found it not answering, started it, and it was still not '
                'answering when it looked again. It tries every five minutes, '
                'three times an hour at most, and says so here if it gives up.'
                % who)
    return ('%s\n```\n%s\n```' % (head, line[:400]))[:1900]


def watch_log_news(lines, state):
    """
    The messages to send for these new watch.log lines, in order.

    state carries what has been said about each service from one call to the
    next. Pass the same dict every time, starting from an empty one.

    ONCE PER OUTAGE, per service and per kind of line. A service that will not
    stay up gets "did not come back" on each of its three restarts an hour and
    "needs a look" on every run after that, every five minutes. Said every
    time, one broken service is twelve messages an hour and the channel stops
    being read, which is the same as nobody being told. So each kind is said
    the first time in an outage and not again until the outage ends. It ends
    when the watchdog writes that the service is back, or when WATCH_LOG_QUIET
    passes with no line about it at all, because the watchdog writes about a
    service that is down on every run and writes nothing about one that is up.

    AND "NEEDS A LOOK" AGAIN EVERY WATCH_LOG_REMIND while the lines keep
    coming. A fix made by hand that falls over before the watchdog's next run
    leaves no gap to end the outage on, so this is what stops that being
    silence for as long as the service is down.

    No file, no Discord, and no clock but the times in the log itself, so the
    harness can drive it one line at a time.
    """
    last = state.setdefault('last', {})
    # Per service, each kind already said in this outage and the log time it
    # was said at.
    said = state.setdefault('said', {})
    out = []
    for raw in lines:
        m = _WATCH_LINE.match(raw or '')
        if not m:
            continue
        try:
            when = datetime.datetime.strptime(m.group(1), '%Y-%m-%d %H:%M:%S')
        except ValueError:
            continue
        for kind, rx in _WATCH_KINDS:
            hit = rx.match(m.group(2))
            if hit:
                break
        else:
            continue
        name = hit.group(1)
        before = last.get(name)
        last[name] = when
        # abs, because the only way a line is older than the one before it is
        # the box's clock going back, and that is better said again than taken
        # for the same outage with the reminder an hour further off.
        if (kind == 'back' or before is None
                or abs((when - before).total_seconds()) > WATCH_LOG_QUIET):
            said[name] = {}
        if kind not in ('look', 'refused', 'stuck'):
            continue
        done = said.setdefault(name, {})
        since = None
        if kind in done:
            if kind != 'look':
                continue
            gone = (when - done[kind]).total_seconds()
            if gone < WATCH_LOG_REMIND:
                continue
            since = int(gone // 60)
        done[kind] = when
        out.append(_watch_log_message(kind, name, hit, raw.strip(), since))
    return out


def _watch_log_lines():
    """
    Every whole line in watch.log, or None when it could not be read.

    No file is an empty list, because that is the normal state of a quiet box:
    the watchdog writes nothing until something goes down. Any other failure
    is None, and the loop skips that round rather than reading an unreadable
    file as an empty one.

    A last line with no line ending is left for the next read. Add-Content may
    be halfway through it, and half a line said now is the whole line said
    again a minute later.
    """
    try:
        with open(WATCH_LOG, 'rb') as f:
            data = f.read()
    except FileNotFoundError:
        return []
    except Exception:
        return None
    # utf-8-sig because the watchdog trims the file with Set-Content -Encoding
    # UTF8, which on Windows PowerShell puts a byte order mark first.
    parts = data.decode('utf-8-sig', errors='replace').split('\n')
    return [p.rstrip('\r') for p in parts[:-1] if p.strip()]


async def watch_services():
    """
    Read the watchdog's log every WATCH_LOG_EVERY seconds and say what needs a
    person.

    WHAT IT REMEMBERS AND WHY. The lines already in the file when this starts
    are treated as said, the same as watch_trouble, or every restart of the
    bot would say the last thousand again. They still go through
    watch_log_news, so an outage that was already under way is known to be one
    and its repeats stay quiet.

    Lines are remembered by their text, time and all, and not by where they
    sit in the file, because the watchdog cuts the file to its last thousand
    lines when it passes two thousand and every position moves.

    Nothing in here may end the loop, for the same reason as the site watcher:
    a watcher that dies quietly looks exactly like everything being fine.
    """
    await client.wait_until_ready()
    loop = asyncio.get_running_loop()
    state = {}
    seen = None
    unreadable = False
    log('services: reading %s every %ds, speaking in channel %d'
        % (WATCH_LOG, WATCH_LOG_EVERY, WATCH_ID))

    while not client.is_closed():
        try:
            lines = await loop.run_in_executor(None, _watch_log_lines)
            if lines is None:
                if not unreadable:
                    log('services: could not read %s, trying again every %ds'
                        % (WATCH_LOG, WATCH_LOG_EVERY))
                unreadable = True
            elif seen is None:
                unreadable = False
                seen = set(lines)
                watch_log_news(lines, state)
                log('services: %d line(s) already in the log, treated as said'
                    % len(lines))
            else:
                unreadable = False
                new = [l for l in lines if l not in seen]
                seen.update(new)
                # The file never holds more than two thousand lines, so this
                # only has to remember what could still be in it.
                if len(seen) > 10000:
                    seen = set(lines)
                for text in watch_log_news(new, state):
                    log('services: saying ' + text.split('\n', 1)[0])
                    await watch_say(text)
        except Exception:
            log('services: the check itself failed, carrying on:\n'
                + traceback.format_exc())
        await asyncio.sleep(WATCH_LOG_EVERY)


def report_text(row):
    """
    One report from the public page, as the staff channel reads it.

    Every word of it was typed by a stranger with no account, so it is escaped
    before it goes anywhere near Discord: an @everyone in a title is text, not
    a ping, and a masked link is shown as what it is.
    """
    def clean(v, n):
        v = str(v or '').strip()[:n]
        return discord.utils.escape_mentions(discord.utils.escape_markdown(v))

    by = clean(row.get('by'), 40)
    detail = clean(row.get('detail'), 400)
    kind = row.get('kind')

    # From inside the game (#414): /helpme and /report. The profile ids in
    # the detail are the client's claim, and the detail says so. A report
    # about somebody never pings: the send switches every mention off.
    if str(row.get('from') or '').startswith('in game'):
        where = ' on the dev server' if 'dev' in str(row.get('from')) else ''
        if kind == 'help':
            head = '**%s asked for help in game%s**' % (by or 'Somebody', where)
        else:
            head = ('**%s reported %s in game%s**'
                    % (by or 'Somebody', clean(row.get('about'), 60) or 'somebody',
                       where))
        return '%s\n%s%s' % (head, clean(row.get('title'), 300) or '(nothing said)',
                             ('\n' + detail) if detail else '')

    # A report about a person from the site, which the site only takes from
    # somebody signed in with Discord, so it always has a name and an account.
    if kind == 'report':
        acct = str(row.get('discordId') or '')
        return ('**%s reported %s on the site**%s.\n%s%s'
                % (by or 'Somebody', clean(row.get('about'), 60) or 'somebody',
                   (' (Discord <@%s>)' % acct) if acct.isdigit() else '',
                   clean(row.get('title'), 200) or '(no title)',
                   ('\n' + detail) if detail else ''))

    kind = 'An idea' if kind == 'idea' else 'A problem'
    return ('**%s sent in on the public report page**, %s.\n%s%s'
            % (kind,
               ('from ' + by) if by else 'with no name left',
               clean(row.get('title'), 200) or '(no title)',
               ('\n' + detail) if detail else ''))


async def report_say(text):
    """Same channel as trouble_say, with every mention switched off."""
    ch = _trouble_channel()
    if ch is None:
        return
    try:
        await ch.send(text[:1900], suppress_embeds=True,
                      allowed_mentions=discord.AllowedMentions.none())
    except Exception:
        log('reports: could not post in #%s:\n' % getattr(ch, 'name', '?')
            + traceback.format_exc())


async def watch_reports():
    """
    Say in the staff channel when somebody sends something in on the public
    report page.

    The page tells them "Somebody will read it", and until this the only place
    it could be read was the inbox on the hub, which nobody opens unless they
    already know something is there, and the To Do List has the hub going
    altogether. The site writes inbox.json on this same box, so this reads it
    the way watch_trouble reads trouble.json.

    Tickets are in that file as well and are left alone: they came from
    Discord, and their thread is already where staff read them.

    The ids already there when this starts are treated as said, for the same
    reason as watch_trouble. A file that is on disk but will not parse, which
    is what a read in the middle of the site writing it looks like, is waited
    out rather than read as empty, because empty would make every row in it
    new on the next look.
    """
    await client.wait_until_ready()

    def read_all():
        try:
            with open(REPORTS_FILE, encoding='utf-8') as f:
                rows = json.load(f)
        except FileNotFoundError:
            return []
        except Exception:
            return None
        return rows if isinstance(rows, list) else None

    def public(row):
        return (isinstance(row, dict) and bool(row.get('id'))
                and row.get('kind') != 'ticket')

    loop = asyncio.get_running_loop()
    rows = await loop.run_in_executor(None, read_all)
    while rows is None:
        await asyncio.sleep(5)
        rows = await loop.run_in_executor(None, read_all)
    said = set(row['id'] for row in rows if public(row))
    ch = _trouble_channel()
    log('reports: watching %s every %ds, speaking in %s, %d already there and '
        'treated as said'
        % (REPORTS_FILE, REPORTS_EVERY,
           ('#' + ch.name) if ch is not None else 'NOWHERE, see above',
           len(said)))

    while not client.is_closed():
        try:
            rows = await loop.run_in_executor(None, read_all)
            fresh = [r for r in (rows or []) if public(r) and r['id'] not in said]
            for r in fresh:
                said.add(r['id'])
            if len(fresh) > REPORTS_AT_ONCE:
                await report_say(
                    '**%d reports came in, from the site and the game,** since the '
                    'last look, which is more than people send and more than '
                    'this channel should carry one at a time. They are in the '
                    'inbox on the site.' % len(fresh))
            else:
                # The file is newest first; the channel reads oldest first.
                for r in reversed(fresh):
                    await report_say(report_text(r))
        except Exception:
            log('reports: the check itself failed, carrying on:\n'
                + traceback.format_exc())
        await asyncio.sleep(REPORTS_EVERY)


# ------------------------------------------------------ staff in the world --
#
# What a moderator did in the game (#412): /kick, /freeze, /silence, /warn and
# the rest. The gamemode appends one JSON line per action to
# private\moderation.log beside each game server, on this same box, and this
# says each new line once in the staff channel, so the record is outside the
# game and in front of the rest of staff. A file rather than a request, for the
# same reason as watch_trouble: no new secret, port or ticket.
MODERATION_LOGS = [
    ('live', os.environ.get('MODERATION_LOG',
                            r'C:\Thornswood-Server\private\moderation.log')),
    ('dev', os.environ.get('MODERATION_LOG_DEV',
                           r'C:\Thornswood-Server-Dev\private\moderation.log')),
    # Bans and notes made on the hub, which the site writes beside
    # trouble.json. The game's own /ban and /note are in the two above.
    ('site', os.environ.get('MODERATION_LOG_SITE',
                            os.path.join(os.path.dirname(TROUBLE_FILE), 'moderation.log'))),
]
MODERATION_EVERY = _int_env('MODERATION_EVERY', 30)
# More than this in one look from one server is said as a count, not a wall.
MODERATION_AT_ONCE = 10

_MOD_DID = {
    'kick': 'removed %s from the world',
    'freeze': 'froze %s in place',
    'unfreeze': 'let %s move again',
    'bring': 'brought %s to them',
    'goto': 'went to %s',
    'silence': 'silenced %s',
    'unsilence': 'let %s speak again',
    'warn': 'warned %s',
    'give': 'gave %s',
    'spawn': 'spawned beside %s',
    'tp': 'sent %s',
    # One character, or the whole account, and a character killed for good (#1010).
    'ban': 'banned the character %s',
    'unban': 'lifted the ban on the character %s',
    'banaccount': 'banned the whole account of %s, every character on it',
    'unbanaccount': 'lifted the ban on the account of %s',
    'pk': 'killed %s for good (PK), quietly',
    'note': 'wrote a note on %s',
    # Not staff: somebody's own /stuck (#414), said as its why reads.
    'stuck': 'used /stuck',
}


def moderation_text(where, row):
    """
    One line of moderation.log as the staff channel reads it, or None for a
    line that is not one. Names and reasons were typed in the game, so they
    are escaped: nothing in them can ping anybody or dress itself up.
    """
    if not isinstance(row, dict) or row.get('did') not in _MOD_DID:
        return None

    def clean(v, n):
        v = str(v or '').strip()[:n]
        return discord.utils.escape_mentions(discord.utils.escape_markdown(v))

    def person(name, pid):
        try:
            pid = int(pid)
        except (TypeError, ValueError):
            pid = 0
        # The hub knows a person by account, not by profile.
        if pid <= 0:
            return clean(name, 40) or 'somebody'
        return '%s (profile %d)' % (clean(name, 40) or 'somebody', pid)

    # /stuck is not a staff action: the person did it to themselves, and the
    # gamemode writes the whole sentence (from where, to where, the account).
    if row['did'] == 'stuck':
        why = clean(row.get('why'), 600) or 'used /stuck.'
        return ('**/stuck on the %s server:** %s %s'
                % (where, person(row.get('byName'), row.get('by')), why))[:1900]

    did = _MOD_DID[row['did']] % person(row.get('whoName'), row.get('who'))
    try:
        minutes = int(row.get('minutes') or 0)
    except (TypeError, ValueError):
        minutes = 0
    if row['did'] == 'silence' and minutes > 0:
        did += ' for %d minute%s' % (minutes, '' if minutes == 1 else 's')
    why = clean(row.get('why'), 300)
    head = ('**Staff on the site:**' if where == 'site'
            else '**Staff on the %s server:**' % where)
    return ('%s %s %s%s'
            % (head, person(row.get('byName'), row.get('by')), did,
               (': ' + why) if why else '.'))[:1900]


def _moderation_lines(path):
    """
    Every whole line in one moderation.log, [] when there is no file yet (no
    staff action on that server so far), None when it could not be read. A
    last line with no line ending is left for the next look, the same as
    _watch_log_lines.
    """
    try:
        with open(path, 'rb') as f:
            data = f.read()
    except FileNotFoundError:
        return []
    except Exception:
        return None
    parts = data.decode('utf-8-sig', errors='replace').split('\n')
    return [p.rstrip('\r') for p in parts[:-1] if p.strip()]


async def watch_moderation():
    """
    Say each new staff action from the game in the staff channel, once.

    The lines already in each file when this starts are treated as said, as in
    watch_trouble, or every restart of the bot would repeat the history. A
    file that cannot be read is skipped for that look rather than read as
    empty. Nothing in here may end the loop.
    """
    await client.wait_until_ready()
    loop = asyncio.get_running_loop()
    seen = {}
    for where, path in MODERATION_LOGS:
        lines = await loop.run_in_executor(None, _moderation_lines, path)
        seen[where] = set(lines) if lines is not None else None
    log('moderation: reading %s every %ds'
        % (', '.join(p for _, p in MODERATION_LOGS), MODERATION_EVERY))

    while not client.is_closed():
        try:
            for where, path in MODERATION_LOGS:
                lines = await loop.run_in_executor(None, _moderation_lines, path)
                if lines is None:
                    continue
                if seen.get(where) is None:
                    seen[where] = set(lines)
                    continue
                new = [l for l in lines if l not in seen[where]]
                seen[where].update(new)
                texts = []
                for l in new:
                    try:
                        text = moderation_text(where, json.loads(l))
                    except ValueError:
                        text = None
                    if text:
                        texts.append(text)
                if len(texts) > MODERATION_AT_ONCE:
                    await report_say(
                        '**%d staff actions on %s** since the last look, more '
                        'than this channel should carry one at a time. They '
                        'are in %s on the VPS.'
                        % (len(texts),
                           'the site' if where == 'site' else 'the %s server' % where,
                           path))
                else:
                    for text in texts:
                        await report_say(text)
        except Exception:
            log('moderation: the check itself failed, carrying on:\n'
                + traceback.format_exc())
        await asyncio.sleep(MODERATION_EVERY)


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
        asyncio.create_task(watch_services())
        asyncio.create_task(watch_reports())
        asyncio.create_task(watch_moderation())

    log('up as %s' % client.user)

    await register_commands()

    for g in client.guilds:
        await ensure_panel(g)
        await ensure_hold_panel(g)
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
