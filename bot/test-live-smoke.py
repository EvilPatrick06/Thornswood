"""
test-live-smoke.py

The living Live smoke checklist in #test-tasks: what it reads, who may run it,
who may mark a row, and the one rule that is not about Discord at all, which is
that a mark never leaves it.

What is worth pinning here, in the order the locks were given on 1 October:

  the export        the bot reads live-smoke-discord-export.json and nothing
                    else, by schema and not by hope, and the Live set in it is
                    the seven rows the vault carries
  the skip rule     the forge rule on the double craft row is on the message a
                    tester reads, so Skip is an informed mark rather than a
                    guess
  who may start     Owner, Dev and Lead Gamemaster, by name, both spellings of
                    the last one, and a Moderator alone is not one of them
  who may mark      a person, never an agent
  where a mark goes on the Discord message it was pressed on, and nowhere
                    else: not the site, not a file, not this bot's log

The real bot module is imported, so a rename or a reword fails here rather
than in the channel, and the functions driven are pure: no Discord, no token,
no network. The last block reads bot.py's own source, because "it must not
write a mark to a file" is a claim about code that no stand-in can prove.

Read only. Never connects to anything.
"""
import asyncio
import datetime
import json
import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
# bot.py refuses to load without one, and never uses it unless client.run is
# called, which nothing here does.
os.environ.setdefault('DISCORD_TOKEN', 'not-a-real-token')

import bot  # noqa: E402

PASS = []
FAIL = []


def yes(what, cond):
    (PASS if cond else FAIL).append(what)
    print(('PASS  ' if cond else 'FAIL  ') + what)


class Role(object):
    def __init__(self, name):
        self.name = name


class Who(object):
    """Somebody pressing a button, or running a command."""

    def __init__(self, roles=(), bot=False, uid=1, display_name='Somebody'):
        self.roles = [Role(r) for r in roles]
        self.bot = bot
        self.id = uid
        self.display_name = display_name


class Guild(object):
    def __init__(self, roles):
        self.roles = [Role(r) for r in roles]


class Channel(object):
    def __init__(self, name):
        self.name = name


class Thread(object):
    def __init__(self, name, parent):
        self.name = name
        self.parent = parent


def tmp_json(what):
    """An export on disk, for the loader to refuse or accept."""
    fd, path = tempfile.mkstemp(prefix='ts-live-smoke-', suffix='.json')
    with os.fdopen(fd, 'w', encoding='utf-8') as f:
        if isinstance(what, str):
            f.write(what)
        else:
            json.dump(what, f)
    return path


# --------------------------------------------------- the export as shipped --
EXPORT = os.path.join(HERE, 'live-smoke-discord-export.json')
yes('the export is deployed beside bot.py, where the bot looks for it',
    os.path.isfile(EXPORT) and bot.LIVE_SMOKE_EXPORT == EXPORT)

live = bot.live_smoke_load()
items = bot.live_smoke_items(live)

yes('it is the schema this bot reads', live['schema'] == 'thornswood.live-smoke.v1')
yes('and it carries the Live 7', len(items) == 7)
yes('in the order the vault gives them',
    [i['order'] for i in items] == [1, 2, 3, 4, 5, 6, 7])
yes('each row has an id, a label and the line a tester reads',
    all(i['id'] and i['label'] and i['discord_line'] for i in items))
yes('the rows are the ones the vault names, by their tickets',
    [i['tickets'] for i in items] ==
    [['381'], ['517'], ['999', '428'], ['1396'], ['505', '517'], ['1402'], ['509']])
yes('the marks are Pass, Fail, Skip and Fail-known, in that order',
    list(bot.LIVE_SMOKE_MARKS) == ['Pass', 'Fail', 'Skip', 'Fail-known']
    and list(live['marks']) == list(bot.LIVE_SMOKE_MARKS))
yes('and the export says the channel is Test-Tasks, created new rather than '
    'test-these renamed',
    live['channel']['name'] == 'Test-Tasks' and live['channel']['create_new'] is True
    and live['channel']['do_not_rename'] == 'test-these')

