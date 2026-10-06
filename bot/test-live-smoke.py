"""
test-live-smoke.py

The living Live smoke checklist in #test-tasks: what it reads, who may run it,
who may mark a row, and the one rule that is not about Discord at all, which is
that a mark never leaves it.

What is worth pinning here, in the order the locks were given on 1 October:

  the export        the bot reads live-smoke-discord-export.json and nothing
                    else, by schema and not by hope, and how many rows the
                    Live set carries is read off that file rather than written
                    down here, because Cynthia refreshes the set
  main only         Patrick's hard gate of 1 October: the main build and the
                    main launcher. A check that only the dev server can answer
                    is left off the list rather than listed with a Skip
  no skip rule      and so no row carries one. Forges are on main, so the
                    double craft row says not to Skip it instead of handing
                    a tester a standing excuse
  the layout        the rows and nothing wrapped around them, with the day the
                    set last changed kept as the version, which is Djinn's
                    call of 1 October
  the tickets       in the export for Dev and for this file, and on none of
                    the words a tester reads, because testers have no GitHub
  who may start     Owner, Dev and Lead Gamemaster, by name, both spellings of
                    the last one, and a Moderator alone is not one of them
  who may mark      a person, never an agent
  where a mark goes on the Discord message it was pressed on, and nowhere
                    else: not the site, not a file, not this bot's log
  the report        the same marks read back and counted, in one session
                    thread, to the one admin who asked for them: no post in
                    the thread, no second record of a mark anywhere, and
                    display names only, which is Djinn's option B of 2 October

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
# How many rows the Live set carries is the export's business, not this
# file's: Cynthia refreshes the set and the count moves with it. So it is
# read here once and everything below counts against it, and the only thing
# that has to be edited by hand when the set changes is TICKETS, which is the
# one claim a count cannot make.
N = len(items)

# The ticket behind each row, in the order the export gives them. Written out
# rather than read off the export, because this is the check that the file
# deployed beside bot.py is the Live set the vault meant and not a stale copy
# with the right shape. Update it with the export, in the same commit.
TICKETS = [
    ['486'],            # 1  Install lands in the Thornswood Game folder
    ['810'],            # 2  Bring it up to date stays quiet
    ['814'],            # 3  Shortcuts keep the right icons after update
    ['533'],            # 4  Undeployed collection shows one Diagnostics message
    ['1268'],           # 5  Offline Play is not called a load-order problem
    ['381'],            # 6  Chat fade in Settings
    ['381'],            # 7  Needs bars and the needs command
    ['999', '428'],     # 8  Discord connect before Play
    ['1264'],           # 9  Wrong or missing join pass is refused clearly
    ['378'],            # 10 Character creation finishes cleanly
    ['517'],            # 11 You arrive clothed after creation
    ['504'],            # 12 Crowded town NPCs settle without a lasting pileup
    ['517'],            # 13 Craft the same thing twice after you respawn
    ['505'],            # 14 Starting gold is 40 once
    ['505'],            # 15 Trade gold with someone else
    ['505'],            # 16 No free extra gold
    ['506', '1394'],    # 17 Paid carriage or ferry takes your fare
    ['505', '517'],     # 18 Quit and relaunch keeps your pack
    ['1402'],           # 19 Refused craft keeps your materials
    ['509'],            # 20 K panel shows profession and half
    ['1275'],           # 21 Friend request gives a clear result
    ['1275'],           # 22 Trade offer gives a clear result
    ['531'],            # 23 Party menu shows a real state
    ['519'],            # 24 Voice stays connected in range
    ['1396'],           # 25 Voice mute works
    ['407', '408'],     # 26 A client crash leaves a log you can find
    ['1157'],           # 27 Kick or refuse does not reconnect every few seconds
    ['486', '999'],     # 28 Install and join copy talks about your own Game folder
]

yes('it is the schema this bot reads', live['schema'] == 'thornswood.live-smoke.v1')
yes('the Live set is as long as the export says, with no row dropped on the '
    'way in', N == len(live['items']) and N == len(TICKETS))
yes('in the order the vault gives them, numbered from one with no gap',
    [i['order'] for i in items] == list(range(1, N + 1)))
yes('and the rows are named live-1 upwards, which is what a button is keyed by',
    [i['id'] for i in items] == ['live-%d' % n for n in range(1, N + 1)])
yes('each row has an id, a label and the line a tester reads',
    all(i['id'] and i['label'] and i['discord_line'] for i in items))
yes('the rows are the ones the vault names, by their tickets',
    [i['tickets'] for i in items] == TICKETS)
yes('the marks are Pass, Fail, Skip and Fail-known, in that order',
    list(bot.LIVE_SMOKE_MARKS) == ['Pass', 'Fail', 'Skip', 'Fail-known']
    and list(live['marks']) == list(bot.LIVE_SMOKE_MARKS))
yes('and the export says the channel is Test-Tasks, created new rather than '
    'test-these renamed',
    live['channel']['name'] == 'Test-Tasks' and live['channel']['create_new'] is True
    and live['channel']['do_not_rename'] == 'test-these')

# ------------------------------------------------- the main build, and only it --
#
# Patrick's hard gate of 1 October, through Tophet: the list is the main
# build and the main launcher. A check only the dev server can answer is left
# off the list. It is not listed with a Skip beside it, because a row a
# tester cannot run is a row that collects Skips and teaches everybody to
# reach for that button.
yes('THE SET IS THE MAIN BUILD AND THE MAIN LAUNCHER, which is the gate',
    live['rules']['main_build_and_launcher_only'] is True
    and live['build']['launcher'] == 'main' and live['build']['server'] == 'main')
yes('  and a check only the dev server can answer is left off rather than '
    'listed with a Skip beside it',
    live['rules']['omit_dev_only_entirely'] is True
    and live['rules']['no_skip_rule_as_dev_placeholder'] is True)
yes('  and every row on the list was seen working on main before it was listed',
    live['rules']['every_item_must_be_live_main_verified'] is True)
yes('the rows held back for a main check are named where they were held, so '
    'they are waiting rather than lost',
    [p['id'] for p in live['pending_main_verify']] ==
    ['pending-hunt', 'pending-fish', 'pending-hang', 'pending-resource',
     'pending-ownership', 'pending-traders', 'pending-recipe-vis',
     'pending-speaking-light', 'pending-checklist-meta']
    and all(p['why'] for p in live['pending_main_verify']))
yes('  and none of them is on the list a tester reads',
    not set(p['id'] for p in live['pending_main_verify'])
    & set(i['id'] for i in items))
yes('the launcher speaking light is off the Live set and stays off it',
    '1396-speaking-light' in live['keep_off']
    and '1396-overlay' in live['keep_off']
    and 'pending-speaking-light' in [p['id'] for p in live['pending_main_verify']]
    and not any('speaking light' in i['label'].lower() for i in items))
# The voice mute row is the one place a tester reads those words, and it reads
# them as something that does not count: a launcher light is not the game
# following the mute, and Pass on this row is the game following it.
light = [i for i in items if 'speaking light' in i['discord_line'].lower()]
yes('  and the one row that names it tells a tester it is not what they are '
    'marking, rather than handing the row back to them',
    [i['id'] for i in light] == ['live-25']
    and 'Do not mark Pass' in light[0]['discord_line'])

# The hold Patrick and Djinn lifted. The bot does not read any of this, and
# the harness does, because an export that lands still holding is the one
# shape of stale copy that looks published and is not.
yes('THE SET IS PUBLISHED AND NOTHING IS STILL HOLDING IT BACK, which is what '
    'lets an admin refresh it',
    live['status'] == 'published'
    and live['rules']['hold_publish_lifted'] is True
    and live['rules']['discord_hold_lifted'] is True
    and not any(v for k, v in live['rules'].items() if k.startswith('hold_')
                and k != 'hold_publish_lifted'))

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

# -------------------------------------------------------- and no skip rule --
#
# There used to be one, on the double craft row: Skip if this live world has
# no forge. Patrick took it off, because forges are on main, and a standing
# Skip on a row that can be run is a row nobody runs. The row says so itself
# now, in the line the vault wrote, which is where a tester will read it.
forge = [i for i in items if 'forge' in i['discord_line'].lower()][0]
plain = items[0]
said = bot.live_smoke_item_text(forge, N)

yes('NO ROW IN THE SET CARRIES A SKIP RULE, which is the call',
    [i['id'] for i in items if i['skip_rule']] == [])
yes('  so nothing a tester reads offers them one',
    not any('Skip rule' in bot.live_smoke_item_text(i, N) for i in items))
yes('the double craft row tells a tester not to Skip it, rather than leaving '
    'the forge question open',
    'do not Skip this row' in forge['discord_line']
    and 'do not Skip this row' in said)
yes('  and the export says why, which is that forges are on main',
    live['rules']['forges_exist_on_live_main'] is True
    and live['rules']['no_forge_skip_without_verify'] is True)
yes('  and the row names its place in the set and the words the vault labels '
    'it with',
    said.startswith('**Live %d of %d: %s**' % (forge['order'], N, forge['label'])))
yes('  and still carries the line the vault wrote', forge['discord_line'] in said)
yes('a row the export gives no skip rule says nothing about one',
    'Skip rule' not in bot.live_smoke_item_text(plain, N))
yes('an item message fits in a Discord message',
    all(len(bot.live_smoke_item_text(i, N)) < 2000 for i in items))

# ----------------------------------------- and the tickets stay off Discord --
#
# Djinn's rule of 1 October: testers do not have GitHub. The tickets are in
# the export, because Dev maps a Fail back to one and this file checks them,
# and they are on none of the words a tester reads.
yes('the export says tickets are not posted to Discord',
    live['rules']['discord_show_tickets'] is False
    and live['rules']['player_facing_no_github_refs'] is True
    and live['rules']['tickets_are_dev_staff_only'] is True
    and bot.live_smoke_show_tickets(live) is False)
yes('NO ROW CARRIES A TICKET NUMBER, which is the rule',
    not any(re.search(r'#\d+', bot.live_smoke_item_text(i, N))
            for i in items))
yes('  nor a Tickets line, which is the other way one used to reach a row',
    not any('Tickets' in bot.live_smoke_item_text(i, N) for i in items))
yes('  nor anything else that reads as a GitHub reference',
    not any(('github.com' in bot.live_smoke_item_text(i, N).lower()
             or 'issue #' in bot.live_smoke_item_text(i, N).lower())
            for i in items))
yes('  and the labels and lines the vault wrote carry none either',
    not any(re.search(r'#\d+', i['label'] + ' ' + i['discord_line'])
            for i in items))
yes('an export with no word on it still posts no tickets, because the '
    'default is off',
    bot.live_smoke_show_tickets({}) is False
    and bot.live_smoke_show_tickets(dict(live, rules={})) is False)
yes('and an export that asks for them in so many words gets them',
    bot.live_smoke_show_tickets(
        dict(live, rules=dict(live['rules'], discord_show_tickets=True))) is True
    and '#517' in bot.live_smoke_item_text(forge, N, True))

# --------------------------------------------------------------- the ids --
yes('a button is keyed by its row and its mark',
    bot.live_smoke_custom_id('live-2', 'Fail-known') == 'ls:live-2:Fail-known')
yes('and read back the same way',
    bot.live_smoke_read_id('ls:live-2:Fail-known') == ('live-2', 'Fail-known'))
yes('every button in the set has a different id, and Discord takes all of them',
    len(set(bot.live_smoke_custom_id(i['id'], m)
            for i in items for m in bot.LIVE_SMOKE_MARKS))
    == N * len(bot.LIVE_SMOKE_MARKS)
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
    ['owner', 'dev', 'lead gamemaster', 'lead gm'])
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
    bot.live_smoke_admin_missing(scrubbed) == ['Lead Gamemaster', 'Lead GM'])
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
row = bot.live_smoke_item_text(forge, N)

one = bot.live_smoke_mark(row, 'Ataxayk', 'Pass')
yes('a mark goes on the row under a heading of its own',
    one.startswith(row) and one.endswith('Ataxayk: Pass'))
yes('  and the line the vault wrote is still there', forge['discord_line'] in one)
yes('  and so is what it says about not Skipping it',
    'do not Skip this row' in one)

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

stamp = bot.live_smoke_stamp(live)
yes('the version stamp is the one the export asks for, off its own date',
    live['session']['version_stamp'] == 'Checklist updated: {updated}'
    and stamp == 'Checklist updated: ' + live['updated'])
yes('and an export with no date on it has no stamp rather than an empty one',
    bot.live_smoke_stamp({}) == '' and bot.live_smoke_stamp(dict(live, updated='')) == '')

opener = bot.live_smoke_opener(title, 'thornswood-one', '1.1.101.17', stamp)
yes('the opener names the live channel, which is the thing a session is of',
    'thornswood-one' in opener)
yes('  and the date and the version, through the title', title in opener)
yes('  and the Settings version in a line of its own',
    'Settings version: 1.1.101.17' in opener)
yes('  and the three required fields are the three the export asks for',
    [f for f in live['session']['required_fields']] ==
    ['date', 'live_channel', 'settings_version'])
yes('  and it keeps the versioning Djinn asked to keep', stamp in opener)
yes('  and it fits in a Discord message', len(opener) < 2000)

# Djinn's layout call of 1 October: the Discord body is the checklist rows.
# The opener is the session's own name and nothing wrapped around it.
yes('THE OPENER CARRIES NO BLOCK OF INSTRUCTIONS ABOVE OR BELOW THE ROWS, '
    'which is the layout call',
    not any(w in opener for w in ('Mark your own rows', 'can read the marks',
                                  'stay in Discord', 'Agents do not mark rows',
                                  'row to mark', 'rows to mark')))
yes('  and it is four lines at the most', len(opener.split('\n')) <= 4)
yes('  and no ticket number reaches it', not re.search(r'#\d+', opener))

# ------------------------------------- the checklist that stands in the channel --
#
# What #test-tasks carries between sessions. Up to 2 October it was one post of
# numbered labels: it named every check in the set and said how to run not one
# of them, so Patrick refreshed to 2026-10-02r7 and got twenty eight titles
# where twenty eight sets of instructions should have been. It is the rows now,
# a message each, worded the way a session words them.
sheet = bot.live_smoke_checklist(live, items)
head, rows = sheet[0], sheet[1:]

yes('THE CHECKLIST CARRIES THE LINE THE VAULT WROTE FOR EVERY ROW, which is '
    'what a tester does and what a list of labels left out',
    len(rows) == N
    and all(i['discord_line'] in rows[n] for n, i in enumerate(items)))
yes('  under the heading and not instead of it, so the name of the row is '
    'still the first thing read',
    all(r.startswith('**Live %d of %d: %s**' % (i['order'], N, i['label']))
        and i['discord_line'] in r.split('\n', 1)[1]
        for i, r in zip(items, rows)))
yes('  one message to a row, in the order the export gives them',
    rows == [bot.live_smoke_item_text(i, N) for i in items])
yes('  so what stands in the channel and what a session posts are the same '
    'words, and nobody is reading two different checklists',
    all(len(r) > len('%d. %s' % (i['order'], i['label']))
        for i, r in zip(items, rows)))
yes('the post the rows hang off is the heading and the day the set last '
    'changed, which is how a tester tells one set from the next',
    [l for l in head.split('\n') if l.strip()] ==
    [bot.LIVE_SMOKE_CHECKLIST_HEAD, stamp])
yes('  and is found again by the words it starts with',
    head.startswith(bot.LIVE_SMOKE_CHECKLIST_HEAD))
yes('every message of it fits in a Discord message',
    all(len(s) < 2000 for s in sheet))
yes('  and offers nobody a standing Skip, because no row has one',
    not any('Skip rule' in s for s in sheet))
yes('  and carries no ticket number', not any(re.search(r'#\d+', s) for s in sheet))
yes('  and no block of prose around the rows',
    not any(w in s for s in sheet
            for w in ('This is what a session checks', 'The marks are Pass',
                      'Agents do not mark rows')))

# A set bigger than a message is a message to a row, so none of it is cut off
# the end of a post that ran out of room.
big = bot.live_smoke_items({'items': [
    {'id': 'live-%d' % n, 'order': n, 'label': 'A row with a long name ' * 5,
     'discord_line': 'What a tester does, said at length. ' * 10}
    for n in range(1, 40)]})
spread = bot.live_smoke_checklist({}, big)
yes('a Live set too big for one message is a message to a row, not a post cut '
    'off at the end',
    len(spread) == len(big) + 1 and all(len(s) < 2000 for s in spread)
    and all(i['discord_line'] in s for i, s in zip(big, spread[1:])))

# One row longer than a Discord message is cut, rather than refused by Discord
# part way through posting a session.
huge = bot.live_smoke_items({'items': [
    {'id': 'live-1', 'order': 1, 'label': 'A long one',
     'discord_line': 'x' * 4000}]})[0]
yes('and a row longer than a Discord message is cut rather than handed to '
    'Discord to refuse',
    len(bot.live_smoke_item_text(huge)) < 2000
    and 'the rest of this row is in the export'
    in bot.live_smoke_item_text(huge))

# -------------------------------------------- reading those marks back --
#
# Djinn's option B of 2 October: the missing piece was never per person
# buttons, which the block above already proves. It was a Dev who had to
# scroll twenty eight rows to find the one Fail. So the marks are read back
# off the messages they were written on, by the other half of the function
# that wrote them, and nothing else is kept anywhere.
yes('A ROW\u2019S MARKS CAN BE READ BACK OFF THE ROW, which is what a report '
    'is made of',
    bot.live_smoke_read_marks(again) == [('Ataxayk', 'Fail-known'),
                                         ('Djinn', 'Skip')])
yes('  every one of them, with as many people on a row as marked it',
    bot.live_smoke_read_marks(
        bot.live_smoke_mark(bot.live_smoke_mark(bot.live_smoke_mark(
            row, 'Ataxayk', 'Pass'), 'Djinn', 'Fail'), 'Cynthia', 'Skip'))
    == [('Ataxayk', 'Pass'), ('Djinn', 'Fail'), ('Cynthia', 'Skip')])
yes('  and a name with a colon in it is read back whole, the way it was '
    'written',
    bot.live_smoke_read_marks(bot.live_smoke_mark(row, 'a:b', 'Fail'))
    == [('a:b', 'Fail')])
yes('a row nobody has marked reads as nobody, not as a blank person',
    bot.live_smoke_read_marks(row) == []
    and bot.live_smoke_read_marks('') == []
    and bot.live_smoke_read_marks(None) == [])
yes('  and so does a row whose marks block is there with nothing under it, '
    'which is what a row somebody cleared looks like',
    bot.live_smoke_read_marks(row + bot.LIVE_SMOKE_MARKS_HEAD) == []
    and bot.live_smoke_read_marks(row + bot.LIVE_SMOKE_MARKS_HEAD + '\n\n') == [])
yes('a line under the heading that is not a name against one of the four '
    'marks is not counted as one',
    bot.live_smoke_read_marks(row + bot.LIVE_SMOKE_MARKS_HEAD
                              + 'Ataxayk: Passed\nDjinn\n: Pass\nDjinn: Pass')
    == [('Djinn', 'Pass')])

# Which row a line of the report is about. The number, because that is what
# the row is called in the thread, in the standing checklist and in the export.
yes('a row names itself by its number, off its own heading',
    bot.live_smoke_row_name(row) == 'Live %d' % forge['order']
    and [bot.live_smoke_row_name(bot.live_smoke_item_text(i, N)) for i in items]
    == ['Live %d' % i['order'] for i in items])
yes('  and a marked row still names itself, because the marks go under it',
    bot.live_smoke_row_name(again) == 'Live %d' % forge['order'])
yes('the opener is not a row, and neither is the standing checklist post',
    bot.live_smoke_row_name(opener) == ''
    and bot.live_smoke_row_name(bot.live_smoke_head(live)) == '')
yes('  nor is anything else somebody said in the thread',
    bot.live_smoke_row_name('Live 3 passed for me') == ''
    and bot.live_smoke_row_name('') == ''
    and bot.live_smoke_row_name(None) == '')

# Which Live set the session was opened against. The thread's name carries
# the date and the version and not that, so it is read off the opener.
yes('the stamp is read back off a session opener',
    bot.live_smoke_opener_stamp(opener) == stamp)
yes('  and an opener posted without one reads as none rather than as a line '
    'of the session\u2019s own',
    bot.live_smoke_opener_stamp(
        bot.live_smoke_opener(title, 'thornswood-one', '1.1.101.17')) == ''
    and bot.live_smoke_opener_stamp('') == ''
    and bot.live_smoke_opener_stamp(None) == '')

# -------------------------------------------------------- the report --
#
# What an admin reads instead of scrolling the session. Counts for every row,
# names for the two marks Dev acts on, and the rows nobody has marked said
# out loud rather than left to be noticed.
R = bot.live_smoke_report_text
session = [
    ('Live 1', [('Ataxayk', 'Pass'), ('Djinn', 'Pass')]),
    ('Live 2', []),
    ('Live 3', [('Ataxayk', 'Fail'), ('Djinn', 'Pass'), ('Cynthia', 'Fail')]),
    ('Live 4', [('Djinn', 'Skip')]),
    ('Live 5', [('Ataxayk', 'Fail-known')]),
]
report = R(title, stamp, session)

yes('THE REPORT COUNTS EVERY ROW AND NAMES THE SESSION IT IS OF, which is '
    'what option B is for',
    report.startswith('**%s**' % title) and stamp in report
    and '5 row(s)' in report)
yes('  per row, every mark that was given with how many gave it',
    'Live 1: Pass 2' in report
    and 'Live 3: Pass 1, Fail 2 (Ataxayk, Cynthia)' in report
    and 'Live 4: Skip 1' in report
    and 'Live 5: Fail-known 1 (Ataxayk)' in report)
yes('  WHO FAILED IT, by the display name the row itself carries',
    'Fail 2 (Ataxayk, Cynthia)' in report
    and 'Fail-known 1 (Ataxayk)' in report)
yes('  and the rows carrying one named where a reader cannot scroll past them',
    'Fail on: Live 3.' in report and 'Fail-known on: Live 5.' in report)
yes('  AND THE ROWS NOBODY HAS MARKED SAID OUT LOUD, which is the Fail that '
    'is easiest to miss',
    'Not marked: Live 2.' in report and '4 marked, 1 not marked yet' in report)
yes('  and the counts are on the row, not a Pass list as long as the session',
    'Pass 2' in report and 'Ataxayk, Djinn' not in report)
yes('  and it fits in a Discord message', len(report) < 2000)

yes('a session nobody has touched says so rather than listing nothing',
    'none of them marked yet' in R(title, '', [('Live %d' % n, [])
                                               for n in range(1, N + 1)]))
yes('a session with every row marked says that instead of naming none',
    'every one of them marked' in R(title, '', [('Live 1', [('Djinn', 'Pass')])])
    and 'Not marked' not in R(title, '', [('Live 1', [('Djinn', 'Pass')])]))
yes('a session with nothing failed names no fails',
    'Fail' not in R(title, '', [('Live 1', [('Djinn', 'Pass')]),
                                ('Live 2', [('Djinn', 'Skip')])]))
yes('a thread with no rows in it says so rather than reading as a clean sweep',
    'no checklist rows in this thread' in R(title, stamp, []))
yes('a session opened without a stamp reports without one rather than an '
    'empty line',
    R(title, '', session).split('\n')[1].startswith('5 row(s)'))

# The length risk the design note named: many testers, every row failed.
crowd = [('Live %d' % n, [(who, 'Fail') for who in
                          ('Ataxayk', 'Djinn', 'Cynthia', 'Harlan', 'Tophet',
                           'Mosby', 'Patrick')])
         for n in range(1, 29)]
long_one = R('Live smoke 2026-10-02 1.1.101.17', stamp, crowd)
yes('a session of twenty eight rows and seven testers still fits in a Discord '
    'message',
    len(long_one) < 2000)
yes('  and what gives way is the list and not the fails, which are named above '
    'it',
    'more marked row(s) are in the thread' in long_one
    and all(('Live %d' % n) in long_one.split('\n')[3] for n in (1, 28)))
yes('and a report is nothing but words: no account id anywhere in one',
    not re.search(r'\d{15,}', report + long_one))

# Where a report may be read. A session thread, and not the standing rows.
yes('A REPORT IS READ IN A SESSION THREAD, which is where the marks are',
    bot.live_smoke_report_refusal(
        Thread('Live smoke 2026-10-02 1.1.101.17', tasks)) is None)
yes('THE STANDING CHECKLIST ROWS ARE REFUSED, because those rows carry no '
    'buttons and so no marks',
    bot.LIVE_SMOKE_ROWS in
    bot.live_smoke_report_refusal(Thread(bot.LIVE_SMOKE_ROWS, tasks)))
yes('  and so is any other thread under the channel',
    bot.live_smoke_report_refusal(Thread('Something else', tasks)) is not None)
yes('  and the channel itself, which holds the openers and not the rows',
    'session thread' in bot.live_smoke_report_refusal(tasks))
yes('  and a thread under some other channel',
    bot.live_smoke_report_refusal(
        Thread('Live smoke 2026-10-02', Channel('general'))) is not None
    and bot.live_smoke_report_refusal(None) is not None)


class Closed(Thread):
    """A session a reset archived and locked where it stood."""

    def __init__(self, name, parent):
        Thread.__init__(self, name, parent)
        self.archived = True
        self.locked = True


yes('a session a reset closed is not the one this reports on, and the refusal '
    'says its marks are still in the thread',
    'closed' in bot.live_smoke_report_refusal(
        Closed('Live smoke 2026-10-01 1.1.101.16', tasks))
    and 'still in the thread' in bot.live_smoke_report_refusal(
        Closed('Live smoke 2026-10-01 1.1.101.16', tasks)))

# ------------------------------------------------------- the words rules --
#
# Developer-Guide.md: no em dashes, and never the word this bans, in anything
# written for people. Check-Words.ps1 does not read bot.py, so it is read here.
WORDS = [opener, bot.live_smoke_admin_refusal(here), gone,
         bot.live_smoke_tick_refusal(Who([], bot=True)),
         report, long_one, R(title, stamp, []),
         bot.live_smoke_report_refusal(tasks),
         bot.live_smoke_report_refusal(Thread(bot.LIVE_SMOKE_ROWS, tasks))]
WORDS += sheet
WORDS += [bot.live_smoke_item_text(i, N) for i in items]
yes('nothing this says to anybody has an em dash in it',
    not any('\u2014' in w for w in WORDS))
yes('and nothing a report says is a GitHub reference, because an admin reads '
    'it in the same thread testers are in',
    not any(re.search(r'#\d+', w) for w in (report, long_one))
    and 'github' not in (report + long_one).lower())

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
yes('start, reset, refresh and report all pass through the one admin gate',
    section.count('await _live_smoke_ready(interaction)') == 3
    and 'async def _live_smoke_ready' in section
    and all(('await live_smoke_open(interaction' in section)
            for _ in ('start', 'reset')))
tail = section[section.index('async def live_smoke_report('):]
yes('the report writes no traceback either, for the same reason: what Discord '
    'hands back when it will not read a thread carries the messages it did read',
    'async def live_smoke_report(' in section and 'format_exc' not in tail)
yes('  and it posts nothing anywhere: every word of it is said to the one '
    'admin who ran it',
    tail.count('ephemeral=True')
    == tail.count('followup.send(') + tail.count('.defer(')
    and 'thread.send' not in tail and 'channel.send' not in tail)

# ------------------------------------------- a session, start to a mark --
#
# The three commands and the button handler, run for real against stand-ins
# that record what would have been asked of Discord. Nothing above this drives
# the gates as a command: this is where a Moderator is turned away by
# /live-smoke start rather than by is_live_smoke_admin, and where an agent
# pressing Pass changes no message.


class Message(object):
    def __init__(self, channel, content, system=False):
        self.channel = channel
        self.content = content
        self.author = Who(uid=BOT_ID)
        # A thread made from a message opens with a system message Discord
        # gives the bot as its author, and refuses to let anybody edit it
        # (#2018: 403, error 50021, on 6 Oct).
        self.system = system
        self.thread = None
        # What Discord has, next to what the message in hand remembers. An
        # archived thread drops out of the cache behind Message.thread and is
        # still there to be fetched, which is the state a refresh weeks later
        # finds.
        self.threaded = None

    async def create_thread(self, name=None, auto_archive_duration=None):
        if self.threaded is not None:
            raise RuntimeError('a message takes one thread, and Discord '
                               'refuses a second')
        self.thread = Session(name, self.channel)
        # What a report reads the session's stamp off: Discord hands a thread
        # the message it hangs off.
        self.thread.starter_message = self
        self.threaded = self.thread
        self.channel.threads.append(self.thread)
        return self.thread

    async def fetch_thread(self):
        if self.threaded is None:
            raise RuntimeError('no thread on this message, which Discord '
                               'answers as not found')
        return self.threaded

    def is_system(self):
        return self.system

    async def edit(self, content=None, view=None):
        if self.system:
            raise RuntimeError('403 Forbidden (error code: 50021): Cannot '
                               'execute action on a system message')
        self.content = content

    async def delete(self):
        # Its own message, which Discord lets a bot take down without Manage
        # Messages.
        self.channel.sent = [(m, v) for m, v in self.channel.sent
                             if m is not self]

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

    async def history(self, limit=50, oldest_first=False):
        order = self.sent if oldest_first else reversed(self.sent)
        for m, _ in list(order):
            yield m


class Session(Posted):
    """A thread off an opener. Its parent is what makes a mark allowed."""

    def __init__(self, name, parent):
        Posted.__init__(self, name)
        self.parent = parent
        self.archived = False
        self.locked = False
        self.mention = '<#%s>' % name
        # What Discord puts first in a thread made from a message: a system
        # message it gives the bot as author. History hands it back with the
        # rest; sent keeps only what the bot posted.
        self.opened = Message(self, '', system=True)

    async def history(self, limit=50, oldest_first=False):
        order = [self.opened] + [m for m, _ in self.sent]
        for m in (order if oldest_first else list(reversed(order))):
            yield m

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
    and 'start, reset, refresh and report' in ask.response.said[0])

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
    len(thread.sent) == N and len(tasks.sent) == 1)
yes('  one message per row, so no message carries every button in the set',
    all(len(v.children) == len(bot.LIVE_SMOKE_MARKS) for _, v in thread.sent))
yes('  each row carrying the four marks',
    [c.label for c in thread.sent[0][1].children] == list(bot.LIVE_SMOKE_MARKS))
yes('  the rows in the order the export gives them',
    [m.content.split('\n')[0] for m, _ in thread.sent] ==
    [bot.live_smoke_item_text(i, N).split('\n')[0] for i in items])
yes('  and not one of them offering a Skip rule',
    not any('Skip rule' in m.content for m, _ in thread.sent))
yes('  and not one ticket number on any row a tester reads',
    not any(re.search(r'#\d+', m.content) for m, _ in thread.sent)
    and not re.search(r'#\d+', opened.content))
yes('  and the opener is the session name and the stamp, with no block of '
    'instructions wrapped round the rows',
    len([l for l in opened.content.split('\n') if l.strip()]) == 4
    and bot.live_smoke_stamp(live) in opened.content)
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
    len(tasks.sent) == 1 and len(thread.sent) == N)

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

# Two testers fail the row after it, so the report has something to name.
hard, hard_view = thread.sent[2]
fails = [c for c in hard_view.children if c.label == 'Fail'][0]
for name in ('Ataxayk', 'Djinn'):
    ask = Ask(Who(['Playtester'], uid=5, display_name=name), guild, thread, hard)
    ran(fails.callback(ask))
    hard.content = ask.response.edited[0]

# The report, run in the session thread by somebody who may.
ask = Ask(Who(['Dev']), guild, thread)
ran(bot.live_smoke_report.callback(ask))
told = ask.response.said[0]
yes('/LIVE-SMOKE REPORT COUNTS THE SESSION IT IS RUN IN and says it to the '
    'admin who ran it, posting nothing in the thread and nothing in the channel',
    ask.response.deferred == 1 and len(ask.response.said) == 1
    and len(thread.sent) == N and len(tasks.sent) == 1)
yes('  naming the session and the Live set it was opened against',
    told.startswith('**%s**' % thread.name)
    and bot.live_smoke_stamp(live) in told)
yes('  and every row of it, counted', '%d row(s)' % N in told)
yes('  the marks read off the rows themselves, one line to a row',
    'Live 2: Pass 1' in told and 'Live 3: Fail 2 (Ataxayk, Djinn)' in told)
yes('  THE FAILED ROW NAMED WHERE IT CANNOT BE SCROLLED PAST, with who failed it',
    'Fail on: Live 3.' in told and '(Ataxayk, Djinn)' in told)
yes('  and the rows nobody has touched said out loud',
    'Not marked: Live 1,' in told and ('Live %d' % N) in told
    and '2 marked, %d not marked yet' % (N - 2) in told)
yes('  and the opener is not counted as a row of its own',
    told.count('row(s)') == 1 and 'Live smoke 2026' not in told.split('\n', 1)[1])

# A tester, and a Moderator, at the report.
ask = Ask(Who(['Playtester'], display_name='Ataxayk'), guild, thread)
ran(bot.live_smoke_report.callback(ask))
yes('A TESTER MAY NOT READ THE REPORT, which is the same gate start and reset '
    'carry',
    ask.response.deferred == 0
    and 'start, reset, refresh and report' in ask.response.said[0])
ask = Ask(Who(['Moderator']), guild, thread)
ran(bot.live_smoke_report.callback(ask))
yes('  nor may a Moderator alone', ask.response.deferred == 0
    and 'start, reset, refresh and report' in ask.response.said[0])

# The same command, run outside a session thread.
ask = Ask(Who(['Dev']), guild, tasks)
ran(bot.live_smoke_report.callback(ask))
yes('AND IT IS REFUSED OUTSIDE A SESSION THREAD, in the channel the openers '
    'sit in, rather than counting the openers',
    ask.response.deferred == 0 and 'session thread' in ask.response.said[0])

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

ask = Ask(Who(['Owner']), guild, thread)
ran(bot.live_smoke_report.callback(ask))
yes('  and the session it closed is no longer the one a report counts',
    ask.response.deferred == 0 and 'closed' in ask.response.said[0])

# Refresh: the standing checklist, made once and then edited. This is the one
# Patrick ran on 2 October against 2026-10-02r7 and got the row names out of.
fresh, guild2 = server()
guild2.text_channels.append(fresh)
ask = Ask(Who(['Dev']), guild2, fresh)
ran(bot.live_smoke_refresh.callback(ask))
post = fresh.sent[0][0]
standing = post.thread
yes('refresh posts the checklist when there is none, and it is one post in '
    'the channel',
    len(fresh.sent) == 1
    and post.content.startswith(bot.LIVE_SMOKE_CHECKLIST_HEAD))
yes('  carrying the day the set last changed', bot.live_smoke_stamp(live) in post.content)
yes('  AND THE ROWS UNDER IT, each one the whole of what a tester does rather '
    'than the name of it',
    standing is not None and len(standing.sent) == N
    and all(i['discord_line'] in standing.sent[n][0].content
            for n, i in enumerate(items)))
yes('  and the system message Discord opens the thread with is left as it '
    'is, not taken for row 1 (#2018)',
    standing.opened.content == '' and standing.opened.is_system())
yes('  worded the way a session words them',
    [m.content for m, _ in standing.sent] ==
    [bot.live_smoke_item_text(i, N) for i in items])
yes('  and not one of them carrying a button, because a mark belongs to a '
    'dated session',
    all(v is None for _, v in standing.sent))
yes('  and whoever ran it is told how many rows went up, and that a session '
    'already open keeps the ones it started with',
    '%d row(s)' % N in ask.response.said[0]
    and '/live-smoke reset' in ask.response.said[0])
yes('  and a pin Discord refuses does not stop it, because the bot asks for '
    'neither Manage Messages nor Pin Messages',
    'now says what the export says' in ask.response.said[0])

was_rows = [m.content for m, _ in standing.sent]
ask = Ask(Who(['Dev']), guild2, fresh)
ran(bot.live_smoke_refresh.callback(ask))
yes('refresh again edits what is there rather than posting the set a second time',
    len(fresh.sent) == 1 and post.content.startswith(bot.LIVE_SMOKE_CHECKLIST_HEAD)
    and [m.content for m, _ in standing.sent] == was_rows)

# Discord archives a quiet thread after a week and drops it out of the cache
# the message carries, which is the state a refresh weeks later finds. The
# thread is fetched and woken rather than a second one being asked for, which
# Discord refuses.
standing.archived = True
post.thread = None
ask = Ask(Who(['Dev']), guild2, fresh)
ran(bot.live_smoke_refresh.callback(ask))
yes('a thread Discord has archived is fetched and woken, so a refresh weeks '
    'later still lands',
    not standing.archived and len(standing.sent) == N
    and len(fresh.threads) == 1)

# Cynthia drops rows from the set. The ones that went are taken down rather
# than left standing, telling testers to run a check nobody is asking for.
short = tmp_json(dict(good, items=good['items'][:3]))
was = bot.LIVE_SMOKE_EXPORT
try:
    bot.LIVE_SMOKE_EXPORT = short
    ask = Ask(Who(['Dev']), guild2, fresh)
    ran(bot.live_smoke_refresh.callback(ask))
    yes('a row the export no longer carries is taken down',
        len(standing.sent) == 3
        and [m.content for m, _ in standing.sent] ==
        [bot.live_smoke_item_text(i, 3) for i in items[:3]])
finally:
    bot.LIVE_SMOKE_EXPORT = was
    os.unlink(short)

ask = Ask(Who(['Dev']), guild2, fresh)
ran(bot.live_smoke_refresh.callback(ask))
yes('  and the whole set is back the next time the export carries it',
    [m.content for m, _ in standing.sent] == was_rows)

ask = Ask(Who(['Playtester']), guild2, fresh)
ran(bot.live_smoke_refresh.callback(ask))
yes('and a tester cannot refresh it', len(fresh.sent) == 1
    and 'start, reset, refresh and report' in ask.response.said[0])

# A report asked of the standing rows. They carry no buttons, so there is
# nothing in them to count, and the refusal says where the marks are instead.
ask = Ask(Who(['Dev']), guild2, standing)
ran(bot.live_smoke_report.callback(ask))
yes('THE STANDING CHECKLIST ROWS THREAD IS REFUSED A REPORT, because a mark '
    'belongs to a dated session and those rows carry no buttons',
    ask.response.deferred == 0 and bot.LIVE_SMOKE_ROWS in ask.response.said[0]
    and 'session' in ask.response.said[0])

# A reset closes the session threads under the channel. The standing checklist
# is not one of them, which is why its thread is not named for a session.
ask = Ask(Who(['Owner']), guild2, fresh)
ran(bot.live_smoke_open(ask, '1.1.102.0', 'thornswood-one', True))
yes('a reset closes the sessions and leaves the standing checklist where it is',
    not standing.archived and not standing.locked
    and not bot.LIVE_SMOKE_ROWS.startswith(bot.LIVE_SMOKE_TITLE)
    and len(standing.sent) == N)

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
    len(bot.live_smoke_views()) == N)
yes('and the slash commands are one group of four',
    sorted(c.name for c in bot.live_smoke.commands) ==
    ['refresh', 'report', 'reset', 'start']
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
