"""
test-bot-overwrites.py

The bot keeps its channels without Administrator.

From the To Do List, entry 223: "The bot is invited with Administrator and
keeps it." Administrator overrides every channel overwrite, and nothing in
Build-Discord.py ever named the bot, so the only reason it could see the staff
channels, the channels behind Member and the holds, and post in the read only
ones was Administrator. Untick it and the @everyone deny shuts the bot out
along with everybody else: the trouble alerts in #staff-general and the site
watcher in the staff #news go quiet, and so does the hold panel.

Build-Discord.py is imported for real, under another name so its __main__
block never runs. Its client is swapped for a stand-in, and every guild, role
and channel here is a stand-in that records what would have been asked of
Discord. The live server is modelled as it is today: every role, category and
channel already there behind the gate set by hand on 23 and 24 September,
which is what the builder's modes now describe, with nothing naming the bot.
Plus two channels made by hand: a staff #news in the Staff category, and one
left open to everybody inside a category that is behind the gate.

The bot's permissions in a channel are worked out in Discord's documented
order: @everyone's and the member's roles, then Administrator, then the
@everyone overwrite, then the roles' overwrites together, then the member's
own overwrite last.

Read only. Never connects to anything and never writes beside the code: the
news webhook the builder saves is pointed at a temporary folder.
"""
import asyncio
import contextlib
import importlib.util
import io
import os
import shutil
import sys
import tempfile
import types

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

PASS = []
FAIL = []


def yes(what, cond):
    (PASS if cond else FAIL).append(what)
    print(('PASS  ' if cond else 'FAIL  ') + what)


try:
    import discord
except ImportError:
    print('SKIP  discord.py is not installed here, so the builder cannot be imported')
    print('')
    print('0 passed, 0 failed')
    sys.exit(0)

spec = importlib.util.spec_from_file_location(
    'build_discord', os.path.join(HERE, 'Build-Discord.py'))
B = importlib.util.module_from_spec(spec)
spec.loader.exec_module(B)

# The three bits, by their numbers on Discord's permissions page, rather than
# by discord.py's names, so a wrong name in the builder cannot agree with
# itself here.
VIEW_CHANNEL = 1 << 10
SEND_MESSAGES = 1 << 11
READ_MESSAGE_HISTORY = 1 << 16
WANT = VIEW_CHANNEL | SEND_MESSAGES | READ_MESSAGE_HISTORY

# Every mode that shuts @everyone out of one of the three. Only public does
# not, and a public channel needs nothing for the bot.
RESTRICTED = ('read', 'open', 'membersread', 'hold', 'staff', 'pathfind')
# The hold a hold mode is asked about, where one is needed.
HOLD = 'Whiterun'


def ow_for(guild, mode, roles):
    return B.overwrites(guild, mode, roles, HOLD if mode == 'hold' else None)


# ------------------------------------------------------------ stand-ins --
class Response(object):
    status = 403
    reason = 'Forbidden'


class Role(object):
    def __init__(self, name, rid, position=1, perms=0):
        self.name = name
        self.id = rid
        self.position = position
        self.permissions = discord.Permissions(perms)

    async def edit(self, **kw):
        if 'position' in kw:
            self.position = kw['position']

    def __repr__(self):
        return '<role %s>' % self.name


class Member(object):
    def __init__(self, mid, roles):
        self.id = mid
        self.roles = list(roles)
        self.top_role = self.roles[-1] if self.roles else None

    def __repr__(self):
        return '<member %d>' % self.id


