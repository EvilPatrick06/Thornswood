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
  Services posts in the staff channel what the VPS watchdog says has died
           and when it is back, from its outbox, once each (issue #447)
  Reports  says each thing sent in on the site's public report page in the
           staff channel, the day it arrives
  Holds    a panel in #choose-your-hold where a Member picks their hold
           and which announcements ping them
  Testing  #known-issues is a forum with one post per open GitHub issue
           labelled Dev Findings or Main Findings; the post goes when the
           issue is closed, which is when its fix is on main. #test-tasks is a
           forum of test tasks: one for each issue closed as fixed (its "Test
           task:" comment), always tagged Main, because main is where testers
           test, plus any posted by hand, tagged Main (/test-task,
           python bot.py --post-task). #dev-test-tasks, a staff only forum
           in Staff, holds the test tasks whose comment says "Server: Dev":
           a measurement someone on dev has to take, open issue or closed.
           The channels get there once, by hand, with
           python bot.py --setup-channels [--apply] (the testing channels
           section below)
  Heartbeat writes heartbeat.json beside this file every minute, so the
           watchdog can tell a bot that is running from one that is on
           Discord (issue #449)
  Uptime   pings an outside monitor every minute while it is on Discord, so
           a bot or a VPS that stops is noticed from outside the box (#449)

Everything it needs is in env:

  DISCORD_TOKEN    the bot token
  THORNSWOOD_SITE  https://thornswood.net
  THORNSWOOD_KEY   shared secret the site checks on /api/ticket
  JOIN_CHANNEL     name of the channel join cards go in, default general
  TICKET_CHANNEL   public channel the panel lives in, comma separated, first wins
  TICKET_LOG       staff only channel closed tickets are recorded in, and where
                   a ticket goes when its thread will not open. Checked by its
                   permissions, never trusted by its name
  STAFF_ROLES      comma separated role IDs (preferred) or names, who gets
                   pulled into every ticket thread
  CREATOR_ROLES    comma separated role IDs or names, added to Apply:
                   Content Creator only
  TICKET_COOLDOWN  seconds between one person's tickets, default 300
  WATCH_CHANNEL_ID id of the staff channel the watchdog's messages go in,
                   default whatever dev-channel.txt beside this file holds
  WATCH_DIR        the watchdog's folder, default the one Watch-Services.ps1
                   makes on the VPS
  WATCH_READ_EVERY seconds between reads of its outbox, default 60
  HOLD_CHANNEL     channel the hold panel lives in, default choose-your-hold
  MEMBER_ROLE      role ID (preferred) or name that may pick a hold, default Member
  TEST_TASK_ROLES  comma separated role IDs (preferred) or names, who may
                   post a test task, default Owner,Dev,Lead Gamemaster,Lead GM
  TEST_TASKS_CHANNEL, TEST_FINDINGS_CHANNEL, KNOWN_ISSUES_CHANNEL
                   default test-tasks, test-findings, known-issues
  DEV_TASKS_CHANNEL   the staff forum of dev test tasks, default dev-test-tasks
  DEV_TASKS_CATEGORY  id of the category it is made in, default the Staff
                      category, 1549254990110134374
  GITHUB_TOKEN     read only token for the repository's issues. A secret, set
                   only in bot.env.json. Not set means no #known-issues posts
  KNOWN_ISSUES_REPO   default EvilPatrick06/Thornswood
  KNOWN_ISSUES_LABELS default Dev Findings,Main Findings
  KNOWN_ISSUES_EVERY  seconds between GitHub reads, default 300, never under 60
  HEARTBEAT_FILE   where the heartbeat goes, default heartbeat.json beside this
                   file, which is where the watchdog reads it
  HEARTBEAT_EVERY  seconds between heartbeats, default 60
  PING_URL         the outside monitor's ping address. A secret, set only by
                   Install-Bot.ps1 -SetPing and never written to the log. Not
                   set means no ping
  PING_EVERY       seconds between pings, default 60
  PING_TIMEOUT     seconds one ping may take, default 10

It is written to keep going when a piece of it fails. A card that will not
draw still gets a greeting, a site that is down still gets a thread, and a
thread that cannot be made still gets an answer to the person who asked.
"""
# First, before anything else: Python 3.10 or newer, or a plain message
# saying so (#2276). Shared with every bot test.
import _pyguard  # noqa: F401
import asyncio
import datetime
import json
import os
import re
import ssl
import time
import traceback
import sys
import typing
import urllib.parse
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


def _load_env_file(argv):
    """
    --env-file PATH: read bot.env.json into the environment before anything
    below reads it, so the one-time setup and --post-task can be run by hand
    on the VPS with the service's settings. The service never passes it.
    """
    if '--env-file' not in argv:
        return
    at = argv.index('--env-file')
    with open(argv[at + 1], encoding='utf-8-sig') as f:
        for k, v in json.load(f).items():
            os.environ[str(k)] = str(v)


if __name__ == '__main__':
    _load_env_file(sys.argv)

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
# Tokens may be Discord role snowflake IDs (digits) or names. IDs survive a
# rename; names are kept so an unmigrated bot.env.json still works.
_STAFF_RAW = [r.strip() for r in
              os.environ.get('STAFF_ROLES', 'Owner,Gamemaster,Dev,Loremaster,Moderator').split(',')
              if r.strip()]

# Roles that see one kind of ticket and not the rest.
#
# Content Creator is not general staff: that role is for social media, and it
# has no reason to be reading somebody's playtest application or a report about
# another person. It does have every reason to read applications to join it,
# so it is added to those threads and no others.
_CREATOR_RAW = [r.strip() for r in
                os.environ.get('CREATOR_ROLES', 'Content Creator').split(',')
                if r.strip()]

def _role_tokens(raw):
    ids, names = set(), set()
    for t in raw:
        t = (t or '').strip()
        if not t:
            continue
        if t.isdigit():
            ids.add(int(t))
        else:
            names.add(t.lower())
    return ids, names

def _role_hit(role, ids, names):
    return getattr(role, 'id', None) in ids or role.name.lower() in names

def _who_hits(who, ids, names):
    for r in getattr(who, 'roles', None) or []:
        if _role_hit(r, ids, names):
            return True
    return False

def _guild_roles(guild, ids, names):
    return [r for r in guild.roles if _role_hit(r, ids, names)]

STAFF_IDS, STAFF_NAMES = _role_tokens(_STAFF_RAW)
CREATOR_IDS, CREATOR_NAMES = _role_tokens(_CREATOR_RAW)
# Name-only views kept for refusal text and older harnesses that read STAFF.
STAFF = sorted(STAFF_NAMES) if STAFF_NAMES else [t.lower() for t in _STAFF_RAW if not t.isdigit()]
CREATOR = sorted(CREATOR_NAMES) if CREATOR_NAMES else [t.lower() for t in _CREATOR_RAW if not t.isdigit()]
EXTRA_STAFF = {'creator': CREATOR}
EXTRA_STAFF_IDS = {'creator': (CREATOR_IDS, CREATOR_NAMES)}


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

# The bot's own records, joins.json, open-tickets.json, heartbeat.json and
# commands-synced.json, go in a folder of their own, data beside bot.py, and
# so does bot.log, which the service writes (issue #1104). The service's
# account may write there and nowhere else in the bot's folder: the code is
# read only to it, so nothing that gets into the bot can rewrite bot.py or put
# a module beside it for the next start to import. The service names the
# folder in THORNSWOOD_BOT_DATA (BotService.cs). With no data folder yet, a
# box whose full install has not run since, the records stay beside bot.py
# where they were, so a code only deploy never starts the join numbers again;
# the full install moves them across while the bot is stopped (Bot-Service.ps1).
HERE = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.environ.get('THORNSWOOD_BOT_DATA') or (
    os.path.join(HERE, 'data') if os.path.isdir(os.path.join(HERE, 'data')) else HERE)

# Where the site writes the sessions that went wrong. The bot and the site run
# on the same box, so this is a file rather than a request: no ticket, no port
# and nothing to keep in step. In for-bot, a folder of the site's data that
# holds only what the site writes for the bot, so the bot's account is granted
# read on that and never on the site's own records, sessions.json among them
# (issue #1102).
TROUBLE_FILE = os.environ.get(
    'TROUBLE_FILE', r'C:\Thornswood-Docs\data\for-bot\trouble.json')
TROUBLE_EVERY = _int_env('TROUBLE_EVERY', 120)

# Where the site writes what people send in on its public report page, read
# the same way as trouble.json and said in the same staff channel.
REPORTS_FILE = os.environ.get(
    'REPORTS_FILE', r'C:\Thornswood-Docs\data\for-bot\inbox.json')
REPORTS_EVERY = _int_env('REPORTS_EVERY', 120)
# More than this many in one look is a script, not five people, because the
# site takes five an hour from any one place. Then one line says how many.
REPORTS_AT_ONCE = 5


# The folder the watchdog Watch-Services.ps1 puts on the VPS. The bot runs on
# the same box, as its own service account, which Install-Bot.ps1 grants read
# on this folder and write on alerts-sent-bot.txt (Bot-Service.ps1).
WATCH_DIR = os.environ.get('WATCH_DIR', r'C:\Thornswood-Watch')
# Once a minute. The watchdog itself runs every five and gives this two and a
# half minutes to post a message before it posts it through its webhook.
WATCH_READ_EVERY = _int_env('WATCH_READ_EVERY', 60)

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
        # First, so a site that is slow to answer below cannot delay it.
        asyncio.create_task(heartbeat())      # for the watchdog, #449
        asyncio.create_task(uptime_ping())    # for the outside monitor, #449
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


def as_typed(v, n=1000):
    """
    Words somebody else typed, as Discord will show them and no more.

    Everything a stranger writes goes through this before it is posted: an
    @everyone in it is text rather than a ping, a role id is text, and
    markdown in it is shown as it was typed instead of being read as
    formatting. It trims the ends and cuts at n characters first, so one long
    answer cannot take a post over Discord's limit on its own.

    The send that carries the text still switches mentions off (see the ticket
    thread and report_say). This is the first of the two, not the only one: a
    mention Discord learns to write differently tomorrow would get past the
    escaping and still not ping anybody.
    """
    v = str(v or '').strip()[:n]
    return discord.utils.escape_mentions(discord.utils.escape_markdown(v))


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
        if ch.permissions_for(guild.default_role).view_channel:
            return False
        roles = list(guild.roles)
        for r in roles:
            if r == guild.default_role or _role_hit(r, STAFF_IDS, STAFF_NAMES):
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
            if ow.view_channel and not _who_hits(who, STAFF_IDS, STAFF_NAMES):
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
            if _role_hit(r, STAFF_IDS, STAFF_NAMES):
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
JOINS = os.path.join(DATA_DIR, 'joins.json')
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
    ('company',     'Apply: Trading Company', 'Haul, make, sell and buy for the Free Skyrim Trading Company. In character.'),
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
    'company':    'Trading Company',
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
    # The Free Skyrim Trading Company (#1393, docs/systems/trading-company.md).
    # The same shape as a Jarl's: answered in character, and the role it
    # leads to is what lets a character handle a company sale in the game.
    'company': [
        ('Who is your character?',
         'Name, where they come from, what they have been doing until now. In character.', True),
        ('What would they do for the company?',
         'Haul, make, sell or buy, and what goods. Answer as them, not as you.', True),
        ('How much time can you give it?', 'Hours a week, and which days.', True),
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

        asking = ROLE_FOR.get(self.kind)

        def answered(want):
            """What they typed in the question that reads exactly like this."""
            for item, (q, _, _) in zip(self.fields, QUESTIONS[self.kind]):
                if q == want:
                    return (item.value or '').strip()
            return ''

        age_said = answered(AGE_Q[0]) if self.kind in AGE_KINDS else ''

        # The rules answer, kept for the site's record of who accepted them.
        rules = None
        rules_said = ''
        if self.kind in RULES_KINDS:
            rules_said = answered(RULES_Q[0])
            rules = {'said': rules_said[:200], 'yes': accepted_rules(rules_said)}

        def written(clean):
            lines = []
            for item, (q, _, _) in zip(self.fields, QUESTIONS[self.kind]):
                lines.append('**%s**\n%s'
                             % (q, clean((item.value or '').strip()) or 'nothing said'))
            out = '\n\n'.join(lines)
            if asking:
                out = '**Asking for:** ' + asking + '\n\n' + out
            # Anything that does not read as a yes says so at the top, in words,
            # on the line staff read first. It never stops the ticket: losing
            # somebody's application over how they phrased one answer would be
            # worse than a person spending two seconds reading it.
            if self.kind in AGE_KINDS and not said_yes(age_said):
                out = ('**CHECK THIS ONE.** Asked if they are 18 or over they '
                       'said "%s".\n\n' % (clean(age_said) or 'nothing')) + out
            if rules is not None and not rules['yes']:
                out = ('**CHECK THIS ONE.** Asked if they accept the rules they '
                       'said "%s".\n\n' % (clean(rules_said) or 'nothing')) + out
            return out

        # Two copies of the same ticket, because the two places that take it
        # protect themselves differently (#1354).
        #
        # detail is as they typed it, for the site, which escapes its own
        # output and whose inbox is the record of what they really wrote.
        #
        # shown is what goes into Discord, where their words would otherwise be
        # read as formatting and as mentions. Before this, an answer of
        # "@everyone" pinged the server from inside a staff thread, a role
        # mention pulled a role into it, and a few asterisks could hide the
        # rest of the application behind a heading. The questions and the
        # CHECK THIS ONE line are ours and stay bold; nothing of theirs does.
        detail = written(lambda v: v)
        shown = written(as_typed)

        title =('%s, %s' % (self.label_text, who.display_name))[:96]

        # Mentioning a role does not put anybody in a private thread. Only
        # people who have been added to one can see it, so a ticket opened
        # without this was visible to the applicant and to nobody else, and the
        # @mention went into a room staff were not in. They are added one at a
        # time, which is the only way Discord offers.
        ids, names = set(STAFF_IDS), set(STAFF_NAMES)
        extra = EXTRA_STAFF_IDS.get(self.kind)
        if extra:
            ids |= extra[0]
            names |= extra[1]
        staff_roles = [r for r in guild.roles if _role_hit(r, ids, names)]
        if not staff_roles:
            log('no role matched ids %r or names %r, so nobody will be pulled '
                'into this ticket. Set STAFF_ROLES in bot.env.json to the role '
                'ids or names this server actually uses.'
                % (sorted(ids), sorted(names)))
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
                # The head is ours and is the one post meant to ping: the
                # person who opened the ticket, and each staff role, by id.
                # Not @everyone, which nothing this bot writes ever says.
                await opened.send(head[:1900], view=TicketTools(),
                                  suppress_embeds=True,
                                  allowed_mentions=discord.AllowedMentions(
                                      everyone=False, users=True, roles=True))
                # Their words. Escaped above, with every mention switched
                # off here as well, and embeds suppressed so a bare link
                # cannot draw its preview. Anything the escaping misses
                # still pings nobody.
                for chunk in _chunks(shown, 1900):
                    await opened.send(chunk,
                                      suppress_embeds=True,
                                      allowed_mentions=discord.AllowedMentions.none())
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
                    # The display name in the title is theirs as well, so it
                    # is escaped here the way the answers are. The thread name
                    # above is a name rather than a post and keeps it as it is.
                    await book.send(
                        ('**%s**\n%s%s' % (as_typed(title, 96), head, note))[:1900],
                        suppress_embeds=True,
                        allowed_mentions=discord.AllowedMentions(
                            everyone=False, users=True, roles=True))
                    for chunk in _chunks(shown, 1900):
                        await book.send(chunk,
                                        suppress_embeds=True,
                                        allowed_mentions=discord.AllowedMentions.none())
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


def is_staff(who):
    """
    Somebody holding one of the STAFF_ROLES roles, matched by id or by name.
    The one gate on /close, the Close ticket button and the ticket limits, and
    the same list that pulls staff into every ticket thread.

    Nothing else makes somebody staff here, a channel permission included.
    This used to let in anybody the channel trusted with threads as well, and
    Lead Gamemaster and Trial Gamemaster carry Manage Threads on every channel
    (GM in Build-Discord.py) while neither is a staff role, so both could
    close any ticket and skip the ticket limits without one (#1342).

    Content Creator is not staff. That role is added to creator application
    threads through EXTRA_STAFF and nowhere else. It does not close tickets,
    and it does not skip the one open ticket rule or the five minute cooldown.

    A person whose roles cannot be read is not staff.
    """
    try:
        return _who_hits(who, STAFF_IDS, STAFF_NAMES)
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
OPEN_TICKETS = os.path.join(DATA_DIR, 'open-tickets.json')


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
        if guild is None or is_staff(who):
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


def is_ticket_thread(ch):
    """
    True for a thread a ticket opened: one off a channel named in
    TICKET_CHANNEL, which is the only place TicketModal opens one. A ticket
    that could not have its thread goes into the TICKET_LOG channel as a
    plain message, never a thread, so that channel has none to close.

    This used to be any thread at all (#1776). /close in a Live smoke session
    thread (since removed) or a #tales post archived and locked it and wrote "Closed: ..."
    into the staff ticket record as if it were a ticket.

    A thread whose parent is not in the bot's cache is not a ticket here:
    refusing a close costs nothing, since staff can still archive a thread by
    hand.
    """
    if not isinstance(ch, discord.Thread):
        return False
    name = getattr(ch.parent, 'name', None)
    return bool(name) and name.lower() in TICKETS


async def close_here(interaction, why=None):
    """
    Close the ticket this was used in.

    Archived and locked rather than deleted. A ticket is the record of what
    somebody was told and when, and the one time anybody goes looking for it
    is the argument afterwards, so nothing here removes anything. Locked means
    it takes a staff member to open it again, not a stray message.

    Only in a ticket's own thread (is_ticket_thread), refused before anything
    is said, archived or written down.
    """
    ch = interaction.channel
    if not is_ticket_thread(ch):
        await interaction.response.send_message(
            'This one only works inside a ticket.', ephemeral=True)
        return

    if not is_staff(interaction.user):
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
            if not (_role_hit(r, STAFF_IDS, STAFF_NAMES)
                    or _role_hit(r, CREATOR_IDS, CREATOR_NAMES)):
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
MEMBER_IDS, MEMBER_NAMES = _role_tokens([MEMBER_ROLE] if MEMBER_ROLE else [])
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
    return (_who_hits(member, MEMBER_IDS, MEMBER_NAMES)
            or _who_hits(member, STAFF_IDS, STAFF_NAMES))


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


# ------------------------------------------------------- testing channels --
#
# Patrick's card of 11 October. The Live smoke checklist that lived in
# #test-tasks (dated sessions, Pass/Fail/Skip/Fail-known rows, /live-smoke)
# is gone, and the testing channels are three things instead:
#
#   #test-tasks     a Forum. One thread per test task, tagged Main: the
#                   bot posts one, tagged Main, for each issue closed as fixed
#                   (see known issues below), and staff can post one by hand
#                   (/test-task, or python bot.py --post-task).
#   #test-findings  what #test-results was, renamed. Nothing else about it moves.
#   #known-issues   a Forum, read only: one bot post per open GitHub issue
#                   labelled Dev Findings or Main Findings, title only, no
#                   number and no link. The post goes when the issue is closed,
#                   which is when its fix is on main (Patrick, 11 Oct: one
#                   entry per issue, not one list).
#   #dev-test-tasks a Forum in Staff, staff only (Patrick, 12 Oct): the test
#                   tasks someone on dev has to measure, from comments that
#                   say "Server: Dev" (see known issues below). Most go to
#                   #test-tasks, because testers play on main in the alpha.
#
# THE ONE-TIME SETUP. Getting the server from the old shape to that one is the
# only channel change the bot makes, and Patrick's explicit exception to the
# never-touch-channels rule, for these three changes only. It runs only when
# asked, from the command line, never on a normal start:
#
#   python bot.py --setup-channels            says what it would do, changes nothing
#   python bot.py --setup-channels --apply    does it, once
#
# A finished apply is written to channel-setup.json in the data folder, and a
# second run reads it and does nothing at all. Each step also looks at the
# server before it acts, so an apply that stopped half way picks up where it
# stopped. Permission overwrites are copied, never invented.
#
# Discord cannot turn a text channel into a forum (a channel's type can only go
# between text and announcement). The edit is asked for anyway, in case that
# changes, and when Discord refuses it a new forum called test-tasks is made in
# the same category, at the same position, with the old channel's overwrites,
# and the old one is renamed test-tasks-archive with sending switched off for
# everyone but the bot. Nothing is deleted.
#
# #dev-test-tasks is the third one-time step (Patrick, 12 Oct), on a server
# that already had the first two: the forum is made in the category whose id
# is DEV_TASKS_CATEGORY, with that category's overwrites copied, so the same
# staff see it, and the bot's own forum rights from #test-tasks. Its id is
# written to channel-setup.json as dev_tasks_id, and from then on the bot
# finds it by that id and never by its name, so a rename keeps it and no
# second one is made. A forum of that name already in the category (made by
# hand or by Build-Discord.py) is taken as it is and its id recorded.
TASKS_NAME = os.environ.get('TEST_TASKS_CHANNEL', 'test-tasks').strip().lower()
TASKS_ARCHIVE = TASKS_NAME + '-archive'
FINDINGS_OLD = 'test-results'
FINDINGS_NAME = os.environ.get('TEST_FINDINGS_CHANNEL', 'test-findings').strip().lower()
KNOWN_NAME = os.environ.get('KNOWN_ISSUES_CHANNEL', 'known-issues').strip().lower()
DEV_TASKS_NAME = os.environ.get('DEV_TASKS_CHANNEL', 'dev-test-tasks').strip().lower()
# The Staff category (Patrick, 12 Oct: "a new forum under 1549254990110134374
# the Staff category").
DEV_TASKS_CATEGORY = _int_env('DEV_TASKS_CATEGORY', 1549254990110134374)
# The one tag a post in #dev-test-tasks carries.
DEV_TAG = 'Dev'
DEV_TOPIC = ('Test tasks someone on dev has to measure, from the board. Kept '
             'by the bot: a post goes when its issue closes as fixed or its '
             'test task no longer says Server: Dev.')
# What the bot is allowed in a forum it keeps: see it, make a post, write in
# a post, delete a post (manage threads), and read back what is there.
FORUM_BOT_NEEDS = ('view_channel', 'send_messages', 'send_messages_in_threads',
                   'manage_threads', 'read_message_history')
TASK_TAGS = ('Dev', 'Main')
# The only tag a test task is posted with, automatic or by hand (Patrick,
# 12 Oct, #2276 option B): testers test on main, so #test-tasks is Main only.
# The forum keeps its Dev tag for older threads; nothing new gets it.
TASK_POST_TAG = 'Main'
SETUP_STATE = os.path.join(DATA_DIR, 'channel-setup.json')
KNOWN_STATE = os.path.join(DATA_DIR, 'known-issues.json')
SETUP_REASON = 'Thornswood channel setup (one time, Patrick 11 Oct)'
# The send permissions switched off on the archived channel, and only those.
ARCHIVE_LOCK = ('send_messages', 'send_messages_in_threads',
                'create_public_threads', 'create_private_threads')
# Who may post a test task with /test-task. The same people who could run the
# Live smoke sessions, by id (preferred) or by name. A bot.env.json that still
# carries LIVE_SMOKE_ADMIN_ROLES (with the role ids in it) keeps working.
TASK_ROLE_NAMES = [r.strip() for r in
                   (os.environ.get('TEST_TASK_ROLES', '').strip()
                    or os.environ.get('LIVE_SMOKE_ADMIN_ROLES', '').strip()
                    or 'Owner,Dev,Lead Gamemaster,Lead GM').split(',')
                   if r.strip()]
# Forum titles are capped at 100 by Discord and a first message at 2000.
TASK_TITLE_ROOM = 100
TASK_BODY_ROOM = 2000


def _channel_named(guild, name, kinds=None):
    """Any channel in the server by name, text, forum or other, optionally of
       the given kinds ('text', 'forum'). guild.channels, not text_channels,
       because a forum is not in text_channels."""
    for ch in list(getattr(guild, 'channels', None) or []):
        if str(getattr(ch, 'name', '') or '').lower() != name:
            continue
        if kinds and _kind(ch) not in kinds:
            continue
        return ch
    return None


def _kind(ch):
    t = getattr(ch, 'type', None)
    return getattr(t, 'name', str(t or ''))


def _copy_overwrites(ch):
    """The channel's overwrites as a fresh dict, each one copied, so changing
       the copy never touches the original."""
    out = {}
    for target, ow in dict(getattr(ch, 'overwrites', None) or {}).items():
        allow, deny = ow.pair()
        out[target] = discord.PermissionOverwrite.from_pair(allow, deny)
    return out


def known_overwrites(guild, like):
    """
    #known-issues' overwrites: #test-findings' copied, so the same people see
    it, then made read only (Patrick, 11 Oct). Sending and threads are off for
    @everyone and every copied role or member; the bot alone may send.
    """
    out = _copy_overwrites(like) if like is not None else {}
    me = getattr(guild, 'me', None)
    everyone = getattr(guild, 'default_role', None)
    if everyone is not None and everyone not in out:
        out[everyone] = discord.PermissionOverwrite()
    for t, ow in out.items():
        if t == me:
            continue
        ow.update(**dict((n, False) for n in ARCHIVE_LOCK))
    if me is not None:
        mine = out.get(me) or discord.PermissionOverwrite()
        # In a forum, send_messages is making a post and manage_threads is
        # deleting one: the bot does both as issues come and go.
        mine.update(view_channel=True, send_messages=True,
                    send_messages_in_threads=True, manage_threads=True,
                    read_message_history=True)
        out[me] = mine
    return out


def _state_read(path):
    try:
        with open(path, encoding='utf-8') as f:
            got = json.load(f)
        return got if isinstance(got, dict) else {}
    except FileNotFoundError:
        return {}
    except Exception:
        return None


def _state_write(path, data):
    tmp = path + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=1, sort_keys=True)
    os.replace(tmp, path)


def setup_done(guild, path=None):
    """When the setup finished on this server, or None."""
    got = _state_read(path or SETUP_STATE) or {}
    rec = (got.get('guilds') or {}).get(str(getattr(guild, 'id', '')))
    return rec.get('done') if isinstance(rec, dict) else None


def _tags_missing(forum):
    have = set(str(getattr(t, 'name', '')).lower()
               for t in (getattr(forum, 'available_tags', None) or []))
    return [t for t in TASK_TAGS if t.lower() not in have]


async def channel_setup(guild, apply=False, path=None):
    """
    The one-time setup on one server. Returns what it did (or with apply
    False, what it would do), one line per change.

    Never runs twice: a server channel-setup.json says is done, with its
    #known-issues forum and its #dev-test-tasks forum (still there, by id),
    gets one line saying so, and nothing is asked of Discord. A server set up
    before a later step existed gets that step alone, once.
    """
    path = path or SETUP_STATE
    state = _state_read(path)
    if state is None:
        return ['%s is there but cannot be read, so nothing was changed. Look '
                'at it by hand.' % path]
    done = setup_done(guild, path)
    if (done and known_forum_done(guild, path)
            and dev_tasks_forum(guild, path) is not None):
        return ['already done on %s, nothing changed' % done]
    if not done:
        said, stop = await _first_setup(guild, apply, path)
        if stop:
            return said
    elif not known_forum_done(guild, path):
        # Set up before #known-issues was a forum: that one step, once.
        said = await known_forum_setup(guild, apply, path)
    else:
        said = []
    said += await dev_tasks_setup(guild, apply, path)
    if not said:
        said.append('nothing to change')
    return said


async def _first_setup(guild, apply, path):
    """The first one-time setup: #test-tasks a forum, #test-results renamed
       #test-findings, the #known-issues forum. Returns (lines, stop), stop
       True when nothing could be done and no later step should run."""
    said = []
    verb = '' if apply else 'would '

    # 1. #test-tasks becomes a forum.
    tasks = _channel_named(guild, TASKS_NAME, ('forum',))
    old = _channel_named(guild, TASKS_NAME, ('text',))
    if tasks is None and old is None:
        return ['there is no #%s in "%s", so nothing was changed. Make it '
                '(Build-Discord.py) and run this again.'
                % (TASKS_NAME, getattr(guild, 'name', '?'))], True
    if tasks is None:
        said.append('%stry to convert #%s to a forum' % (verb, TASKS_NAME))
        if apply:
            try:
                await old.edit(type=discord.ChannelType.forum, reason=SETUP_REASON)
                tasks = _channel_named(guild, TASKS_NAME, ('forum',))
                if tasks is not None:
                    old = None
            except (discord.HTTPException, TypeError, ValueError,
                    AttributeError) as e:
                said.append('Discord refused the conversion (%s), so the '
                            'fallback' % (getattr(e, 'text', '') or type(e).__name__))
        if tasks is None:
            said.append('%smake a new forum #%s in %s with the old channel\'s '
                        '%d permission overwrite(s) and the tags %s'
                        % (verb, TASKS_NAME,
                           getattr(old.category, 'name', None) or 'no category',
                           len(getattr(old, 'overwrites', {}) or {}),
                           ', '.join(TASK_TAGS)))
            if apply:
                tasks = await guild.create_forum(
                    TASKS_NAME, category=old.category,
                    position=getattr(old, 'position', None) or 0,
                    overwrites=_copy_overwrites(old),
                    topic='One thread per test task, tagged Main.',
                    available_tags=[discord.ForumTag(name=t) for t in TASK_TAGS],
                    reason=SETUP_REASON)
    if old is not None:
        # The text channel still called test-tasks, beside the new forum.
        said.append('%srename the old text #%s to #%s and switch off sending '
                    'in it for everyone but the bot (nothing deleted)'
                    % (verb, TASKS_NAME, TASKS_ARCHIVE))
        if apply:
            await old.edit(name=TASKS_ARCHIVE, reason=SETUP_REASON)
            me = getattr(guild, 'me', None)
            targets = [t for t in (getattr(old, 'overwrites', {}) or {})
                       if t != me]
            everyone = getattr(guild, 'default_role', None)
            if everyone is not None and everyone not in targets:
                targets.append(everyone)
            for t in targets:
                ow = old.overwrites_for(t)
                ow.update(**dict((n, False) for n in ARCHIVE_LOCK))
                await old.set_permissions(t, overwrite=ow, reason=SETUP_REASON)
    if tasks is not None:
        missing = _tags_missing(tasks)
        if missing:
            said.append('%sadd the forum tag(s) %s to #%s'
                        % (verb, ', '.join(missing), TASKS_NAME))
            if apply:
                tags = list(getattr(tasks, 'available_tags', None) or [])
                tags += [discord.ForumTag(name=t) for t in missing]
                await tasks.edit(available_tags=tags, reason=SETUP_REASON)

    # 2. #test-results becomes #test-findings. A rename keeps everything else.
    findings = _channel_named(guild, FINDINGS_NAME)
    if findings is None:
        was = _channel_named(guild, FINDINGS_OLD)
        if was is None:
            said.append('there is no #%s or #%s, so that rename was skipped'
                        % (FINDINGS_OLD, FINDINGS_NAME))
        else:
            said.append('%srename #%s to #%s' % (verb, FINDINGS_OLD, FINDINGS_NAME))
            if apply:
                await was.edit(name=FINDINGS_NAME, reason=SETUP_REASON)
            findings = was

    # 3. #known-issues, a forum beside #test-findings, with its overwrites.
    said += await _known_forum_make(guild, findings, apply, verb)

    if apply:
        state = _state_read(path) or {}
        now = _utc_stamp()
        rec = state.setdefault('guilds', {}).setdefault(str(guild.id), {})
        rec.update(done=now, known_forum=now, name=getattr(guild, 'name', ''))
        _state_write(path, state)
        said.append('recorded in %s, so this never runs again' % path)
    return said, False


def _utc_stamp():
    return (datetime.datetime.now(datetime.timezone.utc)
            .strftime('%Y-%m-%dT%H:%M:%SZ'))


def known_forum_done(guild, path=None):
    """When #known-issues was made a forum on this server, or None."""
    got = _state_read(path or SETUP_STATE) or {}
    rec = (got.get('guilds') or {}).get(str(getattr(guild, 'id', '')))
    return rec.get('known_forum') if isinstance(rec, dict) else None


async def _known_forum_make(guild, like, apply, verb):
    """The #known-issues forum, read only, with the Dev and Main tags, when
       there is none. One line per change."""
    said = []
    if _channel_named(guild, KNOWN_NAME, ('forum',)) is not None:
        return said
    said.append('%smake the forum #%s in %s with %s and the tags %s' % (
        verb, KNOWN_NAME,
        getattr(getattr(like, 'category', None), 'name', 'no category'),
        ('the %d permission overwrite(s) of #%s'
         % (len(getattr(like, 'overwrites', {}) or {}), FINDINGS_NAME))
        if like is not None else 'no overwrites of its own',
        ', '.join(TASK_TAGS)))
    said.append('%smake #%s read only: posting and replies off for @everyone '
                'and every copied overwrite; the bot alone posts and deletes '
                'there' % (verb, KNOWN_NAME))
    if apply:
        await guild.create_forum(
            KNOWN_NAME, category=getattr(like, 'category', None),
            position=(getattr(like, 'position', None) or 0) + 1,
            overwrites=known_overwrites(guild, like),
            topic='One post per known issue being worked on. Kept by the bot: '
                  'a post goes when its fix is on main and becomes a test task.',
            available_tags=[discord.ForumTag(name=t) for t in TASK_TAGS],
            reason=SETUP_REASON)
    return said


async def known_forum_setup(guild, apply=False, path=None):
    """
    The second one-time step (Patrick, 11 Oct): #known-issues is a forum with
    one post per known issue, not one channel of messages. On a server whose
    first setup made a text #known-issues, that channel goes: deleted when
    every message in it is the bot's own (all it ever held was the bot's
    list), otherwise renamed known-issues-archive and locked like the tasks
    archive. Then the forum is made. Recorded as known_forum, so it runs once.
    """
    path = path or SETUP_STATE
    verb = '' if apply else 'would '
    said = []
    old = _channel_named(guild, KNOWN_NAME, ('text',))
    if old is not None:
        me = getattr(guild, 'me', None)
        mine_only, n = True, 0
        async for msg in old.history(limit=1000):
            n += 1
            if getattr(msg.author, 'id', None) != getattr(me, 'id', None):
                mine_only = False
                break
        if mine_only:
            said.append('%sdelete the text #%s: its %d message(s) are all the '
                        'bot\'s own list' % (verb, KNOWN_NAME, n))
            if apply:
                await old.delete(reason=SETUP_REASON)
        else:
            archive = KNOWN_NAME + '-archive'
            said.append('%srename the text #%s to #%s and switch off sending in '
                        'it (it holds messages that are not the bot\'s, so '
                        'nothing is deleted)' % (verb, KNOWN_NAME, archive))
            if apply:
                await old.edit(name=archive, reason=SETUP_REASON)
                for t in list((getattr(old, 'overwrites', {}) or {})):
                    if t == me:
                        continue
                    ow = old.overwrites_for(t)
                    ow.update(**dict((x, False) for x in ARCHIVE_LOCK))
                    await old.set_permissions(t, overwrite=ow, reason=SETUP_REASON)
    findings = _channel_named(guild, FINDINGS_NAME)
    said += await _known_forum_make(guild, findings, apply, verb)
    tasks = _channel_named(guild, TASKS_NAME, ('forum',))
    me = getattr(guild, 'me', None)
    if tasks is not None and me is not None and not tasks.overwrites_for(me).manage_threads:
        said.append('%slet the bot delete posts in #%s (manage threads, for a '
                    'test task whose issue is reopened)' % (verb, TASKS_NAME))
        if apply:
            ow = tasks.overwrites_for(me)
            ow.update(view_channel=True, send_messages=True,
                      send_messages_in_threads=True, manage_threads=True)
            await tasks.set_permissions(me, overwrite=ow, reason=SETUP_REASON)
    if apply:
        state = _state_read(path) or {}
        rec = state.setdefault('guilds', {}).setdefault(str(guild.id), {})
        rec['known_forum'] = _utc_stamp()
        _state_write(path, state)
        said.append('recorded in %s, so this never runs again' % path)
    return said


def _setup_rec(guild, path=None):
    got = _state_read(path or SETUP_STATE) or {}
    rec = (got.get('guilds') or {}).get(str(getattr(guild, 'id', '')))
    return rec if isinstance(rec, dict) else {}


def _by_id(guild, cid):
    """The server's channel or category with this id, or None."""
    try:
        cid = int(cid or 0)
    except (TypeError, ValueError):
        return None
    if not cid:
        return None
    getter = getattr(guild, 'get_channel', None)
    return getter(cid) if getter is not None else None


def dev_tasks_forum(guild, path=None):
    """The #dev-test-tasks forum, by the id the setup recorded, or None when
       the setup has not made it or it has been deleted since. Never looked
       for by name: a rename keeps it."""
    ch = _by_id(guild, _setup_rec(guild, path).get('dev_tasks_id'))
    return ch if ch is not None and _kind(ch) == 'forum' else None


def dev_overwrites(guild, category, tasks=None):
    """
    #dev-test-tasks' overwrites: the category's copied, so it is staff only
    the way the category is, then the bot's own overwrite from #test-tasks
    with every forum right it needs there (FORUM_BOT_NEEDS) switched on.
    """
    out = _copy_overwrites(category) if category is not None else {}
    me = getattr(guild, 'me', None)
    if me is not None:
        mine = out.get(me) or discord.PermissionOverwrite()
        if tasks is not None and me in (getattr(tasks, 'overwrites', None) or {}):
            a, d = tasks.overwrites[me].pair()
            mine = discord.PermissionOverwrite.from_pair(a, d)
        mine.update(**dict((n, True) for n in FORUM_BOT_NEEDS))
        out[me] = mine
    return out


async def dev_tasks_setup(guild, apply=False, path=None):
    """
    The third one-time step (Patrick, 12 Oct): the #dev-test-tasks forum in
    the Staff category, staff only, tagged Dev. Recorded with its id as
    dev_tasks_id, so it runs once and the bot finds the forum by that id.
    Nothing to do when the recorded forum is still there.
    """
    path = path or SETUP_STATE
    verb = '' if apply else 'would '
    rec = _setup_rec(guild, path)
    if dev_tasks_forum(guild, path) is not None:
        return []
    said = []
    if rec.get('dev_tasks_id'):
        said.append('the #%s recorded in %s (id %s) is not on the server any '
                    'more' % (DEV_TASKS_NAME, path, rec.get('dev_tasks_id')))
    cat = _by_id(guild, DEV_TASKS_CATEGORY)
    if cat is None or _kind(cat) != 'category':
        return said + ['there is no category with id %d in "%s", so #%s was not '
                       'made. Set DEV_TASKS_CATEGORY in bot.env.json to the '
                       'Staff category\'s id and run this again.'
                       % (DEV_TASKS_CATEGORY, getattr(guild, 'name', '?'),
                          DEV_TASKS_NAME)]
    me = getattr(guild, 'me', None)
    there = [ch for ch in (getattr(cat, 'channels', None) or [])
             if str(getattr(ch, 'name', '')).lower() == DEV_TASKS_NAME]
    forum = next((ch for ch in there if _kind(ch) == 'forum'), None)
    if forum is None and there:
        return said + ['there is a #%s in %s that is not a forum, so nothing was '
                       'made. Rename or remove it by hand, then run this again.'
                       % (DEV_TASKS_NAME, getattr(cat, 'name', '?'))]
    if forum is not None:
        said.append('#%s is already in %s: %staken as it is, by its id %s'
                    % (DEV_TASKS_NAME, getattr(cat, 'name', '?'), verb, forum.id))
        if task_tag_of(forum, DEV_TAG) is None:
            said.append('%sadd the forum tag %s to #%s' % (verb, DEV_TAG, DEV_TASKS_NAME))
            if apply:
                tags = list(getattr(forum, 'available_tags', None) or [])
                tags.append(discord.ForumTag(name=DEV_TAG))
                await forum.edit(available_tags=tags, reason=SETUP_REASON)
        have = forum.overwrites_for(me) if me is not None else None
        if have is not None and not all(getattr(have, n) is True for n in FORUM_BOT_NEEDS):
            said.append('%slet the bot post, reply and delete its posts in #%s'
                        % (verb, DEV_TASKS_NAME))
            if apply:
                have.update(**dict((n, True) for n in FORUM_BOT_NEEDS))
                await forum.set_permissions(me, overwrite=have, reason=SETUP_REASON)
    else:
        tasks = _channel_named(guild, TASKS_NAME, ('forum',))
        said.append('%smake the forum #%s in %s with the category\'s %d '
                    'permission overwrite(s), so only the people who see %s '
                    'see it, and the tag %s'
                    % (verb, DEV_TASKS_NAME, getattr(cat, 'name', '?'),
                       len(getattr(cat, 'overwrites', {}) or {}),
                       getattr(cat, 'name', '?'), DEV_TAG))
        said.append('%sgive the bot its #%s rights there: see it, post, reply, '
                    'delete its posts and read them back' % (verb, TASKS_NAME))
        if apply:
            forum = await guild.create_forum(
                DEV_TASKS_NAME, category=cat,
                overwrites=dev_overwrites(guild, cat, tasks),
                topic=DEV_TOPIC,
                available_tags=[discord.ForumTag(name=DEV_TAG)],
                reason=SETUP_REASON)
    if apply:
        state = _state_read(path) or {}
        r = state.setdefault('guilds', {}).setdefault(str(guild.id), {})
        r['dev_tasks'] = _utc_stamp()
        r['dev_tasks_id'] = forum.id
        _state_write(path, state)
        said.append('recorded #%s (id %s) in %s, so this never runs again and '
                    'the bot finds it by that id' % (DEV_TASKS_NAME, forum.id, path))
    return said


# ------------------------------------------------------------ test tasks --
def is_task_poster(who):
    """Owner, Dev or Lead Gamemaster by TEST_TASK_ROLES. Nobody else."""
    try:
        ids, names = _role_tokens(TASK_ROLE_NAMES)
        return _who_hits(who, ids, names)
    except Exception:
        return False


def task_tag_of(forum, tag):
    """The forum's Dev or Main tag object, or None."""
    want = str(tag or '').strip().lower()
    for t in getattr(forum, 'available_tags', None) or []:
        if str(getattr(t, 'name', '')).lower() == want:
            return t
    return None


async def post_test_task(guild, title, body, tag=TASK_POST_TAG):
    """
    One thread in the #test-tasks forum, titled and tagged Main. Every
    test task is Main only (#2276); a Dev tag, or any other, is refused.

    Returns (thread or None, what to say). A thread already open under that
    exact title is not made twice; the existing one is handed back.
    """
    title = str(title or '').strip()
    body = str(body or '').strip()
    want = str(tag or '').strip().capitalize()
    if want != TASK_POST_TAG:
        return None, ('Test tasks are Main only (testers test on main), '
                      'not %r.' % tag)
    if not title or not body:
        return None, 'A test task needs a title and a body.'
    if len(title) > TASK_TITLE_ROOM:
        return None, 'That title is %d characters; Discord takes %d.' % (
            len(title), TASK_TITLE_ROOM)
    if len(body) > TASK_BODY_ROOM:
        return None, 'That body is %d characters; Discord takes %d.' % (
            len(body), TASK_BODY_ROOM)
    forum = _channel_named(guild, TASKS_NAME, ('forum',))
    if forum is None:
        return None, ('#%s is not a forum yet. The one-time setup '
                      '(python bot.py --setup-channels --apply) makes it one.'
                      % TASKS_NAME)
    t = task_tag_of(forum, want)
    if t is None:
        return None, ('#%s has no %s tag. The one-time setup adds it.'
                      % (TASKS_NAME, want))
    for th in list(getattr(forum, 'threads', None) or []):
        if (str(getattr(th, 'name', '')) == title
                and not getattr(th, 'archived', False)):
            return th, 'Already there: %s' % getattr(th, 'mention', title)
    made = await forum.create_thread(name=title, content=body,
                                     applied_tags=[t],
                                     reason='Thornswood test task')
    thread = getattr(made, 'thread', made)
    return thread, 'Posted: %s' % getattr(thread, 'mention', title)


@tree.command(name='test-task',
              description='Post a test task in #test-tasks, tagged Main. '
                          'Owner, Dev and Lead Gamemaster only.')
@discord.app_commands.describe(title='The thread title.',
                               body='What to test, as the first post.')
async def test_task_cmd(interaction: discord.Interaction, title: str,
                        body: str):
    if interaction.guild is None:
        await _say(interaction, 'This one works in the server.')
        return
    if not is_task_poster(interaction.user):
        await _say(interaction, 'Only %s post test tasks.'
                   % ', '.join(TASK_ROLE_NAMES))
        return
    await interaction.response.defer(ephemeral=True, thinking=True)
    try:
        _, said = await post_test_task(interaction.guild, title, body)
    except discord.HTTPException as e:
        log('test task: Discord refused a post: %s' % getattr(e, 'text', e))
        said = ('That did not go through. In #%s the bot needs View Channel, '
                'Send Messages and Create Posts.' % TASKS_NAME)
    await interaction.followup.send(said, ephemeral=True)


# ---------------------------------------------------------- known issues --
#
# Patrick, 11 Oct: the issue board is not where testers look. Two forums are
# kept from it, automatically, as things are found and fixed:
#
#   #known-issues  one post per open issue labelled Dev Findings or Main
#                  Findings, tagged Dev or Main by its labels (where it was
#                  found). The post goes the moment its issue is no longer an
#                  open finding: fixed and closed, closed any other way, or its
#                  label taken off.
#   #test-tasks    one post per issue closed as fixed from the day this began
#                  (see the since stamp below), for testers to check. Its
#                  title and body are the issue's last comment that starts
#                  "Test task:" (written by whoever fixed it); a finding with
#                  no such comment gets its own title and a plain line. An
#                  issue that is reopened loses its test task, and comes back
#                  to #known-issues if it is still a finding.
#
# When an issue closes (Patrick, 11 Oct): dev is where the team checks that
# nothing breaks the game, and main is where testers test, since we are in
# alpha. So a fix people would notice is closed, with its "Test task:"
# comment, when it reaches main, not when it merges or reaches dev, and every
# test task the bot posts in #test-tasks is tagged Main. A "Server:" line
# under "Known issue:" still sets that post's tag.
#
#   #dev-test-tasks (Patrick, 12 Oct) one post per issue whose last "Test
#                  task:" comment has "Server: Dev" straight under it, open or
#                  closed: the code is done and someone on dev has to measure
#                  something. Most test tasks are Main, because testers play
#                  on main. The post goes when the issue closes as fixed (any
#                  close after the comment), or when a newer "Test task:"
#                  comment does not say Server: Dev; a closed issue's newest
#                  test task then goes to #test-tasks as before, if it is
#                  Main. An issue whose last test task says Server: Dev gets
#                  no #test-tasks post from it.
#
# "Server: Dev" counts only on a comment written from the day #dev-test-tasks
# began (state['dev_since'], set on the first pass that finds the forum).
# Comments from before that carried "Server: Dev" when every test task went
# to #test-tasks; they stay Main, so no post already up moves. Until the
# forum is made, every Server line is read and changes nothing, as before.
#
# Each record holds the form of the post it was made with (TASK_FORM,
# KNOWN_FORM). When the way a post is written changes, the form goes up by
# one, and every record of an older form is written again on the next pass,
# once, even though GitHub says its issue did not change.
#
# Posts carry no issue number and no link: testers have no GitHub. The bot
# remembers which post is which issue in known-issues.json in the data folder,
# written straight after each post, so a restart never posts twice; a post
# made just before a crash is found again by its title among the bot's own.
#
# GitHub: GITHUB_TOKEN in bot.env.json, a read only token for the issues of
# KNOWN_ISSUES_REPO. No token means neither forum is kept, said once.
KNOWN_REPO = os.environ.get('KNOWN_ISSUES_REPO', 'EvilPatrick06/Thornswood').strip()
KNOWN_LABELS = [l.strip() for l in
                os.environ.get('KNOWN_ISSUES_LABELS',
                               'Dev Findings,Main Findings').split(',')
                if l.strip()]
KNOWN_EVERY = max(60, _int_env('KNOWN_ISSUES_EVERY', 300))
GITHUB_API = os.environ.get('GITHUB_API', 'https://api.github.com').rstrip('/')
TASK_MARK = re.compile(r'^\s*test task\s*:\s*(.*)$', re.I)
KNOWN_MARK = re.compile(r'^\s*known issue\s*:\s*(.*)$', re.I)
TASK_SERVER = re.compile(r'^\s*server\s*:\s*(dev|main)\s*$', re.I)
# The one tag a test task from the board carries: testers test on main.
TASK_TAG = 'Main'
# The form of the posts each record was made with. 2: test tasks tagged Main
# whatever their Server line, and both bodies say the fix is on main (11 Oct).
TASK_FORM = 2
KNOWN_FORM = 2
DEV_FORM = 1


def _github_get(url):
    token = os.environ.get('GITHUB_TOKEN', '').strip()
    req = urllib.request.Request(url, headers={
        'Accept': 'application/vnd.github+json',
        'Authorization': 'Bearer ' + token,
        'User-Agent': 'thornswood-bot',
        'X-GitHub-Api-Version': '2022-11-28'})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read().decode('utf-8'))


def github_open_findings(get=None):
    """Every open issue (not pull request) carrying one of KNOWN_LABELS, by
       number. One query per label because GitHub ANDs labels in one."""
    get = get or _github_get
    out = {}
    for label in KNOWN_LABELS:
        page = 1
        while True:
            url = ('%s/repos/%s/issues?state=open&per_page=100&page=%d&labels=%s'
                   % (GITHUB_API, KNOWN_REPO, page,
                      urllib.parse.quote(label)))
            rows = get(url) or []
            for row in rows:
                if isinstance(row, dict) and 'pull_request' not in row:
                    out.setdefault(int(row['number']), row)
            if len(rows) < 100:
                break
            page += 1
    return out


def github_closed_since(since, get=None):
    """Every issue (not pull request) that is closed and was updated at or
       after since, an ISO stamp, by number. A close and a new comment both
       move the update time, so this holds every issue closed since then and
       every closed issue with a comment since then."""
    get = get or _github_get
    out = {}
    page = 1
    while True:
        url = ('%s/repos/%s/issues?state=closed&per_page=100&page=%d'
               '&sort=updated&direction=desc&since=%s'
               % (GITHUB_API, KNOWN_REPO, page, urllib.parse.quote(since)))
        rows = get(url) or []
        for row in rows:
            if isinstance(row, dict) and 'pull_request' not in row:
                out.setdefault(int(row['number']), row)
        if len(rows) < 100:
            break
        page += 1
    return out


def github_changed_since(since, get=None):
    """Every issue (not pull request), open or closed, updated at or after
       since, by number. A new comment, a close and a reopen all move the
       update time, so this holds every issue whose dev test task can have
       come or gone since then."""
    get = get or _github_get
    out = {}
    page = 1
    while True:
        url = ('%s/repos/%s/issues?state=all&per_page=100&page=%d'
               '&sort=updated&direction=asc&since=%s'
               % (GITHUB_API, KNOWN_REPO, page, urllib.parse.quote(since)))
        rows = get(url) or []
        for row in rows:
            if isinstance(row, dict) and 'pull_request' not in row:
                out.setdefault(int(row['number']), row)
        if len(rows) < 100:
            break
        page += 1
    return out


def github_issue(number, get=None):
    get = get or _github_get
    return get('%s/repos/%s/issues/%d' % (GITHUB_API, KNOWN_REPO, int(number)))


def github_comments(number, get=None):
    get = get or _github_get
    out, page = [], 1
    while True:
        rows = get('%s/repos/%s/issues/%d/comments?per_page=100&page=%d'
                   % (GITHUB_API, KNOWN_REPO, int(number), page)) or []
        out += [r for r in rows if isinstance(r, dict)]
        if len(rows) < 100:
            break
        page += 1
    return out


def _labels(issue):
    return [str((l or {}).get('name') if isinstance(l, dict) else l)
            for l in (issue.get('labels') or [])]


def issue_tags(issue, server=None):
    """The #known-issues tags: Dev, Main or both, from the findings labels;
       server ('Dev' or 'Main') when a "Known issue:" comment names one; Dev
       when nothing says. Test tasks do not use this: they are TASK_TAG."""
    if server:
        return [server.capitalize()]
    names = _labels(issue)
    tags = [t for t in TASK_TAGS if ('%s Findings' % t) in names]
    return tags or ['Dev']


def known_title(issue):
    return (str(issue.get('title') or '').strip() or 'untitled')[:TASK_TITLE_ROOM]


def known_body(issue):
    where = ' and '.join(issue_tags(issue))
    return ('Known on %s. The team is working on it. This post goes when the '
            'fix is on main, and then it comes back as a test task.' % where)


def _marked(issue, comments, mark):
    """(title, body, server or None, created_at) from the issue's last comment
       whose first line matches mark ("Test task:" or "Known issue:"), or
       None. A first line with nothing after the colon takes the issue's own
       title."""
    for c in reversed(comments or []):
        lines = str(c.get('body') or '').replace('\r\n', '\n').strip().split('\n')
        m = mark.match(lines[0]) if lines else None
        if not m:
            continue
        title = (m.group(1).strip() or known_title(issue))[:TASK_TITLE_ROOM]
        rest = lines[1:]
        server = None
        if rest and TASK_SERVER.match(rest[0]):
            server = TASK_SERVER.match(rest[0]).group(1).capitalize()
            rest = rest[1:]
        body = '\n'.join(rest).strip()[:TASK_BODY_ROOM]
        return title, body, server, str(c.get('created_at') or '')
    return None


def last_task(issue, comments, dev_since=None):
    """(title, body, server, created_at) from the last "Test task:" comment,
       or None. server is 'Dev' when a "Server: Dev" line is straight under
       it and the comment was written at or after dev_since, the day
       #dev-test-tasks began; 'Main' otherwise, so a Server line from before
       that day, or with no dev_since at all, is read and changes nothing."""
    got = _marked(issue, comments, TASK_MARK)
    if got is None:
        return None
    title, body, server, created = got
    if server == 'Dev' and dev_since and created >= dev_since:
        return title, body or 'Measure this on dev.', 'Dev', created
    return title, body or 'Check this on main.', 'Main', created


def test_task_of(issue, comments, dev_since=None):
    """(title, body, created_at) from the last "Test task:" comment when it
       is one for main, or None. A Server line under it is read so it is not
       in the body. The last one saying Server: Dev (last_task) is not a
       test task for main, so this is None for it."""
    got = last_task(issue, comments, dev_since)
    if got is None or got[2] == 'Dev':
        return None
    return got[0], got[1], got[3]


def dev_post_of(issue, comments, dev_since):
    """(title, body, tags) for an issue's #dev-test-tasks post, or None when
       it has none: its last "Test task:" comment does not say Server: Dev
       (last_task), or the issue was closed after that comment was written."""
    if not dev_since:
        return None
    got = last_task(issue, comments, dev_since)
    if got is None or got[2] != 'Dev':
        return None
    if str(issue.get('state')) != 'open':
        closed = str(issue.get('closed_at') or '')
        if closed and closed >= got[3]:
            return None
    return got[0], got[1], [DEV_TAG]


def known_of(issue, comments):
    """(title, body, tags) for the #known-issues post: the last "Known
       issue:" comment, or the issue's title and a plain line until somebody
       writes one."""
    got = _marked(issue, comments, KNOWN_MARK)
    if got:
        return got[0], got[1] or known_body(issue), issue_tags(issue, got[2])
    return known_title(issue), known_body(issue), issue_tags(issue)


def _sig(title, body, tags):
    return '%s\n%s\n%s' % (title, body, ','.join(sorted(tags)))


def default_task_body(issue):
    """The body for a fixed finding nobody wrote a test task for. Its issue
       closed when the fix reached main, so that is where to check it."""
    return ('This was fixed and the fix is on main. Check it on main, and say '
            'in #%s if it still happens.' % FINDINGS_NAME)


def task_post_of(issue, comments, dev_since=None):
    """(title, body, tags) for an issue's #test-tasks post, or None when it
       gets none (not a finding and nobody wrote a test task, or its last
       test task says Server: Dev, which is #dev-test-tasks')."""
    task = last_task(issue, comments, dev_since)
    if task is not None and task[2] == 'Dev':
        return None
    if task is not None:
        return task[0], task[1], [TASK_TAG]
    if issue_tags_found(issue):
        return known_title(issue), default_task_body(issue), [TASK_TAG]
    return None


async def _forum_thread(forum, tid):
    """The thread by id, or None when it is gone."""
    guild = getattr(forum, 'guild', None)
    th = None
    getter = getattr(guild, 'get_thread', None)
    if getter is not None:
        th = getter(int(tid))
    if th is None and guild is not None:
        try:
            th = await guild.fetch_channel(int(tid))
        except discord.NotFound:
            return None
    return th


async def _forum_post(forum, title, body, tags, me_id=None):
    """A post in the forum, tagged; an open post of the bot's with that exact
       title is handed back rather than made twice. Returns the thread."""
    for th in list(getattr(forum, 'threads', None) or []):
        if (str(getattr(th, 'name', '')) == title
                and not getattr(th, 'archived', False)
                and (me_id is None or getattr(th, 'owner_id', me_id) == me_id)):
            return th
    applied = [t for t in (task_tag_of(forum, x) for x in tags) if t is not None]
    made = await forum.create_thread(name=title, content=body,
                                     applied_tags=applied,
                                     allowed_mentions=discord.AllowedMentions.none(),
                                     reason='Thornswood known issues and test tasks')
    return getattr(made, 'thread', made)


async def _forum_drop(forum, tid):
    th = await _forum_thread(forum, tid)
    if th is not None:
        await th.delete()


async def _forum_edit(forum, tid, title, body, tags):
    """Brings an existing post to this title, body and tags. False when the
       post is gone (deleted by hand), so the caller can make it again."""
    th = await _forum_thread(forum, tid)
    if th is None:
        return False
    applied = [x for x in (task_tag_of(forum, n) for n in tags) if x is not None]
    await th.edit(name=title, applied_tags=applied)
    msg = getattr(th, 'starter_message', None)
    if msg is None:
        try:
            msg = await th.fetch_message(th.id)
        except discord.NotFound:
            msg = None
    if msg is not None:
        await msg.edit(content=body, allowed_mentions=discord.AllowedMentions.none())
    return True


async def known_issues_once(forum, state, get=None, save=None, me_id=None):
    """
    One pass over #known-issues, a forum. state is the dict kept in
    known-issues.json, changed in place; the caller writes it. Returns the
    issue numbers posted, edited and removed.

    Comments are read only for an issue GitHub says changed since the last
    pass (its updated_at), or whose record was made with an older form of
    the post (KNOWN_FORM), so an untouched issue costs nothing.
    """
    loop = asyncio.get_running_loop()
    issues = await loop.run_in_executor(None, github_open_findings, get)
    rec = state.setdefault('issues', {})
    # Records from before #known-issues was a forum point at messages in a
    # channel that is gone: they are forgotten, not deleted again.
    for key, have in list(rec.items()):
        if have.get('channel_id') != getattr(forum, 'id', None) or 'thread_id' not in have:
            rec.pop(key, None)
            state['_dirty'] = True
    posted, edited, removed = [], [], []
    for num in sorted(issues):
        key = str(num)
        issue = issues[num]
        have = rec.get(key)
        if (have and have.get('updated') == issue.get('updated_at')
                and have.get('form') == KNOWN_FORM):
            continue
        comments = await loop.run_in_executor(None, github_comments, num, get)
        title, body, tags = known_of(issue, comments)
        sig = _sig(title, body, tags)
        if have:
            if have.get('sig') != sig:
                try:
                    if not await _forum_edit(forum, have['thread_id'], title, body, tags):
                        have = None
                        rec.pop(key, None)
                    else:
                        edited.append(num)
                except discord.HTTPException:
                    continue
            if have:
                have.update(sig=sig, updated=issue.get('updated_at'),
                            form=KNOWN_FORM)
                state['_dirty'] = True
                continue
        th = await _forum_post(forum, title, body, tags, me_id)
        rec[key] = {'thread_id': th.id, 'channel_id': forum.id, 'sig': sig,
                    'updated': issue.get('updated_at'), 'form': KNOWN_FORM}
        state['_dirty'] = True
        if save:
            save(state)      # straight away, so a crash cannot double it
        posted.append(num)
    for key, have in list(rec.items()):
        if int(key) in issues:
            continue
        try:
            await _forum_drop(forum, have['thread_id'])
        except discord.HTTPException:
            continue
        rec.pop(key, None)
        state['_dirty'] = True
        removed.append(int(key))
    return posted, edited, removed


async def test_tasks_once(forum, state, get=None, save=None, me_id=None, now=None):
    """
    One pass over #test-tasks. An issue closed as fixed gets a post when it
    was closed after state['since'] (set to now on the first pass, so nothing
    from before this began floods in), or when its latest "Test task:"
    comment was written after since. Every post is tagged Main (TASK_TAG).
    A rewritten comment edits the post, and so does a record made with an
    older form of the post (TASK_FORM), once; an issue that is reopened
    loses it. An issue whose last test task says Server: Dev, from the day
    #dev-test-tasks began (state['dev_since']), gets no post here: it is
    in #dev-test-tasks. Returns the issue numbers posted, edited and removed.
    """
    loop = asyncio.get_running_loop()
    dev_since = state.get('dev_since')
    since = state.get('since')
    if not since:
        state['since'] = since = now or _utc_stamp()
        state['_dirty'] = True
    rec = state.setdefault('tasks', {})
    closed = await loop.run_in_executor(None, github_closed_since, since, get)
    posted, edited, removed = [], [], []
    for num in sorted(closed):
        key = str(num)
        issue = closed[num]
        have = rec.get(key)
        if (issue.get('state_reason') or 'completed') != 'completed':
            continue
        if (have and have.get('updated') == issue.get('updated_at')
                and have.get('form') == TASK_FORM):
            continue
        comments = await loop.run_in_executor(None, github_comments, num, get)
        task = test_task_of(issue, comments, dev_since)
        new_enough = (str(issue.get('closed_at') or '') >= since
                      or (task is not None and task[2] >= since))
        if not have and not new_enough:
            continue
        post = task_post_of(issue, comments, dev_since)
        if post is None:
            # Not a finding and nobody wrote a test task, or its last test
            # task says Server: Dev and is #dev-test-tasks'. A post already
            # here is left as it is, and not read again until the issue
            # changes.
            if have:
                have.update(updated=issue.get('updated_at'), form=TASK_FORM)
                state['_dirty'] = True
            continue
        title, body, tags = post
        sig = _sig(title, body, tags)
        if have:
            if have.get('sig') != sig:
                try:
                    if await _forum_edit(forum, have['thread_id'], title, body, tags):
                        edited.append(num)
                    else:
                        rec.pop(key, None)     # deleted by hand: confirmed
                        state['_dirty'] = True
                        continue
                except discord.HTTPException:
                    continue
            have.update(sig=sig, updated=issue.get('updated_at'), form=TASK_FORM)
            state['_dirty'] = True
            continue
        th = await _forum_post(forum, title, body, tags, me_id)
        rec[key] = {'thread_id': th.id, 'channel_id': forum.id, 'sig': sig,
                    'updated': issue.get('updated_at'), 'form': TASK_FORM}
        state['_dirty'] = True
        if save:
            save(state)
        posted.append(num)
    for key, have in list(rec.items()):
        if int(key) in closed:
            continue
        try:
            issue = await loop.run_in_executor(None, github_issue, int(key), get)
        except Exception:
            continue
        if str(issue.get('state')) == 'open':
            try:
                await _forum_drop(forum, have['thread_id'])
            except discord.HTTPException:
                continue
            rec.pop(key, None)
            state['_dirty'] = True
            removed.append(int(key))
        elif (have.get('updated') != issue.get('updated_at')
                or have.get('form') != TASK_FORM):
            # Closed before since, and changed since the last pass (an adopted
            # post whose comment was rewritten) or made with an older form of
            # the post: brought up to date.
            comments = await loop.run_in_executor(None, github_comments, int(key), get)
            post = task_post_of(issue, comments, dev_since)
            if post is not None:
                sig = _sig(*post)
                if have.get('sig') != sig:
                    try:
                        if await _forum_edit(forum, have['thread_id'], *post):
                            edited.append(int(key))
                    except discord.HTTPException:
                        continue
                have['sig'] = sig
            have['updated'] = issue.get('updated_at')
            have['form'] = TASK_FORM
            state['_dirty'] = True
    return posted, edited, removed


async def dev_tasks_once(forum, state, get=None, save=None, me_id=None, now=None):
    """
    One pass over #dev-test-tasks, found by the id the setup recorded. An
    issue, open or closed, whose last "Test task:" comment says Server: Dev
    gets a post tagged Dev (dev_post_of); it goes when the issue is closed
    after that comment, or a newer test task does not say Server: Dev. A
    rewritten comment edits the post.

    The first pass sets state['dev_since'] to now: nothing written before it
    counts as a dev test task, so nothing from before floods in and no post
    already in #test-tasks moves. Each pass reads only the issues GitHub says
    changed since the last (state['dev_seen'], GitHub's own update time of
    the last issue read), so an untouched issue costs nothing. An issue
    Discord refused is read again on the next pass.
    Returns the issue numbers posted, edited and removed.
    """
    loop = asyncio.get_running_loop()
    since = state.get('dev_since')
    if not since:
        state['dev_since'] = since = now or _utc_stamp()
        state['_dirty'] = True
    mark = state.get('dev_seen') or since
    rec = state.setdefault('dev', {})
    read = state.setdefault('dev_read', {})
    changed = await loop.run_in_executor(None, github_changed_since, mark, get)
    posted, edited, removed, refused = [], [], [], []
    newest = mark
    for num in sorted(changed):
        key = str(num)
        issue = changed[num]
        upd = str(issue.get('updated_at') or '')
        newest = max(newest, upd)
        have = rec.get(key)
        if read.get(key) == upd and (not have or have.get('form') == DEV_FORM):
            continue            # read at this update time on an earlier pass
        comments = await loop.run_in_executor(None, github_comments, num, get)
        post = dev_post_of(issue, comments, since)
        try:
            if post is None:
                if have:
                    await _forum_drop(forum, have['thread_id'])
                    rec.pop(key, None)
                    removed.append(num)
            else:
                title, body, tags = post
                sig = _sig(title, body, tags)
                if have and have.get('sig') != sig:
                    if await _forum_edit(forum, have['thread_id'], title, body, tags):
                        edited.append(num)
                    else:
                        rec.pop(key, None)     # deleted by hand: made again
                        have = None
                if have:
                    have.update(sig=sig, updated=upd, form=DEV_FORM)
                else:
                    th = await _forum_post(forum, title, body, tags, me_id)
                    rec[key] = {'thread_id': th.id, 'channel_id': forum.id,
                                'sig': sig, 'updated': upd, 'form': DEV_FORM}
                    if save:
                        save(state)    # straight away, so a crash cannot double it
                    posted.append(num)
        except discord.HTTPException:
            refused.append(upd)
            continue
        read[key] = upd
        state['_dirty'] = True
    # GitHub's since is inclusive, so the next pass starts at the newest
    # update read, or at the oldest one Discord refused, to try it again.
    mark = min([newest] + refused)
    if state.get('dev_seen') != mark:
        state['dev_seen'] = mark
        state['_dirty'] = True
    for key in [k for k, v in read.items() if v < mark]:
        read.pop(key, None)
        state['_dirty'] = True
    return posted, edited, removed


def adopt_task(number, thread_id, path=None):
    """Records a test task post made by hand (--post-task) as issue number's,
       so later passes edit it and take it down if the issue reopens. Run
       with the bot stopped: the running bot holds the file in memory."""
    path = path or KNOWN_STATE
    state = _state_read(path)
    if state is None:
        raise RuntimeError('%s will not read; nothing was changed' % path)
    state.setdefault('tasks', {})[str(int(number))] = {
        'thread_id': int(thread_id), 'channel_id': None, 'sig': '', 'updated': ''}
    _state_write(path, state)
    return 'issue %d now owns test task post %d' % (int(number), int(thread_id))


def issue_tags_found(issue):
    names = _labels(issue)
    return any(l in names for l in KNOWN_LABELS)


def _known_save(state, path=None):
    clean = dict((k, v) for k, v in state.items() if not k.startswith('_'))
    _state_write(path or KNOWN_STATE, clean)
    state.pop('_dirty', None)


async def watch_known_issues():
    await client.wait_until_ready()
    if not os.environ.get('GITHUB_TOKEN', '').strip():
        log('known issues: no GITHUB_TOKEN in bot.env.json, so #%s, #%s and '
            '#%s are not kept' % (KNOWN_NAME, TASKS_NAME, DEV_TASKS_NAME))
        return
    state = _state_read(KNOWN_STATE)
    if state is None:
        log('known issues: %s will not read, so nothing is posted until it is '
            'fixed by hand (posting from empty would double every post)'
            % KNOWN_STATE)
        return
    said_text = said_dev = False
    while not client.is_closed():
        try:
            known = tasks = dev = None
            for g in client.guilds:
                known = known or _channel_named(g, KNOWN_NAME, ('forum',))
                tasks = tasks or _channel_named(g, TASKS_NAME, ('forum',))
                # By the id the one-time setup recorded, read each pass so a
                # setup run while the bot is up is picked up without a restart.
                dev = dev or dev_tasks_forum(g)
                if (dev is None and not said_dev
                        and _setup_rec(g).get('dev_tasks_id')):
                    log('known issues: the #%s recorded in %s (id %s) is not on '
                        'the server, so dev test tasks are not posted. The '
                        'one-time step (python bot.py --setup-channels --apply) '
                        'makes it again.' % (DEV_TASKS_NAME, SETUP_STATE,
                                             _setup_rec(g).get('dev_tasks_id')))
                    said_dev = True
                if known is None and not said_text and _channel_named(g, KNOWN_NAME, ('text',)):
                    log('known issues: #%s is still a text channel. The one-time '
                        'step (python bot.py --setup-channels --apply) makes it '
                        'a forum.' % KNOWN_NAME)
                    said_text = True
            me = getattr(client.user, 'id', None)
            if known is not None:
                posted, edited, removed = await known_issues_once(
                    known, state, save=_known_save, me_id=me)
                if posted or edited or removed:
                    log('known issues: posted %s, edited %s, removed %s'
                        % (posted or 'none', edited or 'none', removed or 'none'))
            if tasks is not None:
                posted, edited, removed = await test_tasks_once(
                    tasks, state, save=_known_save, me_id=me)
                if posted or edited or removed:
                    log('test tasks: posted %s, edited %s, removed %s'
                        % (posted or 'none', edited or 'none', removed or 'none'))
            if dev is not None:
                posted, edited, removed = await dev_tasks_once(
                    dev, state, save=_known_save, me_id=me)
                if posted or edited or removed:
                    log('dev test tasks: posted %s, edited %s, removed %s'
                        % (posted or 'none', edited or 'none', removed or 'none'))
            if state.get('_dirty'):
                _known_save(state)
        except Exception as e:
            # Never the URL with the token, and never the token: the request
            # carries it in a header, which str(e) does not print.
            log('known issues: a pass failed: %s' % type(e).__name__)
        await asyncio.sleep(KNOWN_EVERY)


# ----------------------------------------------------- the staff channel --
#
# Where the watchdog's messages are said. There used to be a site watcher here
# as well, asking https://thornswood.net every five minutes since the Caddy
# outage of 21 September. The watchdog on the VPS asks the same address (its
# caddy check), so one outage was two messages from two watchers; since #447
# the watchdog decides and this only delivers (watch_services, below).


async def watch_say(text):
    """
    Say it once, in the staff channel, found by id. True when it was said.

    Nothing is guessed and nothing falls back to another channel. If that id is
    not a channel this bot can see, it says so in the bot log and stays quiet in
    Discord, because the only channel it could fall back to by name is the
    public one.
    """
    if not WATCH_ID:
        log('watch: no channel id, so nothing was said. dev-channel.txt is '
            'missing or unreadable, or set WATCH_CHANNEL_ID in bot.env.json '
            'on the VPS.')
        return False
    ch = client.get_channel(WATCH_ID)
    if ch is None:
        log('watch: channel %d is not one this bot can see, so nothing was '
            'said.' % WATCH_ID)
        return False
    try:
        # The text is the watchdog's own sentence, which can carry a name
        # or a line from somewhere else. Mentions stay off, so @everyone
        # in it is text and not a ping. Discord honors allowed_mentions
        # even when the text still says @everyone.
        await ch.send(text, allowed_mentions=discord.AllowedMentions.none())
        return True
    except Exception:
        log('watch: could not post in #%s:\n' % getattr(ch, 'name', WATCH_ID)
            + traceback.format_exc())
        return False


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
# answering, and since issue #447 it also decides what is down: one message
# when a thing dies and one when it is back, however long it stays down and
# however often it flaps. It writes them to alerts.jsonl in its folder, one
# JSON line each (id, at, service, kind, text). This says each one in the
# staff channel, by id through watch_say, which has no public fallback, and
# writes its id to alerts-sent-bot.txt, so it is said once across restarts of
# the bot too.
#
# When this bot is down, or up and not posting, the watchdog posts the message
# itself through a webhook kept on the box and writes its id to
# alerts-sent-webhook.txt. This reads that list too, so what the webhook said
# is not said again when the bot comes back.
#
# The watchdog decides and this only delivers, so there is no counting here.
# It replaced a reader of watch.log that tried to work out outages from the
# watchdog's sentences, and repeated "needs a look" every hour.
# tests\test-watch-alerts.ps1 drives the watchdog, and test-watch-services.py
# drives this against an outbox the real watchdog wrote.
#
# WHAT IT CANNOT CATCH is the whole box going down, which takes the watchdog
# with it. That needs something off the machine (issue #448).
WATCH_ALERTS = os.path.join(WATCH_DIR, 'alerts.jsonl')
WATCH_SENT_BOT = os.path.join(WATCH_DIR, 'alerts-sent-bot.txt')
WATCH_SENT_HOOK = os.path.join(WATCH_DIR, 'alerts-sent-webhook.txt')
# The watchdog's $alertMaxAge: a message a day late is noise, not news.
WATCH_ALERT_MAX_AGE = 24 * 3600


def watch_alerts_due(lines, sent, now):
    """
    The (id, text) of each message in the outbox still to be said, in order.

    lines are the outbox's lines, sent every id already said by the bot or the
    webhook, now the time in unix seconds. A line that is not a message is
    skipped rather than stopping the rest, and so is one older than
    WATCH_ALERT_MAX_AGE. An id twice in the outbox is said once.
    """
    out = []
    seen = set(sent)
    for raw in lines:
        try:
            a = json.loads(raw)
            aid = str(a['id']).strip()
            text = str(a['text'])
            at = int(a['at'])
        except Exception:
            continue
        if not aid or not text.strip() or aid in seen:
            continue
        if now - at > WATCH_ALERT_MAX_AGE:
            continue
        seen.add(aid)
        out.append((aid, text[:1900]))
    return out


def _watch_lines(path):
    """
    Every whole, non-empty line of path, [] when there is no such file, and
    None when it is there and cannot be read, so an unreadable outbox is never
    taken for an empty one.

    A last line with no line ending is left for the next read: the watchdog
    may be halfway through writing it.
    """
    try:
        with open(path, 'rb') as f:
            data = f.read()
    except FileNotFoundError:
        return []
    except Exception:
        return None
    parts = data.decode('utf-8-sig', errors='replace').split('\n')
    return [p.strip() for p in parts[:-1] if p.strip()]


def _watch_mark(aid):
    """Write down that the bot said it. Blocking, so run through an executor."""
    with open(WATCH_SENT_BOT, 'a', encoding='ascii', errors='replace') as f:
        f.write(aid + '\r\n')


async def watch_services():
    """
    Every WATCH_READ_EVERY seconds, say what the watchdog's outbox holds that
    nobody has said yet.

    A message that could not be said is left unmarked and the rest of that
    round waits, so they stay in order; the watchdog posts it through its
    webhook once it has waited long enough.

    Nothing in here may end the loop: a watcher that dies quietly looks
    exactly like everything being fine.
    """
    await client.wait_until_ready()
    loop = asyncio.get_running_loop()
    said = set()
    unreadable = False
    log('services: saying what %s holds, every %ds, in channel %d'
        % (WATCH_ALERTS, WATCH_READ_EVERY, WATCH_ID))

    while not client.is_closed():
        try:
            lines = await loop.run_in_executor(None, _watch_lines, WATCH_ALERTS)
            mine = await loop.run_in_executor(None, _watch_lines, WATCH_SENT_BOT)
            hook = await loop.run_in_executor(None, _watch_lines, WATCH_SENT_HOOK)
            if lines is None or mine is None or hook is None:
                if not unreadable:
                    log('services: could not read the watchdog\'s files in %s, '
                        'trying again every %ds' % (WATCH_DIR, WATCH_READ_EVERY))
                unreadable = True
            else:
                unreadable = False
                due = watch_alerts_due(lines, said | set(mine) | set(hook),
                                       int(time.time()))
                for aid, text in due:
                    if not await watch_say(text):
                        break
                    said.add(aid)
                    log('services: said ' + aid)
                    await loop.run_in_executor(None, _watch_mark, aid)
        except Exception:
            log('services: the check itself failed, carrying on:\n'
                + traceback.format_exc())
        await asyncio.sleep(WATCH_READ_EVERY)


def report_text(row):
    """
    One report from the public page, as the staff channel reads it.

    Every word of it was typed by a stranger with no account, so it is escaped
    before it goes anywhere near Discord: an @everyone in a title is text, not
    a ping, and a masked link is shown as what it is. as_typed is the same
    escaping the ticket threads use.
    """
    clean = as_typed

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
# for-bot\moderation.log beside each game server, on this same box, and this
# says each new line once in the staff channel, so the record is outside the
# game and in front of the rest of staff. A file rather than a request, for the
# same reason as watch_trouble: no new secret, port or ticket.
#
# for-bot, not private (#2321): private is SYSTEM's and Administrators' alone,
# and a rule on one file in it could only be given once the gamemode had made
# the file, long after the install that gives it. Install-Bot.ps1 gives the
# bot's account read on the for-bot folder, which a file made later takes.
MODERATION_LOGS = [
    ('live', os.environ.get('MODERATION_LOG',
                            r'C:\Thornswood-Server\for-bot\moderation.log')),
    ('dev', os.environ.get('MODERATION_LOG_DEV',
                           r'C:\Thornswood-Server-Dev\for-bot\moderation.log')),
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
    # An admin undoing a PK made by mistake (#1010, 29 September).
    'unpk': 'undid the PK of %s, so the character can be played again',
    'note': 'wrote a note on %s',
    # Not staff: somebody's own /stuck (#414), said as its why reads.
    'stuck': 'used /stuck',
    # Not staff either: the server took somebody idle out of the world (#1142).
    'idle': 'was moved out for being idle',
}


def moderation_text(where, row):
    """
    One line of moderation.log as the staff channel reads it, or None for a
    line that is not one. Names and reasons were typed in the game, so they
    are escaped: nothing in them can ping anybody or dress itself up.
    """
    if not isinstance(row, dict) or row.get('did') not in _MOD_DID:
        return None

    clean = as_typed

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

    # Moved out of the world for being idle (#1142): nobody did it to them, so
    # it reads as what happened and why, which the gamemode writes.
    if row['did'] == 'idle':
        why = clean(row.get('why'), 600) or 'nothing from their game for too long'
        return ('**Idle on the %s server:** %s was taken back to the character choice and put in line: %s'
                % (where, person(row.get('whoName'), row.get('who')), why))[:1900]

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
    (lines, why). lines is every whole line in one moderation.log, [] when
    there is no file yet (no staff action on that server so far), None when it
    could not be read, and then why says what refused it. A last line with no
    line ending is left for the next look, the same as _watch_log_lines.
    """
    try:
        with open(path, 'rb') as f:
            data = f.read()
    except FileNotFoundError:
        return [], ''
    except Exception as e:
        return None, '%s: %s' % (type(e).__name__, e)
    parts = data.decode('utf-8-sig', errors='replace').split('\n')
    return [p.rstrip('\r') for p in parts[:-1] if p.strip()], ''


def _moderation_unreadable(unread, where, path, why):
    """
    Say in bot.log when one moderation.log cannot be read, and when it can be
    again, once each rather than every look (#2321). Until #2321 a refused
    read was skipped with nothing logged, so a server whose staff log the
    bot's account could not open said nothing anywhere.
    """
    if why and unread.get(where) != why:
        unread[where] = why
        log('moderation: cannot read %s (%s), so staff actions on %s are not '
            'said in the staff channel until it can be. Install-Bot.ps1 gives '
            'the bot\'s account read on that folder.'
            % (path, why, 'the site' if where == 'site' else 'the %s server' % where))
    elif not why and where in unread:
        del unread[where]
        log('moderation: %s can be read again' % path)


async def watch_moderation():
    """
    Say each new staff action from the game in the staff channel, once.

    The lines already in each file when this starts are treated as said, as in
    watch_trouble, or every restart of the bot would repeat the history. A
    file that cannot be read is skipped for that look rather than read as
    empty, and said in bot.log. Nothing in here may end the loop.
    """
    await client.wait_until_ready()
    loop = asyncio.get_running_loop()
    seen = {}
    unread = {}
    for where, path in MODERATION_LOGS:
        lines, why = await loop.run_in_executor(None, _moderation_lines, path)
        seen[where] = set(lines) if lines is not None else None
        _moderation_unreadable(unread, where, path, why)
    log('moderation: reading %s every %ds'
        % (', '.join(p for _, p in MODERATION_LOGS), MODERATION_EVERY))

    while not client.is_closed():
        try:
            for where, path in MODERATION_LOGS:
                lines, why = await loop.run_in_executor(None, _moderation_lines, path)
                _moderation_unreadable(unread, where, path, why)
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


# ------------------------------------------------------------- heartbeat --
# How the watchdog tells a running bot from a working one (issue #449).
#
# The watchdog on the VPS used to know one thing about the bot: whether a
# python process with Thornswood-Bot in its command line was alive. A bot
# stuck logging in, hung, or cut off from Discord and never getting back is
# still that process, so the one outage the bot exists to tell staff about,
# itself, looked fine. So this writes heartbeat.json beside this file every
# HEARTBEAT_EVERY seconds: its pid, when it started, when it wrote it,
# whether it is connected to Discord, when it last was, and when it last
# handled something Discord sent it and what. The watchdog reads it
# (BeatProblem in scripts\vps\Watch-Services.ps1) and treats ten quiet
# minutes of any of those as the bot being down while its process runs.
#
# It is written from its own loop, so a hung event loop stops it, which is
# the point. Written to a temporary file and renamed over the old one, so
# the watchdog never reads half of one.
HEARTBEAT_FILE = os.environ.get(
    'HEARTBEAT_FILE',
    os.path.join(DATA_DIR, 'heartbeat.json'))
HEARTBEAT_EVERY = _int_env('HEARTBEAT_EVERY', 60)

# The fields the watchdog reads. test-heartbeat.py checks the two agree.
_beat = {
    'pid': os.getpid(),
    'started': int(time.time()),
    'connected': False,
    'connected_at': 0,
    'last_event': 0,
    'last_event_type': '',
}
_beat_failed = False


def beat_record(now, closed=False):
    """What heartbeat.json says at unix time now. closed is the client having
       been closed, which no event says."""
    if closed:
        _beat['connected'] = False
    if _beat['connected']:
        _beat['connected_at'] = int(now)
    rec = dict(_beat)
    rec['written'] = int(now)
    return rec


def beat_write(rec, path=None):
    """Put rec in heartbeat.json. True when it is there. A failure is said in
       bot.log once, not every minute, and never stops the bot."""
    global _beat_failed
    path = path or HEARTBEAT_FILE
    tmp = path + '.tmp'
    try:
        with open(tmp, 'w', encoding='utf-8') as f:
            json.dump(rec, f)
        os.replace(tmp, path)
        _beat_failed = False
        return True
    except Exception:
        if not _beat_failed:
            log('could not write ' + path + ', so the watchdog cannot tell '
                'whether this bot is on Discord:\n' + traceback.format_exc())
        _beat_failed = True
        return False


def beat_now():
    return beat_write(beat_record(time.time(), client.is_closed()))


async def heartbeat():
    """Started once, in setup_hook. Runs until the process ends."""
    while True:
        beat_now()
        await asyncio.sleep(HEARTBEAT_EVERY)


def beat_connected(on):
    _beat['connected'] = bool(on)
    beat_now()


@client.event
async def on_connect():
    beat_connected(True)


@client.event
async def on_resumed():
    beat_connected(True)


@client.event
async def on_disconnect():
    beat_connected(False)


@client.event
async def on_socket_event_type(event_type):
    # Every event Discord sends, whether or not anything here handles it.
    # Kept in memory only; the loop above writes it.
    _beat['last_event'] = int(time.time())
    _beat['last_event_type'] = str(event_type)


# ----------------------------------------------------------- uptime ping --
# The heartbeat above is read on the box, by the watchdog, and a box that is
# off, frozen or cut off reads nothing and says nothing. So the bot also pings
# an outside monitor (Patrick, 29 Sep: "I want the bot too as well"): one GET
# to PING_URL every PING_EVERY seconds while it is on Discord. When the pings
# stop for longer than the monitor's grace, the monitor sends its alert,
# whether the bot hung, lost Discord or stopped, or the whole VPS went down,
# and whether or not One is on.
#
# PING_URL lives only in bot.env.json on the VPS, put there by
# .\scripts\deploy\Install-Bot.ps1 -SetPing on ssh's standard input. Whoever
# has it can keep the monitor quiet, so it is never logged, not even in an
# error. Each ping runs on a worker thread with its own timeout, so a slow or
# dead monitor never holds up anything Discord sends, and a ping still in
# flight is never doubled. It is sent from the event loop, so a hung bot stops
# pinging, which is the point. A failure is said once per outage and once
# when it works again; nothing here can stop the bot.
PING_URL = os.environ.get('PING_URL', '').strip()
PING_EVERY = _int_env('PING_EVERY', 60)
PING_TIMEOUT = _int_env('PING_TIMEOUT', 10)
# How often the loop looks, so the first ping follows connecting by seconds.
PING_LOOK = 5

_ping = {'down': False, 'ok_once': False}


def ping_shape_ok(url):
    """A web address, and nothing that could be a file or a command."""
    return (url.lower().startswith(('https://', 'http://'))
            and not any(c.isspace() for c in url))


def _ping_scrub(text, url):
    """text with the address, and its path, taken out."""
    text = str(text)
    for part in (url, url.split('://', 1)[-1]):
        if part:
            text = text.replace(part, 'the ping address')
    tail = url.split('://', 1)[-1].split('/', 1)
    if len(tail) == 2 and len(tail[1]) > 3:
        text = text.replace(tail[1], 'the ping address')
    return text


def ping_once(url, timeout=None):
    """One ping. True when the monitor answered 2xx. Never raises."""
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'thornswood-bot'})
        with urllib.request.urlopen(req, timeout=timeout or PING_TIMEOUT) as r:
            r.read(256)
            code = r.status
        ok = 200 <= code < 300
        why = 'it answered %d' % code
    except Exception as e:
        ok = False
        code = getattr(e, 'code', None)
        if isinstance(code, int):
            why = 'it answered %d' % code
        else:
            why = '%s: %s' % (type(e).__name__, getattr(e, 'reason', None) or e)
    try:
        if ok:
            if _ping['down']:
                log('uptime ping: the outside monitor hears from this bot again')
            elif not _ping['ok_once']:
                log('uptime ping: reached the outside monitor, and pings it every '
                    '%ds while on Discord' % PING_EVERY)
            _ping['down'] = False
            _ping['ok_once'] = True
        else:
            if not _ping['down']:
                log('uptime ping FAILED (%s). The outside monitor alerts if it '
                    'hears nothing past its grace. Said once until it works '
                    'again.' % _ping_scrub(why, url))
            _ping['down'] = True
    except Exception:
        pass
    return ok


async def uptime_ping():
    """Started once, in setup_hook. Runs until the process ends, or returns
       at once when there is nothing to ping."""
    if not PING_URL:
        log('uptime ping: PING_URL is not set in bot.env.json, so no outside '
            'monitor hears from this bot. Install-Bot.ps1 -SetPing sets it.')
        return
    if not ping_shape_ok(PING_URL):
        log('uptime ping: PING_URL in bot.env.json is not a web address, so '
            'nothing is sent. Install-Bot.ps1 -SetPing sets it again.')
        return
    loop = asyncio.get_running_loop()
    inflight = None
    last = None
    while True:
        try:
            now = time.monotonic()
            if (_beat['connected'] and not client.is_closed()
                    and (inflight is None or inflight.done())
                    and (last is None or now - last >= PING_EVERY)):
                last = now
                inflight = loop.run_in_executor(None, ping_once, PING_URL)
        except Exception:
            log('uptime ping: could not start one, carrying on:\n'
                + _ping_scrub(traceback.format_exc(), PING_URL))
        await asyncio.sleep(PING_LOOK)


# on_ready fires again on every reconnect, and a second loop would double every
# message this ever sends.
_watching = False


# What was last registered with Discord, so a restart does not do it all
# again. Next to the code, because that folder is the bot's own and a deploy
# that replaces it is a deploy that may have changed the commands anyway.
STAMP = os.path.join(DATA_DIR, 'commands-synced.json')

# Set FORCE_COMMAND_SYNC=1 in bot.env.json to make the next start register them
# whatever the stamp says. For the case where Discord has them and this file
# does not, which is a deploy that landed on a fresh folder.
FORCE_SYNC = _int_env('FORCE_COMMAND_SYNC', 0)


def _children_of(command):
    """
    A group's subcommands, and nothing at all for a plain command.

    Read by attribute rather than by type, because the ready harness stands a
    counting object in for the tree and never imports a real Group.
    """
    got = getattr(command, 'commands', None)
    return list(got) if got else []


def _command_names():
    """
    Every name Discord has to be told about, sorted: the groups, and their
    children under them.

    THE SCHEME. A child is written under its parent with a space between
    them, the way a person types it in the picker: `live-smoke` is in the
    list, and so are `live-smoke report` and the rest. Nested groups go on the
    same way, `parent child grandchild`. The stamp still holds a sorted list
    of plain strings, so a stamp written before this reads back fine; it is
    missing every child, which is exactly why the next start syncs.

    WHY IT IS NOT THE TOP LEVEL ALONE. It was, and adding a subcommand to a
    group that was already registered left this list identical. `/live-smoke
    report` was merged and deployed, the start said "slash commands already
    registered", no sync went to Discord, and the picker kept offering the
    three subcommands it had. It took FORCE_COMMAND_SYNC to put it there. A
    child is a command as far as the picker is concerned, so it is a name
    here.
    """
    out = []

    def walk(commands, prefix):
        for c in commands:
            name = (prefix + ' ' + c.name) if prefix else c.name
            out.append(name)
            walk(_children_of(c), name)

    walk(tree.get_commands(), '')
    return sorted(out)


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
            log('registered in "%s": %s'
                % (g.name, ', '.join('/' + n for n in want) or 'nothing'))
        except Exception:
            # Named rather than said as "the commands", because which ones
            # they are is the first thing anybody asks when none appear.
            log('could not register %s in "%s", the buttons still work:\n'
                % (', '.join('/' + n for n in want), g.name)
                + traceback.format_exc())
    try:
        tree.clear_commands(guild=None)
        await tree.sync()
    except Exception:
        log('could not clear the global commands, so a command may appear '
            'twice in the picker:\n' + traceback.format_exc())

    _stamp_write(want, synced)


@client.event
async def on_ready():
    global _watching
    if not _watching:
        _watching = True
        asyncio.create_task(watch_trouble())
        asyncio.create_task(watch_services())
        asyncio.create_task(watch_reports())
        asyncio.create_task(watch_moderation())
        asyncio.create_task(watch_known_issues())

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


def run_cli(argv):
    """
    The by-hand jobs, on a connection of their own that starts none of the
    bot's watchers, panels or command sync, and closes when it is done:

      --setup-channels [--apply]   the one-time setup, a preview without --apply
      --post-task --title T --body B|--body-file F [--tag Main]
      --adopt-task --issue N --thread ID   (offline; with the bot stopped)

    Returns the exit code.
    """
    import argparse
    ap = argparse.ArgumentParser(prog='bot.py')
    ap.add_argument('--env-file')
    ap.add_argument('--setup-channels', action='store_true')
    ap.add_argument('--apply', action='store_true')
    ap.add_argument('--post-task', action='store_true')
    ap.add_argument('--title')
    ap.add_argument('--body')
    ap.add_argument('--body-file')
    ap.add_argument('--tag', choices=[TASK_POST_TAG], default=TASK_POST_TAG)
    ap.add_argument('--guild', type=int, default=0)
    ap.add_argument('--adopt-task', action='store_true')
    ap.add_argument('--issue', type=int)
    ap.add_argument('--thread', type=int)
    a = ap.parse_args(argv)
    if a.adopt_task:
        if not a.issue or not a.thread:
            ap.error('--adopt-task needs --issue and --thread')
        print(adopt_task(a.issue, a.thread))
        return 0
    if a.post_task:
        body = a.body
        if a.body_file:
            with open(a.body_file, encoding='utf-8-sig') as f:
                body = f.read()
        if not a.title or not body:
            ap.error('--post-task needs --title and --body or --body-file')
    out = {'code': 0}
    cli = discord.Client(intents=discord.Intents(guilds=True))

    @cli.event
    async def on_ready():
        try:
            guilds = [g for g in cli.guilds if not a.guild or g.id == a.guild]
            if not guilds:
                print('the bot is in no server%s' % (
                    ' with id %d' % a.guild if a.guild else ''))
                out['code'] = 1
            for g in guilds:
                print('"%s" (%d):' % (g.name, g.id))
                if a.setup_channels:
                    for line in await channel_setup(g, apply=a.apply):
                        print('  ' + line)
                    if not a.apply:
                        print('  (preview only; add --apply to do it)')
                else:
                    thread, said = await post_test_task(g, a.title, body, a.tag)
                    print('  ' + said)
                    if thread is None:
                        out['code'] = 1
        except Exception:
            traceback.print_exc()
            out['code'] = 1
        finally:
            await cli.close()

    cli.run(TOKEN, log_handler=None)
    return out['code']


# Under a main guard, so that importing this file reads it instead of running
# it. Without one, `import bot` connects to Discord with whatever token is in
# env, which is why nothing in here had ever been tested: there was no way to
# get at a function without starting a bot. Install-Bot.ps1 launches it as
# `python bot.py`, where __name__ is __main__, so this changes nothing about
# how it runs on the VPS.
if __name__ == '__main__':
    if ('--setup-channels' in sys.argv or '--post-task' in sys.argv
            or '--adopt-task' in sys.argv):
        raise SystemExit(run_cli(sys.argv[1:]))
    # One heartbeat before anything can hang, so a bot stuck logging in has
    # this run's pid in the file and the watchdog can say how long it has sat.
    beat_now()
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
