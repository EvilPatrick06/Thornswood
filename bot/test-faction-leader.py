"""
test-faction-leader.py

Apply: Faction Leader replaced Apply: Trading Company.

The real bot module is imported and the real TicketModal.on_submit is
run. Only what touches Discord is replaced: the guild, its channels,
threads and roles, the interaction, and the push to the site.

Holds:

  the faction pick and Other on the form
  a submit-time recheck that a tampered pick is flagged and Other is not
  the staff flag on both Faction Leader and Jarl
  typed Other text out of the pinging opening line and Asking for
  Faction Leader routing to Owner and UPPER_STAFF_ROLES only
  /close on those threads for UPPER_STAFF_ROLES IDs, without changing is_staff
  delete of the exact opened thread when a later write fails

Read only. Never connects to anything.
"""
import asyncio
import inspect
import json
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
os.environ.setdefault('DISCORD_TOKEN', 'not-a-real-token')
for _k in ('TICKET_CHANNEL', 'TICKET_LOG', 'STAFF_ROLES', 'TICKET_COOLDOWN',
           'UPPER_STAFF_ROLES'):
    os.environ.pop(_k, None)

import discord  # noqa: E402

import bot  # noqa: E402

PASS = []
FAIL = []


def yes(what, cond):
    (PASS if cond else FAIL).append(what)
    print(('PASS  ' if cond else 'FAIL  ') + what)


SHOUT = '@everyone @here'
PULL = '<@&1234567890123456789>'


class Role(object):
    def __init__(self, name, members=(), rid=None):
        self.name = name
        self.id = 7000 if rid is None else rid
        self.members = list(members)
        self.mention = '<@&%s>' % name


class Person(object):
    def __init__(self, uid, name, roles=()):
        self.id = uid
        self.name = name
        self.display_name = name
        self.mention = '<@%d>' % uid
        self.roles = list(roles)
        self.bot = False
        self.dms = []

    def __str__(self):
        return self.name

    async def send(self, *a, **k):
        self.dms.append(a[0] if a else '')


class Perms(object):
    def __init__(self, everything):
        self.everything = everything

    def __getattr__(self, _name):
        return self.everything


class Posts(object):
    def __init__(self):
        self.sent = []

    async def send(self, text=None, **kw):
        await asyncio.sleep(0)
        self.sent.append((text or '', kw))

    def texts(self):
        return [t for t, _ in self.sent]

    def body(self):
        return '\n\n'.join(t for t, _ in self.sent[1:])

    def head(self):
        return self.sent[0][0] if self.sent else ''


class Thread(Posts):
    def __init__(self, tid, name):
        Posts.__init__(self)
        self.id = tid
        self.name = name
        self.archived = False
        self.mention = '<#%d>' % tid
        self.added = []
        self.deleted = False
        self.refuse_send = False
        self.guild = None

    async def add_user(self, m):
        self.added.append(m)

    async def send(self, text=None, **kw):
        if self.refuse_send:
            raise RuntimeError('cannot write')
        await Posts.send(self, text, **kw)

    async def delete(self):
        self.deleted = True
        if self.guild is not None:
            self.guild.threads.pop(self.id, None)


class Channel(Posts):
    def __init__(self, name, guild):
        Posts.__init__(self)
        self.name = name
        self.guild = guild
        self.made = []
        self.refuse_threads = False
        self.refuse_writes = False

    def permissions_for(self, who):
        return Perms(who is self.guild.me)

    async def create_thread(self, name=None, **k):
        await asyncio.sleep(0)
        if self.refuse_threads:
            raise RuntimeError('no private threads today')
        t = Thread(9000 + len(self.made), name)
        t.opened_as = k
        t.guild = self.guild
        if self.refuse_writes:
            t.refuse_send = True
        self.made.append(t)
        self.guild.threads[t.id] = t
        return t