class Channel(object):
    """A channel or a category. Records every write into guild.calls."""

    def __init__(self, guild, name, kind, category=None, topic=None, ow=None):
        self.guild = guild
        self.name = name
        self.kind = kind
        self.category = category
        self.topic = topic
        self.ow = dict(ow or {})
        self.channels = []
        self.refuse = False

    def overwrites_for(self, target):
        o = self.ow.get(target)
        if o is None:
            return discord.PermissionOverwrite()
        a, d = o.pair()
        return discord.PermissionOverwrite.from_pair(a, d)

    async def set_permissions(self, target, overwrite=None, reason=None):
        if self.refuse:
            raise discord.Forbidden(Response(), 'Missing Permissions')
        self.guild.calls.append(('set_permissions', self, target))
        a, d = overwrite.pair()
        self.ow[target] = discord.PermissionOverwrite.from_pair(a, d)

    async def edit(self, **kw):
        self.guild.calls.append(('edit', self, kw))

    async def webhooks(self):
        return [types.SimpleNamespace(name='Thornswood',
                                      url='https://example.invalid/not-a-hook')]

    async def create_webhook(self, **kw):
        self.guild.calls.append(('create_webhook', self, kw))
        return types.SimpleNamespace(name='Thornswood',
                                     url='https://example.invalid/not-a-hook')

    def __repr__(self):
        return '<#%s>' % self.name


class Guild(object):
    def __init__(self):
        self.id = 1
        self.name = 'Thornswood stand-in'
        self.default_role = Role('@everyone', 1, 0, B.PLAIN.value)
        self.roles = []
        self.me = None
        self.categories = []
        self.channels = []
        self.calls = []
        self.afk_channel = None
        self.features = ['COMMUNITY']
        self.rules_channel = object()
        # Set by hand to #welcome-travelers on the live server, which the
        # builder now leaves where it is.
        self.system_channel = object()

    async def _made(self, what, name, **kw):
        self.calls.append((what, name, kw))
        return Channel(self, name, what)

    async def create_role(self, name=None, **kw):
        self.calls.append(('create_role', name, kw))
        return Role(name, 9999)

    async def create_category(self, name, **kw):
        return await self._made('create_category', name, **kw)

    async def create_text_channel(self, name, **kw):
        return await self._made('create_text_channel', name, **kw)

    async def create_voice_channel(self, name, **kw):
        return await self._made('create_voice_channel', name, **kw)

    async def create_forum(self, name, **kw):
        return await self._made('create_forum', name, **kw)

    async def edit(self, **kw):
        self.calls.append(('guild.edit', self, kw))


class Client(object):
    def __init__(self, guild):
        self.guilds = [guild]

    def get_guild(self, _gid):
        return self.guilds[0]

    async def close(self):
        pass


def resolve(guild, member, ch):
    """A member's permissions in a channel, in Discord's documented order."""
    p = discord.Permissions(guild.default_role.permissions.value)
    for r in member.roles:
        p.value |= r.permissions.value
    if p.administrator:
        return discord.Permissions.all()
    if guild.default_role in ch.ow:
        a, d = ch.ow[guild.default_role].pair()
        p.handle_overwrite(a.value, d.value)
    allow = deny = 0
    for r in member.roles:
        if r in ch.ow:
            a, d = ch.ow[r].pair()
            allow |= a.value
            deny |= d.value
    p.handle_overwrite(allow, deny)
    if member in ch.ow:
        a, d = ch.ow[member].pair()
        p.handle_overwrite(a.value, d.value)
    return p


def gets_in(p):
    return p.view_channel and p.send_messages and p.read_message_history


def quiet(coro):
    """Run one coroutine with what the builder says kept out of the results."""
    with contextlib.redirect_stdout(io.StringIO()):
        return asyncio.run(coro)