# ------------------------------------------------------- loading it wrong --
def refused(what):
    """The words the loader refuses this with, or '' when it took it."""
    path = tmp_json(what)
    try:
        bot.live_smoke_load(path)
        return ''
    except ValueError as e:
        return str(e)
    finally:
        os.unlink(path)


good = dict(live)
yes('an export of another schema is refused, and the refusal says which',
    'thornswood.live-smoke.v1' in refused(dict(good, schema='thornswood.live-smoke.v2')))
yes('so is one with no schema at all', refused(dict(good, schema=None)) != '')
yes('so is one with no rows in it', 'no items' in refused(dict(good, items=[])))
yes('so is a file that is not JSON', 'readable JSON' in refused('{not json at all'))

try:
    bot.live_smoke_load(os.path.join(HERE, 'no-such-export.json'))
    gone = ''
except ValueError as e:
    gone = str(e)
yes('a missing export says where it should be and who deploys it',
    'There is no Live smoke export' in gone and 'Install-Bot.ps1' in gone)

# An id too long for a button's custom_id is a session Discord refuses part
# way through posting, so it is refused up front instead.
long_id = dict(good, items=[dict(good['items'][0], id='x' * 120)])
yes('a row whose id will not fit on a button is refused before anything is posted',
    'too long to put on a button' in refused(long_id))

# A row with no line for Discord is dropped rather than posted empty.
half = bot.live_smoke_items(dict(good, items=[
    good['items'][0], {'id': 'live-x', 'order': 2, 'discord_line': ''}]))
yes('a row with nothing to read is dropped', [i['id'] for i in half] == ['live-1'])

# Out of order in the file, in order on Discord.
jumbled = bot.live_smoke_items({'items': [
    {'id': 'b', 'order': 2, 'discord_line': 'second'},
    {'id': 'a', 'order': 1, 'discord_line': 'first'}]})
yes('rows are posted in the order the export gives, not the order it lists them',
    [i['id'] for i in jumbled] == ['a', 'b'])

# ---------------------------------------------------------- the skip rule --
double = [i for i in items if i['id'] == 'live-2'][0]
chat = [i for i in items if i['id'] == 'live-1'][0]
said = bot.live_smoke_item_text(double, len(items))

yes('the double craft row carries its skip rule, so nobody guesses at Skip',
    'Skip rule: Skip if no forge on the live channel under test.' in said)
yes('  and names its ticket and its place in the set',
    said.startswith('**Live 2 of 7: Double craft after respawn**') and '#517' in said)
yes('  and still carries the line the vault wrote', double['discord_line'] in said)
yes('a row with no skip rule in the export says nothing about one',
    'Skip rule' not in bot.live_smoke_item_text(chat, len(items)))
yes('the export keeps a skip rule on exactly the one row that has one',
    [i['id'] for i in items if i['skip_rule']] == ['live-2'])
yes('an item message fits in a Discord message',
    all(len(bot.live_smoke_item_text(i, len(items))) < 2000 for i in items))

# --------------------------------------------------------------- the ids --
yes('a button is keyed by its row and its mark',
    bot.live_smoke_custom_id('live-2', 'Fail-known') == 'ls:live-2:Fail-known')
yes('and read back the same way',
    bot.live_smoke_read_id('ls:live-2:Fail-known') == ('live-2', 'Fail-known'))
yes('every button in the set has a different id, and Discord takes all of them',
    len(set(bot.live_smoke_custom_id(i['id'], m)
            for i in items for m in bot.LIVE_SMOKE_MARKS)) == 28
    and all(len(bot.live_smoke_custom_id(i['id'], m)) <= 100
            for i in items for m in bot.LIVE_SMOKE_MARKS))
yes('somebody else\u2019s button is not one of ours',
    bot.live_smoke_read_id('thornswood:close') is None
    and bot.live_smoke_read_id('') is None
    and bot.live_smoke_read_id(None) is None)
yes('a mark that is not a mark is refused',
    bot.live_smoke_read_id('ls:live-2:Passed') is None
    and bot.live_smoke_read_id('ls::Pass') is None)
yes('an id with a colon in it still reads, because the mark is taken off the end',
    bot.live_smoke_read_id('ls:live:2:Pass') == ('live:2', 'Pass'))