class Guild(object):
    def __init__(self, gid, staff, owner=None):
        self.id = gid
        self.name = 'Thornswood'
        self.me = Person(1, 'Thornswood')
        self.me.bot = True
        self.threads = {}
        self.roles = [Role('Moderator', [staff], rid=11)]
        if owner is not None:
            self.roles.append(Role('Owner', [owner], rid=10))
        self.text_channels = [Channel(bot.TICKETS[0], self)]

    def get_thread(self, tid):
        return self.threads.get(tid)


class Response(object):
    def __init__(self):
        self.said = []
        self.deferred = 0

    async def send_message(self, text, ephemeral=False, **k):
        self.said.append((text, ephemeral))

    async def defer(self, **k):
        self.deferred += 1
        await asyncio.sleep(0)


class Followup(object):
    def __init__(self):
        self.said = []

    async def send(self, text, ephemeral=False, **k):
        self.said.append((text, ephemeral))


class Interaction(object):
    def __init__(self, guild, user):
        self.guild = guild
        self.user = user
        self.channel = guild.text_channels[0]
        self.response = Response()
        self.followup = Followup()


PUSHED = []


async def _push(*a):
    PUSHED.append(a)


bot.push_async = _push
bot.KEY = ''
LOGGED = []
bot.log = lambda *a: LOGGED.append(' '.join(str(x) for x in a))


def off(kw):
    am = kw.get('allowed_mentions')
    return (isinstance(am, discord.AllowedMentions)
            and not am.everyone and not am.users and not am.roles)


def fill_faction(modal, pick, other='', answers=None):
    if modal.faction_select is not None:
        modal.faction_select._values = [pick]
    if modal.faction_other is not None:
        modal.faction_other._value = other
    for f in modal.fields:
        f._value = 'yes'
    if answers:
        for f, a in zip(modal.fields, answers):
            f._value = a


def send_faction(guild, who, pick, other='', answers=None):
    lab = dict((a, b) for a, b, _ in bot.KINDS)['faction']
    m = bot.TicketModal('faction', lab)
    fill_faction(m, pick, other, answers)
    bot._last_ticket.clear()
    i = Interaction(guild, who)
    asyncio.run(m.on_submit(i))
    return i, m


def send_jarl(guild, who):
    lab = dict((a, b) for a, b, _ in bot.KINDS)['jarl']
    m = bot.TicketModal('jarl', lab)
    for f in m.fields:
        f._value = 'Whiterun'
    bot._last_ticket.clear()
    i = Interaction(guild, who)
    asyncio.run(m.on_submit(i))
    return i


def ask_as(who, guild):
    return Interaction(guild, who)


TMP = tempfile.mkdtemp(prefix='thornswood-faction-')
bot.OPEN_TICKETS = os.path.join(TMP, 'open-tickets.json')
STAFF_RULE = (
    'No GM or staff member (Loremaster, Discord Moderator, or any other staff '
    'role) may hold an in-game RP role with faction leadership, such as a Jarl '
    'or a faction lead.')