# ------------------------------------------------------ the live server --
def live_server():
    """
    The server as it stands: everything built and behind the gate, before
    this change.

    The overwrites on every channel are what overwrites() makes for a guild
    with no bot in it, by the modes the builder now has. Those modes are what
    the gate set by hand on 23 and 24 September looks like, and nothing on
    the live server names the bot. The bot's own role holds the three
    permissions it needs everywhere, and not Administrator, because that is
    the state the entry wants to reach.
    """
    g = Guild()
    pos = 50
    for name, _c, _h, _p in B.ROLES:
        g.roles.append(Role(name, 100 + pos, pos))
        pos -= 1
    bot_role = Role('Thornswood Bot', 7, 60, WANT)
    g.roles.append(bot_role)
    roles = dict((r.name, r) for r in g.roles)

    bare = types.SimpleNamespace(default_role=g.default_role, me=None,
                                 roles=g.roles)

    for catname, specs in B.PLAN:
        cat = None
        # The same modes on_ready gives a category it makes.
        cmode = {'Staff': 'staff', 'Testing': 'pathfind', 'The Holds': 'hold',
                 'Applications': 'public'}.get(catname, 'open')
        if catname:
            cat = Channel(g, catname, 'category',
                          ow=B.overwrites(bare, cmode, roles))
            cat.mode = cmode
            g.categories.append(cat)
        for s in specs:
            want = s['name'].lower().replace(' ', '-') if s['kind'] != 'voice' else s['name']
            ch = Channel(g, want, s['kind'], category=cat, topic=s.get('topic'),
                         ow=B.overwrites(bare, s.get('mode', 'open'), roles,
                                         s.get('hold')))
            ch.mode = s.get('mode', 'open')
            g.channels.append(ch)
            if cat is not None:
                cat.channels.append(ch)
            if s.get('key') == 'AFK':
                g.afk_channel = ch

    # The staff #news the site watcher speaks in. bot.py says it sits in
    # Staff; the plan does not name it, so it was made by hand, shut to
    # @everyone like the category it is in.
    staff = [c for c in g.categories if c.name == 'Staff'][0]
    news = Channel(g, 'news', 'text', category=staff,
                   ow=B.overwrites(bare, 'staff', roles))
    news.mode = 'staff'
    g.channels.append(news)
    staff.channels.append(news)

    # One made by hand and left open to everybody, inside a category that is
    # behind the gate. The category's mode is not the channel's, and the bot
    # can already get into it, so the build has no business writing to it.
    around = [c for c in g.categories if c.name == 'Thornswood'][0]
    loose = Channel(g, 'open-by-hand', 'text', category=around)
    loose.mode = 'public'
    g.channels.append(loose)
    around.channels.append(loose)

    g.me = Member(424242, [bot_role])
    somebody = Member(5, [roles['Member']])
    newcomer = Member(6, [])
    return g, roles, (somebody, newcomer), news, loose


def run(g, check):
    B.CHECK = check
    B.PRUNE = False
    B.POSTS = False
    B.ROLES_ONLY = False
    B.GUILD = ''
    B.client = Client(g)
    del B.made[:]
    del B.kept[:]
    del B.failed[:]
    g.calls = []
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        asyncio.run(B.on_ready())
    return buf.getvalue()