# ----------------------------------------------------- who may run the lot --
#
# Patrick locked it on 1 October: Owner, Dev and Lead GM. Not Owner and Dev
# alone, and not the whole of STAFF.
yes('the default is Owner, Dev and Lead Gamemaster, both spellings of the last',
    [n.lower() for n in bot.LIVE_SMOKE_ADMIN_NAMES] ==
    ['owner', 'dev', 'lead gm', 'lead gamemaster'])
yes('and the export asks for the same four names',
    [n.lower() for n in live['session']['admin_roles_default']] ==
    [n.lower() for n in bot.LIVE_SMOKE_ADMIN_NAMES])

yes('the Owner may start a session', bot.is_live_smoke_admin(Who(['Owner'])))
yes('a Dev may', bot.is_live_smoke_admin(Who(['Dev'])))
yes('a Lead GM may', bot.is_live_smoke_admin(Who(['Lead GM'])))
yes('and a Lead Gamemaster may, which is the same person after the scrub',
    bot.is_live_smoke_admin(Who(['Lead Gamemaster'])))
yes('the name is matched whatever its case, the way STAFF_ROLES is',
    bot.is_live_smoke_admin(Who(['lead gamemaster']))
    and bot.is_live_smoke_admin(Who(['OWNER'])))

yes('A MODERATOR ALONE MAY NOT, which is the lock, not an oversight',
    not bot.is_live_smoke_admin(Who(['Moderator'])))
yes('nor may a Gamemaster who is not the lead one',
    not bot.is_live_smoke_admin(Who(['Gamemaster'])))
yes('nor a Loremaster, who is in STAFF_ROLES and not in this',
    'loremaster' in bot.STAFF and not bot.is_live_smoke_admin(Who(['Loremaster'])))
yes('nor a Playtester, who marks rows and does not open sessions',
    not bot.is_live_smoke_admin(Who(['Playtester'])))
yes('nor somebody with no roles at all', not bot.is_live_smoke_admin(Who([])))
yes('this is narrower than STAFF_ROLES and wider than Owner and Dev',
    set(bot.LIVE_SMOKE_ADMIN) != set(bot.STAFF)
    and set(['owner', 'dev']) < set(bot.LIVE_SMOKE_ADMIN))
yes('a Moderator who is also a Lead Gamemaster may, because one role is enough',
    bot.is_live_smoke_admin(Who(['Moderator', 'Lead Gamemaster'])))

# The scrub can rename either of them, and then the env moves the bot without
# a code change. Read the way bot.py reads it, so the two cannot drift.
was = bot.LIVE_SMOKE_ADMIN_NAMES, bot.LIVE_SMOKE_ADMIN
try:
    bot.LIVE_SMOKE_ADMIN_NAMES = ['Owner', 'Dev', 'Head Storyteller']
    bot.LIVE_SMOKE_ADMIN = [n.lower() for n in bot.LIVE_SMOKE_ADMIN_NAMES]
    yes('LIVE_SMOKE_ADMIN_ROLES moves the names without a code change',
        bot.is_live_smoke_admin(Who(['Head Storyteller']))
        and not bot.is_live_smoke_admin(Who(['Lead Gamemaster'])))
finally:
    bot.LIVE_SMOKE_ADMIN_NAMES, bot.LIVE_SMOKE_ADMIN = was

# What a refusal says. A role nobody holds and a role that does not exist are
# different problems and get different words.
here = Guild(['Owner', 'Dev', 'Moderator', 'Playtester', 'Lead Gamemaster'])
no = bot.live_smoke_admin_refusal(here)
yes('a refusal names the roles that may run it',
    'Owner' in no and 'Lead Gamemaster' in no and ' or ' in no)
yes('  and does not send somebody chasing a role that is on the server',
    'Not on this server' not in no)

scrubbed = Guild(['Owner', 'Dev', 'Moderator'])
yes('the roles a scrub took away can be named, for the refusal to use',
    bot.live_smoke_admin_missing(scrubbed) == ['Lead GM', 'Lead Gamemaster'])
