"""
test-faction-leader.py

Apply: Faction Leader replaced Apply: Trading Company.

The real bot module is imported and the real TicketModal.on_submit and
faction_seat_cmd are run. Only what touches Discord is replaced: the guild,
its channels, threads and roles, the interaction, the push to the site, and
the seat file, which is pointed at a temporary folder so this cannot touch
the one beside the code.

Holds:

  the faction pick and Other on the form
  a submit-time recheck of a seat filled after the form opened
  the staff flag on both Faction Leader and Jarl
  typed Other text out of the pinging opening line and Asking for
  /faction-seat is staff only, and records who and when

Read only. Never connects to anything.
"""
import asyncio
import json
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
os.environ.setdefault('DISCORD_TOKEN', 'not-a-real-token')
for _k in ('TICKET_CHANNEL', 'TICKET_LOG', 'STAFF_ROLES', 'TICKET_COOLDOWN'):
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

    def __str__(self):
        return self.name

    async def send(self, *a, **k):
        pass


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

    async def add_user(self, m):
        self.added.append(m)


class Channel(Posts):
    def __init__(self, name, guild):
        Posts.__init__(self)
        self.name = name
        self.guild = guild
        self.made = []

    def permissions_for(self, who):
        return Perms(who is self.guild.me)

    async def create_thread(self, name=None, **k):
        await asyncio.sleep(0)
        t = Thread(9000 + len(self.made), name)
        self.made.append(t)
        self.guild.threads[t.id] = t
        return t


class Guild(object):
    def __init__(self, gid, staff):
        self.id = gid
        self.name = 'Thornswood'
        self.me = Person(1, 'Thornswood')
        self.me.bot = True
        self.threads = {}
        self.roles = [Role('Moderator', [staff])]
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


def seats():
    try:
        with open(bot.FACTION_SEATS, encoding='utf-8') as f:
            return json.load(f)
    except Exception:
        return None


def write_seats(d):
    bot._seats_write(d)


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
bot.FACTION_SEATS = os.path.join(TMP, 'faction-seats.json')