TMP = tempfile.mkdtemp(prefix='ts-bot-overwrites-')
try:
    B.WEBHOOK_OUT = os.path.join(TMP, 'news-webhook.txt')

    # ---------------------------------------------- overwrites(), new ones --
    g, roles, (somebody, newcomer), _news, _loose = live_server()
    me = g.me

    for mode in RESTRICTED:
        out = ow_for(g, mode, roles)
        o = out.get(me)
        yes('a new channel in %s mode gives the bot its own overwrite' % mode, o is not None)
        if o is not None:
            a, d = o.pair()
            yes('  and it allows exactly View Channel, Send Messages and Read '
                'Message History (%d), denies nothing' % WANT,
                a.value == WANT and d.value == 0)

    yes('a public channel still has no overwrites at all',
        B.overwrites(g, 'public', roles) == {})

    bare = types.SimpleNamespace(default_role=g.default_role, me=None,
                                 roles=g.roles)
    for mode in RESTRICTED:
        a = ow_for(g, mode, roles)
        b = ow_for(bare, mode, roles)
        extra = set(a) - set(b)
        same = all(a[k].pair()[0].value == b[k].pair()[0].value and
                   a[k].pair()[1].value == b[k].pair()[1].value for k in b)
        yes('%s mode changes nothing for @everyone, Member, a hold or staff, '
            'and adds only the bot' % mode, same and extra == set([me]))

    for catname, specs in B.PLAN:
        for s in specs:
            mode = s.get('mode', 'open')
            if mode not in RESTRICTED:
                continue
            ch = Channel(g, s['name'], s['kind'],
                         ow=B.overwrites(g, mode, roles, s.get('hold')))
            yes('without Administrator the bot sees, posts and reads in a new #%s' % s['name'],
                gets_in(resolve(g, me, ch)))

    # ------------------------------------------- keep_bot(), one channel --
    keep = getattr(B, 'keep_bot', None)
    yes('there is a way to let the bot into a channel that already exists', keep is not None)

    if keep is not None:
        B.CHECK = False
        del B.failed[:]

        ch = Channel(g, 'staff-general', 'text', ow=B.overwrites(bare, 'staff', roles))
        g.calls = []
        quiet(keep(ch))
        yes('a staff channel with no bot overwrite is written once',
            [c[0] for c in g.calls] == ['set_permissions'] and g.calls[0][2] is me)
        yes('  and the bot sees, posts and reads there afterwards',
            gets_in(resolve(g, me, ch)))
        yes('  and somebody who is not staff still cannot see it',
            not resolve(g, somebody, ch).view_channel)

        g.calls = []
        quiet(keep(ch))
        yes('the same channel again is not written to at all', g.calls == [])

        ch = Channel(g, 'rules', 'text', ow=B.overwrites(bare, 'read', roles))
        ch.ow[me] = discord.PermissionOverwrite(view_channel=True, attach_files=True)
        g.calls = []
        quiet(keep(ch))
        after = ch.ow[me]
        yes('an overwrite on the bot set by hand keeps what it had',
            after.attach_files is True)
        yes('  and gains the two it was missing',
            after.send_messages is True and after.read_message_history is True)
        yes('  and somebody who is not staff still cannot post there',
            not resolve(g, somebody, ch).send_messages)

        ch = Channel(g, 'choose-your-hold', 'text',
                     ow=B.overwrites(bare, 'membersread', roles))
        g.calls = []
        quiet(keep(ch))
        yes('a channel behind Member is written, so the hold panel can be posted',
            [c[0] for c in g.calls] == ['set_permissions'] and gets_in(resolve(g, me, ch)))
        yes('  and somebody not yet approved still cannot see it',
            not resolve(g, newcomer, ch).view_channel)

        ch = Channel(g, 'whiterun', 'text',
                     ow=B.overwrites(bare, 'hold', roles, HOLD))
        g.calls = []
        quiet(keep(ch))
        yes('a hold channel is written, and a Member of no hold still cannot see it',
            [c[0] for c in g.calls] == ['set_permissions'] and
            not resolve(g, somebody, ch).view_channel)

        ch = Channel(g, 'general', 'text')
        g.calls = []
        quiet(keep(ch))
        yes('a channel open to everybody is never touched',
            g.calls == [] and me not in ch.ow)

        ch = Channel(g, 'say-hello', 'text', ow={g.default_role:
                     discord.PermissionOverwrite(add_reactions=False)})
        g.calls = []
        quiet(keep(ch))
        yes('nor is one whose @everyone overwrite takes away nothing the bot needs',
            g.calls == [] and me not in ch.ow)

        ch = Channel(g, 'deploys', 'text', ow=B.overwrites(bare, 'staff', roles))
        B.CHECK = True
        g.calls = []
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            asyncio.run(keep(ch))
        B.CHECK = False
        yes('-Check says it would change the channel and changes nothing',
            g.calls == [] and 'would change' in buf.getvalue() and me not in ch.ow)

        ch.refuse = True
        with contextlib.redirect_stdout(io.StringIO()):
            try:
                asyncio.run(keep(ch))
                raised = False
            except Exception:
                raised = True
        yes('a refusal from Discord is written down and the build carries on',
            not raised and any('#deploys' in f for f in B.failed))

        try:
            asyncio.run(keep(None))
            ok = True
        except Exception:
            ok = False
        yes('a channel -Check never made is passed over', ok)

    # ------------------------------------ the whole build, on the live server --
    g, roles, people, news, loose = live_server()
    me = g.me
    everything = g.categories + g.channels
    before_bot = dict((c, gets_in(resolve(g, me, c))) for c in everything)
    before_them = dict(((p, c), resolve(g, p, c).value)
                       for p in people for c in everything)
    by_name = dict((c.name, c) for c in everything if c is not news)

    yes('as the live server stands, the bot without Administrator is shut out of '
        '#staff-general (the problem, measured)',
        not before_bot[by_name['staff-general']])
    yes('  and out of the staff #news the site watcher speaks in',
        not before_bot[news])
    yes('  and out of #choose-your-hold, where it posts the hold panel',
        not before_bot[by_name['choose-your-hold']])
    yes('  and out of #news, where the release webhook and -Posts write',
        not before_bot[by_name['news']])
    yes('  but not out of #say-hello, which is open to everybody',
        before_bot[by_name['say-hello']])

    said = run(g, True)
    yes('-Check writes nothing to any channel',
        not [c for c in g.calls if c[0] == 'set_permissions'])
    yes('  and says it would let the bot into #staff-general',
        '#staff-general lets the bot in' in said)
    yes('  and the run did not stop part way', 'stopped:' not in said)

    said = run(g, False)
    writes = [c for c in g.calls if c[0] == 'set_permissions']
    wrote = [c[1] for c in writes]
    yes('the build did not stop part way', 'stopped:' not in said)
    yes('nothing was made, because everything was already there',
        not [c for c in g.calls if c[0].startswith('create_')])
    yes('every write was the bot\'s own overwrite', all(c[2] is me for c in writes))

    # Exactly the channels and categories the bot could not get into before,
    # measured off the server rather than off the plan's modes.
    shut = [c for c in everything if not before_bot[c]]
    yes('every channel and category that shut the bot out was written once '
        '(%d of %d)' % (len(set(wrote) & set(shut)), len(shut)),
        sorted(wrote, key=id) == sorted(shut, key=id))
    yes('  which is every one of them but the public ones (%d of %d)'
        % (len(shut), len(everything)),
        sorted(shut, key=id) == sorted(
            [c for c in everything if getattr(c, 'mode', None) in RESTRICTED],
            key=id))
    yes('the staff #news made by hand is one of them', news in wrote)
    yes('no channel open to everybody was touched: not #say-hello, not the '
        'Applications category, not the one made by hand behind the gate',
        not [c for c in wrote if before_bot[c]] and by_name['say-hello'] not in wrote
        and by_name['Applications'] not in wrote and loose not in wrote)

    for c in everything:
        if not gets_in(resolve(g, me, c)):
            yes('without Administrator the bot sees, posts and reads in #' + c.name, False)
    yes('without Administrator the bot sees, posts and reads in every channel and '
        'category (%d)' % len(everything),
        all(gets_in(resolve(g, me, c)) for c in everything))
    yes('nobody else, a Member or somebody not yet approved, can do a single '
        'thing they could not do before',
        all(resolve(g, p, c).value == before_them[(p, c)]
            for p in people for c in everything))
    yes('nothing failed', not B.failed)

    said = run(g, False)
    yes('a second run writes nothing, so it asks nothing of Discord once '
        'Administrator is gone',
        not [c for c in g.calls if c[0] == 'set_permissions'])

finally:
    shutil.rmtree(TMP, ignore_errors=True)

print('')
print('%d passed, %d failed' % (len(PASS), len(FAIL)))
sys.exit(1 if FAIL else 0)