yes('and a server carrying one spelling of Lead Gamemaster is not told the '
    'other one is missing, because the two are one role',
    bot.live_smoke_admin_missing(here) == ['Lead GM']
    and 'missing' not in bot.live_smoke_admin_refusal(here))

gone = bot.live_smoke_admin_refusal(Guild(['Moderator', 'Playtester']))
yes('a server with none of them says to set LIVE_SMOKE_ADMIN_ROLES rather than '
    'leaving somebody guessing',
    'LIVE_SMOKE_ADMIN_ROLES' in gone and 'bot.env.json' in gone)
yes('and nothing anywhere here is a role id',
    not any(c.isdigit() for c in ''.join(bot.LIVE_SMOKE_ADMIN_NAMES)))

# ----------------------------------------------------------- who may mark --
yes('AN AGENT MAY NOT MARK A ROW, which is the lock',
    bot.live_smoke_tick_refusal(Who(['Playtester'], bot=True)) is not None)
yes('  and is told so in words rather than ignored',
    'Agents do not mark' in bot.live_smoke_tick_refusal(Who([], bot=True)))
yes('  even holding every role that may start a session',
    bot.live_smoke_tick_refusal(Who(['Owner', 'Dev', 'Lead Gamemaster'],
                                    bot=True)) is not None)
yes('a tester may', bot.live_smoke_tick_refusal(Who(['Playtester'])) is None)
yes('and so may staff', bot.live_smoke_tick_refusal(Who(['Moderator'])) is None)
yes('the deny list is empty in the repository, so no account id is written here',
    bot.LIVE_SMOKE_DENY == set())

was = bot.LIVE_SMOKE_DENY
try:
    bot.LIVE_SMOKE_DENY = set([424242])
    yes('an account named in LIVE_SMOKE_DENY_USER_IDS is refused',
        bot.live_smoke_tick_refusal(Who(['Playtester'], uid=424242)) is not None)
    yes('and everybody else is not',
        bot.live_smoke_tick_refusal(Who(['Playtester'], uid=7)) is None)
finally:
    bot.LIVE_SMOKE_DENY = was

# ---------------------------------------------------- where a mark may go --
tasks = Channel('test-tasks')
yes('a thread under Test-Tasks is a session',
    bot.live_smoke_in_session(Thread('Live smoke 2026-10-02 1.1.101.17', tasks)))
yes('a thread under some other channel is not',
    not bot.live_smoke_in_session(Thread('Live smoke 2026-10-02', Channel('general'))))
yes('and the channel itself is not a session thread',
    not bot.live_smoke_in_session(tasks))
yes('nor is anywhere with no parent at all',
    not bot.live_smoke_in_session(None) and not bot.live_smoke_in_session(Channel('')))
yes('the channel this looks for is the new one, not the deleted test-these',
    bot.LIVE_SMOKE_CHANNEL == ['test-tasks'])

# ------------------------------------------------------------- the marks --
row = bot.live_smoke_item_text(double, len(items))

one = bot.live_smoke_mark(row, 'Ataxayk', 'Pass')
yes('a mark goes on the row under a heading of its own',
    one.startswith(row) and one.endswith('Ataxayk: Pass'))
yes('  and the line the vault wrote is still there', double['discord_line'] in one)
yes('  and so is the skip rule', 'Skip rule:' in one)

two = bot.live_smoke_mark(one, 'Djinn', 'Skip')
yes('a second person gets their own line, and the first is left alone',
    'Ataxayk: Pass' in two and 'Djinn: Skip' in two)

again = bot.live_smoke_mark(two, 'Ataxayk', 'Fail-known')
yes('MARKING TWICE CORRECTS THE MARK rather than adding a second one',
    'Ataxayk: Fail-known' in again and 'Ataxayk: Pass' not in again
    and again.count('Ataxayk') == 1)
yes('  and does not touch anybody else\u2019s', 'Djinn: Skip' in again)
yes('  and keeps the order people marked in',
    again.index('Ataxayk') < again.index('Djinn'))

yes('every mark can be written', all(
    ('Ataxayk: ' + m) in bot.live_smoke_mark(row, 'Ataxayk', m)
    for m in bot.LIVE_SMOKE_MARKS))