try:
    mo = Person(103, 'Mo', [Role('Moderator', rid=11)])
    pat = Person(100, 'Pat', [Role('Owner', rid=10)])
    G = Guild(1, mo, pat)
    CH = G.text_channels[0]
    ada = Person(101, 'Ada')
    # Owner's ID, as Install-Bot -UpperStaffRoles must carry. Empty is refuse.
    bot.UPPER_STAFF_IDS = {10}

    # ------------------------------------------------------- the form itself
    yes('the panel kind is faction, labelled Apply: Faction Leader',
        any(k == 'faction' and lab == 'Apply: Faction Leader' for k, lab, _ in bot.KINDS)
        and not any(k == 'company' for k, _, _ in bot.KINDS))
    yes('factions.json names the five seats, Other last is added in code',
        bot.faction_names() == [
            'Imperial Embassy', 'Thalmor Remnant', 'Dark Brotherhood',
            'The Companions', 'Free Skyrim Trading Company']
        and bot.FACTION_OTHER == 'Other')

    lab = dict((a, b) for a, b, _ in bot.KINDS)['faction']
    form = bot.TicketModal('faction', lab)
    yes('the form has a required Select of every named faction plus Other',
        form.faction_select is not None
        and [o.value for o in form.faction_select.options]
        == bot.faction_names() + [bot.FACTION_OTHER]
        and form.faction_select.required is True)
    yes('the public panel carries Djinn\'s confirmed staff-rule sentence, and both texts fit Discord\'s 2000 character message',
        STAFF_RULE == bot.STAFF_LEADERSHIP_RULE
        and STAFF_RULE in bot.PANEL_ALPHA
        and STAFF_RULE in bot.PANEL_OPEN
        and STAFF_RULE in bot._PANEL_JOBS
        and len(bot.PANEL_ALPHA) <= 2000
        and len(bot.PANEL_OPEN) <= 2000)
    yes('and an optional Other box with a short length limit',
        form.faction_other is not None
        and form.faction_other.required is False
        and form.faction_other.max_length == 200)
    yes('and the three copied questions stay optional',
        [q for q, _, _ in bot.QUESTIONS['faction']]
        == ['Who is your character?',
            'What would they do with the faction?',
            'How much time can you give it?']
        and all(long for _, _, long in bot.QUESTIONS['faction'])
        and all(not f.required for f in form.fields))
    yes('Asking for does not name a faction',
        bot.ROLE_FOR['faction'] == 'Faction Lead of the faction named below')

    yes('a named pick still lists every faction, including one that will be filled later',
        [o.value for o in form.faction_select.options]
        == bot.faction_names() + [bot.FACTION_OTHER])

    # ---------------------------------------------- a named pick, no flags
    sent, _m = send_faction(G, ada, 'The Companions',
                            answers=['A Nord', 'Lead them', 'Evenings'])
    T = CH.made[0]
    body = T.body()
    yes('a named pick opens a private, not-invitable thread',
        len(CH.made) == 1 and sent.followup.said
        and T.opened_as.get('type') == discord.ChannelType.private_thread
        and T.opened_as.get('invitable') is False)
    yes('the pick is in the escaped answers, not in the opening line',
        'The Companions' in body
        and 'The Companions' not in T.head()
        and ada.mention in T.head())
    yes('and not in Asking for',
        '**Asking for:** Faction Lead of the faction named below' in body
        and 'Asking for:** The Companions' not in body
        and 'Asking for:** Faction Lead of The Companions' not in body)
    yes('and there is no CHECK THIS ONE on a clean named pick',
        'CHECK THIS ONE' not in body)
    yes('their words are posted with mentions off',
        len(T.sent) > 1 and all(off(kw) for _, kw in T.sent[1:]))
    yes('Faction Leader pings and adds Owner, not Moderator',
        any(r.mention in T.head() and r.name == 'Owner' for r in G.roles)
        and not any(r.name == 'Moderator' and r.mention in T.head() for r in G.roles)
        and pat in T.added
        and mo not in T.added)

    # -------------------------------------- Other, and typed mentions
    ben = Person(102, 'Ben')
    sent, _m = send_faction(G, ben, bot.FACTION_OTHER,
                            other=SHOUT + ' ' + PULL,
                            answers=['A thief', 'Hide', 'Nights'])
    other_t = CH.made[1]
    other_body = other_t.body()
    other_head = other_t.head()
    yes('Other is a normal option: the ticket opens with no CHECK THIS ONE for the pick',
        'CHECK THIS ONE' not in other_body
        and 'not on the list' not in other_body
        and len(CH.made) == 2)
    yes('the typed Other text is in the answers, escaped',
        'everyone' in other_body and PULL not in other_body)
    yes('and it is not in the pinging opening line',
        SHOUT not in other_head and PULL not in other_head
        and '@everyone' not in other_head and '@here' not in other_head)
    yes('Asking for is still the static line',
        '**Asking for:** Faction Lead of the faction named below' in other_body)
    asking_line = ''
    for line in other_body.splitlines():
        if line.startswith('**Asking for:**'):
            asking_line = line
            break
    yes('the Asking for line has none of their typed Other text',
        asking_line == '**Asking for:** Faction Lead of the faction named below'
        and SHOUT not in asking_line and PULL not in asking_line
        and 'everyone' not in asking_line)

    # ------------------------------------------ submit-time recheck
    unknown = bot.TicketModal('faction', lab)
    fill_faction(unknown, 'Not A Faction', answers=['A', 'B', 'C'])
    bot._last_ticket.clear()
    asyncio.run(unknown.on_submit(Interaction(G, Person(105, 'Dee'))))
    yes('an unknown or tampered pick is flagged, and the ticket still opens',
        '**CHECK THIS ONE.** The faction they picked is not on the list.'
        in CH.made[-1].body()
        and bot.faction_pick_is_known('The Companions')
        and bot.faction_pick_is_known(bot.FACTION_OTHER)
        and not bot.faction_pick_is_known('Not A Faction')
        and not bot.faction_pick_is_known(''))

    # ----------------------------------------------- staff flag, both forms
    gm = Person(201, 'Gwen', [Role('Gamemaster')])
    lead = Person(202, 'Lee', [Role('Lead Gamemaster')])
    trial = Person(203, 'Ty', [Role('Trial Gamemaster')])
    creator = Person(204, 'Cee', [Role('Content Creator')])
    G.roles.append(Role('Gamemaster', [gm]))
    G.roles.append(Role('Lead Gamemaster', [lead]))
    G.roles.append(Role('Trial Gamemaster', [trial]))
    G.roles.append(Role('Content Creator', [creator]))

    bot._last_ticket.clear()
    send_faction(G, gm, 'The Companions', answers=['A', 'B', 'C'])
    gm_body = CH.made[-1].body()
    yes('a Gamemaster on Faction Leader is flagged, and the ticket opens',
        '**CHECK THIS ONE.** Holds a staff role (Gamemaster); staff cannot '
        'hold a Jarl seat or a faction lead.' in gm_body)
    yes('is_staff itself is unchanged: a Lead Gamemaster is still not staff',
        not bot.is_staff(lead) and not bot.is_staff(trial)
        and bot.is_staff(gm) and bot.is_staff(mo))

    send_faction(G, lead, 'The Companions', answers=['A', 'B', 'C'])
    yes('a Lead Gamemaster on Faction Leader is flagged anyway',
        'Lead Gamemaster' in CH.made[-1].body()
        and 'CHECK THIS ONE' in CH.made[-1].body())

    send_jarl(G, trial)
    yes('a Trial Gamemaster on Jarl is flagged the same way',
        'Trial Gamemaster' in CH.made[-1].body()
        and 'staff cannot hold a Jarl seat or a faction lead' in CH.made[-1].body())

    send_jarl(G, gm)
    yes('a Gamemaster on Jarl is flagged',
        'Holds a staff role (Gamemaster)' in CH.made[-1].body())

    n = len(CH.made)
    send_faction(G, creator, 'The Companions', answers=['A', 'B', 'C'])
    yes('a Content Creator is not flagged: that role is not staff',
        'CHECK THIS ONE' not in CH.made[-1].body()
        and len(CH.made) == n + 1)

    send_jarl(G, ada)
    yes('somebody with no staff role on Jarl is not flagged',
        'Holds a staff role' not in CH.made[-1].body())

    # ------------------------------------------------- routing
    ids, ignored = bot.upper_staff_ids(['Owner', '10', 'Lead Gamemaster', '88'])
    yes('UPPER_STAFF_ROLES keeps IDs and ignores names, including Owner',
        ids == {10, 88} and ignored == ['Owner', 'Lead Gamemaster'])

    fake = Person(401, 'Fay', [Role('Lead Something', rid=88)])
    G.roles.append(Role('Lead Something', [fake], rid=88))
    bot.UPPER_STAFF_IDS = set()
    pulled = bot.ticket_pull_roles('faction', G)
    yes('Owner is not pulled by name when the ID list is empty',
        pulled == []
        and all(r.name != 'Owner' for r in pulled)
        and all(r.name != 'Moderator' for r in pulled))

    n = len(CH.made)
    pushed = len(PUSHED)
    empty = Person(108, 'Ned')
    refused, _m = send_faction(G, empty, 'The Companions', answers=['A', 'B', 'C'])
    yes('an empty UPPER_STAFF_ROLES refuses the ticket, to them alone',
        len(CH.made) == n
        and len(PUSHED) == pushed
        and refused.response.said
        and refused.response.said[0][0] == bot.FACTION_REFUSED
        and refused.response.said[0][1] is True)
    yes('and says so in the log',
        any('UPPER_STAFF_ROLES is empty' in s for s in LOGGED))

    bot.UPPER_STAFF_IDS = {88}
    listed = bot.ticket_pull_roles('faction', G)
    yes('an ID in UPPER_STAFF_ROLES is pulled; Owner is not added by name',
        [r.id for r in listed] == [88]
        and all(r.name != 'Owner' for r in listed)
        and all(r.name != 'Moderator' for r in listed))
    bot.UPPER_STAFF_IDS = {10}

    n = len(CH.made)
    ivy = Person(106, 'Ivy')
    send_jarl(G, ivy)
    jarl_t = CH.made[-1]
    yes('a Jarl ticket still pings and adds general staff, including Moderator',
        len(CH.made) == n + 1
        and any(r.name == 'Moderator' and r.mention in jarl_t.head() for r in G.roles)
        and mo in jarl_t.added)

    n = len(CH.made)
    pushed = len(PUSHED)
    CH.refuse_threads = True
    blocked = Person(107, 'Ora')
    failed, _m = send_faction(G, blocked, 'The Companions', answers=['A', 'B', 'C'])
    CH.refuse_threads = False
    yes('a Faction Leader thread that will not open does not fall back',
        len(CH.made) == n
        and len(PUSHED) == pushed
        and failed.followup.said
        and failed.followup.said[0][0] == bot.FACTION_THREAD_FAILED
        and bot.FACTION_THREAD_FAILED in blocked.dms)
    yes('and the log says it stayed out of the staff log and the inbox',
        any('was not written to the staff log or the site inbox' in s
            for s in LOGGED))

    n = len(CH.made)
    CH.refuse_writes = True
    half = Person(109, 'Hal')
    failed, _m = send_faction(G, half, 'The Companions', answers=['A', 'B', 'C'])
    CH.refuse_writes = False
    left = CH.made[-1]
    yes('a half-written Faction Leader thread is deleted as the opened object',
        len(CH.made) == n + 1
        and left.deleted
        and left.id not in G.threads
        and failed.followup.said
        and failed.followup.said[0][0] == bot.FACTION_THREAD_FAILED)
    yes('and forgotten from the open-ticket file, by id, not by name',
        bot._open_tickets().get(bot._ticket_key(G, half)) is None
        and 'await opened.delete()' in inspect.getsource(bot.TicketModal.on_submit)
        and 'forget_ticket(guild, who, opened)' in inspect.getsource(
            bot.TicketModal.on_submit))

    LOGGED[:] = []
    keep_ids = bot.UPPER_STAFF_IDS
    bot.UPPER_STAFF_IDS = set()
    bot.warn_upper_staff_config()
    empty_src = inspect.getsource(bot.warn_upper_staff_config)
    yes('empty UPPER_STAFF_ROLES is a startup log warning, never a channel post',
        any('UPPER_STAFF_ROLES is empty, so Faction Leader tickets will'
            in s for s in LOGGED)
        and '.send(' not in empty_src
        and 'create_task' not in empty_src)
    LOGGED[:] = []
    bot.UPPER_STAFF_IDS = {999}
    bot.warn_upper_staff_config([G])
    yes('IDs that match no role are a log warning only',
        any('match no role' in s and 'Faction Leader tickets will be refused'
            in s for s in LOGGED))
    LOGGED[:] = []
    bot.UPPER_STAFF_IDS = {10}
    bot.warn_upper_staff_config([G])
    yes('IDs that match a role stay quiet',
        not any('match no role' in s or 'is empty' in s for s in LOGGED))
    bot.UPPER_STAFF_IDS = keep_ids

    # /close on Faction Leader threads: UPPER_STAFF_ROLES IDs, not is_staff.
    class CloseThread(discord.Thread):
        jump_url = 'https://discord.com/channels/1/2/3'
        parent = CH

        def __init__(self, name):
            self.name = name
            self.edited = []

        async def edit(self, **k):
            self.edited.append(k)

    class CloseAsk(object):
        def __init__(self, user, channel):
            self.guild = G
            self.user = user
            self.channel = channel
            self.response = Response()

    async def _no_book(*_a, **_k):
        return None

    keep_book = bot.log_channel
    bot.log_channel = _no_book
    try:
        fac = CloseThread('Apply: Faction Leader, Ada')
        jarl = CloseThread('Apply: Jarl, Ada')
        lead_role = Role('Lead Gamemaster', [lead], rid=20)
        G.roles.append(lead_role)
        bot.UPPER_STAFF_IDS = {10}
        ask = CloseAsk(lead, fac)
        asyncio.run(bot.close_here(ask))
        yes('Lead Gamemaster without an UPPER_STAFF_ROLES id cannot close a '
            'Faction Leader ticket',
            ask.response.said
            and 'Staff close these' in ask.response.said[0][0]
            and not fac.edited
            and not bot.is_staff(lead))

        ask = CloseAsk(pat, fac)
        asyncio.run(bot.close_here(ask))
        yes('Owner still closes a Faction Leader ticket as staff',
            ask.response.said
            and ask.response.said[0][0].startswith('Closed by')
            and fac.edited and fac.edited[0].get('archived'))

        uma = Person(205, 'Uma', [Role('Lead Something', rid=88)])
        bot.UPPER_STAFF_IDS = {88}
        yes('is_staff is unchanged for a role that is only in UPPER_STAFF_ROLES',
            not bot.is_staff(uma)
            and list(inspect.signature(bot.is_staff).parameters) == ['who'])
        fac2 = CloseThread('Apply: Faction Leader, Uma')
        ask = CloseAsk(uma, fac2)
        asyncio.run(bot.close_here(ask))
        yes('a role ID in UPPER_STAFF_ROLES closes a Faction Leader ticket',
            ask.response.said
            and ask.response.said[0][0].startswith('Closed by')
            and fac2.edited and fac2.edited[0].get('archived'))

        ask = CloseAsk(uma, jarl)
        asyncio.run(bot.close_here(ask))
        yes('that same person cannot close a Jarl ticket',
            ask.response.said
            and 'Staff close these' in ask.response.said[0][0]
            and not jarl.edited)
        yes('can_close_ticket is the extra gate, and is_staff is not it',
            bot.can_close_ticket(uma, fac2)
            and not bot.can_close_ticket(uma, jarl)
            and not bot.is_staff(uma)
            and 'is_staff(who)' in inspect.getsource(bot.can_close_ticket)
            and 'holds_upper_staff' in inspect.getsource(bot.can_close_ticket))
    finally:
        bot.log_channel = keep_book
        bot.UPPER_STAFF_IDS = keep_ids

    # Site inbox still gets the kind as a free string.
    yes('the site copy is kind faction, with the answers in detail',
        any(p[0] == 'faction' and 'The Companions' in p[2] for p in PUSHED))

    with open(os.path.join(os.path.dirname(HERE), '.gitignore'), encoding='utf-8') as f:
        ignored = f.read()
    yes('there is no faction-seats file in gitignore, because seat tracking is out',
        'faction-seats.json' not in ignored
        and not hasattr(bot, 'FACTION_SEATS')
        and not hasattr(bot, 'mark_faction_seat'))

finally:
    shutil.rmtree(TMP, ignore_errors=True)

print('')
print('%d passed, %d failed' % (len(PASS), len(FAIL)))
sys.exit(1 if FAIL else 0)