try:
    mo = Person(103, 'Mo', [Role('Moderator')])
    G = Guild(1, mo)
    CH = G.text_channels[0]
    ada = Person(101, 'Ada')

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
    yes('the form has a required Select of the open seats plus Other',
        form.faction_select is not None
        and [o.value for o in form.faction_select.options]
        == bot.faction_names() + [bot.FACTION_OTHER]
        and form.faction_select.required is True)
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

    # ------------------------------------------------- a filled seat drops out
    write_seats({'Imperial Embassy': {
        'filled': True, 'by': 'Mo', 'by_id': 103, 'at': '2026-10-12T00:00:00Z'}})
    closed = bot.TicketModal('faction', lab)
    yes('a filled seat is left out of the Select',
        [o.value for o in closed.faction_select.options]
        == [n for n in bot.faction_names() if n != 'Imperial Embassy']
        + [bot.FACTION_OTHER])
    os.remove(bot.FACTION_SEATS)

    # ---------------------------------------------- an open pick, no flags
    sent, _m = send_faction(G, ada, 'The Companions',
                            answers=['A Nord', 'Lead them', 'Evenings'])
    T = CH.made[0]
    body = T.body()
    yes('an open named seat opens a ticket',
        len(CH.made) == 1 and sent.followup.said)
    yes('the pick is in the escaped answers, not in the opening line',
        'The Companions' in body
        and 'The Companions' not in T.head()
        and ada.mention in T.head())
    yes('and not in Asking for',
        '**Asking for:** Faction Lead of the faction named below' in body
        and 'Asking for:** The Companions' not in body
        and 'Asking for:** Faction Lead of The Companions' not in body)
    yes('submitting did not mark the seat filled',
        seats() is None)
    yes('and there is no CHECK THIS ONE on a clean open pick',
        'CHECK THIS ONE' not in body)
    yes('their words are posted with mentions off',
        len(T.sent) > 1 and all(off(kw) for _, kw in T.sent[1:]))

    # -------------------------------------- Other, and typed mentions
    ben = Person(102, 'Ben')
    sent, _m = send_faction(G, ben, bot.FACTION_OTHER,
                            other=SHOUT + ' ' + PULL,
                            answers=['A thief', 'Hide', 'Nights'])
    other_t = CH.made[1]
    other_body = other_t.body()
    other_head = other_t.head()
    yes('Other is flagged and the ticket still opens',
        '**CHECK THIS ONE.** The faction they picked is not an open named seat.'
        in other_body
        and len(CH.made) == 2)
    yes('the typed Other text is in the answers, escaped',
        'everyone' in other_body and PULL not in other_body)
    yes('and it is not in the pinging opening line',
        SHOUT not in other_head and PULL not in other_head
        and '@everyone' not in other_head and '@here' not in other_head)
    yes('Asking for is still the static line',
        '**Asking for:** Faction Lead of the faction named below' in other_body)
    yes('Other did not mark a seat filled',
        seats() is None)

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
    write_seats({})
    stale = bot.TicketModal('faction', lab)
    fill_faction(stale, 'Dark Brotherhood', answers=['A', 'B', 'C'])
    write_seats({'Dark Brotherhood': {
        'filled': True, 'by': 'Mo', 'by_id': 103, 'at': '2026-10-12T01:00:00Z'}})
    before = seats()
    i = Interaction(G, Person(104, 'Cal'))
    bot._last_ticket.clear()
    asyncio.run(stale.on_submit(i))
    flagged = CH.made[2].body()
    yes('a seat filled after the form opened is flagged, and the ticket opens',
        '**CHECK THIS ONE.** The faction they picked is not an open named seat.'
        in flagged
        and len(CH.made) == 3)
    yes('and submitting still did not write the seat file',
        seats() == before
        and seats()['Dark Brotherhood']['by'] == 'Mo')

    unknown = bot.TicketModal('faction', lab)
    fill_faction(unknown, 'Not A Faction', answers=['A', 'B', 'C'])
    bot._last_ticket.clear()
    asyncio.run(unknown.on_submit(Interaction(G, Person(105, 'Dee'))))
    yes('an unknown pick is flagged the same way',
        '**CHECK THIS ONE.** The faction they picked is not an open named seat.'
        in CH.made[3].body())

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

    # ------------------------------------------------- /faction-seat
    if os.path.exists(bot.FACTION_SEATS):
        os.remove(bot.FACTION_SEATS)

    outsider = Person(301, 'Pat', [Role('Playtester')])
    out_ask = ask_as(outsider, G)
    asyncio.run(bot.mark_faction_seat(out_ask, 'fill', 'Imperial Embassy'))
    yes('/faction-seat refuses someone who is not staff, to them alone',
        len(out_ask.response.said) == 1
        and out_ask.response.said[0][1] is True
        and 'Staff mark these' in out_ask.response.said[0][0])
    yes('and writes nothing',
        seats() is None)

    for who in (Person(302, 'Lee', [Role('Lead Gamemaster')]),
                Person(303, 'Ty', [Role('Trial Gamemaster')])):
        a = ask_as(who, G)
        asyncio.run(bot.mark_faction_seat(a, 'fill', 'Imperial Embassy'))
        yes('/faction-seat refuses %s, the same is_staff as /close'
            % who.roles[0].name,
            a.response.said and 'Staff mark these' in a.response.said[0][0]
            and seats() is None)

    staff_ask = ask_as(mo, G)
    asyncio.run(bot.mark_faction_seat(staff_ask, 'fill', 'Imperial Embassy'))
    rec = seats()
    yes('staff can fill a seat, and the file records who and when',
        staff_ask.response.said
        and 'Filled the lead seat of Imperial Embassy.' in staff_ask.response.said[0][0]
        and rec and rec['Imperial Embassy']['filled'] is True
        and rec['Imperial Embassy']['by'] == 'Mo'
        and rec['Imperial Embassy']['by_id'] == 103
        and rec['Imperial Embassy']['at'])

    free_ask = ask_as(mo, G)
    asyncio.run(bot.mark_faction_seat(free_ask, 'free', 'Imperial Embassy'))
    rec = seats()
    yes('staff can free it again',
        rec['Imperial Embassy']['filled'] is False
        and rec['Imperial Embassy']['by_id'] == 103
        and 'Freed the lead seat of Imperial Embassy.' in free_ask.response.said[0][0])

    yes('_seats_write is the same atomic temp file then replace as joins',
        'JOINS + \'.tmp\'' in open(os.path.join(HERE, 'bot.py'), encoding='utf-8').read()
        and 'FACTION_SEATS + \'.tmp\'' in open(os.path.join(HERE, 'bot.py'), encoding='utf-8').read()
        and 'os.replace(tmp, FACTION_SEATS)' in open(os.path.join(HERE, 'bot.py'), encoding='utf-8').read())

    # Site inbox still gets the kind as a free string.
    yes('the site copy is kind faction, with the answers in detail',
        any(p[0] == 'faction' and 'The Companions' in p[2] for p in PUSHED))

    with open(os.path.join(os.path.dirname(HERE), '.gitignore'), encoding='utf-8') as f:
        ignored = f.read()
    yes('the seat file and its tmp stay out of git',
        'bot/faction-seats.json' in ignored
        and 'bot/faction-seats.json.tmp' in ignored)

finally:
    shutil.rmtree(TMP, ignore_errors=True)

print('')
print('%d passed, %d failed' % (len(PASS), len(FAIL)))
sys.exit(1 if FAIL else 0)