yes('a name with a colon in it is still one person',
    bot.live_smoke_mark(bot.live_smoke_mark(row, 'a:b', 'Pass'),
                        'a:b', 'Fail').count('a:b') == 1)
yes('and somebody with no name at all does not make a nameless line',
    'Somebody: Pass' in bot.live_smoke_mark(row, '', 'Pass'))

# ------------------------------------------------- the session as posted --
day = datetime.date(2026, 10, 2)
title = bot.live_smoke_title_of(live, '1.1.101.17', day)
yes('the session title is the date and the Settings version',
    title == 'Live smoke 2026-10-02 1.1.101.17')
yes('and it fits in a Discord thread name', len(title) <= 100)
yes('the title format is the one the export asks for',
    live['session']['title_format'] == 'Live smoke {YYYY-MM-DD} {settings_version}')
yes('a session thread is found again by the words it starts with',
    title.startswith(bot.LIVE_SMOKE_TITLE))

opener = bot.live_smoke_opener(title, 'thornswood-one', '1.1.101.17', len(items))
yes('the opener names the live channel, which is the thing a session is of',
    'thornswood-one' in opener)
yes('  and the date and the version, through the title', title in opener)
yes('  and the three required fields are the three the export asks for',
    [f for f in live['session']['required_fields']] ==
    ['date', 'live_channel', 'settings_version'])
yes('  and it says the marks are read by everybody in the thread, so nobody '
    'marks a row thinking it is private',
    'can read the marks' in opener)
yes('  and that they go nowhere else', 'stay in Discord' in opener)
yes('  and that agents do not mark rows', 'Agents do not mark rows' in opener)
yes('  and it fits in a Discord message', len(opener) < 2000)

card = bot.live_smoke_template(live, items)
yes('the checklist post carries every row in the set',
    all((i['label'] in card) for i in items))
yes('  and the skip rule, so it reads without the vault open',
    'Skip rule: Skip if no forge' in card)
yes('  and fits in a Discord message', len(card) < 2000)
yes('  and is found again by the words it starts with',
    card.startswith(bot.LIVE_SMOKE_TEMPLATE_HEAD))

# A set big enough to overflow a message is cut rather than refused by Discord.
big = bot.live_smoke_items({'items': [
    {'id': 'live-%d' % n, 'order': n, 'label': 'A row with a long name ' * 5,
     'discord_line': 'x'} for n in range(1, 40)]})
yes('a Live set too big for one message is cut, not thrown away by Discord',
    len(bot.live_smoke_template({}, big)) < 2000
    and 'the rest is in the export' in bot.live_smoke_template({}, big))

# ------------------------------------------------------- the words rules --
#
# CONTRIBUTING.md: no em dashes, and never the word this bans, in anything
# written for people. Check-Words.ps1 does not read bot.py, so it is read here.
WORDS = [opener, card, bot.live_smoke_admin_refusal(here), gone,
         bot.live_smoke_tick_refusal(Who([], bot=True))]
WORDS += [bot.live_smoke_item_text(i, len(items)) for i in items]
yes('nothing this says to anybody has an em dash in it',
    not any('\u2014' in w for w in WORDS))

# ------------------------------------------- and the mark stays on Discord --
#
# The must-hold Harlan gave on 1 October: no Discord id and no Pass, Fail,
# Skip or Fail-known in the site, a database, a file or any store off Discord.
# No stand-in can show that, because the proof is the absence of a call. So
# the section of bot.py this all lives in is read.
src = open(os.path.join(HERE, 'bot.py'), encoding='utf-8').read()
BANNER = '# ------------------------------------------------------------ live smoke --'
yes('the live smoke code is a section of its own in bot.py', BANNER in src)
rest = src[src.index(BANNER) + len(BANNER):]
section = rest[:rest.index('\n# ---')]

yes('it never pushes anything to the site',
    'push(' not in section and 'push_async' not in section
    and 'urllib' not in section and 'SITE' not in section)
yes('it never writes a file: the export is read, and nothing is written back',
    "'w'" not in section and '"w"' not in section
    and 'json.dump' not in section and 'DATA_DIR' not in section)
yes('  and the one file it opens is the export, read only',
    len(re.findall(r'(?<![\w_])open\(', section)) == 1
    and 'with open(where, encoding=' in section)
yes('the mark handler writes no traceback, because Discord hands back the '
    'message it refused and that message holds names against marks',
    'async def live_smoke_tick' in section
    and 'format_exc' not in section[section.index('async def live_smoke_tick'):
                                    section.index('live_smoke = discord.app_commands.Group')])
yes('nothing in it logs a mark or a display name',
    not any(('log(' in line and any(m in line for m in bot.LIVE_SMOKE_MARKS))
            for line in section.split('\n')))
yes('the agent lock is what Discord says about the account, not a list of ids',
    'getattr(who, \'bot\', False)' in section)
yes('start, reset and refresh all pass through the one admin gate',
    section.count('await _live_smoke_ready(interaction)') == 2
    and 'async def _live_smoke_ready' in section
    and all(('await live_smoke_open(interaction' in section)
            for _ in ('start', 'reset')))

# ------------------------------------------- a session, start to a mark --
#
# The three commands and the button handler, run for real against stand-ins
# that record what would have been asked of Discord. Nothing above this drives
# the gates as a command: this is where a Moderator is turned away by
# /live-smoke start rather than by is_live_smoke_admin, and where an agent
# pressing Pass changes no message.


class Message(object):
    def __init__(self, channel, content):
        self.channel = channel
        self.content = content
        self.author = Who(uid=BOT_ID)
        self.thread = None

    async def create_thread(self, name=None, auto_archive_duration=None):
        self.thread = Session(name, self.channel)
        self.channel.threads.append(self.thread)
        return self.thread

    async def edit(self, content=None, view=None):
        self.content = content

    async def pin(self):
        raise RuntimeError('no Manage Messages, which is on purpose')


class Posted(object):
    """A text channel that keeps what was posted in it."""

    def __init__(self, name):
        self.name = name
        self.sent = []
        self.threads = []

    async def send(self, content, view=None):
        m = Message(self, content)
        self.sent.append((m, view))
        return m

    async def history(self, limit=50):
        for m, _ in reversed(self.sent):
            yield m


class Session(Posted):
    """A thread off an opener. Its parent is what makes a mark allowed."""

    def __init__(self, name, parent):
        Posted.__init__(self, name)
        self.parent = parent
        self.archived = False
        self.locked = False
        self.mention = '<#%s>' % name

    async def edit(self, archived=None, locked=None):
        self.archived = bool(archived)
        self.locked = bool(locked)


class Server(object):
    def __init__(self, roles, channels):
        self.roles = [Role(r) for r in roles]
        self.text_channels = channels


class Answer(object):
    """interaction.response and interaction.followup, counted."""

    def __init__(self):
        self.said = []
        self.deferred = 0
        self.edited = []

    async def send_message(self, text, ephemeral=False):
        self.said.append(text)

    async def send(self, text, ephemeral=False):
        self.said.append(text)

    async def defer(self, ephemeral=False, thinking=False):
        self.deferred += 1

    async def edit_message(self, content=None):
        self.edited.append(content)


class Ask(object):
    def __init__(self, who, guild, channel, message=None):
        self.user = who
        self.guild = guild
        self.channel = channel
        self.message = message
        self.response = Answer()
        self.followup = self.response


BOT_ID = 424242
bot.client = type('C', (object,), {'user': Who(uid=BOT_ID)})()


def ran(coro):
    return asyncio.run(coro)


def server():
    return Posted('test-tasks'), Server(
        ['Owner', 'Dev', 'Moderator', 'Playtester', 'Lead Gamemaster'],
        [Posted('general')])


tasks, guild = server()
guild.text_channels.append(tasks)

# A Moderator, at the command rather than at the helper.
ask = Ask(Who(['Moderator']), guild, tasks)
ran(bot.live_smoke_open(ask, '1.1.101.17', 'thornswood-one', False))
yes('/live-smoke start turns a Moderator away and posts nothing',
    tasks.sent == [] and ask.response.deferred == 0
    and 'start, reset and refresh' in ask.response.said[0])

# The Lead Gamemaster, who may.
ask = Ask(Who(['Lead Gamemaster']), guild, tasks)
ran(bot.live_smoke_open(ask, '1.1.101.17', 'thornswood-one', False))
opened = tasks.sent[0][0]
thread = opened.thread
yes('a Lead Gamemaster opens a session, and it is one opener in the channel',
    len(tasks.sent) == 1 and thread is not None)
yes('  named for the date and the version', thread.name.startswith('Live smoke ')
    and thread.name.endswith('1.1.101.17'))
yes('  with the live channel in the opener', 'thornswood-one' in opened.content)
yes('  and the rows in the thread, not in the channel',
    len(thread.sent) == 7 and len(tasks.sent) == 1)
yes('  one message per row, so no message carries twenty eight buttons',
    all(len(v.children) == 4 for _, v in thread.sent))
yes('  each row carrying the four marks',
    [c.label for c in thread.sent[0][1].children] == list(bot.LIVE_SMOKE_MARKS))
yes('  and the forge skip rule where the export puts it',
    'Skip rule: Skip if no forge' in thread.sent[1][0].content)
yes('  and whoever ran it is told where it is, and only them',
    ask.response.deferred == 1 and 'Session open' in ask.response.said[0])

# A tester marks a row, in the thread.
item, view = thread.sent[1]
press = [c for c in view.children if c.label == 'Pass'][0]
ask = Ask(Who(['Playtester'], uid=5, display_name='Ataxayk'), guild, thread, item)
ran(press.callback(ask))
yes('a tester marks a row and the row itself says so',
    ask.response.edited and 'Ataxayk: Pass' in ask.response.edited[0])
yes('  and nothing is posted anywhere else about it',
    len(tasks.sent) == 1 and len(thread.sent) == 7)

# An agent presses the same button.
item.content = ask.response.edited[0]
ask = Ask(Who(['Playtester'], uid=9, display_name='Some agent', bot=True),
          guild, thread, item)
ran(press.callback(ask))
yes('AN AGENT PRESSING THE SAME BUTTON CHANGES NOTHING',
    ask.response.edited == [] and 'Agents do not mark' in ask.response.said[0])

# The same button, reached from the channel rather than the session thread.
ask = Ask(Who(['Playtester'], uid=5, display_name='Ataxayk'), guild, tasks, item)
ran(press.callback(ask))
yes('and so does pressing one outside a session thread',
    ask.response.edited == [] and 'session thread' in ask.response.said[0])

# Reset: the old session is closed and locked, a new one is opened.
ask = Ask(Who(['Owner']), guild, tasks)
ran(bot.live_smoke_open(ask, '1.1.102.0', 'thornswood-one', True))
yes('reset closes and locks the session that was open',
    thread.archived and thread.locked)
yes('  and opens a new one rather than rewriting the old ticks',
    len(tasks.sent) == 2 and len(tasks.threads) == 2
    and 'Ataxayk: Pass' in item.content)
yes('  and says the one before it is closed',
    'closed and locked' in ask.response.said[0])

# Refresh: the checklist post, made once and then edited.
fresh, guild2 = server()
guild2.text_channels.append(fresh)
ask = Ask(Who(['Dev']), guild2, fresh)
ran(bot.live_smoke_refresh.callback(ask))
yes('refresh posts the checklist when there is none',
    len(fresh.sent) == 1
    and fresh.sent[0][0].content.startswith(bot.LIVE_SMOKE_TEMPLATE_HEAD))
yes('  and a pin Discord refuses does not stop it, because the bot asks for '
    'neither Manage Messages nor Pin Messages',
    'posted' in ask.response.said[0])

card_was = fresh.sent[0][0].content
ask = Ask(Who(['Dev']), guild2, fresh)
ran(bot.live_smoke_refresh.callback(ask))
yes('refresh again edits that post rather than adding a second one',
    len(fresh.sent) == 1 and fresh.sent[0][0].content == card_was
    and 'now says what the export says' in ask.response.said[0])

ask = Ask(Who(['Playtester']), guild2, fresh)
ran(bot.live_smoke_refresh.callback(ask))
yes('and a tester cannot refresh it', len(fresh.sent) == 1
    and 'start, reset and refresh' in ask.response.said[0])

# No #test-tasks at all: said in words, nothing posted.
ask = Ask(Who(['Owner']), Server(['Owner'], [Posted('general')]), None)
ran(bot.live_smoke_open(ask, '1.1.102.0', 'thornswood-one', False))
yes('a server with no #test-tasks is told to build it, and nothing is posted',
    'There is no #test-tasks' in ask.response.said[0] and ask.response.deferred == 0)

# An export that will not load stops a session before anything is posted, and
# says what is wrong with it.
tasks3, guild3 = server()
guild3.text_channels.append(tasks3)
wrong = tmp_json(dict(good, schema='thornswood.live-smoke.v9'))
was = bot.LIVE_SMOKE_EXPORT
try:
    bot.LIVE_SMOKE_EXPORT = wrong
    ask = Ask(Who(['Owner']), guild3, tasks3)
    ran(bot.live_smoke_open(ask, '1.1.102.0', 'thornswood-one', False))
    yes('an export of the wrong schema stops the session and says so',
        tasks3.sent == [] and 'thornswood.live-smoke.v1' in ask.response.said[0])
    yes('and the views registered at startup are none, rather than a crash',
        bot.live_smoke_views() == [])
finally:
    bot.LIVE_SMOKE_EXPORT = was
    os.unlink(wrong)

yes('startup registers one view per row, so a session outlives a restart',
    len(bot.live_smoke_views()) == 7)
yes('and the slash commands are one group of three',
    sorted(c.name for c in bot.live_smoke.commands) == ['refresh', 'reset', 'start']
    and bot.live_smoke.name == 'live-smoke'
    and 'live-smoke' in [c.name for c in bot.tree.get_commands()])

# --------------------------------- the channel and the commands agree --
#
# Two files have to say the same thing, and on 2 October they did not:
# bot.py let a Lead Gamemaster run /live-smoke start, and the channel it ran
# in was pathfind, which grants STAFF and Playtester. Somebody holding only
# that role passed the admin check and could not see the channel. So the
# builder's plan is read here and checked against this bot's admin list:
# anybody who may run the commands can see the place they are run in.
import importlib.util  # noqa: E402

spec = importlib.util.spec_from_file_location(
    'build_discord', os.path.join(HERE, 'Build-Discord.py'))
B = importlib.util.module_from_spec(spec)
spec.loader.exec_module(B)

plan = [s for _c, specs in B.PLAN for s in specs]
tasks = [s for s in plan if s.get('key') == 'TESTS'][0]
gated = set(n.lower() for n in B.STAFF) | set(['playtester'])
gated |= set(str(n).lower() for n in (tasks.get('extra_roles') or ()))

yes('the builder makes the channel this bot posts sessions in',
    tasks['name'].lower() in bot.LIVE_SMOKE_CHANNEL)
yes('and it is role gated, never @everyone', tasks['mode'] == 'pathfind')
yes('EVERYBODY WHO MAY RUN THE COMMANDS CAN SEE THE CHANNEL, which is the '
    'thing that was wrong',
    not [n for n in bot.LIVE_SMOKE_ADMIN if n not in gated])
yes('  and the lead gamemaster role is let in by that channel\u2019s own line, '
    'not by widening the mode',
    set(str(n).lower() for n in tasks['extra_roles']) ==
    set(['lead gamemaster', 'lead gm']))
yes('  so no other pathfind channel was widened with it',
    not any(s.get('extra_roles') for s in plan
            if s.get('mode') == 'pathfind' and s.get('key') != 'TESTS'))
yes('  and the roles are named, never a snowflake',
    not any(str(n).isdigit() for n in tasks['extra_roles']))

yes('test-these is retired rather than renamed into it',
    'test-these' in B.RETIRED
    and not [s for s in plan if s['name'].lower() == 'test-these'])
yes('and test-results is left where it was',
    [s['mode'] for s in plan if s['name'] == 'test-results'] == ['pathfind'])

print('')
print('%d passed, %d failed' % (len(PASS), len(FAIL)))
sys.exit(1 if FAIL else 0)
